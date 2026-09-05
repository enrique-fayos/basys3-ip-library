// =============================================================================
// Module: complex_butterfly
// Author: Enrique Fayos Gimeno
// Date: 2026-09-05
//
// Description:
//   Combinational radix-2 complex butterfly for the 32-point FFT.
//   The twiddle factor uses signed fixed-point values with 15 fractional bits.
//   Each output is scaled by 1/2 before returning to a signed 16-bit value.
//
// Interface:
//   a_real - Real component of complex input A.
//   a_imag - Imaginary component of complex input A.
//   b_real - Real component of complex input B.
//   b_imag - Imaginary component of complex input B.
//   w_real - Real component of the Q1.15 twiddle factor W.
//   w_imag - Imaginary component of the Q1.15 twiddle factor W.
//   x_real - Real component of scaled output X = (A + B*W) / 2.
//   x_imag - Imaginary component of scaled output X = (A + B*W) / 2.
//   y_real - Real component of scaled output Y = (A - B*W) / 2.
//   y_imag - Imaginary component of scaled output Y = (A - B*W) / 2.
//
// Reset:
//   None. This module is purely combinational.
// =============================================================================

module complex_butterfly (
    input  logic signed [15:0] a_real,
    input  logic signed [15:0] a_imag,
    input  logic signed [15:0] b_real,
    input  logic signed [15:0] b_imag,
    input  logic signed [15:0] w_real,
    input  logic signed [15:0] w_imag,

    output logic signed [15:0] x_real,
    output logic signed [15:0] x_imag,
    output logic signed [15:0] y_real,
    output logic signed [15:0] y_imag
);

// SIGN-EXTENDED MULTIPLIER OPERANDS
// Explicit extension fixes the signed multiplication width at 32 bits.
logic signed [31:0] b_real_extended;
logic signed [31:0] b_imag_extended;
logic signed [31:0] w_real_extended;
logic signed [31:0] w_imag_extended;

// FULL-PRECISION MULTIPLICATION RESULTS
logic signed [31:0] product_br_wr;
logic signed [31:0] product_bi_wi;
logic signed [31:0] product_br_wi;
logic signed [31:0] product_bi_wr;

// TWIDDLE MULTIPLICATION RESULTS
// One extra bit preserves the sum or difference of two signed products.
logic signed [32:0] product_br_wr_extended;
logic signed [32:0] product_bi_wi_extended;
logic signed [32:0] product_br_wi_extended;
logic signed [32:0] product_bi_wr_extended;
logic signed [32:0] t_real;
logic signed [32:0] t_imag;

// BUTTERFLY ADDITION AND SCALING
logic signed [32:0] a_real_aligned;
logic signed [32:0] a_imag_aligned;
logic signed [32:0] x_real_full;
logic signed [32:0] x_imag_full;
logic signed [32:0] y_real_full;
logic signed [32:0] y_imag_full;
logic signed [32:0] x_real_scaled;
logic signed [32:0] x_imag_scaled;
logic signed [32:0] y_real_scaled;
logic signed [32:0] y_imag_scaled;

// COMPLEX BUTTERFLY DATAPATH
always_comb begin
    b_real_extended = {{16{b_real[15]}}, b_real};
    b_imag_extended = {{16{b_imag[15]}}, b_imag};
    w_real_extended = {{16{w_real[15]}}, w_real};
    w_imag_extended = {{16{w_imag[15]}}, w_imag};

    product_br_wr = b_real_extended * w_real_extended;
    product_bi_wi = b_imag_extended * w_imag_extended;
    product_br_wi = b_real_extended * w_imag_extended;
    product_bi_wr = b_imag_extended * w_real_extended;

    product_br_wr_extended = {product_br_wr[31], product_br_wr};
    product_bi_wi_extended = {product_bi_wi[31], product_bi_wi};
    product_br_wi_extended = {product_br_wi[31], product_br_wi};
    product_bi_wr_extended = {product_bi_wr[31], product_bi_wr};

    t_real = product_br_wr_extended - product_bi_wi_extended;
    t_imag = product_br_wi_extended + product_bi_wr_extended;

    // Append 15 zeros to align A with the Q1.15 multiplication results.
    // The two leading sign bits extend the resulting 31-bit value to 33 bits.
    a_real_aligned = {{2{a_real[15]}}, a_real, 15'b0};
    a_imag_aligned = {{2{a_imag[15]}}, a_imag, 15'b0};

    x_real_full = a_real_aligned + t_real;
    x_imag_full = a_imag_aligned + t_imag;
    y_real_full = a_real_aligned - t_real;
    y_imag_full = a_imag_aligned - t_imag;

    // Remove 15 twiddle fractional bits and apply the stage scaling by 1/2.
    x_real_scaled = x_real_full >>> 16;
    x_imag_scaled = x_imag_full >>> 16;
    y_real_scaled = y_real_full >>> 16;
    y_imag_scaled = y_imag_full >>> 16;

    // Deliberately truncate to 16 bits; this version does not saturate.
    x_real = x_real_scaled[15:0];
    x_imag = x_imag_scaled[15:0];
    y_real = y_real_scaled[15:0];
    y_imag = y_imag_scaled[15:0];
end

endmodule
