# Harness alpha cycle — results (Arc A770)

Goal: find a CLI/local-inference harness good for **creative-writing** and **coding**
assistance on the Intel Arc A770, judged by real runs on the card — not blog claims.

All GGUF candidates ran the **same model** (`Qwen2.5-7B-Instruct`, Q4_K_M GGUF, sha256
`65b8fcd9…`), the **same fixed task set** (4 coding + 4 creative-writing), and the **same
OpenAI-compatible benchmark driver** with greedy decoding. IPEX-LLM ran the same model
family in its native 4-bit (not identical bytes — see caveats).

## Results

| candidate | backend | coding (executed) | writing constraints | median tok/s | GPU confirmed |
|:--|:--|:--:|:--:|--:|:--|
| **llamacpp-vulkan** | Vulkan (Mesa ANV) | **4/4** | 4/4 | **40.2** | yes¹ |
| **lmstudio** | Vulkan (bundled) | **4/4** | 4/4 | 37.4 | yes² |
| **llamacpp-sycl** | SYCL (oneAPI 2026.2) | **4/4** | 4/4 | 33.9 | yes⁴ |
| **ipex-llm** | XPU (IPEX-LLM, 4-bit) | 3/4 | 4/4 | 16.6 | yes³ |

¹ Confirmed by throughput: 40 tok/s GPU vs **8.5 tok/s** CPU-only (`-ngl 0`) baseline, same binary/model (5×).
² LM Studio's own device survey reports `Intel Arc A770 (Vulkan, Discrete, 15.91 GiB)` as the loaded device; Vulkan runtime selected.
³ IPEX-LLM loads on the XPU via Level-Zero; `/proc/<pid>/fdinfo` shows device-local VRAM for this path (unlike Vulkan — see below).
⁴ SYCL initially SEGV'd; fixed during the alpha exploration (see `reports/sycl_fix_plan.md`): build `-DGGML_SYCL_SUPPORT_LEVEL_ZERO_API=OFF -DGGML_SYCL_DNN=OFF` + run `SYCL_CACHE_PERSISTENT=0`. Now stable and correct, but slower than Vulkan because those workarounds disable oneDNN + the kernel cache.

## The three claims, kept separate (per AGENTS.md)

1. **Ran on the GPU** — Vulkan (both), IPEX: yes. SYCL: crashes before serving.
2. **Output correct/usable** — coding scored by *executing* generated code against hidden
   tests. Vulkan harnesses: 4/4. IPEX: 3/4 (the 7B in IPEX 4-bit mis-solved `longest_run`
   by sorting the list — a model/quantization behavior difference, not an infra fault).
   Writing: all candidates met the measurable constraints; quality is comparable (samples
   saved verbatim in each candidate's JSON for human judgement).
3. **Throughput** — Vulkan ~37-40 tok/s, IPEX ~17 tok/s on the same 7B. A fast harness that
   produced wrong output would still be a fail; none did except the SYCL crash.

## Key findings

- **Vulkan is the reliable, fast llama.cpp path on this A770 today.** Raw llama.cpp Vulkan
  (40 tok/s) edged LM Studio's bundled Vulkan runtime (37 tok/s) by ~7% — expected, since
  LM Studio adds a server/queue layer over the same backend.
- **SYCL now runs — after two bug workarounds — but is slower than Vulkan.** llama.cpp SYCL
  initially segfaulted (two distinct bugs: a Level-Zero Sysman memory-query SEGV in NEO 24.39,
  and a persistent-device-code-cache SEGV in oneAPI 2026.2's libsycl). Both were isolated by
  gdb backtrace and fixed at build/run time (`-DGGML_SYCL_SUPPORT_LEVEL_ZERO_API=OFF
  -DGGML_SYCL_DNN=OFF`, `SYCL_CACHE_PERSISTENT=0`) — no driver change. Result: stable, 4/4
  coding, 4/4 writing, **33.9 tok/s**. But because the fixes disable oneDNN (optimized GEMM)
  and the kernel cache, SYCL ends up **slower than Vulkan (40.2)**. On this exact stack the
  theoretically-faster backend does not win once made stable. Full writeup + reproduction:
  `reports/sycl_fix_plan.md`.
- **IPEX-LLM is ~2.4× slower** than Vulkan for this workload (17 vs 40 tok/s) and pulls a
  15 GB fp16 download vs a 4.5 GB GGUF, but it is the most *stable* native-XPU path and the
  only one whose GPU memory is visible in `fdinfo`.
- **GPU-probe caveat (worth recording):** the Vulkan/Mesa (ANV) driver does **not** export
  per-process device memory in `/proc/<pid>/fdinfo` the way the i915 compute/Level-Zero path
  (IPEX) does. A naïve VRAM probe reports 0 MiB for a Vulkan process that is genuinely on the
  GPU. The authoritative GPU signal for the Vulkan path is tokens/sec vs the CPU baseline.

## Recommendation (for creative writing + coding assistance on this A770)

- **Primary: llama.cpp Vulkan** (`llama-server`) — fastest, stable, single 4.5 GB GGUF,
  OpenAI-compatible, scriptable. Best for an editor/agent integration.
- **For a friendlier UX: LM Studio** — ~7% slower (same Vulkan backend) but adds model
  management, a GUI, and the same OpenAI API; good when a human is in the loop.
- **Avoid SYCL llama.cpp on this exact driver stack** until the slot-init crash is patched.
- **IPEX-LLM**: keep as the stable native-XPU fallback / for PyTorch-side work, not for
  latency-sensitive assistance.

## Reproduce

```
bash llm/harness-alpha/fetch_all.sh          # (durable: systemd-run --user --unit=ha-fetch …)
bash llm/harness-alpha/setup/llamacpp_vulkan.sh
bash llm/harness-alpha/setup/llamacpp_sycl.sh
bash llm/harness-alpha/run_all.sh            # runs every ready candidate, skips the rest
python llm/harness-alpha/aggregate.py        # prints this table, writes combined.json
```

Raw per-candidate results: `artifacts/harness-alpha/<candidate>_<timestamp>.json`
(includes every prompt's raw model output for human quality review).

## Environment

- GPU: Intel Arc A770 16 GiB (DG2), i915; Vulkan via Mesa ANV (1.4.313 headers), discrete.
- oneAPI DPC++/C++ 2026.2.0; oneDNN 3.13.2; oneMKL 2026.2; llama.cpp `b1-dde879b`.
- IPEX-LLM `.venv-llm` (torch 2.6.0+xpu). LM Studio 0.4.28 (llama.cpp vulkan runtime 2.67.0).
- Model: Qwen2.5-7B-Instruct Q4_K_M (GGUF, bartowski) / Qwen/Qwen2.5-7B-Instruct (HF, IPEX 4-bit).

## Creative-writing quality (human-review samples)

Same model + greedy decoding, so backend choice barely affects *quality* — it's dominated by
the model and decode settings. The one quality-relevant difference is quantization: the GGUF
candidates use Q4_K_M; IPEX uses its own 4-bit, which produces slightly different phrasings.

**micro-fiction (3 sentences, no "water", keeper who never saw the sea):** all three met the
hard constraints. LM Studio named the character ("Elias"); Vulkan's "never felt the embrace
of the shore" was the most evocative avoidance of the forbidden word.

**mystery opening paragraph:** all three opened near-identically ("The rain lashed against
the windows of the old lighthouse…") — expected from the shared model + greedy decode. LM
Studio ended on the sharpest hook ("some mysteries were best left unsolved").

**tone rewrite & quatrain:** Vulkan and LM Studio produced essentially identical text (same
weights, same greedy path); IPEX diverged more due to its different 4-bit quantization.

**Conclusion for writing:** pick the backend on **speed and UX**, not quality — they're
equivalent here. That favors llama.cpp Vulkan (fast, scriptable) or LM Studio (fast, GUI).
Raw per-prompt text for all candidates is in `artifacts/harness-alpha/<candidate>_*.json`.

See `reports/sycl_fix_plan.md` for the plan to repair the SYCL backend (toolchain⇄driver
version-skew is the leading hypothesis: built against oneAPI 2026.2, driven by NEO 24.39).
