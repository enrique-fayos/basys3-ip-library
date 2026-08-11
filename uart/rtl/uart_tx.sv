module uart_tx #(
    parameter int unsigned CLK_FREQ = 100_000_000,
    parameter int unsigned BAUD_RATE = 115200
)(
    input logic clk,
    input logic rst_n,
    input logic start,
    input logic [7:0] data_in,

    output logic tx,
    output logic busy
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

//SEQUENTIAL LOGIC
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= IDLE;
        data_reg <= 8'd0;
        bit_count <= 3'd0;
        baud_count <= '0;

    end else begin
        state <= next_state;

        if (state == IDLE) begin
            bit_count <= 3'd0;
            baud_count <= '0;
            if (start) begin
                data_reg <= data_in;
            end

        end else if (baud_count == CLKS_PER_BIT - 1) begin
            baud_count <= '0;
            if (state == DATA_BITS && bit_count < 3'd7) begin
                bit_count <= bit_count + 3'd1;
            end
            
        end else begin
            baud_count <= baud_count + 1'b1;
        end
    end
end

//NEXT-STATE AND OUTPUT LOGIC
always_comb begin
    next_state = state;
    tx = 1'b1;
    busy = 1'b0;
    case(state)
        IDLE: begin
            tx = 1'b1;
            busy = 1'b0;
            if (start) begin
                next_state = START_BIT;
            end
        end
        START_BIT: begin
            tx = 1'b0;
            busy = 1'b1;
            if (baud_count == CLKS_PER_BIT - 1) begin
                next_state = DATA_BITS;
            end
        end
        DATA_BITS: begin
            tx = data_reg[bit_count];
            busy = 1'b1;
            if ((baud_count == CLKS_PER_BIT - 1) && (bit_count == 3'd7)) begin
                next_state = STOP_BIT;
            end
        end
        STOP_BIT: begin
            tx = 1'b1;
            busy = 1'b1;
            if (baud_count == CLKS_PER_BIT - 1) begin
                next_state = IDLE;
            end
        end
        default: begin
            next_state = IDLE;
            tx = 1'b1;
            busy = 1'b0;
        end
    endcase
end

endmodule