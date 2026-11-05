#!/usr/bin/env python3
"""bench_openai.py — shared driver for the harness alpha cycle.

Points at any OpenAI-compatible /v1/chat/completions endpoint (llama-server, LM Studio,
Ollama, or our IPEX shim), runs the fixed coding + creative-writing task set, scores it,
measures tokens/sec, and writes one JSON record plus a console summary.

It deliberately does NOT start the server — each run/<candidate>.sh script is responsible
for standing up its own backend, confirming the GPU is used, then calling this. That keeps
the driver identical across candidates.

Usage:
  python bench_openai.py --base-url http://127.0.0.1:8080/v1 --model qwen2.5-7b \
      --candidate llamacpp-sycl [--api-key sk-xxx] [--max-tokens 512]
"""

import argparse
import json
import os
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone

from score import score_coding, score_writing


def load_tasks(task_set):
    """Return (coding, writing) for the chosen set: 'alpha' (default) or 'hard'."""
    if task_set == "hard":
        import tasks_hard

        return tasks_hard.all_tasks()
    from tasks import all_tasks

    return all_tasks()


def chat(base_url, api_key, model, prompt, max_tokens, timeout=600):
    """One deterministic (greedy) chat completion. Returns (text, usage, seconds)."""
    url = base_url.rstrip("/") + "/chat/completions"
    body = json.dumps(
        {
            "model": model,
            "messages": [{"role": "user", "content": prompt}],
            "temperature": 0.0,
            "top_p": 1.0,
            "max_tokens": max_tokens,
            "stream": False,
        }
    ).encode()
    req = urllib.request.Request(url, data=body, method="POST")  # nosec B310 - fixed http scheme
    req.add_header("Content-Type", "application/json")
    if api_key:
        req.add_header("Authorization", f"Bearer {api_key}")
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=timeout) as resp:  # nosec B310
        data = json.loads(resp.read().decode())
    dt = time.time() - t0
    text = data["choices"][0]["message"]["content"]
    usage = data.get("usage", {})
    return text, usage, dt


def tps(usage, seconds):
    n = usage.get("completion_tokens")
    return round(n / seconds, 1) if n and seconds else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base-url", required=True, help="e.g. http://127.0.0.1:8080/v1")
    ap.add_argument("--model", required=True)
    ap.add_argument("--candidate", required=True, help="id, e.g. llamacpp-sycl")
    ap.add_argument("--api-key", default=os.environ.get("OPENAI_API_KEY", "not-needed"))
    ap.add_argument("--max-tokens", type=int, default=512)
    ap.add_argument(
        "--task-set", default="alpha", choices=["alpha", "hard"],
        help="which task set: 'alpha' (default, easy) or 'hard' (discriminating)",
    )
    ap.add_argument(
        "--out-dir",
        default=os.path.expanduser("~/projects/intel_arc_770/artifacts/harness-alpha"),
    )
    args = ap.parse_args()

    coding, writing = load_tasks(args.task_set)
    result = {
        "candidate": args.candidate,
        "model": args.model,
        "base_url": args.base_url,
        "task_set": args.task_set,
        "timestamp": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "max_tokens": args.max_tokens,
    }

    # warmup (first call compiles kernels / loads layers)
    try:
        chat(args.base_url, args.api_key, args.model, "Say hi.", 8)
    except (urllib.error.URLError, urllib.error.HTTPError, OSError) as e:
        print(f"ERROR: endpoint not reachable at {args.base_url}: {e}")
        raise SystemExit(2) from e

    # ---- coding ----
    coding_rows, tpss = [], []
    for task in coding:
        text, usage, dt = chat(
            args.base_url, args.api_key, args.model, task["prompt"], args.max_tokens
        )
        ok, detail = score_coding(text, task)
        t = tps(usage, dt)
        if t:
            tpss.append(t)
        coding_rows.append(
            {"id": task["id"], "passed": ok, "detail": detail, "tokens_per_sec": t, "raw": text}
        )
        print(f"[cod] {task['id']:22s} {'PASS' if ok else 'FAIL':4s} {t or '?'} tok/s  {detail}")

    # ---- writing ----
    writing_rows = []
    for task in writing:
        text, usage, dt = chat(
            args.base_url, args.api_key, args.model, task["prompt"], args.max_tokens
        )
        ok, detail = score_writing(text, task)
        t = tps(usage, dt)
        if t:
            tpss.append(t)
        writing_rows.append(
            {"id": task["id"], "passed": ok, "detail": detail, "tokens_per_sec": t, "raw": text}
        )
        print(
            f"[wri] {task['id']:22s} {'OK  ' if ok else 'WARN':4s} {t or '?'} tok/s  {detail['words']}w"
        )

    result["coding"] = {
        "passed": sum(r["passed"] for r in coding_rows),
        "total": len(coding_rows),
        "tasks": coding_rows,
    }
    result["writing"] = {
        "constraints_met": sum(r["passed"] for r in writing_rows),
        "total": len(writing_rows),
        "tasks": writing_rows,
    }
    result["median_tokens_per_sec"] = round(sorted(tpss)[len(tpss) // 2], 1) if tpss else None

    os.makedirs(args.out_dir, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    path = os.path.join(args.out_dir, f"{args.candidate}_{stamp}.json")
    with open(path, "w") as f:
        json.dump(result, f, indent=2)

    print("\n==== SUMMARY:", args.candidate, "====")
    print(f"model              : {args.model}")
    print(f"coding (executed)  : {result['coding']['passed']}/{result['coding']['total']} passed")
    print(
        f"writing constraints: {result['writing']['constraints_met']}/{result['writing']['total']} met"
        " (quality = human review of raw text)"
    )
    print(f"median tokens/sec  : {result['median_tokens_per_sec']}")
    print(f"\nwrote {path}")


if __name__ == "__main__":
    main()
