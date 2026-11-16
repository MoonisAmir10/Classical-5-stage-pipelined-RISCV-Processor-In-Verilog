# RISC-V SoC Subsystem — Design-for-Test (DFT) Architecture Specification

**Document Version:** 1.0 (Phase 1 Sign-off)  
**Target Technology:** IHP SG13G2 130 nm Standard Cell Library (`sg13g2_stdcell`, 1.2 V typ) & Sky130 HD / SRAM Macros  
**Subsystem Top:** `soc_dft_top`  
**Blocks Under Test:**
1. `rv32i_processor` — 5-stage pipelined RV32I core (`2,035` sequential cells, `187,353.28 µm²` baseline SG13G2 cell area)
2. `cache_2wsa_dft` — 2-way set-associative write-back cache controller (`282` sequential cells, `24,027.49 µm²` logic area)
3. `4 × sram_sync_sp` — Tag & Data SRAM macros (`u_tag_ram_w0/w1`: `8 × 14b`, `u_data_ram_w0/w1`: `8 × 32b`)

---

## 1. SoC Test Interface & Pinout

| Signal | Dir | Width | Domain | Function / Pin-Muxing Role |
| :--- | :--- | :---: | :--- | :--- |
| `sys_clk` | Input | 1 | `sys_clk` | Functional system clock (`100 MHz` nominal, `10 ns` period) |
| `sys_rst_n` | Input | 1 | Async | Active-low functional asynchronous reset |
| `tck` | Input | 1 | `tck` | IEEE 1149.1 JTAG test clock (`10 MHz` nominal, `100 ns` period) |
| `tms` | Input | 1 | `tck` | JTAG Test Mode Select (sampled on rising edge of `tck`) |
| `tdi` | Input | 1 | `tck` | JTAG Test Data Input (sampled on rising edge of `tck`) |
| `tdo` | Output | 1 | `tck` | JTAG Test Data Output (launched on falling edge of `tck`) |
| `tdo_en` | Output | 1 | `tck` | Active-high output enable for off-chip `TDO` pad |
| `trst_n` | Input | 1 | Async | Active-low asynchronous JTAG TAP reset |
| `test_mode` | Input | 1 | Static | Master DFT mode override (gates async reset, muxes OCC clock) |
| `scan_en` | Input | 1 | `tck`/`occ` | Global scan shift enable (`1` = shift, `0` = capture) |
| `scan_in` | Input | 2 | `tck` | 2 external compressed/bypass scan-in channels |
| `scan_out` | Output | 2 | `tck` | 2 external compacted/bypass scan-out channels |
| `bist_done` | Output | 1 | `sys_clk` | Sticky MBIST completion indicator (also mirrored in `TDR_MBIST_STAT`) |
| `bist_fail` | Output | 1 | `sys_clk` | Sticky MBIST failure flag (also mirrored in `TDR_MBIST_STAT`) |

---

## 2. Operating & DFT Mode Truth Table

| Mode | `test_mode` | `scan_en` | JTAG IR / `TDR_DFT_CTRL` | Clock Source (`occ_clk`) | Reset (`dft_rst_n`) | Active Test Path |
| :--- | :---: | :---: | :--- | :--- | :--- | :--- |
| **`FUNC`** | `0` | `0` | `BYPASS` / `IDCODE` | `sys_clk` | `sys_rst_n` | Functional CPU & Cache |
| **`SCAN_SHIFT`** | `1` | `1` | `SCAN_MODE` | `tck` (slow shift) | `1'b1` (masked) | Serial scan shift across balanced chains |
| **`SCAN_CAPTURE`** | `1` | `0` | `SCAN_MODE` | `occ_clk` (2-pulse LOC or single capture) | `1'b1` (masked) | Functional-speed capture window |
| **`SCAN_COMP`** | `1` | `1`/`0` | `COMP_EN=1` (`TDR_COMP_CFG`) | `tck` / `occ_clk` | `1'b1` (masked) | 2:8 decompressor → 8 chains → 8:2 XOR/MISR compactor |
| **`MBIST_RUN`** | `1` | `0` | `MBIST_RUN` (`TDR_MBIST_CMD`) | `sys_clk` | `sys_rst_n` / `1'b1` | March-C MBIST across `t0, t1, d0, d1` SRAM banks |
| **`W1500_INTEST`** | `1` | `0`/`1` | `INTEST` (`WIR=INTEST`) | `tck` / `occ_clk` | `1'b1` (masked) | Isolated block-level test of `rv32i_processor` |
| **`W1500_EXTEST`** | `1` | `0`/`1` | `EXTEST` (`WIR=EXTEST`) | `tck` | `1'b1` (masked) | Inter-block boundary observation/driving |

---

## 3. IEEE 1149.1 JTAG TAP & Test Data Registers (TDRs)

The TAP controller implements the standard 16-state IEEE 1149.1 FSM clocked on `tck` with asynchronous reset on `!trst_n` and synchronous reset via 5 consecutive cycles of `tms = 1`.

### 3.1 Instruction Register (`IR`, 4-bit, Capture `4'b0001`)
| Opcode | Instruction | Selected DR | Length | Description |
| :--- | :--- | :--- | :---: | :--- |
| `4'b0000` | `EXTEST` | `WBR` / Boundary | `WBR_LEN` | Drive/sample external & inter-block wrapper cells |
| `4'b0001` | `IDCODE` | `IDCODE_REG` | `32` | Returns `32'h1BAD_D071` (default reset IR instruction) |
| `4'b0010` | `SAMPLE_PRELOAD` | `WBR` | `WBR_LEN` | Non-intrusive boundary sample/preload |
| `4'b0011` | `INTEST` | `WBR` / Internal | `WBR_LEN` | Isolate `rv32i_processor` via IEEE 1500 wrapper |
| `4'b0100` | `DFT_CTRL` | `TDR_DFT_CTRL` | `8` | Configures scan mode, OCC pulses, reset override |
| `4'b0101` | `MBIST_CMD` | `TDR_MBIST_CMD` | `8` | Triggers/selects March-C MBIST banks & stop-on-fail |
| `4'b0110` | `MBIST_STAT` | `TDR_MBIST_STAT` | `48` | Reads `done`, `fail`, `fail_bank`, `fail_addr`, `fail_mask[31:0]` |
| `4'b0111` | `COMP_CFG` | `TDR_COMP_CFG` | `16` | Compression enable, MISR reset/read, 8-bit X-mask |
| `4'b1000` | `W1500_WIR` | `W1500_WIR` | `4` | Shifts IEEE 1500 Wrapper Instruction Register via JTAG |
| `4'b1111` | `BYPASS` | `BYPASS_REG` | `1` | Single-bit bypass shift register |

### 3.2 Key TDR Bit Maps
* **`TDR_DFT_CTRL[7:0]`:** `[0]` `dft_scan_mode`, `[1]` `occ_loc_en` (2-pulse at-speed capture), `[2]` `occ_bypass`, `[3]` `rst_mask_en` (default `1` during `test_mode`), `[7:4]` reserved.
* **`TDR_MBIST_CMD[7:0]`:** `[0]` `start_pulse`, `[4:1]` `bank_mask` (`t0, t1, d0, d1`), `[5]` `stop_on_fail`, `[7:6]` pattern mode (`00`=March-C, `01`=Checkerboard).
* **`TDR_MBIST_STAT[47:0]`:** `[0]` `done`, `[1]` `fail`, `[3:2]` `fail_bank_id`, `[6:4]` `fail_addr`, `[7]` `parity_err`, `[39:8]` `fail_bitmask[31:0]`, `[47:40]` `march_step_at_fail`.
* **`TDR_COMP_CFG[15:0]`:** `[0]` `comp_en`, `[1]` `misr_en`, `[2]` `misr_clr`, `[10:3]` `chain_x_mask[7:0]`, `[15:11]` signature/reserved.

---

## 4. IEEE 1500 Core Wrapper (`ieee1500_wrapper`)

Wraps `rv32i_processor` to demonstrate hierarchical SoC core isolation:
* **Wrapper Serial Port (WSP):** `WRCK` (muxed from `tck`), `WRSTN`, `SelectWIR`, `ShiftWR`, `CaptureWR`, `UpdateWR`, `WSI`, `WSO`.
* **Wrapper Instruction Register (`WIR`, 4-bit):** `WS_BYPASS`, `WS_INTEST_RING`, `WS_EXTEST`, `WS_SAFE`.
* **Wrapper Boundary Register (`WBR`):** Input & output boundary cells around `prog_sel`, `x14[31:0]`, `pc_obs[31:0]`, and `alu_obs[31:0]` supporting safe `INTEST` containment and `EXTEST` interconnect capture.

---

## 5. March-C Memory BIST (`mbist_ctrl`)

Tests all 4 `sram_sync_sp` banks inside `cache_2wsa_dft` (`t0`: `8×14`, `t1`: `8×14`, `d0`: `8×32`, `d1`: `8×32`) using the **March-C** algorithm (`6` elements, `10N` operations per bank):
1. $\Uparrow (w0)$ — Initialize array to all-`0` (ascending address)
2. $\Uparrow (r0, w1)$ — Read `0`, write `1` (ascending)
3. $\Uparrow (r1, w0)$ — Read `1`, write `0` (ascending)
4. $\Downarrow (r0, w1)$ — Read `0`, write `1` (descending)
5. $\Downarrow (r1, w0)$ — Read `1`, write `0` (descending)
6. $\Uparrow (r0)$ — Final read `0` verify (ascending)

When any read mismatches expected data (`data_read ^ exp_data != 0`), `mbist_ctrl` latches `fail <= 1'b1`, `fail_bank_id`, `fail_addr`, and `fail_bitmask <= (data_read ^ exp_data)` into `TDR_MBIST_STAT` for JTAG readout.

---

## 6. Scan Chains, Compression & Clock/Reset Architecture

* **Clocking (`occ_clk_ctrl`):**
  * Uses glitch-free ICG/mux topology selecting `tck` during `SCAN_SHIFT` (`scan_en = 1`) and `sys_clk` during `FUNC` or `SCAN_CAPTURE` (`scan_en = 0` when `occ_loc_en = 1` generates a clean 2-pulse Launch-on-Capture burst).
* **Reset Controllability:**
  * All core and cache flops (`rv32i_pc`, `rv32i_reg_pl`, `rv32i_regfile`, `rv32i_data_mem`, `cache_2wsa_dft`) receive `dft_rst_n = (test_mode && rst_mask_en) ? 1'b1 : sys_rst_n` so asynchronous reset cannot corrupt shift chains.
* **Scan & Compression (`scan_comp_wrap`):**
  * Baseline uncompressed scan vs. **2-to-8 XOR/LFSR decompressor** driving 8 balanced internal chains feeding an **8-to-2 spatial XOR compactor** + **16-bit MISR signature register** with per-chain `chain_x_mask[7:0]` gating.
  * Target ATPG experiments (`AUCOHL/Fault` + `Atalanta` + Python trade-off sweep): compare **1-chain vs. 4-chain vs. 8-chain** and **uncompressed vs. 4:1 compressed** shift cycles and stuck-at coverage.
