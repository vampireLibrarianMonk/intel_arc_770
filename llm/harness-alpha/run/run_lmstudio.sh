#!/usr/bin/env bash
# run_lmstudio.sh — benchmark LM Studio (Vulkan runtime) through the shared driver.
#
# LM Studio on a headless box needs its llmster daemon running. The daemon is registered by
# running the Electron app once under a virtual display (xvfb); after that `lms` works. This
# runner ensures the daemon is up, loads the SAME shared GGUF with full GPU offload, starts
# the OpenAI-compatible server (port 1234), runs bench_openai.py, then stops the server.
set -uo pipefail
HA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$HA_DIR/setup/common.sh"

[ -f "$MODEL_PATH" ] || die "shared model missing: $MODEL_PATH"
bash "$HA_DIR/setup/lmstudio.sh" >/dev/null 2>&1 || true
LMS="$(cat "$PREFIX/tools/.lms_path" 2>/dev/null || true)"
[ -n "$LMS" ] || die "lms CLI path not found"
APPDIR="$PREFIX/tools/lmstudio/squashfs-root"
PORT="${LMSTUDIO_PORT:-1234}"
MODEL_KEY="qwen2.5-7b-instruct"   # key as registered by 'lms import'
export NEOReadDebugKeys=1 AllowUnrestrictedSize=1

# 1. ensure the llmster daemon is running (first run registers the install under xvfb)
if ! "$LMS" daemon status 2>/dev/null | grep -q "is running"; then
  log "starting LM Studio daemon under xvfb (headless first run) ..."
  setsid xvfb-run -a "$APPDIR/lm-studio" --no-sandbox >"$LOG_DIR/lmstudio_app.log" 2>&1 < /dev/null &
  for _ in $(seq 1 60); do
    "$LMS" daemon status 2>/dev/null | grep -q "is running" && break
    sleep 2
  done
fi
"$LMS" daemon status 2>/dev/null | head -1 | sed 's/^/[lms] /'

# 2. make sure the shared model is imported (copy, so other candidates keep the file)
"$LMS" ls 2>/dev/null | grep -qi "$MODEL_KEY" || \
  "$LMS" import "$MODEL_PATH" --copy -y >/dev/null 2>&1 || true

# 3. load with full GPU offload (Vulkan runtime is the selected engine on Arc)
log "loading $MODEL_KEY with full GPU offload ..."
"$LMS" load "$MODEL_KEY" --gpu max -y >/dev/null 2>&1 \
  || "$LMS" load "$MODEL_KEY" --gpu 1.0 -y >/dev/null 2>&1 \
  || log "WARNING: lms load returned nonzero"

# 4. start the OpenAI-compatible server
log "starting LM Studio server on :$PORT ..."
"$LMS" server start --port "$PORT" >/dev/null 2>&1 || true
sleep 5

# 5. GPU confirmation. fdinfo can't see Mesa/Vulkan VRAM, so rely on the daemon's own
#    loaded-model device report plus the benchmark tok/s (CPU 7B ~8 t/s, GPU ~40+ t/s).
log "loaded model device report:"
"$LMS" ps 2>/dev/null | sed 's/^/[lms ps] /' | head -8

# 6. run the shared benchmark
log "running shared benchmark ..."
"$REPO_ROOT/.venv-llm/bin/python" -u "$HA_DIR/bench_openai.py" \
  --base-url "http://127.0.0.1:$PORT/v1" \
  --model "$MODEL_KEY" \
  --candidate "lmstudio"

# 7. stop the server (leave the daemon up; cheap to reuse)
log "stopping LM Studio server ..."
"$LMS" server stop >/dev/null 2>&1 || true
