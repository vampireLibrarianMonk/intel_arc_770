# PyTorch / XPU Application Harness — Tasks

- [ ] 1. `tests/pytorch/requirements.txt` with pinned torch + XPU backend (R1).
- [ ] 2. `xpu_large_tensor.py`: device select, capability report, graceful skip (R1).
- [ ] 3. Sentinel-over-4GiB tensor test vs CPU reference (R2).
- [ ] 4. Aggregate multi-tensor >4 GiB test (R3).
- [ ] 5. Application op (large matmul / elementwise) + `allclose` validation (R4).
- [ ] 6. Timing + peak-VRAM capture; JSON/JUnit output (R5).
- [ ] 7. `conftest.py` skip logic; verify suite is green offline (no XPU) (R6).
- [ ] 8. Prerequisite scripts: `scripts/check_prereqs.sh` + `scripts/check_pytorch_xpu.py` (offline-green).
- [ ] 9. **[on-hardware]** Run on the A770; validate numerics; capture measurements (R2–R5).
- [ ] 10. **[on-hardware]** Cross-check findings against the C++ OpenCL harness — Phase 5 gate.

## Performance investigation (see docs/PYTORCH_PERF_DUE_DILIGENCE.md)

- [ ] P1. **[on-hardware]** Tier 0 baseline: lock stack, stock throughput, GPU utilization (PT-000..003).
- [ ] P2. Build a reusable A/B micro-benchmark driver (matmul/conv/elementwise) with warm-up,
      20 reps, A/B randomization, split transfer/compute timers, CPU-oracle validation.
- [ ] P3. **[on-hardware]** Tier 1 levers: dtype/autocast, channels-last, torch.compile,
      CPU-fallback detection, transfer overhead (PT-010..017) — one variable per run.
- [ ] P4. **[on-hardware]** Tier 2: large-tensor >4 GiB perf vs chunked equivalent (PT-020..023).
- [ ] P5. **[on-hardware]** Tier 3 profiling: attribute the bottleneck before any driver work (PT-030..034).
- [ ] P6. **[on-hardware]** Tier 4 only if profiling implicates runtime/compiler (PT-040..042); human-approved.

> Tasks 1–8 and P2 are offline-completable. All **[on-hardware]** tasks are blocked until an A770 is attached.
