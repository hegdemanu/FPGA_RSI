# 🚀 RSI FSM Implementation in FPGA (Verilog)

## 📚 **Project Overview**
This project implements a **Relative Strength Index (RSI) calculation FSM** in Verilog for FPGA-based trading systems. It processes incoming price data and generates trading signals based on RSI thresholds. The system uses a **Finite State Machine (FSM)** to manage data fetching, RSI computation, and decision-making efficiently. A **pipelined division module** ensures accurate division with an 8-clock cycle latency.

---

## 🎯 **Objectives**
- ✅ Compute 14-period RSI using price input data.  
- ✅ Generate **buy/sell signals** based on RSI thresholds.  
- ✅ Implement FSM for data fetching, computation, and decision-making.  
- ✅ Ensure FPGA-friendly implementation with clock-cycle-controlled operations.  
- ✅ Handle End-of-Day (EOD) reset and initialization of FIFO.  
- ✅ Implement fixed-point arithmetic for enhanced precision.

---

## 🛠️ **System Design Overview**
### ⚡ **FSM States**
- `IDLE` – Waits for new price input.  
- `FETCH` – Retrieves price and updates FIFO.  
- `COMPUTE` – Calculates gain/loss and averages.  
- `WAIT_DIV` – Initiates RS calculation using the division module.  
- `DECISION` – Generates buy/sell signals based on RSI value.  
- `RESET` – Clears all data on reset or EOD.  

---

## 📡 **Signal Descriptions**
| Signal Name     | Direction | Width  | Description                                  |
|----------------|-----------|--------|----------------------------------------------|
| `clk`           | Input     | 1 bit  | Clock signal controlling FSM operation      |
| `reset`         | Input     | 1 bit  | Asynchronous reset or EOD signal            |
| `price_in`      | Input     | 50 bits| New price data input                        |
| `new_price`     | Input     | 1 bit  | Signal indicating arrival of new price      |
| `EOD`           | Input     | 1 bit  | End-of-Day reset signal                     |
| `RSI_out`       | Output    | 10 bits| Computed RSI output                         |
| `buy_signal`    | Output    | 1 bit  | Buy decision signal                         |
| `sell_signal`   | Output    | 1 bit  | Sell decision signal                        |
| `div_start`     | Internal  | 1 bit  | Start signal for division                   |
| `div_done`      | Internal  | 1 bit  | Completion flag for division                |
| `div_result`    | Internal  | 32 bits| Division result                             |
| `gain_sum`      | Internal  | 64 bits| Accumulated gain for RSI calculation        |
| `loss_sum`      | Internal  | 64 bits| Accumulated loss for RSI calculation        |
| `avg_gain`      | Internal  | 32 bits| Average gain with enhanced precision        |
| `avg_loss`      | Internal  | 32 bits| Average loss with enhanced precision        |

---

## 📝 **Core Components**
### 1️⃣ **FSM Controller**
- Handles price fetching, RSI computation, and decision-making.
- Ensures sequential processing of states to maintain FSM integrity.
- Manages FIFO initialization tracking to prevent invalid calculations.

### 2️⃣ **Price FIFO**
- 14-entry FIFO stores price history.
- Tracks initialization status to ensure valid data before computation.
- Maintains count of valid entries for proper calculation initiation.

### 3️⃣ **RSI Calculation Block**
- Computes gain and loss for each period.
- Uses exponential smoothing for average gain/loss.
- Implements fixed-point arithmetic for enhanced calculation precision.

### 4️⃣ **Pipelined Divider**
- 8-cycle latency division for computing RS.
- Prevents division by zero using denominator checks.
- Controlled via start/done handshaking for reliable operation.

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

### **Fixed-Point Implementation**
- Uses bit-shifting for enhanced precision in RSI calculation
- Implements the formula: `RSI <= 100 - ((100 << 8) / ((1 << 8) + RS)) >> 8`
- Provides more accurate results than simple integer division

---

## ⚡ **Division Module (pipelined_divider)**
- 8-cycle pipelined division for high accuracy.
- Prevents zero division errors and maintains stability.
- Implemented within the main RSI_FSM module for simplified file structure.

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
3. **Wait States:** Allow sufficient cycles for division completion (8 cycles).
4. **FIFO Initialization:** Provide at least 14 price entries before expecting valid RSI.
5. **Check RSI Values:** Validate RSI output after sufficient price entries.  
6. **Test Buy/Sell Conditions:** Confirm buy/sell signals at RSI < 30 and RSI > 70.

---

## 📊 **Simulation Parameters**
- **Clock Frequency:** 50 MHz  
- **FIFO Depth:** 14  
- **Division Latency:** 8 clock cycles  
- **RSI Buy Threshold:** < 30
- **RSI Sell Threshold:** > 70

---

## 🔥 **FPGA Implementation Notes**
- Optimized for generic FPGA implementation with no vendor-specific features.
- Uses fixed-point arithmetic for enhanced precision without floating-point units.
- Division module latency managed with dedicated wait state.
- Expanded bit widths prevent overflow in gain/loss accumulation.
- FIFO initialization tracking prevents invalid calculations.

---

## ⚠️ **Error Handling**
- EOD reset ensures clean state transition.  
- Division by zero is avoided with safe fallback.  
- Initial RSI values default to zero until full FIFO population.
- Proper FIFO initialization tracking prevents premature calculations.

---

## 📚 **References**
- RSI Calculation Theory: [Investopedia](https://www.investopedia.com/terms/r/rsi.asp)  
- FPGA Verilog Best Practices: [FPGA4Fun](https://www.fpga4fun.com/)

---

## 🧠 **Future Enhancements**
- ✅ Dynamic adjustment of period length.  
- ✅ Adding configurable thresholds for RSI decision.  
- ✅ Integrating real-time data feeds and API support.  
- ✅ Separate modules into individual files for easier maintainability.
- ✅ Vendor-specific optimizations for Xilinx/Intel FPGAs.

---

⚡ _"Precision Trading Decisions with FPGA Speed!"_ ⚡
