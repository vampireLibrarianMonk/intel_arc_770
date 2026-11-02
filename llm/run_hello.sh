#!/usr/bin/env bash
# run_hello.sh — minimal smoke test: one Python hello-world coding task + one English
# writing paragraph, each on its own local model, running on the Arc A770 via IPEX-LLM.
#
#   bash llm/run_hello.sh                                            # defaults
#   bash llm/run_hello.sh --topic "the Intel Arc A770 GPU"           # pick the writing topic
#   bash llm/run_hello.sh --code-model Qwen/Qwen2.5-Coder-1.5B-Instruct
#   bash llm/run_hello.sh --write-model Qwen/Qwen2.5-1.5B-Instruct
#   bash llm/run_hello.sh --skip-writing                            # coding only
#
# Activates .venv-llm, sources the Arc runtime env, then runs llm_hello.py.
# Models download from Hugging Face on first use (small defaults, a few GiB each).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENV="$REPO_ROOT/.venv-llm"

if [ ! -d "$VENV" ]; then
  echo "ERROR: $VENV not found. Run:  bash llm/install_ipex_llm.sh" >&2
  exit 1
fi

# shellcheck disable=SC1091
source "$VENV/bin/activate"
# shellcheck disable=SC1091
source "$REPO_ROOT/llm/xpu_runtime.env"

if ! python -c "import torch" 2>/dev/null; then
  echo "ERROR: torch is not installed in $VENV." >&2
  echo "       The install likely did not finish. Re-run:  bash llm/install_ipex_llm.sh" >&2
  exit 1
fi

echo "== LLM hello-world smoke test =="
echo "   args: $*"
echo "   (first run downloads weights + compiles kernels; be patient)"
echo
exec python -u "$REPO_ROOT/llm/llm_hello.py" "$@"
