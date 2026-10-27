#!/usr/bin/env bash
# freeze_all.sh — orchestrate A1 (bundle) + A2 (container) + A3 (image) into ONE
# timestamped snapshot, with a top-level provenance record and a combined checksum manifest.
#
# The "good run" gate is MANUAL: you must pass --i-say-so and --note="...". Nothing heavy
# runs without it. Individual layers can be skipped with --no-<layer>.
#
# Usage:
#   scripts/freeze/freeze_all.sh --i-say-so --note="ARC-MEM-0007 green on A770, commit abc123" \
#       [--no-container] [--no-image] [--include-kernel] [--qcow2=/path --powered-off]
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

DO_PYTHON=1; DO_SYSTEM=1; DO_SOURCE=1; DO_CONTAINER=1; DO_IMAGE=1
PASSTHRU=()
for arg in "$@"; do case "$arg" in
  --no-python)    DO_PYTHON=0;;
  --no-system)    DO_SYSTEM=0;;
  --no-source)    DO_SOURCE=0;;
  --no-container) DO_CONTAINER=0;;
  --no-image)     DO_IMAGE=0;;
  --dry-run)      ;;  # handled globally via freeze_parse_dry_run; not re-passed here
  *)              PASSTHRU+=("$arg");;
esac; done

NOTE="$(require_good_run_confirmation "$@")"
freeze_parse_dry_run "$@"
SNAPSHOT="${FREEZE_ROOT_DEFAULT}/$(freeze_timestamp)"
mkdir_unless_dry "${SNAPSHOT}"
log "freeze snapshot: ${SNAPSHOT}"
log "good-run note (operator-declared): ${NOTE}"
is_dry_run && log "DRY RUN: previewing all layers; nothing downloaded, built, or imaged."

HERE="$(dirname "${BASH_SOURCE[0]}")"
SNAP_ARG="--snapshot=${SNAPSHOT}"
STATUS_LINES=()

record_status() { # record_status "<label>: <state>"
  STATUS_LINES+=("$1")
  is_dry_run || echo "$1" >> "${SNAPSHOT}/freeze_status.txt"
}

run_layer() { # run_layer <label> <script> [extra args...]
  local label="$1"; shift
  local script="$1"; shift
  local dry=(); is_dry_run && dry=(--dry-run)
  log "=== layer: ${label} ==="
  if bash "${script}" --i-say-so "--note=${NOTE}" "${SNAP_ARG}" "${dry[@]}" "$@"; then
    record_status "${label}: OK"
  else
    warn "layer ${label} failed; continuing"
    record_status "${label}: FAILED"
  fi
}

# A1 — offline bundle (python + system + source).
[ "${DO_PYTHON}" -eq 1 ] && run_layer "A1-python" "${HERE}/freeze_python.sh"
[ "${DO_SYSTEM}" -eq 1 ] && run_layer "A1-system" "${HERE}/freeze_system.sh" "${PASSTHRU[@]}"
[ "${DO_SOURCE}" -eq 1 ] && run_layer "A1-source" "${HERE}/freeze_source.sh"

# A2 — container image tarball.
[ "${DO_CONTAINER}" -eq 1 ] && run_layer "A2-container" "${HERE}/freeze_container.sh"

# A3 — full image (guidance by default; qcow2 copy if args passed through).
[ "${DO_IMAGE}" -eq 1 ] && run_layer "A3-image" "${HERE}/freeze_image.sh" "${PASSTHRU[@]}"

# Top-level provenance.
if is_dry_run; then
  log "=== DRY RUN complete: previewed all selected layers ==="
  printf '%s\n' "${STATUS_LINES[@]}"
  dry_note "write PROVENANCE.json and top-level MANIFEST.sha256"
  log "no snapshot content written (dry run). Target would be: ${SNAPSHOT}"
  exit 0
fi
cat > "${SNAPSHOT}/PROVENANCE.json" <<JSON
{
  "snapshot": "$(basename "${SNAPSHOT}")",
  "created_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "operator_note": "${NOTE}",
  "host": {"uname": "$(uname -a | sed 's/"/\\"/g')", "user": "$(id -un)"},
  "repo_commit": "$(git -C "${REPO_ROOT}" rev-parse HEAD 2>/dev/null || echo 'unknown')",
  "layers": "see freeze_status.txt",
  "verify": "run scripts/freeze/verify_freeze.sh --snapshot=$(basename "${SNAPSHOT}")"
}
JSON

# Combined top-level manifest across all layer dirs.
write_sha256_manifest "${SNAPSHOT}"

log "=== freeze complete ==="
printf '%s\n' "${STATUS_LINES[@]}"
log "snapshot at: ${SNAPSHOT}"
echo "${SNAPSHOT}"
