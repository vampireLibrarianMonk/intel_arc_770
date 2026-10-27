# arc-a770-lab

Agentic driver diagnostics & optimization lab for the **Intel Arc A770 16 GiB** (Alchemist / Xe-HPG, PCI ID commonly `8086:56a0`).

> **Charter:** Build a reproducible, agent-assisted laboratory to diagnose Intel Arc A770 compute-driver
> limitations; separate hardware limits, API defaults, application behavior, compiler code generation, and
> fixable runtime defects; design, implement, benchmark, and validate narrowly scoped changes. The focus is
> the historical 4 GiB **per-allocation** behavior, **not** a supposed 4 GiB total-VRAM limit.

## Start here

1. Read [`docs/STRATEGY.md`](docs/STRATEGY.md) — the full project strategy.
2. Read [`AGENTS.md`](AGENTS.md) — always-on guardrails for every agent and contributor.
3. Read the steering files in [`.kiro/steering/`](.kiro/steering/).

## Current status

Scaffolding stage. **No A770 hardware attached to the current host**, so this repo currently contains only
hardware-independent work: structure, steering, specs, harness source, CPU oracles, scripts, and templates.
Nothing here installs drivers, touches firmware, or modifies the kernel.

## Layout

| Path | Purpose |
|:--|:--|
| `.kiro/steering/` | Durable project policy (product, tech, structure) |
| `.kiro/specs/` | Phase specs: requirements, design, tasks |
| `docs/` | Strategy, repo map, experiment template, ADRs |
| `tests/opencl/` | C++17 OpenCL correctness harness |
| `tests/level-zero/` | Follow-on Level Zero tests |
| `tests/pytorch/` | PyTorch / XPU application-level harness |
| `tests/oracles/` | Independent CPU reference implementations |
| `benchmarks/` | Fixed workloads + reproducible parameter manifests |
| `scripts/` | Read-only baseline capture, prerequisite checks, opt-in source setup, matrix runner |
| `src/` | Harness helpers and optional policy experiments |
| `patches/` | Small reviewable diffs (never modify vendor by default) |
| `vendor/` | Upstream clones (git-ignored) |
| `artifacts/` | Bulky logs and raw outputs (git-ignored) |
| `reports/` | Reviewed results and plots |

## Safety

See `AGENTS.md`. Firmware, kernel-module, BIOS, bootloader, driver-package, and system-library changes are
**human-approval-required** and are never performed automatically.
