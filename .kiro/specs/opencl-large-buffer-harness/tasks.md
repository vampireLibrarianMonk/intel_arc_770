# OpenCL >4 GiB Correctness Harness — Tasks

- [ ] 1. CMake project under `tests/opencl/` (find OpenCL, C++17, `-Wall -Wextra -Werror`).
- [ ] 2. Device selection by PCI ID / name with hard failure on no-match (R1).
- [ ] 3. CPU oracle in `tests/oracles/` with fixed-seed PRNG (R3).
- [ ] 4. `sentinel.cl` kernel with 64-bit indexing (R3).
- [ ] 5. Case model + MEM-01..MEM-10 table, incl. negative controls (R2, R4).
- [ ] 6. Device-side digest + sparse sentinel readback for large buffers (R3).
- [ ] 7. JSON + JUnit output with error codes and checksums (R6).
- [ ] 8. Headroom/OOM-vs-policy discrimination + hang/reset abort (R7).
- [ ] 9. Verify harness **compiles** offline (no device needed).
- [ ] 10. **[on-hardware]** Run full matrix on the A770; archive artifacts; produce the behavior table.

> Task 9 is the offline exit for Phase 1 scaffolding. Task 10 is **[on-hardware]**.
