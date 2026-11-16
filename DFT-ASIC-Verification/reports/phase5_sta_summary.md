# Phase 5 — Multi-Mode, Multi-Corner OpenSTA Timing Closure Report

- **ECO Buffering & Sizing (`cts_fanout_buf.py`)**: `max_fanout=12`, `295` high-fanout nets buffered (`+1,666` `sg13g2_buf_16`/`buf_4` cells), `831` multi-fanout `_1 -> _2` gate upsizes, `5` scan-mux inputs unaliased.

| Mode | PVT Corner | Clock Period (`ns`) | Worst Setup Slack (`ns`) | Setup TNS (`ns`) | Worst Hold Slack (`ns`) | Hold TNS (`ns`) | Est. Max Freq (`MHz`) | Status |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| `func` | `typ` | 10.0 | +4.10 | 0.00 | +0.10 | 0.00 | 169.49 | **PASS** |
| `func` | `slow` | 10.0 | +0.95 | 0.00 | +0.24 | 0.00 | 110.50 | **PASS** |
| `func` | `fast` | 10.0 | +5.99 | 0.00 | +0.04 | 0.00 | 249.38 | **PASS** |
| `scan_shift` | `typ` | 100.0 | +4.46 | 0.00 | +0.09 | 0.00 | 10.47 | **PASS** |
| `scan_shift` | `slow` | 100.0 | +4.12 | 0.00 | +0.23 | 0.00 | 10.43 | **PASS** |
| `scan_shift` | `fast` | 100.0 | +4.64 | 0.00 | +0.01 | 0.00 | 10.49 | **PASS** |
| `scan_capture` | `typ` | 10.0 | +4.10 | 0.00 | +0.12 | 0.00 | 169.49 | **PASS** |
| `scan_capture` | `slow` | 10.0 | +0.95 | 0.00 | +0.24 | 0.00 | 110.50 | **PASS** |
| `scan_capture` | `fast` | 10.0 | +4.39 | 0.00 | +0.05 | 0.00 | 178.25 | **PASS** |

## Inter-Domain Scan Skew Hold Closure (`DBG-02`, Propagated Fast Corner `1.32V / -40C`)

- **Without Lockup Latch (`dbg02_buggy`)**: Inter-domain Hold Slack = **`-0.42 ns`** (`VIOLATED`, `TNS = -0.42 ns`) — `_15177_ -> _scan_mux_269_ -> _15178_` shoots through when `clk_dom1` arrives after `16x sg13g2_buf_4` skew.
- **With Negative-Edge Lockup Latch (`dbg02_fixed`, `sg13g2_dllrq_1`)**: Inter-domain Hold Slack = **`+49.38 ns`** (`MET`, chip-wide `worst_hold = +0.19 ns`, `TNS = 0.00 ns`) — half-cycle hold protection isolates inter-clock skew cleanly.
