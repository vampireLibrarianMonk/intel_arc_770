#!/usr/bin/env bash
# get_model.sh — fetch the ONE shared GGUF model all GGUF candidates use.
# Downloads into artifacts/harness-alpha/models/ (git-ignored). Idempotent.
set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

if [ -f "$MODEL_PATH" ]; then
  log "model already present: $MODEL_PATH ($(du -h "$MODEL_PATH" | cut -f1))"
  exit 0
fi

URL="https://huggingface.co/${MODEL_REPO}/resolve/main/${MODEL_FILE}?download=true"
log "downloading $MODEL_FILE from $MODEL_REPO"
log "  -> $MODEL_PATH"
# The link to this mirror drops frequently and curl sometimes dies outright (not an HTTP
# error it can --retry). So wrap it in an outer loop: keep resuming (-C -) until the .part
# reaches the known full size. Each pass appends from wherever the last one stopped.
attempt=0
while :; do
  attempt=$((attempt + 1))
  cur=0; [ -f "$MODEL_PATH.part" ] && cur="$(stat -c %s "$MODEL_PATH.part")"
  if [ "$cur" -ge "$MODEL_SIZE_BYTES" ]; then
    break
  fi
  log "pass $attempt: resuming from $((cur / 1048576)) MiB / $((MODEL_SIZE_BYTES / 1048576)) MiB"
  # || true: a dropped connection returns nonzero; the loop just resumes next pass.
  curl -L --fail -sS --retry 5 --retry-delay 5 -C - -o "$MODEL_PATH.part" "$URL" || true
  sleep 3
done

# --- integrity gate: size then sha256 ---
got_size="$(stat -c %s "$MODEL_PATH.part")"
if [ "$got_size" != "$MODEL_SIZE_BYTES" ]; then
  die "size mismatch: got $got_size, want $MODEL_SIZE_BYTES (download incomplete/corrupt)"
fi
log "verifying sha256 (this reads the whole 4.5 GiB file, ~30-60s) ..."
got_sha="$(sha256sum "$MODEL_PATH.part" | cut -d' ' -f1)"
if [ "$got_sha" != "$MODEL_SHA256" ]; then
  die "sha256 MISMATCH — file is corrupt. got $got_sha want $MODEL_SHA256. Delete the .part and re-run."
fi
mv "$MODEL_PATH.part" "$MODEL_PATH"
log "done & VERIFIED: $(du -h "$MODEL_PATH" | cut -f1), sha256 ok"
