#!/usr/bin/env bash
# run_all.sh — run every ready candidate through the shared benchmark, sequentially.
#
# Each candidate: start its server, confirm the A770 is used (fdinfo probe), run the scored
# task set, stop the server. Skips candidates whose prerequisites aren't ready yet, so it's
# safe to run early and re-run later. Writes a compact RUN_STATUS.txt after each candidate.
#
# Launch durably:
#   systemd-run --user --unit=ha-run --working-directory="$PWD" \
#       bash llm/harness-alpha/run_all.sh
# Watch:  tail -f artifacts/harness-alpha/RUN_STATUS.txt
set -uo pipefail
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/setup/common.sh"

HA_DIR="$REPO_ROOT/llm/harness-alpha"
RUN_STATUS="$PREFIX/RUN_STATUS.txt"
stamp() { date '+%Y-%m-%d %H:%M:%S'; }
note() { printf '%s | %s\n' "$(stamp)" "$*" | tee -a "$RUN_STATUS"; }

: > "$RUN_STATUS"
note "run_all started (pid $$)"

# ---- 1. llama.cpp Vulkan (needs GGUF + vulkan build) ----
if [ -f "$MODEL_PATH" ] && [ -x "$BUILD_DIR/llama.cpp/build-vulkan/bin/llama-server" ]; then
  note "=== llamacpp-vulkan: running ==="
  bash "$HA_DIR/run/run_llamacpp.sh" vulkan >>"$LOG_DIR/run_vulkan.log" 2>&1 \
    && note "llamacpp-vulkan: OK" || note "llamacpp-vulkan: FAILED (see logs/run_vulkan.log)"
else
  note "llamacpp-vulkan: SKIP (model or build not ready)"
fi

# ---- 2. llama.cpp SYCL (needs GGUF + sycl build) ----
if [ -f "$MODEL_PATH" ] && [ -x "$BUILD_DIR/llama.cpp/build-sycl/bin/llama-server" ]; then
  note "=== llamacpp-sycl: running ==="
  bash "$HA_DIR/run/run_llamacpp.sh" sycl >>"$LOG_DIR/run_sycl.log" 2>&1 \
    && note "llamacpp-sycl: OK" || note "llamacpp-sycl: FAILED (see logs/run_sycl.log)"
else
  note "llamacpp-sycl: SKIP (model or sycl build not ready)"
fi

# ---- 3. LM Studio (needs AppImage + GGUF) ----
if [ -f "$PREFIX/tools/LM-Studio.AppImage" ] && [ -f "$MODEL_PATH" ]; then
  note "=== lmstudio: running ==="
  bash "$HA_DIR/run/run_lmstudio.sh" >>"$LOG_DIR/run_lmstudio.log" 2>&1 \
    && note "lmstudio: OK" || note "lmstudio: FAILED (see logs/run_lmstudio.log)"
else
  note "lmstudio: SKIP (AppImage or model not ready)"
fi

# ---- 4. IPEX-LLM (needs 7B HF weights) ----
HF_7B_DIR="$HOME/.cache/huggingface/hub/models--Qwen--Qwen2.5-7B-Instruct"
if [ -n "$(ls "$HF_7B_DIR"/snapshots/*/model-00004-of-00004.safetensors 2>/dev/null)" ]; then
  note "=== ipex-llm: running ==="
  bash "$HA_DIR/run/run_ipex.sh" >>"$LOG_DIR/run_ipex.log" 2>&1 \
    && note "ipex-llm: OK" || note "ipex-llm: FAILED (see logs/run_ipex.log)"
else
  note "ipex-llm: SKIP (7B HF weights not ready)"
fi

# ---- aggregate whatever ran ----
note "=== aggregating ==="
"$REPO_ROOT/.venv-llm/bin/python" "$HA_DIR/aggregate.py" >>"$RUN_STATUS" 2>&1 || true
note "run_all COMPLETE"
