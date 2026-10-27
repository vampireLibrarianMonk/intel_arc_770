# Addressing Performance Study — Requirements

Backlog: ARC-005. Phase 2. Enter only after Phase 1 has a stable baseline.

## Requirements (EARS)

### R1 — Equivalent A/B comparison
- THE SYSTEM SHALL compare stateful/small-buffer, stateless/large-buffer, and application-segmented
  implementations on equivalent data layout and computation.
- IF algorithms are not equivalent across variants, THEN THE SYSTEM SHALL flag the case.

### R2 — Workload classes
- THE SYSTEM SHALL cover: address-generation-heavy, bandwidth-bound streaming, random-access,
  compute-heavy, and segmented-buffer kernels.

### R3 — Measurement protocol
- THE SYSTEM SHALL warm up, then run >= 10 (prefer 20) measured repetitions per case.
- THE SYSTEM SHALL randomize/alternate A/B order.
- THE SYSTEM SHALL report median, p95, dispersion, and raw samples.
- THE SYSTEM SHALL separate host<->device transfer time from kernel time.

### R4 — Context capture
- THE SYSTEM SHALL pin and record workload dims, flags, commits, OS/kernel, firmware, thermals.
- THE SYSTEM SHALL record compile time, buffer-creation latency, VRAM pressure, hang/reset counts.

### R5 — Integrity
- THE SYSTEM SHALL NOT present a single run as a speedup.
- THE SYSTEM SHALL NOT report estimated numbers as measurements.

## Gate
At least one statistically credible bottleneck with an actionable hypothesis, or a documented
negative result.
