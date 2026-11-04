#!/usr/bin/env bash
# llamacpp_vulkan.sh — build llama.cpp with the Vulkan backend for the Arc A770.
# No oneAPI needed: uses stock gcc + the system Vulkan loader/headers (libvulkan-dev).
# Build output: artifacts/harness-alpha/build/llama.cpp/build-vulkan/bin/.
#
# CRITICAL — glslc version gates Q4 throughput. llama.cpp probes glslc at configure time for
# which SPIR-V extensions it can compile. Ubuntu 24.04's stock shaderc (2023.8) CANNOT compile
# GL_EXT_integer_dot_product (the quantized-matmul accelerator) or bfloat16/coopmat2, so the
# Vulkan backend silently falls back to a slower path — measured ~27 tok/s vs ~42 tok/s on the
# A770 with Qwen2.5-7B Q4_K_M (a 32% loss). Fix: install LunarG's shaderc >= 2025.x. This
# script checks and refuses to build with a too-old glslc rather than produce a slow binary.
# See reports/data/baseline-24.04-kernel6.8/vulkan_baseline.md for the full root-cause.
set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

SRC="$BUILD_DIR/llama.cpp"
[ -d "$SRC" ] || die "llama.cpp not cloned at $SRC"
OUT="$SRC/build-vulkan"

# --- glslc capability gate -------------------------------------------------
# Compile a tiny shader that REQUIRES GL_EXT_integer_dot_product; if glslc rejects it, the
# toolchain is too old and the resulting llama.cpp binary would be ~32% slower on Q4 models.
command -v glslc >/dev/null || die "glslc not found. Install LunarG shaderc (noble repo): \
add deb https://packages.lunarg.com/vulkan noble main, then apt install shaderc (>=2025.x). \
Stock Ubuntu shaderc 2023.8 is too old and halves Q4 throughput on the A770."
probe="$(mktemp --suffix=.comp)"
cat > "$probe" <<'GLSL'
#version 450
#extension GL_EXT_integer_dot_product : require
void main() { int r = dotPacked4x8EXT(1, 2); }
GLSL
if ! glslc -fshader-stage=compute "$probe" -o /dev/null 2>/dev/null; then
  rm -f "$probe"
  die "glslc ($(glslc --version 2>&1 | head -1)) cannot compile GL_EXT_integer_dot_product. \
This is the Ubuntu 24.04 stock-shaderc trap: it builds but runs ~32% slower on Q4. \
Install LunarG shaderc >=2025.x (noble repo) and re-run. See vulkan_baseline.md."
fi
rm -f "$probe"
log "glslc OK: $(glslc --version 2>&1 | head -1) (integer_dot_product supported)"

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
