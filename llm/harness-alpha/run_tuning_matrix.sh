#!/usr/bin/env bash
# run_tuning_matrix.sh — sweep llama.cpp Vulkan tuning levers on the Arc A770.
#
# Each variant is a SINGLE controlled change from the verified baseline (full GPU offload,
# ctx 4096, default flags → ~41 tok/s). The shared benchmark driver and task set are held
# fixed (AGENTS.md apples-to-apples rule); only llama-server launch flags vary. Every variant
# is recorded as its own candidate id so aggregate.py lists it as a distinct row.
#
# Usage:
#   bash llm/harness-alpha/run_tuning_matrix.sh [backend]      # backend defaults to vulkan
#
# Durable launch (survives disconnects):
#   systemd-run --user --unit=ha-tune --working-directory="$PWD" \
#       bash llm/harness-alpha/run_tuning_matrix.sh
#   tail -f artifacts/harness-alpha/TUNING_STATUS.txt
#
# Levers tested (see reports/tuning_matrix_plan.md for rationale):
#   baseline        defaults (control; reproduces the ~41 tok/s result)
#   fa-on           -fa on                       force flash attention
#   fa-kvq8         -fa on -ctk q8_0 -ctv q8_0   flash attn + 8-bit KV cache
#   ub256           -ub 256                      smaller physical batch
#   ub1024          -ub 1024                     larger physical batch
#   fa-kvq8-ub256   combined best-guess          stack the winners
set -uo pipefail

BACKEND="${1:-vulkan}"
HA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HA_DIR/setup/common.sh"

STATUS="$PREFIX/TUNING_STATUS.txt"
stamp() { date '+%Y-%m-%d %H:%M:%S'; }
note() { printf '%s | %s\n' "$(stamp)" "$*" | tee -a "$STATUS"; }

BIN="$BUILD_DIR/llama.cpp/build-$BACKEND/bin/llama-server"
[ -x "$BIN" ] || die "llama-server for '$BACKEND' not built at $BIN"
[ -f "$MODEL_PATH" ] || die "shared model missing: $MODEL_PATH"

: > "$STATUS"
note "tuning matrix started (pid $$, backend=$BACKEND)"

# variant_id  ->  extra flags  (empty = baseline control)
run_variant() {
  local suffix="$1"; shift
  local flags="$*"
  note "=== variant '${BACKEND}${suffix}' : flags [${flags:-<defaults>}] ==="
  CANDIDATE_SUFFIX="$suffix" LLAMACPP_EXTRA_FLAGS="$flags" \
    bash "$HA_DIR/run/run_llamacpp.sh" "$BACKEND" \
      >>"$LOG_DIR/tune_${BACKEND}${suffix}.log" 2>&1 \
    && note "variant '${BACKEND}${suffix}': OK" \
    || note "variant '${BACKEND}${suffix}': FAILED (see logs/tune_${BACKEND}${suffix}.log)"
  # give the GPU/VRAM a moment to settle before the next server starts
  sleep 3
}

run_variant "-baseline"      ""
run_variant "-fa-on"         "-fa on"
run_variant "-fa-kvq8"       "-fa on -ctk q8_0 -ctv q8_0"
run_variant "-ub256"         "-ub 256"
run_variant "-ub1024"        "-ub 1024"
run_variant "-fa-kvq8-ub256" "-fa on -ctk q8_0 -ctv q8_0 -ub 256"

note "=== aggregating ==="
python3 "$HA_DIR/aggregate.py" >>"$STATUS" 2>&1 || true
note "tuning matrix COMPLETE"
