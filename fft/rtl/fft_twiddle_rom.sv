// =============================================================================
// Module: fft_twiddle_rom
// Author: Enrique Fayos Gimeno
// Date: 2026-09-23
//
// Description:
//   Combinational constant ROM containing W32^k = exp(-j*2*pi*k/32), k = 0..15.
//   Components use signed Q1.15 representation: stored_value / 32768.
//   Exact +1 is clamped to 32767; exact -1 is represented by -32768.
//
// Interface:
//   address - 4-bit W32 twiddle index from fft_controller.twiddle_addr.
//   w_real  - Signed 16-bit real component of the twiddle factor.
//   w_imag  - Signed 16-bit imaginary component of the twiddle factor.
//
// Reset:
//   None. This module is purely combinational.
// =============================================================================

module fft_twiddle_rom (
    input  logic        [3:0]  address,
    output logic signed [15:0] w_real,
    output logic signed [15:0] w_imag
);

// Q1.15 TWIDDLE CONSTANTS
always_comb begin
    case (address)
        4'd0: begin
            w_real = 16'sd32767;
            w_imag = 16'sd0;
        end
        4'd1: begin
            w_real = 16'sd32138;
            w_imag = -16'sd6393;
        end
        4'd2: begin
            w_real = 16'sd30274;
            w_imag = -16'sd12540;
        end
        4'd3: begin
            w_real = 16'sd27246;
            w_imag = -16'sd18205;
        end
        4'd4: begin
            w_real = 16'sd23170;
            w_imag = -16'sd23170;
        end
        4'd5: begin
            w_real = 16'sd18205;
            w_imag = -16'sd27246;
        end
        4'd6: begin
            w_real = 16'sd12540;
            w_imag = -16'sd30274;
        end
        4'd7: begin
            w_real = 16'sd6393;
            w_imag = -16'sd32138;
        end
        4'd8: begin
            w_real = 16'sd0;
            w_imag = 16'sh8000; // Exact -1 in Q1.15.
        end
        4'd9: begin
            w_real = -16'sd6393;
            w_imag = -16'sd32138;
        end
        4'd10: begin
            w_real = -16'sd12540;
            w_imag = -16'sd30274;
        end
        4'd11: begin
            w_real = -16'sd18205;
            w_imag = -16'sd27246;
        end
        4'd12: begin
            w_real = -16'sd23170;
            w_imag = -16'sd23170;
        end
        4'd13: begin
            w_real = -16'sd27246;
            w_imag = -16'sd18205;
        end
        4'd14: begin
            w_real = -16'sd30274;
            w_imag = -16'sd12540;
        end
        4'd15: begin
            w_real = -16'sd32138;
            w_imag = -16'sd6393;
        end
        default: begin
            w_real = 16'sd0;
            w_imag = 16'sd0;
        end
    endcase
end

endmodule
