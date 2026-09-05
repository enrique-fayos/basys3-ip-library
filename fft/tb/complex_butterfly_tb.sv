// =============================================================================
// Testbench: complex_butterfly_tb
// Author: Enrique Fayos Gimeno
// Date: 2026-09-05
//
// Description:
//   Self-checking testbench for the combinational complex_butterfly module.
//   Applies directed complex inputs and checks the scaled 16-bit outputs.
//
// Verification:
//   - Checks the Q1.15 approximation of the +1 twiddle factor.
//   - Checks the exact -j rotation.
//   - Checks an approximately 45-degree negative rotation.
//   - Checks negative input components and signed truncation.
//   - Checks high-amplitude inputs near the signed 16-bit limits.
// =============================================================================
`timescale 1ns/1ps

module complex_butterfly_tb;

// SIGNALS
logic signed [15:0] a_real;
logic signed [15:0] a_imag;
logic signed [15:0] b_real;
logic signed [15:0] b_imag;
logic signed [15:0] w_real;
logic signed [15:0] w_imag;

logic signed [15:0] x_real;
logic signed [15:0] x_imag;
logic signed [15:0] y_real;
logic signed [15:0] y_imag;

// CONTROL SIGNALS
int unsigned error_count = 0;

// DUT INSTANTIATION
complex_butterfly dut (
    .a_real(a_real),
    .a_imag(a_imag),
    .b_real(b_real),
    .b_imag(b_imag),
    .w_real(w_real),
    .w_imag(w_imag),
    .x_real(x_real),
    .x_imag(x_imag),
    .y_real(y_real),
    .y_imag(y_imag)
);

// TASKS
task automatic check_butterfly(
    input string test_name,
    input logic signed [15:0] test_a_real,
    input logic signed [15:0] test_a_imag,
    input logic signed [15:0] test_b_real,
    input logic signed [15:0] test_b_imag,
    input logic signed [15:0] test_w_real,
    input logic signed [15:0] test_w_imag,
    input logic signed [15:0] expected_x_real,
    input logic signed [15:0] expected_x_imag,
    input logic signed [15:0] expected_y_real,
    input logic signed [15:0] expected_y_imag
);
    begin
        a_real = test_a_real;
        a_imag = test_a_imag;
        b_real = test_b_real;
        b_imag = test_b_imag;
        w_real = test_w_real;
        w_imag = test_w_imag;

        #1;

        assert (
            x_real === expected_x_real &&
            x_imag === expected_x_imag &&
            y_real === expected_y_real &&
            y_imag === expected_y_imag)
        else begin
            error_count++;
            $error(
                "[%0t] %s failed: expected X=(%0d,%0d), Y=(%0d,%0d); got X=(%0d,%0d), Y=(%0d,%0d)",
                $time,
                test_name,
                expected_x_real,
                expected_x_imag,
                expected_y_real,
                expected_y_imag,
                x_real,
                x_imag,
                y_real,
                y_imag
            );
        end

        if (
            x_real === expected_x_real &&
            x_imag === expected_x_imag &&
            y_real === expected_y_real &&
            y_imag === expected_y_imag) begin
            $display("[%0t] %s passed", $time, test_name);
        end
    end
endtask

// STIMULUS
initial begin
    a_real = 16'sd0;
    a_imag = 16'sd0;
    b_real = 16'sd0;
    b_imag = 16'sd0;
    w_real = 16'sd0;
    w_imag = 16'sd0;

    // W is the closest positive Q1.15 value to +1.
    check_butterfly(
        "W approximately +1",
        16'sd1000,
        -16'sd2000,
        16'sd3000,
        16'sd4000,
        16'sh7FFF,
        16'sd0,
        16'sd1999,
        16'sd999,
        -16'sd1000,
        -16'sd3000
    );

    // Multiplication by -j rotates (b_real, b_imag) to (b_imag, -b_real).
    check_butterfly(
        "W equals -j",
        16'sd1000,
        16'sd2000,
        16'sd3000,
        16'sd4000,
        16'sd0,
        16'sh8000,
        16'sd2500,
        -16'sd500,
        -16'sd1500,
        16'sd2500
    );

    // 4096 * 23170 / 32768 = 2896.25 for an auditable product.
    check_butterfly(
        "W approximately 0.7071 - j0.7071",
        16'sd4096,
        16'sd4096,
        16'sd4096,
        16'sd0,
        16'sd23170,
        -16'sd23170,
        16'sd3496,
        16'sd599,
        16'sd599,
        16'sd3496
    );

    // Negative A and B components exercise signed multiplication and truncation.
    check_butterfly(
        "Negative complex inputs",
        -16'sd1000,
        -16'sd2000,
        -16'sd3000,
        -16'sd4000,
        16'sh7FFF,
        16'sd0,
        -16'sd2000,
        -16'sd3000,
        16'sd999,
        16'sd999
    );

    // Exact -j rotation keeps the high-amplitude result within 16 bits after scaling.
    check_butterfly(
        "High-amplitude stage scaling",
        16'sh7FFF,
        16'sh8000,
        16'sh7FFF,
        16'sh8000,
        16'sd0,
        16'sh8000,
        -16'sd1,
        16'sh8000,
        16'sh7FFF,
        -16'sd1
    );

    if (error_count == 0) begin
        $display(
            "[%0t] PASS: All complex butterfly tests passed",
            $time
        );
    end else begin
        $fatal(
            1,
            "[%0t] FAIL: Complex butterfly test completed with %0d errors",
            $time,
            error_count
        );
    end

    #(14);
    $finish;
end

endmodule
