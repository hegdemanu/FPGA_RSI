Here's a complete `README.md` for your **RSI FPGA Implementation Project:**

---

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

---

## 📝 **Core Components**
### 1️⃣ **FSM Controller**
- Handles price fetching, RSI computation, and decision-making.
- Ensures sequential processing of states to maintain FSM integrity.

### 2️⃣ **Price FIFO**
- 14-entry FIFO stores price history.
- Supports shift and push operations for real-time data.

### 3️⃣ **RSI Calculation Block**
- Computes gain and loss for each period.
- Uses exponential smoothing for average gain/loss.

### 4️⃣ **Pipelined Divider**
- 8-cycle latency division for computing RS.
- Prevents division by zero using denominator checks.

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

## ⚡ **Division Module (pipelined_divider)**
- 8-cycle pipelined division for high accuracy.
- Prevents zero division errors and maintains stability.

---

## 📦 **File Structure**
```
📂 RSI_FPGA
├── 📄 RSI_FSM.v                # Main FSM module
├── 📄 pipelined_divider.v      # Pipelined division module
└── 📄 README.md                # Project documentation
```

---

## 🧪 **Test Bench Guidelines**
1. **Initial Reset:** Apply a reset for 2 clock cycles.  
2. **Feed Price Data:** Simulate new price data with `new_price` high.  
3. **Check RSI Values:** Validate RSI output after sufficient price entries.  
4. **Test Buy/Sell Conditions:** Confirm buy/sell signals at RSI < 30 and RSI > 70.

---

## 📊 **Simulation Parameters**
- **Clock Frequency:** 50 MHz  
- **FIFO Depth:** 14  
- **Division Latency:** 8 clock cycles  

---

## 🔥 **FPGA Implementation Notes**
- Optimized for FPGA with pipeline stages for division.  
- Uses minimal resources for RSI computation.  
- Division module latency managed with FSM state transition.  
- Ready for deployment on Xilinx/Intel FPGAs.  

---

## ⚠️ **Error Handling**
- EOD reset ensures clean state transition.  
- Division by zero is avoided with safe fallback.  
- Initial RSI values default to zero until full FIFO population.

---

## 📚 **References**
- RSI Calculation Theory: [Investopedia](https://www.investopedia.com/terms/r/rsi.asp)  
- FPGA Verilog Best Practices: [FPGA4Fun](https://www.fpga4fun.com/)

---

## 🧠 **Future Enhancements**
- ✅ Dynamic adjustment of period length.  
- ✅ Adding configurable thresholds for RSI decision.  
- ✅ Integrating real-time data feeds and API support.  

---

## 📞 **Contact Information**
For any inquiries or contributions:  
📧 **Email:** manu.rsi@trading.com  
💻 **GitHub:** [ManuHegde/RSI-FPGA](https://github.com/ManuHegde/RSI-FPGA)

---

⚡ _“Precision Trading Decisions with FPGA Speed!”_ ⚡

---

Let me know if you need help simulating this or integrating with a real-time trading system! 🚀
