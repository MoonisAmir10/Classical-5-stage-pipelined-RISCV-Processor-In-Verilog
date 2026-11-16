#!/usr/bin/env python3
"""ATE Fail Log Parser & Scan-Chain Pinpoint Diagnostic Tool (Phase 5).

Correlates simulated ATE pin failure records (`ext_pin`, `cyc`, `pat`, `mode`,
`exp`, `got`) against `scan_stitch.py` chain metadata (`scan8.json`) to isolate:
  - Bypass mode (1-chain serial): exact failing chain ID, bit index, synth FF
    instance name, and hierarchical RTL net name.
  - Compressed mode (8:2 XOR compactor): exact parity-group candidate FFs across
    even {0,2,4,6} or odd {1,3,5,7} chains at unload slice `cyc`, narrowed by
    X-mask isolation probe records (`MASK_PROBE`) when present.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

FAIL_RE = re.compile(
    r"ATE_FAIL\s+mode=(?P<mode>\S+)\s+pat=(?P<pat>\d+)\s+cyc=(?P<cyc>\d+)\s+"
    r"ext_pin=(?P<ext_pin>\d+)\s+exp=(?P<exp>\S+)\s+got=(?P<got>\S+)"
    r"(?:\s+note=(?P<note>\S+))?"
)
MASK_RE = re.compile(
    r"MASK_PROBE\s+pat=(?P<pat>\d+)\s+mask=0x(?P<mask>[0-9a-fA-F]+)\s+clean=(?P<clean>[01])"
)


def parse_fail_log(log_path: Path) -> tuple[list[dict], dict[int, list[tuple[int, int]]]]:
    """Parse ATE_FAIL and MASK_PROBE records from a simulation fail log."""
    fails: list[dict] = []
    probes: dict[int, list[tuple[int, int]]] = {}
    for ln in log_path.read_text(encoding="utf-8").splitlines():
        m_f = FAIL_RE.search(ln)
        if m_f:
            d = m_f.groupdict()
            fails.append({
                "mode": d["mode"],
                "pat": int(d["pat"]),
                "cyc": int(d["cyc"]),
                "ext_pin": int(d["ext_pin"]),
                "exp": d["exp"],
                "got": d["got"],
                "note": d["note"] or "",
            })
            continue
        m_p = MASK_RE.search(ln)
        if m_p:
            pat = int(m_p.group("pat"))
            probes.setdefault(pat, []).append((int(m_p.group("mask"), 16), int(m_p.group("clean"))))
    return fails, probes


def diagnose_fails(meta: dict, fails: list[dict], probes: dict[int, list[tuple[int, int]]]) -> list[dict]:
    """Resolve each ATE fail event to candidate/exact failing scan flip-flop(s)."""
    chains: list[list[dict]] = meta["chains"]
    num_chains = len(chains)

    # Flatten bypass daisy-chain order matching scan_comp_wrap.sv:
    # ext_scan_in[0] -> chain[0][0..L0-1] -> ... -> chain[7][0..L7-1] -> ext_scan_out[0]
    bypass_order: list[dict] = []
    for ch in chains:
        bypass_order.extend(ch)
    total_ffs = len(bypass_order)

    results: list[dict] = []
    for f in fails:
        mode = f["mode"]
        cyc = f["cyc"]
        pin = f["ext_pin"]
        pat = f["pat"]

        # Optional per-pattern single-chain X-mask isolation lookup
        isolated_chain: int | None = None
        for mval, clean in probes.get(pat, []):
            if clean == 1 and mval != 0 and (mval & (mval - 1)) == 0:
                isolated_chain = mval.bit_length() - 1

        candidates: list[dict] = []
        resolution = "UNRESOLVED"

        if mode == "BYPASS":
            g_idx = total_ffs - 1 - cyc
            if 0 <= g_idx < total_ffs:
                ff = bypass_order[g_idx]
                candidates.append(ff)
                resolution = "EXACT_1TO1"
        elif mode == "COMP82":
            parity = pin % 2
            for c_idx in range(parity, num_chains, 2):
                ch = chains[c_idx]
                bit_pos = len(ch) - 1 - cyc
                if 0 <= bit_pos < len(ch):
                    if isolated_chain is None or isolated_chain == c_idx:
                        candidates.append(ch[bit_pos])
            if len(candidates) == 1 and isolated_chain is not None:
                resolution = "ISOLATED_BY_XMASK"
            elif candidates:
                resolution = f"XOR_PARITY_GROUP({len(candidates)})"

        results.append({
            **f,
            "resolution": resolution,
            "isolated_chain": isolated_chain,
            "candidates": candidates,
        })
    return results


def format_report(diag_rows: list[dict], log_path: Path, meta_path: Path) -> str:
    """Format human-readable Markdown diagnostic report."""
    lines = [
        "# ATE Silicon Fail Diagnosis Report (`scripts/ate_fail_diag.py`)",
        "",
        f"- **Fail Log:** `{log_path}`",
        f"- **Scan Map:** `{meta_path}`",
        f"- **Total Fail Events Diagnosed:** `{len(diag_rows)}`",
        "",
        "| Pat | Mode | Pin | Shift Cyc | Exp -> Got | Resolution | Suspect Chain / Bit | Synth FF Instance | RTL Signal (`q_net`) | Note |",
        "| :---: | :---: | :---: | :---: | :---: | :--- | :---: | :--- | :--- | :--- |",
    ]
    for r in diag_rows:
        cands = r["candidates"]
        if cands:
            ch_bits = ", ".join(f"ch{c['chain_id']}[{c['bit_idx']}]" for c in cands)
            insts = ", ".join(f"`{c['inst_name']}`" for c in cands)
            nets = ", ".join(f"`{c['q_net'].strip()}`" for c in cands)
        else:
            ch_bits, insts, nets = "-", "-", "-"
        lines.append(
            f"| {r['pat']} | `{r['mode']}` | {r['ext_pin']} | {r['cyc']} | "
            f"`{r['exp']}` -> `{r['got']}` | {r['resolution']} | {ch_bits} | {insts} | {nets} | `{r['note']}` |"
        )
    lines.append("")
    return "\n".join(lines)


def main() -> None:
    ap = argparse.ArgumentParser(description="Diagnose ATE pin fails back to synthesized scan FFs.")
    ap.add_argument("fail_log", type=Path)
    ap.add_argument("--meta", type=Path, required=True, help="Path to scan8.json metadata")
    ap.add_argument("--report", type=Path, default=None, help="Optional Markdown report path")
    ap.add_argument("--json", type=Path, default=None, help="Optional JSON output path")
    args = ap.parse_args()

    meta = json.loads(args.meta.read_text(encoding="utf-8"))
    fails, probes = parse_fail_log(args.fail_log)
    diag = diagnose_fails(meta, fails, probes)
    md = format_report(diag, args.fail_log, args.meta)
    print(md)
    if args.report is not None:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(md, encoding="utf-8")
    if args.json is not None:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(json.dumps(diag, indent=2), encoding="utf-8")
    if not diag:
        raise RuntimeError(f"No ATE_FAIL entries found in {args.fail_log}")


if __name__ == "__main__":
    main()
