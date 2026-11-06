#!/usr/bin/env bash
# fetch_followup_models.sh — fetch the models needed for the follow-up experiments.
#
#   speculative decoding : Qwen2.5-0.5B-Instruct (draft for the Qwen2.5 7B/14B targets)
#   MoE candidate        : gpt-oss-20b MXFP4 (+ EAGLE3 draft head for speculative decoding)
#
# Same sha256-gated, resumable fetcher as the rest of the harness. Smallest first so the
# speculative-decoding test can start while the big MoE file is still downloading.
# sizes + sha256 are HF LFS metadata (queried 2026-11-06). Optional HF_TOKEN is honoured by
# get_model_generic.sh (never logged). Idempotent: verified files are skipped.
set -uo pipefail
HA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$HA_DIR/setup/common.sh"

MODELS=(
  "bartowski/Qwen2.5-0.5B-Instruct-GGUF|Qwen2.5-0.5B-Instruct-Q8_0.gguf|531068480|25130a98aa782284a7dabea0c23245b2fd371ed47244e79d78b8ec23245fdf96"
  "ggml-org/gpt-oss-20b-GGUF|eagle3-gpt-oss-20b-Q8_0.gguf|921488000|6955f98a701e97a8c969f3ff33be8ba17b35bd60e5ac96258d2c42d710c7d63f"
  "ggml-org/gpt-oss-20b-GGUF|gpt-oss-20b-MXFP4.gguf|12109566624|27cd6c432c7672cb812a92f611cf3ba7bbc35928262bb1e1253ff4ee6ae35901"
)
for row in "${MODELS[@]}"; do
  IFS='|' read -r repo file size sha <<< "$row"
  if bash "$HA_DIR/setup/get_model_generic.sh" "$repo" "$file" "$size" "$sha" \
       >>"$LOG_DIR/fetch_followup.log" 2>&1; then
    log "OK   $file"
  else
    log "FAIL $file (see $LOG_DIR/fetch_followup.log)"
  fi
done
log "followup fetch finished"
