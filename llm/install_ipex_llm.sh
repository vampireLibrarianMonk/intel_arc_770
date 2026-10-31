#!/usr/bin/env bash
# install_ipex_llm.sh — set up IPEX-LLM for the Arc A770 in an isolated venv.
#
# Run it:  bash llm/install_ipex_llm.sh
#
# Safe to re-run. Creates .venv-llm next to the project (separate from .venv-xpu so our
# verified torch 2.6 stack is never touched). Downloads several GB from Intel's mirror —
# run it in YOUR shell (not a timed agent call); it may take a while on a slow mirror.
#
# Prereqs already satisfied by the bring-up (kernel 6.8, NEO 24.39, Level Zero, GuC):
# this script installs ONLY the Python side. No sudo, no driver changes.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENV="$REPO_ROOT/.venv-llm"
REGION="${IPEX_REGION:-us}"   # set IPEX_REGION=cn for the China mirror

echo "== IPEX-LLM install =="
echo "   repo:   $REPO_ROOT"
echo "   venv:   $VENV"
echo "   region: $REGION"
echo

if [ ! -d "$VENV" ]; then
  echo "[1/3] create venv"
  python3 -m venv "$VENV"
else
  echo "[1/3] venv exists, reusing"
fi
# shellcheck disable=SC1091
source "$VENV/bin/activate"
python -m pip install --quiet --upgrade pip

echo "[2/3] install ipex-llm + XPU torch stack (large download)"
IDX="https://pytorch-extension.intel.com/release-whl/stable/xpu/${REGION}/"
# IMPORTANT: the extra name uses HYPHENS (xpu-2-6), not xpu_2.6. A wrong/unknown extra is
# silently ignored by pip, leaving a bare ipex-llm with NO torch/IPEX. Verify torch after.
if ! pip install --pre --upgrade "ipex-llm[xpu-2-6]" --extra-index-url "$IDX"; then
  echo "    xpu-2-6 extra failed; falling back to ipex-llm[xpu] (PyTorch 2.1 line)"
  pip install --pre --upgrade "ipex-llm[xpu]" --extra-index-url "$IDX"
fi
# Guard: a bare ipex-llm (no torch) means the extra was ignored. Fail loudly instead of later.
if ! python -c "import torch" 2>/dev/null; then
  echo "ERROR: torch did not install — the ipex-llm extra was not recognized by pip." >&2
  echo "       Try:  pip install --pre --upgrade 'ipex-llm[xpu]' --extra-index-url $IDX" >&2
  exit 1
fi
# Harness extras. transformers is NOT always pulled by the ipex-llm extra, and IPEX-LLM's
# 4-bit loader is pinned to the 4.36-4.38 line (newer breaks from_pretrained). Pin 4.37.0.
pip install --quiet "transformers==4.37.0" sentencepiece "huggingface_hub>=0.23"

echo "[3/3] verify import"
python - <<'PY'
from ipex_llm.transformers import AutoModelForCausalLM  # noqa: F401
import torch
print("ipex-llm import OK; torch", torch.__version__,
      "xpu_available", torch.xpu.is_available() if hasattr(torch, "xpu") else False)
PY

echo
echo "== install complete =="
echo "Next: run a test with"
echo "    bash llm/run_llm_tests.sh --model Qwen/Qwen2.5-1.5B-Instruct"
echo "(models download from Hugging Face on first use; pick one that fits 15 GiB)"
