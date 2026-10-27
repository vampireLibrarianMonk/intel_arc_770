#!/usr/bin/env bash
# verify_freeze.sh — verify the SHA-256 manifests of a freeze snapshot (offline, read-only).
# Use this now to self-test, and years later to prove a snapshot is intact before install.
#
# Usage:
#   scripts/freeze/verify_freeze.sh --snapshot=<dir-or-name>
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

SNAPSHOT=""
for arg in "$@"; do case "$arg" in --snapshot=*) SNAPSHOT="${arg#--snapshot=}";; esac; done
[ -n "${SNAPSHOT}" ] || die "pass --snapshot=<dir|name>"

# Allow passing just the timestamp name.
[ -d "${SNAPSHOT}" ] || SNAPSHOT="${FREEZE_ROOT_DEFAULT}/${SNAPSHOT}"
[ -d "${SNAPSHOT}" ] || die "snapshot not found: ${SNAPSHOT}"

log "verifying snapshot: ${SNAPSHOT}"
rc=0

# Verify each layer manifest, then the top-level one.
for d in "${SNAPSHOT}"/*/; do
  [ -f "${d}/MANIFEST.sha256" ] || continue
  log "  layer $(basename "${d}")"
  if verify_sha256_manifest "${d}"; then
    log "    OK"
  else
    warn "    MISMATCH in $(basename "${d}")"; rc=1
  fi
done

if [ -f "${SNAPSHOT}/MANIFEST.sha256" ]; then
  log "  top-level"
  verify_sha256_manifest "${SNAPSHOT}" && log "    OK" || { warn "    top-level MISMATCH"; rc=1; }
fi

[ "${rc}" -eq 0 ] && log "VERIFY PASSED" || warn "VERIFY FAILED"
exit "${rc}"
