// =============================================================================
// Testbench: tb_uart_rx
// Author: Enrique Fayos Gimeno
// Date: 2026-08-19
//
// Description:
//   Self-checking testbench for the uart_rx module.
//   Verifies UART reception using the 8N1 format, LSB first,
//   at a configurable clock frequency and baud rate.
//
// Verification:
//   - Applies an active-low reset.
//   - Sends multiple UART test bytes.
//   - Checks received data when data_valid is asserted.
//   - Reports reception errors and final PASS/FAIL status.
//
// Default configuration:
//   Clock:     100 MHz
//   Baud rate: 115200
// =============================================================================
`timescale 1ns/1ps

module tb_uart_rx;

// PARAMETERS
localparam int unsigned CLK_FREQ = 100_000_000;
localparam int unsigned BAUD_RATE = 115200;
localparam int unsigned CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;

localparam time CLK_PERIOD = 1s / CLK_FREQ;
localparam time BIT_PERIOD = CLK_PERIOD * CLKS_PER_BIT;

// SIGNALS
logic clk;
logic rst_n;
logic rx;

logic [7:0] data_out;
logic data_valid;

// CONTROL SIGNALS
int unsigned error_count = 0;

// CLOCK GENERATION (100 MHz)
initial clk = 1'b0;
always #(CLK_PERIOD / 2) clk = ~clk;

// DUT INSTANTIATION
uart_rx #(
    .CLK_FREQ(CLK_FREQ),
    .BAUD_RATE(BAUD_RATE)
) dut (
    .clk(clk),
    .rst_n(rst_n),
    .rx(rx),
    .data_out(data_out),
    .data_valid(data_valid)
);

// TASKS
task reset();
    begin
        rst_n = 1'b0;
        rx = 1'b1;

        repeat (5) @(negedge clk);

        rst_n = 1'b1;
        $display("[%0t] Reset complete", $time);
    end
endtask

task automatic send_byte(input logic [7:0] data);
    begin
        $display("[%0t] Sending byte: %02h", $time, data);

        rx = 1'b0;
        #(BIT_PERIOD);

        for (int i = 0; i < 8; i++) begin
            rx = data[i];
            #(BIT_PERIOD);
        end

        rx = 1'b1;
        #(BIT_PERIOD);
    end
endtask

task automatic check_byte(input logic [7:0] expected_data);
    begin
        @(posedge data_valid);

        assert (data_out === expected_data)
        else begin
            error_count++;
            $error(
                "[%0t] Received byte mismatch: expected %02h, got %02h",
                $time,
                expected_data,
                data_out
            );
        end

        $display(
            "[%0t] Byte %02h checked",
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

// STIMULUS
initial begin
    reset();
    
    test_byte(8'h00);
    test_byte(8'hFF);
    test_byte(8'h01);
    test_byte(8'h80);
    test_byte(8'h96);

    repeat (5) @(posedge clk);

    if (error_count == 0) begin
        $display(
            "[%0t] PASS: All UART RX tests passed",
            $time
        );
    end else begin
        $fatal(
            1,
            "[%0t] FAIL: UART RX test completed with %0d errors",
            $time,
            error_count
        );
    end

    #(14);
    $finish;
end
endmodule