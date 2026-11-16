#!/usr/bin/env python3
"""Scan-chain stitcher for flattened Yosys IHP SG13G2 structural Verilog netlists.

Replaces flip-flop .D inputs with sg13g2_mux2_1 scan multiplexers (.A0=func_D,
.A1=scan_prev, .S=scan_en, .X=mux_d) partitioned evenly across N balanced chains,
preserving blackboxes (e.g. SRAM macros) and emitting chain metadata JSON for ATPG/diagnosis.
"""

import argparse
import json
import re
from pathlib import Path

DFF_CELLS = ("sg13g2_dfrbpq_1", "sg13g2_dfrbpq_2", "sg13g2_dfrbp_1", "sg13g2_dfrbp_2")
MUX_AREA_UM2 = 18.1440  # sg13g2_mux2_1 area in sg13g2_stdcell_typ_1p20V_25C.lib
LATCH_AREA_UM2 = 29.0304  # sg13g2_dllrq_1 area

MOD_HDR_RE = re.compile(r"^(\s*module\s+[A-Za-z0-9_]+\s*\()(.*?)(\)\s*;)", re.S | re.M)
INST_RE = re.compile(
    r"(^[ \t]*("
    + "|".join(DFF_CELLS)
    + r")\s+(\S+)\s*\((.*?)\)\s*;)",
    re.S | re.M,
)
PIN_RE = re.compile(r"\.([A-Za-z0-9_]+)\(\s*(.*?)\s*\)", re.S)


def extract_escaped_safe(expr: str) -> str:
    """Keep escaped Verilog identifiers trailing space safe before closing paren."""
    s = expr.strip()
    if s.startswith("\\") and not s.endswith(" "):
        return s + " "
    return s


def stitch_netlist(
    in_path: Path,
    out_path: Path,
    meta_path: Path | None,
    num_chains: int,
    scan_en_name: str = "scan_en",
    scan_in_name: str = "scan_in",
    scan_out_name: str = "scan_out",
    lockup_latch: bool = False,
    clk_name: str = "clk",
    rst_n_name: str = "rst_n",
) -> dict:
    if num_chains < 1:
        raise ValueError("num_chains must be >= 1")

    text = in_path.read_text(encoding="utf-8")

    # Locate module header
    hm = MOD_HDR_RE.search(text)
    if not hm:
        raise RuntimeError(f"Could not find module header in {in_path}")

    # Collect all matching DFF instances in netlist order
    matches = list(INST_RE.finditer(text))
    if not matches:
        raise RuntimeError(f"No matching SG13G2 DFF cells found in {in_path}")

    dff_records = []
    for idx, m in enumerate(matches):
        cell_type = m.group(2)
        inst_name = m.group(3)
        body = m.group(4)
        pins = {}
        for pm in PIN_RE.finditer(body):
            pins[pm.group(1)] = pm.group(2)
        dff_records.append(
            {
                "idx": idx,
                "span": m.span(1),
                "cell_type": cell_type,
                "inst_name": inst_name,
                "pins": pins,
            }
        )

    total_ffs = len(dff_records)
    base, rem = divmod(total_ffs, num_chains)
    chain_lengths = [base + (1 if c < rem else 0) for c in range(num_chains)]

    # Assign each DFF to its chain & shift position
    chains_meta = [[] for _ in range(num_chains)]
    cursor = 0
    for c, clen in enumerate(chain_lengths):
        for pos in range(clen):
            rec = dff_records[cursor]
            rec["chain_id"] = c
            rec["chain_pos"] = pos
            cursor += 1

    # Rewrite DFF instances from end to start so byte spans remain valid
    extra_decls = []
    extra_cells = []
    chain_tail_wires = [None] * num_chains
    mux_idx = 0
    prev_q_per_chain = [f"{scan_in_name}[{c}]" for c in range(num_chains)]

    # Process chains sequentially to track previous Q correctly per chain
    replacements = []
    q_fix_idx = 0
    for rec in dff_records:
        c = rec["chain_id"]
        pos = rec["chain_pos"]
        pins = dict(rec["pins"])

        orig_d = extract_escaped_safe(pins.get("D", "1'b0"))
        if not orig_d:
            orig_d = "1'b0"
        orig_q = extract_escaped_safe(pins.get("Q", ""))
        if not orig_q:
            orig_q = f"_scan_unused_q_{q_fix_idx}_"
            extra_decls.append(f"  wire {orig_q};")
            q_fix_idx += 1

        scan_d = f"_scan_mux_d_{mux_idx}_"
        extra_decls.append(f"  wire {scan_d};")
        prev_si = prev_q_per_chain[c]

        # Build sg13g2_mux2_1 (.A0=func_D, .A1=scan_in/prev_Q, .S=scan_en, .X=scan_d)
        extra_cells.append(
            f"  sg13g2_mux2_1 _scan_mux_{mux_idx}_ (\n"
            f"    .A0({orig_d}),\n"
            f"    .A1({prev_si}),\n"
            f"    .S({scan_en_name}),\n"
            f"    .X({scan_d})\n"
            f"  );"
        )

        # Update FF pins cleanly
        pins["D"] = scan_d
        pins["Q"] = orig_q
        pin_lines = ",\n".join(f"    .{k}({extract_escaped_safe(v)})" for k, v in sorted(pins.items()))
        new_dff = f"  {rec['cell_type']} {extract_escaped_safe(rec['inst_name'])} (\n{pin_lines}\n  );"
        replacements.append((rec["span"][0], rec["span"][1], new_dff))

        chains_meta[c].append(
            {
                "chain_id": c,
                "bit_idx": pos,
                "inst_name": rec["inst_name"].strip(),
                "q_net": orig_q.strip(),
                "d_net": orig_d.strip(),
            }
        )
        prev_q_per_chain[c] = orig_q
        chain_tail_wires[c] = orig_q
        mux_idx += 1

    # Apply FF replacements in reverse offset order
    parts = []
    last_end = 0
    for start, end, repl in sorted(replacements, key=lambda x: x[0]):
        parts.append(text[last_end:start])
        parts.append(repl)
        last_end = end
    parts.append(text[last_end:])
    patched = "".join(parts)

    # Inject scan ports right into module header & body
    hm2 = MOD_HDR_RE.search(patched)
    port_insert = f", {scan_en_name}, {scan_in_name}, {scan_out_name}"
    hi_end = f"[{num_chains - 1}:0] "
    io_decls = (
        f"\n  input {scan_en_name};\n"
        f"  wire {scan_en_name};\n"
        f"  input {hi_end}{scan_in_name};\n"
        f"  wire {hi_end}{scan_in_name};\n"
        f"  output {hi_end}{scan_out_name};\n"
        f"  wire {hi_end}{scan_out_name};\n"
    )
    if extra_decls:
        io_decls += "\n".join(extra_decls) + "\n"

    patched = (
        patched[: hm2.end(2)]
        + port_insert
        + hm2.group(3)
        + io_decls
        + patched[hm2.end(3) :]
    )

    # Append scan muxes, optional tail lockup latches, and scan_out assigns before endmodule
    tail_assigns = []
    added_latches = 0
    for c in range(num_chains):
        tail_net = chain_tail_wires[c]
        if lockup_latch:
            lock_q = f"_scan_lockup_q_{c}_"
            tail_assigns.append(f"  wire {lock_q};")
            tail_assigns.append(
                f"  sg13g2_dllrq_1 _scan_lockup_{c}_ (\n"
                f"    .D({tail_net}),\n"
                f"    .GATE_N({clk_name}),\n"
                f"    .RESET_B({rst_n_name}),\n"
                f"    .Q({lock_q})\n"
                f"  );"
            )
            tail_assigns.append(f"  assign {scan_out_name}[{c}] = {lock_q};")
            added_latches += 1
        else:
            tail_assigns.append(f"  assign {scan_out_name}[{c}] = {tail_net};")

    footer = "\n".join(extra_cells + tail_assigns) + "\nendmodule\n"
    end_idx = patched.rfind("endmodule")
    if end_idx < 0:
        raise RuntimeError(f"Missing endmodule in {in_path}")
    patched = patched[:end_idx] + footer + patched[end_idx + len("endmodule") :]

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(patched, encoding="utf-8")

    summary = {
        "input_netlist": str(in_path),
        "output_netlist": str(out_path),
        "total_ffs": total_ffs,
        "num_chains": num_chains,
        "chain_lengths": chain_lengths,
        "max_chain_len": max(chain_lengths),
        "added_scan_muxes": mux_idx,
        "added_lockup_latches": added_latches,
        "scan_overhead_um2": round(mux_idx * MUX_AREA_UM2 + added_latches * LATCH_AREA_UM2, 4),
        "chains": chains_meta,
    }
    if meta_path is not None:
        meta_path.parent.mkdir(parents=True, exist_ok=True)
        meta_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")
    return summary


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("in_verilog", type=Path)
    ap.add_argument("-o", "--output", required=True, type=Path)
    ap.add_argument("--meta", type=Path, default=None)
    ap.add_argument("--chains", type=int, default=8)
    ap.add_argument("--scan-en", default="scan_en")
    ap.add_argument("--scan-in", default="scan_in")
    ap.add_argument("--scan-out", default="scan_out")
    ap.add_argument("--lockup-latch", action="store_true")
    ap.add_argument("--clk", default="clk")
    ap.add_argument("--rst-n", default="rst_n")
    args = ap.parse_args()

    res = stitch_netlist(
        in_path=args.in_verilog,
        out_path=args.output,
        meta_path=args.meta,
        num_chains=args.chains,
        scan_en_name=args.scan_en,
        scan_in_name=args.scan_in,
        scan_out_name=args.scan_out,
        lockup_latch=args.lockup_latch,
        clk_name=args.clk,
        rst_n_name=args.rst_n,
    )
    print(
        f"Stitched {res['total_ffs']} FFs into {res['num_chains']} chain(s) "
        f"(lengths={res['chain_lengths']}, +{res['added_scan_muxes']} muxes, "
        f"+{res['scan_overhead_um2']} um^2) -> {res['output_netlist']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
