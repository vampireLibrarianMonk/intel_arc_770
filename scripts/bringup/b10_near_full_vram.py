#!/usr/bin/env python3
"""B10: hold a near-14 GiB resident footprint on the A770 while real compute runs.

Strategy: reserve a large persistent block (one or more big tensors, incl. a SINGLE
>4 GiB tensor to exercise the unlock), then run a real train step beside it. This reaches
a high peak FAST, without giant slow kernels. Verifies the big tensor's data past the
4 GiB offset, trains a small model to a falling loss, reports peak memory.

Run under: NEOReadDebugKeys=1 AllowUnrestrictedSize=1 python b10_near_full_vram.py
Env: TARGET_GiB (default 14). No driver/kernel/firmware change.
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
target = float(os.environ.get("TARGET_GiB", 14))


def gib(x):
    return round(x / GiB, 2)


out = {
    "device": props.name,
    "torch": torch.__version__,
    "total_mem_GiB": gib(total),
    "target_GiB": target,
    "ok": False,
}

try:
    torch.xpu.empty_cache()
    # 1) one SINGLE >4 GiB tensor (the unlock), with a verified sentinel past 4 GiB
    big_gib = 6.0
    big_n = int(big_gib * GiB) // 4
    big = torch.zeros(big_n, device=dev, dtype=torch.float32)
    one_gi = 2**32 // 4
    big[one_gi] = 12345.0  # write past the 4 GiB offset
    big[big_n - 1] = 999.0
    torch.xpu.synchronize()
    sentinel_ok = float(big[one_gi].cpu()) == 12345.0 and float(big[big_n - 1].cpu()) == 999.0

    # 2) filler to climb toward TARGET, in chunks (each <= 4 GiB so no single-alloc worry)
    held = [big]
    want_bytes = int(target * GiB)
    have = big_n * 4
    # fill up to want_bytes with a final partial chunk so we land ON target, not a chunk short
    while have < want_bytes:
        remain_elems = (want_bytes - have) // 4
        if remain_elems < 2:
            break
        chunk = min(int(1.0 * GiB) // 4, remain_elems)
        held.append(torch.ones(chunk, device=dev, dtype=torch.float32))
        have += chunk * 4
    torch.xpu.synchronize()

    # 3) real train step beside the held memory (small model = fast steps)
    model = nn.Sequential(nn.Linear(2048, 4096), nn.ReLU(), nn.Linear(4096, 2048)).to(dev)
    opt = torch.optim.Adam(model.parameters(), lr=1e-3)
    loss_fn = nn.MSELoss()
    x = torch.randn(1024, 2048, device=dev)
    y = torch.randn(1024, 2048, device=dev)
    first = last = None
    t0 = time.time()
    for step in range(10):
        opt.zero_grad(set_to_none=True)
        loss = loss_fn(model(x), y)
        loss.backward()
        opt.step()
        torch.xpu.synchronize()
        lv = float(loss.detach().cpu())
        first = lv if first is None else first
        last = lv
        peak = torch.xpu.max_memory_allocated()
        print(f"step {step}  loss={lv:.5f}  peak={gib(peak):.2f} GiB", flush=True)
    dt = time.time() - t0

    peak = torch.xpu.max_memory_allocated()
    reserved = torch.xpu.max_memory_reserved()
    out.update(
        {
            "held_GiB": gib(have),
            "big_tensor_GiB": big_gib,
            "big_sentinel_ok": sentinel_ok,
            "peak_alloc_GiB": gib(peak),
            "peak_reserved_GiB": gib(reserved),
            "peak_pct_of_card": round(100 * peak / total, 1),
            "first_loss": round(first, 5),
            "last_loss": round(last, 5),
            "loss_decreased": last < first,
            "sec_per_step": round(dt / 10, 3),
            "ok": sentinel_ok and last < first,
        }
    )
    print(
        f"\nheld {gib(have):.2f} GiB, peak {gib(peak):.2f} GiB ({out['peak_pct_of_card']}% of card)"
    )
    print(f"big-tensor sentinel past 4 GiB: {'OK' if sentinel_ok else 'FAIL'}")
    print(f"loss {first:.4f} -> {last:.4f}, {out['sec_per_step'] * 1000:.0f} ms/step")
    del held, big, model, x, y
    torch.xpu.empty_cache()
except Exception as e:
    out["error"] = f"{type(e).__name__}: {e}"
    print("FAILED:", out["error"])

path = os.path.expanduser("~/projects/intel_arc_770/artifacts/baseline/near_full_vram.json")
os.makedirs(os.path.dirname(path), exist_ok=True)
json.dump(out, open(path, "w"), indent=2)
print("wrote", path)
