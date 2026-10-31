#!/usr/bin/env python3
"""B7: does NEO AllowUnrestrictedSize let torch.xpu use a SINGLE >4 GiB tensor
CORRECTLY (not just allocate it)? Run under:
    NEOReadDebugKeys=1 AllowUnrestrictedSize=1 python b7_torch_unrestricted.py

Writes sentinel values on both sides of the 2^32-byte (4 GiB) offset, runs a real
GPU kernel over the whole tensor, reads back and checks. Also finds the largest
single tensor that allocates AND computes correctly. No driver/kernel/firmware change.
"""

import json
import os

import torch

dev = "xpu"
GiB = 2**30
props = torch.xpu.get_device_properties(0)


def check_one(size_gib):
    """Alloc one float32 tensor, write sentinels across the 4 GiB mark via a real
    kernel, read back, verify. Returns (ok, detail)."""
    n = int(size_gib * GiB) // 4
    one_gi = 2**32 // 4  # element index at the 4 GiB byte offset
    try:
        t = torch.zeros(n, device=dev, dtype=torch.float32)
    except Exception as e:
        return False, f"alloc_failed: {type(e).__name__}"
    try:
        # sentinel indices straddling the 4 GiB offset, clamped in-bounds
        cand = [0, 1, one_gi - 1, one_gi, one_gi + 1024, n - 1]
        idx = sorted({i for i in cand if 0 <= i < n})
        want = {i: float((i % 997) + 1) for i in idx}
        # write via indexing (device kernel), then a real elementwise pass over ALL n
        for i, v in want.items():
            t[i] = v
        t.add_(0.0)  # full-tensor kernel touches every element
        torch.xpu.synchronize()
        bad = {i: (want[i], float(t[i].cpu())) for i in idx if float(t[i].cpu()) != want[i]}
        # a reduction that must run across the whole buffer
        s = float(t.sum().cpu())
        del t
        torch.xpu.empty_cache()
        if bad:
            return False, f"CORRUPT past offset: {bad}"
        return True, f"sentinels_ok, sum={s}"
    except Exception as e:
        torch.xpu.empty_cache()
        return False, f"compute_failed: {type(e).__name__}: {e}"


out = {
    "device": props.name,
    "torch": torch.__version__,
    "total_mem_GiB": round(props.total_memory / GiB, 2),
    "debug_key": os.environ.get("AllowUnrestrictedSize", "<unset>"),
    "read_keys": os.environ.get("NEOReadDebugKeys", "<unset>"),
    "results": [],
}

for gib in [2, 3.8, 4.2, 6, 8, 10, 12]:
    ok, detail = check_one(gib)
    out["results"].append({"size_GiB": gib, "ok": ok, "detail": detail})
    print(f"{gib:>5} GiB -> {'OK ' if ok else 'FAIL'}  {detail[:80]}")

path = os.path.expanduser("~/projects/intel_arc_770/artifacts/baseline/torch_unrestricted.json")
os.makedirs(os.path.dirname(path), exist_ok=True)
json.dump(out, open(path, "w"), indent=2)
print("\nwrote", path)
