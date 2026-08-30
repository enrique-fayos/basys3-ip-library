// =============================================================================
// Module: fft_memory
// Author: Enrique Fayos Gimeno
// Date: 2026-08-30
//
// Description:
//   32-word x 32-bit true dual-port synchronous memory for FFT data storage.
//   The memory is implemented as Block RAM on Xilinx devices.
//
// Interface:
//   address_a      - Port A 5-bit word address.
//   write_enable_a - Port A write enable, active-high.
//   data_in_a      - Port A 32-bit write data.
//   data_out_a     - Port A 32-bit synchronous read data.
//   address_b      - Port B 5-bit word address.
//   write_enable_b - Port B write enable, active-high.
//   data_in_b      - Port B 32-bit write data.
//   data_out_b     - Port B 32-bit synchronous read data.
//
// Reset:
//   None.
// =============================================================================

module fft_memory (
    input logic clk,

    input  logic [4:0] address_a,
    input  logic       write_enable_a,
    input  logic [31:0] data_in_a,
    output logic [31:0] data_out_a,

    input  logic [4:0] address_b,
    input  logic       write_enable_b,
    input  logic [31:0] data_in_b,
    output logic [31:0] data_out_b
);

// BLOCK RAM
(* ram_style = "block" *) logic [31:0] memory [0:31];

// DUAL-PORT MEMORY
// port A 
always_ff @(posedge clk) begin
    if (write_enable_a) begin
        memory[address_a] <= data_in_a;
    end

    data_out_a <= memory[address_a];
end
// port B
always_ff @(posedge clk) begin
    if (write_enable_b) begin
        memory[address_b] <= data_in_b;
    end

    data_out_b <= memory[address_b];
end

// synthesis translate_off

// ASSERTIONS
// Both ports should not write to the same address simultaneously
assert_no_simultaneous_writes:
assert property (
    @(posedge clk)
    !(write_enable_a == 1'b1 && write_enable_b == 1'b1 && address_a == address_b))
    else $error("[%0t] FFT memory ports wrote to the same address simultaneously", $time);

// One port should not write while the other accesses the same address
assert_no_read_write_collision:
assert property (
    @(posedge clk)
    !((write_enable_a == 1'b1 && write_enable_b == 1'b0 && address_a == address_b) ||
      (write_enable_b == 1'b1 && write_enable_a == 1'b0 && address_b == address_a)))
    else $error("[%0t] FFT memory read/write collision detected", $time);

// synthesis translate_on

endmodule
