"""test_xpu_large_tensor.py — pytest wrapper.

The oracle (expected_value / sentinel_indices) is pure-Python and is always tested.
The device test is skipped cleanly when no XPU is present.
"""
from __future__ import annotations

import conftest
import xpu_large_tensor as h


def test_expected_value_deterministic():
    assert h.expected_value(123456, 42) == h.expected_value(123456, 42)


def test_expected_value_distinct():
    assert h.expected_value(123456, 1) != h.expected_value(123456, 2)


def test_sentinel_indices_cross_4gib():
    n = (h.FOUR_GIB + (1 << 20)) // 4
    idxs = h.sentinel_indices(n, 4)
    assert any((i * 4) >= h.FOUR_GIB for i in idxs), "need a sentinel at/above 4 GiB"
    assert all(0 <= i < n for i in idxs)


@conftest.requires_xpu
def test_large_tensor_sentinels_on_hardware():
    assert h.run(bytes_target=6 * h.GIB, seed=123456) == 0
