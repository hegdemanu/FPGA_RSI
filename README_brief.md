# FPGA_RSI
# RSI FPGA Implementation

## Overview
This repository contains a complete Verilog implementation of the Relative Strength Index (RSI) trading indicator for FPGAs. The design focuses on accuracy and FPGA-friendly implementation with proper pipelining, state management, and trading decision logic.

## Features
- **Complete RSI calculation** with proper exponential smoothing
- **Finite State Machine (FSM)** control for robust operation
- **Pipelined division module** for efficient FPGA resource utilization
- **14-period RSI** implementation (standard for trading)
- **Trading signals** generation (buy/sell based on RSI thresholds)
- **End-of-Day (EOD) reset** capability
- **50-bit price input** support for high-precision market data

## Module Structure

### Main Components
1. **RSI_FSM Module**: Core implementation with FSM control
2. **Pipelined Divider**: Multi-cycle division operation for RS calculation

### FSM States
- **IDLE**: Waiting for new price data
- **FETCH**: Loading price data into FIFO
- **COMPUTE**: Calculating price differences, gains/losses
- **WAIT_DIV**: Waiting for division operation to complete
- **DECISION**: Generating buy/sell signals based on RSI
- **RESET**: Resetting all calculations (manual or EOD)

## Signal Interface

### Inputs
- `clk`: System clock
- `reset`: Asynchronous reset
- `price_in[49:0]`: 50-bit price input
- `new_price`: Flag indicating new price data is available
- `EOD`: End-of-Day reset signal

### Outputs
- `RSI_out[9:0]`: 10-bit RSI value output (0-100)
- `buy_signal`: Trading buy signal (RSI < 30)
- `sell_signal`: Trading sell signal (RSI > 70)

## Implementation Details

### RSI Calculation
The implementation follows the standard RSI formula:
```
RSI = 100 - (100 / (1 + RS))
```
Where `RS` is the ratio of average gain to average loss over the specified period.

### Key Technical Features
1. **Proper Initialization**: Tracks FIFO filling status before generating signals
2. **Exponential Smoothing**: Uses proper EMA calculation after initial period
3. **Fixed-Point Arithmetic**: Enhanced precision for accurate RSI calculation
4. **Multi-Cycle Division**: Pipelined division for optimal FPGA implementation
5. **Edge Case Handling**: Properly handles division by zero and other edge cases

## Usage

### Integration
Include both the `RSI_FSM` and `pipelined_divider` modules in your project. Connect the inputs and outputs according to your system's requirements.

### Clock Domain
Ensure the module operates in a stable clock domain. The division operation takes 8 clock cycles to complete.

### Synthesis Considerations
- Target FPGA: Compatible with most FPGA families
- Resource usage: Moderate (primarily registers and LUTs)
- Timing: Critical path typically in the division operation

## Testing Recommendations
1. Test with various market conditions (trending up/down, ranging)
2. Verify correct RSI calculation against software reference
3. Test edge cases (zero prices, identical sequential prices)
4. Verify proper trading signal generation

## Customization
- Modify `FIFO_DEPTH` to change the RSI period (default: 14)
- Adjust buy/sell thresholds in the DECISION state (default: 30/70)
- Modify the division latency in the pipelined divider for resource/speed tradeoffs

## License
[Insert your preferred license information here]

## Acknowledgments
This implementation incorporates best practices for FPGA-based financial indicator calculation with a focus on accuracy and resource efficiency.
