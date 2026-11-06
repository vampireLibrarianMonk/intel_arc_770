#!/usr/bin/env python3
"""long_prompt_bench.py — time one long-context request against an OpenAI-compatible server.

Builds a deterministic ~N-token prompt (real Python source from this repo, repeated) followed
by a question, sends it with greedy decoding, and reports wall time plus llama.cpp's own
`timings` (prompt and generation tok/s) when the server returns them.

  python long_prompt_bench.py --base-url http://127.0.0.1:8080/v1 --target-chars 48000
"""
import argparse
import json
import pathlib
import time
import urllib.request

HERE = pathlib.Path(__file__).resolve().parent


def build_prompt(target_chars):
    src = "".join(p.read_text() for p in sorted(HERE.glob("*.py")))
    body = (src * (target_chars // len(src) + 1))[:target_chars]
    return ("Here is a Python codebase:\n\n" + body +
            "\n\nIn one paragraph, summarize what the function `tps` does.")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base-url", required=True)
    ap.add_argument("--target-chars", type=int, default=48000)
    ap.add_argument("--max-tokens", type=int, default=128)
    ap.add_argument("--runs", type=int, default=2)
    a = ap.parse_args()
    prompt = build_prompt(a.target_chars)
    for i in range(a.runs):
        # vary the first line so the server cannot reuse a cached prefix between runs
        msg = f"[run {i} {time.time()}]\n" + prompt
        body = json.dumps({"model": "x", "messages": [{"role": "user", "content": msg}],
                           "temperature": 0.0, "max_tokens": a.max_tokens}).encode()
        req = urllib.request.Request(a.base_url.rstrip("/") + "/chat/completions", data=body,
                                     headers={"Content-Type": "application/json"})
        t0 = time.time()
        with urllib.request.urlopen(req, timeout=1800) as r:  # nosec B310 - local server
            d = json.loads(r.read())
        wall = time.time() - t0
        u, t = d.get("usage", {}), d.get("timings", {})
        print(json.dumps({"run": i, "prompt_tokens": u.get("prompt_tokens"),
                          "completion_tokens": u.get("completion_tokens"),
                          "wall_s": round(wall, 2),
                          "prompt_tok_s": round(t.get("prompt_per_second", 0), 1),
                          "gen_tok_s": round(t.get("predicted_per_second", 0), 1)}), flush=True)


if __name__ == "__main__":
    main()
