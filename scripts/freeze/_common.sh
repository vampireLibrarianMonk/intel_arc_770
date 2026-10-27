#!/usr/bin/env bash
# _common.sh — shared helpers for the freeze toolkit. Sourced, not executed.
# No side effects on source beyond defining functions and a few vars.

# Resolve repo root regardless of where a freeze script is invoked from.
freeze_repo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd
}

REPO_ROOT="$(freeze_repo_root)"
FREEZE_ROOT_DEFAULT="${REPO_ROOT}/artifacts/freeze"

log()  { echo "[freeze] $*"; }
warn() { echo "[freeze][WARN] $*" >&2; }
die()  { echo "[freeze][ERROR] $*" >&2; exit 1; }

# have CMD -> true if command exists
have() { command -v "$1" >/dev/null 2>&1; }

# Timestamp used to name a freeze snapshot (UTC, sortable).
freeze_timestamp() { date -u +%Y%m%dT%H%M%SZ; }

# --- "Good run" gate -----------------------------------------------------------
# The freeze is destructive of time/space and only meaningful after a verified
# good run. Per the owner's instruction, the gate is a MANUAL confirmation, not an
# automated check. Require either --i-say-so on the CLI or FREEZE_CONFIRM=1 in env.
# Also require a human-supplied note describing which run is being frozen.
require_good_run_confirmation() {
  local confirmed="${FREEZE_CONFIRM:-0}"
  local note="${FREEZE_NOTE:-}"
  for arg in "$@"; do
    case "$arg" in
      --i-say-so) confirmed=1 ;;
      --note=*)   note="${arg#--note=}" ;;
    esac
  done
  if [ "${confirmed}" != "1" ]; then
    die "Refusing to freeze: no confirmation. Re-run with --i-say-so (you declare the run good)."
  fi
  if [ -z "${note}" ]; then
    die "Refusing to freeze: provide --note='what run this is' (e.g. experiment id / commit)."
  fi
  echo "${note}"
}

# --- Manifest / checksums ------------------------------------------------------
# Write SHA-256 sums for everything under a directory into MANIFEST.sha256.
write_sha256_manifest() {
  local dir="$1"
  ( cd "${dir}" && find . -type f ! -name 'MANIFEST.sha256' -print0 \
      | sort -z \
      | xargs -0 sha256sum ) > "${dir}/MANIFEST.sha256"
  log "wrote ${dir}/MANIFEST.sha256 ($(wc -l < "${dir}/MANIFEST.sha256") files)"
}

# Verify a previously written manifest.
verify_sha256_manifest() {
  local dir="$1"
  [ -f "${dir}/MANIFEST.sha256" ] || die "no MANIFEST.sha256 in ${dir}"
  ( cd "${dir}" && sha256sum --quiet -c MANIFEST.sha256 )
}
