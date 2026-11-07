#!/usr/bin/env python3
"""rescore.py — re-run the coding tests on already-saved model outputs (no model calls).

Used after fixing the scorer: executor.py originally aborted when a model's own example-usage
statement crashed at import time, which failed a possibly-correct function. Every stored
attempt is re-scored with the current executor; the previous verdict is kept as `ok_strict`
so the change stays auditable, and summaries are recomputed.

  python3 llm/eval-v2/rescore.py artifacts/eval-v2/results
"""
import glob
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from executor import run_tests  # noqa: E402
from tasks_coding import CODING_TASKS  # noqa: E402

TESTS = {t["id"]: t["tests"] for t in CODING_TASKS}


def main(results_dir):
    changed = []
    for f in sorted(glob.glob(os.path.join(results_dir, "*.json"))):
        r = json.load(open(f))
        for row in r["coding"]:
            for a in row["attempts"]:
                a.setdefault("ok_strict", a["ok"])
                new = run_tests(a["text"], TESTS[row["id"]])
                if new["ok"] != a["ok"]:
                    changed.append((r["candidate"], row["id"], a["kind"], a["seed"], a["ok"], new["ok"]))
                a.update(ok=new["ok"], detail=new["detail"], passed_tests=new.get("passed_tests", 0),
                         total_tests=new.get("total_tests", 0),
                         demo_errors_ignored=new.get("demo_errors_ignored", []))
            row["pass_greedy"] = row["attempts"][0]["ok"]
            row["sampled_passes"] = sum(x["ok"] for x in row["attempts"][1:])
        c = r["coding"]
        r["summary"]["coding_pass_greedy"] = sum(x["pass_greedy"] for x in c)
        r["summary"]["coding_sampled_pass_rate"] = round(sum(x["sampled_passes"] for x in c) / (3 * len(c)), 3)
        r["summary"]["coding_rescored"] = True
        json.dump(r, open(f, "w"), indent=2)
    print(f"re-scored; {len(changed)} attempt verdicts changed:")
    for ch in changed:
        print("  ", ch[0], ch[1], ch[2], ch[3], "was", ch[4], "now", ch[5])


if __name__ == "__main__":
    main(sys.argv[1])
