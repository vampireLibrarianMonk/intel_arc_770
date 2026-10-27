#!/usr/bin/env bash
# freeze_source.sh — snapshot this repo + all vendor/ clones as self-contained git bundles.
# Part of the A1 offline bundle. A git bundle is a single file containing full history that
# can be cloned offline years later: `git clone snapshot.bundle restored-repo`.
#
# Usage:
#   scripts/freeze/freeze_source.sh --i-say-so --note="..." [--snapshot=DIR]
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

SNAPSHOT=""
for arg in "$@"; do case "$arg" in --snapshot=*) SNAPSHOT="${arg#--snapshot=}";; esac; done
freeze_parse_dry_run "$@"
NOTE="$(require_good_run_confirmation "$@")"
[ -n "${SNAPSHOT}" ] || SNAPSHOT="${FREEZE_ROOT_DEFAULT}/$(freeze_timestamp)"
OUT="${SNAPSHOT}/source"
mkdir_unless_dry "${OUT}/bundles"

log "freezing source trees (note: ${NOTE})"
is_dry_run && log "DRY RUN: no bundles created, no manifest written."
have git || die "git not found"

bundle_repo() {
  local repo_dir="$1" label="$2"
  [ -d "${repo_dir}/.git" ] || { warn "not a git repo, skipping: ${repo_dir}"; return 0; }
  local sha; sha="$(git -C "${repo_dir}" rev-parse HEAD)"
  local dirty=""
  git -C "${repo_dir}" diff --quiet || dirty=" (DIRTY working tree)"
  if is_dry_run; then
    echo "[freeze][would] git bundle ${label}.bundle @ ${sha}${dirty}"
    return 0
  fi
  git -C "${repo_dir}" bundle create "${OUT}/bundles/${label}.bundle" --all \
    >> "${OUT}/bundle.log" 2>&1 || { warn "bundle failed for ${label}"; return 0; }
  echo "${label} ${sha}${dirty}" >> "${OUT}/pinned_shas.txt"
  log "  bundled ${label} @ ${sha}${dirty}"
}

[ "${FREEZE_DRY_RUN}" = "1" ] || : > "${OUT}/pinned_shas.txt"

# 1. This project repo.
bundle_repo "${REPO_ROOT}" "arc-a770-lab"

# 2. Every vendored upstream clone.
if [ -d "${REPO_ROOT}/vendor" ]; then
  for d in "${REPO_ROOT}"/vendor/*/; do
    [ -d "${d}" ] || continue
    bundle_repo "${d%/}" "vendor-$(basename "${d%/}")"
  done
fi

# 3. Restore helper.
if is_dry_run; then
  dry_note "generate restore_source_offline.sh"
  log "DRY RUN complete: previewed source freeze (no bundles)."
  echo "${SNAPSHOT}"
  exit 0
fi
cat > "${OUT}/restore_source_offline.sh" <<'RESTORE'
#!/usr/bin/env bash
# Clone the frozen source trees from bundles (offline).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${1:-./restored}"
mkdir -p "${DEST}"
for b in "${HERE}"/bundles/*.bundle; do
  name="$(basename "${b}" .bundle)"
  echo "restoring ${name}"
  git clone "${b}" "${DEST}/${name}"
done
echo "Source restored under ${DEST}. See pinned_shas.txt for exact commits."
RESTORE
chmod +x "${OUT}/restore_source_offline.sh"

write_sha256_manifest "${OUT}"
log "source freeze complete: ${OUT}"
echo "${SNAPSHOT}"
