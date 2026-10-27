# Runtime Patch Candidate — Tasks

- [ ] 1. Draft the flag-mismatch diagnostic design against a concrete reproducer (R1, R2).
- [ ] 2. Prototype capability-query/adaptive helper in `src/` with unit tests (R2, R4).
- [ ] 3. **[on-hardware]** Local-prefix NEO build, pinned versions; prove loaded ICD (R3).
- [ ] 4. **[on-hardware]** Apply one patch; re-run Phase 1 matrix + regression test (R4).
- [ ] 5. **[on-hardware]** Record pre/post measurements with SHAs; keep or revert (R4, R5) — Phase 3 gate.
- [ ] 6. Any privileged step → pause for human approval (R5).
