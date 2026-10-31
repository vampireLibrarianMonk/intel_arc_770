# Testing Report — arc-a770-lab v0.1.0

**Date:** 2026-10-31
**Host:** intelgpuserver · Ubuntu 22.04.5 · kernel 6.8.0-138-generic
**GPU:** Intel Arc A770 `8086:56a0` · 15.11 GiB VRAM
**Stack:** NEO/IGC 24.39.31294 · Level Zero 1.17.44 · PyTorch 2.6.0+xpu
**Method:** every number below is from a run on this card. Correctness is checked by writing
sentinel values across the 2³²-byte (4 GiB) offset and comparing to an independent CPU oracle;
allocation success alone is never counted as a pass. Raw data in `artifacts/baseline/`.

---

## Summary

| suite | result |
|:--|:--|
| CPU oracle self-check (offline) | PASS |
| OpenCL boundary matrix (MEM-01…MEM-10) | PASS — boundary + fix + traps all as expected |
| Level Zero boundary + fix | PASS — same as OpenCL |
| H2 stateless-vs-stateful benchmark | PASS — no penalty (within 1%) |
| PyTorch correctness (2…12 GiB single tensor) | PASS — all correct past 4 GiB |
| PyTorch max single tensor | 15.03 GiB (99.5% of card) |
| PyTorch near-full-card training | 14.34 GiB peak, loss falling, no crash |
| Pre-commit gate (ruff/bandit/detect-secrets/shellcheck) | PASS |

---

## 1. Correctness — the 4 GiB boundary

### OpenCL (`tests/opencl/large_buffer.cpp` → `opencl_boundary.json`)
`CL_DEVICE_MAX_MEM_ALLOC_SIZE = 4.00 GiB`, global 15.11 GiB.

| case | size | relaxed | stateless | result |
|:--|:--|:--|:--|:--|
| MEM-01 | 0.25 GiB | no | no | ok |
| MEM-02 | 2 GiB | no | no | ok |
| MEM-03 | 3.999 GiB | no | no | ok |
| MEM-04 | 4.001 GiB | no | no | rejected `CL_INVALID_BUFFER_SIZE` (-61) |
| MEM-05 | 6 GiB | yes | yes | ok, correct past 4 GiB |
| MEM-06 | 8 GiB | yes | yes | ok, correct past 4 GiB |
| MEM-09 | 6 GiB | yes | no | ALLOCATED_BUT_CORRUPT (2 device + 5 host mismatches) |
| MEM-10 | 6 GiB | no | yes | rejected `CL_INVALID_BUFFER_SIZE` (-61) |

### Level Zero (`tests/level-zero/l0_large_buffer.cpp`)
`maxMemAllocSize = 4.00 GiB`. 2 GiB default ok; 6 GiB default refused with
`ZE_RESULT_ERROR_UNSUPPORTED_SIZE` (0x78000009); 6 and 8 GiB with the relaxed-limits
descriptor allocate and verify correct across the 4 GiB offset.

**Verdict:** H0 and H1 confirmed on both APIs. The two single-flag traps reproduce exactly.

## 2. Performance — stateless addressing cost (H2)

`benchmarks/addr_bench.cpp`, kernel-time only (clEvent), warmup 5, 20 reps, median.
Matched 3.5 GiB buffer (`h2_addressing.json`):

| workload | stateful | stateless | ratio |
|:--|:--|:--|:--|
| W1 address-gen | 7.79 ms | 7.85 ms | 1.01 |
| W2 streaming | 16.47 ms | 16.37 ms | 0.99 |
| W3 random | 127.66 ms | 128.07 ms | 1.00 |

**Verdict:** no measurable penalty. Refutes the original H2 hypothesis for this card + driver.

## 3. PyTorch — full-card use

| test | script | result |
|:--|:--|:--|
| fp32 4096³ matmul baseline | `b5_baseline.py` | 16.8 TFLOPS |
| single tensor 2…12 GiB | `b7_torch_unrestricted.py` | all correct past 4 GiB |
| largest single tensor | `b8_max_and_matmul.py` | **15.03 GiB** |
| matmul, 4.17 GiB operand | `b8_max_and_matmul.py` | correct vs CPU, 8120 GFLOPS |
| near-full training | `b10_near_full_vram.py` | **14.34 GiB peak (94.9%)**, loss 1.05→0.79, 6 GiB tensor verified inside |

All PyTorch >4 GiB results require `NEOReadDebugKeys=1 AllowUnrestrictedSize=1`.

## 4. Static checks (pre-commit)

ruff (lint+format), bandit (security), detect-secrets, shellcheck (error severity), file
hygiene — all pass on `--all-files`. Config: `.pre-commit-config.yaml`, `pyproject.toml`.

---

## Known limitations

- `AllowUnrestrictedSize` is Intel's **debug key** (dev-only, may be deprecated). The stable
  path is the OpenCL/Level Zero API flags, which plain torch.xpu does not expose.
- The near-15 GiB ceiling leaves little headroom; real jobs should target ≤ ~14 GiB.
- H2 random-access slows at larger sizes — a cache/working-set effect, not the addressing mode.
- Single-host, single-card, single-driver (NEO 24.39). Numbers may shift on other stacks.

## Reproduce
See [`docs/USER_GUIDE.md`](USER_GUIDE.md) § Reproduce, or run each `scripts/bringup/b*.py`
under `scripts/xpu_env.sh`. Offline oracle needs no GPU:
`g++ -std=c++17 tests/opencl/oracle_selfcheck.cpp -o /tmp/o && /tmp/o`.
