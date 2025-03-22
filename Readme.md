
---

# 🚀 RSI FSM Implementation in FPGA (Verilog)

## 📚 **Project Overview**
This project implements a **Relative Strength Index (RSI) calculation FSM** in Verilog for FPGA-based trading systems. It processes incoming price data and generates trading signals based on RSI thresholds. The system uses a **Finite State Machine (FSM)** to manage data fetching, RSI computation, and decision-making efficiently. A **pipelined division module** ensures accurate division with configurable latency.

---

## 🎯 **Objectives**
- ✅ Compute 14-period RSI using price input data.  
- ✅ Generate **buy/sell signals** based on RSI thresholds.  
- ✅ Implement FSM for data fetching, computation, and decision-making.  
- ✅ Ensure FPGA-friendly implementation with clock-cycle-controlled operations.  
- ✅ Handle End-of-Day (EOD) reset and initialization of FIFO.  
- ✅ Implement fixed-point arithmetic for enhanced precision.
- ✅ Support both register-based and BlockRAM-based FIFO implementations.
- ✅ Provide debugging outputs for system monitoring.

---

## 🛠️ **System Design Overview**
### ⚡ **FSM States (One-Hot Encoded)**
- `IDLE` – Waits for new price input.  
- `FETCH` – Retrieves price and updates FIFO.  
- `COMPUTE` – Calculates gain/loss and averages.  
- `WAIT_DIV` – Initiates RS calculation using the division module.  
- `DECISION` – Generates buy/sell signals based on RSI value.  

---

## 📡 **Signal Descriptions**
| Signal Name     | Direction | Width  | Description                                  |
|----------------|-----------|--------|----------------------------------------------|
| `clk`           | Input     | 1 bit  | Clock signal controlling FSM operation      |
| `rst_n`         | Input     | 1 bit  | Active\-low asynchronous reset               |
| `price_in`      | Input     | 50 bits| New price data input                        |
| `new_price`     | Input     | 1 bit  | Signal indicating arrival of new price      |
| `EOD`           | Input     | 1 bit  | End\-of\-Day reset signal                     |
| `RSI_out`       | Output    | 10 bits| Computed RSI output                         |
| `buy_signal`    | Output    | 1 bit  | Buy decision signal                         |
| `sell_signal`   | Output    | 1 bit  | Sell decision signal                        |
| `state_out`     | Output    | 3 bits | Current FSM state for monitoring            |
| `fifo_ready`    | Output    | 1 bit  | Indicates FIFO has enough data              |
| `div_start`     | Internal  | 1 bit  | Start signal for division                   |
| `div_done`      | Internal  | 1 bit  | Completion flag for division                |
| `div_result`    | Internal  | Param  | Division result                             |
| `gain_sum`      | Internal  | Param  | Accumulated gain for RSI calculation        |
| `loss_sum`      | Internal  | Param  | Accumulated loss for RSI calculation        |
| `avg_gain`      | Internal  | Param  | Average gain with enhanced precision        |
| `avg_loss`      | Internal  | Param  | Average loss with enhanced precision        |

---

## 📝 **Core Components**
### 1️⃣ **FSM Controller**
- Implements one\-hot state encoding for improved timing.
- Handles price fetching, RSI computation, and decision\-making.  
- Ensures sequential processing of states to maintain FSM integrity.  
- Manages FIFO initialization tracking to prevent invalid calculations.  

### 2️⃣ **Configurable Price FIFO**
- Supports both register\-based and BlockRAM\-based implementations.
- 14\-entry FIFO stores price history (configurable via parameter).  
- Tracks initialization status to ensure valid data before computation.  
- Maintains count of valid entries for proper calculation initiation.  

### 3️⃣ **RSI Calculation Block**
- Computes gain and loss for each period.  
- Uses exponential smoothing for average gain/loss.  
- Implements fixed\-point arithmetic for enhanced calculation precision.  
- Includes overflow protection and saturation logic for reliability.

### 4️⃣ **Pipelined Divider**
- Configurable pipeline stages for division operation.
- Prevents division by zero using denominator checks.  
- Includes overflow detection and handling.
- Controlled via start/done handshaking for reliable operation.  

---

## 🧠 **RSI Computation Formula**

The RSI is computed using the following formulas:

$$
RS = \frac{\text{Average Gain}}{\text{Average Loss}}
$$

$$
RSI = 100 - \frac{100}{1 + RS}
$$

### **Smoothing Formula**

$$
\text{New Avg Gain} = \frac{(13 \times \text{Prev Avg Gain}) + \text{Current Gain}}{14}
$$

$$
\text{New Avg Loss} = \frac{(13 \times \text{Prev Avg Loss}) + \text{Current Loss}}{14}
$$

---


---

## 📏 **Fixed-Point Implementation**
- Uses bit-shifting for enhanced precision in RSI calculation.  
- Implements the formula:

\[
\text{RSI} = 100 - \left( \frac{100 \times 2^{\text{FIXED\_POINT\_BITS}}}{2^{\text{FIXED\_POINT\_BITS}} + RS} \right) \div 2^{\text{FIXED\_POINT\_BITS}}
\]

- Configurable fixed-point precision bits.  
- Includes saturation logic to prevent overflow.

---

## 🧠 **RSI Computation Formula**
The RSI is computed using the following formula:

\[
RS = \frac{\text{Average Gain}}{\text{Average Loss}}
\]

\[
RSI = 100 - \frac{100}{1 + RS}
\]

### **Smoothing Formula**
\[
\text{New Avg Gain} = \frac{(13 \times \text{Prev Avg Gain}) + \text{Current Gain}}{14}
\]
\[
\text{New Avg Loss} = \frac{(13 \times \text{Prev Avg Loss}) + \text{Current Loss}}{14}
\]

---

## 🔥 **Pipelined Divider Implementation**
- The divider uses configurable pipeline stages for division.
- Prevents zero division errors by checking denominators.
- Overflow detection and handling are built-in.
- Configured with formal verification properties to ensure division correctness.

### **Division Formula**
\[
\text{Quotient} = \frac{\text{Numerator}}{\text{Denominator}}
\]

---

## 📦 **File Structure**
```
📂 RSI_FPGA
├── 📄 rsi_fpga.v               # Complete implementation with FSM and divider
└── 📄 README.md                # Project documentation
```

---

## 🧪 **Test Bench Guidelines**
1. **Initial Reset:** Apply a reset for 2 clock cycles.  
2. **Feed Price Data:** Simulate new price data with `new_price` high.  
3. **Wait States:** Allow sufficient cycles for division completion.  
4. **FIFO Initialization:** Provide at least 14 price entries before expecting valid RSI.  
5. **Check RSI Values:** Validate RSI output after sufficient price entries.  
6. **Test Buy/Sell Conditions:** Confirm buy/sell signals at RSI < 30 and RSI > 70.  
7. **Monitor Debug Signals:** Check `state_out` and `fifo_ready` signals.

---

## 📊 **Configuration Parameters**
- **PRICE\_WIDTH:** Width of price input (default: 50)
- **RSI\_WIDTH:** Width of RSI output (default: 10)
- **RSI\_PERIOD:** Period for RSI calculation (default: 14)
- **BUY\_THRESHOLD:** RSI value to trigger buy (default: 30)
- **SELL\_THRESHOLD:** RSI value to trigger sell (default: 70)
- **FIXED\_POINT\_BITS:** Precision bits for fixed-point math (default: 8)
- **USE\_BRAM\_FIFO:** Set to 1 for BlockRAM FIFO, 0 for register-based (default: 1)

---

## 🔥 **FPGA Implementation Notes**
- Optimized for generic FPGA implementation with no vendor\-specific features.  
- Uses fixed\-point arithmetic for enhanced precision without floating\-point units.  
- Division module latency managed with dedicated wait state.  
- Expanded bit widths prevent overflow in gain/loss accumulation.  
- FIFO implementation optimized based on RSI period length.
- One\-hot encoding improves FSM timing and reliability.

---

## ⚠️ **Error Handling**
- **EOD Reset:** Ensures clean state transition and clears all historical data.  
- **Division by Zero:** Avoided with safe fallback (denominator set to 1).  
- **Invalid RSI Values:** Defaulted to zero until FIFO is fully populated.  
- **FIFO Initialization:** Prevents calculations until a full history is available.  
- **Overflow Protection:** Saturation logic prevents arithmetic overflow.

---

## 📚 **References**
- RSI Calculation Theory: [Investopedia](https://www.investopedia.com/terms/r/rsi.asp)  
- FPGA Verilog Best Practices: [FPGA4Fun](https://www.fpga4fun.com/)  

---

## 🧠 **Future Enhancements**
- ✅ Dynamic adjustment of period length.  
- ✅ Adding configurable thresholds for RSI decision.  
- ✅ Separate modules into individual files for easier maintainability.  
- ✅ Configurable FIFO implementation (register or BlockRAM).
- ❓ Integrating real-time data feeds and API support.  
- ❓ Vendor-specific optimizations for Xilinx/Intel FPGAs.  
- ❓ Add parameterized hysteresis to prevent signal oscillation.

---

⚡ _"Precision Trading Decisions with FPGA Speed!"_ ⚡

---
