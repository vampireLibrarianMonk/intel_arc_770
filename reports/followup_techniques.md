# Follow-up: techniques, harnesses and packages not yet tried (2026-11-06)

Audit of what the earlier cycles skipped, with measurements for everything that could be run
without human approval. Negative and unexplained results are stated as such.

## Environment (applies to every number below)

- GPU: Intel Arc A770 16 GiB, PCI `8086:56a0`, i915 driver
- OS/kernel: Ubuntu 24.04, kernel 7.0.0-42-generic
- Vulkan driver: Mesa 25.2.8-0ubuntu0.24.04.4 (ANV), Vulkan API 1.4.318
- NEO/IGC/GmmLib: **not installed and not used** (the Vulkan path goes through Mesa). This is
  also why OpenVINO cannot see the GPU — see §5.
- llama.cpp: source tarball `llama.cpp-dde879b`, Vulkan build; `llama-server --version`
  reports `0.8.0-dev (build 22, b2bb5ab)`
- All models Q4_K_M GGUF, sha256-verified, `-ngl 999`. Harness runs: hard task set, greedy,
  ctx 4096, `max_tokens` 512.
- Raw data: `reports/data/tuning-24.04-kernel7.0/` (harness JSON) and
  `reports/data/tuning-24.04-kernel7.0/llama-bench/` (llama-bench tables).

## 1. Speculative decoding — the one lever that helps

Draft model: `Qwen2.5-0.5B-Instruct-Q8_0` (shares the Qwen2.5 tokenizer), fully on GPU.
Script: `llm/harness-alpha/run_spec_decoding.sh`.

| config | median tok/s | vs base | draft acceptance | hard coding | hard writing |
|:--|--:|--:|--:|:--:|:--:|
| 14B base (run 1 / run 2) | 21.5 / 21.5 | — | — | 5/5 / 5/5 | 3/5 / 3/5 |
| **14B + draft, n-max 4** (run 1 / run 2) | **31.0 / 30.9** | **+44%** | 54% | 4/5 / 4/5 | 2/5 / 2/5 |
| 14B + draft, n-max 8 | 12.2 | −43% | 39% | 4/5 | 3/5 |
| 14B ngram-mod / ngram-simple | 21.5 / 21.4 | 0% | (no drafts) | 5/5 | 3/5 |
| 7B base | 42.2 | — | — | 4/5 | 2/5 |
| 7B + draft, n-max 4 | 46.4 | +10% | 61% | 4/5 | 1/5 |
| 7B + draft, n-max 8 | 19.4 | −54% | 46% | 4/5 | 3/5 |
| 7B ngram-mod | 42.0 | 0% | — | 4/5 | 2/5 |
| DeepSeek-Coder-V2-Lite ngram-mod | 56.3 | (58.6 earlier) | — | 4/5 | 0/5 |

Reproduce: `bash llm/harness-alpha/run_spec_decoding.sh` (or `VARIANTS="14b-draft4"`).
Server flags: `--spec-type draft-simple -md <0.5B gguf> --spec-draft-ngl 999 --spec-draft-n-max 4`.

Findings:
- **Qwen2.5-14B goes from 21.5 to 31.0 tok/s with a 0.5B draft (n-max 4), reproduced twice.**
  That closes about half the speed gap between the 14B and the 7-8B models. On the 7B it is a
  much smaller +10%: the 0.5B draft costs relatively more when the target is only 14x larger.
- n-max 8 is much slower on both models: acceptance falls and each rejected run wastes a
  verification pass. 4 is the right setting here; 2, 3, 5 and 6 were not tried.
- The n-gram modes did nothing on this task set. They need repeated text to copy (editing,
  refactoring, rewriting a document), which these short generation tasks don't have.
  Untested on such workloads.
- **The draft changed outputs, but it shouldn't have.** Greedy speculative decoding should
  produce the same text. Here the 14B lost `basic_calculator` (5/5 → 4/5) in both draft runs.
  The likely cause is that batched verification takes a different matmul path, so the
  floating-point results differ slightly and greedy argmax flips on close calls. This is
  inferred, not confirmed. The 14B's pass on that task is fragile anyway: it also fails it with
  `-fa off` (§3). So read the 14B's 5/5 as "usually solves it", not as a stable margin.
- Uncertainty: two runs per 14B config, one per 7B config. tok/s repeated to within 0.1; the
  task scores are the noisier signal.

## 2. Vulkan cooperative matrix (matrix cores) on the A770 — negative

Mesa exposes `VK_KHR_cooperative_matrix`, and our shader compiler supports it, but llama.cpp
logs `matrix cores: none`. The source deliberately allow-lists only Xe2 and some integrated Xe1
for Intel, citing "performance regressions" on the A770. I tested that claim with a one-line
patch (`patches/ggml-vulkan-allow-xe1-discrete-coopmat.patch`) in a separate source copy:

| model | stock pp512 | coopmat pp512 | stock tg128 | coopmat tg128 |
|:--|--:|--:|--:|--:|
| Qwen2.5-7B | 983 | 114 | 44.1 | 44.3 |
| Llama-3.1-8B | 977 | 99 | 43.3 | 43.3 |
| Qwen2.5-14B | 523 | 51 | 22.6 | 22.5 |

**Prompt processing is ~9-10x slower with matrix cores on; generation is unchanged.** Upstream
is right to disable it on this stack. The patch is kept so this can be re-tested after a Mesa
upgrade. It has not been applied to the build the harness uses.

## 3. Long context and flash attention — partly unexplained

llama-bench at prior-context depth (`-d`), default flags (flash attention auto = on):

| model | tg @0 | tg @4K | tg @16K | pp512 @0 | pp512 @16K |
|:--|--:|--:|--:|--:|--:|
| Qwen2.5-7B | 44.6 | 38.4 | 27.8 | 997 | 144 |
| Llama-3.1-8B | 43.0 | 39.4 | 31.7 | 983 | 98 |
| Qwen2.5-14B | 22.5 | 18.0 | 11.4 | 521 | 58 |
| DeepSeek-Coder-V2-Lite | 63.6 | 50.5 | 31.0 | 1436 | 178 |

Long prompts are expensive: at 16K of context, reading a 512-token chunk is 5-10x slower than at
the start, and generation slows 30-50%.

llama-bench with `-fa 0` vs `-fa 1` at depth (pp512 / tg64):

| model | depth | fa off | fa on |
|:--|:--|:--|:--|
| Qwen2.5-7B | 16K | 293 / 36.2 | 142 / 27.8 |
| Llama-3.1-8B | 16K | 245 / 30.3 | 100 / 31.5 |
| Qwen2.5-14B | 16K | 132 / 17.2 | 58 / 11.4 |
| DeepSeek-Coder-V2-Lite | 16K | 441 / 30.4 | 182 / 31.0 |

In llama-bench, turning flash attention off doubles long-context prompt processing on every
model, and improves generation on the Qwen models.

**But in the real server it does the opposite.** The harness with `-fa off` on Qwen2.5-7B ran at
21.8 / 24.0 / 22.2 tok/s (three runs, one with `-np 1`) vs 42.0 / 42.4 with defaults. The
machine was idle, and the shared-KV/slot difference was ruled out by the `-np 1` run. The cause
is **not known**. Until it is, **do not turn flash attention off in the server.** The llama-bench
advantage may still be usable for long-document batch work through `llama-cli`, but that's
untested.

Memory ceiling (how much context fits on 16 GiB, one sequence): Qwen2.5-7B ran at 32K depth
with `-fa 0` (pp 174, tg 30.0). Qwen2.5-14B ran at 24K with `-fa 1` (tg 8.8), ran at 20K with
`-fa 0`, and ran out of device memory at 24K with `-fa 0`. 8-bit KV cache with flash attention
was within ~5% of f16 at 4-16K. Its use is fitting more context, not speed.

## 4. Models not yet evaluated

- **gpt-oss-20b (MXFP4, 12.1 GB, MoE ~3.6B active)** — the most-cited 16 GB model in current
  roundups. Downloading via `setup/fetch_followup_models.sh`, together with its EAGLE3 draft
  head (on disk). About 10 h left at ~0.3 MiB/s. Not yet scored.
- Exist on HF, not downloaded: Qwen3.5-9B (Q4_K_M 5.7 GB), Gemma-4-26B-A4B MoE (IQ4_XS 14.2 GB —
  tight on 16 GiB with any context).

## 5. Harnesses / packages

| option | status | evidence |
|:--|:--|:--|
| **OpenVINO GenAI** | **blocked — needs approval** | Installed pinned `openvino-genai==2026.4.1.0` in `.venv-ov` (local, git-ignored). It sees only `CPU`: the GPU plugin needs the Intel compute runtime (NEO OpenCL / Level Zero), which is not installed system-wide. Installing it is a driver-package change (AGENTS.md approval gate). An independent A770 benchmark ([diunox/arc-inference-bench](https://github.com/diunox/arc-inference-bench), Mar 2026) reports OpenVINO INT4 at 57 tok/s for Mistral-7B and 46 for Qwen3-8B. That's above our ~42-44 for 7-8B Q4_K_M, but on a different stack, models and quantisation, so treat it as a lead to test, not a result. |
| llama.cpp SYCL | not worth retrying | Our earlier 33.9 vs 40.2 (Vulkan) matches upstream: llama.cpp issue [#19918](https://github.com/ggml-org/llama.cpp/issues/19918) ("SYCL is slower than VULKAN (A770)"), where a SYCL maintainer agrees Vulkan is currently faster. |
| Ollama | not worth it | Runs Intel Arc through the same Vulkan backend; no speed gain over llama.cpp expected. |
| llama-bench / perplexity / quantize | **added** | Were never built. Built locally (13 s, same build dir); used for every pp/tg number above. |

## Recommendations

1. **Quality work:** Qwen2.5-14B + 0.5B draft (n-max 4) → ~31 tok/s. **Fast writing:**
   Llama-3.1-8B, default flags (~42 tok/s). Keep flash attention at its default in the server.
2. **Highest-value next step needs your approval:** install the Intel compute runtime (NEO +
   Level Zero) so OpenVINO can use the GPU, then compare it against Vulkan on the same task
   set. Prefer a local prefix or container (`llm/harness-alpha/container/` already has NEO
   Dockerfiles) over system packages.
3. Score gpt-oss-20b when it lands, with and without its EAGLE3 draft.
4. Find out why `-fa off` halves server generation while llama-bench says it should help.
