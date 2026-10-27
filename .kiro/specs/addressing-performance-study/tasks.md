# Addressing Performance Study — Tasks

- [ ] 1. Define workload manifests (sizes, seeds, dims) under `benchmarks/manifests/` (R2, R4).
- [ ] 2. Implement the five workload-class kernels + host drivers (R2).
- [ ] 3. Build `scripts/run_matrix.py`: warm-up, repeats, A/B randomization, split timers (R1, R3).
- [ ] 4. Stats + raw-sample persistence (median/p95/dispersion) (R3, R5).
- [ ] 5. Wire in `intel/compute-benchmarks` for cross-check (R1).
- [ ] 6. **[on-hardware]** Run the A/B matrix; capture thermals, VRAM, reset counts (R4).
- [ ] 7. **[on-hardware]** Produce reviewed report + at least one bottleneck hypothesis — Phase 2 gate.
