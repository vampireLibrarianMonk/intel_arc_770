#!/usr/bin/env bash
# b4_pytorch_xpu.sh — installs an XPU-enabled PyTorch into a project venv. Run AFTER B3.
# This one does NOT need root: it builds a venv under the repo and pip-installs there.
# The Kiro agent MAY run this once B3 is confirmed.
#
# Uses Intel's XPU wheels. torch>=2.5 ships native XPU support; pin exact versions per
# docs/REPOSITORIES.md once chosen. Verifies with scripts/check_pytorch_xpu.py.
set -euo pipefail
DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1
run() { echo "+ $*"; [ "$DRY_RUN" -eq 1 ] || "$@"; }

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VENV="$REPO_ROOT/.venv-xpu"

echo "== B4: PyTorch/XPU venv =="
echo "   repo: $REPO_ROOT   venv: $VENV   dry-run: $DRY_RUN"

echo "[1/4] Create venv"
run python3 -m venv "$VENV"

echo "[2/4] Upgrade pip"
run "$VENV/bin/pip" install --upgrade pip

echo "[3/4] Install torch XPU build (Intel index). PIN exact versions before real run."
# Intel XPU wheels index. Keep versions pinned in docs/REPOSITORIES.md.
run "$VENV/bin/pip" install torch torchvision torchaudio \
  --index-url https://download.pytorch.org/whl/xpu

echo "[4/4] Verify XPU visibility (read-only probe)"
run "$VENV/bin/python" "$REPO_ROOT/scripts/check_pytorch_xpu.py" \
  --json-out "$REPO_ROOT/artifacts/baseline/pytorch_xpu.json"

echo
echo "== B4 complete. If xpu_available=true and the A770 is listed, proceed to B5 baseline."
