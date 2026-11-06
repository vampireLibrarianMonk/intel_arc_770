#!/usr/bin/env bash
# run_long_prompt_ab.sh — long-prompt (~12K token) latency through llama-server:
# flash attention default vs `-fa off --cache-ram 0`.
#
# Why --cache-ram 0: with -fa off, the server's host-RAM prompt cache takes 2-3 s per request
# to save/restore slot state (seen between slot selection and launch in the server log), which
# is what made -fa off look 2x slower in the harness. With the prompt cache off it is not.
#
#   bash llm/harness-alpha/run_long_prompt_ab.sh      # results -> logs/long_prompt_ab.txt
set -uo pipefail
HA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HA_DIR/setup/common.sh"
SRV_BIN="$BUILD_DIR/llama.cpp/build-vulkan/bin/llama-server"
P=8081
for spec in "Qwen2.5-7B-Instruct|default|" "Qwen2.5-7B-Instruct|fa-off-nocache|-fa off --cache-ram 0" \
            "Qwen2.5-14B-Instruct|default|" "Qwen2.5-14B-Instruct|fa-off-nocache|-fa off --cache-ram 0"; do
  IFS='|' read -r m name fl <<< "$spec"
  slog="$LOG_DIR/lp_${m}_${name}.log"
  # shellcheck disable=SC2086
  "$SRV_BIN" -m "$MODELS_DIR/$m-Q4_K_M.gguf" --port $P --host 127.0.0.1 -ngl 999 -c 16384 -np 1 \
    --no-webui $fl > "$slog" 2>&1 &
  S=$!
  for _ in $(seq 1 120); do grep -q "listening on" "$slog" && break; sleep 1; done
  echo "== $m $name"
  python3 "$HA_DIR/long_prompt_bench.py" --base-url "http://127.0.0.1:$P/v1" --target-chars 42000 --runs 2
  kill $S; wait $S 2>/dev/null
done
echo LP_DONE
