# Product steering — arc-a770-lab

## Goal

Build a reproducible, agent-assisted laboratory to diagnose Intel Arc A770 16 GiB compute-driver
behavior around the historical **4 GiB per-allocation** limit, and to design, implement, benchmark,
and validate narrowly scoped improvements.

## What we are actually investigating

The A770 has 16 GiB VRAM. Intel's **stateful addressing** model can cap a **single allocation** near
4 GiB. There is a documented supported path for >4 GiB allocations that requires **both**:

- an allocation override (`CL_MEM_ALLOW_UNRESTRICTED_SIZE_INTEL` / Level Zero relaxed limits), **and**
- stateless kernel compilation (`-cl-intel-greater-than-4GB-buffer-required` /
  `-ze-opt-greater-than-4GB-buffer-required`).

Using only one of the two can silently produce **wrong results** even though allocation succeeds.

## Non-goals

- Modifying GPU firmware/microcode or bypassing hardware safety mechanisms.
- Reverse-engineering Intel's proprietary Windows driver.
- Assuming a single 16 GiB allocation must be possible just because the card has 16 GiB.
- Claiming >4 GiB buffers can always be split transparently (pointer semantics, indexing, kernel
  args, visibility, and synchronization can prevent it).
- Installing system-wide drivers, editing bootloader/kernel, flashing firmware, or unloading
  production GPU modules without explicit human approval.
- Treating a successful build or allocation as a fixed defect.

## Exit criteria (any one is valuable)

1. Confirm the limitation and quantify its real-world cost on current software.
2. Find and fix a reproducible driver/compiler bug with an upstream-ready regression test.
3. Produce a measurable, repeatable application-level optimization for large-buffer use.
4. Show a credible speedup for a narrow class of kernels via better addressing/code generation.
5. Deliver a public benchmark harness useful to Intel GPU developers even without a driver patch.

## The three claims we never conflate

1. **Allocation capability improved** — a larger buffer can be created.
2. **Application can handle the workload** — correct results end-to-end.
3. **GPU throughput improved** — measured, repeatable performance gain.
