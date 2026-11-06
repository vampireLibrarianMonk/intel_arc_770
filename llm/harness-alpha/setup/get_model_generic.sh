#!/usr/bin/env bash
# get_model_generic.sh — fetch ANY GGUF with the same resume + integrity discipline as
# get_model.sh, but parameterized so the model sweep can pull several models.
#
#   bash get_model_generic.sh <repo> <file> <size_bytes> <sha256>
#
# Downloads into artifacts/harness-alpha/models/<file> (git-ignored). Idempotent: if the
# file already exists and matches sha256, it's a no-op. Resumes dropped connections until
# the .part reaches full size, then gates on size + sha256 before promoting to final name.
# A model that fails either gate is left as .part and the script exits nonzero — the
# benchmark must never run on an unverified model (AGENTS.md).
set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

REPO="${1:?usage: get_model_generic.sh <repo> <file> <size_bytes> <sha256>}"
FILE="${2:?missing file}"
WANT_SIZE="${3:?missing size_bytes}"
WANT_SHA="${4:?missing sha256}"

DEST="$MODELS_DIR/$FILE"

if [ -f "$DEST" ]; then
  got="$(sha256sum "$DEST" | cut -d' ' -f1)"
  if [ "$got" = "$WANT_SHA" ]; then
    log "already present & verified: $FILE ($(du -h "$DEST" | cut -f1))"
    exit 0
  fi
  log "present but sha mismatch — re-fetching $FILE"
  rm -f "$DEST"
fi

URL="https://huggingface.co/${REPO}/resolve/main/${FILE}?download=true"
# Optional auth: if HF_TOKEN (or HUGGING_FACE_HUB_TOKEN) is set, send it as a Bearer header
# to lift anonymous rate/throughput limits. Passed via a curl config on stdin (-K -) so the
# token never appears in argv / `ps` output. Anonymous download is used when no token is set.
HF_AUTH_TOKEN="${HF_TOKEN:-${HUGGING_FACE_HUB_TOKEN:-}}"
if [ -n "$HF_AUTH_TOKEN" ]; then
  log "using HF auth token (value not logged)"
fi
hf_curl() {
  if [ -n "$HF_AUTH_TOKEN" ]; then
    printf 'header = "Authorization: Bearer %s"\n' "$HF_AUTH_TOKEN" \
      | curl -K - "$@"
  else
    curl "$@"
  fi
}
log "downloading $FILE from $REPO -> $DEST"
attempt=0
while :; do
  attempt=$((attempt + 1))
  cur=0; [ -f "$DEST.part" ] && cur="$(stat -c %s "$DEST.part")"
  [ "$cur" -ge "$WANT_SIZE" ] && break
  log "pass $attempt: $((cur / 1048576)) / $((WANT_SIZE / 1048576)) MiB"
  hf_curl -L --fail -sS --retry 5 --retry-delay 5 -C - -o "$DEST.part" "$URL" || true
  sleep 3
done

got_size="$(stat -c %s "$DEST.part")"
[ "$got_size" = "$WANT_SIZE" ] || die "size mismatch: got $got_size want $WANT_SIZE"
log "verifying sha256 ..."
got_sha="$(sha256sum "$DEST.part" | cut -d' ' -f1)"
[ "$got_sha" = "$WANT_SHA" ] || die "sha256 MISMATCH: got $got_sha want $WANT_SHA"
mv "$DEST.part" "$DEST"
log "done & VERIFIED: $FILE ($(du -h "$DEST" | cut -f1))"
