#!/usr/bin/env python3
"""ipex_server.py — minimal OpenAI-compatible /v1/chat/completions server over IPEX-LLM.

Lets the incumbent IPEX-LLM harness be benchmarked by the exact same bench_openai.py driver
as the GGUF candidates, so the comparison is apples-to-apples at the API level.

Loads one HF model on the XPU (4-bit), then serves greedy completions. stdlib-only HTTP
server (no flask/fastapi) to avoid adding deps to .venv-llm.

Usage (run inside .venv-llm with xpu_runtime.env sourced):
  python ipex_server.py --model Qwen/Qwen2.5-7B-Instruct --port 8099
"""

import argparse
import json
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import torch

STATE = {"tok": None, "model": None, "model_id": None}


def load_model(model_id, load_in_4bit=True):
    from ipex_llm.transformers import AutoModelForCausalLM
    from transformers import AutoTokenizer

    tok = AutoTokenizer.from_pretrained(model_id, trust_remote_code=True)
    model = AutoModelForCausalLM.from_pretrained(
        model_id,
        load_in_4bit=load_in_4bit,
        optimize_model=True,
        trust_remote_code=True,
        use_cache=True,
    ).to("xpu")
    torch.xpu.synchronize()
    STATE.update(tok=tok, model=model, model_id=model_id)


def generate(messages, max_tokens):
    tok, model = STATE["tok"], STATE["model"]
    prompt = tok.apply_chat_template(messages, tokenize=False, add_generation_prompt=True)
    ids = tok(prompt, return_tensors="pt").input_ids.to("xpu")
    torch.xpu.synchronize()
    with torch.inference_mode():
        out = model.generate(
            ids,
            do_sample=False,
            num_beams=1,
            temperature=None,
            top_p=None,
            top_k=None,
            max_new_tokens=max_tokens,
            use_cache=True,
        )
    torch.xpu.synchronize()
    new = out.shape[-1] - ids.shape[-1]
    text = tok.decode(out[0][ids.shape[-1] :], skip_special_tokens=True)
    return text, int(ids.shape[-1]), int(new)


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
        messages = req.get("messages", [])
        max_tokens = int(req.get("max_tokens", 512))
        t0 = time.time()
        text, pt, ct = generate(messages, max_tokens)
        dt = time.time() - t0
        self._send(
            200,
            {
                "id": "ipex-" + str(int(t0)),
                "object": "chat.completion",
                "model": STATE["model_id"],
                "choices": [
                    {
                        "index": 0,
                        "message": {"role": "assistant", "content": text},
                        "finish_reason": "stop",
                    }
                ],
                "usage": {
                    "prompt_tokens": pt,
                    "completion_tokens": ct,
                    "total_tokens": pt + ct,
                    "seconds": round(dt, 3),
                },
            },
        )

    def do_GET(self):
        if self.path.rstrip("/").endswith("/models"):
            self._send(200, {"data": [{"id": STATE["model_id"], "object": "model"}]})
        else:
            self._send(200, {"status": "ok", "model": STATE["model_id"]})


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--port", type=int, default=8099)
    ap.add_argument("--no-4bit", dest="load_in_4bit", action="store_false", default=True)
    args = ap.parse_args()

    print(f"loading {args.model} on XPU (4bit={args.load_in_4bit}) ...", flush=True)
    t0 = time.time()
    load_model(args.model, args.load_in_4bit)
    print(f"loaded in {time.time() - t0:.1f}s; serving on :{args.port}", flush=True)
    ThreadingHTTPServer(("127.0.0.1", args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
