#!/usr/bin/env python3
"""Pre-CTS balanced high-fanout buffer tree & SDF netlist preparation for Phase 5.

Reads synthesized `soc_dft_wrappers.v` + stitched `soc_func_scan*.v`, eliminates
aliasing `A0 == A1` scan-mux inputs (so Icarus SDF ModPath resolves uniquely),
inserts uniform-depth `sg13g2_buf_16` buffer trees for any net with fanout >
`--max-fanout` (default 16), and emits:
  1. Combined simulation netlist (`--out-sim`) keeping parameterized `sram_sync_sp`.
  2. OpenSTA netlist (`--out-sta`) with non-parameterized SRAM timing stubs.
"""

from __future__ import annotations

import argparse
import math
import re
from pathlib import Path

OUTPUT_PINS = {"X", "Y", "Q", "Q_N", "GCLK", "Z", "SUM", "COUT", "L_HI", "L_LO"}

UPSIZE_TO_2 = {
    "sg13g2_nor4_1": "sg13g2_nor4_2",
    "sg13g2_nor3_1": "sg13g2_nor3_2",
    "sg13g2_nor2_1": "sg13g2_nor2_2",
    "sg13g2_nor2b_1": "sg13g2_nor2b_2",
    "sg13g2_nand2_1": "sg13g2_nand2_2",
    "sg13g2_nand2b_1": "sg13g2_nand2b_2",
    "sg13g2_and2_1": "sg13g2_and2_2",
    "sg13g2_and3_1": "sg13g2_and3_2",
    "sg13g2_and4_1": "sg13g2_and4_2",
    "sg13g2_or2_1": "sg13g2_or2_2",
    "sg13g2_or3_1": "sg13g2_or3_2",
    "sg13g2_or4_1": "sg13g2_or4_2",
    "sg13g2_a21o_1": "sg13g2_a21o_2",
    "sg13g2_a21oi_1": "sg13g2_a21oi_2",
    "sg13g2_inv_1": "sg13g2_inv_2",
    "sg13g2_mux2_1": "sg13g2_mux2_2",
}

HIGH_FANOUT_CLK_NETS = {"clk", "tck", "sys_clk", "wrck", "occ_clk", "rst_n", "trst_n", "dft_rst_n", "wrst_n"}

CELL_RE = re.compile(
    r"(?P<indent>[ \t]*)(?P<cell>sg13g2_\w+)\s+(?P<inst>[^\s(]+)\s*\((?P<body>.*?)\)\s*;",
    re.S,
)
PORT_RE = re.compile(r"\.(?P<pin>\w+)\s*\(\s*(?P<net>[^)]*?)\s*\)")

SRAM_STA_STUBS = """module sram_sync_sp_tag(clock, addr, din, we, dout, bist_en, bist_addr, bist_din, bist_we, bist_dout);
  input clock;
  input [2:0] addr;
  input [13:0] din;
  input we;
  output [13:0] dout;
  input bist_en;
  input [2:0] bist_addr;
  input [13:0] bist_din;
  input bist_we;
  output [13:0] bist_dout;
endmodule

module sram_sync_sp_data(clock, addr, din, we, dout, bist_en, bist_addr, bist_din, bist_we, bist_dout);
  input clock;
  input [2:0] addr;
  input [31:0] din;
  input we;
  output [31:0] dout;
  input bist_en;
  input [2:0] bist_addr;
  input [31:0] bist_din;
  input bist_we;
  output [31:0] bist_dout;
endmodule
"""


def _is_const_net(net: str) -> bool:
    s = net.strip()
    return (not s) or ("'" in s) or s.startswith("{")


def _fmt_net(net: str) -> str:
    """Keep mandatory trailing whitespace after Verilog escaped identifiers before `)`."""
    s = net.strip()
    return f"{s} " if s.startswith("\\") else s


def _unalias_mux2_inputs(mod_text: str) -> tuple[str, int]:
    """Insert a sg13g2_buf_1 on `.A1` whenever a sg13g2_mux2_1 has A0 == A1."""
    extra_wires: list[str] = []
    extra_cells: list[str] = []
    idx = 0

    def repl(m: re.Match[str]) -> str:
        nonlocal idx
        if m.group("cell") != "sg13g2_mux2_1":
            return m.group(0)
        body = m.group("body")
        ports = {pm.group("pin"): pm.group("net").strip() for pm in PORT_RE.finditer(body)}
        if "A0" in ports and "A1" in ports and ports["A0"] == ports["A1"]:
            orig = ports["A1"]
            buf_net = f"_unalias_a1_{idx}_"
            buf_inst = f"_unalias_buf_{idx}_"
            idx += 1
            extra_wires.append(f"  wire {buf_net};")
            extra_cells.append(
                f"  sg13g2_buf_1 {buf_inst} (\n"
                f"    .A({_fmt_net(orig)}),\n"
                f"    .X({buf_net})\n"
                f"  );"
            )
            new_body = re.sub(r"\.A1\s*\([^)]*\)", f".A1({buf_net})", body, count=1)
            return f"{m.group('indent')}{m.group('cell')} {m.group('inst')} ({new_body});"
        return m.group(0)

    patched = CELL_RE.sub(repl, mod_text)
    if idx > 0:
        first_cell = CELL_RE.search(patched)
        if first_cell is not None:
            patched = patched[:first_cell.start()] + "\n".join(extra_wires) + "\n" + patched[first_cell.start():]
        end_pos = patched.rfind("endmodule")
        patched = patched[:end_pos] + "\n".join(extra_cells) + "\n" + patched[end_pos:]
    return patched, idx


def balance_module_fanouts(mod_text: str, max_fanout: int = 16) -> tuple[str, dict[str, int]]:
    """Insert uniform-depth sg13g2_buf_16 trees on high-fanout nets inside one module."""
    mod_text, unaliased = _unalias_mux2_inputs(mod_text)

    # First collect all cell instances and identify every sink (cell_idx, pin_name, net)
    matches = list(CELL_RE.finditer(mod_text))
    cell_ports: list[list[tuple[str, str]]] = []
    net_sinks: dict[str, list[tuple[int, int]]] = {}

    for c_idx, m in enumerate(matches):
        p_list: list[tuple[str, str]] = []
        for pm in PORT_RE.finditer(m.group("body")):
            pin = pm.group("pin")
            net = pm.group("net").strip()
            p_idx = len(p_list)
            p_list.append((pin, net))
            if pin not in OUTPUT_PINS and not _is_const_net(net):
                net_sinks.setdefault(net, []).append((c_idx, p_idx))
        cell_ports.append(p_list)

    high_fanout = {n: s for n, s in net_sinks.items() if len(s) > max_fanout}
    if not high_fanout and unaliased == 0:
        return mod_text, {"unaliased_muxes": 0, "buffered_nets": 0, "added_buffers": 0, "upsized_cells": 0}

    extra_wires: list[str] = []
    extra_cells: list[str] = []
    buf_counter = 0
    tree_counter = 0

    for root_net, sinks in sorted(high_fanout.items()):
        t_id = tree_counter
        tree_counter += 1
        buf_cell = "sg13g2_buf_16" if root_net in HIGH_FANOUT_CLK_NETS else "sg13g2_buf_4"
        # Build uniform-depth tree bottom-up so all leaves have equal buffer depth
        groups: list[list[tuple[int, int]]] = [
            sinks[i : i + max_fanout] for i in range(0, len(sinks), max_fanout)
        ]
        leaf_nets: list[str] = []
        for g_idx, grp in enumerate(groups):
            w_name = f"_cts_{t_id}_lv0_{g_idx}_"
            extra_wires.append(f"  wire {w_name};")
            leaf_nets.append(w_name)
            for c_idx, p_idx in grp:
                pin, _ = cell_ports[c_idx][p_idx]
                cell_ports[c_idx][p_idx] = (pin, w_name)

        cur_children = leaf_nets
        level = 1
        while len(cur_children) > max_fanout:
            next_parents: list[str] = []
            p_groups = [
                cur_children[i : i + max_fanout]
                for i in range(0, len(cur_children), max_fanout)
            ]
            for p_idx, ch_list in enumerate(p_groups):
                p_wire = f"_cts_{t_id}_lv{level}_{p_idx}_"
                extra_wires.append(f"  wire {p_wire};")
                next_parents.append(p_wire)
                for ch_wire in ch_list:
                    b_name = f"_cts_buf_{buf_counter}_"
                    buf_counter += 1
                    extra_cells.append(
                        f"  {buf_cell} {b_name} (\n"
                        f"    .A({_fmt_net(p_wire)}),\n"
                        f"    .X({ch_wire})\n"
                        f"  );"
                    )
            cur_children = next_parents
            level += 1

        # Connect root_net to top stage of buffers
        for ch_wire in cur_children:
            b_name = f"_cts_buf_{buf_counter}_"
            buf_counter += 1
            extra_cells.append(
                f"  {buf_cell} {b_name} (\n"
                f"    .A({_fmt_net(root_net)}),\n"
                f"    .X({ch_wire})\n"
                f"  );"
            )

    # ECO drive-strength upsizing: upsize multi-fanout logic cells (_1 -> _2) after buffering
    recount_sinks: dict[str, int] = {}
    for p_list in cell_ports:
        for pin, net in p_list:
            if pin not in OUTPUT_PINS and not _is_const_net(net):
                recount_sinks[net] = recount_sinks.get(net, 0) + 1

    upsized_cnt = 0
    out_parts: list[str] = []
    last = 0
    for c_idx, m in enumerate(matches):
        out_parts.append(mod_text[last : m.start()])
        indent = m.group("indent")
        cell = m.group("cell")
        inst = m.group("inst")
        out_nets = [net for pin, net in cell_ports[c_idx] if pin in OUTPUT_PINS]
        if cell in UPSIZE_TO_2 and any(recount_sinks.get(n, 0) >= 2 for n in out_nets):
            cell = UPSIZE_TO_2[cell]
            upsized_cnt += 1
        conns = ",\n".join(f"{indent}  .{pin}({_fmt_net(net)})" for pin, net in cell_ports[c_idx])
        out_parts.append(f"{indent}{cell} {inst} (\n{conns}\n{indent});")
        last = m.end()
    out_parts.append(mod_text[last:])
    rebuilt = "".join(out_parts)

    if extra_wires:
        first_cell = CELL_RE.search(rebuilt)
        insert_at = first_cell.start() if first_cell is not None else rebuilt.rfind("endmodule")
        rebuilt = rebuilt[:insert_at] + "\n".join(extra_wires) + "\n" + rebuilt[insert_at:]
    if extra_cells:
        end_pos = rebuilt.rfind("endmodule")
        rebuilt = rebuilt[:end_pos] + "\n".join(extra_cells) + "\n" + rebuilt[end_pos:]

    return rebuilt, {
        "unaliased_muxes": unaliased,
        "buffered_nets": len(high_fanout),
        "added_buffers": buf_counter,
        "upsized_cells": upsized_cnt,
    }


def _balance_top_clocks(mod_text: str) -> str:
    """Balance occ_clk root load and match u_mbist_ctrl / SRAM clock insertion depth."""
    if not mod_text.lstrip().startswith("module soc_dft_top"):
        return mod_text

    extra_wires = [
        "  wire _cts_occ_root_;",
        "  wire _cts_sram_clk_;",
        "  wire _cts_comp_c0_, _cts_comp_clk_;",
        "  wire _cts_mb0_, _cts_mb1_, _cts_mb2_, _cts_mbist_clk_;",
    ]
    extra_cells = [
        "  sg13g2_buf_16 _cts_occ_root_buf_ (.A(occ_clk), .X(_cts_occ_root_));",
        "  sg13g2_buf_16 _cts_sram_clk_buf_ (.A(_cts_occ_root_), .X(_cts_sram_clk_));",
        "  sg13g2_buf_16 _cts_comp_d0_     (.A(_cts_occ_root_), .X(_cts_comp_c0_));",
        "  sg13g2_buf_16 _cts_comp_d1_     (.A(_cts_comp_c0_),  .X(_cts_comp_clk_));",
        "  sg13g2_buf_4  _cts_mb_d0_       (.A(sys_clk), .X(_cts_mb0_));",
        "  sg13g2_buf_4  _cts_mb_d1_       (.A(_cts_mb0_), .X(_cts_mb1_));",
        "  sg13g2_buf_4  _cts_mb_d2_       (.A(_cts_mb1_), .X(_cts_mb2_));",
        "  sg13g2_buf_8  _cts_mb_d3_       (.A(_cts_mb2_), .X(_cts_mbist_clk_));",
    ]
    patched = mod_text
    patched = patched.replace(".clock(occ_clk)", ".clock(_cts_sram_clk_)")
    patched = re.sub(
        r"(u_scan_comp_wrap\s*\(.*?)\.clk\s*\(\s*occ_clk\s*\)",
        r"\1.clk(_cts_comp_clk_)",
        patched,
        count=1,
        flags=re.S,
    )
    patched = patched.replace(".clk(occ_clk)", ".clk(_cts_occ_root_)")
    patched = re.sub(
        r"(mbist_ctrl\s+u_mbist_ctrl\s*\(.*?)\.clk\s*\(\s*sys_clk\s*\)",
        r"\1.clk(_cts_mbist_clk_)",
        patched,
        count=1,
        flags=re.S,
    )
    first_inst = re.search(r"^\s*(?:\S+)\s+\w+\s*(?:#\(|\()", patched[patched.find(");") + 2 :], re.M)
    ins_at = (patched.find(");") + 2 + first_inst.start()) if first_inst else patched.rfind("endmodule")
    patched = patched[:ins_at] + "\n".join(extra_wires) + "\n" + patched[ins_at:]
    end_pos = patched.rfind("endmodule")
    return patched[:end_pos] + "\n".join(extra_cells) + "\n" + patched[end_pos:]


def make_sta_netlist(sim_text: str) -> str:
    """Convert parameterized `sram_sync_sp` instances into OpenSTA blackbox stubs."""
    def rep_sram(m: re.Match[str]) -> str:
        params = m.group(1)
        inst = m.group(2)
        return ("sram_sync_sp_tag " if "14" in params else "sram_sync_sp_data ") + inst

    sta_body = re.sub(r"sram_sync_sp\s*#\((.*?)\)\s*(\w+)", rep_sram, sim_text, flags=re.S)
    return SRAM_STA_STUBS + "\n" + sta_body


def build_cts_netlists(
    wrappers_v: Path,
    func_v: Path,
    out_sim: Path,
    out_sta: Path,
    max_fanout: int = 16,
) -> dict[str, int]:
    """Process all modules in wrappers + stitched core, emitting simulation and STA netlists."""
    combined = wrappers_v.read_text(encoding="utf-8") + "\n" + func_v.read_text(encoding="utf-8")
    modules = re.split(r"(?=^module\s+)", combined, flags=re.M)

    totals = {"unaliased_muxes": 0, "buffered_nets": 0, "added_buffers": 0, "upsized_cells": 0}
    processed: list[str] = []
    for mod in modules:
        if not mod.strip():
            continue
        if "module " not in mod:
            processed.append(mod)
            continue
        new_mod, st = balance_module_fanouts(mod, max_fanout=max_fanout)
        new_mod = _balance_top_clocks(new_mod)
        for k, v in st.items():
            totals[k] += v
        processed.append(new_mod)

    sim_text = "".join(processed)
    out_sim.parent.mkdir(parents=True, exist_ok=True)
    out_sim.write_text(sim_text, encoding="utf-8")

    out_sta.parent.mkdir(parents=True, exist_ok=True)
    out_sta.write_text(make_sta_netlist(sim_text), encoding="utf-8")
    return totals


def main() -> None:
    ap = argparse.ArgumentParser(description="Insert uniform high-fanout buffer trees for Phase 5 STA/SDF.")
    ap.add_argument("--wrappers", type=Path, required=True)
    ap.add_argument("--func", type=Path, required=True)
    ap.add_argument("--out-sim", type=Path, required=True)
    ap.add_argument("--out-sta", type=Path, required=True)
    ap.add_argument("--max-fanout", type=int, default=16)
    args = ap.parse_args()
    stats = build_cts_netlists(args.wrappers, args.func, args.out_sim, args.out_sta, args.max_fanout)
    print(
        f"[CTS-Buf] max_fanout={args.max_fanout}: buffered_nets={stats['buffered_nets']}, "
        f"added_buffers={stats['added_buffers']}, upsized_cells={stats['upsized_cells']}, "
        f"unaliased_muxes={stats['unaliased_muxes']} -> {args.out_sim}"
    )


if __name__ == "__main__":
    main()
