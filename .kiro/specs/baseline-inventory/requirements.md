# Baseline Inventory — Requirements

Backlog: ARC-001. Phase 0. **All read-only; no privileged changes.**

## User stories & acceptance criteria (EARS)

### R1 — Hardware identification
- WHEN the capture script runs, THE SYSTEM SHALL record GPU model, PCI ID, and all `/dev/dri` render nodes.
- WHEN an A770 is present, THE SYSTEM SHALL confirm the `8086:56a0` (or variant) PCI ID explicitly.
- IF multiple GPUs/accelerators are present, THEN THE SYSTEM SHALL require explicit device selection.

### R2 — Software stack
- THE SYSTEM SHALL record OS release, kernel version, and loaded `i915`/`xe` modules.
- THE SYSTEM SHALL record the OpenCL ICD and (if present) Level Zero loader, with vendor library paths.
- THE SYSTEM SHALL record NEO/IGC/GmmLib versions where discoverable.

### R3 — Capability snapshot
- THE SYSTEM SHALL record `CL_DEVICE_GLOBAL_MEM_SIZE` and `CL_DEVICE_MAX_MEM_ALLOC_SIZE`.
- THE SYSTEM SHALL record ReBAR state and PCIe link negotiation where available.

### R4 — Permissions & access
- THE SYSTEM SHALL verify read/write access to `/dev/dri/renderD*`.

### R5 — Evidence integrity
- THE SYSTEM SHALL write full unfiltered output to `artifacts/baseline/`.
- THE SYSTEM SHALL emit a structured `environment.json`.
- THE SYSTEM SHALL NOT modify firmware, kernel modules, boot config, or driver packages.

## Gate
Stock driver passes a 256 MiB read/write test AND `environment.json` is complete.
