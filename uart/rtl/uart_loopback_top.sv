// =============================================================================
// Module: uart_loopback_top
// Author: Enrique Fayos Gimeno
// Date: 2026-08-26
//
// Description:
//   Top-level module for UART loopback testing.
//   Receives UART bytes and retransmits the same data back to the host.
//
// Interface:
//   uart_rx - UART serial input from the host, idle-high.
//   uart_tx - UART serial output to the host, idle-high.
//
// Reset:
//   Active-low asynchronous reset.
//
// Default configuration:
//   Clock:     100 MHz
//   Baud rate: 115200
// =============================================================================

module uart_loopback_top #(
    parameter int unsigned CLK_FREQ  = 100_000_000,
    parameter int unsigned BAUD_RATE = 115_200
)(
    input  logic clk,
    input  logic rst_n,

    input  logic uart_rx,
    output logic uart_tx
);

// UART RX SIGNALS
logic [7:0] rx_data;
logic       rx_valid;

// UART TX SIGNALS
logic [7:0] tx_data;
logic       tx_start;
logic       tx_busy;

// LOOPBACK BUFFER
logic [7:0] pending_data;
logic       pending_valid;

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

// LOOPBACK CONTROL
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        tx_data       <= 8'd0;
        tx_start      <= 1'b0;
        pending_data  <= 8'd0;
        pending_valid <= 1'b0;
    end else begin
        tx_start <= 1'b0;
        if (rx_valid) begin
            pending_data  <= rx_data;
            pending_valid <= 1'b1;
        end
        if (pending_valid && !tx_busy) begin
            tx_data       <= pending_data;
            tx_start      <= 1'b1;
            pending_valid <= 1'b0;
        end
    end
end

endmodule