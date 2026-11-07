// =============================================================================
// Testbench: fft_top_tb
// Author: Enrique Fayos Gimeno
// Date: 2026-11-07
//
// Description:
//   Self-checking serial-to-serial test for the 32-point FFT UART top.
//   Checks complete response blocks against an independent integer model
//   and checks that model against a direct, normalized floating-point DFT.
//
// Verification:
//   - Zero, impulse, shifted impulse, DC, positive/negative tone, mixed inputs.
//   - Signed components, byte order, bin order, and exactly 128 output bytes.
//   - Back-to-back input bytes, input gaps, and reset during a partial sample.
//   - Ignored input during result transmission and after completion.
//   - RTL assertions enabled and a bounded simulation watchdog.
// =============================================================================
`timescale 1ns/1ps

module fft_top_tb;

// PARAMETERS
localparam int unsigned CLK_FREQ = 100_000_000;
localparam int unsigned BAUD_RATE = 115_200;
localparam time CLK_PERIOD = 10ns;
// Independent host timing uses the requested baud rate, not the RTL divider.
localparam time BIT_PERIOD = 1s / BAUD_RATE;
localparam real PI = 3.141592653589793;

// SIGNALS
logic clk;
logic rst_n;
logic uart_rx;
logic uart_tx;

// REFERENCE DATA
int signed input_real [0:31];
int signed input_imag [0:31];
int signed expected_real [0:31];
int signed expected_imag [0:31];
logic [7:0] expected_bytes [0:127];
int unsigned received_count = 0;
int unsigned test_count = 0;

// CLOCK GENERATION (100 MHz)
initial clk = 1'b0;
always #(CLK_PERIOD / 2) clk = ~clk;

// DUT INSTANTIATION
fft_top #(
    .CLK_FREQ(CLK_FREQ),
    .BAUD_RATE(BAUD_RATE)
) dut (
    .clk(clk),
    .rst_n(rst_n),
    .uart_rx(uart_rx),
    .uart_tx(uart_tx)
);

// REFERENCE FUNCTIONS
function automatic int signed nearest_integer(input real value);
    return value >= 0.0 ? $rtoi(value + 0.5) : $rtoi(value - 0.5);
endfunction

function automatic int signed wrap_signed_16(input longint signed value);
    logic signed [15:0] narrowed;
    narrowed = value[15:0];
    return int'(narrowed);
endfunction

// TASKS
task automatic reset();
    @(negedge clk);
    rst_n = 1'b0;
    uart_rx = 1'b1;
    repeat (5) @(negedge clk);
    rst_n = 1'b1;
    repeat (5) @(negedge clk);
    received_count = 0;
endtask

task automatic send_byte(input logic [7:0] data);
    uart_rx = 1'b0;
    #(BIT_PERIOD);
    for (int bit_index = 0; bit_index < 8; bit_index++) begin
        uart_rx = data[bit_index];
        #(BIT_PERIOD);
    end
    uart_rx = 1'b1;
    #(BIT_PERIOD);
endtask

task automatic prepare_input(input int unsigned test_index);
    for (int n = 0; n < 32; n++) begin
        input_real[n] = 0;
        input_imag[n] = 0;
        case (test_index)
            1: if (n == 0) begin
                input_real[n] = 8192;
                input_imag[n] = -4096;
            end
            2: if (n == 7) begin
                input_real[n] = 4096;
                input_imag[n] = -2048;
            end
            3: begin
                input_real[n] = 1024;
                input_imag[n] = -512;
            end
            4: begin
                input_real[n] = nearest_integer(4096.0 * $cos(2.0 * PI * 3 * n / 32));
                input_imag[n] = nearest_integer(4096.0 * $sin(2.0 * PI * 3 * n / 32));
            end
            5: begin
                input_real[n] = nearest_integer(4096.0 * $cos(-2.0 * PI * 5 * n / 32));
                input_imag[n] = nearest_integer(4096.0 * $sin(-2.0 * PI * 5 * n / 32));
            end
            6: begin
                input_real[n] = ((n * 1931 + 101) % 8192) - 4096;
                input_imag[n] = ((n * n * 719 + 29) % 8192) - 4096;
            end
            default: begin
                input_real[n] = 0;
                input_imag[n] = 0;
            end
        endcase
    end
endtask

task automatic calculate_reference();
    int reversed;
    int a, b;
    int signed wr, wi;
    longint signed ar, ai, br, bi, tr, ti;
    real angle, dft_real, dft_imag;

    // Generate bit-reversed loading independently of the controller wiring.
    for (int n = 0; n < 32; n++) begin
        reversed = 0;
        for (int bit_index = 0; bit_index < 5; bit_index++) begin
            reversed = (reversed << 1) | ((n >> bit_index) & 1);
        end
        expected_real[reversed] = input_real[n];
        expected_imag[reversed] = input_imag[n];
    end

    // Mathematical radix-2 schedule with wide integer arithmetic.
    for (int span = 2; span <= 32; span *= 2) begin
        for (int base = 0; base < 32; base += span) begin
            for (int j = 0; j < span / 2; j++) begin
                angle = -2.0 * PI * j / span;
                wr = nearest_integer(32768.0 * $cos(angle));
                wi = nearest_integer(32768.0 * $sin(angle));
                if (wr > 32767) wr = 32767;
                if (wi > 32767) wi = 32767;
                a = base + j;
                b = a + span / 2;
                ar = expected_real[a];
                ai = expected_imag[a];
                br = expected_real[b];
                bi = expected_imag[b];
                tr = br * wr - bi * wi;
                ti = br * wi + bi * wr;
                expected_real[a] = wrap_signed_16((ar * 32768 + tr) >>> 16);
                expected_imag[a] = wrap_signed_16((ai * 32768 + ti) >>> 16);
                expected_real[b] = wrap_signed_16((ar * 32768 - tr) >>> 16);
                expected_imag[b] = wrap_signed_16((ai * 32768 - ti) >>> 16);
            end
        end
    end

    for (int k = 0; k < 32; k++) begin
        expected_bytes[4*k]   = expected_real[k][15:8];
        expected_bytes[4*k+1] = expected_real[k][7:0];
        expected_bytes[4*k+2] = expected_imag[k][15:8];
        expected_bytes[4*k+3] = expected_imag[k][7:0];

        // Independently check transform sign, ordering, and 1/32 scaling.
        dft_real = 0.0;
        dft_imag = 0.0;
        for (int n = 0; n < 32; n++) begin
            angle = -2.0 * PI * k * n / 32;
            dft_real += input_real[n] * $cos(angle) - input_imag[n] * $sin(angle);
            dft_imag += input_real[n] * $sin(angle) + input_imag[n] * $cos(angle);
        end
        if (expected_real[k] - dft_real / 32 > 6.0 ||
            expected_real[k] - dft_real / 32 < -6.0 ||
            expected_imag[k] - dft_imag / 32 > 6.0 ||
            expected_imag[k] - dft_imag / 32 < -6.0) begin
            $fatal(1, "Reference model differs from normalized DFT at bin %0d", k);
        end
    end
endtask

task automatic send_block(input bit add_gaps);
    for (int n = 0; n < 32; n++) begin
        send_byte(input_real[n][15:8]);
        send_byte(input_real[n][7:0]);
        send_byte(input_imag[n][15:8]);
        send_byte(input_imag[n][7:0]);
        if (add_gaps && n % 5 == 0) begin
            #(2 * BIT_PERIOD);
        end
    end
endtask

// INDEPENDENT UART RESPONSE MONITOR
// This monitor stays active while input stimulus is being transmitted.
initial begin
    logic [7:0] received_byte;
    forever begin
        @(negedge uart_tx);
        if (rst_n === 1'b1) begin
            #(BIT_PERIOD / 2);
            if (uart_tx !== 1'b0) $fatal(1, "Invalid response start bit");
            for (int bit_index = 0; bit_index < 8; bit_index++) begin
                #(BIT_PERIOD);
                received_byte[bit_index] = uart_tx;
            end
            #(BIT_PERIOD);
            if (uart_tx !== 1'b1) $fatal(1, "Invalid response stop bit");
            if (received_count >= 128) $fatal(1, "More than 128 response bytes");
            if (received_byte !== expected_bytes[received_count]) begin
                $fatal(1, "Test %0d byte %0d: expected %02h, got %02h",
                       test_count, received_count,
                       expected_bytes[received_count], received_byte);
            end
            received_count++;
        end
    end
end

// STIMULUS
initial begin
    rst_n = 1'b0;
    uart_rx = 1'b1;
    reset();

    // Reset discards a partially assembled sample and an incomplete block.
    for (int n = 0; n < 11; n++) send_byte(8'hA5);
    #(12 * BIT_PERIOD);
    if (received_count != 0) $fatal(1, "Response to an incomplete block");

    for (int test_index = 0; test_index < 7; test_index++) begin
        reset();
        test_count = test_index;
        prepare_input(test_index);
        calculate_reference();
        send_block(test_index[0]);

        // Extra RX traffic must not corrupt the results being transmitted.
        send_byte(8'hDE);
        send_byte(8'hAD);
        send_byte(8'hBE);
        send_byte(8'hEF);
        wait (received_count == 128);
        #(2 * BIT_PERIOD);

        // A second input block without reset must not restart the FFT.
        send_block(1'b0);
        #(12 * BIT_PERIOD);
        if (received_count != 128) $fatal(1, "Incorrect response byte count");
        $display("PASS: Test %0d checked all 32 bins and 128 UART bytes", test_index);
    end

    $display("PASS: All FFT top tests passed");
    $finish;
end

// WATCHDOG
initial begin
    #300ms;
    $fatal(1, "FFT top test timed out");
end

endmodule
