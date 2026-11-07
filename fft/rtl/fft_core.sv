// =============================================================================
// Module: fft_core
// Author: Enrique Fayos Gimeno
// Date: 2026-10-05
//
// Description:
//   Byte-oriented core for a 32-point radix-2 DIT FFT. Assembles four bytes
//   into each complex sample, loads samples in bit-reversed order, and reuses
//   one combinational butterfly for five stages of in-place computation.
//   Results remain in memory in natural bin order and can be read through
//   Port A after computation has finished.
//
// Interface:
//   input_data       - Incoming byte: real high, real low, imag high, imag low.
//   input_data_valid - High when input_data contains a valid byte.
//   fft_done         - One-clock pulse after writing the final FFT results.
//   result_address   - Result bin address, 0..31, used when results_ready is high.
//   result_data      - Synchronous result word: {real[15:0], imag[15:0]}.
//                      Set result_address before a rising edge and capture the
//                      updated result_data on the following rising edge.
//   results_ready    - High after fft_done until reset. Readout owns Port A.
//                      Input bytes are accepted only during the load phase.
//
// Reset:
//   Active-low asynchronous reset for the assembler and controller.
//   Memory is not reset. One block is processed per reset.
// =============================================================================

module fft_core (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        input_data_valid,
    input  logic [7:0]  input_data,

    output logic        fft_done,

    input  logic [4:0]  result_address,
    output logic [31:0] result_data,
    output logic        results_ready
);

// ASSEMBLED SAMPLE
logic [31:0] assembled_sample;
logic        assembled_sample_valid;

// LOAD CONTROL
logic load_active;
// Indicates completion of the 32-sample load phase.
// Currently kept internal and reserved for possible future use.
logic load_done;

// MEMORY CONTROL
logic [4:0] address_a;
logic       write_enable_a;
logic [4:0] address_b;
logic       write_enable_b;
logic [4:0] memory_address_a;

// MEMORY DATA
logic [31:0] memory_data_in_a;
logic [31:0] memory_data_out_a;
logic [31:0] memory_data_in_b;
logic [31:0] memory_data_out_b;

// TWIDDLE SIGNALS
logic        [3:0]  twiddle_addr;
logic signed [15:0] w_real;
logic signed [15:0] w_imag;

// BUTTERFLY COMPONENTS
logic signed [15:0] a_real;
logic signed [15:0] a_imag;
logic signed [15:0] b_real;
logic signed [15:0] b_imag;
logic signed [15:0] x_real;
logic signed [15:0] x_imag;
logic signed [15:0] y_real;
logic signed [15:0] y_imag;

// SAMPLE ASSEMBLY
// Four valid bytes form {real[15:0], imag[15:0]} for a controller LOAD write.
sample_assembler sample_assembler_inst (
    .clk(clk),
    .rst_n(rst_n),

    .input_data_valid(input_data_valid && load_active),
    .input_data(input_data),

    .output_data_valid(assembled_sample_valid),
    .output_data(assembled_sample)
);

// FFT CONTROL
fft_controller fft_controller_inst (
    .clk(clk),
    .rst_n(rst_n),
    .sample_valid(assembled_sample_valid),

    .address_a(address_a),
    .write_enable_a(write_enable_a),
    .address_b(address_b),
    .write_enable_b(write_enable_b),

    .twiddle_addr(twiddle_addr),
    .load_active(load_active),
    .load_done(load_done),
    .fft_done(fft_done)
);

// FFT MEMORY
fft_memory fft_memory_inst (
    .clk(clk),

    .address_a(memory_address_a),
    .write_enable_a(write_enable_a),
    .data_in_a(memory_data_in_a),
    .data_out_a(memory_data_out_a),

    .address_b(address_b),
    .write_enable_b(write_enable_b),
    .data_in_b(memory_data_in_b),
    .data_out_b(memory_data_out_b)
);

// TWIDDLE ROM
fft_twiddle_rom fft_twiddle_rom_inst (
    .address(twiddle_addr),
    .w_real(w_real),
    .w_imag(w_imag)
);

// RAM-TO-BUTTERFLY UNPACKING
// Same-width signed signals preserve each component's two's-complement bits.
// Registered RAM outputs from FFT_READ feed the butterfly during FFT_WRITE.
always_comb begin
    a_real = memory_data_out_a[31:16];
    a_imag = memory_data_out_a[15:0];
    b_real = memory_data_out_b[31:16];
    b_imag = memory_data_out_b[15:0];
end

// COMPLEX BUTTERFLY
complex_butterfly complex_butterfly_inst (
    .a_real(a_real),
    .a_imag(a_imag),
    .b_real(b_real),
    .b_imag(b_imag),
    .w_real(w_real),
    .w_imag(w_imag),

    .x_real(x_real),
    .x_imag(x_imag),
    .y_real(y_real),
    .y_imag(y_imag)
);

// MEMORY WRITE DATA
// Port A selects assembled samples during LOAD and packed butterfly X otherwise.
// Port B packs butterfly Y; the controller enables its writes only in FFT_WRITE.
always_comb begin
    memory_data_in_a = load_active ? assembled_sample : {x_real, x_imag};
    memory_data_in_b = {y_real, y_imag};
end

// RESULT READOUT
// Latch completion before transferring Port A to the external result reader.
// The controller remains in DONE with both write enables low until reset.
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        results_ready <= 1'b0;
    end else if (fft_done) begin
        results_ready <= 1'b1;
    end
end

always_comb begin
    memory_address_a = results_ready ? result_address : address_a;
    result_data = memory_data_out_a;
end

endmodule
