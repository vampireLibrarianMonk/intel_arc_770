# Changelog

All notable changes to arc-a770-lab. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added — speculative decoding, model registry, follow-up audit (2026-11-06)
- **Speculative decoding is the first measured throughput win:** Qwen2.5-14B + Qwen2.5-0.5B
  draft (`--spec-draft-n-max 4`) runs **31.0 tok/s vs 21.5** (+44%, reproduced twice; 54% draft
  acceptance). The 7B gains only +10% (42.2 → 46.4). n-max 8 is slower on both; n-gram
  speculation does nothing on this task set. Caveat: the draft changed greedy outputs (14B
  coding 5/5 → 4/5 in both runs, on the already-fragile `basic_calculator`).
  `llm/harness-alpha/run_spec_decoding.sh`.
- **Negative:** enabling Vulkan cooperative-matrix (matrix cores) on the A770 makes prompt
  processing ~9-10x slower with no generation change, confirming upstream's allow-list. Patch
  kept for re-testing on newer Mesa: `patches/ggml-vulkan-allow-xe1-discrete-coopmat.patch`.
- **Unexplained:** llama-bench shows `-fa 0` doubling long-context prefill, but `-fa off` in
  `llama-server` halves generation in the harness (3 runs, `-np 1` ruled out). Defaults kept.
- Context sweep: generation falls 30-50% and prefill 5-10x by 16K context. Fits measured:
  7B 32K (fa off), 14B 24K (fa on) / 20K (fa off).
- `llm/harness-alpha/MODELS.md`: registry of all on-disk models (sha256 re-verified, all 8
  match), pp/tg per model, hard-set scores, keep/prune verdicts, recommended configs.
- `setup/fetch_followup_models.sh`: hash-pinned fetch of the 0.5B draft, gpt-oss-20b MXFP4 and
  its EAGLE3 head (gpt-oss still downloading).
- Built `llama-bench`, `llama-perplexity`, `llama-quantize` (were never built).
- Ran the Qwen2.5-Coder-7B hard set, which had never completed: 4/5 coding, 3/5 writing,
  41.8 tok/s.
- OpenVINO GenAI 2026.4.1 installed in `.venv-ov` (local), but it only sees the CPU: the GPU
  plugin needs the Intel compute runtime, which is an approval-gated driver install.
- Full write-up: `reports/followup_techniques.md`.

### Verified — kernel 7.0 upgrade holds the Vulkan throughput fix; tuning matrix finds no faster flags
- Rebooted onto kernel **7.0.0-42** (from 6.8.0-147). Confirmed: `i915` still binds the A770
  (xe loaded, 0 refs), `render`/`video` groups now apply without an `sg` wrapper, Vulkan sees
  the card via Mesa 25.2.8 (API 1.4.318). Re-ran the Vulkan baseline → **41.0 tok/s** (4/4
  coding, 4/4 writing), within noise of the pre-reboot 41.9 — the glslc fix survived the
  kernel upgrade.
- **Negative result (stated plainly):** swept six llama.cpp Vulkan launch-flag variants
  (flash-attn on, 8-bit KV cache, ubatch 256/1024, and combinations) against the baseline.
  **None beat the defaults.** `-fa on` and ubatch resizing were within ±0.5 tok/s noise;
  8-bit KV cache (`-ctk/-ctv q8_0`) measurably *hurt* (−1.5 tok/s) — on the Mesa/ANV path the
  per-access dequant cost outweighs the bandwidth saving at 7B-Q4 / 4K context. Conclusion:
  default flags are already near-optimal for throughput; the ~41 tok/s ceiling is not set by
  these knobs. Correctness held across all variants.

### Added — Vulkan tuning matrix
- `llm/harness-alpha/run_tuning_matrix.sh`: sweeps single-variable tuning levers as distinct
  candidates, reusing the shared driver + task set. `run/run_llamacpp.sh` parameterized with
  `LLAMACPP_EXTRA_FLAGS`, `CANDIDATE_SUFFIX`, `LLAMACPP_CTX`, `LLAMACPP_MODEL` (defaults
  unchanged → still reproduces the ~41 tok/s baseline).
- `reports/tuning_matrix_plan.md`: context, hypotheses, results tables, and conclusions for
  the flag matrix, GPU clock headroom, and the model sweep.
- `reports/data/tuning-24.04-kernel7.0/`: env capture + raw per-variant/per-model JSON.

### Added — hard discriminating task set + harness robustness fix
- `llm/harness-alpha/tasks_hard.py`: 5 real algorithmic coding problems (longest palindromic
  substring, edit distance, interval merge, coin change, hand-written expression parser) with
  edge-case tests, and 5 tighter writing tasks (exact 6-word story, compound forbidden+required
  constraints, C-O-D-E acrostic, jargon-free explanation, subtext dialogue). Selectable via
  `bench_openai.py --task-set hard` / `TASK_SET=hard`; `run_hard_suite.sh` runs it on all
  on-disk models. `score.py` gains required-inclusion + acrostic checks.
- **It discriminates:** on the hard set the 7B scores coding 4/5 + writing 2/5 vs the 14B's
  **5/5 + 3/5** — the capability gap the alpha set (both 4/4) couldn't show. Both still miss
  the hardest negative-constraint instruction-following, leaving headroom for larger models.
- **Fixed a harness hang the hard set exposed:** harder prompts make models more likely to
  emit infinite loops; `score_coding` ran model code unbounded and one looping generation
  stalled the whole benchmark (~14 min). Added a `SIGALRM` watchdog around the defining
  `exec` and every test call — a runaway now fails as a timeout. Unit-verified.

### Researched + tested — alternatives to Qwen (not locked in)
- `reports/tuning_matrix_plan.md` lists non-Qwen open-weight models that fit 16 GiB at Q4
  with mature GGUF support and complementary strengths. `run_alt_models.sh` + the hardened
  harness benchmark them on the hard task set; `reports/alt_models_comparison.md` collects the
  side-by-side.
- **First results confirm we are not stuck with Qwen:** **Llama-3.1-8B** matches the Qwen-14B
  writing score (3/5 hard) at half the params and ~2x the speed (42 vs 22 tok/s), and ties
  Qwen-7B on coding — a strong, faster writing default. **Phi-3.5-mini (3.8B)** runs
  **76.8 tok/s** (~2x the 7-8B class) but drops quality (3/5 coding, 2/5 writing) — a
  speed-for-simple-work pick.
- **Remaining three models now scored** (hard set, Vulkan, kernel 7.0, all sha256-verified,
  GPU at 2400 MHz): **DeepSeek-Coder-V2-Lite** 58.6 tok/s, coding 4/5, writing 0/5;
  **Gemma-2-9B** 26.9 tok/s, 3/5 + 2/5; **Mistral-Nemo-12B** 27.9 tok/s, 4/5 + 1/5. None beat
  Llama-3.1-8B (writing) or Qwen-14B (quality). The MoE is the speed outlier (2.7x the
  Qwen-14B) but is not a writer and does not out-code the 7-8B dense models. Single greedy run
  per model; a one-task gap is within noise. Cause of gemma-2/Nemo's lower tok/s not
  investigated. Details: `reports/alt_models_comparison.md`.

### Added — resume driver for unscored models; optional HF auth in fetcher
- `llm/harness-alpha/run_alt_models_pending.sh`: runs only the gemma/Nemo/DeepSeek rows with the
  same fetcher, runner, flags and candidate suffixes as `run_alt_models.sh`, so finished models
  are not re-benchmarked.
- `setup/get_model_generic.sh`: if `HF_TOKEN`/`HUGGING_FACE_HUB_TOKEN` is set, sends it as a
  Bearer header via a curl config on stdin (not in argv/`ps`, not logged). Anonymous fetch is
  unchanged when unset. It did not speed up downloads: the cap measured the same against a
  non-HF server, so the earlier "throttled HF mirror" diagnosis was wrong (local uplink).
- `.gitignore`: ignore `.env` / `.env.*` so a token file cannot be committed by accident.

### Investigated — GPU clock headroom + model sweep (where the real lever is)
- **GPU is not clock/thermal-limited:** read-only telemetry shows the A770 pins its max
  2400 MHz (RP0) under load with every `throttle_reason_*` flag at 0. Raising clocks is a
  non-lever — nothing to raise. No power/clock changes made (AGENTS.md gate respected).
- **Model sweep (7B / Coder-7B / 14B, all Q4, Vulkan):** throughput is governed by parameter
  count, not flags or clocks. Both 7B models run **42 tok/s** (coding 4/4, writing 4/4);
  **14B runs 21.9 tok/s** (coding 4/4, writing 3/4 — the one miss is a structural
  `min_sentences` check, not a quality failure). 14B (8.4 GB) fits 16 GiB comfortably and
  stays interactive. Recommendation: **Coder-7B** for interactive coding (free on speed),
  **14B** for a quality pass. Added `run_model_sweep.sh` + `setup/get_model_generic.sh`
  (sha256-gated fetch for any GGUF). Key limitation surfaced: the current task set is too
  easy to rank model quality (everything scores ~4/4) — a harder, discriminating suite is the
  next step.

### Fixed — Vulkan Q4 throughput regression on Ubuntu 24.04 (glslc too old)
- After the 22.04→24.04 reinstall, llama.cpp Vulkan dropped from **40.2 → 27.2 tok/s** on the
  A770 (Qwen2.5-7B Q4_K_M), correctness unchanged (4/4 coding, 4/4 writing). Root-caused to
  the **build-time shader toolchain**, not the driver or kernel: Ubuntu 24.04's stock `shaderc`
  (2023.8) cannot compile `GL_EXT_integer_dot_product` (quantized-matmul accelerator) or
  bfloat16/coopmat2, so llama.cpp's Vulkan backend silently fell back to a slow path. Confirmed
  the GPU ran at full 2400 MHz with no throttle, and that both OS builds used the **same
  llama.cpp SHA `dde879b`** (the b1/b22 tags are only `git describe` counts). Fix: install
  LunarG **shaderc 2025.2** from the Vulkan SDK noble repo and rebuild → **41.9 tok/s** (above
  the old 40.2). `setup/llamacpp_vulkan.sh` now gates the build on a glslc capability probe and
  refuses to produce a slow binary. Full write-up:
  `reports/data/baseline-24.04-kernel6.8/vulkan_baseline.md`.

### Added
- `reports/data/baseline-24.04-kernel6.8/`: first on-hardware baseline after the 24.04
  reinstall (env capture + Vulkan baseline + root-cause). Also records a provisioning trap:
  a fresh user must be in the `render`/`video` groups or Vulkan silently uses llvmpipe (CPU).

### Added — LLM harness alpha cycle
- `llm/harness-alpha/`: a reproducible four-candidate comparison of local inference harnesses
  (llama.cpp Vulkan, llama.cpp SYCL, LM Studio, IPEX-LLM) for coding + creative-writing
  assistance on the A770. Shared Qwen2.5-7B model, fixed scored task set (coding executed
  against hidden tests; writing checked for measurable properties + saved verbatim), shared
  OpenAI-compatible driver. Downloads/runs are durable systemd user units with a compact
  `status.sh`.
- `llm/llm_hello.py` + `llm/run_hello.sh`: minimal "is IPEX-LLM working" smoke test
  (one Python hello-world coding task + one English writing paragraph).
- `reports/harness_alpha_comparison.md`: results, three-claims breakdown, writing-quality
  comparison, and recommendation (**llama.cpp Vulkan**, ~40 tok/s).
- `reports/sycl_fix_plan.md`: root-cause analysis + fix for the llama.cpp SYCL crash.

### Fixed
- IPEX-LLM installer: pin `ipex-llm==2.3.0b20251026` (a datestamp with a matching
  `bigdl-core-xe-all` wheel); add `LD_LIBRARY_PATH` + `HF_HUB_DISABLE_XET=1` to
  `xpu_runtime.env` so the XPU stack loads and downloads complete reliably.
- llama.cpp **SYCL segfault on A770** (NEO 24.39 + oneAPI 2026.2): isolated two bugs by gdb
  backtrace — a Level-Zero Sysman memory-query SEGV and a persistent-device-code-cache SEGV.
  Worked around with `-DGGML_SYCL_SUPPORT_LEVEL_ZERO_API=OFF -DGGML_SYCL_DNN=OFF` +
  `SYCL_CACHE_PERSISTENT=0`. SYCL now runs correctly (4/4 coding, 4/4 writing) though slower
  than Vulkan until oneDNN + the cache can be re-enabled.

### Finding
- GPU-use probe blind spot: the Vulkan/Mesa (ANV) driver does not expose per-process VRAM in
  `/proc/<pid>/fdinfo` (unlike the i915 compute/Level-Zero path). Vulkan GPU use is confirmed
  via tokens/sec vs a CPU baseline instead (`gpu_probe.sh` documents this).
- `.gitignore`: add `.venv-llm/`.

## [0.1.0] — 2026-10-31

First on-hardware release. Full A770 bring-up plus the memory-boundary study (H0/H1/H2)
and the full-16-GiB unlock, all verified on real hardware.

### Added — hardware bring-up
- Kernel 6.8.0-138 (HWE) so i915 binds the A770 (`56a0` alias); 5.15 kept as fallback.
  Operator script `scripts/bringup/b1_kernel_i915.sh`.
- OpenCL + Level Zero user-space from Intel's client-GPU repo (NEO 24.39).
  Operator script `scripts/bringup/b3_compute_userspace.sh`.
- GuC/HuC submission enabled via `i915.enable_guc=3`.
  Operator script `scripts/bringup/b5_enable_guc.sh`.
- PyTorch `2.6.0+xpu` installed into `.venv-xpu` and verified running real compute
  (`scripts/bringup/b5_baseline.py` → 16.8 TFLOPS fp32 matmul).

### Added — memory boundary study (see `reports/FINDINGS_memory_4gib.md`)
- `tests/opencl/large_buffer.cpp` — MEM-01…MEM-10 matrix. Confirms the 4 GiB cap is a
  policy (`CL_INVALID_BUFFER_SIZE`), the two-flag >4 GiB fix is correct, and the
  single-flag traps (reject / silent corruption).
- `tests/level-zero/l0_large_buffer.cpp` — same boundary + fix on Level Zero
  (`ZE_RESULT_ERROR_UNSUPPORTED_SIZE`; relaxed-limits descriptor lifts it).
- `benchmarks/addr_bench.cpp` + `benchmarks/workloads/addr_bench.cl` — H2 study:
  stateless addressing has no measurable penalty vs the default path (within 1%).

### Added — full 16 GiB for PyTorch
- `scripts/xpu_env.sh` — sets `NEOReadDebugKeys=1 AllowUnrestrictedSize=1` to lift the
  per-allocation cap driver-wide (no code change). Source, wrap, or print.
- `scripts/bringup/b7_torch_unrestricted.py` — single >4 GiB tensors correct 2…12 GiB.
- `scripts/bringup/b8_max_and_matmul.py` — largest correct single tensor **15.03 GiB**;
  matmul with a 4.17 GiB operand, correct vs CPU.
- `scripts/bringup/b9_training_stress.py` — wide-MLP training loop to 11–12 GiB peak.
- `scripts/bringup/b10_near_full_vram.py` — real training at **14.34 GiB peak (94.9%)**.

### Added — project tooling
- Pre-commit gate (`.pre-commit-config.yaml`): ruff (lint+format), bandit (security),
  detect-secrets, shellcheck, plus file-hygiene hooks. Config in `pyproject.toml`.
- `.gitignore` now excludes `.venv-xpu/` (9.2 GB), caches.

### Documentation
- `README.md` updated from scaffolding to on-hardware complete.
- `reports/FINDINGS_memory_4gib.md` — H0/H1/H2 findings with raw-artifact citations.
- `docs/USER_GUIDE.md`, `docs/TESTING_REPORT.md`, `CHANGELOG.md`, `VERSION`.

### Safety
- No firmware/BIOS changes. All privileged steps (kernel, driver packages, build tools,
  `libze-dev`) were operator-run, never automated. `AllowUnrestrictedSize` is Intel's
  debug key; documented as dev-only with the stable API path noted.

[0.1.0]: https://github.com/vampireLibrarianMonk/intel_arc_770/releases/tag/v0.1.0
