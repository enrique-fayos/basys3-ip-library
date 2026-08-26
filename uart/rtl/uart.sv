// =============================================================================
// Module: uart
// Author: Enrique Fayos Gimeno
// Date: 2026-08-26
//
// Description:
//   UART wrapper combining the uart_rx and uart_tx modules.
//   Provides a byte-oriented interface for internal FPGA logic.
//
// Interface:
//   uart_rx  - UART serial input, idle-high.
//   uart_tx  - UART serial output, idle-high.
//   rx_data  - Last successfully received 8-bit data.
//   rx_valid - One-clock pulse when a new byte has been received.
//   tx_data  - 8-bit data to transmit.
//   tx_start - One-clock pulse requesting a new transmission.
//   tx_busy  - High while a transmission is in progress.
//
// Reset:
//   Active-low asynchronous reset.
//
// Default configuration:
//   Clock:     100 MHz
//   Baud rate: 115200
// =============================================================================

module uart #(
    parameter int unsigned CLK_FREQ = 100_000_000,
    parameter int unsigned BAUD_RATE = 115_200
)(
    input  logic clk,
    input  logic rst_n,

    input  logic uart_rx,
    output logic uart_tx,

    output logic [7:0] rx_data,
    output logic rx_valid,

    input  logic [7:0] tx_data,
    input  logic tx_start,
    output logic tx_busy
);

// UART RX

uart_rx #(
    .CLK_FREQ(CLK_FREQ),
    .BAUD_RATE(BAUD_RATE)
) uart_rx_inst (
    .clk(clk),
    .rst_n(rst_n),
    .rx(uart_rx),
    .data_out(rx_data),
    .data_valid(rx_valid)
);

// UART TX
uart_tx #(
    .CLK_FREQ(CLK_FREQ),
    .BAUD_RATE(BAUD_RATE)
) uart_tx_inst (
    .clk(clk),
    .rst_n(rst_n),
    .start(tx_start),
    .data_in(tx_data),
    .tx(uart_tx),
    .busy(tx_busy)
);

endmodule