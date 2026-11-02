#!/usr/bin/env bash
# llamacpp_vulkan.sh — build llama.cpp with the Vulkan backend for the Arc A770.
# No oneAPI needed: uses stock gcc + the system Vulkan loader/headers (libvulkan-dev) and
# glslang-tools. Build output: artifacts/harness-alpha/build/llama.cpp/build-vulkan/bin/.
set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

SRC="$BUILD_DIR/llama.cpp"
[ -d "$SRC" ] || die "llama.cpp not cloned at $SRC"
OUT="$SRC/build-vulkan"

log "configuring llama.cpp (Vulkan) ..."
cmake -S "$SRC" -B "$OUT" \
  -DGGML_VULKAN=ON \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLAMA_CURL=OFF \
  -DCMAKE_C_COMPILER_LAUNCHER=ccache \
  -DCMAKE_CXX_COMPILER_LAUNCHER=ccache

log "building (this takes a few minutes) ..."
cmake --build "$OUT" --config Release -j"$(nproc)" --target llama-server llama-cli

log "built:"
ls -la "$OUT/bin/llama-server" "$OUT/bin/llama-cli"
