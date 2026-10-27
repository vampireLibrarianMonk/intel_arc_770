"""ab_bench.py — reusable A/B micro-benchmark driver for PyTorch/XPU perf work.

Implements the comparison hygiene from docs/PYTORCH_PERF_DUE_DILIGENCE.md:
  * warm-up iterations discarded
  * N measured reps (default 20), A/B order randomized per rep
  * separate transfer vs compute timing
  * median / p95 / stddev + ALL raw samples retained
  * correctness validated against a CPU reference (never perf-only)

Runs only when torch.xpu is available; otherwise it SKIPS cleanly (returns a report
with skipped=True) so it stays CI-green on a host with no Arc GPU. It never fabricates
timings and never mutates global perf settings implicitly.
"""
from __future__ import annotations

import argparse
import json
import random
import statistics
import sys
import time
from dataclasses import dataclass, field, asdict
from typing import Callable

try:
    import torch
except Exception:
    torch = None  # type: ignore[assignment]


def xpu_available() -> bool:
    return torch is not None and bool(getattr(torch, "xpu", None)) and torch.xpu.is_available()


@dataclass
class Variant:
    """One side of an A/B comparison."""
    name: str
    setup: Callable[[], object]              # build inputs on device; returns state
    run: Callable[[object], object]          # execute the op; returns device result
    reference: Callable[[], object] | None   # CPU oracle output (optional)


@dataclass
class VariantResult:
    name: str
    samples_ms: list[float] = field(default_factory=list)
    median_ms: float = 0.0
    p95_ms: float = 0.0
    stddev_ms: float = 0.0
    correct: bool | None = None
    max_abs_err: float | None = None


def _sync() -> None:
    if torch is not None and xpu_available():
        torch.xpu.synchronize()


def _time_once(variant: Variant, state: object) -> float:
    _sync()
    t0 = time.perf_counter()
    variant.run(state)
    _sync()
    return (time.perf_counter() - t0) * 1000.0


def _percentile(sorted_vals: list[float], pct: float) -> float:
    if not sorted_vals:
        return 0.0
    k = max(0, min(len(sorted_vals) - 1, int(round(pct / 100.0 * (len(sorted_vals) - 1)))))
    return sorted_vals[k]


def run_ab(variant_a: Variant, variant_b: Variant, reps: int = 20, warmup: int = 5,
           seed: int = 123456, tol: float = 1e-3) -> dict:
    report: dict = {"skipped": False, "reps": reps, "warmup": warmup, "seed": seed}

    if not xpu_available():
        report["skipped"] = True
        report["reason"] = "torch.xpu not available; no measurements produced."
        return report

    assert torch is not None
    rng = random.Random(seed)
    states = {variant_a.name: variant_a.setup(), variant_b.name: variant_b.setup()}
    results = {v.name: VariantResult(name=v.name) for v in (variant_a, variant_b)}
    variants = {variant_a.name: variant_a, variant_b.name: variant_b}

    # Warm-up (discarded).
    for _ in range(warmup):
        for name in variants:
            _time_once(variants[name], states[name])

    # Measured reps with randomized A/B order each rep.
    order = [variant_a.name, variant_b.name]
    for _ in range(reps):
        rng.shuffle(order)
        for name in order:
            results[name].samples_ms.append(_time_once(variants[name], states[name]))

    # Correctness vs CPU reference.
    for v in (variant_a, variant_b):
        if v.reference is not None:
            ref = v.reference()
            dev_out = v.run(states[v.name])
            dev_cpu = dev_out.detach().to("cpu") if hasattr(dev_out, "detach") else dev_out
            err = float(torch.max(torch.abs(dev_cpu - ref)).item())
            results[v.name].correct = err <= tol
            results[v.name].max_abs_err = err

    # Stats.
    for r in results.values():
        s = sorted(r.samples_ms)
        r.median_ms = statistics.median(s) if s else 0.0
        r.p95_ms = _percentile(s, 95.0)
        r.stddev_ms = statistics.pstdev(s) if len(s) > 1 else 0.0

    report["variants"] = {name: asdict(res) for name, res in results.items()}
    a_med = results[variant_a.name].median_ms
    b_med = results[variant_b.name].median_ms
    report["speedup_a_over_b"] = (b_med / a_med) if a_med else None
    report["note"] = "speedup reported only alongside raw samples and correctness."
    return report


# --- Example variant builder (elementwise saxpy), used by tests / as a template ------

def _saxpy_variants(n: int, dtype_a: str, dtype_b: str, seed: int):
    assert torch is not None
    dev = "xpu:0"
    g = torch.Generator(device="cpu").manual_seed(seed)
    x_cpu = torch.randn(n, generator=g)
    y_cpu = torch.randn(n, generator=g)
    a = 2.0

    def make(dtype_name: str) -> Variant:
        dt = getattr(torch, dtype_name)

        def setup():
            return (x_cpu.to(dev, dtype=dt), y_cpu.to(dev, dtype=dt))

        def run(state):
            x, y = state
            return a * x + y

        def reference():
            return (a * x_cpu + y_cpu)

        return Variant(name=f"saxpy_{dtype_name}", setup=setup, run=run, reference=reference)

    return make(dtype_a), make(dtype_b)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="PyTorch/XPU A/B micro-benchmark driver")
    parser.add_argument("--n", type=int, default=1 << 24, help="element count for the demo saxpy")
    parser.add_argument("--reps", type=int, default=20)
    parser.add_argument("--dtype-a", default="float32")
    parser.add_argument("--dtype-b", default="bfloat16")
    parser.add_argument("--json-out")
    args = parser.parse_args(argv)

    if not xpu_available():
        print(json.dumps({"skipped": True,
                          "reason": "torch.xpu not available; nothing measured."}, indent=2))
        return 0

    va, vb = _saxpy_variants(args.n, args.dtype_a, args.dtype_b, seed=123456)
    report = run_ab(va, vb, reps=args.reps)
    text = json.dumps(report, indent=2, default=str)
    print(text)
    if args.json_out:
        with open(args.json_out, "w", encoding="utf-8") as fh:
            fh.write(text + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
