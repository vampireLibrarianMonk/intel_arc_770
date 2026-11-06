#!/usr/bin/env python3
"""ov_server.py — minimal OpenAI-compatible /v1/chat/completions server over OpenVINO GenAI.

Lets OpenVINO be scored by the exact same bench_openai.py driver as the llama.cpp candidates
(same prompts, greedy, same max_tokens, same tok/s definition: completion tokens / wall time).

Loads either an OpenVINO IR directory (e.g. OpenVINO/Qwen2.5-7B-Instruct-int4-ov) or a GGUF
file (OpenVINO GenAI's GGUF reader) onto the GPU. stdlib-only HTTP server; requests are served
one at a time (plain HTTPServer) because the pipeline is not shared across threads.

Usage (inside .venv-ov):
  python ov_server.py --model artifacts/ov-models/Qwen2.5-7B-Instruct-int4-ov --port 8098
  python ov_server.py --model artifacts/harness-alpha/models/Qwen2.5-7B-Instruct-Q4_K_M.gguf
Optional plugin properties: --prop KV_CACHE_PRECISION=u8 (repeatable).
"""

import argparse
import json
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

import openvino_genai as og

STATE = {"pipe": None, "model_id": None}


def load(model, device, props):
    pipe = og.LLMPipeline(model, device, **props)
    cfg = og.GenerationConfig()
    cfg.max_new_tokens = 8
    cfg.do_sample = False
    pipe.generate(["warm-up"], cfg)  # compile kernels before the first timed request
    STATE.update(pipe=pipe, model_id=model)


def generate(messages, max_tokens):
    pipe = STATE["pipe"]
    prompt = pipe.get_tokenizer().apply_chat_template(messages, add_generation_prompt=True)
    cfg = og.GenerationConfig()
    cfg.max_new_tokens = max_tokens
    cfg.do_sample = False  # greedy, matching temperature=0 in bench_openai.py
    cfg.apply_chat_template = False  # template already applied above
    res = pipe.generate([prompt], cfg)
    pm = res.perf_metrics
    return res.texts[0], int(pm.get_num_input_tokens()), int(pm.get_num_generated_tokens())


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):  # quiet
        pass

    def _send(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        if not self.path.rstrip("/").endswith("/chat/completions"):
            self._send(404, {"error": "not found"})
            return
        n = int(self.headers.get("Content-Length", 0))
        req = json.loads(self.rfile.read(n) or b"{}")
        t0 = time.time()
        text, pt, ct = generate(req.get("messages", []), int(req.get("max_tokens", 512)))
        self._send(200, {
            "id": "ov-" + str(int(t0)),
            "object": "chat.completion",
            "model": STATE["model_id"],
            "choices": [{"index": 0, "message": {"role": "assistant", "content": text},
                         "finish_reason": "stop"}],
            "usage": {"prompt_tokens": pt, "completion_tokens": ct, "total_tokens": pt + ct,
                      "seconds": round(time.time() - t0, 3)},
        })

    def do_GET(self):
        if self.path.rstrip("/").endswith("/models"):
            self._send(200, {"data": [{"id": STATE["model_id"], "object": "model"}]})
        else:
            self._send(200, {"status": "ok", "model": STATE["model_id"]})


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--device", default="GPU")
    ap.add_argument("--port", type=int, default=8098)
    ap.add_argument("--prop", action="append", default=[], help="KEY=VALUE plugin property")
    args = ap.parse_args()
    props = dict(p.split("=", 1) for p in args.prop)
    print(f"loading {args.model} on {args.device} props={props} ...", flush=True)
    t0 = time.time()
    load(args.model, args.device, props)
    print(f"loaded in {time.time() - t0:.1f}s; serving on :{args.port}", flush=True)
    HTTPServer(("127.0.0.1", args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
