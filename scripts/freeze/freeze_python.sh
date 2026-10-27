#!/usr/bin/env bash
# freeze_python.sh — snapshot the exact Python/PyTorch dependency set as offline wheels.
# Part of the A1 offline bundle. Read-only w.r.t. the live environment (downloads only).
#
# Produces, under <snapshot>/python/:
#   requirements.lock   -- fully pinned freeze of the active environment
#   wheels/             -- every wheel needed to reinstall offline
#   install_python_offline.sh
#
# Usage:
#   scripts/freeze/freeze_python.sh --i-say-so --note="ARC-...good run" [--snapshot DIR]
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

SNAPSHOT=""
for arg in "$@"; do case "$arg" in --snapshot=*) SNAPSHOT="${arg#--snapshot=}";; esac; done
freeze_parse_dry_run "$@"
NOTE="$(require_good_run_confirmation "$@")"
[ -n "${SNAPSHOT}" ] || SNAPSHOT="${FREEZE_ROOT_DEFAULT}/$(freeze_timestamp)"
OUT="${SNAPSHOT}/python"
mkdir_unless_dry "${OUT}/wheels"

log "freezing python env (note: ${NOTE})"
is_dry_run && log "DRY RUN: no wheels downloaded, no manifest written."
have python3 || die "python3 not found"
have pip3 2>/dev/null || python3 -m pip --version >/dev/null 2>&1 || die "pip not available"

# 1. Fully pinned freeze of whatever is currently installed (the good-run env).
#    Prefer an active virtualenv: a venv avoids OS-managed/VCS packages that have no
#    downloadable wheel (e.g. apturl on Debian/Ubuntu system Python).
if [ -z "${VIRTUAL_ENV:-}" ]; then
  warn "no active virtualenv detected. Freezing the SYSTEM Python may include OS-managed"
  warn "packages that cannot be downloaded as wheels. Strongly prefer: source arc-venv/bin/activate"
fi

# In dry-run, compute into a temp dir so nothing is written under the snapshot.
if is_dry_run; then
  WORK="$(mktemp -d)"
  trap 'rm -rf "${WORK}"' EXIT
else
  WORK="${OUT}"
fi

python3 -m pip freeze --all > "${WORK}/requirements.lock.raw"

# Drop entries pip cannot resolve offline later: editable installs, VCS URLs, local paths.
grep -vE '^(-e |.+ @ |.*/)' "${WORK}/requirements.lock.raw" \
  | grep -E '==' > "${WORK}/requirements.lock" || true
SKIPPED="$(grep -cE '^(-e |.+ @ |.*/)' "${WORK}/requirements.lock.raw" || true)"
[ "${SKIPPED:-0}" -gt 0 ] && warn "excluded ${SKIPPED} non-wheel entries (editable/VCS/local); see requirements.lock.raw"
log "pinned $(wc -l < "${WORK}/requirements.lock") wheel-eligible packages -> requirements.lock"

# 2. Download every wheel (incl. deps) for offline reinstall on the same platform.
#    Best-effort PER PACKAGE so one unresolvable package cannot abort the whole closure.
if is_dry_run; then
  dry_note "download wheels for $(wc -l < "${WORK}/requirements.lock") packages into python/wheels/"
  dry_note "generate install_python_offline.sh and platform.json"
  log "DRY RUN complete: previewed python freeze (no downloads)."
  echo "${SNAPSHOT}"
  exit 0
fi
: > "${OUT}/pip_download.log"
UNRESOLVED=0
while IFS= read -r req; do
  [ -n "${req}" ] || continue
  if ! python3 -m pip download "${req}" --dest "${OUT}/wheels" \
        >> "${OUT}/pip_download.log" 2>&1; then
    warn "could not download: ${req}"
    echo "${req}" >> "${OUT}/unresolved_packages.txt"
    UNRESOLVED=$((UNRESOLVED+1))
  fi
done < "${OUT}/requirements.lock"
[ "${UNRESOLVED}" -gt 0 ] && warn "${UNRESOLVED} package(s) unresolved; see unresolved_packages.txt"

log "downloaded $(ls -1 "${OUT}/wheels" | wc -l) files into python/wheels/"

# 3. Offline installer for the future host.
cat > "${OUT}/install_python_offline.sh" <<'INSTALL'
#!/usr/bin/env bash
# Reinstall the frozen Python environment with NO network access.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 -m venv "${1:-./arc-venv}"
# shellcheck disable=SC1091
source "${1:-./arc-venv}/bin/activate"
pip install --no-index --find-links "${HERE}/wheels" -r "${HERE}/requirements.lock"
echo "Offline Python env ready. Activate with: source ${1:-./arc-venv}/bin/activate"
INSTALL
chmod +x "${OUT}/install_python_offline.sh"

# 4. Record the platform this freeze targets (wheels are platform/abi specific).
python3 - > "${OUT}/platform.json" <<'PY'
import json, platform, sys
print(json.dumps({
    "python_version": sys.version,
    "python_impl": platform.python_implementation(),
    "machine": platform.machine(),
    "system": platform.system(),
    "libc": platform.libc_ver(),
}, indent=2))
PY

write_sha256_manifest "${OUT}"
log "python freeze complete: ${OUT}"
echo "${SNAPSHOT}"
