#!/usr/bin/env bash
# b5_enable_guc.sh — OPERATOR-RUN, PRIVILEGED. Fixes A770 compute hang by enabling the
# i915 GuC/HuC firmware loader via a kernel boot flag.
#
# WHY: torch.xpu enumerates the A770 and tiny allocs work, but any real GPU kernel
# (e.g. a 4096x4096 matmul) hangs at 0% CPU forever. On DG2/Alchemist, compute
# submission needs GuC-based submission. Without i915.enable_guc=3 (GuC + HuC),
# the card accepts work but never completes it. The current boot has NO guc flag set.
#
# WHAT IT DOES:
#   1. Reads the live enable_guc value (diagnostic, read-only).
#   2. Appends i915.enable_guc=3 to GRUB_CMDLINE_LINUX_DEFAULT in /etc/default/grub.
#   3. Runs update-grub.
#   RESTART REQUIRED afterward for the flag to take effect.
#
# SAFETY:
#   - Run as root / with sudo in a REAL shell (the Kiro agent cannot run this).
#   - Backs up /etc/default/grub to /etc/default/grub.bak-YYYYMMDD-HHMMSS first.
#   - Idempotent: if i915.enable_guc is already in the cmdline, it does nothing.
#   - UNDO: restore the backup file and re-run update-grub, then reboot.
#   - Does NOT touch which kernel boots; 5.15 and 6.8 both remain in the GRUB menu.
#   - --dry-run prints the plan and changes nothing.
set -euo pipefail

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1
run() { echo "+ $*"; [ "$DRY_RUN" -eq 1 ] || eval "$*"; }

if [ "$(id -u)" -ne 0 ] && [ "$DRY_RUN" -eq 0 ]; then
  echo "ERROR: run as root (sudo $0) or use --dry-run" >&2
  exit 1
fi

GRUB=/etc/default/grub
FLAG="i915.enable_guc=3"

echo "== B5: enable i915 GuC/HuC for A770 compute =="
echo "   dry-run: $DRY_RUN"
echo

echo "[1/4] Live GuC state (read-only)"
echo "+ cat /sys/module/i915/parameters/enable_guc"
cat /sys/module/i915/parameters/enable_guc 2>/dev/null || echo "(unreadable without root/now)"
echo "+ grep enable_guc /proc/cmdline"
grep -o "i915.enable_guc=[0-9]*" /proc/cmdline || echo "(no guc flag in current cmdline)"
echo

echo "[2/4] Check if flag already present in $GRUB"
if grep -q "i915.enable_guc=" "$GRUB"; then
  echo "   already set in $GRUB — nothing to change:"
  grep "GRUB_CMDLINE_LINUX_DEFAULT" "$GRUB"
  echo "== B5: no change needed. If the running cmdline lacks it, just reboot. =="
  exit 0
fi

echo "[3/4] Back up and append $FLAG to GRUB_CMDLINE_LINUX_DEFAULT"
TS="$(date +%Y%m%d-%H%M%S)"
run "cp -a '$GRUB' '$GRUB.bak-$TS'"
# Append the flag inside the existing GRUB_CMDLINE_LINUX_DEFAULT="..." quotes.
run "sed -i 's/\\(GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*\\)\"/\\1 $FLAG\"/' '$GRUB'"
echo "   new line:"
grep "GRUB_CMDLINE_LINUX_DEFAULT" "$GRUB"

echo "[4/4] Rebuild GRUB config"
run "update-grub"

echo
echo "== B5 complete. RESTART REQUIRED. =="
echo "After reboot verify:"
echo "    cat /sys/module/i915/parameters/enable_guc   # expect 3"
echo "    grep enable_guc /proc/cmdline                 # expect i915.enable_guc=3"
echo "Then re-run the matmul test; it should finish in seconds."
echo "UNDO: sudo cp -a $GRUB.bak-$TS $GRUB && sudo update-grub && sudo reboot"
