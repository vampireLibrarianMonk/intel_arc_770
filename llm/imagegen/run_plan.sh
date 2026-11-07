#!/usr/bin/env bash
# run_plan.sh — plan phase: start a local LLM, turn STORY + BIBLE into OUT/scenes.json, stop the LLM.
#
#   bash llm/imagegen/run_plan.sh <story.md> <bible.json> <out_dir>
#   LLM_FILE=gpt-oss-20b-MXFP4.gguf LLM_FLAGS="--reasoning-effort low" bash llm/imagegen/run_plan.sh ...
#
# Default LLM is Llama-3.1-8B (fast, follows format instructions well in eval-v2). The server is
# stopped before this script returns, so the GPU is free for the render phase.
set -uo pipefail
STORY="${1:?story.md}"; BIBLE="${2:?bible.json}"; OUT="${3:?out dir}"
HA="$(cd "$(dirname "${BASH_SOURCE[0]}")/../harness-alpha" && pwd)"
IMG="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HA/setup/common.sh"
LLM_FILE="${LLM_FILE:-Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf}"
PORT="${PLAN_PORT:-8090}"
SLOG="$LOG_DIR/imagegen_plan_server.log"
mkdir -p "$OUT"

# shellcheck disable=SC2086
"$BUILD_DIR/llama.cpp/build-vulkan/bin/llama-server" -m "$MODELS_DIR/$LLM_FILE" --port "$PORT" \
  --host 127.0.0.1 -ngl 999 -c 8192 -np 1 --no-webui ${LLM_FLAGS:-} > "$SLOG" 2>&1 &
SRV=$!
trap 'kill $SRV 2>/dev/null; wait $SRV 2>/dev/null' EXIT
for _ in $(seq 1 300); do
  grep -q "listening on" "$SLOG" 2>/dev/null && break
  kill -0 $SRV 2>/dev/null || { echo "LLM server died:"; tail -20 "$SLOG"; exit 1; }
  sleep 1
done
python3 "$IMG/illustrate.py" plan --story "$STORY" --bible "$BIBLE" --out "$OUT" \
  --llm-url "http://127.0.0.1:$PORT/v1"
