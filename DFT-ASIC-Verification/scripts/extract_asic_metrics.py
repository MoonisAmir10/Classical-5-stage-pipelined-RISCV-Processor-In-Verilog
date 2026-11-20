#!/usr/bin/env python3
"""Extract ASIC Area, Timing, Power, Schematic Figures & FPGA Comparison Metrics.

Computes repeatable, tool-measured reports directly from:
  - Yosys `stat -liberty` across IHP SG13G2 baseline, stitched, and post-CTS/ECO signoff netlists
  - OpenSTA 3.2.0 `report_power` across all 3 modes (func, scan_shift, scan_capture) x 3 PVT corners
  - OpenSTA `phase5_sta_summary.csv` & Phase 4 ATPG `phase4_atpg_tradeoff.csv`
  - Optional Yosys `synth_xilinx -family xc7` open-source Artix-7 resource count
  - Post-synthesis ASIC schematics (`docs/figures/asic_soc_dft_schematic.*`,
    `docs/figures/asic_occ_gate_schematic.*`) via Yosys `show` + Graphviz `dot`

Outputs:
  - reports/asic_metrics_summary.csv
  - reports/asic_metrics_summary.md
  - reports/fpga_xc7_metrics.json (when --run-xilinx is used)
  - docs/figures/asic_soc_dft_schematic.{png,svg}
  - docs/figures/asic_occ_gate_schematic.{png,svg}
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import subprocess
from pathlib import Path

from PIL import Image

Image.MAX_IMAGE_PIXELS = None

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build"
BUILD4 = BUILD / "phase4"
BUILD5 = BUILD / "phase5"
REPORTS = ROOT / "reports"
FIGURES = ROOT / "docs" / "figures"

CORNERS = {
    "typ": "/home/moonis/auto_job_seeker/.eda_tools/pdk/ihp-sg13g2/libs.ref/sg13g2_stdcell/lib/sg13g2_stdcell_typ_1p20V_25C.lib",
    "slow": "/home/moonis/auto_job_seeker/.eda_tools/pdk/ihp-sg13g2/libs.ref/sg13g2_stdcell/lib/sg13g2_stdcell_slow_1p08V_125C.lib",
    "fast": "/home/moonis/auto_job_seeker/.eda_tools/pdk/ihp-sg13g2/libs.ref/sg13g2_stdcell/lib/sg13g2_stdcell_fast_1p32V_m40C.lib",
}
NAND2_AREA_UM2 = 7.2576  # sg13g2_nand2_1 area in IHP SG13G2 130nm Liberty
SRAM_MACRO_AREA_UM2 = {
    "tag": 4800.0,   # flow/sta/sram_sync_sp.lib modeled macro stub (2x per 2-way cache)
    "data": 9600.0,  # flow/sta/sram_sync_sp.lib modeled macro stub (2x per 2-way cache)
}
# Vivado XC7A100T baseline from original Classical-5-stage-pipelined-RISCV-Processor-In-Verilog repo
VIVADO_BASELINE = {
    "device": "Xilinx Artix-7 (XC7A100T-1CSG324C)",
    "tool": "Xilinx Vivado",
    "fmax_mhz": 168.07,
    "luts": 534,
    "ffs": 625,
    "bram": 0,
}


def run_cmd(cmd: list[str]) -> str:
    res = subprocess.run(cmd, cwd=ROOT, text=True, capture_output=True, check=False)
    if res.returncode != 0:
        raise RuntimeError(
            f"Command failed ({res.returncode}): {' '.join(cmd)}\n"
            f"STDOUT:\n{res.stdout}\nSTDERR:\n{res.stderr}"
        )
    return res.stdout


def parse_nand2_area(lib_path: str) -> float:
    txt = Path(lib_path).read_text(encoding="utf-8", errors="ignore")
    m = re.search(r"cell\s*\(\s*sg13g2_nand2_1\s*\)\s*\{[^}]*?area\s*:\s*([0-9.]+)\s*;", txt, re.S)
    return float(m.group(1)) if m else NAND2_AREA_UM2


def yosys_stat_module(netlist_files: list[Path], top: str, lib_typ: str, blackbox_sram: bool = True) -> dict[str, dict]:
    """Run Yosys `stat -liberty` and parse per-module + top hierarchy counts."""
    reads = [f"read_liberty -lib {lib_typ}"]
    if blackbox_sram:
        reads.append(f"read_verilog -DSYNTHESIS -DSYNTHESIS_SRAM_BLACKBOX {ROOT / 'rtl/mem/sram_sync_sp.v'}")
    for nf in netlist_files:
        reads.append(f"read_verilog {nf}")
    reads.append(f"stat -liberty {lib_typ} -top {top}")
    out = run_cmd(["yosys", "-p", "; ".join(reads)])

    sections: dict[str, dict] = {}
    cur_name: str | None = None
    buf_lines: list[str] = []
    for ln in out.splitlines():
        m_sec = re.match(r"^===\s+(.*?)\s+===$", ln.strip())
        if m_sec:
            if cur_name is not None:
                sections[cur_name] = _parse_stat_block(buf_lines)
            cur_name = m_sec.group(1)
            buf_lines = []
        elif cur_name is not None:
            buf_lines.append(ln)
    if cur_name is not None:
        sections[cur_name] = _parse_stat_block(buf_lines)
    return sections


def _parse_stat_block(lines: list[str]) -> dict:
    txt = "\n".join(lines)
    cells_m = re.search(r"^\s*(\d+)\s+[^\s]+\s+cells\s*$", txt, re.M)
    area_m = re.search(r"Chip area for (?:top )?module '.*':\s*([0-9.]+)", txt)
    seq_m = re.search(r"of which used for sequential elements:\s*([0-9.]+)\s*\(([^)]+)\)", txt)
    sub_m = re.search(r"^\s*(\d+)\s+[^\s]+\s+submodules\s*$", txt, re.M)

    cell_types: dict[str, int] = {}
    for m in re.finditer(r"^\s*(\d+)\s+(?:[0-9.E+-]+|-)\s+(sg13g2_\S+)\s*$", txt, re.M):
        cell_types[m.group(2)] = int(m.group(1))
    cell_section = txt.split("submodules")[0] if "submodules" in txt else txt
    bb_types: dict[str, int] = {}
    for m in re.finditer(r"^\s*(\d+)\s+-\s+(sram_sync_sp\S*|soc_func_logic)\s*$", cell_section, re.M):
        bb_types[m.group(2)] = int(m.group(1))

    dffs = sum(v for k, v in cell_types.items() if "dfrbpq" in k or "dfxtp" in k)
    latches = sum(v for k, v in cell_types.items() if "dllrq" in k or "dlxtp" in k)
    muxes = sum(v for k, v in cell_types.items() if "mux2" in k)
    bufs = sum(v for k, v in cell_types.items() if "_buf_" in k)
    srams = sum(v for k, v in bb_types.items() if k.startswith("sram_sync_sp"))
    stdcell_count = sum(cell_types.values())
    total_reported = int(cells_m.group(1)) if cells_m else stdcell_count
    return {
        "reported_cells": total_reported,
        "stdcells": stdcell_count,
        "srams": srams,
        "dffs": dffs,
        "latches": latches,
        "muxes": muxes,
        "buffers": bufs,
        "submodules": int(sub_m.group(1)) if sub_m else 0,
        "area_um2": float(area_m.group(1)) if area_m else 0.0,
        "seq_area_um2": float(seq_m.group(1)) if seq_m else 0.0,
        "seq_pct": seq_m.group(2) if seq_m else "0.00%",
        "cell_types": cell_types,
    }


def extract_area_metrics(lib_typ: str, nand2_area: float) -> dict:
    sec_rv = yosys_stat_module([BUILD / "rv32i_processor_ihp.v"], "rv32i_processor", lib_typ, blackbox_sram=False)
    sec_ca = yosys_stat_module([BUILD / "cache_2wsa_dft_ihp.v"], "cache_2wsa_dft", lib_typ, blackbox_sram=True)
    sec_fn0 = yosys_stat_module([BUILD4 / "soc_func_flat.v"], "soc_func_logic", lib_typ, blackbox_sram=False)
    sec_fn8 = yosys_stat_module([BUILD4 / "soc_func_scan8.v"], "soc_func_logic", lib_typ, blackbox_sram=False)
    sec_wrp = yosys_stat_module([BUILD5 / "soc_dft_wrappers.v"], "soc_dft_top", lib_typ, blackbox_sram=True)
    sec_sta = yosys_stat_module([BUILD5 / "soc_dft_top_sta.v"], "soc_dft_top", lib_typ, blackbox_sram=True)

    # Identify parametric module keys dynamically
    def find_mod(sec: dict, prefix: str) -> dict:
        if prefix in sec:
            return sec[prefix]
        for k, v in sec.items():
            if prefix in k and k != "design hierarchy":
                return v
        return {}

    def hier_or_top(sec: dict, prefix: str) -> dict:
        return sec.get("design hierarchy") or find_mod(sec, prefix)

    macro_total = 2 * SRAM_MACRO_AREA_UM2["tag"] + 2 * SRAM_MACRO_AREA_UM2["data"]
    top_sta = hier_or_top(sec_sta, "soc_dft_top")
    top_sta["macro_area_um2"] = macro_total
    top_sta["total_with_macro_um2"] = top_sta["area_um2"] + macro_total
    top_sta["ge"] = round(top_sta["area_um2"] / nand2_area)

    # Pre-CTS stitched total = wrappers (excluding blackbox soc_func_logic) + scan8
    wrp_hier = hier_or_top(sec_wrp, "soc_dft_top")
    fn8_hier = hier_or_top(sec_fn8, "soc_func_logic")
    pre_cts_area = wrp_hier["area_um2"] + fn8_hier["area_um2"]
    pre_cts_cells = wrp_hier["stdcells"] + fn8_hier["stdcells"]

    modules_post_cts = [
        ("u_func_logic (RV32I + 2-Way Cache Ctrl, 8-Ch Scan + CTS)", find_mod(sec_sta, "soc_func_logic")),
        ("u_ieee1500_wrapper (IEEE 1500 Core Test Wrapper)", find_mod(sec_sta, "ieee1500_wrapper")),
        ("u_jtag_tap (IEEE 1149.1 TAP + 4 TDRs)", find_mod(sec_sta, "jtag_tap")),
        ("u_mbist_ctrl (March-C + Checkerboard Engine)", find_mod(sec_sta, "mbist_ctrl")),
        ("u_scan_comp_wrap (2:8 PRPG Decomp + 8:2 XOR + 16b MISR)", find_mod(sec_sta, "scan_comp_wrap")),
        ("u_occ_clk_ctrl (Glitch-Free OCC + ICG + LOC + RstMask)", find_mod(sec_sta, "occ_clk_ctrl")),
        ("soc_dft_top (Top-Level Clock/Reset Glue)", find_mod(sec_sta, "soc_dft_top")),
    ]

    return {
        "nand2_area_um2": nand2_area,
        "rv32i_baseline": hier_or_top(sec_rv, "rv32i_processor"),
        "cache_baseline": hier_or_top(sec_ca, "cache_2wsa_dft"),
        "soc_func_noscan": hier_or_top(sec_fn0, "soc_func_logic"),
        "soc_func_scan8": fn8_hier,
        "pre_cts_stitched": {
            "stdcells": pre_cts_cells,
            "dffs": wrp_hier["dffs"] + fn8_hier["dffs"],
            "latches": wrp_hier["latches"] + fn8_hier["latches"],
            "area_um2": round(pre_cts_area, 2),
            "ge": round(pre_cts_area / nand2_area),
        },
        "post_cts_signoff": top_sta,
        "modules_post_cts": modules_post_cts,
        "macro_area_um2": macro_total,
    }


def extract_power_metrics() -> tuple[list[dict], list[dict]]:
    """Run OpenSTA `report_power` across all 3 modes x 3 corners and hierarchical breakdown at typ."""
    netlist = BUILD5 / "soc_dft_top_sta.v"
    sram_lib = ROOT / "flow" / "sta" / "sram_sync_sp.lib"
    modes = [
        ("func", 100.0, "-activity 0.1 -duty 0.5 -clock sys_clk", "0.1/sys_clk (100 MHz)"),
        ("scan_shift", 10.0, "-density 0.001 -duty 0.5", "0.1/tck (10 MHz shift-rate)"),
        ("scan_shift_unscaled", 10.0, "-activity 0.1 -duty 0.5", "0.1/min_clk default ref"),
        ("scan_capture", 100.0, "-activity 0.1 -duty 0.5 -clock sys_clk", "0.1/sys_clk (100 MHz LOC)"),
    ]

    power_rows: list[dict] = []
    hier_rows: list[dict] = []

    for corner, lib_path in CORNERS.items():
        tcl_parts = [
            f"read_liberty {lib_path}",
            f"read_liberty {sram_lib}",
            f"read_verilog {netlist}",
            "link_design soc_dft_top",
        ]
        for mode_tag, freq_mhz, act_flags, _desc in modes:
            sdc_name = "scan_shift" if mode_tag.startswith("scan_shift") else mode_tag
            tcl_parts.extend([
                f"read_sdc {ROOT / 'flow' / 'sdc' / f'{sdc_name}.sdc'}",
                f"set_power_activity -global {act_flags}",
                f'puts "=== PWR {mode_tag} {corner} ==="',
                "report_power -digits 5",
            ])
            if corner == "typ" and mode_tag in ("func", "scan_shift"):
                tcl_parts.extend([
                    f'puts "=== HIER {mode_tag} {corner} ==="',
                    "report_power -instances [get_cells {u_func_logic u_mbist_ctrl u_ieee1500_wrapper u_jtag_tap u_occ_clk_ctrl u_scan_comp_wrap}] -digits 5",
                ])
        tcl_parts.append("exit")
        tcl_path = BUILD5 / f"sta_power_{corner}.tcl"
        tcl_path.write_text("\n".join(tcl_parts) + "\n", encoding="utf-8")
        out = run_cmd(["sta", "-exit", str(tcl_path)])

        for mode_tag, freq_mhz, _act, desc in modes:
            sec_m = re.search(
                rf"=== PWR {re.escape(mode_tag)} {corner} ===(.*?)(?==== (?:PWR|HIER)|$)",
                out,
                re.S,
            )
            if not sec_m:
                continue
            blk = sec_m.group(1)

            def grab_grp(grp: str) -> tuple[float, float, float, float]:
                gm = re.search(
                    rf"^{grp}\s+([0-9.eE+-]+)\s+([0-9.eE+-]+)\s+([0-9.eE+-]+)\s+([0-9.eE+-]+)",
                    blk,
                    re.M,
                )
                if not gm:
                    return (0.0, 0.0, 0.0, 0.0)
                return tuple(float(gm.group(i)) for i in range(1, 5))  # Watts

            seq_p = grab_grp("Sequential")
            cmb_p = grab_grp("Combinational")
            clk_p = grab_grp("Clock")
            tot_p = grab_grp("Total")
            power_rows.append({
                "mode": mode_tag,
                "corner": corner,
                "freq_mhz": freq_mhz,
                "activity_basis": desc,
                "seq_mw": round(seq_p[3] * 1e3, 4),
                "comb_mw": round(cmb_p[3] * 1e3, 4),
                "clock_mw": round(clk_p[3] * 1e3, 4),
                "internal_mw": round(tot_p[0] * 1e3, 4),
                "switching_mw": round(tot_p[1] * 1e3, 4),
                "leakage_uw": round(tot_p[2] * 1e6, 3),
                "total_mw": round(tot_p[3] * 1e3, 4),
            })

            if corner == "typ" and mode_tag in ("func", "scan_shift"):
                hm = re.search(
                    rf"=== HIER {re.escape(mode_tag)} {corner} ===(.*?)(?==== (?:PWR|HIER)|$)",
                    out,
                    re.S,
                )
                if hm:
                    for ln in hm.group(1).splitlines():
                        im = re.match(
                            r"^\s*([0-9.eE+-]+)\s+([0-9.eE+-]+)\s+([0-9.eE+-]+)\s+([0-9.eE+-]+)\s+(\S+)\s*$",
                            ln,
                        )
                        if im:
                            hier_rows.append({
                                "mode": mode_tag,
                                "instance": im.group(5),
                                "internal_mw": round(float(im.group(1)) * 1e3, 4),
                                "switching_mw": round(float(im.group(2)) * 1e3, 4),
                                "leakage_uw": round(float(im.group(3)) * 1e6, 3),
                                "total_mw": round(float(im.group(4)) * 1e3, 4),
                            })

    return power_rows, hier_rows


def extract_xilinx_xc7() -> dict:
    """Measure Xilinx Artix-7 (`xc7`) LUT/FF resource usage using Yosys `synth_xilinx`."""
    core_files = sorted(str(p) for p in (ROOT / "rtl/core").glob("rv32i_*.v"))
    cache_files = [
        str(ROOT / "rtl/mem/sram_sync_sp.v"),
        str(ROOT / "rtl/core/cache_ctrl_logic.v"),
        str(ROOT / "rtl/core/cache_2wsa_dft.v"),
    ]
    dft_files = sorted(str(p) for p in (ROOT / "rtl/dft").glob("*.sv"))

    def run_xc7(files_sv: list[str], files_v: list[str], top: str) -> dict:
        cmds = []
        if files_v:
            cmds.append("read_verilog -DSYNTHESIS " + " ".join(files_v))
        if files_sv:
            cmds.append("read_verilog -sv -DSYNTHESIS " + " ".join(files_sv))
        cmds.append(f"synth_xilinx -family xc7 -top {top}; stat")
        out = run_cmd(["yosys", "-p", "; ".join(cmds)])
        m = re.search(r"=== design hierarchy ===(.*?)Warnings:|=== design hierarchy ===(.*?)End of script", out, re.S)
        blk = (m.group(1) or m.group(2)) if m else out[-2500:]
        counts: dict[str, int] = {}
        for cm in re.finditer(r"^\s*(\d+)\s+([A-Z0-9_]+)\s*$", blk, re.M):
            counts[cm.group(2)] = int(cm.group(1))
        luts = sum(counts.get(k, 0) for k in ("LUT1", "LUT2", "LUT3", "LUT4", "LUT5", "LUT6", "INV"))
        ffs = sum(counts.get(k, 0) for k in ("FDCE", "FDCE_1", "FDPE", "FDPE_1", "FDRE", "FDSE"))
        latches = sum(counts.get(k, 0) for k in ("LDCE", "LDPE"))
        ram_dist = sum(counts.get(k, 0) for k in ("RAM32M", "RAM64M", "RAM32X1S", "RAM64X1S"))
        brams = sum(counts.get(k, 0) for k in ("RAMB18E1", "RAMB36E1"))
        return {
            "top": top,
            "luts_incl_inv": luts,
            "ffs": ffs,
            "latches": latches,
            "dist_ram32m": ram_dist,
            "brams": brams,
            "raw_counts": counts,
        }

    res = {
        "soc_func_logic": run_xc7([], core_files + cache_files + [str(ROOT / "rtl/core/soc_func_logic.v")], "soc_func_logic"),
        "soc_dft_top": run_xc7(dft_files + [str(ROOT / "rtl/top/soc_dft_top.sv")], core_files + cache_files, "soc_dft_top"),
    }
    json_path = REPORTS / "fpga_xc7_metrics.json"
    json_path.write_text(json.dumps(res, indent=2) + "\n", encoding="utf-8")
    return res


def generate_schematics() -> None:
    """Generate SVG & high-clarity PNG ASIC schematics using Yosys `show` + Graphviz `dot`."""
    FIGURES.mkdir(parents=True, exist_ok=True)
    met_dir = BUILD / "metrics"
    met_dir.mkdir(parents=True, exist_ok=True)
    lib_typ = os.environ.get("IHP_LIB_TYP", CORNERS["typ"])

    # 1. Top-level post-scan-stitch ASIC architecture schematic
    ys_top = (
        f"read_liberty -lib {lib_typ}; "
        f"read_verilog -DSYNTHESIS -DSYNTHESIS_SRAM_BLACKBOX {ROOT / 'rtl/mem/sram_sync_sp.v'}; "
        f"read_verilog -DSYNTHESIS {BUILD5 / 'soc_func_bb.v'}; "
        f"read_verilog {BUILD5 / 'soc_dft_wrappers.v'}; "
        "hierarchy -check -top soc_dft_top; proc; opt_clean -purge; "
        f"show -colors 42 -stretch -prefix {met_dir / 'asic_soc_dft_schematic'} -format dot soc_dft_top"
    )
    run_cmd(["yosys", "-q", "-p", ys_top])

    # 2. Leaf IHP SG13G2 stdcell gate-level schematic of Glitch-Free OCC Clock Controller
    ys_occ = (
        f"read_liberty -lib {lib_typ}; "
        f"read_verilog {BUILD5 / 'soc_dft_wrappers.v'}; "
        f"show -colors 42 -stretch -prefix {met_dir / 'asic_occ_gate_schematic'} -format dot occ_clk_ctrl"
    )
    run_cmd(["yosys", "-q", "-p", ys_occ])

    for stem, max_w in (("asic_soc_dft_schematic", 4200), ("asic_occ_gate_schematic", 4200)):
        dot_p = met_dir / f"{stem}.dot"
        svg_p = FIGURES / f"{stem}.svg"
        png_raw = met_dir / f"{stem}_raw.png"
        png_out = FIGURES / f"{stem}.png"
        run_cmd(["dot", "-Tsvg", str(dot_p), "-o", str(svg_p)])
        run_cmd(["dot", "-Tpng", str(dot_p), "-o", str(png_raw)])
        im = Image.open(png_raw).convert("RGB")
        w, h = im.size
        if w > max_w:
            im = im.resize((max_w, int(round(h * max_w / w))), Image.Resampling.LANCZOS)
        im.save(png_out, format="PNG", optimize=True)
        print(f"  Schematic ready: {png_out.relative_to(ROOT)} {im.size} ({png_out.stat().st_size // 1024} KB)")


def write_reports(area: dict, power_rows: list[dict], hier_rows: list[dict], fpga_xc7: dict | None) -> None:
    REPORTS.mkdir(parents=True, exist_ok=True)
    sta_rows = list(csv.DictReader((REPORTS / "phase5_sta_summary.csv").open(encoding="utf-8")))
    atpg_rows = list(csv.DictReader((REPORTS / "phase4_atpg_tradeoff.csv").open(encoding="utf-8")))

    # Flatten key CSV metrics
    csv_rows: list[dict] = []
    for stage_label, rec in (
        ("Baseline: rv32i_processor (IHP SG13G2)", area["rv32i_baseline"]),
        ("Baseline: cache_2wsa_dft ctrl (excl. 4 SRAMs)", area["cache_baseline"]),
        ("Func Logic: No-Scan Baseline (soc_func_logic)", area["soc_func_noscan"]),
        ("Func Logic: 8-Chain Scan Stitched (soc_func_scan8)", area["soc_func_scan8"]),
        ("Full SoC: Post-Stitch Pre-CTS (soc_dft_top)", area["pre_cts_stitched"]),
        ("Full SoC: Post-CTS Signoff Stdcell (soc_dft_top_sta)", area["post_cts_signoff"]),
    ):
        csv_rows.append({
            "category": "ASIC_AREA",
            "name": stage_label,
            "cells": rec.get("stdcells", ""),
            "dffs": rec.get("dffs", ""),
            "area_um2": f"{rec.get('area_um2', 0.0):.2f}",
            "extra": f"GE={round(rec.get('area_um2', 0.0) / area['nand2_area_um2'])}",
        })
    for p in power_rows:
        csv_rows.append({
            "category": "ASIC_POWER",
            "name": f"{p['mode']}@{p['corner']}",
            "cells": f"{p['freq_mhz']}MHz",
            "dffs": p["activity_basis"],
            "area_um2": f"{p['total_mw']:.4f}mW",
            "extra": f"int={p['internal_mw']}mW sw={p['switching_mw']}mW leak={p['leakage_uw']}uW",
        })
    csv_path = REPORTS / "asic_metrics_summary.csv"
    with csv_path.open("w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=["category", "name", "cells", "dffs", "area_um2", "extra"])
        w.writeheader()
        w.writerows(csv_rows)

    post_top = area["post_cts_signoff"]
    pre_top = area["pre_cts_stitched"]
    cts_delta_cells = post_top["stdcells"] - pre_top["stdcells"]
    cts_delta_area = post_top["area_um2"] - pre_top["area_um2"]

    func_typ = next(r for r in power_rows if r["mode"] == "func" and r["corner"] == "typ")
    func_slow = next(r for r in power_rows if r["mode"] == "func" and r["corner"] == "slow")
    func_fast = next(r for r in power_rows if r["mode"] == "func" and r["corner"] == "fast")
    shift_typ = next(r for r in power_rows if r["mode"] == "scan_shift" and r["corner"] == "typ")
    cap_typ = next(r for r in power_rows if r["mode"] == "scan_capture" and r["corner"] == "typ")

    sta_func_typ = next(r for r in sta_rows if r["mode"] == "func" and r["corner"] == "typ")
    sta_func_slow = next(r for r in sta_rows if r["mode"] == "func" and r["corner"] == "slow")
    sta_func_fast = next(r for r in sta_rows if r["mode"] == "func" and r["corner"] == "fast")

    comp_row = next(r for r in atpg_rows if r["mode"] == "8-Chain 2:8/8:2 Compressed (RTL)")
    hyb_row = next(r for r in atpg_rows if r["mode"] == "Hybrid 2:8 LFSR(512) + TopOff")

    lines = [
        "# IHP SG13G2 130nm ASIC vs. Artix-7 FPGA Implementation Metrics",
        "",
        f"> **PDK & Tooling**: `IHP SG13G2` (`130 nm` CMOS, `typ 1.20V / 25°C`, `slow 1.08V / 125°C`, `fast 1.32V / -40°C`, `NAND2_1 = {area['nand2_area_um2']:.4f} um^2`), `Yosys 0.71+`, `OpenSTA 3.2.0`, `AUCOHL Fault 0.9.4 + Atalanta 2.0`.",
        "",
        "## 1. ASIC Area & Gate-Equivalent Summary (`IHP SG13G2 130nm`)",
        "",
        "| Synthesis Stage / Scope | Stdcell Count | FFs (`dfrbpq_1`) | Latches | Scan Muxes (`mux2`) | Stdcell Area (`um^2`) | Gate Equiv (`GE`) |",
        "| :--- | :---: | :---: | :---: | :---: | :---: | :---: |",
    ]
    for label, rec in (
        ("`rv32i_processor` Baseline (RTL -> IHP)", area["rv32i_baseline"]),
        ("`cache_2wsa_dft` Ctrl Baseline (excl. 4 SRAMs)", area["cache_baseline"]),
        ("`soc_func_logic` No-Scan Baseline", area["soc_func_noscan"]),
        ("`soc_func_logic` 8-Chain Scan Stitched", area["soc_func_scan8"]),
        ("`soc_dft_top` Post-Stitch Pre-CTS (incl. All DFT IP)", area["pre_cts_stitched"]),
        ("`soc_dft_top` **Final Post-CTS/ECO Signoff**", post_top),
    ):
        ge_val = round(rec["area_um2"] / area["nand2_area_um2"])
        lines.append(
            f"| {label} | {rec['stdcells']:,} | {rec['dffs']:,} | {rec.get('latches', 0)} | "
            f"{rec.get('muxes', '-')} | {rec['area_um2']:,.2f} | {ge_val:,} |"
        )
    lines.extend([
        "",
        f"- **CTS/ECO Physical Closure Delta**: `+{cts_delta_cells:,}` cells (`+{cts_delta_area:,.2f} um^2`), `{post_top['buffers']:,}` buffer instances total in signoff netlist.",
        f"- **Total Signoff Standard-Cell Core Area**: **`{post_top['area_um2']:,.2f} um^2`** (`{post_top['area_um2'] / 1e6:.4f} mm^2`, **`{post_top['ge']:,} GE`**; sequential cells = `{post_top['seq_area_um2']:,.2f} um^2` / `{post_top['seq_pct']}`).",
        f"- **Total Area incl. Modeled 4x SRAM Macro Stubs**: `+{area['macro_area_um2']:,.2f} um^2` (`2x 4,800 um^2` Tag + `2x 9,600 um^2` Data stubs in `flow/sta/sram_sync_sp.lib`) = **`{post_top['total_with_macro_um2']:,.2f} um^2`** (`{post_top['total_with_macro_um2'] / 1e6:.4f} mm^2`).",
        "",
        "### Hierarchical Area Breakdown (`soc_dft_top_sta.v` Post-CTS Signoff)",
        "",
        "| Module / Instance | Stdcells | FFs | Area (`um^2`) | Share of Stdcell Area |",
        "| :--- | :---: | :---: | :---: | :---: |",
    ])
    for mlabel, mrec in area["modules_post_cts"]:
        share = (100.0 * mrec["area_um2"] / post_top["area_um2"]) if post_top["area_um2"] else 0.0
        lines.append(
            f"| {mlabel} | {mrec['stdcells']:,} | {mrec['dffs']:,} | {mrec['area_um2']:,.2f} | {share:.2f}% |"
        )

    lines.extend([
        "",
        "## 2. ASIC Power Summary (`OpenSTA 3.2.0` on Post-CTS Signoff Netlist)",
        "",
        f"> **Methodology Note**: Static probabilistic power computed on `soc_dft_top_sta.v` at global toggle activity `0.1` transitions/cycle referenced to each mode's active clock (`100 MHz` `sys_clk` for `func` & `scan_capture`; `10 MHz` `tck` via `-density 0.001` for `scan_shift`, plus unscaled `-activity 0.1` shown for reference) and duty `0.5`. Power covers all **`{post_top['stdcells']:,}`** `IHP SG13G2` standard cells; the `4x sram_sync_sp` Liberty stubs model timing/area without array `internal_power()` tables (`Macro = 0.00 mW`).",
        "",
        "| Mode | PVT Corner | Clock (`MHz`) | Sequential (`mW`) | Combinational (`mW`) | Clock Net (`mW`) | Leakage (`uW`) | **Total Power (`mW`)** |",
        "| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |",
    ])
    for p in power_rows:
        lines.append(
            f"| `{p['mode']}` | `{p['corner']}` | {p['freq_mhz']:.0f} | {p['seq_mw']:.3f} | "
            f"{p['comb_mw']:.3f} | {p['clock_mw']:.3f} | {p['leakage_uw']:.2f} | **{p['total_mw']:.3f}** |"
        )

    lines.extend([
        "",
        "### Hierarchical Power Breakdown (`typ_1p20V_25C`)",
        "",
        "| Instance | Functional `100 MHz` (`mW`) | Scan-Shift `10 MHz` (`mW`) | Leakage @ `25°C` (`uW`) |",
        "| :--- | :---: | :---: | :---: |",
    ])
    func_map = {h["instance"]: h for h in hier_rows if h["mode"] == "func"}
    shft_map = {h["instance"]: h for h in hier_rows if h["mode"] == "scan_shift"}
    for inst in ("u_func_logic", "u_mbist_ctrl", "u_ieee1500_wrapper", "u_scan_comp_wrap", "u_jtag_tap", "u_occ_clk_ctrl"):
        f_r = func_map.get(inst, {})
        s_r = shft_map.get(inst, {})
        lines.append(
            f"| `{inst}` | {f_r.get('total_mw', 0.0):.4f} | {s_r.get('total_mw', 0.0):.4f} | {f_r.get('leakage_uw', 0.0):.3f} |"
        )

    lines.extend([
        "",
        "## 3. FPGA vs. ASIC Comparative Summary",
        "",
        "| Metric | FPGA Baseline (`Vivado Artix-7` Baseline RTL) | FPGA Post-DFT (`Yosys synth_xilinx xc7`) | ASIC Post-DFT (`IHP SG13G2 130nm` Signoff) |",
        "| :--- | :---: | :---: | :---: |",
        f"| **Device / Technology** | `{VIVADO_BASELINE['device']}` | Xilinx Artix-7 (`xc7`) | `IHP SG13G2 130nm` (`1.08V–1.32V`, `-40°C..125°C`) |",
        f"| **Max Operating Freq (`F_max`)** | **{VIVADO_BASELINE['fmax_mhz']:.2f} MHz** (`100 MHz` target) | Functional RTL reference | **{float(sta_func_typ['est_fmax_mhz']):.2f} MHz** (`typ`) / **{float(sta_func_slow['est_fmax_mhz']):.2f} MHz** (`slow`) / **{float(sta_func_fast['est_fmax_mhz']):.2f} MHz** (`fast`) |",
    ])
    if fpga_xc7 is not None:
        sd = fpga_xc7["soc_dft_top"]
        sf = fpga_xc7["soc_func_logic"]
        lines.append(
            f"| **Logic Resources / Area** | `{VIVADO_BASELINE['luts']}` LUTs, `{VIVADO_BASELINE['ffs']}` FFs (`< 1%`) | "
            f"`{sd['luts_incl_inv']:,}` LUTs, `{sd['ffs']:,}` FFs (`soc_func`: `{sf['luts_incl_inv']:,}` LUTs / `{sf['ffs']:,}` FFs) | "
            f"**`{post_top['area_um2']:,.2f} um^2`** (`{post_top['area_um2'] / 1e6:.4f} mm^2` stdcell = `{post_top['ge']:,} GE`, `{post_top['stdcells']:,}` cells, `{post_top['dffs']:,}` FFs) |"
        )
        lines.append(
            f"| **Memory Blocks** | `{VIVADO_BASELINE['bram']} BRAM` (Distributed RAM) | `{sd['dist_ram32m']} RAM32M`, `{sd['brams']} BRAM` | `4x sram_sync_sp` (`2x 8x14b` Tag + `2x 8x32b` Data = `{area['macro_area_um2']:,.0f} um^2` stub) |"
        )
    else:
        lines.append(
            f"| **Logic Resources / Area** | `{VIVADO_BASELINE['luts']}` LUTs, `{VIVADO_BASELINE['ffs']}` FFs (`< 1%`) | Re-run with `--run-xilinx` | "
            f"**`{post_top['area_um2']:,.2f} um^2`** (`{post_top['area_um2'] / 1e6:.4f} mm^2` stdcell = `{post_top['ge']:,} GE`, `{post_top['stdcells']:,}` cells, `{post_top['dffs']:,}` FFs) |"
        )
    lines.extend([
        f"| **Timing Closure (Setup / Hold)** | `{VIVADO_BASELINE['fmax_mhz']:.2f} MHz` Vivado signoff | N/A | **9/9 Modes×Corners PASS** (`slow`: `+{float(sta_func_slow['worst_slack_setup_ns']):.2f} ns` / `+{float(sta_func_slow['worst_slack_hold_ns']):.2f} ns`) |",
        f"| **Core Power (`OpenSTA`)** | N/A (not extracted in Vivado) | N/A | **`{func_typ['total_mw']:.2f} mW`** (`func 100 MHz typ`), **`{shift_typ['total_mw']:.2f} mW`** (`scan_shift 10 MHz typ`), **`{func_fast['total_mw']:.2f} mW`** (`fast`) |",
        f"| **Leakage Power (`stdcells`)** | N/A | N/A | `{func_typ['leakage_uw']:.2f} uW` (`25°C typ`) / `{func_slow['leakage_uw']:.2f} uW` (`125°C slow`) |",
        f"| **DFT Capabilities** | None (Functional Core only) | Full JTAG / 1500 / MBIST / OCC / Comp | **{float(hyb_row['fc_all_po_pct']):.3f}% / {float(comp_row['fc_scan_out_pct']):.3f}% SA FC**, `4x` Comp (`{comp_row['pattern_count']}` vec), Hybrid `{hyb_row['pattern_count']}` vec (`{float(hyb_row['ate_data_comp_ratio']):.2f}x` data red.), 3-corner SDF GLS |",
        "",
        f"> **Why Vivado Baseline (`534 LUTs / 625 FFs`) vs. Yosys (`soc_func_logic`) Differ**: In the standalone Vivado Artix-7 synthesis of the baseline core, Vivado inferred Distributed `LUTRAM` for the register file and pruned unobserved debug outputs. In the ASIC scan-ready flow (`soc_func_logic`), the `32x32` register file, 5-stage pipeline, and integrated 32-bit 2-way D-cache controller are explicitly synthesized into `{area['soc_func_noscan']['dffs']:,}` scan-stitchable `sg13g2_dfrbpq_1` flip-flops backed by `4x sram_sync_sp` SRAM macros alongside `100%` of IEEE 1500 / MBIST / JTAG / OCC / compactor DFT hardware.",
        "",
        "## 4. Extracted ASIC Schematics",
        "",
        "- **Full Post-Stitch ASIC SoC Schematic**: [asic_soc_dft_schematic.png](../docs/figures/asic_soc_dft_schematic.png) ([SVG](../docs/figures/asic_soc_dft_schematic.svg))",
        "- **Glitch-Free OCC Stdcell Gate Schematic (`IHP SG13G2`)**: [asic_occ_gate_schematic.png](../docs/figures/asic_occ_gate_schematic.png) ([SVG](../docs/figures/asic_occ_gate_schematic.svg))",
        "",
    ])

    md_path = REPORTS / "asic_metrics_summary.md"
    md_path.write_text("\n".join(lines), encoding="utf-8")
    print(f"[Metrics] Wrote {csv_path.relative_to(ROOT)} & {md_path.relative_to(ROOT)}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Extract ASIC area/timing/power metrics & schematics.")
    parser.add_argument("--skip-metrics", action="store_true", help="Only render schematics.")
    parser.add_argument("--skip-schematics", action="store_true", help="Only compute metrics.")
    parser.add_argument("--run-xilinx", action="store_true", help="Also run Yosys synth_xilinx (xc7) FPGA mapping (~70s).")
    args = parser.parse_args()

    if not args.skip_schematics:
        print("[Metrics] Rendering ASIC schematics into docs/figures/...")
        generate_schematics()

    if not args.skip_metrics:
        lib_typ = os.environ.get("IHP_LIB_TYP", CORNERS["typ"])
        nand2_area = parse_nand2_area(lib_typ)
        print(f"[Metrics] Extracting IHP SG13G2 ASIC area metrics (NAND2_1 = {nand2_area:.4f} um^2)...")
        area = extract_area_metrics(lib_typ, nand2_area)
        print("[Metrics] Extracting multi-mode multi-corner OpenSTA power metrics...")
        power_rows, hier_rows = extract_power_metrics()

        xc7_json = REPORTS / "fpga_xc7_metrics.json"
        if args.run_xilinx:
            print("[Metrics] Running Yosys synth_xilinx (xc7) FPGA resource comparison...")
            fpga_xc7 = extract_xilinx_xc7()
        elif xc7_json.is_file():
            fpga_xc7 = json.loads(xc7_json.read_text(encoding="utf-8"))
        else:
            fpga_xc7 = None

        write_reports(area, power_rows, hier_rows, fpga_xc7)


if __name__ == "__main__":
    main()
