#!/usr/bin/env python3
"""llm_bench.py — language + coding test regime for a local LLM on the Arc A770 (IPEX-LLM).

Loads one model on the XPU, then measures:
  * load time and resident VRAM
  * prefill + decode tokens/sec at a short and a long prompt
  * coding tasks: small HumanEval-style problems, scored by executing the output
    against hidden unit tests (pass/fail)
  * language tasks: short deterministic prompts with keyword checks

Everything is written to artifacts/llm/<model>_<timestamp>.json. Deterministic (greedy)
so runs are comparable. Designed to be driven by run_llm_tests.sh.

Usage:
  python llm/llm_bench.py --model Qwen/Qwen2.5-1.5B-Instruct [--load-in-4bit] [--max-new 128]
"""

import argparse
import json
import os
import time
from datetime import datetime, timezone

import torch

# ---------- task sets ----------

CODING_TASKS = [
    {
        "name": "sum_list",
        "prompt": "Write a Python function `solve(nums)` that returns the sum of a list of "
        "integers. Return only the function, no explanation.",
        "entry": "solve",
        "tests": [(([1, 2, 3],), 6), (([],), 0), (([-5, 5],), 0)],
    },
    {
        "name": "is_palindrome",
        "prompt": "Write a Python function `solve(s)` that returns True if the string s is a "
        "palindrome, else False. Return only the function.",
        "entry": "solve",
        "tests": [(("racecar",), True), (("hello",), False), (("",), True)],
    },
    {
        "name": "fizzbuzz_count",
        "prompt": "Write a Python function `solve(n)` returning how many integers from 1..n "
        "(inclusive) are divisible by 3 or 5. Return only the function.",
        "entry": "solve",
        "tests": [((15,), 7), ((1,), 0), ((5,), 2)],
    },
]

LANGUAGE_TASKS = [
    {
        "name": "capital",
        "prompt": "What is the capital of Japan? Answer in one word.",
        "must_include": ["tokyo"],
    },
    {
        "name": "arithmetic",
        "prompt": "What is 17 multiplied by 4? Answer with the number only.",
        "must_include": ["68"],
    },
    {
        "name": "summarize",
        "prompt": "In one short sentence, what does a compiler do?",
        "must_include": ["code", "machine", "program", "instruction", "translat"],
    },
]


def extract_code(text):
    """Pull a python code block if present, else return the raw text."""
    if "```" in text:
        parts = text.split("```")
        for p in parts:
            p = p.strip()
            if p.startswith("python"):
                return p[len("python") :].strip()
        # any fenced block
        if len(parts) >= 2:
            return parts[1].strip()
    return text


def score_coding(output, task):
    """Execute the model's function against the task's tests. Returns (passed, detail)."""
    code = extract_code(output)
    ns = {}
    try:
        # Intentional: the coding benchmark MUST run the model's output to score it against
        # unit tests. Tasks are tiny and self-contained; see llm/README.md caveat. Do not
        # point this harness at untrusted/adversarial prompts.
        exec(code, ns)  # nosec B102
    except Exception as e:
        return False, f"exec_error: {type(e).__name__}: {e}"
    fn = ns.get(task["entry"])
    if not callable(fn):
        return False, f"no function named {task['entry']}"
    for args, want in task["tests"]:
        try:
            got = fn(*args)
        except Exception as e:
            return False, f"call_error on {args}: {type(e).__name__}: {e}"
        if got != want:
            return False, f"wrong: {task['entry']}{args} -> {got!r}, want {want!r}"
    return True, "all tests passed"


def gib(x):
    return round(x / (1024**3), 2)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True, help="HF model id, e.g. Qwen/Qwen2.5-1.5B-Instruct")
    ap.add_argument("--load-in-4bit", action="store_true", default=True)
    ap.add_argument("--no-4bit", dest="load_in_4bit", action="store_false")
    ap.add_argument("--max-new", type=int, default=128)
    ap.add_argument(
        "--out-dir", default=os.path.expanduser("~/projects/intel_arc_770/artifacts/llm")
    )
    args = ap.parse_args()

    from ipex_llm.transformers import AutoModelForCausalLM
    from transformers import AutoTokenizer

    result = {
        "model": args.model,
        "load_in_4bit": args.load_in_4bit,
        "max_new_tokens": args.max_new,
        "device": torch.xpu.get_device_properties(0).name if torch.xpu.is_available() else "no-xpu",
        "timestamp": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    }

    # ---- load ----
    t0 = time.time()
    tok = AutoTokenizer.from_pretrained(args.model, trust_remote_code=True)
    model = AutoModelForCausalLM.from_pretrained(
        args.model,
        load_in_4bit=args.load_in_4bit,
        optimize_model=True,
        trust_remote_code=True,
        use_cache=True,
    )
    model = model.to("xpu")
    torch.xpu.synchronize()
    result["load_seconds"] = round(time.time() - t0, 2)

    def generate(prompt, max_new):
        ids = tok(prompt, return_tensors="pt").input_ids.to("xpu")
        torch.xpu.synchronize()
        t = time.time()
        with torch.inference_mode():
            out = model.generate(ids, do_sample=False, max_new_tokens=max_new, use_cache=True)
        torch.xpu.synchronize()
        dt = time.time() - t
        new = out.shape[-1] - ids.shape[-1]
        text = tok.decode(out[0][ids.shape[-1] :], skip_special_tokens=True)
        return text, new, dt

    # ---- warmup (first run compiles kernels) ----
    generate("Hello.", 8)

    # ---- throughput: short and long prompt ----
    short = "Explain what a GPU does in two sentences."
    long = "Summarize the following: " + ("The Intel Arc A770 is a discrete GPU. " * 60)
    tp = {}
    for label, prompt in [("short", short), ("long", long)]:
        text, n, dt = generate(prompt, args.max_new)
        tp[label] = {
            "new_tokens": n,
            "seconds": round(dt, 3),
            "tokens_per_sec": round(n / dt, 1) if dt else None,
        }
    result["throughput"] = tp
    result["peak_vram_GiB"] = gib(torch.xpu.max_memory_allocated())

    # ---- coding ----
    coding = []
    for task in CODING_TASKS:
        text, _, _ = generate(task["prompt"], 200)
        ok, detail = score_coding(text, task)
        coding.append({"name": task["name"], "passed": ok, "detail": detail})
    result["coding"] = {
        "passed": sum(c["passed"] for c in coding),
        "total": len(coding),
        "tasks": coding,
    }

    # ---- language ----
    lang = []
    for task in LANGUAGE_TASKS:
        text, _, _ = generate(task["prompt"], 48)
        low = text.lower()
        ok = any(k in low for k in task["must_include"])
        lang.append({"name": task["name"], "passed": ok, "answer": text.strip()[:120]})
    result["language"] = {
        "passed": sum(x["passed"] for x in lang),
        "total": len(lang),
        "tasks": lang,
    }

    # ---- report ----
    os.makedirs(args.out_dir, exist_ok=True)
    safe = args.model.replace("/", "_")
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    path = os.path.join(args.out_dir, f"{safe}_{stamp}.json")
    with open(path, "w") as f:
        json.dump(result, f, indent=2)

    # ---- console summary ----
    print("\n==== LLM TEST SUMMARY ====")
    print(f"model      : {result['model']}")
    print(f"device     : {result['device']}")
    print(f"load       : {result['load_seconds']}s")
    print(f"peak VRAM  : {result['peak_vram_GiB']} GiB")
    print(
        f"throughput : short {tp['short']['tokens_per_sec']} tok/s, "
        f"long {tp['long']['tokens_per_sec']} tok/s"
    )
    print(f"coding     : {result['coding']['passed']}/{result['coding']['total']} passed")
    for c in coding:
        print(f"   [{'PASS' if c['passed'] else 'FAIL'}] {c['name']}: {c['detail']}")
    print(f"language   : {result['language']['passed']}/{result['language']['total']} passed")
    for x in lang:
        print(f"   [{'PASS' if x['passed'] else 'FAIL'}] {x['name']}: {x['answer']}")
    print(f"\nwrote {path}")


if __name__ == "__main__":
    main()
