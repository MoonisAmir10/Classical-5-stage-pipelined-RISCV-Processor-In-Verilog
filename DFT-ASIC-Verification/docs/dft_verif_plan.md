# RISC-V SoC Subsystem — DFT Verification Plan

**Reference Spec:** [dft_spec.md](dft_spec.md)  
**Primary Simulators & Checkers:** `Verilator 5.054` (UVM/SVA + `--coverage`), `cocotb 2.0.1` + `Icarus Verilog 13.0` (4-state RTL & SDF GLS), `OpenSTA 3.2.0`, `AUCOHL Fault 0.9.4` + `Atalanta 2.0`

---

## 1. Verification Objectives & Closure Targets

| Metric | Target | Enforcement Tool |
| :--- | :---: | :--- |
| RTL Linting (`-Wall`) | `0` warnings/errors on all `rtl/` modules | `Verilator 5.054` |
| Baseline Functional Regression | 100% pass (Fibonacci, SW/LW hazard, Cache hit/miss/evict) | `Icarus Verilog 13.0` & `Verilator 5.054` |
| DFT IP Assertions (SVA) | 100% pass, `0` failed cycles across all tests | `Verilator 5.054 --assert` |
| Functional & Code Coverage (DFT IPs) | >= 95% line/toggle, 100% JTAG/MBIST/1500 state bins | `Verilator --coverage` |
| MBIST Fault Detection Rate | 100% detection of injected SA0, SA1, and bit-flip faults | `tb_mbist` fault-injection campaign |
| Logic Stuck-At ATPG Coverage | >= 92% collapsed stuck-at coverage (sweep documented) | `AUCOHL Fault` + `Atalanta` |
| STA Signoff (`func`, `scan_shift`, `scan_capture`) | Positive setup & hold slack across `fast`/`typ`/`slow` | `OpenSTA 3.2.0` |
| SDF Gate-Level Simulation | 100% pass on scan chain integrity, ATPG & MBIST | `Icarus Verilog 13.0` (`-gspecify -ginterconnect`) |

---

## 2. Verification Matrix

### 2.1 Phase 1 — Baseline RTL Verification (Completed)
| ID | Testcase | Scope | Checking Method | Status |
| :--- | :--- | :--- | :--- | :---: |
| `BASE-01` | `tb_rv32i_baseline` (Prog 0) | RV32I Fibonacci `1..34` on `x14`, hazard forwarding (`0` spurious cache accesses) | Self-checking TB + SVA reset check (`iverilog` & `Verilator`) | **PASS** |
| `BASE-02` | `tb_rv32i_baseline` (Prog 1) | End-to-end RV32I + integrated 2-way D-cache (`LW`/`SW`, hit/miss/evict/dirty WB, load-use stall, `SW` fwd) | Self-checking `x14 == 1297` (`7H/7M/2WB`, `iverilog` & `Verilator`) | **PASS** |
| `BASE-03` | `tb_cache_baseline` | Directed + 1,000-op randomized golden-scoreboard 2-way LRU cache verification + MBIST mux & SA0 inject | Self-checking TB (`iverilog` & `Verilator`) | **PASS** |
| `BASE-04` | Yosys Synthesis Check | `rv32i_processor` (`1,523` FFs) & `cache_2wsa_dft` (`152` FFs + `4` SRAM blackboxes) | Zero latches, zero tri-states, `sg13g2` mapping | **PASS** |

### 2.2 Phase 2 & 3 — DFT Architecture DV (Directed, Constrained-Random, SVA)
| ID | Testcase | Stimulus Type | Key Checks & Assertions |
| :--- | :--- | :--- | :--- |
| `JTAG-01` | TAP FSM State Traversal | Directed (`cocotb` / SV) | Verify all 16 IEEE 1149.1 states, `IDCODE=32'h1BAD_D071`, `BYPASS` 1-cycle shift |
| `JTAG-02` | Randomized TDR Stress | Constrained-Random (UVM/SV) | Random IR opcodes, mid-shift `trst_n`, 5-cycle `TMS=1` soft-reset, back-to-back TDR updates |
| `JTAG-03` | Illegal Opcode & `TDO` Tri-State | Directed + SVA | Undefined IR selects `BYPASS`; SVA checks `tdo_en` active only in `SHIFT_DR`/`SHIFT_IR` |
| `W1500-01` | Core `INTEST` Isolation | Directed + Constrained-Random | Shift stimuli via `WBR`, capture `rv32i_processor` outputs, verify isolation from external pins |
| `W1500-02` | Wrapper `EXTEST` & `BYPASS` | Directed | Drive `WBR` outputs to cache boundary; verify 1-bit `WBY` latency |
| `MBIST-01` | Clean March-C Run | Directed | Run March-C across all 4 banks (`t0, t1, d0, d1`) via JTAG `MBIST_CMD` → `done=1, fail=0` |
| `MBIST-02` | Fault-Injection Sweep | Automated Matrix | Inject SA0, SA1, and bit-invert across banks `0..3`, addrs `0..7`, MSB/LSB bits → verify exact `fail_bank_id`, `fail_addr`, `fail_bitmask` in `TDR_MBIST_STAT` |
| `COMP-01` | Decompressor & Compactor Bypass vs. Comp | Directed + Random | Compare 1-chain bypass vs. 2:8 XOR compression + MISR signature; verify `chain_x_mask` prevents single-chain `X` from corrupting MISR |
| `OCC-01` | Clock Switching & LOC Pulse | Directed + SVA | Verify glitch-free `tck <-> sys_clk` switch; SVA checks exactly 2 capture pulses during `occ_loc_en=1` and `dft_rst_n == 1` while `test_mode=1` |

### 2.3 Phase 4 & 5 — ATPG, Mode STA & SDF Gate-Level Debug
| ID | Flow Step | Scope / Experiment | Acceptance Criteria |
| :--- | :--- | :--- | :--- |
| `ATPG-01` | Scan Chain Integrity | `1/4/8`-chain `sg13g2_mux2_1` stitched netlists (`scan_stitch.py`) + `soc_dft_top` `-DPOST_SCAN_STITCH` | **PASS** — `tb_scan_chain_generic` (`1/4/8` chains) + `tb_soc_scan8_gls` (`1,586`-FF bypass, Fibonacci `x14=34`, integrated D-cache `x14=1297` `7H/7M/2WB`, `2:8` compressed LOC, MBIST) pass in `iverilog` (`make test-scan-gls`) |
| `ATPG-02` | Trade-Off Sweep | `1` vs. `4` vs. `8` chains; `4:1`/`8:2`/`8:1` XOR; `2:8` LFSR (`32..4096`); Hybrid top-off | **PASS** — `37,748` faults (`99.976%` All-PO / `94.283%` Scan-Out); CSVs, report (`docs/atpg_tradeoff_report.md`) & 3-panel plot (`docs/figures/atpg_tradeoff_charts.png`) generated via `make atpg-sweep` |
| `STA-01` | `func.sdc` Timing Closure | `sys_clk` (`100 MHz`) propagated functional mode (`typ`/`slow`/`fast`) | **PASS** — `slow`: `+0.87 ns` setup (`109.53 MHz`) / `+0.15 ns` hold; `fast`: `+5.61 ns` / `+0.00 ns` (`make sta`) |
| `STA-02` | `scan_shift.sdc` Closure | `tck` (`10 MHz`), `set_case_analysis` + SRAM standby false paths | **PASS** — Zero hold violations across `typ` (`+0.09`), `slow` (`+0.23`), `fast` (`+0.01 ns`) (`make sta`) |
| `STA-03` | `scan_capture.sdc` Closure | At-speed `100 MHz` LOC capture window (`scan_en=0`), multicycle TDR paths | **PASS** — `slow`: `+0.87 ns` setup / `+0.17 ns` hold; `fast`: `+4.39 ns` / `+0.01 ns` (`make sta`) |
| `GLS-01` | SDF Gate-Level Sim | `iverilog -gspecify` + OpenSTA `.sdf` (`slow`/`typ`/`fast`) | **PASS** — `100 MHz` FUNC Fib (`x14=34`) + Integrated D-Cache (`x14=1297`), 1,586-FF `00110011...` shift, March-C MBIST (`53` cycles), and `2:8` Compressed LOC (`MISR=0x0de0` slow / `0x52e6` typ / `0x6f97` fast) pass (`make test-sdf-gls`) |
| `DBG-01` | Case Study 1: Async Reset Leak | Clear `rst_mask_en` & glitch `sys_rst_n` during `SCAN_SHIFT` | **PASS** — Reproduced `16/16` corrupted bits (`DBG01_RESET_LEAK`) → verified `rst_mask_en=1` (`0/64` errors) in slow SDF GLS |
| `DBG-02` | Case Study 2: Scan Hold / Skew | `16x sg13g2_buf_4` skew across `Chain 0 -> Chain 1` (`fast_1p32V_m40C`) | **PASS** — Reproduced `-0.48 ns` hold slack & `32/64` fast-SDF bit slips → `sg13g2_dllrq_1` lockup latch closes to `+49.38 ns` boundary / `+0.20 ns` chip worst & `0` slips across 398 FFs (`make test-dbg-studies`) |
| `DBG-03` | Case Study 3: MISR X-Corruption | Inject `1'bx` into `Chain 3` `_15211_` during compressed capture | **PASS** — Observed `MISR=0xXXxx` at `cyc=155` → pinpointed `ch3[42]` via `ate_fail_diag.py` → masked cleanly (`chain_x_mask=8'h08`, `MISR=0x0d5a`) |
