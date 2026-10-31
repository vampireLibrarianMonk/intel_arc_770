#!/usr/bin/env python3
"""B8: (1) binary-search the largest single correct torch.xpu tensor near 15 GiB,
(2) run a REAL matmul whose operand is a >4 GiB tensor, verify vs CPU.
Run under: NEOReadDebugKeys=1 AllowUnrestrictedSize=1 python b8_max_and_matmul.py
No driver/kernel/firmware change.
"""

import json
import os
import time

import torch

dev = "xpu"
GiB = 2**30
props = torch.xpu.get_device_properties(0)
total_gib = props.total_memory / GiB


def alloc_ok(size_gib):
    """True if a single float32 tensor of this size allocates AND a sentinel past
    the 4 GiB offset round-trips correctly through a real kernel."""
    n = int(size_gib * GiB) // 4
    if n < 2:
        return False
    try:
        t = torch.zeros(n, device=dev, dtype=torch.float32)
        one_gi = 2**32 // 4
        probe = [i for i in (one_gi, n - 1) if 0 <= i < n]
        for i in probe:
            t[i] = float((i % 997) + 1)
        t.add_(0.0)
        torch.xpu.synchronize()
        ok = all(float(t[i].cpu()) == float((i % 997) + 1) for i in probe)
        del t
        torch.xpu.empty_cache()
        return ok
    except Exception:
        torch.xpu.empty_cache()
        return False


# ---- (1) binary search the ceiling, resolution 0.1 GiB ----
lo, hi = 4.0, total_gib  # lo known-good, hi likely too big
# confirm lo
if not alloc_ok(lo):
    raise SystemExit("4 GiB should allocate with the key — is NEOReadDebugKeys=1 set?")
for _ in range(40):
    if hi - lo <= 0.1:
        break
    mid = round((lo + hi) / 2, 2)
    if alloc_ok(mid):
        lo = mid
    else:
        hi = mid
max_gib = lo
print(f"largest single correct tensor: {max_gib:.2f} GiB  (card total {total_gib:.2f} GiB)")

# ---- (2) a REAL matmul with a >4 GiB operand ----
# A @ B where A is (m, k) float32. Make A exceed 4 GiB: m*k*4 > 2^32.
# m=40000, k=28000 -> 40000*28000*4 = 4.48 GiB. B=(k, n2) small n2 to keep output modest.
m, k, n2 = 40000, 28000, 64
a_gib = m * k * 4 / GiB
matmul = {"m": m, "k": k, "n": n2, "A_GiB": round(a_gib, 2)}
try:
    A = torch.randn(m, k, device=dev, dtype=torch.float32)  # > 4 GiB operand
    B = torch.randn(k, n2, device=dev, dtype=torch.float32)
    for _ in range(2):
        C = A @ B
    torch.xpu.synchronize()
    t0 = time.time()
    C = A @ B
    torch.xpu.synchronize()
    dt = time.time() - t0
    # correctness: check a few output rows against CPU (float32 tolerance)
    import random

    rows = random.sample(range(m), 8)
    A_cpu = A[rows].cpu()
    B_cpu = B.cpu()
    ref = A_cpu @ B_cpu
    got = C[rows].cpu()
    max_err = (ref - got).abs().max().item()
    matmul.update(
        {
            "ran": True,
            "seconds": round(dt, 4),
            "GFLOP": round(2 * m * k * n2 / 1e9, 1),
            "GFLOPS": round(2 * m * k * n2 / dt / 1e9, 1),
            "max_abs_err_vs_cpu": round(max_err, 3),
            "correct": max_err < 1.0,  # float32 over k=28000 sums; loose but catches corruption
        }
    )
    print(
        f"matmul A={a_gib:.2f}GiB ({m}x{k}) @ B({k}x{n2}): {dt:.3f}s, "
        f"max_err={max_err:.3f}, correct={matmul['correct']}"
    )
    del A, B, C
    torch.xpu.empty_cache()
except Exception as e:
    matmul.update({"ran": False, "error": f"{type(e).__name__}: {e}"})
    print("matmul FAILED:", matmul["error"])

out = {
    "device": props.name,
    "torch": torch.__version__,
    "total_mem_GiB": round(total_gib, 2),
    "max_single_tensor_GiB": round(max_gib, 2),
    "matmul_over_4GiB": matmul,
}
path = os.path.expanduser("~/projects/intel_arc_770/artifacts/baseline/max_and_matmul.json")
os.makedirs(os.path.dirname(path), exist_ok=True)
json.dump(out, open(path, "w"), indent=2)
print("wrote", path)
