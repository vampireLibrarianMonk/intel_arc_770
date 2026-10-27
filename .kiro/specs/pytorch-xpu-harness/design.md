# PyTorch / XPU Application Harness — Design

## Layout
- `tests/pytorch/xpu_large_tensor.py` — main harness (CLI: sizes, seed, reps, tolerance).
- `tests/pytorch/requirements.txt` — pinned deps (torch + XPU backend).
- `tests/pytorch/conftest.py` — pytest skip logic when XPU absent (CI-safe offline).
- Reuses the sentinel/oracle concept from `tests/oracles/`.

## Device & backend
- Prefer upstream `torch.xpu` (PyTorch 2.5+ ships XPU support). Record whether IPEX is present.
- Explicit device string `xpu:<index>`; log `torch.xpu.get_device_properties(idx)`.

## Sentinel over the 4 GiB boundary
- Build a 1-D `uint8`/`int64` tensor sized just above 4 GiB.
- Compute element indices whose byte offsets land near `2^32-1`, `2^32`, `2^32+4096`, near-max.
- Write known values at those indices on device; read back; compare to CPU reference (same seed).
- Use sparse indexing — do not copy the whole multi-GiB tensor to host.

## Workload
- Large elementwise (`y = a*x + b`) and/or a tiled matmul whose operand exceeds 4 GiB.
- Validate against CPU oracle with `torch.allclose(atol, rtol)`; record max abs error.

## Measurement
- `torch.xpu.synchronize()` around timed regions; warm-up discarded; >= 10 reps.
- Separate transfer vs compute; `max_memory_allocated` for peak VRAM.

## Output
- JSON per run mirroring `docs/EXPERIMENT_TEMPLATE.md`; JUnit via pytest.

## Offline behavior
- With no XPU device, tests **skip** cleanly so the harness stays CI-green on the current host.
