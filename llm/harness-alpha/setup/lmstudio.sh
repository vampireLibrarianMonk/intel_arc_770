#!/usr/bin/env bash
# lmstudio.sh — set up LM Studio headless on the Arc A770 (Vulkan runtime).
#
# LM Studio ships as an AppImage. On a headless server FUSE is often missing, so we extract
# it (--appimage-extract) instead of mounting. We then use the bundled `lms` CLI to: install
# the Vulkan llama.cpp runtime, download the shared model (GGUF), and start the headless
# OpenAI-compatible server. No GUI, no sudo.
set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

APPIMAGE="$PREFIX/tools/LM-Studio.AppImage"
EXTRACT="$PREFIX/tools/lmstudio"
[ -f "$APPIMAGE" ] || die "LM Studio AppImage missing at $APPIMAGE"

if [ ! -d "$EXTRACT/squashfs-root" ]; then
  log "extracting AppImage (no FUSE needed) ..."
  chmod +x "$APPIMAGE"
  mkdir -p "$EXTRACT"
  ( cd "$EXTRACT" && "$APPIMAGE" --appimage-extract >/dev/null 2>&1 ) || \
    die "appimage-extract failed; check $APPIMAGE"
fi

# locate the bundled lms CLI inside the extracted tree
LMS_BIN="$(find "$EXTRACT/squashfs-root" -name lms -type f 2>/dev/null | head -1)"
[ -n "$LMS_BIN" ] || LMS_BIN="$(find "$EXTRACT/squashfs-root" -path '*lms*' -name '*.js' 2>/dev/null | head -1)"
[ -n "$LMS_BIN" ] || die "could not find the lms CLI inside the extracted AppImage"
log "lms CLI: $LMS_BIN"
echo "$LMS_BIN" > "$PREFIX/tools/.lms_path"
log "LM Studio extracted. Runner will bootstrap the CLI and Vulkan runtime."
