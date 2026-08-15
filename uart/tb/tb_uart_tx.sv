// =============================================================================
// Testbench: tb_uart_tx
// Author: Enrique Fayos Gimeno
// Date: 2026-08-15
//
// Description:
//   Self-checking testbench for the uart_tx module.
//   Verifies UART transmission using the 8N1 format, LSB first,
//   at a configurable clock frequency and baud rate.
//
// Verification:
//   - Applies an active-low reset.
//   - Sends multiple test bytes.
//   - Checks start, data and stop bits.
//   - Reports transmission errors and final PASS/FAIL status.
//
// Default configuration:
//   Clock:     100 MHz
//   Baud rate: 115200
// =============================================================================
`timescale 1ns/1ps

module tb_uart_tx;

// PARAMETERS
localparam int unsigned CLK_FREQ = 100_000_000;
localparam int unsigned BAUD_RATE = 115200;
localparam int unsigned CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;

localparam int unsigned CLK_PERIOD = 1s / CLK_FREQ;

// SIGNALS
logic clk;
logic rst_n;
logic start;
logic [7:0] data_in;

logic tx;
logic busy;

// CONTROL SIGNALS
int unsigned error_count = 0;

// CLOCK GENERATION (100 MHz)
initial clk = 1'b0;
always #(CLK_PERIOD / 2) clk = ~clk;

// DUT INSTANTIATION
uart_tx #(
    .CLK_FREQ(CLK_FREQ),
    .BAUD_RATE(BAUD_RATE)
) dut (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .data_in(data_in),
    .tx(tx),
    .busy(busy)
);

// TASKS
task reset();
    begin
        rst_n = 1'b0;
        start = 1'b0;
        data_in = 8'd0;

        repeat (5) @(negedge clk);

        rst_n = 1'b1;
        $display("[%0t] Reset complete", $time);
    end
endtask

task automatic send_byte(input logic [7:0] data);
    begin
        wait(!busy);

        @(negedge clk);
        data_in = data;
        start = 1'b1;

        $display("[%0t] Sending byte: %02h", $time, data);

        @(negedge clk);
        start = 1'b0;
    end
endtask

task automatic check_byte(input logic [7:0] expected_data);
    begin
        @(negedge tx);
        //Move to the middle of the start bit
        repeat (CLKS_PER_BIT/2) @(negedge clk);
        assert (tx == 1'b0)
        else begin
            error_count++;
            $error("[%0t] Invalid start bit", $time);
        end

        //Check the 8 bits, LSB first
        for (int i = 0; i < 8; i++) begin
            repeat (CLKS_PER_BIT) @(negedge clk);
            assert (tx == expected_data[i])
            else begin
                error_count++;
                $error(
                    "[%0t] Data bit %0d mismatch: expected %b, got %b",
                    $time,
                    i,
                    expected_data[i],
                    tx
                );
            end
        end

        repeat (CLKS_PER_BIT) @(negedge clk);
        assert (tx === 1'b1)
        else begin
            error_count++;
            $error("[%0t] Invalid stop bit", $time);
        end

        wait (!busy);
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
            "[%0t] PASS: All UART TX tests passed",
            $time
        );
    end else begin
        $fatal(
            1,
            "[%0t] FAIL: UART TX test completed with %0d errors",
            $time,
            error_count
        );
    end

    #(14);
    $finish;
end
endmodule