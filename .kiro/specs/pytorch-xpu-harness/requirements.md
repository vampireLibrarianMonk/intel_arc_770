# PyTorch / XPU Application Harness — Requirements

Backlog: ARC-012. Phase 5 (application transfer). Validates the three claims at the framework level.

## Context
PyTorch targets Intel GPUs via the **XPU** backend (`torch.xpu`), built on oneAPI / Level Zero /
SYCL. This harness checks whether the >4 GiB behavior and any runtime changes transfer to a real
framework workload — not just the low-level C++ harness.

## Requirements (EARS)

### R1 — Device selection & capability report
- THE SYSTEM SHALL verify `torch.xpu.is_available()` and select the A770 explicitly by index/name.
- IF XPU is unavailable, THEN THE SYSTEM SHALL skip (not fail) with a clear, recorded reason.
- THE SYSTEM SHALL record torch version, IPEX/backend version, and device properties.

### R2 — Large-tensor boundary test
- THE SYSTEM SHALL allocate a single tensor whose byte size crosses `2^32` (e.g. > 4 GiB) and
  write/read **distinct sentinel values on both sides of the 4 GiB offset**.
- THE SYSTEM SHALL compare against a CPU reference tensor (same seed), not allocation success alone.

### R3 — Aggregate multi-tensor test
- THE SYSTEM SHALL demonstrate >4 GiB aggregate VRAM via multiple tensors and verify each.

### R4 — Application workload
- THE SYSTEM SHALL run at least one realistic op (large matmul or elementwise over a >4 GiB tensor)
  and validate numerics against a CPU oracle within a stated tolerance.

### R5 — Measurement
- THE SYSTEM SHALL separate H2D/D2H transfer from compute; warm up; >= 10 reps; report median/p95.
- THE SYSTEM SHALL record peak VRAM via `torch.xpu.max_memory_allocated()` where available.

### R6 — Integrity & safety
- THE SYSTEM SHALL distinguish the three claims (allocation / correctness / throughput).
- THE SYSTEM SHALL stop on hang/reset and record raw outputs; never invent measurements.

## Gate
Framework-level behavior reproduced with independent numeric validation; no unsupported universal
performance claim.
