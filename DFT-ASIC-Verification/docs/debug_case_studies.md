# Phase 5 — Silicon & ATE Debug Case Studies (`IHP SG13G2` STA + SDF GLS)

This document details three intentional pre-silicon DFT failure case studies reproduced on the synthesized, 8-chain stitched, clock-buffered `soc_dft_top` gate-level netlist ([`build/phase5/soc_dft_top_cts.v`](../build/phase5/soc_dft_top_cts.v)) with `OpenSTA 3.2.0` corner `.sdf` back-annotation (`iverilog -gspecify`).

---

## Case Study 1 (`DBG-01`): Un-Gated Asynchronous Reset Corrupting Scan Shift

### 1. Symptom & Failure Reproduction
- **Configuration:** `test_mode = 1`, `scan_en = 1`, `comp_en = 0` (1,586-FF serial bypass chain clocked at `10 MHz` `tck`), JTAG `TDR_DFT_CTRL = 8'h01` (**`rst_mask_en = 0`**).
- **Stimulus:** Shift continuous `1`s through all 1,586 scan FFs (`_14573_`..`_16158_`), then assert a brief `sys_rst_n = 0` glitch mid-shift under `soc_dft_top_slow.sdf` (`-Tmax`).
- **Observed Behavior:** All `sg13g2_dfrbpq_1.RESET_B` pins immediately asynchronously clear to `0`, corrupting **16 / 16** checked shifted output bits (`exp=1, got=0`) starting at `cyc=0` (`ATE_FAIL mode=BYPASS pat=0 cyc=0 ext_pin=0 exp=1 got=0 note=DBG01_RESET_LEAK` -> diagnosed to `ch7[197]` tail flop `_16158_`, `pc_obs[1]`).

### 2. Root Cause
[`occ_clk_ctrl.sv`](../rtl/dft/occ_clk_ctrl.sv) gates functional async reset onto `dft_rst_n` via:
```systemverilog
assign dft_rst_n = (test_mode && rst_mask_en) ? 1'b1 : sys_rst_n;
```
When `rst_mask_en` is cleared (`TDR_DFT_CTRL[3] = 0`), external `sys_rst_n` board noise or reset-vector switching during scan shift asynchronously clears every flip-flop across `u_func_logic` and `u_scan_comp_wrap`.

### 3. Hardware Fix & Verification
- **Fix:** Assert `rst_mask_en = 1` via JTAG `DFT_CTRL = 8'h09` (and constrain `set_false_path -from [get_ports sys_rst_n]` in [`flow/sdc/scan_shift.sdc`](../flow/sdc/scan_shift.sdc)).
- **Result (`tb/gate/tb_soc_sdf_gls.sv`):** Repeating the identical `sys_rst_n = 0` glitch yields **0 mismatches across 64 unload cycles** under slow-corner SDF delays.

---

## Case Study 2 (`DBG-02`): Inter-Domain Scan Skew Hold Violation & Lockup Latch Fix

### 1. Symptom & Failure Reproduction
- **Topology ([`scripts/run_phase5_sta.py`](../scripts/run_phase5_sta.py)):** Inter-domain boundary bridging stitched `Chain 0` tail (`_14771_`, nominal balanced `2`-level `sg13g2_buf_16` `clk` tree) to `Chain 1` head (`_14772_`, skewed `clk_dom1` delayed through `16x sg13g2_buf_4` buffers) in fast PVT corner (`sg13g2_stdcell_fast_1p32V_m40C.lib`).
- **OpenSTA Propagated Timing (`dbg02_buggy`):**
  - Launch clock (`clk` → `2x sg13g2_buf_16` → `_14771_/CLK`): `0.11 ns`, data arrival at `_14772_/D`: `0.30 ns`.
  - Skewed capture clock (`16x sg13g2_buf_4` → `_14772_/CLK`): `0.81 ns`, required hold time: `0.79 ns`.
  - **Inter-Domain Hold Slack = `-0.48 ns` (`VIOLATED`, `TNS = -0.48 ns`)**.
- **SDF Fast-Corner GLS ([`tb/gate/tb_dbg02_skew_hold.sv`](../tb/gate/tb_dbg02_skew_hold.sv), `-Tmin`):** Shifting `00110011...` across the 398-FF `Chain 0 -> Chain 1` pair exhibits deterministic single-cycle shoot-through bit slips (`HOLD_SLIP cyc=398 exp=0 got=1`, `cyc=400 exp=1 got=0`, **32 mismatches / 64 cycles**).

### 2. Root Cause
Because fast-corner `clk->Q` + scan-mux delay (`0.19 ns`) is shorter than the clock tree skew between `Chain 0` and `Chain 1` (`0.70 ns` net skew), `_14772_` captures the **newly shifted** bit from `_14771_` on the *same* clock cycle instead of the *previous* bit.

### 3. Hardware Fix & Verification
- **Fix:** Insert a negative-edge-transparent lockup latch (`sg13g2_dllrq_1 u_lockup_ch0_to_ch1`, `.GATE_N(clk)`, `.RESET_B(rst_n)`) on the launch side of the `Chain 0 -> Chain 1` boundary (`dbg02_fixed`, also supported directly via [`scripts/scan_stitch.py`](../scripts/scan_stitch.py) `--lockup-latch`).
- **Before vs. After Metrics (`fast_1p32V_m40C`):**

| Metric | Without Lockup (`dbg02_buggy`) | With Lockup Latch (`dbg02_fixed`) |
| :--- | :---: | :---: |
| **Inter-Domain Boundary Hold Slack** | **`-0.48 ns`** (`VIOLATED`) | **`+49.38 ns`** (`MET`, chip worst `+0.20 ns`) |
| **Setup Slack @ `10 MHz` (`100 ns`)** | `+94.75 ns` | `+49.75 ns` (half-cycle borrow) |
| **Fast SDF `00110011...` GLS Result** | **32 / 64 bit slips** (`HOLD_SLIP`) | **0 / 64 errors across 398 FFs** (`PASS`) |

---

## Case Study 3 (`DBG-03`): Uninitialized Flop `X` Corrupting MISR + ATE Fail Diagnosis

### 1. Symptom & Failure Reproduction
- **Configuration:** Compressed `2:8`/`8:2` scan (`TDR_COMP_CFG = 16'h0003`: `comp_en=1, misr_en=1, chain_x_mask=8'h00`).
- **Stimulus:** Inject an uninitialized unknown state (`1'bx`) into `Chain 3`, bit `42` (synthesized cell `_15211_`, net `\u_rv32i_core.datapath_inst.regfile_inst.reg_array[9] [5]`) via `_scan_mux_d_638_` during compressed capture and unload under `soc_dft_top_slow.sdf`.
- **Observed Behavior:**
  - `1'bx` propagates through Chain 3 (`198 - 1 - 42 = 155` shifts) and escapes onto `ext_scan_out[1]` (`ATE_FAIL mode=COMP82 pat=2 cyc=155 ext_pin=1 exp=0 got=x note=DBG03_X_INJECT`).
  - Once `ext_scan_out[1]` drives `1'bx` into the feedback polynomial of `scan_comp_wrap.misr_q`, the **16-bit MISR signature corrupts permanently to `16'hXXxx`**.

### 2. Automated ATE Diagnosis (`scripts/ate_fail_diag.py`)
Parsing [`reports/ate_sim_fail.log`](../reports/ate_sim_fail.log) against [`build/phase4/scan8.json`](../build/phase4/scan8.json) produces [`reports/ate_diag_report.md`](../reports/ate_diag_report.md):
- **Uncompressed Bypass (`pat=1`, `cyc=947`, `ext_pin=0`)**: Maps 1-to-1 (`EXACT_1TO1`) to `ch3[42]` (`_15211_`, `reg_array[9][5]`).
- **Compressed 8:2 XOR (`pat=2`, `cyc=155`, `ext_pin=1`)**: Identifies odd-parity XOR group `{ch1, ch3, ch5, ch7}[42]`, then narrows deterministically (`ISOLATED_BY_XMASK`) via `MASK_PROBE pat=2 mask=0x08 clean=1` straight to `ch3[42]` (`_15211_`).

### 3. Hardware Fix & Verification
- **Fix:** Program `TDR_COMP_CFG = 16'h0043` (`chain_x_mask = 8'h08`, masking Chain 3 inside [`scan_comp_wrap.sv`](../rtl/dft/scan_comp_wrap.sv) via `(~chain_x_mask[i]) & chain_scan_out[i]`).
- **Result:** Even with `_15211_` latched to `1'bx`, **`0` X-values reach `scan_out[1:0]`** during compressed unload and **`misr_sig` recovers a deterministic, golden signature (`16'h0d5a`)** (at the Phase 4 quantified observability cost of `-4.967%` fault coverage while Chain 3 is masked).
