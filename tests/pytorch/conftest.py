"""conftest.py — skip XPU tests cleanly when no Intel GPU/torch.xpu is available.

Keeps the suite CI-green on the current (no-A770) host while remaining ready to run
end-to-end once the hardware and an XPU-enabled PyTorch build are present.
"""

from __future__ import annotations

import pytest


def xpu_available() -> bool:
    try:
        import torch  # noqa: WPS433 (local import by design)
    except Exception:
        return False
    return bool(getattr(torch, "xpu", None)) and torch.xpu.is_available()


requires_xpu = pytest.mark.skipif(
    not xpu_available(),
    reason="Intel XPU (torch.xpu) not available on this host; on-hardware test skipped.",
)
