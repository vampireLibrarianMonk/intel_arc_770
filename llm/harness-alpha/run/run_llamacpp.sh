#!/usr/bin/env bash
# run_llamacpp.sh — benchmark a llama.cpp build (SYCL or Vulkan) through the shared driver.
#
#   bash run_llamacpp.sh sycl      # uses build-sycl/
#   bash run_llamacpp.sh vulkan    # uses build-vulkan/
#
# Starts llama-server with full GPU offload, confirms the Arc A770 is actually used (VRAM
# via fdinfo), then runs bench_openai.py against it.
#
# Tuning hooks (optional, all backward compatible — defaults reproduce the 41 tok/s baseline):
#   LLAMACPP_EXTRA_FLAGS   extra args appended to the llama-server command line
#                          (e.g. "-fa on -ctk q8_0 -ctv q8_0 -ub 256")
#   CANDIDATE_SUFFIX       appended to the candidate id so a tuned run is recorded as its own
#                          row (e.g. CANDIDATE_SUFFIX=-fa-kvq8 -> candidate "llamacpp-vulkan-fa-kvq8")
#   LLAMACPP_CTX           context size (default 4096)
#   LLAMACPP_MODEL         absolute path to a GGUF, overriding the shared model (model sweep)
set -euo pipefail

BACKEND="${1:?usage: run_llamacpp.sh <sycl|vulkan>}"
HA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$HA_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$HA_DIR/setup/common.sh"

BIN="$BUILD_DIR/llama.cpp/build-$BACKEND/bin/llama-server"
[ -x "$BIN" ] || die "llama-server for '$BACKEND' not built at $BIN"
# LLAMACPP_MODEL overrides the shared model (used by the model sweep). Defaults to the
# canonical shared GGUF from common.sh so existing callers are unaffected.
MODEL_PATH="${LLAMACPP_MODEL:-$MODEL_PATH}"
[ -f "$MODEL_PATH" ] || die "shared model missing: $MODEL_PATH (run setup/get_model.sh)"

PORT="${LLAMACPP_PORT:-8080}"
CANDIDATE="llamacpp-$BACKEND${CANDIDATE_SUFFIX:-}"
CTX="${LLAMACPP_CTX:-4096}"
read -r -a EXTRA_FLAGS <<< "${LLAMACPP_EXTRA_FLAGS:-}"
SLOG="$LOG_DIR/${CANDIDATE}_server.log"

# For SYCL we need the oneAPI + venv-xpu runtime libraries on the path at RUN time too.
if [ "$BACKEND" = "sycl" ]; then
  set +u
  # shellcheck disable=SC1091
  source "${ONEAPI_ROOT:-/opt/intel/oneapi}/setvars.sh" --force >/dev/null 2>&1 || true
  set -u
fi
# A770 per-allocation cap lift + SYCL device selection (harmless for Vulkan).
export NEOReadDebugKeys=1 AllowUnrestrictedSize=1
export ONEAPI_DEVICE_SELECTOR="level_zero:0"
export ONEDNN_VERBOSE=0
# Persist SYCL JIT kernels so first-run compile (which can exceed 5 min) is paid once.
# EXCEPTION: oneAPI 2026.2's libsycl.so.9 persistent device-code cache
# (PersistentDeviceCodeCache::getItemFromDisc -> getSortedImages) SEGVs on this stack during
# the first GPU kernel launch (confirmed by gdb backtrace). Disabling the persistent cache
# avoids that code path entirely — SYCL then loads and generates correctly. Trade-off: kernels
# recompile each run (slower first token). See reports/sycl_fix_plan.md.
if [ "$BACKEND" = "sycl" ]; then
  export SYCL_CACHE_PERSISTENT=0
else
  export SYCL_CACHE_PERSISTENT=1
fi

# SYCL first-run kernel compilation is slow; give it a longer window than Vulkan.
WAIT_SECS=600
[ "$BACKEND" = "vulkan" ] && WAIT_SECS=300

log "starting $CANDIDATE server on :$PORT (full GPU offload)"
# -ngl 999 => offload all layers to GPU; -c context; --no-webui keeps it headless.
# EXTRA_FLAGS lets the tuning matrix vary flash-attn, KV cache type, ubatch, etc. without
# forking this runner (shared driver stays identical — AGENTS.md apples-to-apples rule).
log "launch flags: -ngl 999 -c $CTX --no-webui ${EXTRA_FLAGS[*]:-}"
"$BIN" --model "$MODEL_PATH" --port "$PORT" --host 127.0.0.1 \
  -ngl 999 -c "$CTX" --no-webui "${EXTRA_FLAGS[@]}" > "$SLOG" 2>&1 &
SRV=$!
trap 'kill $SRV 2>/dev/null || true' EXIT

log "waiting for server to come up ..."
for _ in $(seq 1 "$WAIT_SECS"); do
  grep -qE "listening on|server is listening|HTTP server listening|all slots are idle" "$SLOG" 2>/dev/null && break
  kill -0 $SRV 2>/dev/null || { echo "server died:"; tail -30 "$SLOG"; exit 1; }
  sleep 1
done

# confirm GPU + how many layers actually offloaded (llama.cpp logs this)
log "offload report:"
grep -iE "offloaded|assigned to device|using device|Arc|Vulkan0|load_tensors" "$SLOG" | tail -6 || true
log "GPU check (fdinfo):"
bash "$HA_DIR/gpu_probe.sh" "$SRV" || log "WARNING: GPU probe did not confirm device-local memory"

log "running shared benchmark ..."
python3 -u "$HA_DIR/bench_openai.py" \
  --base-url "http://127.0.0.1:$PORT/v1" \
  --model "$(basename "$MODEL_PATH")" \
  --candidate "$CANDIDATE"