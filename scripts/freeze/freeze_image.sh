#!/usr/bin/env bash
# freeze_image.sh — A3: full VM/disk image guidance + guarded capture.
#
# A full image is the only format that reproduces the KERNEL + i915 driver together with
# user space. It is large and host-specific, so this script is deliberately conservative:
#   * It never images a mounted/live root filesystem automatically.
#   * For a VM qcow2 it performs a guarded copy only when you pass the explicit path and
#     confirm the guest is powered off.
#   * For bare metal it emits step-by-step guidance rather than running dd on a live disk.
#
# Usage (VM qcow2 copy):
#   scripts/freeze/freeze_image.sh --i-say-so --note="..." --qcow2=/path/guest.qcow2 --powered-off
# Usage (bare-metal guidance only):
#   scripts/freeze/freeze_image.sh --i-say-so --note="..." --guidance
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

SNAPSHOT=""; QCOW2=""; POWERED_OFF=0; GUIDANCE=0
for arg in "$@"; do case "$arg" in
  --snapshot=*)  SNAPSHOT="${arg#--snapshot=}";;
  --qcow2=*)     QCOW2="${arg#--qcow2=}";;
  --powered-off) POWERED_OFF=1;;
  --guidance)    GUIDANCE=1;;
esac; done
NOTE="$(require_good_run_confirmation "$@")"
[ -n "${SNAPSHOT}" ] || SNAPSHOT="${FREEZE_ROOT_DEFAULT}/$(freeze_timestamp)"
OUT="${SNAPSHOT}/image"
mkdir -p "${OUT}"

log "A3 full-image freeze (note: ${NOTE})"

write_guidance() {
  cat > "${OUT}/FULL_IMAGE_GUIDANCE.md" <<'DOC'
# A3 — Full image freeze guidance

A full image captures kernel + i915 + user space together: the highest-fidelity,
largest, most host-specific format. Choose the path matching your setup.

## If the good run was in a KVM/QEMU guest (recommended)
1. **Power off the guest** (clean shutdown, not pause).
2. Copy the qcow2 and compress:
   ```bash
   qemu-img convert -O qcow2 -c guest.qcow2 arc-a770-good-run.qcow2
   sha256sum arc-a770-good-run.qcow2 > arc-a770-good-run.qcow2.sha256
   ```
3. Record the exact VM definition (CPU, RAM, PCIe passthrough topology):
   ```bash
   virsh dumpxml <domain> > domain.xml
   ```
4. Keep `domain.xml` + the qcow2 + checksum together. Future restore: import the
   qcow2 and re-create the domain, preserving the A770 passthrough config.

## If the good run was on bare metal
A live root filesystem must NOT be imaged with dd while mounted. Instead:
1. Boot a live USB (so the target disk is unmounted).
2. Image the device:
   ```bash
   sudo dd if=/dev/<disk> bs=64M status=progress | zstd -o arc-a770-good-run.img.zst
   sha256sum arc-a770-good-run.img.zst > arc-a770-good-run.img.zst.sha256
   ```
3. Record `lsblk`, partition table (`sfdisk -d`), and bootloader config.

## Honest caveats
- Full images are tied to the hardware/VM topology they were captured on. Restoring onto
  materially different hardware may not boot or may not see the A770.
- This is the only format that preserves the kernel/i915 pairing; prefer it if kernel-level
  reproduction matters. Otherwise A1 (user-space bundle) + A2 (container) are lighter.
DOC
  log "wrote ${OUT}/FULL_IMAGE_GUIDANCE.md"
}

write_guidance

if [ -n "${QCOW2}" ]; then
  have qemu-img || die "qemu-img not found; install qemu-utils or use --guidance"
  [ -f "${QCOW2}" ] || die "qcow2 not found: ${QCOW2}"
  [ "${POWERED_OFF}" -eq 1 ] || die "refusing to copy a possibly-running guest; pass --powered-off after a clean shutdown"
  log "compressing qcow2 -> ${OUT}/arc-a770-good-run.qcow2 (this can take a while)"
  qemu-img convert -O qcow2 -c "${QCOW2}" "${OUT}/arc-a770-good-run.qcow2"
  log "qcow2 captured"
elif [ "${GUIDANCE}" -eq 1 ]; then
  log "guidance-only mode: no image captured. See FULL_IMAGE_GUIDANCE.md"
else
  warn "no --qcow2 and no --guidance: wrote guidance only. Nothing imaged."
fi

write_sha256_manifest "${OUT}"
log "image freeze step complete: ${OUT}"
echo "${SNAPSHOT}"
