#!/usr/bin/env bash
# b3_compute_userspace.sh — OPERATOR-RUN, PRIVILEGED. Installs the OpenCL + Level Zero
# user-space that torch.xpu needs. Run AFTER B1/B2 (render node exists).
#
# NOTE ON SOURCES:
#   - The stock Ubuntu 22.04 archive has `intel-opencl-icd` (old, 22.14) and `clinfo`,
#     but NO Level Zero packages. torch.xpu REQUIRES Level Zero, so the Intel client-GPU
#     repo is required here.
#   - Repo string and package names VERIFIED against the live repo 2026-10-30:
#       repo:  https://repositories.intel.com/gpu/ubuntu  jammy  client  (arch amd64)
#       pkgs:  intel-opencl-icd  intel-level-zero-gpu  libze1  libze-intel-gpu1
#     Use --skip-repo if the repo was already added.
#
# SAFETY: run as root/sudo in a real shell. --dry-run prints the plan, changes nothing.
set -euo pipefail
DRY_RUN=0; SKIP_REPO=0
for a in "$@"; do case "$a" in
  --dry-run) DRY_RUN=1 ;;
  --skip-repo) SKIP_REPO=1 ;;
  *) echo "unknown arg: $a" >&2; exit 2 ;;
esac; done
run() { echo "+ $*"; [ "$DRY_RUN" -eq 1 ] || "$@"; }
if [ "$(id -u)" -ne 0 ] && [ "$DRY_RUN" -eq 0 ]; then
  echo "ERROR: run as root (sudo $0) or use --dry-run" >&2; exit 1
fi

echo "== B3: OpenCL + Level Zero user-space =="
if [ "$SKIP_REPO" -eq 0 ]; then
  echo "[1/3] Add Intel client-GPU repo (jammy) — strings verified 2026-10-30"
  run bash -c 'wget -qO - https://repositories.intel.com/gpu/intel-graphics.key \
    | gpg --yes --dearmor --output /usr/share/keyrings/intel-graphics.gpg'
  run bash -c 'echo "deb [arch=amd64 signed-by=/usr/share/keyrings/intel-graphics.gpg] \
https://repositories.intel.com/gpu/ubuntu jammy client" \
    > /etc/apt/sources.list.d/intel-gpu-jammy.list'
  run apt-get update
else
  echo "[1/3] skip repo add (already present)"
fi

echo "[2/3] Install compute runtime, Level Zero, tools"
# libze-intel-gpu1 (24.39+) is the CURRENT L0 GPU driver and Provides/Replaces the older
# intel-level-zero-gpu (1.3.x) — install only the new one or apt reports a Breaks conflict.
# libze1 = L0 loader, intel-opencl-icd = OpenCL, clinfo = enumeration.
run apt-get install -y \
  intel-opencl-icd \
  libze-intel-gpu1 libze1 \
  clinfo

echo "[3/3] Verify enumeration (read-only)"
run bash -c 'command -v clinfo >/dev/null && clinfo | grep -Ei "Device Name|Global memory size|Max memory allocation" || echo "clinfo not found"'
run bash -c 'command -v ze_info >/dev/null && ze_info | head -40 || echo "ze_info not installed (optional: intel level-zero tools)"'

echo
echo "== B3 complete. Next: B4 (PyTorch/XPU)."
echo "   Expect clinfo to list the Arc A770 and a Max memory allocation near 4 GiB."
