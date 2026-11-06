#!/usr/bin/env python3
"""run_eval.py — run the eval-v2 coding + writing suite against one OpenAI-compatible server.

  python run_eval.py --base-url http://127.0.0.1:8090/v1 --candidate qwen2.5-14b \
      --model-file Qwen2.5-14B-Instruct-Q4_K_M.gguf --out-dir artifacts/eval-v2/results

Protocol (fixed; see README.md):
  coding : each task once greedy (temperature 0) -> pass@1, plus 3 sampled attempts
           (temperature 0.6, top_p 0.95, seeds 11/22/33) -> sampled pass rate. Executed in an
           isolated subprocess against hidden tests (executor.py).
  writing: each prompt twice with sampling (temperature 0.8, top_p 0.95, seeds 101/202),
           raw text saved for blind judging; secondary metrics from writing_metrics().
"""

import argparse
import json
import os
import sys
import time
import urllib.request
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from executor import run_tests  # noqa: E402
from tasks_coding import CODING_TASKS  # noqa: E402
from tasks_writing import all_writing_tasks, writing_metrics  # noqa: E402

CODE_SEEDS = [11, 22, 33]
WRITE_SEEDS = [101, 202]


def chat(base_url, prompt, max_tokens, temperature, seed=None, top_p=1.0, timeout=1800):
    body = {"model": "local", "messages": [{"role": "user", "content": prompt}],
            "temperature": temperature, "top_p": top_p, "max_tokens": max_tokens, "stream": False}
    if seed is not None:
        body["seed"] = seed
    req = urllib.request.Request(base_url.rstrip("/") + "/chat/completions",
                                 data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=timeout) as r:  # nosec B310 - local server
        d = json.loads(r.read())
    dt = time.time() - t0
    msg = d["choices"][0]["message"]
    usage = d.get("usage", {})
    n = usage.get("completion_tokens") or 0
    return {"text": msg.get("content") or "", "reasoning_chars": len(msg.get("reasoning_content") or ""),
            "finish_reason": d["choices"][0].get("finish_reason"), "completion_tokens": n,
            "seconds": round(dt, 2), "tok_s": round(n / dt, 1) if n and dt else None}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base-url", required=True)
    ap.add_argument("--candidate", required=True)
    ap.add_argument("--model-file", default="")
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--code-max-tokens", type=int, default=1024)
    ap.add_argument("--write-max-tokens", type=int, default=1600)
    ap.add_argument("--limit", type=int, default=0, help="smoke test: first N tasks of each kind")
    a = ap.parse_args()

    coding = CODING_TASKS[: a.limit or None]
    writing = all_writing_tasks()[: a.limit or None]
    chat(a.base_url, "Say hi.", 8, 0.0)  # warm-up

    res = {"candidate": a.candidate, "model_file": a.model_file, "suite": "eval-v2",
           "timestamp": datetime.now(timezone.utc).isoformat(timespec="seconds"),
           "protocol": {"code_seeds": CODE_SEEDS, "code_temp": 0.6, "write_seeds": WRITE_SEEDS,
                        "write_temp": 0.8, "top_p": 0.95, "code_max_tokens": a.code_max_tokens,
                        "write_max_tokens": a.write_max_tokens},
           "coding": [], "writing": []}

    for t in coding:
        row = {"id": t["id"], "category": t["category"], "attempts": []}
        for kind, temp, seed in [("greedy", 0.0, None)] + [("sampled", 0.6, s) for s in CODE_SEEDS]:
            r = chat(a.base_url, t["prompt"], a.code_max_tokens, temp, seed, 0.95 if seed else 1.0)
            r.update(run_tests(r["text"], t["tests"]), kind=kind, seed=seed)
            row["attempts"].append(r)
        g = row["attempts"][0]
        row["pass_greedy"] = g["ok"]
        row["sampled_passes"] = sum(x["ok"] for x in row["attempts"][1:])
        res["coding"].append(row)
        print(f"[cod] {t['id']:28} greedy={'PASS' if g['ok'] else 'FAIL'} sampled={row['sampled_passes']}/3 "
              f"{g['tok_s']} tok/s  {'' if g['ok'] else g['detail'][:90]}", flush=True)

    for t in writing:
        for seed in WRITE_SEEDS:
            r = chat(a.base_url, t["prompt"], a.write_max_tokens, 0.8, seed, 0.95)
            r.update(id=t["id"], seed=seed, metrics=writing_metrics(r["text"], t))
            res["writing"].append(r)
            m = r["metrics"]
            print(f"[wri] {t['id']:28} seed={seed} {m['words']}w len_ok={m['length_ok']} "
                  f"stock={m['stock_phrases']} {r['tok_s']} tok/s finish={r['finish_reason']}", flush=True)

    c = res["coding"]
    tps = sorted(x["tok_s"] for row in c for x in row["attempts"] if x["tok_s"]) + \
        sorted(w["tok_s"] for w in res["writing"] if w["tok_s"])
    res["summary"] = {
        "coding_pass_greedy": sum(r["pass_greedy"] for r in c), "coding_tasks": len(c),
        "coding_sampled_pass_rate": round(sum(r["sampled_passes"] for r in c) / (3 * len(c)), 3) if c else None,
        "writing_samples": len(res["writing"]),
        "writing_length_ok": sum(w["metrics"]["length_ok"] for w in res["writing"]),
        "writing_empty": sum(w["metrics"]["empty"] for w in res["writing"]),
        "writing_truncated": sum(w["finish_reason"] == "length" for w in res["writing"]),
        "stock_per_1k_words_mean": round(sum(w["metrics"]["stock_per_1k_words"] for w in res["writing"])
                                         / len(res["writing"]), 2) if res["writing"] else None,
        "median_tok_s": sorted(tps)[len(tps) // 2] if tps else None,
    }
    os.makedirs(a.out_dir, exist_ok=True)
    path = os.path.join(a.out_dir, f"{a.candidate}.json")
    json.dump(res, open(path, "w"), indent=2)
    print("SUMMARY", json.dumps(res["summary"]), "\nwrote", path, flush=True)


if __name__ == "__main__":
    main()
