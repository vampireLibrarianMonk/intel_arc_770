# ADR-0001: Start runtime-first, defer compiler modifications

- **Status:** Accepted
- **Date:** 2026-10-27

## Context

The Arc A770 exhibits a historical ~4 GiB per-allocation limit tied to Intel's stateful addressing
model. Multiple layers could be implicated: application code, the OpenCL/Level Zero API defaults,
the Intel Compute Runtime (NEO), the Intel Graphics Compiler (IGC), the `i915` kernel driver, or the
hardware itself. Intel engineers (May 2025) attributed the stateful default on Alchemist to
workload-specific overhead from stateless 64-bit messages (register pressure, spills, more complex
address calculation) — i.e. partly a hardware trade-off, not purely a software defect.

## Decision

Begin with the **Intel Compute Runtime plus a standalone C++ OpenCL/Level Zero diagnostic harness**,
using the **stock installed driver as a control**. Introduce IGC source modifications only after
Phase 2 evidence implicates generated machine code or compiler optimization. Do **not** begin by
replacing the kernel or modifying Mesa — those target different parts of the stack and are not the
first place to look for this OpenCL allocation behavior.

## Consequences

- First deliverables are evidence (baseline inventory, reproducer) rather than code changes.
- The compiler toolchain (large, expensive) is read early but built only after a stable baseline.
- Comparisons require pinned NEO/IGC/GmmLib versions from `manifests/manifest.yml`.
- Removing a hardware addressing-mode limitation purely in software is explicitly **not** a goal; the
  likely wins are memory-strategy selection, diagnostics, buffer layout, and error handling.

## Alternatives considered

- **Kernel/`i915` first** — rejected: no kernel-level evidence yet; high risk.
- **Compiler first** — rejected: premature without a profiled bottleneck.
- **Mesa** — rejected: wrong stack component for a compute allocation issue.
