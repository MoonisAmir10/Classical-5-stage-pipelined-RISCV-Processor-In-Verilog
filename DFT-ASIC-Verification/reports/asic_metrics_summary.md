# IHP SG13G2 130nm ASIC vs. Artix-7 FPGA Implementation Metrics

> **PDK & Tooling**: `IHP SG13G2` (`130 nm` CMOS, `typ 1.20V / 25°C`, `slow 1.08V / 125°C`, `fast 1.32V / -40°C`, `NAND2_1 = 7.2576 um^2`), `Yosys 0.71+`, `OpenSTA 3.2.0`, `AUCOHL Fault 0.9.4 + Atalanta 2.0`.

## 1. ASIC Area & Gate-Equivalent Summary (`IHP SG13G2 130nm`)

| Synthesis Stage / Scope | Stdcell Count | FFs (`dfrbpq_1`) | Latches | Scan Muxes (`mux2`) | Stdcell Area (`um^2`) | Gate Equiv (`GE`) |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| `rv32i_processor` Baseline (RTL -> IHP) | 9,649 | 2,035 | 0 | 1525 | 187,353.28 | 25,815 |
| `cache_2wsa_dft` Ctrl Baseline (excl. 4 SRAMs) | 1,367 | 282 | 0 | 109 | 24,395.59 | 3,361 |
| `soc_func_logic` No-Scan Baseline | 9,658 | 2,151 | 0 | 692 | 180,114.62 | 24,817 |
| `soc_func_logic` 8-Chain Scan Stitched | 11,809 | 2,151 | 0 | 2843 | 219,142.36 | 30,195 |
| `soc_dft_top` Post-Stitch Pre-CTS (incl. All DFT IP) | 14,207 | 2,550 | 1 | - | 256,473.04 | 35,339 |
| `soc_dft_top` **Final Post-CTS/ECO Signoff** | 15,886 | 2,550 | 1 | 2944 | 298,186.09 | 41,086 |

- **CTS/ECO Physical Closure Delta**: `+1,679` cells (`+41,713.05 um^2`), buffering `295` high-fanout/clock nets (`1,679` buffer instances total) and upsizing `831` `_1 -> _2` combinational/mux cells.
- **Total Signoff Standard-Cell Core Area**: **`298,186.09 um^2`** (`0.2982 mm^2`, **`41,086 GE`**; sequential cells = `124,921.44 um^2` / `41.89%`).
- **Total Area incl. Modeled 4x SRAM Macro Stubs**: `+28,800.00 um^2` (`2x 4,800 um^2` Tag + `2x 9,600 um^2` Data stubs in `flow/sta/sram_sync_sp.lib`) = **`326,986.09 um^2`** (`0.3270 mm^2`).

### Hierarchical Area Breakdown (`soc_dft_top_sta.v` Post-CTS Signoff)

| Module / Instance | Stdcells | FFs | Area (`um^2`) | Share of Stdcell Area |
| :--- | :---: | :---: | :---: | :---: |
| u_func_logic (RV32I + 2-Way Cache Ctrl, 8-Ch Scan + CTS) | 13,273 | 2,151 | 254,826.17 | 85.46% |
| u_ieee1500_wrapper (IEEE 1500 Core Test Wrapper) | 1,469 | 203 | 23,187.69 | 7.78% |
| u_jtag_tap (IEEE 1149.1 TAP + 4 TDRs) | 540 | 96 | 9,395.11 | 3.15% |
| u_mbist_ctrl (March-C + Checkerboard Engine) | 404 | 67 | 7,168.58 | 2.40% |
| u_scan_comp_wrap (2:8 PRPG Decomp + 8:2 XOR + 16b MISR) | 157 | 24 | 2,666.87 | 0.89% |
| u_occ_clk_ctrl (Glitch-Free OCC + ICG + LOC + RstMask) | 34 | 9 | 684.03 | 0.23% |
| soc_dft_top (Top-Level Clock/Reset Glue) | 9 | 0 | 257.64 | 0.09% |

## 2. ASIC Power Summary (`OpenSTA 3.2.0` on Post-CTS Signoff Netlist)

> **Methodology Note**: Static probabilistic power computed on `soc_dft_top_sta.v` at global toggle activity `0.1` transitions/cycle referenced to each mode's active clock (`100 MHz` `sys_clk` for `func` & `scan_capture`; `10 MHz` `tck` via `-density 0.001` for `scan_shift`, plus unscaled `-activity 0.1` shown for reference) and duty `0.5`. Power covers all **`15,886`** `IHP SG13G2` standard cells; the `4x sram_sync_sp` Liberty stubs model timing/area without array `internal_power()` tables (`Macro = 0.00 mW`).

| Mode | PVT Corner | Clock (`MHz`) | Sequential (`mW`) | Combinational (`mW`) | Clock Net (`mW`) | Leakage (`uW`) | **Total Power (`mW`)** |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| `func` | `typ` | 100 | 12.807 | 1.758 | 4.714 | 4.08 | **19.278** |
| `scan_shift` | `typ` | 10 | 1.761 | 0.178 | 0.672 | 4.13 | **2.611** |
| `scan_shift_unscaled` | `typ` | 10 | 2.738 | 1.760 | 0.672 | 4.13 | **5.170** |
| `scan_capture` | `typ` | 100 | 12.807 | 1.758 | 4.713 | 4.08 | **19.279** |
| `func` | `slow` | 100 | 10.420 | 1.354 | 3.633 | 18.29 | **15.407** |
| `scan_shift` | `slow` | 10 | 1.438 | 0.145 | 0.520 | 18.71 | **2.104** |
| `scan_shift_unscaled` | `slow` | 10 | 2.213 | 1.356 | 0.520 | 18.71 | **4.089** |
| `scan_capture` | `slow` | 100 | 10.420 | 1.354 | 3.633 | 18.29 | **15.407** |
| `func` | `fast` | 100 | 15.615 | 2.259 | 6.107 | 8.86 | **23.981** |
| `scan_shift` | `fast` | 10 | 2.146 | 0.231 | 0.870 | 8.92 | **3.248** |
| `scan_shift_unscaled` | `fast` | 10 | 3.358 | 2.262 | 0.870 | 8.92 | **6.491** |
| `scan_capture` | `fast` | 100 | 15.615 | 2.259 | 6.107 | 8.86 | **23.982** |

### Hierarchical Power Breakdown (`typ_1p20V_25C`)

| Instance | Functional `100 MHz` (`mW`) | Scan-Shift `10 MHz` (`mW`) | Leakage @ `25°C` (`uW`) |
| :--- | :---: | :---: | :---: |
| `u_func_logic` | 17.8436 | 1.7876 | 3.493 |
| `u_mbist_ctrl` | 0.5360 | 0.4659 | 0.097 |
| `u_ieee1500_wrapper` | 0.3771 | 0.1764 | 0.317 |
| `u_scan_comp_wrap` | 0.1870 | 0.0189 | 0.036 |
| `u_jtag_tap` | 0.1592 | 0.0777 | 0.125 |
| `u_occ_clk_ctrl` | 0.0487 | 0.0386 | 0.007 |

## 3. FPGA vs. ASIC Comparative Summary

| Metric | FPGA Baseline (`Vivado Artix-7` Baseline RTL) | FPGA Post-DFT (`Yosys synth_xilinx xc7`) | ASIC Post-DFT (`IHP SG13G2 130nm` Signoff) |
| :--- | :---: | :---: | :---: |
| **Device / Technology** | `Xilinx Artix-7 (XC7A100T-1CSG324C)` | Xilinx Artix-7 (`xc7`) | `IHP SG13G2 130nm` (`1.08V–1.32V`, `-40°C..125°C`) |
| **Max Operating Freq (`F_max`)** | **168.07 MHz** (`100 MHz` target) | Functional RTL reference | **169.49 MHz** (`typ`) / **110.50 MHz** (`slow`) / **249.38 MHz** (`fast`) |
| **Logic Resources / Area** | `534` LUTs, `625` FFs (`< 1%`) | `3,902` LUTs, `2,798` FFs (`soc_func`: `3,087` LUTs / `2,320` FFs) | **`298,186.09 um^2`** (`0.2982 mm^2` stdcell = `41,086 GE`, `15,886` cells, `2,550` FFs) |
| **Memory Blocks** | `0 BRAM` (Distributed RAM) | `12 RAM32M`, `0 BRAM` | `4x sram_sync_sp` (`2x 8x14b` Tag + `2x 8x32b` Data = `28,800 um^2` stub) |
| **Timing Closure (Setup / Hold)** | `168.07 MHz` Vivado signoff | N/A | **9/9 Modes×Corners PASS** (`slow`: `+0.95 ns` / `+0.24 ns`) |
| **Core Power (`OpenSTA`)** | N/A (not extracted in Vivado) | N/A | **`19.28 mW`** (`func 100 MHz typ`), **`2.61 mW`** (`scan_shift 10 MHz typ`), **`23.98 mW`** (`fast`) |
| **Leakage Power (`stdcells`)** | N/A | N/A | `4.08 uW` (`25°C typ`) / `18.29 uW` (`125°C slow`) |
| **DFT Capabilities** | None (Functional Core only) | Full JTAG / 1500 / MBIST / OCC / Comp | **99.983% / 97.163% SA FC**, `4x` Comp (`7388` vec), Hybrid `1233` vec (`8.77x` data red.), 3-corner SDF GLS |

> **Why Vivado Baseline (`534 LUTs / 625 FFs`) vs. Yosys (`soc_func_logic`) Differ**: In the standalone Vivado Artix-7 synthesis of the baseline core, Vivado inferred Distributed `LUTRAM` for the register file / data memory and pruned unobserved debug outputs. In the ASIC scan-ready flow (`soc_func_logic`), the `32x32` regfile and `16x32` scratchpad are explicitly synthesized into `2,151` scan-stitchable `sg13g2_dfrbpq_1` flip-flops alongside `100%` of IEEE 1500 / MBIST / JTAG / OCC / compactor DFT hardware.

## 4. Extracted ASIC Schematics

- **Full Post-Stitch ASIC SoC Schematic**: [asic_soc_dft_schematic.png](../docs/figures/asic_soc_dft_schematic.png) ([SVG](../docs/figures/asic_soc_dft_schematic.svg))
- **Glitch-Free OCC Stdcell Gate Schematic (`IHP SG13G2`)**: [asic_occ_gate_schematic.png](../docs/figures/asic_occ_gate_schematic.png) ([SVG](../docs/figures/asic_occ_gate_schematic.svg))
