#!/usr/bin/env bash
# capture_baseline.sh — READ-ONLY Arc A770 environment inventory.
# Does NOT install, modify firmware/kernel/bootloader, or touch driver packages.
# Writes raw logs + a merged environment.json under artifacts/baseline/<timestamp>/.
set -uo pipefail

TS="$(date -u +%Y%m%dT%H%M%SZ)"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${ROOT}/artifacts/baseline/${TS}"
mkdir -p "${OUT}"
RAW="${OUT}/raw.txt"

log() { echo "== $* =="; }
run() { # run <label> <cmd...>  -> append to raw, never fatal
  local label="$1"; shift
  { echo; echo "### ${label}"; echo "\$ $*"; "$@" 2>&1; echo "[exit=$?]"; } >>"${RAW}" || true
}

echo "arc-a770-lab baseline capture ${TS}" >"${RAW}"

run "uname" uname -a
run "os-release" cat /etc/os-release
run "lspci-gpu" bash -c "lspci -nnk | grep -A5 -Ei 'VGA|3D|Display'"
run "dev-dri" bash -c "ls -la /dev/dri /dev/dri/by-path 2>/dev/null"
run "modules" bash -c "lsmod | grep -E '^(i915|xe)\b'"
run "clinfo" bash -c "command -v clinfo >/dev/null && clinfo | grep -Ei 'Device Name|Global memory size|Max memory allocation'"
run "clinfo-full" bash -c "command -v clinfo >/dev/null && clinfo"
run "ze_info" bash -c "command -v ze_info >/dev/null && ze_info"
run "rebar" bash -c "lspci -vv 2>/dev/null | grep -A2 -i 'resizable bar'"
run "dmesg-gpu" bash -c "journalctl -k -b --no-pager 2>/dev/null | grep -Ei 'i915|xe|drm|guc|gpu|hang|reset' | tail -150"

# --- Permissions probe (read-only): can we open a render node? ---
RENDER_RW="false"
for n in /dev/dri/renderD*; do
  [ -e "$n" ] || continue
  if [ -r "$n" ] && [ -w "$n" ]; then RENDER_RW="true"; fi
done
run "render-node-rw" bash -c "echo render_node_rw=${RENDER_RW}"

# --- Extract a few values for the JSON (best-effort) ---
OS_NAME="$(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-}")"
KERNEL="$(uname -r)"
PCI_ID="$(lspci -nn 2>/dev/null | grep -Ei 'VGA|3D|Display' | grep -oE '8086:[0-9a-fA-F]{4}' | head -1)"
RENDER_NODES="$(ls -1 /dev/dri/renderD* 2>/dev/null | paste -sd, -)"
CL_DEV="$(command -v clinfo >/dev/null && clinfo 2>/dev/null | grep -E 'Device Name' | head -1 | sed 's/.*Device Name[[:space:]]*//')"
L0_PRESENT="false"; command -v ze_info >/dev/null && L0_PRESENT="true"

cat >"${OUT}/environment.json" <<JSON
{
  "captured_at": "${TS}",
  "host": {"os": "${OS_NAME}", "kernel": "${KERNEL}"},
  "gpu": {"pci_id": "${PCI_ID:-unknown}", "render_nodes": "${RENDER_NODES:-}"},
  "opencl": {"device_name": "${CL_DEV:-unknown}"},
  "level_zero": {"present": ${L0_PRESENT}},
  "permissions": {"render_node_rw": ${RENDER_RW}},
  "versions": {"neo": "TO_RECORD", "igc": "TO_RECORD", "gmmlib": "TO_RECORD"},
  "notes": ["raw log at raw.txt", "versions require clinfo/package query on hardware"]
}
JSON

echo "Baseline written to: ${OUT}"
echo "  - raw.txt"
echo "  - environment.json"
