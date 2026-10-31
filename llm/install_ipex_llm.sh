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
# LESSON LEARNED: which [xpu*] extras exist DIFFERS BY ipex-llm version, and an unknown
# extra is SILENTLY IGNORED by pip (bare install, no torch). `--pre --upgrade` also lets
# pip hop to a version whose extras differ. So: PIN an exact version known to provide the
# 'xpu-2-6' extra (pulls torch 2.6.0+xpu, matching our NEO 24.39), and do NOT use --upgrade.
IPEX_VERSION="${IPEX_VERSION:-2.3.0b20251110}"
# Extra choice depends on the venv's Python:
#   - Python 3.10 (this host): the 'xpu-2-6' extra wants torch==2.6.0+xpu, which is NOT on
#     this Intel index (only +cxx11.abi builds, newest 2.5.1). Use the 'xpu' extra →
#     torch 2.1.0a0+cxx11.abi + IPEX 2.1.10+xpu, both present for py3.10. Works on A770.
#   - Python 3.11+: you can use IPEX_EXTRA=xpu-2-6 for torch 2.6 (set a 3.11 venv first).
PYVER="$(python -c 'import sys; print("%d.%d" % sys.version_info[:2])')"
IPEX_EXTRA="${IPEX_EXTRA:-xpu}"
echo "    python $PYVER → ipex-llm[${IPEX_EXTRA}]==${IPEX_VERSION}"
if [ "$PYVER" = "3.10" ] && [ "$IPEX_EXTRA" = "xpu-2-6" ]; then
  echo "    NOTE: xpu-2-6 needs torch 2.6 (py3.11+). On 3.10 falling back to [xpu]." >&2
  IPEX_EXTRA="xpu"
fi
pip install "ipex-llm[${IPEX_EXTRA}]==${IPEX_VERSION}" --extra-index-url "$IDX"
# Guard: a bare ipex-llm (no torch) means the extra was ignored for this version.
if ! python -c "import torch" 2>/dev/null; then
  echo "ERROR: torch did not install — version ${IPEX_VERSION} may not provide xpu-2-6." >&2
  echo "       List extras:  python -c \"import importlib.metadata as m; print(m.metadata('ipex-llm').get_all('Provides-Extra'))\"" >&2
  echo "       Then re-run with IPEX_VERSION=<ver that has xpu-2-6>." >&2
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
