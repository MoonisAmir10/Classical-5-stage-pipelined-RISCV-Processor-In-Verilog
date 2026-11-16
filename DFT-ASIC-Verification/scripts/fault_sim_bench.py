#!/usr/bin/env python3
"""Bit-parallel event-driven ISCAS-89 stuck-at fault simulator with collapsing.

Evaluates batches of W patterns packed into arbitrary-precision Python ints
to accurately grade deterministic ATPG patterns, LFSR PRPG BIST sequences, and
8:2 spatial XOR compacted outputs against the full collapsed fault universe.
"""

from __future__ import annotations

import argparse
import heapq
import re
from pathlib import Path

GATE_RE = re.compile(r"^([A-Za-z0-9_.\[\]]+)\s*=\s*([A-Za-z]+)\(([^)]*)\)$")


class BenchCircuit:
    """Compiled topological representation of an ISCAS-89 .bench circuit."""

    def __init__(self, bench_path: Path):
        self.path = bench_path
        self.inputs: list[str] = []
        self.outputs: list[str] = []
        gates: dict[str, tuple[str, list[str]]] = {}

        for raw in bench_path.read_text(encoding="utf-8").splitlines():
            s = raw.strip()
            if not s or s.startswith("#"):
                continue
            if s.startswith("INPUT(") and s.endswith(")"):
                self.inputs.append(s[6:-1].strip())
            elif s.startswith("OUTPUT(") and s.endswith(")"):
                self.outputs.append(s[7:-1].strip())
            else:
                m = GATE_RE.match(s)
                if not m:
                    raise ValueError(f"Invalid BENCH line: {raw}")
                lhs, op, rhs = m.group(1), m.group(2).upper(), m.group(3)
                args = [a.strip() for a in rhs.split(",") if a.strip()]
                if op == "BUFF":
                    op = "BUF"
                gates[lhs] = (op, args)

        # Assign integer net IDs cleanly (PIs first, then topologically sorted gates)
        self.net_id: dict[str, int] = {}
        self.id_name: list[str] = []
        for inp in self.inputs:
            self._add_net(inp)

        in_deg: dict[str, int] = {}
        children: dict[str, list[str]] = {n: [] for n in self.inputs}
        for lhs in gates:
            children.setdefault(lhs, [])
        for lhs, (_, args) in gates.items():
            uniq = set(args)
            in_deg[lhs] = sum(1 for a in uniq if a in gates)
            for a in uniq:
                children.setdefault(a, []).append(lhs)

        q = [lhs for lhs, d in in_deg.items() if d == 0]
        topo: list[str] = []
        idx = 0
        while idx < len(q):
            u = q[idx]
            idx += 1
            topo.append(u)
            for v in children.get(u, []):
                in_deg[v] -= 1
                if in_deg[v] == 0:
                    q.append(v)

        if len(topo) != len(gates):
            raise RuntimeError("Combinational loop detected in BENCH netlist!")

        for g in topo:
            self._add_net(g)

        self.num_nets = len(self.id_name)
        self.num_pis = len(self.inputs)
        self.output_ids = [self.net_id[o] for o in self.outputs]
        self.output_set = set(self.output_ids)

        # Store gate specs indexed by net_id: (op_code, arg_ids_tuple)
        # Op codes: 0=BUF, 1=NOT, 2=AND, 3=NAND, 4=OR, 5=NOR, 6=XOR, 7=XNOR
        op_map = {"BUF": 0, "NOT": 1, "AND": 2, "NAND": 3, "OR": 4, "NOR": 5, "XOR": 6, "XNOR": 7}
        self.gate_op = [-1] * self.num_nets
        self.gate_args: list[tuple[int, ...]] = [() for _ in range(self.num_nets)]
        self.fanout: list[list[int]] = [[] for _ in range(self.num_nets)]

        for gname in topo:
            op_str, args = gates[gname]
            gid = self.net_id[gname]
            self.gate_op[gid] = op_map[op_str]
            arg_ids = tuple(self.net_id[a] for a in args)
            self.gate_args[gid] = arg_ids
            for aid in set(arg_ids):
                self.fanout[aid].append(gid)

        self.topo_gate_ids = [self.net_id[g] for g in topo]

    def _add_net(self, name: str) -> int:
        if name not in self.net_id:
            nid = len(self.id_name)
            self.net_id[name] = nid
            self.id_name.append(name)
        return self.net_id[name]

    def collapse_faults(self) -> list[tuple[int, int, int]]:
        """Generate equivalence/dominance-collapsed single stuck-at faults.

        Returns list of tuples (target_gate_id_or_minus1, line_id, stuck_val 0|1).
        target_gate_id == -1 denotes stem/gate-output fault; >=0 denotes specific gate input branch.
        """
        faults: list[tuple[int, int, int]] = []
        # Gate output faults & fanout stem faults using standard checkpoint collapsing
        for nid in range(self.num_nets):
            is_branch = len(self.fanout[nid]) > 1
            if nid < self.num_pis or nid in self.output_set or is_branch:
                faults.append((-1, nid, 0))
                faults.append((-1, nid, 1))
            if nid >= self.num_pis:
                op = self.gate_op[nid]
                # Controlling values collapse equivalence: AND/NAND share SA0->out, retain SA1 on inputs
                # OR/NOR share SA1->out, retain SA0 on inputs; XOR/XNOR retain both on inputs
                args = self.gate_args[nid]
                if op in (2, 3):  # AND / NAND: SA1 on each multi-input
                    if len(args) > 1:
                        for idx, aid in enumerate(args):
                            faults.append((nid * 16 + idx, aid, 1))
                elif op in (4, 5):  # OR / NOR: SA0 on each multi-input
                    if len(args) > 1:
                        for idx, aid in enumerate(args):
                            faults.append((nid * 16 + idx, aid, 0))
                elif op in (6, 7):  # XOR / XNOR: both SA0 and SA1
                    for idx, aid in enumerate(args):
                        faults.append((nid * 16 + idx, aid, 0))
                        faults.append((nid * 16 + idx, aid, 1))
        return faults

    def _eval_gate(self, op: int, arg_vals: list[int], mask: int) -> int:
        if op == 0:
            return arg_vals[0]
        if op == 1:
            return mask ^ arg_vals[0]
        if op == 2:
            v = arg_vals[0]
            for a in arg_vals[1:]:
                v &= a
            return v
        if op == 3:
            v = arg_vals[0]
            for a in arg_vals[1:]:
                v &= a
            return mask ^ v
        if op == 4:
            v = arg_vals[0]
            for a in arg_vals[1:]:
                v |= a
            return v
        if op == 5:
            v = arg_vals[0]
            for a in arg_vals[1:]:
                v |= a
            return mask ^ v
        if op == 6:
            v = arg_vals[0]
            for a in arg_vals[1:]:
                v ^= a
            return v
        # XNOR (op == 7)
        v = arg_vals[0]
        for a in arg_vals[1:]:
            v ^= a
        return mask ^ v

    def eval_good(self, pi_words: list[int], width: int) -> list[int]:
        """Evaluate fault-free values for W packed patterns across all nets."""
        mask = (1 << width) - 1
        vals = [0] * self.num_nets
        for i in range(self.num_pis):
            vals[i] = pi_words[i] & mask
        for gid in self.topo_gate_ids:
            args = self.gate_args[gid]
            vals[gid] = self._eval_gate(self.gate_op[gid], [vals[a] for a in args], mask)
        return vals

    def _fault_detect_mask(
        self,
        f_idx: int,
        faults: list[tuple[int, int, int]],
        good: list[int],
        mask: int,
        po_to_comp_group: dict[int, int] | None,
        stop_early: bool,
    ) -> int:
        """Return bitmask of patterns in current batch detecting fault f_idx."""
        tgt_enc, line_id, s_val = faults[f_idx]
        f_const = mask if s_val else 0
        fanout = self.fanout
        gate_op = self.gate_op
        gate_args = self.gate_args
        out_set = self.output_set

        if tgt_enc < 0:
            init_diff = good[line_id] ^ f_const
            if init_diff == 0:
                return 0
            if line_id in out_set and po_to_comp_group is None:
                return init_diff
            override = {line_id: f_const}
            heap: list[int] = list(fanout[line_id])
            heapq.heapify(heap)
            in_heap = set(heap)
            diff_po_ids = [line_id] if line_id in out_set else []
        else:
            gid = tgt_enc // 16
            pin_idx = tgt_enc % 16
            if (good[line_id] ^ f_const) == 0:
                return 0
            g_args = gate_args[gid]
            av = [f_const if k == pin_idx else good[a] for k, a in enumerate(g_args)]
            new_gval = self._eval_gate(gate_op[gid], av, mask)
            init_diff = new_gval ^ good[gid]
            if init_diff == 0:
                return 0
            if gid in out_set and po_to_comp_group is None:
                return init_diff
            override = {gid: new_gval}
            heap = list(fanout[gid])
            heapq.heapify(heap)
            in_heap = set(heap)
            diff_po_ids = [gid] if gid in out_set else []

        raw_det = 0
        while heap:
            cur = heapq.heappop(heap)
            in_heap.discard(cur)
            av = [override.get(a, good[a]) for a in gate_args[cur]]
            new_v = self._eval_gate(gate_op[cur], av, mask)
            diff = new_v ^ good[cur]
            if diff != 0:
                override[cur] = new_v
                if cur in out_set:
                    if po_to_comp_group is None:
                        raw_det |= diff
                        if stop_early:
                            return raw_det
                    else:
                        diff_po_ids.append(cur)
                for nxt in fanout[cur]:
                    if nxt not in in_heap:
                        heapq.heappush(heap, nxt)
                        in_heap.add(nxt)

        if po_to_comp_group is None:
            return raw_det

        group_diff: dict[int, int] = {}
        direct_det = 0
        for pid in diff_po_ids:
            grp = po_to_comp_group.get(pid, -1)
            if grp < 0:
                continue
            dmask = override.get(pid, good[pid]) ^ good[pid]
            group_diff[grp] = group_diff.get(grp, 0) ^ dmask
        for dv in group_diff.values():
            direct_det |= dv
        return direct_det

    def _pack_batch(self, batch: list[list[int]]) -> tuple[list[int], int]:
        width = len(batch)
        mask = (1 << width) - 1
        pi_words = [0] * self.num_pis
        for p_bit, pat in enumerate(batch):
            bit_val = 1 << p_bit
            for i, b in enumerate(pat):
                if b:
                    pi_words[i] |= bit_val
        return pi_words, mask

    def grade_patterns(
        self,
        patterns: list[list[int]],
        faults: list[tuple[int, int, int]] | None = None,
        compacted_po_groups: list[list[int]] | None = None,
        batch_size: int = 256,
    ) -> tuple[int, int, list[int]]:
        """Run fault-dropping bit-parallel FSIM across patterns (each a bit list of len num_pis).

        Returns (detected_count, total_faults, per_batch_cum_detected).
        """
        if faults is None:
            faults = self.collapse_faults()
        remaining = set(range(len(faults)))
        total = len(faults)
        cum_curve: list[int] = []

        po_to_comp_group: dict[int, int] | None = None
        if compacted_po_groups is not None:
            po_to_comp_group = {}
            for g_idx, group in enumerate(compacted_po_groups):
                for pid in group:
                    po_to_comp_group[pid] = g_idx

        for b_start in range(0, len(patterns), batch_size):
            batch = patterns[b_start : b_start + batch_size]
            pi_words, mask = self._pack_batch(batch)
            good = self.eval_good(pi_words, len(batch))

            newly_detected = [
                f_idx
                for f_idx in remaining
                if self._fault_detect_mask(f_idx, faults, good, mask, po_to_comp_group, True) != 0
            ]
            remaining.difference_update(newly_detected)
            cum_curve.append(total - len(remaining))

        return total - len(remaining), total, cum_curve

    def compact_topoff(
        self,
        seed_patterns: list[list[int]],
        cand_patterns: list[list[int]],
        faults: list[tuple[int, int, int]] | None = None,
        compacted_po_groups: list[list[int]] | None = None,
        batch_size: int = 256,
    ) -> tuple[int, int, int]:
        """Grade seed_patterns first, then pick minimal top-off vectors from cand_patterns.

        Returns (seed_det, total_det_after_topoff, num_topoff_patterns).
        """
        if faults is None:
            faults = self.collapse_faults()
        remaining = set(range(len(faults)))
        po_to_comp_group: dict[int, int] | None = None
        if compacted_po_groups is not None:
            po_to_comp_group = {}
            for g_idx, group in enumerate(compacted_po_groups):
                for pid in group:
                    po_to_comp_group[pid] = g_idx

        for b_start in range(0, len(seed_patterns), batch_size):
            batch = seed_patterns[b_start : b_start + batch_size]
            pi_words, mask = self._pack_batch(batch)
            good = self.eval_good(pi_words, len(batch))
            det = [
                f for f in remaining
                if self._fault_detect_mask(f, faults, good, mask, po_to_comp_group, True) != 0
            ]
            remaining.difference_update(det)
        seed_det = len(faults) - len(remaining)

        selected_count = 0
        for b_start in range(0, len(cand_patterns), batch_size):
            if not remaining:
                break
            batch = cand_patterns[b_start : b_start + batch_size]
            pi_words, mask = self._pack_batch(batch)
            good = self.eval_good(pi_words, len(batch))
            # Collect per-fault detection mask across patterns inside this batch
            det_masks: dict[int, int] = {}
            for f in remaining:
                dm = self._fault_detect_mask(f, faults, good, mask, po_to_comp_group, False)
                if dm != 0:
                    det_masks[f] = dm
            # Greedy set cover inside batch
            while det_masks:
                best_bit = 0
                best_score = 0
                for p_bit in range(len(batch)):
                    pm = 1 << p_bit
                    score = sum(1 for dm in det_masks.values() if dm & pm)
                    if score > best_score:
                        best_score = score
                        best_bit = pm
                if best_score == 0:
                    break
                selected_count += 1
                covered = [f for f, dm in det_masks.items() if dm & best_bit]
                for f in covered:
                    det_masks.pop(f, None)
                    remaining.discard(f)

        return seed_det, len(faults) - len(remaining), selected_count


def load_atalanta_test(test_path: Path) -> list[list[int]]:
    pats: list[list[int]] = []
    for raw in test_path.read_text(encoding="utf-8").splitlines():
        s = raw.strip()
        if not s or s.startswith("*"):
            continue
        if ":" in s:
            lhs, rhs = s.split(":", 1)
            if lhs.strip().isdigit():
                bits_str = rhs.strip().split()[0]
                pats.append([1 if ch == "1" else 0 for ch in bits_str])
    return pats


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="Bit-parallel combinational .bench stuck-at fault simulator.")
    ap.add_argument("bench", type=Path)
    ap.add_argument("--test", type=Path, required=True)
    ap.add_argument("--max-patterns", type=int, default=0, help="0 = evaluate all patterns in --test")
    args = ap.parse_args()
    ckt = BenchCircuit(args.bench)
    pats = load_atalanta_test(args.test)
    if args.max_patterns > 0:
        pats = pats[: args.max_patterns]
    det, tot, _ = ckt.grade_patterns(pats)
    print(f"Graded {len(pats)} vectors on {args.bench}: {det}/{tot} ({100.0*det/tot:.3f}%)")
