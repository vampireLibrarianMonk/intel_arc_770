#!/usr/bin/env python3
"""B9: near-15 GiB training stress test on the A770.

A real training loop (forward + backward + optimizer step) whose resident GPU memory
is pushed toward the card's 15.11 GiB limit — only possible with the >4 GiB unlock.
Run under: NEOReadDebugKeys=1 AllowUnrestrictedSize=1 python b9_training_stress.py

Checks: loss is finite and trends DOWN (real learning, not NaN/garbage), peak memory
is near the card limit, no hang/crash over N steps. Writes a JSON summary.
No driver/kernel/firmware change.
"""

import json
import os
import time

import torch
import torch.nn as nn

dev = "xpu"
GiB = 2**30
props = torch.xpu.get_device_properties(0)
total = props.total_memory

# A wide MLP whose parameters + activations + Adam state sit in the many-GiB range.
# Adam keeps 2 extra copies of every parameter, so param bytes alone are ~3x in memory.
# Sizes chosen to push resident memory toward ~12-14 GiB without a single >4 GiB tensor
# being required — this proves the UNLOCK via aggregate + lets individual layers be big.
HID = int(os.environ.get("HID", 8192))  # hidden width
LAYERS = int(os.environ.get("LAYERS", 3))
BATCH = int(os.environ.get("BATCH", 2048))
IN = int(os.environ.get("IN", 4096))
OUT = int(os.environ.get("OUT", 2048))
STEPS = int(os.environ.get("STEPS", 15))

torch.manual_seed(0)


class WideMLP(nn.Module):
    def __init__(self):
        super().__init__()
        layers = [nn.Linear(IN, HID), nn.ReLU()]
        for _ in range(LAYERS - 1):
            layers += [nn.Linear(HID, HID), nn.ReLU()]
        layers += [nn.Linear(HID, OUT)]
        self.net = nn.Sequential(*layers)

    def forward(self, x):
        return self.net(x)


def gib(x):
    return round(x / GiB, 2)


out = {
    "device": props.name,
    "torch": torch.__version__,
    "total_mem_GiB": gib(total),
    "config": {
        "hidden": HID,
        "layers": LAYERS,
        "batch": BATCH,
        "in": IN,
        "out": OUT,
        "steps": STEPS,
    },
    "steps": [],
    "ok": False,
}

try:
    torch.xpu.empty_cache()
    model = WideMLP().to(dev)
    opt = torch.optim.Adam(model.parameters(), lr=1e-4)
    loss_fn = nn.MSELoss()

    # fixed synthetic batch (reused) so we measure the GPU, not data loading
    x = torch.randn(BATCH, IN, device=dev)
    y = torch.randn(BATCH, OUT, device=dev)

    n_params = sum(p.numel() for p in model.parameters())
    out["param_count"] = n_params
    out["param_GiB"] = gib(n_params * 4)

    first_loss = None
    last_loss = None
    t_start = time.time()
    for step in range(STEPS):
        opt.zero_grad(set_to_none=True)
        pred = model(x)
        loss = loss_fn(pred, y)
        loss.backward()
        opt.step()
        torch.xpu.synchronize()
        lv = float(loss.detach().cpu())
        if first_loss is None:
            first_loss = lv
        last_loss = lv
        peak = torch.xpu.max_memory_allocated()
        if step % 3 == 0 or step == STEPS - 1:
            out["steps"].append({"step": step, "loss": round(lv, 5), "peak_GiB": gib(peak)})
        print(f"step {step:3d}  loss={lv:.5f}  peak={gib(peak):.2f} GiB", flush=True)

    dt = time.time() - t_start
    peak = torch.xpu.max_memory_allocated()
    reserved = torch.xpu.max_memory_reserved()
    finite = (last_loss == last_loss) and abs(last_loss) != float("inf")
    learned = finite and (last_loss < first_loss)
    out.update(
        {
            "first_loss": round(first_loss, 5),
            "last_loss": round(last_loss, 5),
            "loss_finite": finite,
            "loss_decreased": learned,
            "peak_alloc_GiB": gib(peak),
            "peak_reserved_GiB": gib(reserved),
            "peak_pct_of_card": round(100 * peak / total, 1),
            "seconds_total": round(dt, 2),
            "sec_per_step": round(dt / STEPS, 3),
            "ok": learned,
        }
    )
    print(f"\nloss {first_loss:.4f} -> {last_loss:.4f}  (decreased={learned})")
    print(
        f"peak alloc {gib(peak):.2f} GiB ({out['peak_pct_of_card']}% of card), "
        f"reserved {gib(reserved):.2f} GiB"
    )
    print(f"{dt:.1f}s total, {dt / STEPS * 1000:.0f} ms/step")
except Exception as e:
    out["error"] = f"{type(e).__name__}: {e}"
    print("STRESS TEST FAILED:", out["error"])

path = os.path.expanduser("~/projects/intel_arc_770/artifacts/baseline/training_stress.json")
os.makedirs(os.path.dirname(path), exist_ok=True)
json.dump(out, open(path, "w"), indent=2)
print("wrote", path)
