#!/usr/bin/env bash
# run_openvino.sh — benchmark OpenVINO GenAI (GPU) through the shared driver.
#
#   OV_MODEL=<IR dir or .gguf> [CANDIDATE_SUFFIX=-x] [TASK_SET=hard] [OV_PROPS="K=V K2=V2"] \
#     bash run_openvino.sh
#
# Needs the Intel compute runtime (NEO + Level Zero) so OpenVINO's GPU plugin sees the A770,
# and .venv-ov (pinned openvino-genai 2026.4.1.0). Same bench_openai.py as every candidate.
set -euo pipefail
HA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$HA_DIR/../.." && pwd)"
VENV="$REPO_ROOT/.venv-ov"
MODEL="${OV_MODEL:?set OV_MODEL to an OpenVINO IR dir or a .gguf}"
PORT="${OV_PORT:-8098}"
CANDIDATE="openvino-gpu${CANDIDATE_SUFFIX:-}"
LOG_DIR="$REPO_ROOT/artifacts/harness-alpha/logs"
SLOG="$LOG_DIR/${CANDIDATE}_server.log"
mkdir -p "$LOG_DIR"
[ -x "$VENV/bin/python" ] || { echo "ERROR: $VENV missing" >&2; exit 1; }

PROP_ARGS=()
for kv in ${OV_PROPS:-}; do PROP_ARGS+=(--prop "$kv"); done

echo "== $CANDIDATE :: $MODEL ${OV_PROPS:-} =="
"$VENV/bin/python" -u "$HA_DIR/run/ov_server.py" --model "$MODEL" --port "$PORT" \
  "${PROP_ARGS[@]}" > "$SLOG" 2>&1 &
SRV=$!
trap 'kill $SRV 2>/dev/null || true' EXIT
for _ in $(seq 1 600); do
  grep -q "serving on" "$SLOG" 2>/dev/null && break
  kill -0 $SRV 2>/dev/null || { echo "server died:"; tail -20 "$SLOG"; exit 1; }
  sleep 1
done
grep -E "loaded in" "$SLOG" || true

"$VENV/bin/python" -u "$HA_DIR/bench_openai.py" \
  --base-url "http://127.0.0.1:$PORT/v1" \
  --model "$(basename "$MODEL")" \
  --candidate "$CANDIDATE" \
  --task-set "${TASK_SET:-hard}"
