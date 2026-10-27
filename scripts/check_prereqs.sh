#!/usr/bin/env bash
# check_prereqs.sh — READ-ONLY prerequisite check for PyTorch-on-Arc-A770 work.
# Verifies the SYSTEM-level oneAPI / Level Zero / i915 stack that torch.xpu needs.
# Installs nothing, changes nothing. Prints a PASS/WARN/FAIL report and exits non-zero
# only if a HARD prerequisite is missing AND an Intel GPU appears to be present.
set -uo pipefail

PASS=0; WARN=0; FAIL=0
ARC_PRESENT="unknown"

ok()   { echo "  [PASS] $*"; PASS=$((PASS+1)); }
warn() { echo "  [WARN] $*"; WARN=$((WARN+1)); }
bad()  { echo "  [FAIL] $*"; FAIL=$((FAIL+1)); }
have() { command -v "$1" >/dev/null 2>&1; }

echo "== arc-a770-lab PyTorch/XPU prerequisite check =="
echo "   (read-only; nothing is installed or modified)"

# --- 1. GPU presence and model -------------------------------------------------
echo; echo "[1] GPU hardware"
if have lspci; then
  GPU_LINE="$(lspci -nn | grep -Ei 'VGA|3D|Display' | grep -i '8086' || true)"
  if [ -n "${GPU_LINE}" ]; then
    echo "      ${GPU_LINE}"
    if echo "${GPU_LINE}" | grep -qiE '56a0|56a1|arc|a770'; then
      ARC_PRESENT="true";  ok "Intel Arc (A-series) GPU detected"
    else
      ARC_PRESENT="false"; warn "Intel GPU found but not an Arc A-series (A770 PCI id 8086:56a0)"
    fi
  else
    ARC_PRESENT="false"; warn "No Intel GPU found via lspci"
  fi
else
  warn "lspci not available; cannot confirm GPU model"
fi

# --- 2. Kernel driver ----------------------------------------------------------
echo; echo "[2] Kernel driver (i915 / xe)"
if lsmod 2>/dev/null | grep -qE '^(i915|xe)\b'; then
  ok "$(lsmod | grep -E '^(i915|xe)\b' | awk '{print $1}' | paste -sd, -) module loaded"
else
  warn "neither i915 nor xe module is loaded"
fi

# --- 3. Render nodes + permissions --------------------------------------------
echo; echo "[3] Render node access"
RN_FOUND=0
for n in /dev/dri/renderD*; do
  [ -e "$n" ] || continue
  RN_FOUND=1
  if [ -r "$n" ] && [ -w "$n" ]; then
    ok "read/write access to $n"
  else
    bad "no read/write access to $n (add user to 'render' group)"
  fi
done
[ "${RN_FOUND}" -eq 0 ] && warn "no /dev/dri/renderD* nodes present"

# --- 4. Level Zero loader ------------------------------------------------------
echo; echo "[4] Level Zero loader (libze_loader)"
if ldconfig -p 2>/dev/null | grep -qi 'libze_loader'; then
  ok "libze_loader present: $(ldconfig -p | grep -i libze_loader | head -1 | awk '{print $NF}')"
else
  warn "libze_loader not found (install level-zero runtime for torch.xpu)"
fi
if have ze_info; then ok "ze_info available"; else warn "ze_info not found (level-zero-devel/tools)"; fi

# --- 5. Compute runtime (NEO) --------------------------------------------------
echo; echo "[5] Intel Compute Runtime (NEO)"
if ldconfig -p 2>/dev/null | grep -qiE 'libze_intel_gpu|libigdrcl'; then
  ok "Intel GPU compute runtime libraries present"
else
  warn "intel-opencl-icd / libze-intel-gpu not detected"
fi

# --- 6. oneAPI runtime (SYCL) --------------------------------------------------
echo; echo "[6] oneAPI / SYCL runtime"
if ldconfig -p 2>/dev/null | grep -qi 'libsycl'; then
  ok "libsycl present"
elif [ -d /opt/intel/oneapi ]; then
  warn "/opt/intel/oneapi exists but libsycl not on linker path (source setvars.sh?)"
else
  warn "oneAPI/SYCL runtime not detected (needed by some torch.xpu builds)"
fi

# --- 7. clinfo sanity ----------------------------------------------------------
echo; echo "[7] OpenCL device enumeration"
if have clinfo; then
  DEVS="$(clinfo 2>/dev/null | grep -c 'Device Name' || true)"
  ok "clinfo reports ${DEVS} device entry(ies)"
else
  warn "clinfo not installed (clinfo package)"
fi

# --- Summary -------------------------------------------------------------------
echo; echo "== Summary: ${PASS} pass, ${WARN} warn, ${FAIL} fail =="
echo "   Arc A-series present: ${ARC_PRESENT}"
echo "   Next: ./scripts/check_pytorch_xpu.py for the framework-level check."

# Only fail the script when hard prereqs are missing AND an Arc GPU is actually here.
if [ "${ARC_PRESENT}" = "true" ] && [ "${FAIL}" -gt 0 ]; then
  exit 1
fi
exit 0
