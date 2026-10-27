"""xpu_large_tensor.py — PyTorch/XPU >4 GiB correctness & measurement harness.

Design: .kiro/specs/pytorch-xpu-harness/

Runs on an Intel Arc A770 via the torch.xpu backend. On a host without XPU it SKIPS
(it never fabricates results). Correctness is judged against a CPU reference tensor,
never by allocation success alone.

CPU-side reference values mirror the SplitMix64 scheme used by the C++/OpenCL oracle
so findings can be cross-checked across harnesses.
"""
from __future__ import annotations

import argparse
import sys

try:
    import torch
except Exception:  # torch may be absent on the scaffolding host
    torch = None  # type: ignore[assignment]

_MASK64 = (1 << 64) - 1
GIB = 1 << 30
FOUR_GIB = 1 << 32  # 2^32 bytes


def splitmix64(state: int) -> int:
    state = (state + 0x9E3779B97F4A7C15) & _MASK64
    z = state
    z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & _MASK64
    z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & _MASK64
    return (z ^ (z >> 31)) & _MASK64


def expected_value(seed: int, element_index: int) -> int:
    """Matches arc_oracle::expected_value in the C++ oracle (low 32 bits used for int32)."""
    state = (seed ^ ((element_index * 0xD1B54A32D192ED03) & _MASK64)) & _MASK64
    return splitmix64(state)


def xpu_available() -> bool:
    return torch is not None and bool(getattr(torch, "xpu", None)) and torch.xpu.is_available()


def sentinel_indices(n_elems: int, elem_size: int) -> list[int]:
    """Element indices whose byte offsets bracket the 4 GiB boundary (in-bounds only)."""
    candidates_bytes = [0, FOUR_GIB - elem_size, FOUR_GIB, FOUR_GIB + 4096]
    idxs = []
    for b in candidates_bytes:
        if b >= 0 and (b + elem_size) <= n_elems * elem_size:
            idxs.append(b // elem_size)
    idxs.append(n_elems - 1)
    # de-dup, keep order
    seen: set[int] = set()
    out = []
    for i in idxs:
        if 0 <= i < n_elems and i not in seen:
            seen.add(i)
            out.append(i)
    return out


def run(bytes_target: int, seed: int) -> int:
    if not xpu_available():
        print("Intel XPU not available; skipping (by design). No measurements produced.")
        return 0

    assert torch is not None
    dev = "xpu:0"
    props = torch.xpu.get_device_properties(0)
    print(f"XPU device: {props}")
    print(f"torch: {torch.__version__}")

    elem_size = 4  # int32
    n_elems = bytes_target // elem_size
    print(f"Allocating {bytes_target / GIB:.2f} GiB tensor ({n_elems} int32 elements)")

    buf = torch.empty(n_elems, dtype=torch.int32, device=dev)

    idxs = sentinel_indices(n_elems, elem_size)
    print(f"Sentinel element indices (byte offsets bracket 4 GiB): {idxs}")

    failures = 0
    for i in idxs:
        val = expected_value(seed, i)
        # Use signed 32-bit representation for int32 storage.
        signed = val & 0xFFFFFFFF
        if signed >= 0x80000000:
            signed -= 0x100000000
        buf[i] = signed
        read_back = int(buf[i].item())
        if read_back != signed:
            print(f"  MISMATCH at element {i} (byte {i * elem_size}): "
                  f"wrote {signed}, read {read_back}")
            failures += 1
        else:
            print(f"  OK element {i} (byte {i * elem_size})")

    torch.xpu.synchronize()
    peak = torch.xpu.max_memory_allocated()
    print(f"peak XPU memory allocated: {peak / GIB:.2f} GiB")

    if failures:
        print(f"RESULT: {failures} sentinel mismatch(es) -> correctness FAILED")
        return 1
    print("RESULT: all sentinels match CPU reference across the 4 GiB boundary")
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="PyTorch/XPU >4 GiB sentinel harness")
    parser.add_argument("--bytes", type=int, default=6 * GIB,
                        help="target tensor size in bytes (default 6 GiB)")
    parser.add_argument("--seed", type=int, default=123456)
    args = parser.parse_args(argv)
    return run(args.bytes, args.seed)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
