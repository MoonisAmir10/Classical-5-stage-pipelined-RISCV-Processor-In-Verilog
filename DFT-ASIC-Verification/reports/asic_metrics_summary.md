# IHP SG13G2 130nm ASIC vs. Artix-7 FPGA Implementation Metrics

> **PDK & Tooling**: `IHP SG13G2` (`130 nm` CMOS, `typ 1.20V / 25°C`, `slow 1.08V / 125°C`, `fast 1.32V / -40°C`, `NAND2_1 = 7.2576 um^2`), `Yosys 0.71+`, `OpenSTA 3.2.0`, `AUCOHL Fault 0.9.4 + Atalanta 2.0`.

## 1. ASIC Area & Gate-Equivalent Summary (`IHP SG13G2 130nm`)

| Synthesis Stage / Scope | Stdcell Count | FFs (`dfrbpq_1`) | Latches | Scan Muxes (`mux2`) | Stdcell Area (`um^2`) | Gate Equiv (`GE`) |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| `rv32i_processor` Baseline (RTL -> IHP) | 7,948 | 1,523 | 0 | 1137 | 145,478.21 | 20,045 |
| `cache_2wsa_dft` Ctrl Baseline (excl. 4 SRAMs) | 1,040 | 152 | 0 | 144 | 16,423.46 | 2,263 |
| `soc_func_logic` No-Scan Baseline | 8,925 | 1,586 | 0 | 200 | 146,409.72 | 20,173 |
| `soc_func_logic` 8-Chain Scan Stitched | 10,511 | 1,586 | 0 | 1786 | 175,186.10 | 24,138 |
| `soc_dft_top` Post-Stitch Pre-CTS (incl. All DFT IP) | 12,909 | 1,985 | 1 | - | 212,516.78 | 29,282 |
| `soc_dft_top` **Final Post-CTS/ECO Signoff** | 14,345 | 1,985 | 1 | 1887 | 248,004.63 | 34,172 |

- **CTS/ECO Physical Closure Delta**: `+1,436` cells (`+35,487.85 um^2`), `1,436` buffer instances total in signoff netlist.
- **Total Signoff Standard-Cell Core Area**: **`248,004.63 um^2`** (`0.2480 mm^2`, **`34,172 GE`**; sequential cells = `97,242.77 um^2` / `39.21%`).
- **Total Area incl. Modeled 4x SRAM Macro Stubs**: `+28,800.00 um^2` (`2x 4,800 um^2` Tag + `2x 9,600 um^2` Data stubs in `flow/sta/sram_sync_sp.lib`) = **`276,804.63 um^2`** (`0.2768 mm^2`).

### Hierarchical Area Breakdown (`soc_dft_top_sta.v` Post-CTS Signoff)

| Module / Instance | Stdcells | FFs | Area (`um^2`) | Share of Stdcell Area |
| :--- | :---: | :---: | :---: | :---: |
| u_func_logic (RV32I + 2-Way Cache Ctrl, 8-Ch Scan + CTS) | 11,732 | 1,586 | 204,644.70 | 82.52% |
| u_ieee1500_wrapper (IEEE 1500 Core Test Wrapper) | 1,469 | 203 | 23,187.69 | 9.35% |
| u_jtag_tap (IEEE 1149.1 TAP + 4 TDRs) | 540 | 96 | 9,395.11 | 3.79% |
| u_mbist_ctrl (March-C + Checkerboard Engine) | 404 | 67 | 7,168.58 | 2.89% |
| u_scan_comp_wrap (2:8 PRPG Decomp + 8:2 XOR + 16b MISR) | 157 | 24 | 2,666.87 | 1.08% |
| u_occ_clk_ctrl (Glitch-Free OCC + ICG + LOC + RstMask) | 34 | 9 | 684.03 | 0.28% |
| soc_dft_top (Top-Level Clock/Reset Glue) | 9 | 0 | 257.64 | 0.10% |

## 2. ASIC Power Summary (`OpenSTA 3.2.0` on Post-CTS Signoff Netlist)

> **Methodology Note**: Static probabilistic power computed on `soc_dft_top_sta.v` at global toggle activity `0.1` transitions/cycle referenced to each mode's active clock (`100 MHz` `sys_clk` for `func` & `scan_capture`; `10 MHz` `tck` via `-density 0.001` for `scan_shift`, plus unscaled `-activity 0.1` shown for reference) and duty `0.5`. Power covers all **`14,345`** `IHP SG13G2` standard cells; the `4x sram_sync_sp` Liberty stubs model timing/area without array `internal_power()` tables (`Macro = 0.00 mW`).

| Mode | PVT Corner | Clock (`MHz`) | Sequential (`mW`) | Combinational (`mW`) | Clock Net (`mW`) | Leakage (`uW`) | **Total Power (`mW`)** |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| `func` | `typ` | 100 | 9.676 | 1.553 | 3.562 | 3.40 | **14.790** |
| `scan_shift` | `typ` | 10 | 1.447 | 0.157 | 0.557 | 3.44 | **2.162** |
| `scan_shift_unscaled` | `typ` | 10 | 2.222 | 1.555 | 0.557 | 3.44 | **4.334** |
| `scan_capture` | `typ` | 100 | 9.676 | 1.553 | 3.562 | 3.40 | **14.791** |
| `func` | `slow` | 100 | 7.871 | 1.196 | 2.746 | 15.16 | **11.814** |
| `scan_shift` | `slow` | 10 | 1.182 | 0.128 | 0.431 | 15.48 | **1.742** |
| `scan_shift_unscaled` | `slow` | 10 | 1.796 | 1.199 | 0.431 | 15.48 | **3.426** |
| `scan_capture` | `slow` | 100 | 7.871 | 1.197 | 2.746 | 15.17 | **11.814** |
| `func` | `fast` | 100 | 11.801 | 2.005 | 4.616 | 7.48 | **18.423** |
| `scan_shift` | `fast` | 10 | 1.764 | 0.205 | 0.721 | 7.53 | **2.690** |
| `scan_shift_unscaled` | `fast` | 10 | 2.728 | 2.009 | 0.721 | 7.53 | **5.457** |
| `scan_capture` | `fast` | 100 | 11.801 | 2.006 | 4.616 | 7.48 | **18.424** |

### Hierarchical Power Breakdown (`typ_1p20V_25C`)

| Instance | Functional `100 MHz` (`mW`) | Scan-Shift `10 MHz` (`mW`) | Leakage @ `25°C` (`uW`) |
| :--- | :---: | :---: | :---: |
| `u_func_logic` | 13.3264 | 1.3352 | 2.815 |
| `u_mbist_ctrl` | 0.5360 | 0.4659 | 0.097 |
| `u_ieee1500_wrapper` | 0.3772 | 0.1764 | 0.317 |
| `u_scan_comp_wrap` | 0.1874 | 0.0190 | 0.036 |
| `u_jtag_tap` | 0.1592 | 0.0777 | 0.125 |
| `u_occ_clk_ctrl` | 0.0501 | 0.0388 | 0.007 |

## 3. FPGA vs. ASIC Comparative Summary

| Metric | FPGA Baseline (`Vivado Artix-7` Baseline RTL) | FPGA Post-DFT (`Yosys synth_xilinx xc7`) | ASIC Post-DFT (`IHP SG13G2 130nm` Signoff) |
| :--- | :---: | :---: | :---: |
| **Device / Technology** | `Xilinx Artix-7 (XC7A100T-1CSG324C)` | Xilinx Artix-7 (`xc7`) | `IHP SG13G2 130nm` (`1.08V–1.32V`, `-40°C..125°C`) |
| **Max Operating Freq (`F_max`)** | **168.07 MHz** (`100 MHz` target) | Functional RTL reference | **168.07 MHz** (`typ`) / **109.53 MHz** (`slow`) / **227.79 MHz** (`fast`) |
| **Logic Resources / Area** | `534` LUTs, `625` FFs (`< 1%`) | `3,800` LUTs, `2,155` FFs (`soc_func`: `2,985` LUTs / `1,677` FFs) | **`248,004.63 um^2`** (`0.2480 mm^2` stdcell = `34,172 GE`, `14,345` cells, `1,985` FFs) |
| **Memory Blocks** | `0 BRAM` (Distributed RAM) | `12 RAM32M`, `0 BRAM` | `4x sram_sync_sp` (`2x 8x14b` Tag + `2x 8x32b` Data = `28,800 um^2` stub) |
| **Timing Closure (Setup / Hold)** | `168.07 MHz` Vivado signoff | N/A | **9/9 Modes×Corners PASS** (`slow`: `+0.87 ns` / `+0.15 ns`) |
| **Core Power (`OpenSTA`)** | N/A (not extracted in Vivado) | N/A | **`14.79 mW`** (`func 100 MHz typ`), **`2.16 mW`** (`scan_shift 10 MHz typ`), **`18.42 mW`** (`fast`) |
| **Leakage Power (`stdcells`)** | N/A | N/A | `3.40 uW` (`25°C typ`) / `15.16 uW` (`125°C slow`) |
| **DFT Capabilities** | None (Functional Core only) | Full JTAG / 1500 / MBIST / OCC / Comp | **99.976% / 94.283% SA FC**, `4x` Comp (`8614` vec), Hybrid `1884` vec (`5.72x` data red.), 3-corner SDF GLS |

> **Why Vivado Baseline (`534 LUTs / 625 FFs`) vs. Yosys (`soc_func_logic`) Differ**: In the standalone Vivado Artix-7 synthesis of the baseline core, Vivado inferred Distributed `LUTRAM` for the register file and pruned unobserved debug outputs. In the ASIC scan-ready flow (`soc_func_logic`), the `32x32` register file, 5-stage pipeline, and integrated 32-bit 2-way D-cache controller are explicitly synthesized into `1,586` scan-stitchable `sg13g2_dfrbpq_1` flip-flops backed by `4x sram_sync_sp` SRAM macros alongside `100%` of IEEE 1500 / MBIST / JTAG / OCC / compactor DFT hardware.

## 4. Extracted ASIC Schematics

- **Full Post-Stitch ASIC SoC Schematic**: [asic_soc_dft_schematic.png](../docs/figures/asic_soc_dft_schematic.png) ([SVG](../docs/figures/asic_soc_dft_schematic.svg))
- **Glitch-Free OCC Stdcell Gate Schematic (`IHP SG13G2`)**: [asic_occ_gate_schematic.png](../docs/figures/asic_occ_gate_schematic.png) ([SVG](../docs/figures/asic_occ_gate_schematic.svg))
