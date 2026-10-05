// =============================================================================
// Module: fft_controller
// Author: Enrique Fayos Gimeno
// Date: 2026-09-23
//
// Description:
//   Controls loading and in-place computation of a 32-point radix-2 DIT FFT.
//   Loads samples in bit-reversed order, then performs five stages of sixteen
//   butterflies using one external combinational butterfly. Results remain in
//   memory in natural bin order. Each butterfly uses one read and one write cycle.
//   Generates control signals only; all sample and result data bypass this module.
//   The external datapath selects the Port A write source using load_active.
//
// Interface:
//   sample_valid   - Indicates a complete input sample for a LOAD write.
//   address_a      - FFT memory Port A 5-bit word address.
//   write_enable_a - FFT memory Port A write enable, active-high.
//   address_b      - FFT memory Port B 5-bit word address.
//   write_enable_b - FFT memory Port B write enable, active-high.
//   twiddle_addr   - W32 index for the external combinational twiddle ROM.
//   load_active    - High during LOAD when reset is released; selects assembler
//                    data for Port A. Low selects butterfly X in the external mux.
//   load_done      - One-clock pulse after writing the 32nd input sample.
//   fft_done       - One-clock pulse after writing the final butterfly results.
//
// Reset:
//   Active-low asynchronous reset. DONE holds until reset; no restart protocol.
// =============================================================================

module fft_controller (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        sample_valid,

    output logic [4:0]  address_a,
    output logic        write_enable_a,

    output logic [4:0]  address_b,
    output logic        write_enable_b,

    output logic [3:0]  twiddle_addr,
    output logic        load_active, //mux
    output logic        load_done, //debug
    output logic        fft_done
);

// STATE DEFINITIONS
typedef enum logic [1:0] {
    LOAD,
    FFT_READ,
    FFT_WRITE,
    DONE
} state_t;

// INTERNAL REGISTERS
state_t     state;
logic [4:0] sample_count;
logic [2:0] stage;
logic [3:0] butterfly_count;

// BIT-REVERSED LOAD ADDRESS
logic [4:0] bit_reverse_addr;

always_comb begin
    bit_reverse_addr = {sample_count[0], sample_count[1], sample_count[2],
                        sample_count[3], sample_count[4]};
end

// FFT ADDRESS AND TWIDDLE GENERATION
// Insert the butterfly-side selection bit at the current stage position:
// zero selects A and one selects B. The remaining bits come from butterfly_count.
// Low stage bits select the position within a group; upper bits select the group.
// The W32 index is that position shifted left by (4 - stage), using wiring only.
logic [4:0] fft_address_a;
logic [4:0] fft_address_b;

always_comb begin
    fft_address_a = 5'd0;
    fft_address_b = 5'd1;
    twiddle_addr  = 4'd0;

    case (stage)
        3'd0: begin
            fft_address_a = {butterfly_count[3:0], 1'b0};
            fft_address_b = {butterfly_count[3:0], 1'b1};
            twiddle_addr  = 4'd0;
        end
        3'd1: begin
            fft_address_a = {butterfly_count[3:1], 1'b0, butterfly_count[0]};
            fft_address_b = {butterfly_count[3:1], 1'b1, butterfly_count[0]};
            twiddle_addr  = {butterfly_count[0], 3'b000};
        end
        3'd2: begin
            fft_address_a = {butterfly_count[3:2], 1'b0, butterfly_count[1:0]};
            fft_address_b = {butterfly_count[3:2], 1'b1, butterfly_count[1:0]};
            twiddle_addr  = {butterfly_count[1:0], 2'b00};
        end
        3'd3: begin
            fft_address_a = {butterfly_count[3], 1'b0, butterfly_count[2:0]};
            fft_address_b = {butterfly_count[3], 1'b1, butterfly_count[2:0]};
            twiddle_addr  = {butterfly_count[2:0], 1'b0};
        end
        3'd4: begin
            fft_address_a = {1'b0, butterfly_count[3:0]};
            fft_address_b = {1'b1, butterfly_count[3:0]};
            twiddle_addr  = butterfly_count[3:0];
        end
        default: begin
            fft_address_a = 5'd0;
            fft_address_b = 5'd1;
            twiddle_addr  = 4'd0;
        end
    endcase
end

// MEMORY CONTROL
// The external Port A mux selects assembler data during LOAD and butterfly X
// otherwise. Port B can receive butterfly Y directly; it writes only in FFT_WRITE.
// Memory read outputs connect directly to the external combinational butterfly.
always_comb begin
    address_a      = 5'd0;
    write_enable_a = 1'b0;
    address_b      = 5'd1;
    write_enable_b = 1'b0;
    load_active    = 1'b0;

    if (rst_n) begin
        case (state)
            LOAD: begin
                address_a      = bit_reverse_addr;
                write_enable_a = sample_valid;
                load_active    = 1'b1;
                // Port B always reads, so keep it distinct from the load address.
                address_b      = bit_reverse_addr ^ 5'b00001;
            end

            FFT_READ: begin
                address_a = fft_address_a;
                address_b = fft_address_b;
            end

            FFT_WRITE: begin
                address_a      = fft_address_a;
                write_enable_a = 1'b1;
                address_b      = fft_address_b;
                write_enable_b = 1'b1;
            end

            DONE: begin
                // Both write enables remain low, preserving the completed FFT.
            end

            default: begin
                write_enable_a = 1'b0;
                write_enable_b = 1'b0;
            end
        endcase
    end
end

// STATE AND COUNTER CONTROL
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state           <= LOAD;
        sample_count    <= 5'd0;
        stage           <= 3'd0;
        butterfly_count <= 4'd0;
        load_done       <= 1'b0;
        fft_done        <= 1'b0;
    end else begin
        load_done <= 1'b0;
        fft_done  <= 1'b0;

        case (state)
            LOAD: begin
                if (sample_valid) begin
                    if (sample_count == 5'd31) begin
                        stage           <= 3'd0;
                        butterfly_count <= 4'd0;
                        load_done       <= 1'b1;
                        state           <= FFT_READ;
                    end else begin
                        sample_count <= sample_count + 1'b1;
                    end
                end
            end

            FFT_READ: begin
                // This edge registers both operands in fft_memory. They feed the
                // butterfly during FFT_WRITE and are written on the next edge.
                state <= FFT_WRITE;
            end

            FFT_WRITE: begin
                // This edge writes X and Y before advancing the address counters.
                if (butterfly_count == 4'd15) begin
                    if (stage == 3'd4) begin
                        fft_done <= 1'b1;
                        state    <= DONE;
                    end else begin
                        butterfly_count <= 4'd0;
                        stage           <= stage + 1'b1;
                        state           <= FFT_READ;
                    end
                end else begin
                    butterfly_count <= butterfly_count + 1'b1;
                    state           <= FFT_READ;
                end
            end

            DONE: begin
                // Hold the completed block until reset. Further samples are ignored.
            end

            default: begin
                state           <= LOAD;
                sample_count    <= 5'd0;
                stage           <= 3'd0;
                butterfly_count <= 4'd0;
            end
        endcase
    end
end

// synthesis translate_off

// ASSERTIONS
// During reset, the controller should be inactive
assert_reset_idle:
assert property (
    @(posedge clk)
    !rst_n |-> (state == LOAD && sample_count == 5'd0 && stage == 3'd0 &&
                butterfly_count == 4'd0 && write_enable_a == 1'b0 &&
                write_enable_b == 1'b0 && load_active == 1'b0 &&
                load_done == 1'b0 && fft_done == 1'b0))
    else $error("[%0t] FFT controller is not idle during reset", $time);

// The external input mux should select assembler data throughout LOAD only
assert_load_source_selection:
assert property (
    @(posedge clk)
    disable iff (!rst_n)
    load_active == (state == LOAD))
    else $error("[%0t] FFT controller generated an incorrect load selector", $time);

// Loading should write only valid samples through Port A
assert_load_control:
assert property (
    @(posedge clk)
    disable iff (!rst_n)
    state == LOAD |-> (write_enable_a == sample_valid &&
                       write_enable_b == 1'b0 && address_a == bit_reverse_addr))
    else $error("[%0t] FFT controller generated incorrect load control", $time);

// Both ports continuously read, so any write requires distinct port addresses
assert_distinct_write_addresses:
assert property (
    @(posedge clk)
    disable iff (!rst_n)
    (write_enable_a || write_enable_b) |-> address_a != address_b)
    else $error("[%0t] FFT controller generated a memory address collision", $time);

// Computation should use only the five supported stages
assert_stage_range:
assert property (
    @(posedge clk)
    disable iff (!rst_n)
    (state == FFT_READ || state == FFT_WRITE) |-> stage <= 3'd4)
    else $error("[%0t] FFT controller stage is out of range", $time);

// A read should not write either memory port
assert_read_writes_disabled:
assert property (
    @(posedge clk)
    disable iff (!rst_n)
    state == FFT_READ |-> (write_enable_a == 1'b0 && write_enable_b == 1'b0))
    else $error("[%0t] FFT controller wrote memory during FFT_READ", $time);

// Every read should be followed by a write with unchanged addressing and twiddle
assert_read_write_sequence:
assert property (
    @(posedge clk)
    disable iff (!rst_n)
    state == FFT_READ |=> (state == FFT_WRITE && $stable(stage) &&
                          $stable(butterfly_count) && $stable(address_a) &&
                          $stable(address_b) && $stable(twiddle_addr)))
    else $error("[%0t] FFT controller changed the read/write butterfly selection", $time);

// Each FFT write should follow a read and enable both memory ports
assert_fft_write_control:
assert property (
    @(posedge clk)
    disable iff (!rst_n)
    state == FFT_WRITE |-> ($past(state == FFT_READ) &&
                           write_enable_a == 1'b1 && write_enable_b == 1'b1))
    else $error("[%0t] FFT controller generated incorrect FFT_WRITE control", $time);

// The last load write should start computation immediately
assert_load_starts_fft:
assert property (
    @(posedge clk)
    disable iff (!rst_n)
    (state == LOAD && sample_valid && sample_count == 5'd31) |=>
        (state == FFT_READ && stage == 3'd0 && butterfly_count == 4'd0 && load_done))
    else $error("[%0t] FFT controller did not start after the last sample", $time);

// The final butterfly write should complete the FFT
assert_final_write_completes_fft:
assert property (
    @(posedge clk)
    disable iff (!rst_n)
    (state == FFT_WRITE && stage == 3'd4 && butterfly_count == 4'd15) |=>
        (state == DONE && fft_done))
    else $error("[%0t] FFT controller did not finish after the final write", $time);

// fft_done should only follow the final butterfly write
assert_fft_done_after_final_write:
assert property (
    @(posedge clk)
    disable iff (!rst_n)
    fft_done |-> $past(state == FFT_WRITE && stage == 3'd4 &&
                       butterfly_count == 4'd15))
    else $error("[%0t] FFT controller asserted fft_done at the wrong time", $time);

// Completion indications should only last one clock cycle
assert_completion_pulses:
assert property (
    @(posedge clk)
    disable iff (!rst_n)
    (load_done || fft_done) |=> (!load_done && !fft_done))
    else $error("[%0t] FFT controller completion pulse lasted more than one clock", $time);

// DONE should preserve memory and remain active until reset
assert_done_writes_disabled:
assert property (
    @(posedge clk)
    disable iff (!rst_n)
    state == DONE |-> (write_enable_a == 1'b0 && write_enable_b == 1'b0))
    else $error("[%0t] FFT controller wrote memory after completion", $time);

assert_done_holds:
assert property (
    @(posedge clk)
    disable iff (!rst_n)
    state == DONE |=> state == DONE)
    else $error("[%0t] FFT controller left DONE without reset", $time);

// synthesis translate_on

endmodule
