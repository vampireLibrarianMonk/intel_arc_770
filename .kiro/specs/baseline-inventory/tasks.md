# Baseline Inventory — Tasks

- [ ] 1. Implement `scripts/capture_baseline.sh` read-only probes (ARC-001, R1–R4).
- [ ] 2. Emit merged `environment.json` to `artifacts/baseline/<timestamp>/` (R5).
- [ ] 3. Add graceful fallbacks when `clinfo`/`ze_info` are absent (R2, R3).
- [ ] 4. **[on-hardware]** Run on the A770 host; verify PCI ID and render-node RW (R1, R4).
- [ ] 5. **[on-hardware]** Record NEO/IGC/GmmLib versions and ReBAR/PCIe state (R2, R3).
- [ ] 6. **[on-hardware]** Confirm stock 256 MiB read/write passes — Phase 0 gate.
- [ ] 7. Fill the pinned-SHA table in `docs/REPOSITORIES.md` from NEO `manifest.yml`.

> Tasks tagged **[on-hardware]** are blocked until an A770 is attached.
