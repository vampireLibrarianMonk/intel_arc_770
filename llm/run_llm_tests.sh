#!/usr/bin/env bash
# run_llm_tests.sh — one command to run the LLM test regime on the Arc A770.
#
#   bash llm/run_llm_tests.sh                                   # default model
#   bash llm/run_llm_tests.sh --model Qwen/Qwen2.5-7B-Instruct  # pick a model
#   bash llm/run_llm_tests.sh --model <id> --max-new 256        # pass-through args
#
# Activates .venv-llm, sources the Arc runtime env, then runs llm_bench.py.
# Models download from Hugging Face on first use. Results land in artifacts/llm/.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENV="$REPO_ROOT/.venv-llm"
DEFAULT_MODEL="Qwen/Qwen2.5-1.5B-Instruct"

if [ ! -d "$VENV" ]; then
  echo "ERROR: $VENV not found. Run:  bash llm/install_ipex_llm.sh" >&2
  exit 1
fi

# default model if the caller passed none
case " $* " in
  *" --model "*) ARGS=("$@") ;;
  *) ARGS=(--model "$DEFAULT_MODEL" "$@") ;;
esac

# shellcheck disable=SC1091
source "$VENV/bin/activate"
# shellcheck disable=SC1091
source "$REPO_ROOT/llm/xpu_runtime.env"

echo "== running LLM tests =="
echo "   model args: ${ARGS[*]}"
echo "   (first run per model downloads weights + compiles kernels; be patient)"
echo
exec python "$REPO_ROOT/llm/llm_bench.py" "${ARGS[@]}"
