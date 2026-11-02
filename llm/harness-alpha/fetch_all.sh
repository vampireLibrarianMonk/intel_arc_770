#!/usr/bin/env bash
# fetch_all.sh — ONE self-healing download manager for the harness alpha cycle.
#
# Why this exists: the mirror link drops often and curl/python downloaders die mid-transfer;
# ad-hoc background jobs also got reaped. This script runs the downloads SEQUENTIALLY (never
# two at once — that both saturates the flaky link and previously caused dual-write
# corruption), each in an auto-resuming loop, and writes a compact status file after every
# step so progress can be checked with a single cheap read (no process hunting).
#
# Launch it durably (survives shell/session exit) with systemd-run:
#   systemd-run --user --unit=ha-fetch --working-directory="$PWD" \
#       bash llm/harness-alpha/fetch_all.sh
# Watch:   bash llm/harness-alpha/status.sh
# Logs:    journalctl --user -u ha-fetch -f     (or the STATUS file below)
set -uo pipefail   # NOT -e: a failed pass must not abort the whole manager; we loop instead.

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/setup/common.sh"

STATUS="$PREFIX/STATUS.txt"
HF_7B_DIR="$HOME/.cache/huggingface/hub/models--Qwen--Qwen2.5-7B-Instruct"

stamp() { date '+%Y-%m-%d %H:%M:%S'; }
set_status() { printf '%s | %s\n' "$(stamp)" "$*" >> "$STATUS"; }

: > "$STATUS"
set_status "fetch_all started (pid $$)"

# ---------------------------------------------------------------------------
# Step 1: shared GGUF (needed by llamacpp-vulkan, llamacpp-sycl, lmstudio)
# ---------------------------------------------------------------------------
if [ -f "$MODEL_PATH" ]; then
  set_status "GGUF: already present & verified"
else
  URL="https://huggingface.co/${MODEL_REPO}/resolve/main/${MODEL_FILE}?download=true"
  pass=0
  while :; do
    cur=0; [ -f "$MODEL_PATH.part" ] && cur="$(stat -c %s "$MODEL_PATH.part")"
    [ "$cur" -ge "$MODEL_SIZE_BYTES" ] && break
    pass=$((pass + 1))
    set_status "GGUF: pass $pass, $((cur / 1048576))/$((MODEL_SIZE_BYTES / 1048576)) MiB"
    curl -L --fail -sS --retry 5 --retry-delay 5 -C - -o "$MODEL_PATH.part" "$URL" || true
    sleep 3
  done
  sz="$(stat -c %s "$MODEL_PATH.part")"
  if [ "$sz" != "$MODEL_SIZE_BYTES" ]; then
    set_status "GGUF: SIZE MISMATCH ($sz vs $MODEL_SIZE_BYTES) — aborting"; exit 1
  fi
  set_status "GGUF: size ok, verifying sha256 ..."
  sha="$(sha256sum "$MODEL_PATH.part" | cut -d' ' -f1)"
  if [ "$sha" != "$MODEL_SHA256" ]; then
    set_status "GGUF: SHA256 MISMATCH — corrupt. Deleting .part so next run restarts clean."
    rm -f "$MODEL_PATH.part"
    exit 1
  fi
  mv "$MODEL_PATH.part" "$MODEL_PATH"
  set_status "GGUF: DONE & VERIFIED ($(du -h "$MODEL_PATH" | cut -f1))"
fi

# ---------------------------------------------------------------------------
# Step 2: 7B HF weights (needed by ipex-llm candidate). Resumable; Xet off.
# huggingface_hub resumes partial blobs itself; wrap in a retry loop for dropped links.
# ---------------------------------------------------------------------------
if [ -n "$(ls "$HF_7B_DIR"/snapshots/*/model-00004-of-00004.safetensors 2>/dev/null)" ] \
   && [ -z "$(ls "$HF_7B_DIR"/blobs/*.incomplete 2>/dev/null)" ]; then
  set_status "7B-HF: already complete"
else
  pass=0
  while :; do
    pass=$((pass + 1))
    set_status "7B-HF: download pass $pass"
    HF_HUB_DISABLE_XET=1 "$REPO_ROOT/.venv-llm/bin/python" - <<'PY' && break || true
from huggingface_hub import snapshot_download
snapshot_download("Qwen/Qwen2.5-7B-Instruct")
print("ok")
PY
    sleep 5
  done
  set_status "7B-HF: DONE"
fi

# ---------------------------------------------------------------------------
# Step 3: oneAPI DPC++ compiler (needed by llamacpp-sycl). apt resumes from its cache.
# Needs passwordless sudo (already configured). Retry loop for the flaky Intel mirror.
# ---------------------------------------------------------------------------
if [ -n "$(ls /opt/intel/oneapi/compiler/*/bin/icpx 2>/dev/null)" ]; then
  set_status "DPCPP: icpx already installed"
else
  pass=0
  while :; do
    [ -n "$(ls /opt/intel/oneapi/compiler/*/bin/icpx 2>/dev/null)" ] && break
    pass=$((pass + 1))
    set_status "DPCPP: apt install pass $pass"
    sudo dpkg --configure -a >/dev/null 2>&1 || true
    sudo apt-get install -y -o Acquire::Retries=5 intel-oneapi-compiler-dpcpp-cpp \
      >>"$PREFIX/apt_dpcpp.log" 2>&1 || true
    sleep 5
  done
  set_status "DPCPP: icpx installed"
fi

set_status "fetch_all COMPLETE — all prerequisites ready"
