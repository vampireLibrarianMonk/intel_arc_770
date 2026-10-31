#!/usr/bin/env python3
"""B5 baseline: correctness + speed for torch.xpu on the A770. Writes JSON."""

import json
import os
import time

import torch

dev = "xpu"
# correctness vs CPU
a = torch.randn(1024, 1024)
b = torch.randn(1024, 1024)
err = ((a.to(dev) @ b.to(dev)).cpu() - a @ b).abs().max().item()
# speed: 4096^3 matmul, averaged
x = torch.randn(4096, 4096, device=dev)
y = torch.randn(4096, 4096, device=dev)
for _ in range(5):
    _ = x @ y
torch.xpu.synchronize()
t0 = time.time()
for _ in range(20):
    _ = x @ y
torch.xpu.synchronize()
dt = (time.time() - t0) / 20
p = torch.xpu.get_device_properties(0)
out = {
    "torch": torch.__version__,
    "device": p.name,
    "driver_neo": "24.39.31294",
    "total_mem_GiB": round(p.total_memory / 1024**3, 2),
    "matmul_max_abs_err": round(err, 4),
    "matmul4096_s": round(dt, 4),
    "matmul4096_TFLOPS": round(2 * 4096**3 / dt / 1e12, 1),
}
print(json.dumps(out, indent=2))
path = os.path.expanduser("~/projects/intel_arc_770/artifacts/baseline/pytorch_xpu.json")
os.makedirs(os.path.dirname(path), exist_ok=True)
json.dump(out, open(path, "w"), indent=2)
print("wrote", path)
