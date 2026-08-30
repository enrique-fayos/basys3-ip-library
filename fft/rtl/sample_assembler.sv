// =============================================================================
// Module: sample_assembler
// Author: Enrique Fayos Gimeno
// Date: 2026-08-30
//
// Description:
//   Assembles four consecutive input bytes into one 32-bit complex sample.
//   Input bytes are ordered as real high, real low, imaginary high, and
//   imaginary low, producing {Real[15:0], Imag[15:0]}.
//
// Interface:
//   input_data        - Incoming 8-bit sample data.
//   input_data_valid  - High when input_data contains a valid byte.
//   output_data       - Assembled 32-bit complex sample.
//   output_data_valid - One-clock pulse when a complete sample is available.
//
// Reset:
//   Active-low asynchronous reset.
// =============================================================================

module sample_assembler (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        input_data_valid,
    input  logic [7:0]  input_data,

    output logic        output_data_valid,
    output logic [31:0] output_data
);

// INTERNAL REGISTERS
logic [1:0] byte_count;
logic [23:0] sample_reg;

// SAMPLE ASSEMBLY
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        byte_count        <= 2'd0;
        sample_reg        <= 24'd0;
        output_data       <= 32'd0;
        output_data_valid <= 1'b0;
    end else begin
        output_data_valid <= 1'b0;

        if (input_data_valid) begin
            if (byte_count == 2'd3) begin
                output_data       <= {sample_reg[23:0], input_data};
                output_data_valid <= 1'b1;
                byte_count        <= 2'd0;
            end else begin
                sample_reg <= {sample_reg[15:0], input_data};
                byte_count <= byte_count + 1'b1;
            end
        end
    end
end

// synthesis translate_off

// ASSERTIONS
// During reset, the assembler should be inactive
assert_reset_idle:
assert property (
    @(posedge clk)
    !rst_n |-> (output_data_valid == 1'b0 && byte_count == 2'd0))
    else $error("[%0t] Sample assembler is not idle during reset", $time);

// output_data_valid should only assert after receiving the fourth byte
assert_valid_after_fourth_byte:
assert property (
    @(posedge clk)
    disable iff (!rst_n)
    output_data_valid |-> $past(input_data_valid == 1'b1 && byte_count == 2'd3))
    else $error("[%0t] Sample assembler asserted output_data_valid without a fourth byte", $time);

// A complete sample should reset the byte counter
assert_complete_sample_resets_counter:
assert property (
    @(posedge clk)
    disable iff (!rst_n)
    output_data_valid |-> (byte_count == 2'd0))
    else $error("[%0t] Sample assembler byte counter did not reset after a complete sample", $time);

// output_data_valid should only last one clock cycle
assert_output_data_valid_pulse:
assert property (
    @(posedge clk)
    disable iff (!rst_n)
    output_data_valid |=> !output_data_valid)
    else $error("[%0t] Sample assembler output_data_valid lasted more than one clock cycle", $time);

// synthesis translate_on

endmodule
