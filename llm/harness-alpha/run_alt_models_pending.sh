#!/usr/bin/env bash
# run_alt_models_pending.sh — resume the non-Qwen sweep for ONLY the models not yet scored.
#
# Phi-3.5-mini and Llama-3.1-8B are already benchmarked (see reports/alt_models_comparison.md),
# so re-running them wastes ~4h of GPU time. This driver benchmarks exactly the three pending
# models, reusing the SAME fetcher, runner, flags, task set, and candidate suffixes as
# run_alt_models.sh so results stay apples-to-apples (AGENTS.md).
#
# Auth: get_model_generic.sh reads HF_TOKEN / HUGGING_FACE_HUB_TOKEN from the environment and
# sends it as a Bearer header (value never logged). Export it before launching; do not hardcode.
#
# Usage:
#   set -a; . ./.env; set +a; export HUGGING_FACE_HUB_TOKEN="$HF_TOKEN"
#   systemd-run --user --unit=ha-alt-pending --working-directory="$PWD" \
#       --setenv=HF_TOKEN --setenv=HUGGING_FACE_HUB_TOKEN \
#       bash llm/harness-alpha/run_alt_models_pending.sh vulkan
#   tail -f artifacts/harness-alpha/ALT_STATUS.txt
set -uo pipefail
HA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HA_DIR/setup/common.sh"

BACKEND="${1:-vulkan}"
TASK_SET="${TASK_SET:-hard}"
STATUS="$PREFIX/ALT_STATUS.txt"
GT=/sys/class/drm/card1/gt/gt0
stamp() { date '+%Y-%m-%d %H:%M:%S'; }
note() { printf '%s | %s\n' "$(stamp)" "$*" | tee -a "$STATUS"; }

# Pending only. repo | file | size_bytes | sha256 | candidate-suffix
# (metadata identical to run_alt_models.sh — the authoritative HF LFS values.)
MODELS=(
  "bartowski/gemma-2-9b-it-GGUF|gemma-2-9b-it-Q4_K_M.gguf|5761057728|13b2a7b4115bbd0900162edcebe476da1ba1fc24e718e8b40d32f6e300f56dfe|-gemma2-9b"
  "bartowski/Mistral-Nemo-Instruct-2407-GGUF|Mistral-Nemo-Instruct-2407-Q4_K_M.gguf|7477208192|7c1a10d202d8788dbe5628dc962254d10654c853cae6aaeca0618f05490d4a46|-mistral-nemo-12b"
  "bartowski/DeepSeek-Coder-V2-Lite-Instruct-GGUF|DeepSeek-Coder-V2-Lite-Instruct-Q4_K_M.gguf|10364416768|603bd3f8a0281d16571da7c08bd661ee17ff0d1be6fcbd1b42242da257ef0bb8|-deepseek-coder-v2-lite"
)

note "alt-models PENDING resume started (pid $$, backend=$BACKEND, task_set=$TASK_SET)"

for row in "${MODELS[@]}"; do
  IFS='|' read -r repo file size sha suffix <<< "$row"
  note "=== $file (candidate ${BACKEND}${suffix}, task_set=$TASK_SET) ==="

  if ! bash "$HA_DIR/setup/get_model_generic.sh" "$repo" "$file" "$size" "$sha" \
        >>"$LOG_DIR/fetch_${suffix}.log" 2>&1; then
    note "$file: FETCH FAILED (see logs/fetch_${suffix}.log) — skipping"
    continue
  fi

  ( for _ in $(seq 1 1200); do cat "$GT/rps_act_freq_mhz" 2>/dev/null; sleep 0.5; done \
      > "$LOG_DIR/clk_${suffix}.log" 2>&1 ) &
  SAMPLER=$!

  if CANDIDATE_SUFFIX="$suffix" LLAMACPP_MODEL="$MODELS_DIR/$file" TASK_SET="$TASK_SET" \
      bash "$HA_DIR/run/run_llamacpp.sh" "$BACKEND" \
        >>"$LOG_DIR/alt_${suffix}.log" 2>&1; then
    kill "$SAMPLER" 2>/dev/null || true
    peak="$(sort -n "$LOG_DIR/clk_${suffix}.log" 2>/dev/null | tail -1)"
    note "$file: OK (peak GPU clock ${peak:-?} MHz)"
  else
    kill "$SAMPLER" 2>/dev/null || true
    note "$file: BENCH FAILED (see logs/alt_${suffix}.log)"
  fi
  sleep 3
done

note "=== aggregating ==="
python3 "$HA_DIR/aggregate.py" >>"$STATUS" 2>&1 || true
note "alt-models PENDING resume COMPLETE"
