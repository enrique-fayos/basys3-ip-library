// =============================================================================
// Testbench: tb_uart_loopback_top
// Author: Enrique Fayos Gimeno
// Date: 2026-08-27
//
// Description:
//   Self-checking testbench for the uart_loopback_top module.
//   Drives UART bytes into uart_rx and verifies that the same bytes are
//   retransmitted on uart_tx using the 8N1 format, LSB first.
//
// Verification:
//   - Applies an active-low reset.
//   - Sends multiple UART test bytes to uart_rx.
//   - Checks start, data and stop bits on uart_tx.
//   - Reports loopback errors and final PASS/FAIL status.
//
// Default configuration:
//   Clock:     100 MHz
//   Baud rate: 115200
// =============================================================================
`timescale 1ns/1ps

module tb_uart_loopback_top;

// PARAMETERS
localparam int unsigned CLK_FREQ = 100_000_000;
localparam int unsigned BAUD_RATE = 115200;
localparam int unsigned CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;

localparam time CLK_PERIOD = 1s / CLK_FREQ;
localparam time BIT_PERIOD = CLK_PERIOD * CLKS_PER_BIT;

// SIGNALS
logic clk;
logic rst_n;
logic uart_rx;

logic uart_tx;

// CONTROL SIGNALS
int unsigned error_count = 0;

// CLOCK GENERATION (100 MHz)
initial clk = 1'b0;
always #(CLK_PERIOD / 2) clk = ~clk;

// DUT INSTANTIATION
uart_loopback_top #(
    .CLK_FREQ(CLK_FREQ),
    .BAUD_RATE(BAUD_RATE)
) dut (
    .clk(clk),
    .rst_n(rst_n),
    .uart_rx(uart_rx),
    .uart_tx(uart_tx)
);

// TASKS
task reset();
    begin
        rst_n = 1'b0;
        uart_rx = 1'b1;

        repeat (5) @(negedge clk);

        rst_n = 1'b1;
        $display("[%0t] Reset complete", $time);
    end
endtask

task automatic send_byte(input logic [7:0] data);
    begin
        $display("[%0t] Sending byte: %02h", $time, data);

        // Start bit
        uart_rx = 1'b0;
        #(BIT_PERIOD);

        // Data bits, LSB first
        for (int i = 0; i < 8; i++) begin
            uart_rx = data[i];
            #(BIT_PERIOD);
        end

        // Stop bit
        uart_rx = 1'b1;
        #(BIT_PERIOD);
    end
endtask

task automatic check_byte(input logic [7:0] expected_data);
    begin
        @(negedge uart_tx);

        // Move to the middle of the start bit
        repeat (CLKS_PER_BIT/2) @(negedge clk);
        assert (uart_tx == 1'b0)
        else begin
            error_count++;
            $error("[%0t] Invalid loopback start bit", $time);
        end

        // Check the 8 data bits, LSB first
        for (int i = 0; i < 8; i++) begin
            repeat (CLKS_PER_BIT) @(negedge clk);
            assert (uart_tx == expected_data[i])
            else begin
                error_count++;
                $error(
                    "[%0t] Loopback data bit %0d mismatch: expected %b, got %b",
                    $time,
                    i,
                    expected_data[i],
                    uart_tx
                );
            end
        end

        repeat (CLKS_PER_BIT) @(negedge clk);
        assert (uart_tx === 1'b1)
        else begin
            error_count++;
            $error("[%0t] Invalid loopback stop bit", $time);
        end

        $display(
            "[%0t] Loopback byte %02h checked",
            $time,
            expected_data
        );
    end
endtask

task automatic test_byte(input logic [7:0] data);
    fork
        send_byte(data);
        check_byte(data);
    join
endtask

// ASSERTIONS
// During reset, the UART transmitter should be idle
assert_reset_idle:
assert property (
    @(posedge clk)
    !rst_n |-> (uart_tx == 1'b1))
    else begin
        error_count++;
        $error("[%0t] UART TX is not idle during reset", $time);
    end

// STIMULUS
initial begin
    reset();

    test_byte(8'h00);
    test_byte(8'hFF);
    test_byte(8'h01);
    test_byte(8'h80);
    test_byte(8'h96);
    test_byte(8'h57);
    test_byte(8'hAB);

    repeat (5) @(posedge clk);

    if (error_count == 0) begin
        $display(
            "[%0t] PASS: All UART loopback tests passed",
            $time
        );
    end else begin
        $fatal(
            1,
            "[%0t] FAIL: UART loopback test completed with %0d errors",
            $time,
            error_count
        );
    end

    #(14);
    $finish;
end
endmodule
