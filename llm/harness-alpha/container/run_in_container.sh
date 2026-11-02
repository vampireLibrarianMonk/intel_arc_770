#!/usr/bin/env bash
# run_in_container.sh — entrypoint for the latest-driver SYCL test.
# Reports the in-container driver versions, then runs llama.cpp SYCL with oneDNN + the
# persistent cache ENABLED and checks it loads + generates WITHOUT segfaulting.
set -uo pipefail

MODEL="${MODEL:-/models/Qwen2.5-7B-Instruct-Q4_K_M.gguf}"
BIN=/opt/llama.cpp/build-sycl/bin

# shellcheck disable=SC1091
source /opt/intel/oneapi/setvars.sh --force >/dev/null 2>&1

echo "================ in-container driver stack ================"
echo "NEO/L0 GPU driver + OpenCL:"
sycl-ls 2>/dev/null | sed 's/^/  /'
echo "packages:"
dpkg -l 2>/dev/null | grep -iE "intel-opencl|libze-intel|intel-igc|igdgmm|level-zero" \
  | awk '{print "  "$2"="$3}'
echo "==========================================================="

if [ ! -f "$MODEL" ]; then
  echo "ERROR: model not found at $MODEL (mount it with -v <host-gguf-dir>:/models)"; exit 2
fi

# The whole point: everything ON. SYCL_CACHE_PERSISTENT=1 (the host crashes here),
# oneDNN compiled in, Level-Zero API compiled in.
export SYCL_CACHE_PERSISTENT=1 ONEAPI_DEVICE_SELECTOR="level_zero:0" ONEDNN_VERBOSE=0
rm -rf ~/.cache/libsycl_cache ~/.cache/neo_compiler_cache 2>/dev/null || true

echo "[test] SYCL generate with oneDNN + persistent cache ENABLED ..."
printf 'Write one clear sentence about the Intel Arc GPU.\n/exit\n' \
  | timeout 420 "$BIN/llama-cli" --model "$MODEL" -ngl 999 -c 512 -n 32 > /tmp/run1.log 2>&1
rc=$?
echo "---- generation (filtered) ----"
grep -ivE "onednn_verbose" /tmp/run1.log | grep -iE "Arc|Intel|GPU|sentence|tokens per second|eval time|segmentation|error|SYCL" | tail -12
echo "---- exit code: $rc ----"
if [ $rc -eq 139 ] || grep -qiE "segmentation|core dumped" /tmp/run1.log; then
  echo "RESULT: STILL CRASHES (SEGV) with latest driver"
  exit 3
elif [ $rc -eq 0 ]; then
  echo "RESULT: SUCCESS — SYCL runs with oneDNN + cache ENABLED on the latest driver"
  # quick second pass to confirm warm-cache restart works (the host's cache-SEGV path)
  echo "[test] warm-cache restart ..."
  printf 'Say hi.\n/exit\n' | timeout 180 "$BIN/llama-cli" --model "$MODEL" -ngl 999 -c 512 -n 8 2>&1 \
    | grep -iE "tokens per second|segmentation" | tail -2
  exit 0
else
  echo "RESULT: inconclusive (rc=$rc) — see /tmp/run1.log"
  exit 1
fi
