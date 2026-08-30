// =============================================================================
// Module: uart_rx
// Author: Enrique Fayos Gimeno
// Date: 2026-08-19
//
// Description:
//   UART receiver with configurable clock frequency and baud rate.
//   Receives 8-bit data using the 8N1 format, LSB first.
//   Includes a two-flip-flop synchronizer for the asynchronous RX input.
//
// Interface:
//   rx         - UART serial input, idle-high.
//   data_out   - Last successfully received 8-bit data.
//   data_valid - One-clock pulse when a new valid byte has been received.
//
// Reset:
//   Active-low asynchronous reset.
//
// Default configuration:
//   Clock:     100 MHz
//   Baud rate: 115200
// =============================================================================

module uart_rx #(
    parameter int unsigned CLK_FREQ = 100_000_000,
    parameter int unsigned BAUD_RATE = 115200
)(
    input logic clk,
    input logic rst_n,
    input logic rx,

    output logic [7:0] data_out,
    output logic data_valid
);

// UART TIMING
localparam int unsigned CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
localparam int unsigned BAUD_COUNTER_WIDTH = $clog2(CLKS_PER_BIT);

// FSM STATES
typedef enum logic [1:0] {
    IDLE,
    START_BIT,
    DATA_BITS,
    STOP_BIT
} state_t;

state_t state, next_state;

// INTERNAL REGISTERS
logic [2:0] bit_count;
logic [7:0] data_reg;
logic [BAUD_COUNTER_WIDTH-1:0] baud_count;

// RX SYNCHRONIZER
logic rx_meta;
logic rx_sync;

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rx_meta <= 1'b1;
        rx_sync <= 1'b1;
    end else begin
        rx_meta <= rx;
        rx_sync <= rx_meta;
    end
end

// STATE REGISTER
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= IDLE;
    end else begin
        state <= next_state;
    end
end

// DATAPATH REGISTER
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        baud_count <= '0;
        bit_count <= 3'd0;
        data_reg <= 8'd0;
        data_out <= 8'd0;
        data_valid <= 1'b0;
    end else begin
        data_valid <= 1'b0;
        case (state)
            IDLE: begin
                baud_count <= '0;
                bit_count  <= 3'd0;
            end
            START_BIT: begin
                if (baud_count == CLKS_PER_BIT/2 -1) begin
                    baud_count <= '0;
                end else begin
                    baud_count <= baud_count + 1'b1;
                end
            end
            DATA_BITS: begin
                if (baud_count == CLKS_PER_BIT - 1) begin
                    baud_count <= '0;
                    data_reg[bit_count] <= rx_sync;
                    if (bit_count < 3'd7) begin
                        bit_count <= bit_count + 1'b1;
                    end
                end else begin
                    baud_count <= baud_count + 1'b1;
                end
            end
            STOP_BIT: begin
                if (baud_count == CLKS_PER_BIT - 1) begin
                    baud_count <= '0;
                    if (rx_sync == 1'b1) begin
                        data_out <= data_reg;
                        data_valid <= 1'b1;
                    end
                end else begin
                    baud_count <= baud_count + 1'b1;
                end
            end
            default: begin
                baud_count <= '0;
                bit_count  <= 3'd0;
            end
        endcase
    end
end

// NEXT-STATE LOGIC
always_comb begin
    next_state = state;
    case (state)
        IDLE: begin
            if (rx_sync == 1'b0) begin
                next_state = START_BIT;
            end
        end
        START_BIT: begin
            if (baud_count == CLKS_PER_BIT/2 - 1) begin
                if (rx_sync == 1'b0) begin
                    next_state = DATA_BITS;
                end else begin
                    next_state = IDLE;
                end
            end
        end
        DATA_BITS: begin
            if ((baud_count == CLKS_PER_BIT - 1) && (bit_count == 3'd7)) begin
                next_state = STOP_BIT;
            end
        end
        STOP_BIT: begin
            if (baud_count == CLKS_PER_BIT - 1) begin
                next_state = IDLE;
            end
        end
        default: begin
            next_state = IDLE;
        end
    endcase
end

// synthesis translate_off

// ASSERTIONS
// During reset, the receiver should be inactive
assert_reset_idle:
assert property (
    @(posedge clk)
    !rst_n |-> (state == IDLE && data_valid == 1'b0))
    else $error("[%0t] UART RX is not idle during reset", $time);

// A detected start bit should move the receiver to START_BIT
assert_start_detected:
assert property (
    @(posedge clk)
    disable iff (!rst_n)
    (state == IDLE && rx_sync == 1'b0)
    |=> (state == START_BIT))
    else $error("[%0t] UART RX did not enter START_BIT", $time);

// A valid stop bit should generate data_valid
assert_valid_stop:
assert property (
    @(posedge clk)
    disable iff (!rst_n)
    (state == STOP_BIT && baud_count == CLKS_PER_BIT - 1 && rx_sync == 1'b1) 
    |=> data_valid)
    else $error("[%0t] UART RX did not assert data_valid after valid stop bit", $time);

// data_valid should only last one clock cycle
assert_data_valid_pulse:
assert property (
    @(posedge clk)
    disable iff (!rst_n)
    data_valid |=> !data_valid)
    else $error("[%0t] UART RX data_valid lasted more than one clock cycle", $time);

// synthesis translate_on

endmodule