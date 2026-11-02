# LLM test regime — Arc A770 (IPEX-LLM)

Run local language models on the A770 and score them on throughput, VRAM, coding, and
language tasks. Uses [IPEX-LLM](https://github.com/intel/ipex-llm), Intel's XPU runtime —
**not** LM Studio or Ollama, which have no native Intel XPU backend on this card.

## Quick start

```bash
# 1. Install (once). Isolated venv; does NOT touch the verified .venv-xpu stack.
#    Several GB from Intel's mirror — run it in YOUR shell, it can take 30-60+ min.
IPEX_EXTRA=xpu-2-6 bash llm/install_ipex_llm.sh

# 2. Smoke test: one Python hello-world coding task + one English writing paragraph,
#    each on its own small model. This is the "is it working?" check.
bash llm/run_hello.sh

# 3. Full benchmark (optional): throughput + a task suite on any model.
bash llm/run_llm_tests.sh --model Qwen/Qwen2.5-1.5B-Instruct
```

`run_hello.sh` is the fastest way to prove the stack works end to end:

- **Coding** — asks `Qwen/Qwen2.5-Coder-1.5B-Instruct` for a Python `hello()` function,
  then actually executes it and checks it prints `Hello, World!`.
- **Writing** — asks `Qwen/Qwen2.5-1.5B-Instruct` for one English paragraph on a topic,
  then checks it reads like a real 4-6 sentence paragraph.

It prints each model's reply and a `PASS`/`FAIL` summary, and exits non-zero if either fails.

```bash
bash llm/run_hello.sh --topic "the Intel Arc A770 GPU"   # change the writing topic
bash llm/run_hello.sh --skip-writing                     # coding check only
bash llm/run_hello.sh --skip-coding                      # writing check only
bash llm/run_hello.sh --code-model <id> --write-model <id>
```

Default benchmark model if you pass none: `Qwen/Qwen2.5-1.5B-Instruct` (small, quick).

### Install notes

- `IPEX_EXTRA=xpu-2-6` selects the torch 2.6.0+xpu stack (needs Python 3.11+; `.venv-llm`
  is built with 3.11). On a 3.10 interpreter the script falls back to the older `[xpu]`
  extra automatically.
- The install pins an exact `ipex-llm` datestamp (`IPEX_VERSION`, default `2.3.0b20251026`).
  The `xpu-2-6` extra requires a **same-date** `bigdl-core-xe-all` wheel; not every date has
  one (e.g. `2.3.0b20251110` fails with *"No matching distribution found for
  bigdl-core-xe-all==2.7.0b20251110"*). If you bump `IPEX_VERSION`, first confirm the match:
  `pip index versions bigdl-core-xe-all --pre --extra-index-url https://pytorch-extension.intel.com/release-whl/stable/xpu/us/`

## What it measures

| metric | how |
|:--|:--|
| load time, peak VRAM | timed load + `torch.xpu.max_memory_allocated` |
| throughput | greedy decode tokens/sec at a short and a long prompt |
| coding | 3 HumanEval-style problems, scored by running the output against unit tests |
| language | 3 short deterministic prompts with keyword checks |

Results: `artifacts/llm/<model>_<timestamp>.json` plus a console summary.

## Models that fit 15 GiB (4-bit)

| model | approx VRAM (4-bit) |
|:--|:--|
| Qwen2.5-1.5B-Instruct | ~2 GiB |
| Qwen2.5-Coder-1.5B-Instruct | ~2 GiB (coding, used by `run_hello.sh`) |
| Qwen2.5-7B-Instruct | ~6 GiB |
| Qwen2.5-14B-Instruct | ~9 GiB |
| Qwen2.5-Coder-7B | ~6 GiB (coding-focused) |

Larger single-tensor needs are covered by our 4 GiB-cap unlock
(`NEOReadDebugKeys=1 AllowUnrestrictedSize=1`, set in `xpu_runtime.env`).

## Notes & caveats

- **First run per model is slow** — kernel compile + weight download. Later runs are fast
  (`SYCL_CACHE_PERSISTENT=1`).
- **Coding scorer runs model output** via `exec` to check correctness. The tasks are tiny and
  self-contained, but treat any model-generated code as untrusted; run on a machine you don't
  mind. Do not point this at adversarial prompts.
- IPEX-LLM pins its own torch build; that's why it lives in `.venv-llm`, separate from the
  `.venv-xpu` (torch 2.6.0+xpu) we verified for the memory study.
- `install_ipex_llm.sh` downloads several GB from Intel's mirror — run it in your own shell.
