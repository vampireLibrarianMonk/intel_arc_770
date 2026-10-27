# Tech steering — arc-a770-lab

## Target platform

- **GPU:** Intel Arc A770, 16 GiB VRAM (Alchemist / Xe-HPG), PCI ID commonly `8086:56a0`.
- **OS:** Ubuntu Linux; preferred dedicated Ubuntu 24.04+ GPU test install. An Ubuntu 22.04 host
  may serve as a build host (CLI tooling only).
- **Kernel driver:** `i915` for baseline; record exact version. Do not replace initially.

## Engineering domains

OpenCL, oneAPI Level Zero, Intel Compute Runtime (NEO), Intel Graphics Compiler (IGC),
GPU memory management; application layer via PyTorch/XPU and SYCL.

## Languages & toolchain

- **C++17** for the OpenCL/Level Zero harness, built with **CMake** (>= 3.20).
- **Python 3.10+** for the PyTorch/XPU harness and the matrix runner.
- Independent **CPU oracles** for every correctness claim.

## Version policy (critical)

- Pin all source checkouts to specific **release tags and SHAs**.
- NEO's `manifests/manifest.yml` is the source of truth for matching **IGC** and **GmmLib** versions.
- Never mix random `master` HEADs between baseline and modified comparisons.
- Record the actually-loaded OpenCL ICD / Level Zero loader and vendor library paths — prove which
  driver a test used; a compiled runtime is not necessarily the one that loads.

## Key flags

| API | Allocation override | Stateless compile flag |
|:--|:--|:--|
| OpenCL | `CL_MEM_ALLOW_UNRESTRICTED_SIZE_INTEL` | `-cl-intel-greater-than-4GB-buffer-required` |
| Level Zero | `ze_relaxed_allocation_limits_exp_desc_t` + `ZE_RELAXED_ALLOCATION_LIMITS_EXP_FLAG_MAX_SIZE` | `-ze-opt-greater-than-4GB-buffer-required` |

## Host constraints / safety

- Keep experimental libraries in a **per-test prefix** or disposable VM/container with passed-through
  `/dev/dri`. A container does **not** replace kernel isolation.
- Firmware, kernel-module, BIOS, bootloader, driver-package, and system-library changes are
  **human-approval-required**.
- Use exact binary units: `GiB = 2^30 bytes`.
