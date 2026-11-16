#!/usr/bin/env python3
"""Sanitize nl2bench output into valid ISCAS-89 BENCH compatible with Atalanta 2.0.

Handles VDD/VSS constants and prunes unreferenced primary inputs / dangling
gates (e.g. redundant LRU tag bit sram_rtag1[12]) that cause Atalanta fatal errors.
"""

import re
import sys
from pathlib import Path

GATE_RE = re.compile(r"^([A-Za-z0-9_.\[\]]+)\s*=\s*([A-Za-z]+)\(([^)]*)\)$")


def clean_bench_for_atalanta(in_path: Path, out_path: Path) -> None:
    raw_lines = in_path.read_text(encoding="utf-8").splitlines()
    comments = []
    inputs = []
    outputs = []
    gate_defs = []

    for line in raw_lines:
        s = line.strip()
        if not s:
            continue
        if s.startswith("#"):
            comments.append(line + "\n")
        elif s.startswith("INPUT(") and s.endswith(")"):
            inputs.append(s[6:-1].strip())
        elif s.startswith("OUTPUT(") and s.endswith(")"):
            outputs.append(s[7:-1].strip())
        elif s.startswith("__NL2BENCH_"):
            continue
        else:
            m = GATE_RE.match(s)
            if not m:
                raise RuntimeError(f"Unrecognized BENCH line in {in_path}: {line}")
            lhs, op, rhs_str = m.group(1), m.group(2).upper(), m.group(3)
            args = [a.strip() for a in rhs_str.split(",") if a.strip()]
            gate_defs.append([lhs, op, args])

    if not inputs:
        raise RuntimeError(f"No INPUT() found in {in_path}")

    # Collect initial set of referenced nets so we pick an active reference input for tie cells
    rhs_counts = set()
    for _, _, args in gate_defs:
        rhs_counts.update(args)
    active_inputs = [inp for inp in inputs if inp in rhs_counts]
    ref_in = active_inputs[0] if active_inputs else inputs[0]

    has_vss = any(op in ("VSS", "GND") for _, op, _ in gate_defs)
    has_vdd = any(op == "VDD" for _, op, _ in gate_defs)

    const_gates = []
    if has_vss or has_vdd:
        const_gates.append(["__CONST_N__", "NOT", [ref_in]])
        if has_vss:
            const_gates.append(["__CONST0__", "AND", [ref_in, "__CONST_N__"]])
        if has_vdd:
            const_gates.append(["__CONST1__", "OR", [ref_in, "__CONST_N__"]])

    norm_gates = []
    for lhs, op, args in const_gates + gate_defs:
        if op in ("VSS", "GND"):
            norm_gates.append([lhs, "BUF", ["__CONST0__"]])
        elif op == "VDD":
            norm_gates.append([lhs, "BUF", ["__CONST1__"]])
        else:
            norm_gates.append([lhs, op, args])

    # Iteratively prune dangling internal gates not reaching any OUTPUT()
    out_set = set(outputs)
    changed = True
    while changed:
        changed = False
        used = set(out_set)
        for _, _, args in norm_gates:
            used.update(args)
        kept = [g for g in norm_gates if g[0] in used]
        if len(kept) != len(norm_gates):
            norm_gates = kept
            changed = True

    used_nets = set(out_set)
    for _, _, args in norm_gates:
        used_nets.update(args)

    # Prune floating INPUT() pins (except those connected directly to an OUTPUT)
    final_inputs = [inp for inp in inputs if inp in used_nets]
    # Also prune any OUTPUT() that has neither a driving gate nor an active INPUT()
    gate_lhs = {g[0] for g in norm_gates}
    valid_drivers = gate_lhs | set(final_inputs)
    final_outputs = [o for o in outputs if o in valid_drivers]

    out_lines = list(comments)
    for inp in final_inputs:
        out_lines.append(f"INPUT({inp})\n")
    for o in final_outputs:
        out_lines.append(f"OUTPUT({o})\n")
    for lhs, op, args in norm_gates:
        out_lines.append(f"{lhs} = {op}({', '.join(args)})\n")

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text("".join(out_lines), encoding="utf-8")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(f"Usage: {sys.argv[0]} <in.bench> <out.bench>")
    clean_bench_for_atalanta(Path(sys.argv[1]), Path(sys.argv[2]))
