#!/usr/bin/env bash
# run_ipex.sh — benchmark the incumbent IPEX-LLM harness through the shared driver.
# Starts ipex_server.py (OpenAI-compatible) on the XPU, confirms GPU use, runs bench_openai.py.
set -euo pipefail

HA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$HA_DIR/../.." && pwd)"
VENV="$REPO_ROOT/.venv-llm"
MODEL="${IPEX_MODEL:-Qwen/Qwen2.5-7B-Instruct}"
PORT="${IPEX_PORT:-8099}"
LOG_DIR="$REPO_ROOT/artifacts/harness-alpha/logs"
mkdir -p "$LOG_DIR"

[ -d "$VENV" ] || { echo "ERROR: $VENV missing; run llm/install_ipex_llm.sh" >&2; exit 1; }
# shellcheck disable=SC1091
source "$VENV/bin/activate"
# shellcheck disable=SC1091
source "$REPO_ROOT/llm/xpu_runtime.env"

echo "== IPEX-LLM candidate =="
echo "   model: $MODEL  port: $PORT"

# start server
python -u "$HA_DIR/run/ipex_server.py" --model "$MODEL" --port "$PORT" \
  > "$LOG_DIR/ipex_server.log" 2>&1 &
SRV=$!
trap 'kill $SRV 2>/dev/null || true' EXIT

# wait for "serving on" (model load can take a while on first run)
echo "   waiting for model load..."
for _ in $(seq 1 600); do
  grep -q "serving on" "$LOG_DIR/ipex_server.log" 2>/dev/null && break
  kill -0 $SRV 2>/dev/null || { echo "server died:"; tail -20 "$LOG_DIR/ipex_server.log"; exit 1; }
  sleep 2
done

# confirm GPU use
echo "   GPU check:"
bash "$HA_DIR/gpu_probe.sh" "$SRV" || echo "   (warning: GPU probe did not confirm device-local memory)"

# run the shared benchmark
python -u "$HA_DIR/bench_openai.py" \
  --base-url "http://127.0.0.1:$PORT/v1" \
  --model "$MODEL" \
  --candidate "ipex-llm"
