# Arc A770 — 4 GiB per-allocation boundary: findings (H0 / H1 / H2)

**Date:** 2026-10-31
**Host:** intelgpuserver · Ubuntu 22.04.5 · kernel 6.8.0-138-generic
**GPU:** Intel Arc A770 `8086:56a0` @ PCI `2d:00.0` · 15.11 GiB VRAM
**Stack:** i915 (GuC+HuC on) · NEO / IGC `24.39.31294` · Level Zero `libze1 1.17.44` ·
PyTorch `2.6.0+xpu`
**Method:** every result is from a run on this card. Sentinel values are written and read
back across the 2^32-byte (4 GiB) offset and checked against an independent CPU oracle;
allocation success is never treated as proof of correctness. Raw JSON in `artifacts/baseline/`.

---

## TL;DR

- The A770 caps a **single** allocation at **4.00 GiB** (`CL_DEVICE_MAX_MEM_ALLOC_SIZE`).
  This is a driver **policy**, not the card running out of memory. Total VRAM is 15.11 GiB.
- The cap is removable, correctly, by using **both** a relaxed-allocation flag **and** a
  stateless-compile flag. Either one alone is wrong: alloc-flag-only silently corrupts data
  past 4 GiB; compile-flag-only is still rejected.
- The stateless path has **no measurable speed penalty** vs the default at matched size.
- For PyTorch (which exposes no such flags), the NEO debug key
  `NEOReadDebugKeys=1 AllowUnrestrictedSize=1` unlocks the cap with no code change. A single
  **15.03 GiB** tensor and a matmul with a **4.17 GiB** operand both run correctly.

---

## H0 — the 4 GiB cap is a policy, not OOM  ✅ confirmed

`CL_DEVICE_MAX_MEM_ALLOC_SIZE = 4.00 GiB`, `CL_DEVICE_GLOBAL_MEM_SIZE = 15.11 GiB`.

OpenCL harness (`tests/opencl/large_buffer.cpp` → `artifacts/baseline/opencl_boundary.json`):

| case | size | relaxed | stateless | result |
|:--|:--|:--|:--|:--|
| MEM-01 | 0.25 GiB | no | no | ok |
| MEM-02 | 2.0 GiB | no | no | ok |
| MEM-03 | 3.999 GiB | no | no | ok |
| MEM-04 | 4.001 GiB | no | no | **rejected — `CL_INVALID_BUFFER_SIZE` (-61)** |

The rejection code is `CL_INVALID_BUFFER_SIZE`, a size-policy refusal, returned with the
whole card free. torch.xpu reports the same wall as a generic `OutOfMemoryError`
(`artifacts/baseline/alloc_boundary.json`): 4.2 GiB and 6 GiB rejected while "0 bytes
allocated by PyTorch". Same policy, less informative message.

## H1 — the supported >4 GiB path works, and needs BOTH flags  ✅ confirmed

| case | size | relaxed alloc | stateless build | result |
|:--|:--|:--|:--|:--|
| MEM-05 | 6 GiB | yes | yes | **ok — values past 4 GiB correct** |
| MEM-06 | 8 GiB | yes | yes | **ok — values past 4 GiB correct** |
| MEM-09 | 6 GiB | yes | **no** | **ALLOCATED_BUT_CORRUPT** (2 device + 5 host mismatches) |
| MEM-10 | 6 GiB | **no** | yes | rejected — `CL_INVALID_BUFFER_SIZE` (-61) |

- Correct path: `CL_MEM_ALLOW_UNRESTRICTED_SIZE_INTEL` on the buffer **and**
  `-cl-intel-greater-than-4GB-buffer-required` on `clBuildProgram`.
- **The trap (MEM-09):** relaxed allocation **without** the stateless flag allocates fine but
  returns wrong data above the 4 GiB offset — no error raised. This is why allocation success
  must never be trusted as correctness.
- Both pieces are mandatory: the stateless flag alone (MEM-10) is still rejected.

### Level Zero — same boundary, same fix  ✅ confirmed
`tests/level-zero/l0_large_buffer.cpp` (needs `libze-dev`). `zeDeviceGetProperties`
reports `maxMemAllocSize = 4.00 GiB`, matching OpenCL.

| case | relaxed | result |
|:--|:--|:--|
| 2 GiB | no | allocated |
| 6 GiB | no | **refused — `ZE_RESULT_ERROR_UNSUPPORTED_SIZE` (0x78000009)** |
| 6 GiB | yes | **allocated — values past 4 GiB correct** |
| 8 GiB | yes | allocated |

The relaxed path is `ze_relaxed_allocation_limits_exp_desc_t` with
`ZE_RELAXED_ALLOCATION_LIMITS_EXP_FLAG_MAX_SIZE` passed via `pNext`, plus
`-ze-opt-greater-than-4GB-buffer-required` for stateless modules. Allocation correctness
verified across the 4 GiB offset by host↔device copy round-trip. So the cap and its fix hold
identically on both Intel compute APIs.

## H2 — stateless addressing has no measurable penalty  ✅ measured (refutes the hypothesis)

`benchmarks/addr_bench.cpp`, kernel-time only (clEvent), warmup 5, 20 reps, median + p95.
Matched buffer size 3.5 GiB so both paths run the identical workload
(`artifacts/baseline/h2_addressing.json`):

| workload | stateful med | stateless med | penalty |
|:--|:--|:--|:--|
| W1 address-gen | 7.79 ms | 7.85 ms | ×1.01 |
| W2 streaming | 16.47 ms | 16.37 ms | ×0.99 |
| W3 random | 127.66 ms | 128.07 ms | ×1.00 |

All within 1% — noise. The strategy's H2 expected a real stateless cost (register pressure /
spills on Alchemist); on this card + NEO 24.39 **there is none**.

Scaling the stateless path 3.5 → 6 GiB (`h2_addressing_6gib.json`): W1 ×1.72, W2 ×1.72 —
linear with the ×1.71 data growth, no cliff crossing 4 GiB. W3 random jumps ×6.9: a
cache / working-set effect of size and scatter, not the addressing mode (it would hit any path).

---

## Using the full 16 GiB

### In C++ (OpenCL / Level Zero) — stable, supported
Use the flag pair from H1. This is the production route; it is in Intel's programmer's guide
and is not a debug switch.

### In PyTorch (torch.xpu) — no code change
torch.xpu exposes neither flag, so it is stuck at 4 GiB per tensor by default. The NEO debug
key removes the cap driver-wide. Set **both** env vars before launching
(`artifacts/baseline/torch_unrestricted.json`, `max_and_matmul.json`):

```bash
export NEOReadDebugKeys=1
export AllowUnrestrictedSize=1
```

Verified under the key on this card:

| test | result |
|:--|:--|
| single tensor 2 / 3.8 / 4.2 / 6 / 8 / 10 / 12 GiB | all correct (sentinels past 4 GiB) |
| **largest correct single tensor** | **15.03 GiB** (card total 15.11) |
| matmul, 4.17 GiB operand (40000×28000 @ 28000×64) | 0.018 s, correct vs CPU (max err 0.003) |
| **near-full-card training** (`b10_near_full_vram.py`) | **14.34 GiB peak (94.9% of card)**, real fwd+bwd+Adam loop, loss 1.05→0.79, 6 GiB tensor inside verified past 4 GiB |

Training stress at lower footprints (`b9_training_stress.py`): a wide-MLP train loop reaches
11.3–12.2 GiB peak with loss decreasing and no hang — confirming the unlock holds under a real
workload, not just a static allocation.

`AllowUnrestrictedSize=1` alone does nothing — `NEOReadDebugKeys=1` is required to read it.

**Caveat:** Intel documents `AllowUnrestrictedSize` as a **debug key for driver development**;
it is not part of any spec and may change or be deprecated. Fine for experiments and local
large-tensor work on this box; a shipping product should use the real API flags (which means
C++/SYCL, not plain torch.xpu).

---

## Reproduce

```bash
# OpenCL boundary + H1 (needs build-essential cmake opencl-headers ocl-icd-opencl-dev)
cd tests/opencl && cmake -S . -B build && cmake --build build
./build/large_buffer --kernel kernels/sentinel.cl --json ../../artifacts/baseline/opencl_boundary.json

# H2 addressing benchmark
cd ../../benchmarks && cmake -S . -B build && cmake --build build
./build/addr_bench --size-gib 3.5 --reps 20 --kernel workloads/addr_bench.cl \
  --json ../artifacts/baseline/h2_addressing.json

# torch.xpu full-card unlock
NEOReadDebugKeys=1 AllowUnrestrictedSize=1 \
  ./.venv-xpu/bin/python scripts/bringup/b8_max_and_matmul.py
```

## Artifacts
`artifacts/baseline/`: `opencl_boundary.json`, `alloc_boundary.json`, `h2_addressing.json`,
`h2_addressing_6gib.json`, `torch_unrestricted.json`, `max_and_matmul.json`, `pytorch_xpu.json`,
`training_stress.json`, `near_full_vram.json`. L0 probe: `tests/level-zero/l0_large_buffer.cpp`.

No driver, kernel, or firmware was modified for any result above. The only privileged steps on
this host were operator-run package installs (kernel 6.8, Intel compute runtime, build tools).
