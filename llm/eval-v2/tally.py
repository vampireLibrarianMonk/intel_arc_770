#!/usr/bin/env python3
"""tally.py — score your filled-in blind ballot and reveal which writer was which.

Borda count per prompt: with n writers, 1st gets n-1 points, last gets 0. Also reports first
places. Prompts left as '_' are skipped.

  python3 llm/eval-v2/tally.py            # defaults below
"""

import argparse
import collections
import json
import os
import re

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ballot", default=os.path.join(ROOT, "reports/eval_v2/ballot.txt"))
    ap.add_argument("--key", default=os.path.join(ROOT, "artifacts/eval-v2/review_key.json"))
    ap.add_argument("--out", default=os.path.join(ROOT, "reports/eval_v2/human_results.md"))
    ap.add_argument("--label", default="blind human ranking",
                    help="who ranked, e.g. 'AI reviewer ranking (a language model, not a human)'")
    a = ap.parse_args()
    key = json.load(open(a.key))
    pts, firsts, counted = collections.Counter(), collections.Counter(), 0
    for ln in open(a.ballot):
        m = re.match(r"\s*([\w-]+)\s*:\s*(.+)$", ln)
        if not m or m[1] not in key:
            continue
        order = [x.strip().upper() for x in m[2].split(">")]
        if any(x not in key[m[1]] for x in order) or len(set(order)) != len(order):
            print(f"skip {m[1]}: incomplete or invalid ranking {order}")
            continue
        n = len(order)
        for pos, lab in enumerate(order):
            pts[key[m[1]][lab]] += n - 1 - pos
        firsts[key[m[1]][order[0]]] += 1
        counted += 1
    rows = sorted(pts, key=lambda c: (-pts[c], -firsts[c]))
    md = [f"# eval-v2 {a.label}", "", f"Prompts ranked: {counted}.", "",
          "| writer | Borda points | first places |", "|:--|--:|--:|"]
    md += [f"| {c} | {pts[c]} | {firsts[c]} |" for c in rows]
    open(a.out, "w").write("\n".join(md) + "\n")
    print("\n".join(md))


if __name__ == "__main__":
    main()
