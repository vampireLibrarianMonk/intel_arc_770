# Bring-up status — arc-a770-lab

Single source of truth for on-hardware bring-up. Update after every step.
Legend: ✅ done · 🔧 in progress · ⛔ blocked (needs operator) · ⬜ not started

**Host:** intelgpuserver · Ubuntu 22.04.5 · kernel 6.8.0-138-generic
**GPU:** Intel Arc A770 `8086:56a0` @ PCI `2d:00.0`
**Last updated:** 2026-10-31 by agent

---

## STATUS: ✅ BRING-UP COMPLETE — torch.xpu runs real compute on the A770

First baseline (`artifacts/baseline/pytorch_xpu.json`, 2026-10-31):
- torch **2.6.0+xpu**, device Intel Arc A770, 15.11 GiB
- matmul correctness err 0.0002 vs CPU
- 4096³ matmul 0.0082 s → **16.8 TFLOPS** (fp32)

---

## Environment facts (verified)

| Fact | Value | How checked |
|:--|:--|:--|
| GPU present | yes, `8086:56a0` | `lspci -nn` |
| Kernel driver bound | **i915** | `lspci -vnnk -s 2d:00.0` |
| i915 supports `56a0` | yes (kernel 6.8) | `modinfo i915` |
| `/dev/dri/renderD128` | present, rw | `ls /dev/dri` |
| GuC / HuC firmware | loaded, HuC authenticated | `dmesg \| grep -i guc/huc` |
| OpenCL (NEO) | 24.39.31294 | `clinfo` |
| Level Zero | libze1 1.17.44, libze-intel-gpu1 24.39 | `dpkg -l` |
| torch | 2.6.0+xpu, xpu_available=True | probe |

---

## Blockers — all cleared

### B1 — i915 that supports A770  ✅ DONE
Booted `6.8.0-138-generic` (HWE, from stock jammy-updates). i915 binds, `56a0` alias present.
5.15 kept as GRUB fallback. Script: `scripts/bringup/b1_kernel_i915.sh --route=A`.

### B2 — render node + permissions  ✅ DONE
`/dev/dri/renderD128` present, user in render/video. DG2 firmware already in `/lib/firmware/i915`.

### B3 — compute user-space (OpenCL / Level Zero)  ✅ DONE
Intel client repo: intel-opencl-icd 24.39, libze1 1.17.44, libze-intel-gpu1 24.39, clinfo.
**H0 confirmed:** 15.11 GiB total, 4.00 GiB max alloc. Script: `scripts/bringup/b3_compute_userspace.sh`.
(Install `libze-intel-gpu1` only; it supersedes `intel-level-zero-gpu`.)

### B4a — GuC firmware (compute submission)  ✅ DONE
A770 compute needs GuC-based submission. Added `i915.enable_guc=3` via GRUB, rebooted.
Necessary but NOT sufficient on its own. Script: `scripts/bringup/b5_enable_guc.sh`.

### B4b — torch version matched to driver  ✅ DONE — THE KEY FIX
**Root cause of the compute hang:** torch 2.14.1+xpu is built with oneAPI 2026.1
(`SYCL_COMPILER_VERSION=20260100`), but the system GPU compiler/driver is NEO **24.39** (Oct 2024).
The old IGC could not JIT torch 2.14's GEMM kernel — it **deadlocked** at kernel-build time
(enumeration + elementwise + copy all worked; only matmul hung, EXIT=124).
Fix: pin torch to the version built for NEO 24.39 → **torch 2.6.0+xpu / torchvision 0.21.0+xpu /
torchaudio 2.6.0+xpu** from `download.pytorch.org/whl/xpu`. matmul then ran in 0.28 s.
Env-var workarounds (immediate cmdlists, IGC flags, NEO cache) did NOT help — it was a version mismatch.
Reserved option if ever on newer torch: upgrade system NEO driver to a 2025+ build.

### B5 — baseline capture  ✅ DONE
`scripts/bringup/b5_baseline.py` → `artifacts/baseline/pytorch_xpu.json`.

---

## H0 — 4 GiB per-allocation boundary  ✅ CONFIRMED (torch.xpu)
`scripts/bringup/b6_alloc_boundary.py` → `artifacts/baseline/alloc_boundary.json` (2026-10-31).
Single-tensor float32 allocations on the A770 (15.11 GiB total):

| size | result |
|:--|:--|
| 256 MiB | ok, sentinels verified |
| 2.0 GiB | ok, sentinels verified |
| 3.8 GiB | ok (just under cap), sentinels verified |
| 4.2 GiB | REJECTED |
| 6.0 GiB | REJECTED |

Over ~4 GiB fails even with 15 GiB free and 0 bytes held by PyTorch → per-allocation
policy cap, not real OOM. Matches H0. Correctness (not just allocation) proven up to 3.8 GiB.

**Caveat:** torch raises `OutOfMemoryError`, which bundles policy-cap + true OOM. To prove it
is the policy cap and capture the real driver code (`CL_INVALID_BUFFER_SIZE -61`), the next step
is the C++ OpenCL/Level Zero harness in `tests/` (STRATEGY Phase 1), plus the relaxed-allocation
+ stateless-compile path (H1) for a correct single >4 GiB buffer.

## Phase 1 — OpenCL >4 GiB correctness harness  ✅ DONE (H0 + H1 proven)
Built `tests/opencl/large_buffer.cpp` (needs build-essential cmake opencl-headers
ocl-icd-opencl-dev). Ran on the A770 → `artifacts/baseline/opencl_boundary.json` (2026-10-31).
Driver reports `CL_DEVICE_MAX_MEM_ALLOC_SIZE = 4.00 GiB`, global 15.11 GiB.

| case | size | relaxed | stateless | result |
|:--|:--|:--|:--|:--|
| MEM-03 | 4.0 GiB | no | no | ok |
| MEM-04 | >4 GiB | no | no | **rejected: CL_INVALID_BUFFER_SIZE (-61)** |
| MEM-05 | 6 GiB | yes | yes | ok, values past 4 GiB correct |
| MEM-06 | 8 GiB | yes | yes | ok, values past 4 GiB correct |
| MEM-09 | 6 GiB | yes | no | **ALLOCATED_BUT_CORRUPT** (dev_mis=2 host_mis=5) |
| MEM-10 | 6 GiB | no | yes | rejected: CL_INVALID_BUFFER_SIZE (-61) |

- **H0 proven:** the >4 GiB rejection is a policy cap with exact code `CL_INVALID_BUFFER_SIZE (-61)`,
  not OOM. (torch's `OutOfMemoryError` hid this code; the C++ harness exposes it.)
- **H1 proven:** relaxed allocation (`CL_MEM_ALLOW_UNRESTRICTED_SIZE_INTEL`) + stateless compile
  (`-cl-intel-greater-than-4GB-buffer-required`) TOGETHER give a correct single 6/8 GiB buffer,
  verified past the 4 GiB offset by device-side check AND host read-back vs the SplitMix64 CPU oracle.
- **Silent-corruption case confirmed:** relaxed alloc WITHOUT the stateless flag (MEM-09) allocates
  but returns WRONG data above 4 GiB. Allocation success is not correctness. Both flags are required.

## Phase 2 — stateless vs stateful addressing cost  ✅ DONE (H2 refuted for this card)
Built `benchmarks/addr_bench.cpp` + `benchmarks/workloads/addr_bench.cl`. Kernel-time only
(clEvent profiling), warmup 5, 20 reps, median + p95. Same source/size/workload; only the build
flag + alloc mode differ. Artifacts: `artifacts/baseline/h2_addressing.json`,
`artifacts/baseline/h2_addressing_6gib.json` (2026-10-31).

**Matched size (3.5 GiB, both paths):**

| workload | stateful med | stateless med | penalty |
|:--|:--|:--|:--|
| W1 addr-gen | 7.79 ms | 7.85 ms | x1.01 |
| W2 stream | 16.48 ms | 16.37 ms | x0.99 |
| W3 random | 127.66 ms | 128.07 ms | x1.00 |

All within 1% = noise. **No measurable stateless penalty** on this A770 + NEO 24.39.
This REFUTES STRATEGY H2 (which expected a measurable stateless cost) for this hardware/driver.

**Scaling (stateless only, 3.5 → 6 GiB):** W1 x1.72, W2 x1.72 (linear with the x1.71 data growth,
no cliff crossing 4 GiB). W3 random x6.9 — a cache/working-set effect of size + scatter pattern,
NOT addressing overhead; it would hit any path.

## ★ GOAL MET — full 16 GiB usable in torch.xpu via NEO debug key
`scripts/bringup/b7_torch_unrestricted.py` → `artifacts/baseline/torch_unrestricted.json` (2026-10-31).
Setting BOTH env vars before launching torch unlocks single >4 GiB tensors:
```
export NEOReadDebugKeys=1
export AllowUnrestrictedSize=1
```
Single-tensor correctness (sentinels verified across the 4 GiB offset + full-tensor kernel):

| size | result |
|:--|:--|
| 2 / 3.8 / 4.2 / 6 / 8 / 10 / 12 GiB | ALL correct |

Without the key, >4 GiB fails with torch OutOfMemoryError. `AllowUnrestrictedSize=1` alone does
nothing — `NEOReadDebugKeys=1` is required to make NEO read the key. Source: NEO large-allocation
guide (programmers-guide/ALLOCATIONS_GREATER_THAN_4GB.md).
**Caveat:** this is Intel's DEBUG key (dev/debug only, may be deprecated). The stable path is the
real API flags (relaxed alloc + stateless build, proven in Phase 1); torch.xpu does not expose
those, so the env key is the no-code route to the full 16 GiB on this host.

## Levers to break the 4 GiB per-allocation cap (from NEO guide)
| lever | layer | effect |
|:--|:--|:--|
| `CL_MEM_ALLOW_UNRESTRICTED_SIZE_INTEL` | OpenCL alloc | allow >4 GiB buffer |
| `-cl-intel-greater-than-4GB-buffer-required` | OpenCL build | stateless kernel (correctness) |
| `ZE_RELAXED_ALLOCATION_LIMITS_EXP_FLAG_MAX_SIZE` | L0 alloc | allow >4 GiB buffer |
| `-ze-opt-greater-than-4GB-buffer-required` | L0 build | stateless kernel |
| `NEOReadDebugKeys=1 AllowUnrestrictedSize=1` | env (driver-wide) | >4 GiB with NO code change (debug key) |
| `clSVMAlloc` / `clDeviceMemAllocINTEL` + flag | OpenCL SVM/USM | >4 GiB SVM/USM alloc |

## Phase 5 — Level Zero confirms the same boundary + fix  ✅ DONE
`tests/level-zero/l0_large_buffer.cpp` (needs libze-dev). `maxMemAllocSize = 4.00 GiB`.

| case | relaxed | result |
|:--|:--|:--|
| 2 GiB | no | allocated |
| 6 GiB | no | refused (0x78000009 = ZE_RESULT_ERROR_UNSUPPORTED_SIZE) |
| 6 GiB | yes | allocated, sentinels past 4 GiB correct |
| 8 GiB | yes | allocated |

`ze_relaxed_allocation_limits_exp_desc_t` + `ZE_RELAXED_ALLOCATION_LIMITS_EXP_FLAG_MAX_SIZE`
lifts the cap, same as OpenCL. Correctness verified across the 4 GiB offset via copy round-trip.

## torch.xpu full-VRAM helper + training stress  ✅ DONE
- `scripts/xpu_env.sh` — sets `NEOReadDebugKeys=1 AllowUnrestrictedSize=1` (source / wrap a
  command / print). The no-code route to >4 GiB tensors.
- `scripts/bringup/b9_training_stress.py` → `artifacts/baseline/training_stress.json`: a real
  train loop (fwd+bwd+Adam) at **11.34 GiB peak (75% of card)**, loss 1.00→0.99 over 12 steps,
  no hang/crash. Proves the unlock holds under a genuine workload, not just a lone allocation.
  Config tunable via env (HID/LAYERS/BATCH/IN/OUT/STEPS).

## Next: STRATEGY Phase 3/5 — options
- Phase 5: confirm the same 4 GiB boundary + relaxed path via Level Zero (`tests/level-zero/`).
- Write a findings report (`reports/`) consolidating H0/H1/H2 with the artifact JSONs.
- Phase 3: a diagnostics helper that warns when relaxed-alloc is used WITHOUT the stateless flag
  (the MEM-09 silent-corruption trap). No driver/kernel/firmware changes without approval (AGENTS.md).
