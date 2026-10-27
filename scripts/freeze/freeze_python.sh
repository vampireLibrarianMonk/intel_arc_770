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
NOTE="$(require_good_run_confirmation "$@")"
[ -n "${SNAPSHOT}" ] || SNAPSHOT="${FREEZE_ROOT_DEFAULT}/$(freeze_timestamp)"
OUT="${SNAPSHOT}/python"
mkdir -p "${OUT}/wheels"

log "freezing python env (note: ${NOTE})"
have python3 || die "python3 not found"
have pip3 2>/dev/null || python3 -m pip --version >/dev/null 2>&1 || die "pip not available"

# 1. Fully pinned freeze of whatever is currently installed (the good-run env).
python3 -m pip freeze --all > "${OUT}/requirements.lock"
log "pinned $(wc -l < "${OUT}/requirements.lock") packages -> requirements.lock"

# 2. Download every wheel (incl. deps) for offline reinstall on the same platform.
#    --no-deps off on purpose: we want the full closure. Platform-specific by default.
python3 -m pip download \
  --requirement "${OUT}/requirements.lock" \
  --dest "${OUT}/wheels" \
  2> "${OUT}/pip_download.log" || warn "pip download had issues; see pip_download.log"

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
