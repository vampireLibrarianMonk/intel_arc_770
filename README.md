# arc-a770-lab

A reproducible, agent-assisted laboratory for diagnosing and optimizing **Intel Arc A770
16 GiB** (Alchemist / Xe-HPG, PCI ID commonly `8086:56a0`) compute-driver behavior across
OpenCL, oneAPI Level Zero, and PyTorch/XPU.

The lab focuses on the historical **4 GiB per-allocation** limit — *not* a supposed 4 GiB
total-VRAM limit — and is built to cleanly separate five distinct causes of GPU problems:
hardware limits, API defaults, application behavior, compiler code generation, and fixable
runtime defects.

> **Charter:** Build a reproducible, agent-assisted laboratory to diagnose Intel Arc A770
> compute-driver limitations; separate hardware limits, API defaults, application behavior,
> compiler code generation, and fixable runtime defects; design, implement, benchmark, and
> validate narrowly scoped changes.

## Principles

Correctness → repeatability → performance, in that order. Three claims are **never
conflated**: *allocation capability improved*, *the application handles the workload*, and
*throughput improved*. A created allocation is never sufficient proof — values above the
4 GiB offset are verified against an independent CPU oracle. Firmware, kernel-module, BIOS,
bootloader, and driver-package changes are human-approval-required and never automated.

## What's inside

- **OpenCL C++17 harness** (`tests/opencl/`) — explicit A770 selection, a MEM-01…MEM-10
  allocation matrix, and sentinels that verify correct data *across the 4 GiB byte offset*
  (2³²), checked against a CPU oracle. Includes negative controls for the single-flag traps.
- **PyTorch / XPU harness** (`tests/pytorch/`) — large-tensor (>4 GiB) sentinel tests, an
  A/B micro-benchmark driver with warm-up / repeated runs / split transfer-vs-compute timing,
  and a tiered performance due-diligence plan (`docs/PYTORCH_PERF_DUE_DILIGENCE.md`).
- **Level Zero** (`tests/level-zero/`) — follow-on test slot.
- **Read-only discovery & readiness checks** (`scripts/`) — baseline capture plus
  system-level (`check_prereqs.sh`) and framework-level (`check_pytorch_xpu.py`) probes.
  Nothing privileged runs automatically.
- **Offline "freeze" toolkit** (`scripts/freeze/`) — capture a known-good run as a
  timestamped, checksum-verified snapshot in three formats for reinstall and reproduction
  years later with no network: A1 pip-wheel + `.deb` bundle, A2 container image, A3 full
  VM/disk image. Gated by a manual confirmation and a `--dry-run` rehearsal mode.
- **Kiro steering + phase specs** (`.kiro/`) — requirements/design/tasks per phase, plus
  ADRs documenting key decisions (runtime-first, compiler-later).

## Start here

1. Read [`docs/STRATEGY.md`](docs/STRATEGY.md) — the full project strategy.
2. Read [`AGENTS.md`](AGENTS.md) — always-on guardrails for every agent and contributor.
3. Read the steering files in [`.kiro/steering/`](.kiro/steering/).

## Quick start

```bash
# Read-only system + framework readiness checks (safe on any host):
scripts/check_prereqs.sh
scripts/check_pytorch_xpu.py

# Capture a read-only environment baseline:
scripts/capture_baseline.sh

# Offline CPU-oracle unit check (no GPU required):
g++ -std=c++17 tests/opencl/oracle_selfcheck.cpp -o /tmp/oracle && /tmp/oracle

# PyTorch harness offline tests (XPU tests skip cleanly without hardware):
cd tests/pytorch && python3 -m pytest -q
```

## Current status

**Scaffolding stage.** No A770 hardware is attached to the development host, so this repo
currently contains hardware-independent work only: structure, steering, specs, harness
source that compiles/passes offline, CPU oracles, read-only scripts, the freeze toolkit, and
templates. On-hardware tasks (allocation/boundary tests, benchmarks, driver-load
verification) are explicitly gated until an A770 is attached. Nothing here installs drivers,
touches firmware, or modifies the kernel.

## Layout

| Path | Purpose |
|:--|:--|
| `.kiro/steering/` | Durable project policy (product, tech, structure) |
| `.kiro/specs/` | Phase specs: requirements, design, tasks |
| `docs/` | Strategy, repo map, experiment template, ADRs, PyTorch perf plan |
| `tests/opencl/` | C++17 OpenCL correctness harness + kernels |
| `tests/level-zero/` | Follow-on Level Zero tests |
| `tests/pytorch/` | PyTorch / XPU harness + A/B benchmark driver |
| `tests/oracles/` | Independent CPU reference implementations |
| `benchmarks/` | Fixed workloads + reproducible parameter manifests |
| `scripts/` | Read-only baseline capture, prerequisite checks, opt-in source setup, matrix runner |
| `scripts/freeze/` | Offline time-capsule toolkit (A1 bundle / A2 container / A3 image) |
| `src/` | Harness helpers and optional policy experiments |
| `patches/` | Small reviewable diffs (never modify vendor by default) |
| `vendor/` | Upstream clones (git-ignored) |
| `artifacts/` | Bulky logs and raw outputs (git-ignored) |
| `reports/` | Reviewed results and plots |

## Safety

See [`AGENTS.md`](AGENTS.md). Firmware, kernel-module, BIOS, bootloader, driver-package, and
system-library changes are **human-approval-required** and are never performed automatically.
Experimental libraries live in per-test prefixes or disposable containers/VMs; stock drivers
are never overwritten.
