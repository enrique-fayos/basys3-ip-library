// =============================================================================
// Module: fft_top
// Author: Enrique Fayos Gimeno
// Date: 2026-11-07
//
// Description:
//   Board-facing UART interface for the 32-point complex FFT.
//   Receives one block of 128 bytes, computes the FFT, and transmits all
//   32 result bins in natural order as a block of 128 bytes.
//
// Protocol:
//   Each complex value contains signed 16-bit real and imaginary components.
//   Input and output byte order: real high, real low, imag high, imag low.
//   No header, checksum, or flow control is used. Send exactly one block
//   after reset and wait for the complete response. Further input bytes are
//   ignored after loading. Reset is required before sending another block
//   or recovering from an incomplete or incorrectly aligned input block.
//   Results use the core's per-stage scaling, approximately FFT(input) / 32.
//
// Interface:
//   clk     - System clock.
//   rst_n   - Active-low asynchronous reset.
//   uart_rx - UART serial input from the host, idle-high.
//   uart_tx - UART serial output to the host, idle-high.
//
// Default configuration:
//   Clock:     100 MHz
//   Baud rate: 115200, 8N1, LSB first within each UART byte.
// =============================================================================

module fft_top #(
    parameter int unsigned CLK_FREQ  = 100_000_000,
    parameter int unsigned BAUD_RATE = 115_200
)(
    input  logic clk,
    input  logic rst_n,

    input  logic uart_rx,
    output logic uart_tx
);

// STATE DEFINITIONS
typedef enum logic [2:0] {
    WAIT_FFT,
    READ_RESULT,
    LATCH_RESULT,
    SEND_BYTE,
    WAIT_TX_BUSY,
    WAIT_TX_DONE,
    DONE
} state_t;

state_t state;

// UART RX SIGNALS
logic [7:0] rx_data;
logic       rx_valid;

// UART TX SIGNALS
logic [7:0] tx_data;
logic       tx_start;
logic       tx_busy;

// FFT SIGNALS
logic        fft_done;
logic        results_ready;
logic [4:0]  result_address;
logic [31:0] result_data;

// RESULT SERIALIZER
logic [31:0] result_word;
logic [1:0]  byte_count;

// UART
uart #(
    .CLK_FREQ(CLK_FREQ),
    .BAUD_RATE(BAUD_RATE)
) uart_inst (
    .clk(clk),
    .rst_n(rst_n),

    .uart_rx(uart_rx),
    .uart_tx(uart_tx),

    .rx_data(rx_data),
    .rx_valid(rx_valid),

    .tx_data(tx_data),
    .tx_start(tx_start),
    .tx_busy(tx_busy)
);

// FFT CORE
// The core accepts RX bytes during loading and ignores them afterward.
fft_core fft_core_inst (
    .clk(clk),
    .rst_n(rst_n),

    .input_data_valid(rx_valid),
    .input_data(rx_data),

    .fft_done(fft_done),
    .result_address(result_address),
    .result_data(result_data),
    .results_ready(results_ready)
);

// RESULT READOUT AND UART TRANSMISSION
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state          <= WAIT_FFT;
        result_address <= 5'd0;
        result_word    <= 32'd0;
        byte_count     <= 2'd0;
        tx_data        <= 8'd0;
        tx_start       <= 1'b0;
    end else begin
        tx_start <= 1'b0;

        case (state)
            WAIT_FFT: begin
                if (results_ready) begin
                    state <= READ_RESULT;
                end
            end

            READ_RESULT: begin
                // This edge reads result_address into the RAM output register.
                state <= LATCH_RESULT;
            end

            LATCH_RESULT: begin
                // Capture the synchronous RAM output one edge after its read.
                result_word <= result_data;
                byte_count  <= 2'd0;
                state       <= SEND_BYTE;
            end

            SEND_BYTE: begin
                if (!tx_busy) begin
                    case (byte_count)
                        2'd0: tx_data <= result_word[31:24];
                        2'd1: tx_data <= result_word[23:16];
                        2'd2: tx_data <= result_word[15:8];
                        2'd3: tx_data <= result_word[7:0];
                    endcase
                    tx_start <= 1'b1;
                    state    <= WAIT_TX_BUSY;
                end
            end

            WAIT_TX_BUSY: begin
                // TX accepts the registered start pulse on the next edge.
                // Wait for busy to rise before looking for completion.
                if (tx_busy) begin
                    state <= WAIT_TX_DONE;
                end
            end

            WAIT_TX_DONE: begin
                if (!tx_busy) begin
                    if (byte_count == 2'd3) begin
                        if (result_address == 5'd31) begin
                            state <= DONE;
                        end else begin
                            result_address <= result_address + 1'b1;
                            state          <= READ_RESULT;
                        end
                    end else begin
                        byte_count <= byte_count + 1'b1;
                        state      <= SEND_BYTE;
                    end
                end
            end

            DONE: begin
                // Hold until reset after the final byte has left the UART.
            end

            default: begin
                state <= DONE;
            end
        endcase
    end
end

// synthesis translate_off

// ASSERTIONS
// A transmit request must target an idle UART with completed FFT results.
assert_tx_request_valid:
assert property (
    @(posedge clk)
    disable iff (!rst_n)
    tx_start |-> (!tx_busy && results_ready))
    else $error("[%0t] FFT top generated an invalid UART transmit request", $time);

// Each transmit request should last exactly one clock cycle.
assert_tx_start_pulse:
assert property (
    @(posedge clk)
    disable iff (!rst_n)
    tx_start |=> !tx_start)
    else $error("[%0t] FFT top tx_start lasted more than one clock cycle", $time);

// The completed transaction must remain inactive until reset.
assert_done_holds:
assert property (
    @(posedge clk)
    disable iff (!rst_n)
    state == DONE |=> (state == DONE && !tx_start))
    else $error("[%0t] FFT top restarted without reset", $time);

// synthesis translate_on

endmodule
