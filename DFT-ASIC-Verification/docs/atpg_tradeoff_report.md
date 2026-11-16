# Phase 4 — Synthesis, Scan Stitching, ATPG & Trade-Off Report

## 1. Executive Summary & Synthesis Baseline (IHP SG13G2 `typ_1p20V_25C`)

All combinational/sequential logic of the RV32I processor and 2-way set-associative cache controller is grouped into **`soc_func_logic`** with the 4 `sram_sync_sp` SRAM macros isolated outside the scan/ATPG boundary (tested separately via MBIST).

| Module | Cell Count | Sequential FFs (`sg13g2_dfrbpq_1`) | `sg13g2_mux2_1` (Added Scan) | Post-Opt Area (`um^2`) |
| :--- | :---: | :---: | :---: | :---: |
| `soc_func_logic` (No-Scan Baseline) | 9,658 | 2,151 | 692 (+0) | 180,114.62 |
| `soc_func_logic` (1-Ch Scan Stitched) | 11,809 | 2,151 | 2,843 (+2,151) | 219,142.36 |
| `soc_func_logic` (4-Ch Scan Stitched) | 11,809 | 2,151 | 2,843 (+2,151) | 219,142.36 |
| `soc_func_logic` (8-Ch Scan Stitched) | 11,809 | 2,151 | 2,843 (+2,151) | 219,142.36 |
| `scan_comp_wrap` (`2:8`/`8:2` + `16`-bit MISR) | 145 | 24 | 0 (+0) | 2,329.35 |

- **ATPG Extraction (`AUCOHL Fault cut` -> `nl2bench` -> `Atalanta 2.0`)**: `41,842` collapsed stuck-at faults (`0` aborted, `7` redundant).
- **Atalanta Pattern Compaction**: Uncompacted (`-N`): **`9,521`** patterns (14.79 s) vs. Reverse-Order + Shuffle Compacted (`-c 2`): **`7,388`** patterns (21.85 s) — a **`22.4%`** vector count reduction at zero coverage loss.

## 2. Scan Architecture Trade-Off Comparison Table

| Mode | Chains (`L_max`) | ATE Pins (`SI+SO`) | Total Area (`um^2`) | Area Overhead (%) | Vectors | Shift Cycles | Speedup vs 1-Ch | ATE In-Bits (`Mb`) | Data Comp | Cov (All POs / Scan-Out) |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| No-Scan Baseline | 0 (-) | 0 | 180,114.6 | +0.00% | 0 | 0 | 0.00x | 0.00 | 0.00x | - / - |
| 1-Chain Uncompressed (No-Comp ATPG) | 1 (2151) | 2 | 219,142.4 | +21.67% | 9,521 | 20,491,343 | 0.78x | 20.48 | 0.78x | 99.983% / 97.163% |
| 1-Chain Uncompressed (Compacted) | 1 (2151) | 2 | 219,142.4 | +21.67% | 7,388 | 15,901,127 | 1.00x | 15.89 | 1.00x | 99.983% / 97.163% |
| 4-Chain Uncompressed (Compacted) | 4 (538) | 8 | 219,142.4 | +21.67% | 7,388 | 3,982,670 | 3.99x | 15.90 | 1.00x | 99.983% / 97.163% |
| 8-Chain Uncompressed (Compacted) | 8 (269) | 16 | 219,142.4 | +21.67% | 7,388 | 1,995,029 | 7.97x | 15.90 | 1.00x | 99.983% / 97.163% |
| 4-Chain 1:4/4:1 Compressed | 4 (538) | 2 | 221,471.7 | +22.96% | 7,388 | 3,982,670 | 3.99x | 3.97 | 4.00x | - / 97.163% |
| 8-Chain 2:8/8:2 Compressed (RTL) | 8 (269) | 4 | 221,471.7 | +22.96% | 7,388 | 1,995,029 | 7.97x | 3.97 | 4.00x | - / 97.163% |
| 8-Chain 1:8/8:1 Compressed | 8 (269) | 2 | 221,471.7 | +22.96% | 7,388 | 1,995,029 | 7.97x | 1.99 | 8.00x | - / 97.163% |
| 8-Chain 2:8/8:2 + Ch3 X-Mask | 8 (269) | 4 | 221,471.7 | +22.96% | 7,388 | 1,995,029 | 7.97x | 3.97 | 4.00x | - / 90.899% |
| PRPG 2:8 LFSR-Only (512v) | 8 (269) | 4 | 221,471.7 | +22.96% | 512 | 138,509 | 114.80x | 0.28 | 57.69x | 94.197% / 91.377% |
| PRPG 2:8 LFSR-Only (4096v) | 8 (269) | 4 | 221,471.7 | +22.96% | 4,096 | 1,106,189 | 14.37x | 2.20 | 7.21x | 96.379% / 93.559% |
| Hybrid 2:8 LFSR(512) + TopOff | 8 (269) | 4 | 221,471.7 | +22.96% | 1,233 | 333,179 | 47.73x | 1.83 | 8.70x | 99.983% / 97.163% |

## 3. 2:8 Hardware LFSR+XOR Decompressor PRPG Curve (`32 .. 4096` Vectors)

Simulating `rtl/dft/scan_comp_wrap.sv` exact LFSR polynomial (`x^8+x^6+x^5+x^4+1`, init `0xA5`) fed by 2 ATE scan-in channels vs. unconstrained full-chip PRPG and per-shift-slice XOR compactors:

| Vectors | Unconstrained PRPG (All PO) | 2:8 LFSR Decomp (All PO) | 2:8 Decomp + 8:2 XOR (Scan-Out) | 2:8 Decomp + 8:1 XOR (Scan-Out) | 8:2 XOR w/ Ch3 X-Mask (Scan-Out) |
| :---: | :---: | :---: | :---: | :---: | :---: |
| 32 | 70.847% | 72.002% | 69.191% | 69.191% | 63.981% |
| 64 | 80.171% | 79.788% | 76.968% | 76.968% | 71.763% |
| 128 | 87.735% | 86.454% | 83.634% | 83.634% | 78.060% |
| 256 | 92.331% | 91.721% | 88.901% | 88.901% | 82.859% |
| 512 | 94.647% | 94.197% | 91.377% | 91.377% | 85.158% |
| 1024 | 95.777% | 95.571% | 92.751% | 92.751% | 86.506% |
| 2048 | 96.303% | 96.167% | 93.346% | 93.346% | 87.104% |
| 4096 | 96.456% | 96.379% | 93.559% | 93.559% | 87.317% |

## 4. Key Architectural Findings

1. **Shift-Time vs. Pin-Count Scaling**: Splitting the `2,151` FFs from 1 chain (`L_max=2,151`) to 8 balanced chains (`L_max=269`) reduces scan shift cycles by **7.97x** (`15,901,127` -> `1,995,029` cycles) at **zero additional scan-mux silicon cost** (`+39,027.74 um^2` = `+21.67%` fixed across 1, 4, and 8 chains).
2. **4x ATE Pin & Data Volume Compression**: Adding `scan_comp_wrap` (`+2,329.3 um^2`, only `+1.29%` additional overhead) achieves the full **~8x test-time speedup** of 8 chains using only **4 external scan pins** (`2 SI + 2 SO`, down from `16` uncompressed pins) and reduces external scan-in data volume by **4.00x** (`3.97 Mb` vs. `15.90 Mb`), with **0.000% spatial XOR aliasing loss** across per-shift-slice buckets (`97.163%` scan-out observability matching uncompressed scan-out `97.163%`).
3. **Internal Scan vs. Unwrapped Macro Outputs (`97.163%` vs. `99.983%`)**: Pure internal scan FF observation detects `40,655 / 41,842` faults (`97.163%`). The `1,180`-fault (`2.82%`) gap originates cleanly in combinational cones feeding module outputs and black-box `sram_sync_sp` ports (`sram_wdata`, `sram_wtag0/1`, `alu_obs`) lacking shadow capture FFs at the macro boundary — quantifying why full-SoC closure requires IEEE 1500 / wrapper cells around memory/probe outputs.
4. **LFSR PRPG vs. Hybrid Top-Off**: The 2:8 LFSR+XOR phase-shifter matches unconstrained PRPG (`96.379%` vs. `96.456%` at 4,096 vectors) with rapid saturation above 512 vectors; topping up 512 2:8 LFSR vectors (`2` SI pins, `0.28 Mb`) with **`721`** 8-chain deterministic top-off vectors (`1.53 Mb`) restores the full **`99.983%`** stuck-at ceiling in `1,233` total vectors (`8.70x` ATE scan-in volume reduction vs. 1-chain deterministic).
5. **X-Masking Coverage Penalty**: Asserting `chain_x_mask = 8'h08` (masking Chain 3's 269 FFs to isolate an unknown `X` source before MISR compaction) cleanly contains corruption at a measured cost of `-6.264%` scan-out fault coverage.

## 5. Visualization

![Phase 4 ATPG Trade-Off Charts](figures/atpg_tradeoff_charts.png)
