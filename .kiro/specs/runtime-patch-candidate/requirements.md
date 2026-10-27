# Runtime Patch Candidate — Requirements

Backlog: ARC-007, ARC-008. Phase 3. Lowest-risk changes first. No IGC changes here.

## Requirements (EARS)

### R1 — Evidence precondition
- THE SYSTEM SHALL NOT propose a runtime patch without a failing/ambiguous reproducer from Phase 1/2.

### R2 — Diagnostics-first candidates
- THE SYSTEM SHALL prefer: better diagnostics when allocation flags and kernel build flags are
  inconsistent; a capability-query/adaptive selection helper; clearer policy-vs-exhaustion errors.

### R3 — Isolated builds
- THE SYSTEM SHALL build NEO in a local prefix with pinned NEO/IGC/GmmLib versions.
- THE SYSTEM SHALL prove which driver a test actually loaded (ICD/loader path).
- THE SYSTEM SHALL apply one patch at a time.

### R4 — Correctness preservation
- THE SYSTEM SHALL pass all Phase 1 correctness tests with the patch.
- THE SYSTEM SHALL add a regression test for any demonstrated bug.
- THE SYSTEM SHALL produce identical validated outputs (correctness unchanged).

### R5 — Safety
- THE SYSTEM SHALL NOT install system-wide, unbind modules, edit GRUB, change `i915`/`xe` params,
  or touch firmware without explicit human approval.
- THE SYSTEM SHALL revert unsuccessful patches.

## Gate
Patch passes all correctness tests, adds no new error paths, and is neutral-to-better on measured
workloads.
