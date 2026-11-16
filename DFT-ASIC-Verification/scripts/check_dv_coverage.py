#!/usr/bin/env python3
"""Parse Verilator SystemC::Coverage-3 .dat files and verify Phase 3 DFT coverage closure."""

import argparse
import re
import sys
from collections import defaultdict
from pathlib import Path

RECORD_RE = re.compile(r"^C '([^']+)'\s+(\d+)\s*$")


def parse_dat(paths: list[Path]):
    """Aggregate line, toggle, and user coverage points per source file."""
    counts = defaultdict(lambda: defaultdict(int))
    for path in paths:
        for raw in path.read_text(encoding="utf-8").splitlines():
            m = RECORD_RE.match(raw)
            if not m:
                continue
            key_str, count = m.group(1), int(m.group(2))
            fields = {}
            for pair in key_str.split("\x01"):
                if "\x02" in pair:
                    k, v = pair.split("\x02", 1)
                    fields[k] = v
            src = fields.get("f", "")
            ctype = fields.get("t", "")
            counts[(src, ctype)][key_str] += count
    return counts


def summarize(counts, prefixes: tuple[str, ...]):
    """Build per-file breakdown for matching source prefixes."""
    per_file = defaultdict(lambda: {"line": [0, 0], "toggle": [0, 0], "user": [0, 0]})
    for (src, ctype), items in counts.items():
        if not any(src.startswith(p) for p in prefixes):
            continue
        if ctype not in ("line", "toggle", "user"):
            continue
        hit = sum(1 for v in items.values() if v > 0)
        tot = len(items)
        per_file[src][ctype][0] += hit
        per_file[src][ctype][1] += tot
    return dict(sorted(per_file.items()))


def fmt_pct(hit: int, tot: int) -> str:
    if tot == 0:
        return "   n/a   "
    return f"{100.0 * hit / tot:5.1f}% ({hit}/{tot})"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("dat_files", nargs="+", type=Path)
    ap.add_argument("--report", type=Path, default=None)
    ap.add_argument("--min-line", type=float, default=95.0)
    ap.add_argument("--min-toggle", type=float, default=95.0)
    ap.add_argument("--min-user", type=float, default=100.0)
    args = ap.parse_args()

    counts = parse_dat(args.dat_files)
    dft_stats = summarize(counts, ("rtl/dft/", "rtl/top/", "tb/sva/"))
    all_stats = summarize(counts, ("rtl/", "tb/sva/"))

    lines = [
        "=== Phase 3 Verilator DFT IP Coverage Closure Report ===",
        f"{'Module Source':36s} | {'Line':18s} | {'Toggle':20s} | {'User Bins':16s}",
        "-" * 98,
    ]
    dft_totals = {"line": [0, 0], "toggle": [0, 0], "user": [0, 0]}
    for src, metrics in dft_stats.items():
        for k in dft_totals:
            dft_totals[k][0] += metrics[k][0]
            dft_totals[k][1] += metrics[k][1]
        lines.append(
            f"{src:36s} | {fmt_pct(*metrics['line']):18s} | "
            f"{fmt_pct(*metrics['toggle']):20s} | {fmt_pct(*metrics['user']):16s}"
        )

    lines.append("-" * 98)
    lines.append(
        f"{'DFT IP + Top + SVA TOTAL':36s} | "
        f"{fmt_pct(*dft_totals['line']):18s} | "
        f"{fmt_pct(*dft_totals['toggle']):20s} | "
        f"{fmt_pct(*dft_totals['user']):16s}"
    )

    core_stats = {k: v for k, v in all_stats.items() if k.startswith(("rtl/core/", "rtl/mem/"))}
    if core_stats:
        core_tot = {"line": [0, 0], "toggle": [0, 0]}
        for metrics in core_stats.values():
            core_tot["line"][0] += metrics["line"][0]
            core_tot["line"][1] += metrics["line"][1]
            core_tot["toggle"][0] += metrics["toggle"][0]
            core_tot["toggle"][1] += metrics["toggle"][1]
        lines.append(
            f"{'Core + Cache + SRAM (DV scope)':36s} | "
            f"{fmt_pct(*core_tot['line']):18s} | "
            f"{fmt_pct(*core_tot['toggle']):20s} | {'   n/a   ':16s}"
        )

    text = "\n".join(lines) + "\n"
    print(text, end="")
    if args.report is not None:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(text, encoding="utf-8")

    # Enforce thresholds across aggregate DFT IP metrics
    line_pct = 100.0 * dft_totals["line"][0] / max(1, dft_totals["line"][1])
    tog_pct = 100.0 * dft_totals["toggle"][0] / max(1, dft_totals["toggle"][1])
    usr_pct = 100.0 * dft_totals["user"][0] / max(1, dft_totals["user"][1])

    failed = []
    if line_pct < args.min_line:
        failed.append(f"line {line_pct:.1f}% < {args.min_line:.1f}%")
    if tog_pct < args.min_toggle:
        failed.append(f"toggle {tog_pct:.1f}% < {args.min_toggle:.1f}%")
    if usr_pct < args.min_user:
        failed.append(f"user {usr_pct:.1f}% < {args.min_user:.1f}%")

    if failed:
        print(f"FAIL [Coverage Closure]: {', '.join(failed)}", file=sys.stderr)
        return 1
    print(
        f"PASS [Coverage Closure]: DFT IP line={line_pct:.1f}%, "
        f"toggle={tog_pct:.1f}%, user={usr_pct:.1f}%"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
