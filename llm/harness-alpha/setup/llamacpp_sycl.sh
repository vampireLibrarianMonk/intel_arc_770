#!/usr/bin/env bash
# llamacpp_sycl.sh — build llama.cpp with the Intel SYCL backend for the Arc A770.
# Needs the oneAPI DPC++ compiler (icpx) from /opt/intel/oneapi. Build output:
#   artifacts/harness-alpha/build/llama.cpp/build-sycl/bin/
set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

ONEAPI="${ONEAPI_ROOT:-/opt/intel/oneapi}"
[ -f "$ONEAPI/setvars.sh" ] || die "oneAPI not found at $ONEAPI (install intel-oneapi-compiler-dpcpp-cpp)"
# Intel's setvars.sh references many optional/unbound env vars and returns nonzero in places;
# under `set -eu` that aborts the script. Relax -e/-u just for the source, then restore.
set +eu
# shellcheck disable=SC1091
source "$ONEAPI/setvars.sh" --force >/dev/null 2>&1 || true
set -eu
command -v icpx >/dev/null || die "icpx not on PATH after sourcing setvars.sh"
log "using icpx: $(icpx --version | head -1)"

SRC="$BUILD_DIR/llama.cpp"
[ -d "$SRC" ] || die "llama.cpp not cloned at $SRC"
OUT="$SRC/build-sycl"

log "configuring llama.cpp (SYCL, FP16) ..."
# GGML_SYCL=ON with the Intel DPC++ compiler; target Intel GPU (Xe). FP16 is the documented
# fast path for Arc. We do NOT enable the per-allocation >4GiB flags here — the shared 7B
# Q4_K_M model's tensors are well under 4 GiB, so this build is a clean baseline.
# GGML_SYCL_DNN=OFF: the oneDNN 2026.1 GPU engine probe fails ("could not create an engine")
# on this NEO/Level-Zero stack and SEGVs during model load. Pure SYCL kernels are stable and
# the GEMM perf difference is minor for this workload; correctness/stability comes first.
# GGML_SYCL_SUPPORT_LEVEL_ZERO_API=OFF: the backend otherwise calls the Level-Zero *Sysman*
# API (zesInit / zesDeviceEnumMemoryModules) to query free VRAM during model load. On NEO
# 24.39 that path SEGVs inside libze_intel_gpu.so (confirmed by backtrace in
# get_memory_size -> query_free_memory_by_ze). Turning it OFF removes that code and uses the
# pure SYCL memory query instead, which NEO 24.39 handles correctly.
CC=icx CXX=icpx cmake -S "$SRC" -B "$OUT" \
  -DGGML_SYCL=ON \
  -DGGML_SYCL_TARGET=INTEL \
  -DGGML_SYCL_F16=ON \
  -DGGML_SYCL_DNN=OFF \
  -DGGML_SYCL_SUPPORT_LEVEL_ZERO_API=OFF \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLAMA_CURL=OFF \
  -DCMAKE_C_COMPILER=icx \
  -DCMAKE_CXX_COMPILER=icpx

log "building (this takes several minutes) ..."
cmake --build "$OUT" --config Release -j"$(nproc)" --target llama-server llama-cli

log "built:"
ls -la "$OUT/bin/llama-server" "$OUT/bin/llama-cli"
