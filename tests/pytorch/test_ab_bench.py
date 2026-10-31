"""Offline-testable parts of the A/B benchmark driver.

The timing/execution path needs an XPU device and is skipped there; the pure helpers
(percentile, skip behavior) are always exercised so regressions surface in CI.
"""

from __future__ import annotations

import ab_bench


def test_percentile_basic():
    vals = [float(i) for i in range(1, 101)]  # 1..100 sorted
    assert ab_bench._percentile(vals, 95.0) >= 95.0
    assert ab_bench._percentile(vals, 0.0) == 1.0
    assert ab_bench._percentile(vals, 100.0) == 100.0


def test_percentile_empty():
    assert ab_bench._percentile([], 95.0) == 0.0


def test_run_ab_skips_without_xpu():
    # On a host with no XPU, run_ab must skip cleanly and never fabricate timings.
    if ab_bench.xpu_available():
        import pytest

        pytest.skip("XPU present; skip-path test not applicable here")
    dummy = ab_bench.Variant("a", setup=lambda: None, run=lambda s: None, reference=None)
    report = ab_bench.run_ab(dummy, dummy, reps=3)
    assert report["skipped"] is True
    assert "variants" not in report
