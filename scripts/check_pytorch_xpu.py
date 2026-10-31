#!/usr/bin/env python3
"""check_pytorch_xpu.py — READ-ONLY framework-level prerequisite & capability probe.

Confirms that PyTorch can see the Arc A770 via the XPU backend and reports the
properties and runtime knobs that matter for performance work. Imports torch if
present; if torch or XPU is absent it reports that cleanly and exits 0 (an offline
scaffolding host is expected). It does NOT change any setting or run a workload.

Emits a JSON report to stdout (and optionally a file) mirroring the environment.json
style so it can be archived next to baseline captures.
"""

from __future__ import annotations

import argparse
import json
import sys


def _safe(fn, default=None):
    try:
        return fn()
    except Exception as exc:  # report, do not crash the probe
        return f"error: {exc}" if default is None else default


def collect() -> dict:
    report: dict = {
        "torch_importable": False,
        "torch_version": None,
        "xpu_attr_present": False,
        "xpu_available": False,
        "device_count": 0,
        "devices": [],
        "ipex": None,
        "perf_knobs": {},
        "notes": [],
    }

    try:
        import torch
    except Exception as exc:
        report["notes"].append(f"torch not importable: {exc}")
        return report

    report["torch_importable"] = True
    report["torch_version"] = getattr(torch, "__version__", None)

    # Optional Intel Extension for PyTorch (older stacks). Newer torch has native XPU.
    try:
        import intel_extension_for_pytorch as ipex  # type: ignore

        report["ipex"] = getattr(ipex, "__version__", "present")
    except Exception:
        report["ipex"] = None

    xpu = getattr(torch, "xpu", None)
    report["xpu_attr_present"] = xpu is not None
    if xpu is None:
        report["notes"].append("torch has no .xpu backend (need an XPU-enabled build)")
        return report

    report["xpu_available"] = bool(_safe(lambda: torch.xpu.is_available(), False))
    if not report["xpu_available"]:
        report["notes"].append("torch.xpu present but no XPU device available on this host")
        return report

    count = int(_safe(lambda: torch.xpu.device_count(), 0) or 0)
    report["device_count"] = count
    for i in range(count):
        props = _safe(lambda i=i: torch.xpu.get_device_properties(i))
        report["devices"].append(
            {
                "index": i,
                "name": _safe(lambda p=props: getattr(p, "name", None)),
                "total_memory_bytes": _safe(lambda p=props: getattr(p, "total_memory", None)),
                "max_compute_units": _safe(lambda p=props: getattr(p, "max_compute_units", None)),
                "properties_repr": str(props),
            }
        )

    # Performance-relevant runtime knobs (reported, never changed here).
    report["perf_knobs"] = {
        "tf32_allowed": _safe(lambda: getattr(torch.backends, "mkldnn", None) is not None),
        "autocast_xpu_supported": _safe(lambda: hasattr(torch, "autocast")),
        "num_threads": _safe(lambda: torch.get_num_threads()),
    }

    return report


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="PyTorch/XPU capability probe (read-only)")
    parser.add_argument("--json-out", help="write the JSON report to this path")
    args = parser.parse_args(argv)

    report = collect()
    text = json.dumps(report, indent=2, default=str)
    print(text)
    if args.json_out:
        with open(args.json_out, "w", encoding="utf-8") as fh:
            fh.write(text + "\n")
        print(f"\nwrote {args.json_out}", file=sys.stderr)

    # Always exit 0: absence of hardware/torch is an expected state, not an error.
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
