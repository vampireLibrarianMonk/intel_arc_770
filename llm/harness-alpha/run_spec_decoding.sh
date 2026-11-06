#!/usr/bin/env bash
# run_spec_decoding.sh — does speculative decoding raise tok/s on the A770 (Vulkan)?
#
# Why: token generation here is memory-bandwidth-bound (every dense model moves ~200 GB/s
# regardless of size; see llama-bench pp/tg in reports/). Speculative decoding verifies several
# drafted tokens per pass over the weights, so it attacks exactly that limit. Greedy
# speculation should be lossless — so we also check the task scores did not change.
#
# Same harness, hard task set, greedy, ctx 4096, Vulkan; ONLY the speculation flags vary
# (AGENTS.md apples-to-apples). Each variant is its own candidate row / JSON.
#
# Usage:  bash llm/harness-alpha/run_spec_decoding.sh            # all variants
#         VARIANTS="14b-draft8 7b-draft4" bash llm/harness-alpha/run_spec_decoding.sh
set -uo pipefail
HA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HA_DIR/setup/common.sh"

STATUS="$PREFIX/SPEC_STATUS.txt"
note() { printf '%s | %s\n' "$(date '+%F %T')" "$*" | tee -a "$STATUS"; }
Q7="$MODELS_DIR/Qwen2.5-7B-Instruct-Q4_K_M.gguf"
Q14="$MODELS_DIR/Qwen2.5-14B-Instruct-Q4_K_M.gguf"
DSL="$MODELS_DIR/DeepSeek-Coder-V2-Lite-Instruct-Q4_K_M.gguf"
DRAFT="$MODELS_DIR/Qwen2.5-0.5B-Instruct-Q8_0.gguf"
D="--spec-type draft-simple -md $DRAFT --spec-draft-ngl 999"

# name | target model | extra llama-server flags
VARIANT_TABLE=(
  # same-day, no-speculation controls: measure run-to-run noise in scores AND tok/s
  "14b-base|$Q14|"
  "14b-base2|$Q14|"
  "7b-base|$Q7|"
  "14b-draft4|$Q14|$D --spec-draft-n-max 4"
  "14b-draft3|$Q14|$D --spec-draft-n-max 3"
  "14b-draft5|$Q14|$D --spec-draft-n-max 5"
  "14b-draft4-faoff|$Q14|$D --spec-draft-n-max 4 -fa off --cache-ram 0"
  "7b-draft4-faoff|$Q7|$D --spec-draft-n-max 4 -fa off --cache-ram 0"
  "14b-faoff|$Q14|-fa off --cache-ram 0"
  "14b-draft8|$Q14|$D --spec-draft-n-max 8"
  "7b-draft4|$Q7|$D --spec-draft-n-max 4"
  "7b-draft8|$Q7|$D --spec-draft-n-max 8"
  "14b-ngram-mod|$Q14|--spec-type ngram-mod"
  "14b-ngram-simple|$Q14|--spec-type ngram-simple"
  "7b-ngram-mod|$Q7|--spec-type ngram-mod"
  "dsl-ngram-mod|$DSL|--spec-type ngram-mod"
)

: >> "$STATUS"
note "spec-decoding experiment started (pid $$)"
for row in "${VARIANT_TABLE[@]}"; do
  IFS='|' read -r name model flags <<< "$row"
  if [ -n "${VARIANTS:-}" ] && [[ " $VARIANTS " != *" $name "* ]]; then continue; fi
  [ -f "$model" ] || { note "$name: SKIP (missing $model)"; continue; }
  note "=== $name :: $(basename "$model") :: $flags ==="
  if CANDIDATE_SUFFIX="-spec-$name" LLAMACPP_MODEL="$model" TASK_SET=hard \
       LLAMACPP_EXTRA_FLAGS="$flags" \
       timeout 1500 bash "$HA_DIR/run/run_llamacpp.sh" vulkan \
       >>"$LOG_DIR/spec_${name}.log" 2>&1; then
    note "$name: OK"
  else
    note "$name: FAILED (see logs/spec_${name}.log)"
  fi
  sleep 3
done
note "spec-decoding experiment finished"
