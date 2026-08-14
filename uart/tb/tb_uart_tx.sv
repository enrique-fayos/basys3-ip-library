`timescale 1ns/1ps

module tb_uart_tx;

// PARAMETERS
parameter int unsigned CLK_FREQ = 100_000_000;
parameter int unsigned BAUD_RATE = 115200;

// SIGNALS
logic clk;
logic rst_n;
logic start;
logic [7:0] data_in;

logic tx;
logic busy;

// CLOCK GENERATION
initial clk = 1'b0;
always #5 clk = ~clk;

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
    end
endtask

task automatic send_byte(input logic [7:0] data);
    begin
        wait(!busy);

        @(negedge clk);
        data_in = data;
        start = 1'b1;

        @(negedge clk);
        start = 1'b0;
    end
endtask

endmodule