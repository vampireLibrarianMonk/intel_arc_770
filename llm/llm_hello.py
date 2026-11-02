#!/usr/bin/env python3
"""llm_hello.py — minimal "is my IPEX-LLM stack working?" smoke test on the Arc A770.

Two tiny end-to-end checks, each on its own model:

  1. CODING  — ask a (code-capable) model to write a Python hello-world function,
               then actually EXECUTE the generated code and confirm it prints the
               expected text. Generation succeeding is not enough; we run the output.
  2. WRITING — ask a writing/instruct model for one English paragraph on a topic,
               then sanity-check it is a real paragraph (enough words / sentences).

This is deliberately small: one prompt per model, greedy decoding, clear PASS/FAIL.
Use llm_bench.py for the full throughput + task-suite benchmark.

Usage:
  python llm/llm_hello.py                                   # sensible defaults
  python llm/llm_hello.py --code-model Qwen/Qwen2.5-Coder-1.5B-Instruct
  python llm/llm_hello.py --write-model Qwen/Qwen2.5-1.5B-Instruct
  python llm/llm_hello.py --topic "the Intel Arc A770 GPU"
  python llm/llm_hello.py --no-4bit --max-new 200
"""

import argparse
import contextlib
import io
import sys

import torch

DEFAULT_CODE_MODEL = "Qwen/Qwen2.5-Coder-1.5B-Instruct"
DEFAULT_WRITE_MODEL = "Qwen/Qwen2.5-1.5B-Instruct"


def banner(msg):
    print("\n" + "=" * 60)
    print(msg)
    print("=" * 60)


def load(model_id, load_in_4bit):
    """Load a model + tokenizer onto the XPU. Returns (tok, model)."""
    from ipex_llm.transformers import AutoModelForCausalLM
    from transformers import AutoTokenizer

    tok = AutoTokenizer.from_pretrained(model_id, trust_remote_code=True)
    model = AutoModelForCausalLM.from_pretrained(
        model_id,
        load_in_4bit=load_in_4bit,
        optimize_model=True,
        trust_remote_code=True,
        use_cache=True,
    )
    model = model.to("xpu")
    torch.xpu.synchronize()
    return tok, model


def chat(tok, model, user_msg, max_new):
    """Run one greedy chat turn through the model's chat template. Returns decoded text."""
    messages = [{"role": "user", "content": user_msg}]
    # Use the model's chat template so instruct models behave correctly.
    prompt = tok.apply_chat_template(messages, tokenize=False, add_generation_prompt=True)
    ids = tok(prompt, return_tensors="pt").input_ids.to("xpu")
    torch.xpu.synchronize()
    with torch.inference_mode():
        # Greedy, deterministic. Clear the sampling knobs the model's generation_config may
        # set (temperature/top_p/top_k), otherwise transformers warns they're ignored.
        out = model.generate(
            ids,
            do_sample=False,
            num_beams=1,
            temperature=None,
            top_p=None,
            top_k=None,
            max_new_tokens=max_new,
            use_cache=True,
        )
    torch.xpu.synchronize()
    return tok.decode(out[0][ids.shape[-1] :], skip_special_tokens=True)


def extract_code(text):
    """Pull a fenced python block if present, else return the raw text."""
    if "```" in text:
        parts = text.split("```")
        for p in parts:
            s = p.strip()
            if s.startswith("python"):
                return s[len("python") :].strip()
        if len(parts) >= 2:
            return parts[1].strip()
    return text


def run_coding_test(model_id, load_in_4bit, max_new):
    """Generate a hello-world function, execute it, confirm it prints the expected text."""
    banner(f"CODING TEST  (model: {model_id})")
    tok, model = load(model_id, load_in_4bit)
    expected = "Hello, World!"
    prompt = (
        "Write a Python function named `hello` that takes no arguments and prints "
        f"exactly the text: {expected}\n"
        "Return only a single fenced python code block, no explanation."
    )
    print(f"prompt:\n  {prompt}\n")
    reply = chat(tok, model, prompt, max_new)
    print("model reply:\n" + reply.strip() + "\n")

    code = extract_code(reply)
    ns = {}
    buf = io.StringIO()
    try:
        # Intentional: we must run the model's output to verify it actually works.
        # The task is tiny and self-contained; do not point this at untrusted prompts.
        # Capture stdout now, because a small model often returns a bare `print(...)`
        # script rather than a function definition — both are valid hello-worlds.
        with contextlib.redirect_stdout(buf):
            exec(code, ns)  # nosec B102
    except Exception as e:  # noqa: BLE001
        print(f"[FAIL] generated code raised on exec: {type(e).__name__}: {e}")
        return False

    printed = buf.getvalue()
    fn = ns.get("hello")
    if callable(fn):
        # Preferred shape: a hello() function. Call it and check what it prints.
        buf2 = io.StringIO()
        try:
            with contextlib.redirect_stdout(buf2):
                fn()
        except Exception as e:  # noqa: BLE001
            print(f"[FAIL] calling hello() raised: {type(e).__name__}: {e}")
            return False
        printed = buf2.getvalue() or printed

    if expected.lower() in printed.lower():
        print(f"[PASS] program printed: {printed.strip()!r}")
        return True
    print(f"[FAIL] printed {printed.strip()!r}, expected to contain {expected!r}")
    return False


def run_writing_test(model_id, load_in_4bit, max_new, topic):
    """Ask for one English paragraph and sanity-check it reads like a paragraph."""
    banner(f"WRITING TEST  (model: {model_id})")
    tok, model = load(model_id, load_in_4bit)
    prompt = (
        f"Write one clear, well-formed English paragraph (4 to 6 sentences) about {topic}. "
        "Return only the paragraph, no title, no bullet points."
    )
    print(f"prompt:\n  {prompt}\n")
    reply = chat(tok, model, prompt, max_new).strip()
    print("model reply:\n" + reply + "\n")

    words = len(reply.split())
    sentences = sum(reply.count(c) for c in ".!?")
    print(f"stats: {words} words, ~{sentences} sentences")
    if words >= 40 and sentences >= 3:
        print("[PASS] looks like a real English paragraph")
        return True
    print("[FAIL] output too short to be a 4-6 sentence paragraph")
    return False


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--code-model", default=DEFAULT_CODE_MODEL, help="model for the coding test")
    ap.add_argument("--write-model", default=DEFAULT_WRITE_MODEL, help="model for the writing test")
    ap.add_argument("--topic", default="what a GPU is and why it is useful")
    ap.add_argument("--max-new", type=int, default=256)
    ap.add_argument("--load-in-4bit", action="store_true", default=True)
    ap.add_argument("--no-4bit", dest="load_in_4bit", action="store_false")
    ap.add_argument("--skip-coding", action="store_true")
    ap.add_argument("--skip-writing", action="store_true")
    args = ap.parse_args()

    if not (hasattr(torch, "xpu") and torch.xpu.is_available()):
        print("ERROR: torch.xpu is not available — the IPEX-LLM XPU stack is not active.")
        print("       Run:  bash llm/install_ipex_llm.sh   then re-run via run_hello.sh")
        sys.exit(1)

    print("device:", torch.xpu.get_device_properties(0).name)

    results = {}
    if not args.skip_coding:
        results["coding"] = run_coding_test(args.code_model, args.load_in_4bit, args.max_new)
    if not args.skip_writing:
        results["writing"] = run_writing_test(
            args.write_model, args.load_in_4bit, args.max_new, args.topic
        )

    banner("SUMMARY")
    for name, ok in results.items():
        print(f"  {name:8s}: {'PASS' if ok else 'FAIL'}")
    all_ok = all(results.values()) if results else False
    print("\noverall:", "PASS" if all_ok else "FAIL")
    sys.exit(0 if all_ok else 1)


if __name__ == "__main__":
    main()
