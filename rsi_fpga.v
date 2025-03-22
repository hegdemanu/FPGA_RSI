`timescale 1ns/1ps
module RSI_FSM #(
    parameter PRICE_WIDTH       = 50,    // Width of price input
    parameter RSI_WIDTH         = 10,    // Width of RSI output
    parameter RSI_PERIOD        = 14,    // Standard RSI period
    parameter BUY_THRESHOLD     = 30,    // RSI value to trigger buy
    parameter SELL_THRESHOLD    = 70,    // RSI value to trigger sell
    parameter FIXED_POINT_BITS  = 8,     // Precision bits for fixed-point math
    parameter USE_BRAM_FIFO     = 1      // Set to 1 to use BlockRAM for FIFO
)(
    input  wire                   clk,
    input  wire                   rst_n,   // Active-low reset
    input  wire [PRICE_WIDTH-1:0] price_in,
    input  wire                   new_price,
    input  wire                   EOD,     // End of Day signal
    output reg  [RSI_WIDTH-1:0]   RSI_out,
    output reg                  buy_signal,
    output reg                  sell_signal,
    // Debug/monitor outputs
    output wire [4:0]           state_out,  // One-hot state output
    output wire                 fifo_ready  // Indicates FIFO has enough data
);

    // --- FSM States (One-hot encoding) ---
    localparam [4:0]
        IDLE     = 5'b00001,
        FETCH    = 5'b00010,
        COMPUTE  = 5'b00100,
        WAIT_DIV = 5'b01000,
        DECISION = 5'b10000;

    reg [4:0] current_state, next_state;

    // --- FIFO Implementation ---
    // FIFO count is driven from either FIFO implementation
    wire [$clog2(RSI_PERIOD+1)-1:0] fifo_count;
    generate
        if (USE_BRAM_FIFO) begin : g_bram_fifo
            // BlockRAM-based FIFO
            reg [PRICE_WIDTH-1:0] price_fifo_ram [0:RSI_PERIOD-1];
            reg [$clog2(RSI_PERIOD)-1:0] write_ptr;
            reg [$clog2(RSI_PERIOD+1)-1:0] fifo_count_internal;
            // (Optional) A registered output for reading the oldest value
            reg [PRICE_WIDTH-1:0] fifo_output_reg;

            always @(posedge clk) begin
                if (~rst_n || EOD) begin
                    write_ptr <= 0;
                    fifo_count_internal <= 0;
                end else if (current_state == FETCH && new_price) begin
                    price_fifo_ram[write_ptr] <= price_in;
                    write_ptr <= (write_ptr == RSI_PERIOD-1) ? 0 : write_ptr + 1;
                    if (fifo_count_internal < RSI_PERIOD)
                        fifo_count_internal <= fifo_count_internal + 1;
                end
            end

            // Compute read pointer (oldest entry)
            wire [$clog2(RSI_PERIOD)-1:0] read_ptr = (fifo_count_internal < RSI_PERIOD) ?
                                                     0 : ((write_ptr == 0) ? RSI_PERIOD-1 : write_ptr - 1);

            always @(posedge clk) begin
                if (current_state == FETCH || current_state == COMPUTE)
                    fifo_output_reg <= price_fifo_ram[read_ptr];
            end

            assign fifo_count = fifo_count_internal;
        end else begin : g_reg_fifo
            // Register-based FIFO for smaller RSI_PERIOD values
            reg [PRICE_WIDTH-1:0] price_fifo [0:RSI_PERIOD-1];
            reg [$clog2(RSI_PERIOD+1)-1:0] fifo_count_internal;
            integer i;
            always @(posedge clk) begin
                if (~rst_n || EOD) begin
                    for (i = 0; i < RSI_PERIOD; i = i + 1)
                        price_fifo[i] <= 0;
                    fifo_count_internal <= 0;
                end else if (current_state == FETCH && new_price) begin
                    for (i = RSI_PERIOD-1; i > 0; i = i - 1)
                        price_fifo[i] <= price_fifo[i-1];
                    price_fifo[0] <= price_in;
                    if (fifo_count_internal < RSI_PERIOD)
                        fifo_count_internal <= fifo_count_internal + 1;
                end
            end
            assign fifo_count = fifo_count_internal;
        end
    endgenerate

    // --- Common Counters and State Variables ---
    reg fifo_valid;
    assign fifo_ready = fifo_valid && (fifo_count >= RSI_PERIOD);

    reg [PRICE_WIDTH-1:0] current_price, prev_price;
    reg [PRICE_WIDTH:0] price_diff;   // +1 bit for possible overflow/saturation
    reg price_up;

    localparam GAIN_SUM_WIDTH = PRICE_WIDTH + $clog2(RSI_PERIOD) + 1;
    reg [GAIN_SUM_WIDTH-1:0] gain_sum, loss_sum;
    reg [GAIN_SUM_WIDTH-1:0] avg_gain, avg_loss;

    // --- Divider Signals ---
    reg div_start;
    wire div_done;
    reg [GAIN_SUM_WIDTH-1:0] RS_numerator, RS_denominator;
    reg [GAIN_SUM_WIDTH-1:0] RS;
    wire [GAIN_SUM_WIDTH-1:0] div_result;

    // --- Intermediate Signals for RSI Calculation ---
    reg [GAIN_SUM_WIDTH + FIXED_POINT_BITS:0] denom;
    reg [GAIN_SUM_WIDTH + RSI_WIDTH + FIXED_POINT_BITS:0] rsi_calc_full;
    reg [RSI_WIDTH-1:0] rsi_temp;

    // --- Reset Signal ---
    wire reset = ~rst_n | EOD;

    // --- Output state for debugging ---
    assign state_out = current_state;

    // --- Pipelined Divider Instance ---
    pipelined_divider #(
        .WIDTH(GAIN_SUM_WIDTH),
        .PIPELINE_STAGES(4),
        .CHECK_OVERFLOW(1)
    ) div_inst (
        .clk(clk),
        .reset(reset),
        .start(div_start),
        .numerator(RS_numerator),
        .denominator(RS_denominator),
        .quotient(div_result),
        .done(div_done),
        .overflow()  // Overflow output (unused)
    );

    // --- FSM State Register ---
    always @(posedge clk) begin
        if (reset)
            current_state <= IDLE;
        else
            current_state <= next_state;
    end

    // --- FSM Next-State Logic ---
    always @(*) begin
        next_state = current_state;  // Default assignment
        case (current_state)
            IDLE:     next_state = new_price ? FETCH : IDLE;
            FETCH:    next_state = COMPUTE;
            COMPUTE:  next_state = WAIT_DIV;
            WAIT_DIV: next_state = div_done ? DECISION : WAIT_DIV;
            DECISION: next_state = IDLE;
            default:  next_state = IDLE;
        endcase
    end

    // --- Main FSM Processing ---
    always @(posedge clk) begin
        if (reset) begin
            fifo_valid  <= 0;
            gain_sum    <= 0;
            loss_sum    <= 0;
            RSI_out     <= 0;
            buy_signal  <= 0;
            sell_signal <= 0;
            div_start   <= 0;
            current_price <= 0;
            prev_price    <= 0;
            avg_gain    <= 0;
            avg_loss    <= 0;
        end else begin
            div_start <= 0;  // Default: clear div_start each cycle

            case (current_state)
                IDLE: begin
                    buy_signal  <= 0;
                    sell_signal <= 0;
                end

                FETCH: begin
                    fifo_valid <= (fifo_count >= 1) || ((fifo_count == 0) && new_price);
                    if (new_price) begin
                        prev_price   <= current_price;
                        current_price <= price_in;
                    end
                end

                COMPUTE: begin
                    if (fifo_valid) begin
                        // Determine price direction and compute difference
                        price_up = (current_price > prev_price);
                        if (price_up) begin
                            if (current_price > prev_price)
                                price_diff <= current_price - prev_price;
                            else
                                price_diff <= {PRICE_WIDTH+1{1'b1}};  // Saturation on overflow
                        end else begin
                            if (prev_price > current_price)
                                price_diff <= prev_price - current_price;
                            else
                                price_diff <= {PRICE_WIDTH+1{1'b1}};
                        end

                        // Accumulate gains/losses (initial accumulation vs. smoothing)
                        if (fifo_count < RSI_PERIOD) begin
                            if (price_up)
                                gain_sum <= gain_sum + price_diff;
                            else
                                loss_sum <= loss_sum + price_diff;
                            if (fifo_count == RSI_PERIOD-1) begin
                                avg_gain <= gain_sum / RSI_PERIOD;
                                avg_loss <= loss_sum / RSI_PERIOD;
                            end
                        end else begin
                            if (price_up) begin
                                avg_gain <= ((avg_gain * (RSI_PERIOD-1)) +
                                             (price_diff << FIXED_POINT_BITS)) / RSI_PERIOD;
                                avg_loss <= (avg_loss * (RSI_PERIOD-1)) / RSI_PERIOD;
                            end else begin
                                avg_gain <= (avg_gain * (RSI_PERIOD-1)) / RSI_PERIOD;
                                avg_loss <= ((avg_loss * (RSI_PERIOD-1)) +
                                             (price_diff << FIXED_POINT_BITS)) / RSI_PERIOD;
                            end
                        end

                        // Prepare for RS calculation
                        RS_numerator <= avg_gain;
                        RS_denominator <= (avg_loss == 0) ? 1 : avg_loss;
                        if (fifo_count >= RSI_PERIOD)
                            div_start <= 1;
                    end
                end

                WAIT_DIV: begin
                    // Clear division start signal
                    div_start <= 0;
                    if (div_done) begin
                        RS <= div_result;
                        // Fixed-point RSI calculation: RSI = 100 - (100 / (1 + RS))
                        if (avg_loss == 0) begin
                            RSI_out <= 100;
                        end else begin
                            denom       <= (1 << FIXED_POINT_BITS) + div_result;
                            rsi_calc_full <= (100 << FIXED_POINT_BITS) - ((100 << (2*FIXED_POINT_BITS)) / denom);
                            rsi_temp    <= rsi_calc_full >> FIXED_POINT_BITS;
                            if (rsi_temp > 100)
                                RSI_out <= 100;
                            else
                                RSI_out <= rsi_temp;
                        end
                    end
                end

                DECISION: begin
                    if (fifo_ready) begin
                        buy_signal  <= (RSI_out < BUY_THRESHOLD);
                        sell_signal <= (RSI_out > SELL_THRESHOLD);
                    end
                end
            endcase
        end
    end

endmodule

// --- Enhanced Pipelined Divider with Overflow Detection ---
module pipelined_divider #(
    parameter WIDTH = 32,            // Bit width of operands
    parameter PIPELINE_STAGES = 4,   // Number of pipeline stages
    parameter CHECK_OVERFLOW = 1     // Enable overflow checking
)(
    input  wire             clk,
    input  wire             reset,
    input  wire             start,
    input  wire [WIDTH-1:0] numerator,
    input  wire [WIDTH-1:0] denominator,
    output reg  [WIDTH-1:0] quotient,
    output reg            done,
    output reg            overflow  // Overflow indicator
);

    // Pipeline registers and control signals
    reg [WIDTH-1:0] num_pipeline [0:PIPELINE_STAGES-1];
    reg [WIDTH-1:0] den_pipeline [0:PIPELINE_STAGES-1];
    reg [PIPELINE_STAGES-1:0] valid_pipeline;
    reg [WIDTH*2-1:0] remainder_pipeline [0:PIPELINE_STAGES-1];
    reg [PIPELINE_STAGES-1:0] overflow_pipeline;
    reg [$clog2(WIDTH+1)-1:0] bit_count;  // Counter for division bits
    reg state;
    localparam IDLE = 1'b0, DIVIDING = 1'b1;
    integer i;

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            for (i = 0; i < PIPELINE_STAGES; i = i + 1) begin
                num_pipeline[i]      <= 0;
                den_pipeline[i]      <= 0;
                valid_pipeline[i]    <= 0;
                overflow_pipeline[i] <= 0;
                remainder_pipeline[i] <= 0;
            end
            quotient <= 0;
            done <= 0;
            overflow <= 0;
            bit_count <= 0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 0;
                    if (start) begin
                        if (denominator == 0) begin
                            overflow <= 1;
                            quotient <= {WIDTH{1'b1}};
                            done <= 1;
                            state <= IDLE;
                        end else begin
                            state <= DIVIDING;
                            bit_count <= 0;
                            overflow <= 0;
                            quotient <= 0;
                            // Initialize remainder with numerator in lower half
                            remainder_pipeline[0] <= { {WIDTH{1'b0}}, numerator };
                            den_pipeline[0] <= denominator;
                        end
                    end
                end

                DIVIDING: begin
                    if (bit_count < WIDTH) begin
                        remainder_pipeline[0] <= remainder_pipeline[0] << 1;
                        if (remainder_pipeline[0][WIDTH*2-1:WIDTH] >= den_pipeline[0]) begin
                            remainder_pipeline[0][WIDTH*2-1:WIDTH] <= remainder_pipeline[0][WIDTH*2-1:WIDTH] - den_pipeline[0];
                            quotient <= (quotient << 1) | 1'b1;
                        end else begin
                            quotient <= quotient << 1;
                        end
                        bit_count <= bit_count + 1;
                        if (bit_count == WIDTH-1) begin
                            done <= 1;
                            state <= IDLE;
                        end
                    end
                end
            endcase
        end
    end
endmodule
