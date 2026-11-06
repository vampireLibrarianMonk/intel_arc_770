#!/usr/bin/env bash
# run_eval_v2.sh — run the eval-v2 suite (coding + creative writing) against every model.
#
# 1. waits until the download/eval chain (llm/harness-alpha/run_pending_evals.sh) reports
#    COMPLETE, so every model, gpt-oss-20b included, is on disk and the GPU is free;
# 2. for each candidate: start llama-server (Vulkan, full offload, ctx 8192, 1 slot, otherwise
#    default flags so the comparison is model-vs-model), run run_eval.py, stop the server;
# 3. blind-judge all writing samples with each available judge model;
# 4. copy raw data to reports/data/eval-v2/ and build reports/eval_v2/ (results + packet).
# Resumable: a candidate or judge that already has output is skipped (FORCE=1 to redo).
#
#   systemd-run --user --unit=eval-v2 --working-directory="$PWD" bash llm/eval-v2/run_eval_v2.sh
#   SKIP_WAIT=1 ...   start immediately        SMOKE=1 ...   2 tasks, Phi only, separate dirs
set -uo pipefail
EV="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$EV/../.." && pwd)"
# shellcheck disable=SC1091
source "$REPO/llm/harness-alpha/setup/common.sh"
SRV_BIN="$BUILD_DIR/llama.cpp/build-vulkan/bin/llama-server"
P=8090

if [ "${SMOKE:-0}" = 1 ]; then
  OUT="$REPO/artifacts/eval-v2-smoke"; LIMIT="--limit 2"; SKIP_WAIT=1
else
  OUT="$REPO/artifacts/eval-v2"; LIMIT=""
fi
RES="$OUT/results"; JDG="$OUT/judgments"; LOGS="$OUT/logs"; STATUS="$OUT/STATUS.txt"
mkdir -p "$RES" "$JDG" "$LOGS"
note() { printf '%s | %s\n' "$(date '+%F %T')" "$*" | tee -a "$STATUS"; }

# name | gguf | extra server flags
CANDIDATES=(
  "phi-3.5-mini|Phi-3.5-mini-instruct-Q4_K_M.gguf|"
  "qwen2.5-7b|Qwen2.5-7B-Instruct-Q4_K_M.gguf|"
  "qwen2.5-coder-7b|Qwen2.5-Coder-7B-Instruct-Q4_K_M.gguf|"
  "llama-3.1-8b|Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf|"
  "gemma-2-9b|gemma-2-9b-it-Q4_K_M.gguf|"
  "mistral-nemo-12b|Mistral-Nemo-Instruct-2407-Q4_K_M.gguf|"
  "qwen2.5-14b|Qwen2.5-14B-Instruct-Q4_K_M.gguf|"
  "deepseek-coder-v2-lite|DeepSeek-Coder-V2-Lite-Instruct-Q4_K_M.gguf|"
  "gpt-oss-20b|gpt-oss-20b-MXFP4.gguf|--reasoning-effort low"
  # OpenVINO GenAI on the GPU (native int4 IR); served by harness-alpha/run/ov_server.py
  "qwen2.5-7b-ov-int4|ov:Qwen2.5-7B-Instruct-int4-ov|"
)
JUDGES=(
  "qwen2.5-14b|Qwen2.5-14B-Instruct-Q4_K_M.gguf|"
  "gpt-oss-20b|gpt-oss-20b-MXFP4.gguf|--reasoning-effort low"
)
if [ "${SMOKE:-0}" = 1 ]; then
  CANDIDATES=("${SMOKE_ROW:-phi-3.5-mini|Phi-3.5-mini-instruct-Q4_K_M.gguf|}")
  JUDGES=("qwen2.5-14b|Qwen2.5-14B-Instruct-Q4_K_M.gguf|")
  if [ -n "${SMOKE_ROW:-}" ]; then JUDGES=(); fi
fi

start_server() {  # $1 gguf (or ov:<IR dir name>)  $2 flags  $3 log
  if [[ "$1" == ov:* ]]; then
    "$REPO/.venv-ov/bin/python" -u "$REPO/llm/harness-alpha/run/ov_server.py" \
      --model "$REPO/artifacts/ov-models/${1#ov:}" --port $P > "$3" 2>&1 &
    SRV=$!
    for _ in $(seq 1 600); do
      grep -q "serving on" "$3" 2>/dev/null && return 0
      kill -0 $SRV 2>/dev/null || return 1
      sleep 1
    done
    return 1
  fi
  # shellcheck disable=SC2086
  "$SRV_BIN" -m "$MODELS_DIR/$1" --port $P --host 127.0.0.1 -ngl 999 -c 8192 -np 1 --no-webui $2 \
    > "$3" 2>&1 &
  SRV=$!
  for _ in $(seq 1 300); do
    grep -q "listening on" "$3" 2>/dev/null && return 0
    kill -0 $SRV 2>/dev/null || return 1
    sleep 1
  done
  return 1
}
stop_server() { kill "$SRV" 2>/dev/null; wait "$SRV" 2>/dev/null; sleep 3; }

note "eval-v2 started (pid $$, smoke=${SMOKE:-0})"
if [ "${SKIP_WAIT:-0}" != 1 ]; then
  note "waiting for download chain to finish (artifacts/harness-alpha/PENDING_STATUS.txt)"
  until grep -q "pending-evals COMPLETE" "$PREFIX/PENDING_STATUS.txt" 2>/dev/null; do sleep 120; done
  note "download chain complete"
fi

for row in "${CANDIDATES[@]}"; do
  IFS='|' read -r name file flags <<< "$row"
  if [[ "$file" == ov:* ]]; then
    [ -f "$REPO/artifacts/ov-models/${file#ov:}/openvino_model.bin" ] || { note "$name: SKIP (OV model missing)"; continue; }
  else
    [ -f "$MODELS_DIR/$file" ] || { note "$name: SKIP (model file missing)"; continue; }
  fi
  if [ -f "$RES/$name.json" ] && [ "${FORCE:-0}" != 1 ]; then note "$name: already done"; continue; fi
  note "=== $name ($file) $flags ==="
  if ! start_server "$file" "$flags" "$LOGS/server_$name.log"; then
    note "$name: SERVER FAILED (logs/server_$name.log)"; stop_server; continue
  fi
  # shellcheck disable=SC2086
  if timeout 14400 python3 "$EV/run_eval.py" --base-url "http://127.0.0.1:$P/v1" --candidate "$name" \
       --model-file "$file" --out-dir "$RES" $LIMIT > "$LOGS/eval_$name.log" 2>&1; then
    note "$name: OK $(grep -o 'SUMMARY.*' "$LOGS/eval_$name.log" | cut -c1-200)"
  else
    note "$name: EVAL FAILED (logs/eval_$name.log)"
  fi
  stop_server
done

for row in "${JUDGES[@]}"; do
  IFS='|' read -r name file flags <<< "$row"
  [ -f "$MODELS_DIR/$file" ] || { note "judge $name: SKIP (model file missing)"; continue; }
  note "=== judge $name ==="
  if ! start_server "$file" "$flags" "$LOGS/server_judge_$name.log"; then
    note "judge $name: SERVER FAILED"; stop_server; continue
  fi
  timeout 21600 python3 "$EV/judge.py" --base-url "http://127.0.0.1:$P/v1" --judge "$name" \
    --judge-model-file "$file" --results-dir "$RES" --out "$JDG/$name.jsonl" \
    > "$LOGS/judge_$name.log" 2>&1 && note "judge $name: OK" || note "judge $name: FAILED (logs/judge_$name.log)"
  stop_server
done

if [ "${SMOKE:-0}" = 1 ]; then
  REPORT="$OUT/report"
else
  REPORT="$REPO/reports/eval_v2"
  mkdir -p "$REPO/reports/data/eval-v2"
  cp "$RES"/*.json "$JDG"/*.jsonl "$REPO/reports/data/eval-v2/" 2>/dev/null
fi
python3 "$EV/make_report.py" --results-dir "$RES" --judgments-dir "$JDG" --report-dir "$REPORT" \
  --key-path "$OUT/review_key.json" >> "$STATUS" 2>&1 && note "report: $REPORT" || note "report FAILED"
note "eval-v2 COMPLETE"
