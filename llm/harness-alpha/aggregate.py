#!/usr/bin/env python3
"""aggregate.py — collect the per-candidate JSON results into one comparison.

Reads the latest artifacts/harness-alpha/<candidate>_*.json for each candidate and prints
a markdown comparison table plus the three-claims breakdown. Writes a combined JSON too.

Usage: python aggregate.py [--out-dir artifacts/harness-alpha] [--report reports/...]
"""

import argparse
import glob
import json
import os
from collections import defaultdict


def latest_per_candidate(out_dir):
    by_cand = defaultdict(list)
    for p in glob.glob(os.path.join(out_dir, "*_*.json")):
        base = os.path.basename(p)
        if base == "combined.json":
            continue
        try:
            with open(p) as f:
                data = json.load(f)
        except (json.JSONDecodeError, OSError):
            continue
        cand = data.get("candidate")
        if cand:
            by_cand[cand].append((os.path.getmtime(p), data))
    return {c: sorted(v)[-1][1] for c, v in by_cand.items()}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--out-dir", default=os.path.expanduser("~/projects/intel_arc_770/artifacts/harness-alpha")
    )
    ap.add_argument("--report", default=None, help="optional path to write a markdown report")
    args = ap.parse_args()

    results = latest_per_candidate(args.out_dir)
    if not results:
        print("no results found in", args.out_dir)
        raise SystemExit(1)

    order = ["llamacpp-sycl", "llamacpp-vulkan", "lmstudio", "ipex-llm"]
    cands = [c for c in order if c in results] + [c for c in results if c not in order]

    lines = []
    lines.append("| candidate | backend | coding (exec) | writing constraints | median tok/s |")
    lines.append("|:--|:--|:--|:--|--:|")
    for c in cands:
        r = results[c]
        cod = r.get("coding", {})
        wri = r.get("writing", {})
        backend = {
            "llamacpp-sycl": "SYCL",
            "llamacpp-vulkan": "Vulkan",
            "lmstudio": "Vulkan",
            "ipex-llm": "XPU/IPEX",
        }.get(c, "?")
        lines.append(
            f"| {c} | {backend} | {cod.get('passed', '?')}/{cod.get('total', '?')} | "
            f"{wri.get('constraints_met', '?')}/{wri.get('total', '?')} | "
            f"{r.get('median_tokens_per_sec', '?')} |"
        )
    table = "\n".join(lines)
    print("\n=== HARNESS ALPHA — COMPARISON ===\n")
    print(table)
    print(
        "\nNote: 'coding (exec)' = generated code executed against hidden unit tests. "
        "'writing constraints' = measurable property checks only; quality is human-judged "
        "from the saved raw text in each candidate's JSON."
    )

    combined = {"candidates": results, "order": cands}
    cpath = os.path.join(args.out_dir, "combined.json")
    with open(cpath, "w") as f:
        json.dump(combined, f, indent=2)
    print(f"\nwrote {cpath}")

    if args.report:
        os.makedirs(os.path.dirname(args.report), exist_ok=True)
        with open(args.report, "w") as f:
            f.write("# Harness alpha — results\n\n")
            f.write(table + "\n")
        print(f"wrote {args.report}")


if __name__ == "__main__":
    main()
