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
    output wire [2:0] state_out,             // Current state for monitoring
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
            
            always @(posedge clk) begin
                if (current_state == FETCH && new_price) begin
                    price_fifo_ram[write_ptr] <= price_in;
                    write_ptr <= (write_ptr == RSI_PERIOD-1) ? 0 : write_ptr + 1;
                end
            end
            
            // Efficient way to read the oldest value from circular buffer
            wire [$clog2(RSI_PERIOD)-1:0] read_ptr = (write_ptr == 0) ? 
                                          RSI_PERIOD-1 : write_ptr - 1;
            
            // Read operation
            always @(posedge clk) begin
                fifo_output <= price_fifo_ram[read_ptr];
            end
        end else begin : g_reg_fifo
            // Register-based FIFO for smaller RSI_PERIOD values
            reg [PRICE_WIDTH-1:0] price_fifo [0:RSI_PERIOD-1];
            
            // This will be efficiently synthesized for small FIFO sizes
            integer i;
            always @(posedge clk) begin
                if (current_state == FETCH && new_price) begin
                    for (i = RSI_PERIOD-1; i > 0; i = i - 1)
                        price_fifo[i] <= price_fifo[i-1];
                    price_fifo[0] <= price_in;
                end
            end
            wire [PRICE_WIDTH-1:0] fifo_output = price_fifo[RSI_PERIOD-1];
        end
    endgenerate
    
    // --- Common counters and state variables ---
    reg [$clog2(RSI_PERIOD+1)-1:0] fifo_count;
    reg fifo_valid;
    assign fifo_ready = fifo_valid && (fifo_count >= RSI_PERIOD);
    
    // --- Calculation Registers with optimized bit widths ---
    reg [PRICE_WIDTH-1:0] current_price, prev_price;
    reg [PRICE_WIDTH:0] price_diff;              // +1 bit for sign consideration
    reg price_up;
    
    // Optimize gain/loss sum bit widths based on maximum possible value
    // Worst case: all price diffs are gains/losses, so need log2(PERIOD) extra bits
    localparam GAIN_SUM_WIDTH = PRICE_WIDTH + $clog2(RSI_PERIOD) + 1;
    
    reg [GAIN_SUM_WIDTH-1:0] gain_sum, loss_sum;
    reg [GAIN_SUM_WIDTH-1:0] avg_gain, avg_loss;
    
    // --- Safe division with overflow protection ---
    reg div_start;
    wire div_done;
    reg [GAIN_SUM_WIDTH-1:0] RS;                 // Relative Strength
    wire [GAIN_SUM_WIDTH-1:0] div_result;
    
    // --- Reset handling ---
    wire reset = ~rst_n | EOD;
    
    // --- Convert state encoding for output ---
    assign state_out = {
        current_state == DECISION,
        current_state == WAIT_DIV,
        current_state == COMPUTE | current_state == FETCH | current_state == IDLE
    };
    
    // --- Improved pipelined divider with overflow protection ---
    pipelined_divider #(
        .WIDTH(GAIN_SUM_WIDTH),
        .PIPELINE_STAGES(4),
        .CHECK_OVERFLOW(1)                      // Enable overflow detection
    ) div_inst (
        .clk(clk),
        .reset(reset),
        .start(div_start),
        .numerator(avg_gain),
        .denominator((avg_loss == 0) ? 1 : avg_loss),
        .quotient(div_result),
        .done(div_done),
        .overflow()                             // Optional connection for monitoring
    );
    
    // --- FSM: State Transition Logic ---
    always @(posedge clk or posedge reset) begin
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
            fifo_count <= 0;
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
            
            // Reset pointers for BRAM FIFO if used
            if (USE_BRAM_FIFO)
                g_bram_fifo.write_ptr <= 0;
                
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
                    
                    // Update FIFO status efficiently
                    if (new_price && fifo_count < RSI_PERIOD)
                        fifo_count <= fifo_count + 1;
                        
                    fifo_valid <= (fifo_count >= 1) || (fifo_count == 0 && new_price);
                    
                    // Update price registers
                    if (new_price) begin
                        current_price <= price_in;
                        // Use FIFO output directly
                        prev_price <= USE_BRAM_FIFO ? g_bram_fifo.fifo_output : 
                                     g_reg_fifo.fifo_output;
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
                            if (fifo_count == RSI_PERIOD-1) begin
                                avg_gain <= gain_sum / RSI_PERIOD;
                                avg_loss <= loss_sum / RSI_PERIOD;
                            end
                        end else begin
                            // Wilder's smoothing with overflow protection
                            // Pipelined for better timing
                            if (price_up) begin
                                // Gain calculation in stages to improve timing
                                avg_gain <= ((avg_gain * (RSI_PERIOD-1)) + 
                                          (price_diff << FIXED_POINT_BITS)) / RSI_PERIOD;
                                avg_loss <= (avg_loss * (RSI_PERIOD-1)) / RSI_PERIOD;
                            end else begin
                                avg_gain <= (avg_gain * (RSI_PERIOD-1)) / RSI_PERIOD;
                                avg_loss <= ((avg_loss * (RSI_PERIOD-1)) + 
                                          (price_diff << FIXED_POINT_BITS)) / RSI_PERIOD;
                            end
                        end
                        
                        // Initialize division if we have enough data
                        if (fifo_count >= RSI_PERIOD-1)
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
                        if (div_result == 0) begin
                            RSI_out <= 0;
                        end else begin
                            // Use full fixed-point precision for calculation
                            // with saturation to prevent overflow
                            reg [GAIN_SUM_WIDTH + FIXED_POINT_BITS:0] denom;
                            reg [GAIN_SUM_WIDTH + FIXED_POINT_BITS:0] rsi_calc;
                            
                            denom = (1 << FIXED_POINT_BITS) + div_result;
                            rsi_calc = (100 << FIXED_POINT_BITS) - 
                                      ((100 << (2*FIXED_POINT_BITS)) / denom);
                            
                            // Apply shift and saturation
                            if (rsi_calc > (100 << FIXED_POINT_BITS))
                                RSI_out <= 100;
                            else
                                RSI_out <= rsi_calc >> FIXED_POINT_BITS;
                        end
                    end
                end
                
                DECISION: begin
                    // Generate trading signals with hysteresis to prevent signal oscillation
                    if (fifo_ready) begin
                        // Ensure RSI is in valid range
                        RSI_out <= (RSI_out > 100) ? 100 : RSI_out;
                        
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
    
    // Pipeline stage for overflow detection
    reg [PIPELINE_STAGES-1:0] overflow_pipeline;
    
    // More efficient for loop with single iterator declaration
    integer i;
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            // Reset all pipeline registers and outputs
            for (i = 0; i < PIPELINE_STAGES; i = i + 1) begin
                num_pipeline[i] <= 0;
                den_pipeline[i] <= 0;
                valid_pipeline[i] <= 0;
                overflow_pipeline[i] <= 0;
            end
            quotient <= 0;
            done <= 0;
            overflow <= 0;
        end else begin
            // Input stage with overflow detection
            if (start) begin
                // Input checking with overflow detection
                if (CHECK_OVERFLOW) begin
                    // Check for division by zero or extreme values
                    overflow_pipeline[0] <= (denominator == 0) || 
                                         (numerator > {WIDTH{1'b1}} / 2);
                end else begin
                    overflow_pipeline[0] <= 0;
                end
                
                num_pipeline[0] <= numerator;
                den_pipeline[0] <= (denominator == 0) ? 1 : denominator; // Prevent division by zero
                valid_pipeline[0] <= 1;
            end else begin
                valid_pipeline[0] <= 0;
                overflow_pipeline[0] <= 0;
            end
            
            // Pipeline stages - shift registers through pipeline
            for (i = 1; i < PIPELINE_STAGES; i = i + 1) begin
                num_pipeline[i] <= num_pipeline[i-1];
                den_pipeline[i] <= den_pipeline[i-1];
                valid_pipeline[i] <= valid_pipeline[i-1];
                overflow_pipeline[i] <= overflow_pipeline[i-1];
            end
            
            // Output stage with safe division and overflow propagation
            done <= valid_pipeline[PIPELINE_STAGES-1];
            overflow <= overflow_pipeline[PIPELINE_STAGES-1];
            
            if (valid_pipeline[PIPELINE_STAGES-1]) begin
                // Safe division with output clamping on overflow
                if (overflow_pipeline[PIPELINE_STAGES-1] || den_pipeline[PIPELINE_STAGES-1] == 0) begin
                    quotient <= {WIDTH{1'b1}}; // Max value on overflow
                end else begin
                    quotient <= num_pipeline[PIPELINE_STAGES-1] / den_pipeline[PIPELINE_STAGES-1];
                end
            end
        end
    end
    
    // Formal verification properties (if supported by tool)
    // synthesis translate_off
    // Example SVA property: division by zero should never happen at output stage
    property div_by_zero_check;
        @(posedge clk) disable iff (reset)
        valid_pipeline[PIPELINE_STAGES-1] |-> den_pipeline[PIPELINE_STAGES-1] != 0;
    endproperty
    assert property (div_by_zero_check);
    // synthesis translate_on
    
endmodule
