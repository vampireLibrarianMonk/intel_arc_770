# LLM test regime — Arc A770 (IPEX-LLM)

Run local language models on the A770 and score them on throughput, VRAM, coding, and
language tasks. Uses [IPEX-LLM](https://github.com/intel/ipex-llm), Intel's XPU runtime —
**not** LM Studio or Ollama, which have no native Intel XPU backend on this card.

## Two commands

```bash
# 1. Install (once). Isolated venv; does NOT touch the verified .venv-xpu stack.
bash llm/install_ipex_llm.sh

# 2. Test (any model). Downloads weights on first use.
bash llm/run_llm_tests.sh --model Qwen/Qwen2.5-1.5B-Instruct
```

Default model if you pass none: `Qwen/Qwen2.5-1.5B-Instruct` (small, quick smoke test).

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
