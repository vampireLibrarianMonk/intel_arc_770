#!/usr/bin/env python3
"""B6: probe the 4 GiB per-allocation boundary on torch.xpu (A770).

Tests H0 from docs/STRATEGY.md: CL_DEVICE_MAX_MEM_ALLOC_SIZE is ~4 GiB, so a
single tensor larger than 4 GiB may fail or misbehave, even though the card has
16 GiB total. We do NOT trust allocation success alone — we write distinct
sentinel values on BOTH sides of the 2^32-byte offset and read them back, so a
silent wrap/corruption is caught.

Unprivileged, read/compute only. No driver/kernel/firmware changes.
Writes artifacts/baseline/alloc_boundary.json.
"""

import json
import os

import torch

dev = "xpu"
GiB = 2**30
props = torch.xpu.get_device_properties(0)
total = props.total_memory

# float32 element = 4 bytes. 2^32 bytes = 1 Gi elements.
# Pick sizes in ELEMENTS so the byte size straddles 4 GiB (2^32 bytes).
MiB = 2**20
cases = [
    ("256MiB", (256 * MiB) // 4),
    ("2GiB", (2 * GiB) // 4),
    ("3_8GiB", int(3.8 * GiB) // 4),  # just under the 4 GiB policy limit
    ("4_2GiB", int(4.2 * GiB) // 4),  # just over 2^32 bytes
    ("6GiB", (6 * GiB) // 4),  # well over; aggregate still < 16 GiB
]


def sentinel_test(n_elem):
    """Allocate n_elem float32 on XPU, write distinct values at the ends and
    just across the 2^32-byte (1 Gi-element) mark, read back, verify."""
    t = torch.zeros(n_elem, device=dev, dtype=torch.float32)
    one_gi = 2**32 // 4  # element index at the 2^32-byte (4 GiB) offset
    # candidate sentinel indices; keep only those actually inside this buffer
    cand = [0, 1, one_gi - 1, one_gi, one_gi + 1024, n_elem - 1]
    idx = sorted({i for i in cand if 0 <= i < n_elem})
    vals = {i: float((i % 997) + 1) for i in idx}
    for i, v in vals.items():
        t[i] = v
    torch.xpu.synchronize()
    bad = {i: (vals[i], float(t[i].cpu())) for i in idx if float(t[i].cpu()) != vals[i]}
    # also a reduction so the whole buffer is touched by a real kernel
    s = float(t.sum().cpu())
    del t
    torch.xpu.empty_cache()
    return bad, s


out = {
    "device": props.name,
    "torch": torch.__version__,
    "total_mem_GiB": round(total / GiB, 2),
    "max_alloc_hint_GiB": 4.0,  # OpenCL CL_DEVICE_MAX_MEM_ALLOC_SIZE on A770
    "cases": [],
}

for name, n in cases:
    size_gib = round(n * 4 / GiB, 3)
    rec = {"name": name, "size_GiB": size_gib, "n_elem": n}
    try:
        bad, s = sentinel_test(n)
        rec["allocated"] = True
        rec["sentinels_ok"] = len(bad) == 0
        rec["bad_sentinels"] = {str(k): v for k, v in bad.items()}
        rec["sum"] = s
        rec["verdict"] = "ok" if not bad else "ALLOCATED_BUT_CORRUPT"
    except Exception as e:
        rec["allocated"] = False
        rec["sentinels_ok"] = None
        rec["error"] = f"{type(e).__name__}: {e}"
        rec["verdict"] = "alloc_rejected"
    out["cases"].append(rec)
    print(
        f"{name:8} {size_gib:>6} GiB -> {rec['verdict']}"
        + ("" if rec.get("allocated") else f"  ({rec.get('error', '')[:70]})")
    )

path = os.path.expanduser("~/projects/intel_arc_770/artifacts/baseline/alloc_boundary.json")
os.makedirs(os.path.dirname(path), exist_ok=True)
json.dump(out, open(path, "w"), indent=2)
print("\nwrote", path)
