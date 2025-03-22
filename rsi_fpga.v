module RSI_FSM (
    input wire clk,
    input wire reset,
    input wire [49:0] price_in,  // 50-bit input price
    input wire new_price,        // Signal when new price arrives
    input wire EOD,              // End of Day reset
    output reg [9:0] RSI_out,    // 10-bit RSI output
    output reg buy_signal,       // Buy decision
    output reg sell_signal       // Sell decision
);

    // --- FSM States ---
    // Using standard Verilog parameter definitions instead of SystemVerilog enum
    parameter [2:0] 
        IDLE = 3'b000,
        FETCH = 3'b001,
        COMPUTE = 3'b010,
        WAIT_DIV = 3'b011,
        DECISION = 3'b100,
        RESET = 3'b101;
    
    reg [2:0] current_state, next_state;

    // --- FIFO Parameters ---
    parameter FIFO_DEPTH = 14;  // Traditional RSI uses 14 periods
    parameter SMOOTH_FACTOR = 14;  // For proper averaging
    
    reg [49:0] price_fifo [FIFO_DEPTH-1:0]; // Store prices
    reg fifo_initialized;  // Track if FIFO has been filled
    reg [3:0] fifo_count;  // Track how many valid entries are in FIFO
    integer i;

    // --- RSI Calculation Registers ---
    reg [49:0] current_price, prev_price;
    reg [49:0] price_diff;
    reg price_increased;
    
    reg [63:0] gain_sum, loss_sum;  // Expanded bit width for accumulation
    reg [31:0] avg_gain, avg_loss;  // Expanded for precision
    
    reg [31:0] RS_numerator, RS_denominator;
    reg [31:0] RS;  // Expanded for better precision
    reg [9:0] RSI;  // Final RSI value
    
    // --- Division Module Control ---
    reg div_start;
    wire div_done;
    wire [31:0] div_result;

    // --- Division Module Instantiation ---
    pipelined_divider div_inst (
        .clk(clk),
        .reset(reset),
        .start(div_start),
        .numerator(RS_numerator),
        .denominator(RS_denominator),
        .quotient(div_result),
        .done(div_done)
    );

    // --- FSM State Transitions ---
    always @(posedge clk or posedge reset) begin
        if (reset || EOD)
            current_state <= RESET;
        else
            current_state <= next_state;
    end

    // --- FSM Next State Logic ---
    always @(*) begin
        case (current_state)
            IDLE: next_state = new_price ? FETCH : IDLE;
            FETCH: next_state = COMPUTE;
            COMPUTE: next_state = WAIT_DIV;
            WAIT_DIV: next_state = div_done ? DECISION : WAIT_DIV;
            DECISION: next_state = IDLE;
            RESET: next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end

    // --- FSM Operations ---
    always @(posedge clk) begin
        if (reset || EOD) begin
            // Reset logic
            for (i = 0; i < FIFO_DEPTH; i = i + 1) begin
                price_fifo[i] <= 0;
            end
            fifo_initialized <= 0;
            fifo_count <= 0;
            gain_sum <= 0;
            loss_sum <= 0;
            RSI_out <= 0;
            buy_signal <= 0;
            sell_signal <= 0;
            div_start <= 0;
        end else begin
            case (current_state)
                IDLE: begin
                    buy_signal <= 0;
                    sell_signal <= 0;
                    div_start <= 0;
                end
                
                FETCH: begin
                    // Shift FIFO and store new price
                    for (i = FIFO_DEPTH-1; i > 0; i = i - 1) begin
                        price_fifo[i] <= price_fifo[i-1];
                    end
                    price_fifo[0] <= price_in;
                    
                    // Track FIFO filling status
                    if (fifo_count < FIFO_DEPTH)
                        fifo_count <= fifo_count + 1;
                    
                    if (fifo_count >= 1) begin
                        fifo_initialized <= 1;
                        current_price <= price_in;
                        prev_price <= price_fifo[0]; // Previous price is now what was at position 0
                    end
                end
                
                COMPUTE: begin
                    if (fifo_initialized) begin
                        // Calculate price difference and determine if price increased
                        if (current_price > prev_price) begin
                            price_diff <= current_price - prev_price;
                            price_increased <= 1;
                        end else begin
                            price_diff <= prev_price - current_price;
                            price_increased <= 0;
                        end
                        
                        // Apply gain/loss calculation with proper smoothing
                        if (fifo_count < FIFO_DEPTH) begin
                            // During initial period collection
                            if (price_increased)
                                gain_sum <= gain_sum + price_diff;
                            else
                                loss_sum <= loss_sum + price_diff;
                                
                            if (fifo_count == FIFO_DEPTH-1) begin
                                // Initial averages at end of first period
                                avg_gain <= gain_sum / SMOOTH_FACTOR;
                                avg_loss <= loss_sum / SMOOTH_FACTOR;
                            end
                        end else begin
                            // After initial period, apply exponential smoothing
                            if (price_increased) begin
                                avg_gain <= ((avg_gain * (SMOOTH_FACTOR-1)) + price_diff) / SMOOTH_FACTOR;
                                avg_loss <= (avg_loss * (SMOOTH_FACTOR-1)) / SMOOTH_FACTOR;
                            end else begin
                                avg_gain <= (avg_gain * (SMOOTH_FACTOR-1)) / SMOOTH_FACTOR;
                                avg_loss <= ((avg_loss * (SMOOTH_FACTOR-1)) + price_diff) / SMOOTH_FACTOR;
                            end
                        end
                        
                        // Prepare for RS calculation
                        RS_numerator <= avg_gain;
                        RS_denominator <= (avg_loss == 0) ? 1 : avg_loss; // Avoid division by zero
                        div_start <= 1; // Start division process
                    end
                end
                
                WAIT_DIV: begin
                    div_start <= 0; // Clear start signal
                    if (div_done) begin
                        RS <= div_result;
                        
                        // RSI calculation using fixed-point arithmetic for better precision
                        // RSI = 100 - (100 / (1 + RS))
                        if (RS == 0)
                            RSI <= 0; // If RS is 0, RSI is 0
                        else
                            RSI <= 100 - ((100 << 8) / ((1 << 8) + RS)) >> 8;
                    end
                end
                
                DECISION: begin
                    if (fifo_initialized && fifo_count >= FIFO_DEPTH) begin
                        RSI_out <= RSI;
                        if (RSI < 30)
                            buy_signal <= 1;
                        else if (RSI > 70)
                            sell_signal <= 1;
                        else begin
                            buy_signal <= 0;
                            sell_signal <= 0;
                        end
                    end
                end
                
                RESET: begin
                    // Reset logic is handled in the outer if statement
                end
            endcase
        end
    end

endmodule

// --- Pipelined Division Module ---
module pipelined_divider (
    input wire clk,
    input wire reset,
    input wire start,
    input wire [31:0] numerator,
    input wire [31:0] denominator,
    output reg [31:0] quotient,
    output reg done
);
    // Simple 8-cycle pipelined divider
    parameter IDLE = 1'b0;
    parameter DIVIDING = 1'b1;
    
    reg state;
    reg [2:0] cycle_count;
    reg [31:0] num_reg, den_reg;
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            done <= 0;
            cycle_count <= 0;
            quotient <= 0;
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        state <= DIVIDING;
                        cycle_count <= 0;
                        num_reg <= numerator;
                        den_reg <= denominator;
                        done <= 0;
                    end
                end
                
                DIVIDING: begin
                    if (cycle_count < 7) begin
                        cycle_count <= cycle_count + 1;
                    end else begin
                        // Division completes after 8 cycles
                        quotient <= (den_reg != 0) ? num_reg / den_reg : 0;
                        done <= 1;
                        state <= IDLE;
                    end
                end
            endcase
        end
    end
endmodule
