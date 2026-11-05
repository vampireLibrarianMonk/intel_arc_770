#!/usr/bin/env bash
# run_alt_models.sh — download + benchmark non-Qwen open-weight models on the A770.
#
# Answers "are we stuck with Qwen?" empirically: pulls alternative families that fit 16 GiB
# at Q4 and runs each through the HARD task set (the one that actually discriminates quality)
# plus the alpha set for continuity. Backend/flags/driver held fixed; only the model varies.
#
# Each model: sha256-gated fetch -> benchmark (hard set) as its own candidate, sampling peak
# GPU clock. Durable + resumable (the fetcher resumes dropped connections). Safe to re-run.
#
# Usage:
#   bash llm/harness-alpha/run_alt_models.sh [backend]        # backend defaults to vulkan
#   TASK_SET=alpha bash llm/harness-alpha/run_alt_models.sh   # use the easy set instead
#
# Durable:
#   systemd-run --user --unit=ha-alt --working-directory="$PWD" \
#       bash llm/harness-alpha/run_alt_models.sh
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

# repo | file | size_bytes | sha256 | candidate-suffix
# sizes + sha256 are authoritative HF LFS metadata (verified 2026-11-05, not guessed).
# Ordered smallest-first so quick wins land before the big MoE download.
MODELS=(
  "bartowski/Phi-3.5-mini-instruct-GGUF|Phi-3.5-mini-instruct-Q4_K_M.gguf|2393232672|e4165e3a71af97f1b4820da61079826d8752a2088e313af0c7d346796c38eff5|-phi35mini"
  "bartowski/Meta-Llama-3.1-8B-Instruct-GGUF|Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf|4920739232|7b064f5842bf9532c91456deda288a1b672397a54fa729aa665952863033557c|-llama31-8b"
  "bartowski/gemma-2-9b-it-GGUF|gemma-2-9b-it-Q4_K_M.gguf|5761057728|13b2a7b4115bbd0900162edcebe476da1ba1fc24e718e8b40d32f6e300f56dfe|-gemma2-9b"
  "bartowski/Mistral-Nemo-Instruct-2407-GGUF|Mistral-Nemo-Instruct-2407-Q4_K_M.gguf|7477208192|7c1a10d202d8788dbe5628dc962254d10654c853cae6aaeca0618f05490d4a46|-mistral-nemo-12b"
  "bartowski/DeepSeek-Coder-V2-Lite-Instruct-GGUF|DeepSeek-Coder-V2-Lite-Instruct-Q4_K_M.gguf|10364416768|603bd3f8a0281d16571da7c08bd661ee17ff0d1be6fcbd1b42242da257ef0bb8|-deepseek-coder-v2-lite"
)

: > "$STATUS"
note "alt-models sweep started (pid $$, backend=$BACKEND, task_set=$TASK_SET)"

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
note "alt-models sweep COMPLETE"
