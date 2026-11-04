#!/usr/bin/env bash
# run_model_sweep.sh — benchmark several GGUF models on the A770 Vulkan path.
#
# For the stated goal (creative writing + Python coding assistance) raw tok/s is not the only
# axis: a bigger or coding-specialized model may give better output at still-usable speed.
# This sweep holds the backend, flags, task set, and driver fixed and varies ONLY the model,
# so throughput + VRAM + scored quality are comparable across models.
#
# Each model: verify (sha256-gated download) -> run shared benchmark as its own candidate
# -> record median tok/s, coding pass rate, writing constraints, and sampled peak GPU clock.
#
# Usage:
#   bash llm/harness-alpha/run_model_sweep.sh
#
# Durable:
#   systemd-run --user --unit=ha-sweep --working-directory="$PWD" \
#       bash llm/harness-alpha/run_model_sweep.sh
#   tail -f artifacts/harness-alpha/SWEEP_STATUS.txt
set -uo pipefail
HA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HA_DIR/setup/common.sh"

BACKEND="${1:-vulkan}"
STATUS="$PREFIX/SWEEP_STATUS.txt"
GT=/sys/class/drm/card1/gt/gt0
stamp() { date '+%Y-%m-%d %H:%M:%S'; }
note() { printf '%s | %s\n' "$(stamp)" "$*" | tee -a "$STATUS"; }

# model table: repo | file | size_bytes | sha256 | candidate-suffix
# sizes + sha256 are authoritative HF LFS metadata (verified, not guessed — AGENTS.md).
MODELS=(
  "bartowski/Qwen2.5-7B-Instruct-GGUF|Qwen2.5-7B-Instruct-Q4_K_M.gguf|4683074240|65b8fcd92af6b4fefa935c625d1ac27ea29dcb6ee14589c55a8f115ceaaa1423|-7b"
  "bartowski/Qwen2.5-Coder-7B-Instruct-GGUF|Qwen2.5-Coder-7B-Instruct-Q4_K_M.gguf|4683074336|1664fccab734674a50763490a8c6931b70e3f2f8ec10031b54806d30e5f956b6|-coder7b"
  "bartowski/Qwen2.5-14B-Instruct-GGUF|Qwen2.5-14B-Instruct-Q4_K_M.gguf|8988110976|e47ad95dad6ff848b431053b375adb5d39321290ea2c638682577dafca87c008|-14b"
)

: > "$STATUS"
note "model sweep started (pid $$, backend=$BACKEND)"

for row in "${MODELS[@]}"; do
  IFS='|' read -r repo file size sha suffix <<< "$row"
  note "=== model '$file' (candidate ${BACKEND}${suffix}) ==="

  # 1. fetch + verify
  if ! bash "$HA_DIR/setup/get_model_generic.sh" "$repo" "$file" "$size" "$sha" \
        >>"$LOG_DIR/fetch_${suffix}.log" 2>&1; then
    note "model '$file': FETCH FAILED (see logs/fetch_${suffix}.log) — skipping"
    continue
  fi

  # 2. benchmark, sampling GPU clock in the background
  ( for _ in $(seq 1 600); do cat "$GT/rps_act_freq_mhz" 2>/dev/null; sleep 0.5; done \
      > "$LOG_DIR/clk_${suffix}.log" 2>&1 ) &
  SAMPLER=$!

  if CANDIDATE_SUFFIX="$suffix" LLAMACPP_MODEL="$MODELS_DIR/$file" \
      bash "$HA_DIR/run/run_llamacpp.sh" "$BACKEND" \
        >>"$LOG_DIR/sweep_${suffix}.log" 2>&1; then
    kill "$SAMPLER" 2>/dev/null || true
    peak="$(sort -n "$LOG_DIR/clk_${suffix}.log" 2>/dev/null | tail -1)"
    note "model '$file': OK (peak GPU clock ${peak:-?} MHz)"
  else
    kill "$SAMPLER" 2>/dev/null || true
    note "model '$file': BENCH FAILED (see logs/sweep_${suffix}.log)"
  fi
  sleep 3
done

note "=== aggregating ==="
python3 "$HA_DIR/aggregate.py" >>"$STATUS" 2>&1 || true
note "model sweep COMPLETE"
