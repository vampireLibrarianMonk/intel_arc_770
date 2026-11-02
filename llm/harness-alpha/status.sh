#!/usr/bin/env bash
# status.sh — compact, single-screen status of the harness alpha prerequisites.
# Safe to call repeatedly; output is tiny (a handful of lines), never floods.
set -uo pipefail
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/setup/common.sh"

HF_7B_DIR="$HOME/.cache/huggingface/hub/models--Qwen--Qwen2.5-7B-Instruct"
mib() { awk -v b="${1:-0}" 'BEGIN{printf "%.0f", b/1048576}'; }

echo "==== harness-alpha status @ $(date '+%H:%M:%S') ===="

# fetch_all systemd unit state
if systemctl --user is-active ha-fetch >/dev/null 2>&1; then
  echo "fetch_all unit : ACTIVE (running)"
else
  st="$(systemctl --user show ha-fetch -p SubState --value 2>/dev/null || echo unknown)"
  echo "fetch_all unit : $st"
fi

# GGUF
if [ -f "$MODEL_PATH" ]; then
  echo "GGUF           : DONE ($(du -h "$MODEL_PATH" | cut -f1), verified)"
elif [ -f "$MODEL_PATH.part" ]; then
  echo "GGUF           : $(mib "$(stat -c %s "$MODEL_PATH.part")")/$(mib "$MODEL_SIZE_BYTES") MiB"
else
  echo "GGUF           : not started"
fi

# 7B HF
if [ -n "$(ls "$HF_7B_DIR"/snapshots/*/model-00004-of-00004.safetensors 2>/dev/null)" ] \
   && [ -z "$(ls "$HF_7B_DIR"/blobs/*.incomplete 2>/dev/null)" ]; then
  echo "7B-HF          : DONE"
elif [ -d "$HF_7B_DIR" ]; then
  echo "7B-HF          : partial ($(du -sh "$HF_7B_DIR" 2>/dev/null | cut -f1))"
else
  echo "7B-HF          : not started"
fi

# DPC++ compiler
if [ -n "$(ls /opt/intel/oneapi/compiler/*/bin/icpx 2>/dev/null)" ]; then
  echo "DPCPP (icpx)   : READY"
else
  echo "DPCPP (icpx)   : not installed"
fi

# built binaries
echo "llamacpp-vulkan: $([ -x "$BUILD_DIR/llama.cpp/build-vulkan/bin/llama-server" ] && echo BUILT || echo not-built)"
echo "llamacpp-sycl  : $([ -x "$BUILD_DIR/llama.cpp/build-sycl/bin/llama-server" ] && echo BUILT || echo not-built)"
echo "lmstudio       : $([ -f "$PREFIX/tools/LM-Studio.AppImage" ] && echo downloaded || echo missing)"

echo "---- last fetch_all log lines ----"
tail -n 4 "$PREFIX/STATUS.txt" 2>/dev/null || echo "(no STATUS.txt yet)"
