# Follow-up: techniques, harnesses and packages not yet tried (2026-11-06)

Audit of what the earlier cycles skipped, with measurements for everything that could be run
without human approval. Negative and unexplained results are stated as such.

## Environment (applies to every number below)

- GPU: Intel Arc A770 16 GiB, PCI `8086:56a0`, i915 driver
- OS/kernel: Ubuntu 24.04, kernel 7.0.0-42-generic
- Vulkan driver: Mesa 25.2.8-0ubuntu0.24.04.4 (ANV), Vulkan API 1.4.318
- NEO/IGC/GmmLib: for §1-§4, **not installed and not used** (the Vulkan path goes through
  Mesa). For §5-§6 (installed with approval 2026-11-06, from the GitHub release `.deb`s,
  sha256 matched against GitHub's published digests): NEO 26.40.40196.8, IGC 2.42.6,
  GmmLib 22.10.2 (replaced Ubuntu's 22.3.17), Level Zero loader 1.34.0. Vulkan re-checked after
  the install: Qwen2.5-7B tg128 45.7 / pp512 1014, i.e. no regression.
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
| **14B + draft, n-max 3** | **31.9** | **+48%** | 61% | 4/5 | 3/5 |
| 14B + draft, n-max 5 | 27.9 | +30% | 49% | 5/5 | 3/5 |
| 14B + draft n-max 4, `-fa off --cache-ram 0` | 29.6 | +38% | 55% | 4/5 | 3/5 |
| 14B `-fa off --cache-ram 0` (no draft) | 23.0 | +7% | — | 4/5 | 3/5 |
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
- n-max 3 is the best setting on the 14B (31.9), then 4 (30.9), 5 (27.9) and 8 (12.2).
  Acceptance falls as the draft length grows, and each rejected run wastes a verification pass.
  Adding the flash-attention change (§3) on top doesn't help on these short prompts.
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

## 3. Long context and flash attention — resolved: a big win for long prompts

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

**In the server it first looked like the opposite, and the cause is now found.** The harness
with `-fa off` on Qwen2.5-7B ran at 21.8 / 24.0 / 22.2 tok/s (three runs, one with `-np 1`) vs
42.0 / 42.4 with defaults. Yet the server's own generation timing with `-fa off` was *faster*
(44.9-45.2 vs 43.5 tok/s) and its per-request totals matched. The lost time sits between
"selected slot by LCP similarity" and "launch_slot" in the server log: **1.8-3.1 s per request
with `-fa off`, ~12 ms with defaults.** That step is the host-RAM prompt cache (`--cache-ram`,
default 8192 MiB) saving and restoring slot state. The cause of the slowness is inferred, not
profiled: without flash attention the V cache is stored transposed, which makes copying it to
host RAM expensive. Confirmed by switching the cache off:

| Qwen2.5-7B, hard set | median tok/s | coding | writing |
|:--|--:|:--:|:--:|
| defaults | 42.3 | 4/5 | 2/5 |
| `-fa off` | 22-24 | 4/5 | 3/5 |
| **`-fa off --cache-ram 0`** | **43.7** | 4/5 | 3/5 |

Long prompt through the real server (~10.9K-token prompt, ctx 16384, `-np 1`, 2 runs each,
fresh prefix per run; `llm/harness-alpha/run_long_prompt_ab.sh`):

| model | config | wall s | prompt tok/s | gen tok/s |
|:--|:--|--:|--:|--:|
| Qwen2.5-7B | defaults | 27.9 / 29.0 | 431 / 418 | 32.8 |
| Qwen2.5-7B | **`-fa off --cache-ram 0`** | **19.3 / 19.3** | 630 / 628 | 37.5 |
| Qwen2.5-14B | defaults | 67.4 / 68.0 | 179 / 180 | 14.1 |
| Qwen2.5-14B | **`-fa off --cache-ram 0`** | **40.6 / 40.7** | 307 / 303 | 17.7 |

**For long prompts (big files, long documents), `-fa off --cache-ram 0` cuts response time
31-40%.** The cost is losing the host-RAM prompt cache, which lets the server resume *other*
conversations without re-reading them; reuse within the active slot still works. Also, without
flash attention the 14B fits ~20K of context instead of ~24K (below).

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
| **OpenVINO GenAI** | **runs on the GPU; no speed gain on identical weights** | See §6. |
| llama.cpp SYCL | not worth retrying | Our earlier 33.9 vs 40.2 (Vulkan) matches upstream: llama.cpp issue [#19918](https://github.com/ggml-org/llama.cpp/issues/19918) ("SYCL is slower than VULKAN (A770)"), where a SYCL maintainer agrees Vulkan is currently faster. |
| Ollama | not worth it | Runs Intel Arc through the same Vulkan backend; no speed gain over llama.cpp expected. |
| llama-bench / perplexity / quantize | **added** | Were never built. Built locally (13 s, same build dir); used for every pp/tg number above. |

## 6. OpenVINO GenAI on the A770

- Stack: `openvino-genai==2026.4.1.0` (+ `openvino==2026.4.1`, `openvino-tokenizers==2026.4.1.0`)
  in `.venv-ov`, NEO 26.40 as in the environment section. `ov.Core().available_devices` →
  `['CPU', 'GPU']`, GPU = "Intel(R) Arc(TM) A770 Graphics (dGPU)".
- **Driver finding:** NEO 26.40 enumerates the A770 on kernel 7.0 (OpenCL platform "Intel(R)
  OpenCL Graphics", 15.11 GiB, 4 GiB max single allocation). On kernel 6.8, NEO 26.35 found
  0 devices (`reports/data/driver-baseline/container_track_b_result.txt`).
- Harness wrapper: `llm/harness-alpha/run/ov_server.py` (OpenAI-compatible, greedy, same
  tok/s definition) + `run/run_openvino.sh`.

**Same weights as llama.cpp** (OpenVINO GenAI reading our `Qwen2.5-7B-Instruct-Q4_K_M.gguf`):

| measurement | OpenVINO GPU | llama.cpp Vulkan |
|:--|--:|--:|
| harness hard set, median tok/s | 38.4 | 42.0-42.7 |
| harness hard set, coding / writing | 4/5 / 2/5 | 4/5 / 2/5 |
| steady-state generation, 256 tokens (`llm/harness-alpha/ov_sweep.py`) | 41.5-42.2 | 43.6-45.7 (tg128) |

OpenVINO's `KV_CACHE_PRECISION` f16/u8, `DYNAMIC_QUANTIZATION_GROUP_SIZE=32` and
`PERFORMANCE_HINT=LATENCY` all landed within 41.5-42.2 tok/s, so none of them is a lever. On
identical Q4_K_M weights **OpenVINO is ~5-10% slower than llama.cpp Vulkan**, and the task
scores match.

**Native OpenVINO int4** (`OpenVINO/Qwen2.5-7B-Instruct-int4-ov`, the format the published
"2x" claims use): downloading; queued to be scored by `llm/harness-alpha/run_pending_evals.sh`.
Pending.

## Recommendations

1. **Quality work (coding):** Qwen2.5-14B + 0.5B draft, `--spec-draft-n-max 3` → ~32 tok/s.
2. **Fast writing / general:** Llama-3.1-8B, default flags → ~42 tok/s.
3. **Long prompts (large files or documents, ~8K+ tokens):** add `-fa off --cache-ram 0`; it
   cuts response time 31-40% at ~11K tokens. Leave it off for many short multi-conversation
   requests, where the prompt cache helps.
4. OpenVINO: on identical weights it's no faster than Vulkan. The native int4 result is still
   pending.
5. Pending (unattended, `run_pending_evals.sh`): OpenVINO native int4, then gpt-oss-20b with and
   without EAGLE3.
6. Not run, by choice:
   - llama.cpp SYCL: our earlier 33.9 vs 40.2, plus upstream #19918, say Vulkan is faster. It
     would need a multi-GB oneAPI download on a 0.3-0.6 MiB/s link.
   - `xe` kernel driver: needs a reboot with changed kernel parameters, so it needs you present.
