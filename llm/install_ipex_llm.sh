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
# Extra name must be one the installed wheel actually provides; an unknown extra is
# SILENTLY IGNORED by pip, leaving a bare ipex-llm with NO torch/IPEX.
# For the Arc A770 (DG2) the Arc-specific extra is 'xpu-arc' (torch 2.3.1+cxx11.abi,
# IPEX 2.3.110+xpu, bigdl-core-xe-23). 'xpu' is the older 2.1 line. Try Arc first.
installed=0
for extra in "xpu-arc" "xpu"; do
  echo "    trying ipex-llm[$extra]"
  if pip install --pre --upgrade "ipex-llm[$extra]" --extra-index-url "$IDX"; then
    installed=1; break
  fi
done
[ "$installed" = 1 ] || { echo "ERROR: no ipex-llm xpu extra installed" >&2; exit 1; }
# Guard: a bare ipex-llm (no torch) means the extra was ignored. Fail loudly, not at runtime.
if ! python -c "import torch" 2>/dev/null; then
  echo "ERROR: torch did not install — the ipex-llm extra was not recognized by pip." >&2
  echo "       Check available extras, then install the right one, e.g. 'ipex-llm[xpu-arc]'." >&2
  exit 1
fi
# The xpu-arc extra already pins transformers==4.37.0 + tokenizers==0.15.2 + sentencepiece.
# Only add the model-download helper; do NOT re-pin transformers (would fight the extra).
pip install --quiet "huggingface_hub>=0.23"

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
