#!/usr/bin/env bash
# run_hard_suite.sh — run the HARD task set against every GGUF already on disk.
#
# No downloads: benchmarks whatever models are present in artifacts/harness-alpha/models/.
# Purpose: find out whether the harder task set (tasks_hard.py) actually discriminates model
# quality, where the alpha set saturated everything at ~4/4.
#
#   bash llm/harness-alpha/run_hard_suite.sh [backend]   # backend defaults to vulkan
set -uo pipefail
HA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HA_DIR/setup/common.sh"

BACKEND="${1:-vulkan}"
STATUS="$PREFIX/HARD_STATUS.txt"
stamp() { date '+%Y-%m-%d %H:%M:%S'; }
note() { printf '%s | %s\n' "$(stamp)" "$*" | tee -a "$STATUS"; }

# model file -> candidate suffix (only runs those present on disk)
declare -A SUFFIX=(
  ["Qwen2.5-7B-Instruct-Q4_K_M.gguf"]="-hard-7b"
  ["Qwen2.5-Coder-7B-Instruct-Q4_K_M.gguf"]="-hard-coder7b"
  ["Qwen2.5-14B-Instruct-Q4_K_M.gguf"]="-hard-14b"
)

: > "$STATUS"
note "hard-suite started (pid $$, backend=$BACKEND)"

for file in "${!SUFFIX[@]}"; do
  path="$MODELS_DIR/$file"
  [ -f "$path" ] || { note "SKIP $file (not on disk)"; continue; }
  suffix="${SUFFIX[$file]}"
  note "=== $file (candidate ${BACKEND}${suffix}) ==="
  if CANDIDATE_SUFFIX="$suffix" LLAMACPP_MODEL="$path" TASK_SET=hard \
      bash "$HA_DIR/run/run_llamacpp.sh" "$BACKEND" \
        >>"$LOG_DIR/hard_${suffix}.log" 2>&1; then
    note "$file: OK"
  else
    note "$file: FAILED (see logs/hard_${suffix}.log)"
  fi
  sleep 3
done

note "hard-suite COMPLETE"
