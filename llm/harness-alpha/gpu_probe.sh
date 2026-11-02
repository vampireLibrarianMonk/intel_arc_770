#!/usr/bin/env bash
# gpu_probe.sh — prove a process is actually using the Arc A770 (not a silent CPU fallback).
#
#   bash gpu_probe.sh <pid>
#
# Reads per-process DRM memory from /proc/<pid>/fdinfo for any fd pointing at the render
# node, and reports device-local (VRAM) bytes. i915 exposes:
#   drm-total-local0     bytes allocated in device-local memory (VRAM)
#   drm-resident-local0  bytes currently resident in VRAM
# A real GPU inference process shows tens of MiB to GiB of local0. A CPU-fallback process
# shows ~0 local0. No root, no extra tools (no intel_gpu_top / xpu-smi needed).
#
# Exit 0 and print "GPU: yes" if device-local memory exceeds the threshold, else "GPU: no".
set -euo pipefail

PID="${1:?usage: gpu_probe.sh <pid>}"
THRESHOLD_KIB="${GPU_PROBE_THRESHOLD_KIB:-20480}"  # 20 MiB default

if [ ! -d "/proc/$PID" ]; then
  echo "GPU: unknown (pid $PID not found)"
  exit 1
fi

total_local=0
resident_local=0
render_fds=0
for fd in /proc/"$PID"/fd/*; do
  tgt="$(readlink "$fd" 2>/dev/null || true)"
  case "$tgt" in
    *renderD*|*/dri/card*)
      fdinfo="${fd/\/fd\//\/fdinfo\/}"
      [ -r "$fdinfo" ] || continue
      render_fds=$((render_fds + 1))
      # sum device-local memory across all render fds; values look like "12345 KiB"
      while IFS= read -r line; do
        case "$line" in
          drm-total-local0:*)
            v="$(echo "$line" | grep -oE '[0-9]+' | head -1)"; total_local=$((total_local + v)) ;;
          drm-resident-local0:*)
            v="$(echo "$line" | grep -oE '[0-9]+' | head -1)"; resident_local=$((resident_local + v)) ;;
        esac
      done < "$fdinfo"
      ;;
  esac
done

echo "pid               : $PID"
echo "render fds        : $render_fds"
echo "VRAM total (local): $((total_local / 1024)) MiB"
echo "VRAM resident     : $((resident_local / 1024)) MiB"

if [ "$total_local" -ge "$THRESHOLD_KIB" ]; then
  echo "GPU: yes (device-local memory above ${THRESHOLD_KIB} KiB threshold)"
  exit 0
fi

# fdinfo VRAM was inconclusive. This is EXPECTED for the Vulkan/Mesa (ANV) backend, which
# does not export per-process device memory in fdinfo the way the i915 compute/Level-Zero
# path (IPEX) does. Fall back to a second signal: GPU engine busy % via intel_gpu_top.
# If the render engine is clearly busy while this pid runs, it is using the GPU.
if [ "$render_fds" -gt 0 ] && command -v intel_gpu_top >/dev/null 2>&1; then
  echo "fdinfo VRAM inconclusive; sampling GPU engine busy (intel_gpu_top, 3s) ..."
  # -o - streams CSV; sample a few rows and take the max Render/3D or Compute busy %.
  busy="$(timeout 4 sudo intel_gpu_top -c -s 500 2>/dev/null \
    | awk -F, 'NR>1 {for(i=1;i<=NF;i++){v=$i+0; if(v>max)max=v}} END{printf "%d", max}')"
  echo "peak engine busy  : ${busy:-0}%"
  if [ "${busy:-0}" -ge 20 ]; then
    echo "GPU: yes (engine busy ${busy}% — Vulkan/Mesa path, memory not in fdinfo)"
    exit 0
  fi
fi

echo "GPU: inconclusive (no device-local memory in fdinfo and engine not clearly busy)"
echo "  NOTE: for the Vulkan backend, confirm via tokens/sec vs CPU baseline instead —"
echo "  Mesa ANV does not expose per-process VRAM. CPU 7B ~8 t/s, GPU 7B ~40+ t/s."
exit 3
