# Intel Arc A770 Lab — Agent Rules

- Objective: reproducible OpenCL/Level Zero diagnostics and narrowly scoped improvements for Arc A770 16 GiB.
- Prefer a minimal falsifiable test over broad speculative refactoring.
- Every reported finding includes: GPU PCI ID, OS/kernel, NEO/IGC/GmmLib release and SHA, exact flags, reproduction command, evidence, and uncertainty.
- Do not confuse a ~4 GiB per-buffer limit with total VRAM capacity.
- For >4 GiB OpenCL access, verify BOTH relaxed allocation and stateless kernel compilation.
- A created allocation is never sufficient proof: verify values above the 4 GiB offset.
- Use pinned dependency versions. Use local prefixes; do not overwrite stock drivers.
- Treat shell commands that modify firmware, kernel modules, BIOS, boot configuration, driver packages, or system library paths as human-approval-required.
- Do not silently change GPU power or clocks. Stop on repeated hangs, faults, or data corruption.
- Prioritize correctness, then repeatability, then performance. Revert unsuccessful patches.
- Never invent measurements. Keep raw results and describe limitations.
- Keep driver source and test harness separate; submit small, reviewable changes upstream.

## Three distinct claims (never conflate)

1. "Allocation capability improved" — a larger buffer can be created.
2. "Application can handle the workload" — the program produces correct results end-to-end.
3. "GPU throughput improved" — measured, repeatable performance gain.

## Hardware-independent vs hardware-required work

- **Offline (no A770):** scaffolding, specs, steering, harness source that compiles, CPU oracles, experiment schema, documentation, dependency-pin research.
- **On-hardware only:** running the discovery commands, allocation/boundary tests, benchmarks, any driver load verification.
