#!/usr/bin/env bash
# freeze_system.sh — cache the Intel GPU user-space stack as offline .deb packages.
# Part of the A1 offline bundle. Downloads packages only; installs/changes nothing.
#
# Freezes (user-space, reliably portable):
#   intel-opencl-icd, level-zero / libze loader, intel compute runtime (NEO),
#   intel graphics compiler runtime (IGC), gmmlib, intel-gpu-tools, clinfo.
#
# Kernel/i915 (--include-kernel): OPT-IN and explicitly flagged as NOT guaranteed to
# install cleanly on a future OS. We cache the .deb for reference only; use the full
# image (A3) if you truly need kernel-level reproduction.
#
# Usage:
#   scripts/freeze/freeze_system.sh --i-say-so --note="..." [--snapshot=DIR] [--include-kernel]
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

SNAPSHOT=""; INCLUDE_KERNEL=0
for arg in "$@"; do case "$arg" in
  --snapshot=*) SNAPSHOT="${arg#--snapshot=}";;
  --include-kernel) INCLUDE_KERNEL=1;;
esac; done
NOTE="$(require_good_run_confirmation "$@")"
[ -n "${SNAPSHOT}" ] || SNAPSHOT="${FREEZE_ROOT_DEFAULT}/$(freeze_timestamp)"
OUT="${SNAPSHOT}/system"
mkdir -p "${OUT}/debs"

log "freezing system GPU stack (note: ${NOTE})"
have dpkg || die "not a dpkg-based system; use the container (A2) or full image (A3) instead"
have apt-get || die "apt-get not found"

# Candidate user-space packages. Missing ones are skipped (names vary by release).
USERSPACE_PKGS=(
  intel-opencl-icd
  level-zero
  libze1
  libze-intel-gpu1
  intel-level-zero-gpu
  libigdgmm12
  intel-igc-core
  intel-igc-opencl
  clinfo
  intel-gpu-tools
)

# 1. Record exactly-installed versions of anything GPU-related (the source of truth).
dpkg -l | grep -Ei 'opencl|level-zero|libze|igc|gmm|intel-gpu|i915|xe ' \
  > "${OUT}/installed_versions.txt" || true
log "recorded installed GPU-related package versions"

# 2. Download .debs (+ dependencies) without installing.
#    apt-get download does not pull deps; use a download-only install plan instead.
download_with_deps() {
  local pkg="$1"
  if ! apt-cache show "${pkg}" >/dev/null 2>&1; then
    warn "package not available in apt cache: ${pkg} (skipping)"
    return 0
  fi
  # Resolve the dependency closure and download each .deb.
  apt-get install --reinstall --download-only -y -o Dir::Cache::archives="${OUT}/debs" "${pkg}" \
    >> "${OUT}/apt_download.log" 2>&1 || warn "download issues for ${pkg} (see apt_download.log)"
}

log "NOTE: downloading .debs may require sudo for apt cache dirs on some hosts."
for pkg in "${USERSPACE_PKGS[@]}"; do
  log "  fetching ${pkg}"
  download_with_deps "${pkg}"
done

# Move any .debs apt placed in its partial/archive layout into debs/ flat.
find "${OUT}/debs" -name '*.deb' -exec mv -n {} "${OUT}/debs/" \; 2>/dev/null || true
log "cached $(find "${OUT}/debs" -name '*.deb' | wc -l) .deb files"

# 3. Optional kernel/i915 — with a loud caveat.
if [ "${INCLUDE_KERNEL}" -eq 1 ]; then
  warn "including kernel/i915 .debs — NOT guaranteed to install on a future OS."
  KVER="$(uname -r)"
  for pkg in "linux-image-${KVER}" "linux-modules-${KVER}" "linux-modules-extra-${KVER}"; do
    download_with_deps "${pkg}"
  done
  echo "Kernel ${KVER} cached for reference only. Prefer the full image (A3) for kernel reproduction." \
    > "${OUT}/KERNEL_CAVEAT.txt"
fi

# 4. Offline installer.
cat > "${OUT}/install_system_offline.sh" <<'INSTALL'
#!/usr/bin/env bash
# Install the cached Intel GPU user-space stack offline. Requires root.
# This modifies system packages -> run only on a disposable/intended test host.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ "$(id -u)" -eq 0 ] || { echo "run as root (sudo)"; exit 1; }
echo "Installing cached .debs from ${HERE}/debs (offline)..."
dpkg -i "${HERE}"/debs/*.deb || {
  echo "dpkg reported unmet deps; attempting offline fixup from the same dir..."
  dpkg -i "${HERE}"/debs/*.deb
}
echo "Done. Verify with: clinfo && ze_info"
INSTALL
chmod +x "${OUT}/install_system_offline.sh"

write_sha256_manifest "${OUT}"
log "system freeze complete: ${OUT}"
echo "${SNAPSHOT}"
