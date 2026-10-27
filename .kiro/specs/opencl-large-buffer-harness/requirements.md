# OpenCL >4 GiB Correctness Harness — Requirements

Backlog: ARC-002, ARC-003, ARC-004. Phase 1.

## Requirements (EARS)

### R1 — Explicit device selection
- THE SYSTEM SHALL select the A770 by PCI ID and/or device name, never "first device".
- IF the target device is not found, THEN THE SYSTEM SHALL fail with a clear error.

### R2 — Allocation modes
- THE SYSTEM SHALL support regular allocation and relaxed allocation
  (`CL_MEM_ALLOW_UNRESTRICTED_SIZE_INTEL`) as separate, labeled cases.
- THE SYSTEM SHALL compile kernels with and without `-cl-intel-greater-than-4GB-buffer-required`
  as separate, labeled cases.

### R3 — Correctness across the 4 GiB boundary
- THE SYSTEM SHALL write and read **distinct** sentinel values at offsets around
  `2^32-1`, `2^32`, and `2^32+4096` (within valid bounds).
- THE SYSTEM SHALL compare every result against an independent CPU oracle.
- THE SYSTEM SHALL NOT treat allocation success as proof of correctness.

### R4 — Test matrix
- THE SYSTEM SHALL implement MEM-01..MEM-10, including negative controls MEM-09/MEM-10
  (single-flag configurations) that detect rejection OR silent corruption safely.

### R5 — Multi-buffer aggregate
- THE SYSTEM SHALL demonstrate >4 GiB **aggregate** VRAM via multiple smaller buffers (MEM-08).

### R6 — Output
- THE SYSTEM SHALL emit JUnit/JSON with per-case status, error codes, and checksums.
- THE SYSTEM SHALL distinguish supported behavior, expected errors, and defects.

### R7 — Resource safety
- THE SYSTEM SHALL reserve headroom below reported max and distinguish OOM/fragmentation
  from a policy limit.
- WHEN a GPU hang/reset is detected, THE SYSTEM SHALL stop and report.

## Gate
Demonstrate the documented behavior OR a new reproducible discrepancy; no silent corruption in
supported configurations.
