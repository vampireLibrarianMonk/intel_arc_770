#!/usr/bin/env python3
"""run_matrix.py — test/benchmark orchestration (STUB).

Planned responsibilities (Phase 2+):
  * Load a workload manifest from benchmarks/manifests/*.yaml
  * Build the A/B case list (stateful/small, stateless/large, segmented)
  * Warm up, then run >= 10 (prefer 20) measured repetitions, A/B order randomized
  * Separate H2D / kernel / D2H / compile / buffer-creation timers
  * Emit median, p95, dispersion, and ALL raw samples to artifacts/
  * Abort + flag on GPU hang/reset; never fabricate measurements

Intentionally does not run anything yet: no A770 is attached. Implement per
.kiro/specs/addressing-performance-study/ when on hardware.
"""
from __future__ import annotations

import argparse
import sys


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="arc-a770-lab matrix runner (stub)")
    parser.add_argument("--manifest", help="path to a workload manifest YAML")
    parser.add_argument("--dry-run", action="store_true", help="print the planned plan only")
    args = parser.parse_args(argv)

    print("run_matrix.py is a stub — orchestration not yet implemented.")
    print("See .kiro/specs/addressing-performance-study/ for the design.")
    if args.manifest:
        print(f"Requested manifest: {args.manifest}")
    print("No hardware attached; nothing executed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
