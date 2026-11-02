# Changelog

All notable changes to arc-a770-lab. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
