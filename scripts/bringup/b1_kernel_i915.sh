#!/usr/bin/env bash
# b1_kernel_i915.sh — OPERATOR-RUN, PRIVILEGED. Gets the Arc A770 (8086:56a0) to bind on
# this host by installing a kernel whose i915 supports DG2/Alchemist.
#
# WHY: stock kernel 5.15 i915 has no 56a0 alias, so the card never binds and no
# /dev/dri render node appears. DG2 firmware is ALREADY present in /lib/firmware/i915,
# so only the kernel is missing.
#
# ROUTE A (default, recommended, all from stock Ubuntu archive):
#   Install the HWE kernel (linux-image-generic-hwe-22.04 => 6.8.x). No third-party repo,
#   no dkms build. 6.8 i915 has mature A770 support. Lowest risk, fully offline-verifiable.
#
# ROUTE B (alternative): Intel client-GPU repo + i915 backport dkms on 5.15. Use only if
#   you must stay on 5.15. The repo URL/package names below are NOT verified against a live
#   source in this session — confirm against https://dgpu-docs.intel.com before running.
#
# SAFETY:
#   - Run as root / with sudo in a REAL shell (the Kiro agent cannot run this).
#   - RESTART REQUIRED afterward. Have console/recovery access first.
#   - Review every command. --dry-run prints the plan and changes nothing.
#   - Both routes KEEP the 5.15 kernel installed as a GRUB fallback.
set -euo pipefail

ROUTE="A"
DRY_RUN=0
for a in "$@"; do
  case "$a" in
    --dry-run) DRY_RUN=1 ;;
    --route=A) ROUTE="A" ;;
    --route=B) ROUTE="B" ;;
    *) echo "unknown arg: $a" >&2; exit 2 ;;
  esac
done

run() { echo "+ $*"; [ "$DRY_RUN" -eq 1 ] || "$@"; }

if [ "$(id -u)" -ne 0 ] && [ "$DRY_RUN" -eq 0 ]; then
  echo "ERROR: run as root (sudo $0) or use --dry-run" >&2
  exit 1
fi

TARGET_USER="${SUDO_USER:-flaniganp}"
echo "== B1: kernel/i915 bring-up for Arc A770 — route $ROUTE =="
echo "   OS: $(. /etc/os-release; echo "$PRETTY_NAME")  running kernel: $(uname -r)"
echo "   dry-run: $DRY_RUN   target user: $TARGET_USER"
echo

if [ "$ROUTE" = "A" ]; then
  echo "[1/3] apt-get update"
  run apt-get update
  echo "[2/3] Install HWE 6.8 kernel (keeps 5.15 as fallback) + updated firmware"
  run apt-get install -y linux-image-generic-hwe-22.04 linux-headers-generic-hwe-22.04 linux-firmware
  echo "[3/3] Add $TARGET_USER to render,video groups"
  run usermod -aG render,video "$TARGET_USER"
else
  echo "[1/5] Add Intel client-GPU repo (jammy) — VERIFY STRINGS FIRST"
  run bash -c 'wget -qO - https://repositories.intel.com/gpu/intel-graphics.key \
    | gpg --yes --dearmor --output /usr/share/keyrings/intel-graphics.gpg'
  run bash -c 'echo "deb [arch=amd64 signed-by=/usr/share/keyrings/intel-graphics.gpg] \
https://repositories.intel.com/gpu/ubuntu jammy client" \
    > /etc/apt/sources.list.d/intel-gpu-jammy.list'
  echo "[2/5] apt-get update"
  run apt-get update
  echo "[3/5] headers + dkms for $(uname -r)"
  run apt-get install -y "linux-headers-$(uname -r)" dkms
  echo "[4/5] i915 backport dkms + firmware"
  run apt-get install -y intel-i915-dkms intel-fw-gpu
  echo "[5/5] Add $TARGET_USER to render,video groups"
  run usermod -aG render,video "$TARGET_USER"
fi

echo
echo "== B1 complete (route $ROUTE). =="
echo "RESTART REQUIRED. After reboot verify (run scripts/bringup/verify_b1_b2.sh):"
echo "    lspci -vnnk -s 2d:00.0   # expect: Kernel driver in use: i915"
echo "    ls -l /dev/dri/renderD128"
echo "    groups $TARGET_USER       # expect render, video"
