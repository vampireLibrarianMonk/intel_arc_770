#!/usr/bin/env bash
# verify_b1_b2.sh — READ-ONLY. Run AFTER the B1 reboot to confirm the A770 bound and a
# render node exists. Changes nothing; safe for the Kiro agent to run.
set -uo pipefail
PASS=0; FAIL=0
ok()  { echo "  [PASS] $*"; PASS=$((PASS+1)); }
bad() { echo "  [FAIL] $*"; FAIL=$((FAIL+1)); }

echo "== verify B1/B2 — A770 bind + render node =="
echo "   kernel: $(uname -r)"

echo; echo "[1] i915 bound to GPU"
if lspci -vnnk -s 2d:00.0 2>/dev/null | grep -qi 'Kernel driver in use: i915'; then
  ok "i915 is bound to 2d:00.0"
else
  bad "i915 NOT bound to 2d:00.0 — B1 not effective yet"
  lspci -vnnk -s 2d:00.0 2>/dev/null | sed 's/^/      /'
fi

echo; echo "[2] i915 knows 56a0"
if modinfo i915 2>/dev/null | grep -qi '56a0'; then
  ok "i915 advertises 56a0 alias"
else
  bad "i915 has no 56a0 alias (old kernel still booted?)"
fi

echo; echo "[3] render node"
if [ -e /dev/dri/renderD128 ]; then
  ok "render node present: $(ls -l /dev/dri/renderD128)"
  if [ -r /dev/dri/renderD128 ] && [ -w /dev/dri/renderD128 ]; then
    ok "current user can read/write it"
  else
    bad "no rw access — ensure user is in 'render' group and re-login"
  fi
else
  bad "/dev/dri/renderD128 missing"
fi

echo; echo "[4] render group membership"
if id -nG | tr ' ' '\n' | grep -qx render; then
  ok "user in render group"
else
  bad "user not in render group (re-login or newgrp render after usermod)"
fi

echo; echo "== $PASS pass, $FAIL fail =="
[ "$FAIL" -eq 0 ] && echo "B1/B2 look good → proceed to B3 (compute user-space)." \
  || echo "Resolve failures before B3."
exit 0
