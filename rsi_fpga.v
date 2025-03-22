module RSI_FSM #(
    parameter PRICE_WIDTH = 50,              // Width of price input
    parameter RSI_WIDTH = 10,                // Width of RSI output
    parameter RSI_PERIOD = 14,               // Standard RSI period
    parameter BUY_THRESHOLD = 30,            // RSI value to trigger buy
    parameter SELL_THRESHOLD = 70,           // RSI value to trigger sell
    parameter FIXED_POINT_BITS = 8,          // Precision bits for fixed-point math
    parameter USE_BRAM_FIFO = 1              // Set to 1 to use BlockRAM for FIFO (better for large RSI_PERIOD)
)(
    input wire clk,
    input wire rst_n,                        // Active-low reset
    input wire [PRICE_WIDTH-1:0] price_in,
    input wire new_price,
    input wire EOD,                          // End of Day signal
    output reg [RSI_WIDTH-1:0] RSI_out,
    output reg buy_signal,
    output reg sell_signal,
    // Additional outputs for debugging and monitoring
    output wire [4:0] state_out,             // FIX 3: Changed to 5 bits to match one-hot encoding
    output wire fifo_ready                   // Indicates FIFO has enough data
);

    // --- FSM States with one-hot encoding for better timing
    localparam [4:0]
        IDLE     = 5'b00001,
        FETCH    = 5'b00010,
        COMPUTE  = 5'b00100,
        WAIT_DIV = 5'b01000,
        DECISION = 5'b10000;

    reg [4:0] current_state, next_state;

    // --- FIFO implementation with efficient resource usage ---
    // FIFO registers or BlockRAM based on parameter
    generate
        if (USE_BRAM_FIFO) begin : g_bram_fifo
            // BlockRAM-based FIFO implementation
            reg [PRICE_WIDTH-1:0] price_fifo_ram [0:RSI_PERIOD-1];
            reg [$clog2(RSI_PERIOD)-1:0] write_ptr;
            reg [PRICE_WIDTH-1:0] fifo_output;

            // FIX 1: Added explicit management of fifo_count for BRAM FIFO
            reg [$clog2(RSI_PERIOD+1)-1:0] fifo_count_internal;

            always @(posedge clk) begin
                if (~rst_n || EOD) begin
                    write_ptr <= 0;
                    fifo_count_internal <= 0; // FIX: Reset count on reset
                end else if (current_state == FETCH && new_price) begin
                    // Improved FIFO Full Condition Handling for BRAM FIFO
                    price_fifo_ram[write_ptr] <= price_in;
                    write_ptr <= (write_ptr == RSI_PERIOD-1) ? 0 : write_ptr + 1;

                    // Update FIFO count
                    if (fifo_count_internal < RSI_PERIOD)
                        fifo_count_internal <= fifo_count_internal + 1;
                end
            end

            // Efficient way to read the oldest value from circular buffer
            wire [$clog2(RSI_PERIOD)-1:0] read_ptr = (fifo_count_internal < RSI_PERIOD) ?
                                          0 : ((write_ptr == 0) ? RSI_PERIOD-1 : write_ptr - 1);

            // Read operation - Registered output for timing improvement
            always @(posedge clk) begin
                if (current_state == FETCH || current_state == COMPUTE) // Keep output updated during relevant states
                    fifo_output <= price_fifo_ram[read_ptr];
            end

            // Connect internal count to module count
            assign fifo_count = fifo_count_internal;

        end else begin : g_reg_fifo
            // Register-based FIFO for smaller RSI_PERIOD values
            reg [PRICE_WIDTH-1:0] price_fifo [0:RSI_PERIOD-1];
            reg [$clog2(RSI_PERIOD+1)-1:0] fifo_count_internal;

            // This will be efficiently synthesized for small FIFO sizes
            integer i;
            always @(posedge clk) begin
                if (~rst_n || EOD) begin
                    for (i = 0; i < RSI_PERIOD; i = i + 1)
                        price_fifo[i] <= 0;
                    fifo_count_internal <= 0; // FIX: Reset count on reset
                end else if (current_state == FETCH && new_price) begin
                    // For register-based FIFO, shift register implementation
                    for (i = RSI_PERIOD-1; i > 0; i = i - 1)
                        price_fifo[i] <= price_fifo[i-1];
                    price_fifo[0] <= price_in;

                    // Update FIFO count
                    if (fifo_count_internal < RSI_PERIOD)
                        fifo_count_internal <= fifo_count_internal + 1;
                end
            end

            // Connect internal count to module count
            assign fifo_count = fifo_count_internal;

            // Using oldest value in FIFO for calculation
            wire [PRICE_WIDTH-1:0] fifo_output = price_fifo[RSI_PERIOD-1];
        end
    endgenerate

    // --- Common counters and state variables ---
    wire [$clog2(RSI_PERIOD+1)-1:0] fifo_count; // Changed to wire for generate block assignment
    reg fifo_valid;
    assign fifo_ready = fifo_valid && (fifo_count >= RSI_PERIOD);

    // --- Calculation Registers with optimized bit widths ---
    reg [PRICE_WIDTH-1:0] current_price, prev_price;
    reg [PRICE_WIDTH:0] price_diff;              // +1 bit for sign consideration
    reg price_up;

    // Optimize gain/loss sum bit widths based on maximum possible value
    // Worst case: all price diffs are gains/losses, so need log2(RSI_PERIOD) extra bits
    localparam GAIN_SUM_WIDTH = PRICE_WIDTH + $clog2(RSI_PERIOD) + 1;

    reg [GAIN_SUM_WIDTH-1:0] gain_sum, loss_sum;
    reg [GAIN_SUM_WIDTH-1:0] avg_gain, avg_loss;

    // --- Safe division with overflow protection ---
    reg div_start;
    wire div_done;
    reg [GAIN_SUM_WIDTH-1:0] RS_numerator, RS_denominator;
    reg [GAIN_SUM_WIDTH-1:0] RS;                 // Relative Strength
    wire [GAIN_SUM_WIDTH-1:0] div_result;

    // --- Reset handling ---
    wire reset = ~rst_n | EOD;

    // FIX 3: Output full state for better debugging
    assign state_out = current_state;

    // --- Improved pipelined divider with overflow protection ---
    pipelined_divider #(
        .WIDTH(GAIN_SUM_WIDTH),
        .PIPELINE_STAGES(4),
        .CHECK_OVERFLOW(1)                      // Enable overflow detection
    ) div_inst (
        .clk(clk),
        .reset(reset),
        .start(div_start),
        .numerator(RS_numerator),
        .denominator(RS_denominator),
        .quotient(div_result),
        .done(div_done),
        .overflow()                             // Optional connection for monitoring
    );

    // --- FSM: State Transition Logic ---
    // FIX: Simplified reset handling to avoid asynchronous paths
    always @(posedge clk) begin
        if (reset)
            current_state <= IDLE;
        else
            current_state <= next_state;
    end

    // --- FSM: Next State Logic with default assignments to avoid latches ---
    always @(*) begin
        next_state = current_state; // Default: stay in current state

        case (current_state)
            IDLE:     next_state = new_price ? FETCH : IDLE;
            FETCH:    next_state = COMPUTE;
            COMPUTE:  next_state = WAIT_DIV;
            WAIT_DIV: next_state = div_done ? DECISION : WAIT_DIV;
            DECISION: next_state = IDLE;
            default:  next_state = IDLE;
        endcase
    end

    // --- Main Processing Logic with pipelining for better timing ---
    always @(posedge clk) begin
        if (reset) begin
            // Reset with explicit initialization
            fifo_valid <= 0;
            gain_sum <= 0;
            loss_sum <= 0;
            RSI_out <= 0;
            buy_signal <= 0;
            sell_signal <= 0;
            div_start <= 0;
            current_price <= 0;
            prev_price <= 0;
            avg_gain <= 0;
            avg_loss <= 0;
        end else begin
            // Default signal states to prevent unwanted latches
            div_start <= 0;

            case (current_state)
                IDLE: begin
                    // Clear trading signals each cycle
                    buy_signal <= 0;
                    sell_signal <= 0;
                end

                FETCH: begin
                    // FIFO shifting happens in the generate block
                    fifo_valid <= (fifo_count >= 1) || (fifo_count == 0 && new_price);

                    // Update price registers
                    if (new_price) begin
                        prev_price <= current_price;
                        current_price <= price_in;
                    end
                end

                COMPUTE: begin
                    if (fifo_valid) begin
                        // Compute price difference with saturation to prevent overflow
                        price_up = (current_price > prev_price);

                        // Calculate difference with saturation
                        if (price_up) begin
                            // Price increase - check for overflow
                            if (current_price > {1'b0, prev_price})
                                price_diff <= current_price - prev_price;
                            else
                                price_diff <= {PRICE_WIDTH+1{1'b1}}; // Max value on overflow
                        end else begin
                            // Price decrease
                            if (prev_price > {1'b0, current_price})
                                price_diff <= prev_price - current_price;
                            else
                                price_diff <= {PRICE_WIDTH+1{1'b1}}; // Max value on overflow
                        end

                        // Split gain/loss logic for clarity and better timing
                        if (fifo_count < RSI_PERIOD) begin
                            // Initial accumulation phase
                            if (price_up) begin
                                gain_sum <= gain_sum + price_diff;
                            end else begin
                                loss_sum <= loss_sum + price_diff;
                            end

                            // Calculate initial averages at end of accumulation
                            if (fifo_count == RSI_PERIOD-1) begin // FIX: Use period-1 since we're checking before increment
                                avg_gain <= gain_sum / RSI_PERIOD;
                                avg_loss <= loss_sum / RSI_PERIOD;
                            end
                        end else begin
                            // Wilder's smoothing with overflow protection
                            // Pipelined for better timing
                            if (price_up) begin
                                avg_gain <= ((avg_gain * (RSI_PERIOD-1)) +
                                          (price_diff << FIXED_POINT_BITS)) / RSI_PERIOD; // FIX: Apply fixed-point scaling
                                avg_loss <= (avg_loss * (RSI_PERIOD-1)) / RSI_PERIOD;
                            end else begin
                                avg_gain <= (avg_gain * (RSI_PERIOD-1)) / RSI_PERIOD;
                                avg_loss <= ((avg_loss * (RSI_PERIOD-1)) +
                                          (price_diff << FIXED_POINT_BITS)) / RSI_PERIOD; // FIX: Apply fixed-point scaling
                            end
                        end

                        // Prepare for RS calculation
                        RS_numerator <= avg_gain;
                        RS_denominator <= (avg_loss == 0) ? 1 : avg_loss;
                        // Initialize division if we have enough data
                        if (fifo_count >= RSI_PERIOD)
                            div_start <= 1;
                    end
                end

                WAIT_DIV: begin
                    // Clear division start signal
                    div_start <= 0;

                    if (div_done) begin
                        RS <= div_result;

                        // More accurate fixed-point RSI calculation
                        // RSI = 100 - (100 / (1 + RS))
                        if (avg_loss == 0) begin
                            // FIX 2: RSI = 100 when avg_loss is zero (RS is effectively infinite)
                            RSI_out <= 100;
                        end else begin
                            // Use full fixed-point precision for calculation
                            // with saturation to prevent overflow
                            reg [GAIN_SUM_WIDTH + FIXED_POINT_BITS:0] denom;
                            reg [GAIN_SUM_WIDTH + RSI_WIDTH + FIXED_POINT_BITS:0] rsi_calc_full; // Increased width for intermediate calculation
                            reg [RSI_WIDTH-1:0] rsi_temp;

                            denom = (1 << FIXED_POINT_BITS) + div_result;
                            rsi_calc_full = (100 << FIXED_POINT_BITS) -
                                      ((100 << (2*FIXED_POINT_BITS)) / denom); // Corrected shift for 100

                            rsi_temp = rsi_calc_full >> FIXED_POINT_BITS;

                            // Apply saturation to RSI_out
                            if (rsi_temp > 100)
                                RSI_out <= 100;
                            else
                                RSI_out <= rsi_temp;
                        end
                    end
                end

                DECISION: begin
                    // Generate trading signals with configurable thresholds
                    if (fifo_ready) begin
                        // Generate signals with configurable thresholds
                        buy_signal <= (RSI_out < BUY_THRESHOLD);
                        sell_signal <= (RSI_out > SELL_THRESHOLD);
                    end
                end
            endcase
        end
    end

endmodule

// --- Enhanced Pipelined Divider with Overflow Detection ---
module pipelined_divider #(
    parameter WIDTH = 32,                    // Bit width of operands
    parameter PIPELINE_STAGES = 4,           // Number of pipeline stages
    parameter CHECK_OVERFLOW = 1             // Enable overflow checking
)(
    input wire clk,
    input wire reset,
    input wire start,
    input wire [WIDTH-1:0] numerator,
    input wire [WIDTH-1:0] denominator,
    output reg [WIDTH-1:0] quotient,
    output reg done,
    output reg overflow                      // Overflow indicator
);
    // Pipeline registers with optimized structure
    reg [WIDTH-1:0] num_pipeline [0:PIPELINE_STAGES-1];
    reg [WIDTH-1:0] den_pipeline [0:PIPELINE_STAGES-1];
    reg [PIPELINE_STAGES-1:0] valid_pipeline;
    reg [WIDTH*2-1:0] remainder_pipeline [0:PIPELINE_STAGES-1]; // Remainder for division

    // Pipeline stage for overflow detection
    reg [PIPELINE_STAGES-1:0] overflow_pipeline;

    // FIX: Improve division algorithm with proper bit counting
    reg [$clog2(WIDTH+1)-1:0] bit_count; // Counter for division bits
    reg state;
    localparam IDLE = 1'b0, DIVIDING = 1'b1;

    // More efficient for loop with single iterator declaration
    integer i;

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            // Reset all pipeline registers and outputs
            for (i = 0; i < PIPELINE_STAGES; i = i + 1) begin
                num_pipeline[i] <= 0;
                den_pipeline[i] <= 0;
                valid_pipeline[i] <= 0;
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
                    done <= 0; // Clear done signal in IDLE state

                    if (start) begin
                        state <= DIVIDING;
                        bit_count <= 0;

                        // FIX: Properly initialize division operation
                        // Check for division by zero
                        if (denominator == 0) begin
                            overflow <= 1;
                            quotient <= {WIDTH{1'b1}}; // Maximum value on division by zero
                            done <= 1;
                            state <= IDLE;
                        end else begin
                            // Initialize division operation
                            overflow <= 0;
                            // Setup initial remainder and quotient
                            quotient <= 0;
                            // Initialize remainder with numerator in lower half
                            remainder_pipeline[0] <= {WIDTH'b0, numerator};
                            // Store denominator for division
                            den_pipeline[0] <= denominator;
                        end
                    end
                end

                DIVIDING: begin
                    // FIX: Improved division algorithm
                    if (bit_count < WIDTH) begin
                        // Shift remainder left by 1 bit
                        remainder_pipeline[0] <= remainder_pipeline[0] << 1;

                        // Check if we can subtract denominator
                        if (remainder_pipeline[0][WIDTH*2-1:WIDTH] >= den_pipeline[0]) begin
                            remainder_pipeline[0][WIDTH*2-1:WIDTH] <=
                                remainder_pipeline[0][WIDTH*2-1:WIDTH] - den_pipeline[0];
                            quotient <= (quotient << 1) | 1'b1;
                        else
                            quotient <= quotient << 1;
                        end

                        bit_count <= bit_count + 1;

                        // If this is the last bit, signal completion
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
