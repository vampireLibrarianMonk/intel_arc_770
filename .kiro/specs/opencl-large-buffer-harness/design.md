# OpenCL >4 GiB Correctness Harness — Design

## Layout
- `tests/opencl/large_buffer.cpp` — main harness (C++17).
- `tests/opencl/kernels/sentinel.cl` — minimal write/read kernel using 64-bit indexing.
- `tests/oracles/sentinel_oracle.hpp` — host reference (shared with PyTorch harness where sensible).
- `tests/opencl/CMakeLists.txt` — build; finds OpenCL, C++17, warnings-as-errors.

## Device selection
Enumerate platforms/devices; match on PCI ID (via `cl_intel_device_attribute_query` /
`CL_DEVICE_PCI_BUS_INFO_KHR` when available) or exact device name substring. Abort if no match.

## Case model
Each case = {size, allocation_mode, compile_mode, expectation}. The matrix MEM-01..MEM-10 is a
table of these. Negative controls (MEM-09/10) expect either a clean rejection or detected corruption
— never a silent pass.

## Sentinel strategy
- 64-bit element indexing; element type `uint64_t`.
- Sentinel offsets: byte offsets near `2^32-1`, `2^32`, `2^32+4096`, plus near-max and near-zero.
- For large buffers, avoid full host copy: device-side digest + sparse sentinel readback, then
  selective full checks. Digest must not wrap/mask corruption.

## Oracle
Pure-CPU function computes expected sentinel values and digest from (seed, size, offset list).
Deterministic PRNG with fixed seed (123456 default).

## Output
JSON per run + JUnit XML. Fields: case id, size, modes, cl error code, alloc_time_ms, kernel_time_ms,
sentinel pass/fail per offset, digest match, notes.

## Safety hooks
Poll for `CL_OUT_OF_RESOURCES` / context errors; on suspected hang/reset, abort the run and flag.
