# Changelog

All notable changes to arc-a770-lab. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
