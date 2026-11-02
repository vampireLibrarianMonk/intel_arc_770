#!/usr/bin/env bash
# common.sh — shared paths/helpers for harness-alpha setup. Source this, don't run it.
# No sudo, no system installs: everything lands under a per-cycle prefix (steering rule).

# Resolve repo root from this file's location (setup/ -> harness-alpha/ -> llm/ -> repo).
HA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$HA_DIR/../.." && pwd)"

# Everything heavy is git-ignored (under artifacts/).
PREFIX="$REPO_ROOT/artifacts/harness-alpha"
MODELS_DIR="$PREFIX/models"
BUILD_DIR="$PREFIX/build"
BIN_DIR="$PREFIX/bin"
LOG_DIR="$PREFIX/logs"

# The one shared GGUF model all GGUF candidates use (apples-to-apples).
# bartowski's repo ships a single-file Q4_K_M (the official Qwen GGUF repo splits it).
MODEL_REPO="${MODEL_REPO:-bartowski/Qwen2.5-7B-Instruct-GGUF}"
MODEL_FILE="${MODEL_FILE:-Qwen2.5-7B-Instruct-Q4_K_M.gguf}"
MODEL_PATH="$MODELS_DIR/$MODEL_FILE"
# Authoritative integrity values from the HF LFS metadata (verified, not guessed). A model
# that downloads to the right SIZE can still be byte-corrupt (e.g. interrupted/dup writes);
# only the sha256 proves it. The benchmark must never run on an unverified model.
MODEL_SHA256="${MODEL_SHA256:-65b8fcd92af6b4fefa935c625d1ac27ea29dcb6ee14589c55a8f115ceaaa1423}"
MODEL_SIZE_BYTES="${MODEL_SIZE_BYTES:-4683074240}"

mkdir -p "$MODELS_DIR" "$BUILD_DIR" "$BIN_DIR" "$LOG_DIR"

# The Intel SYCL/OpenCL runtime libraries already live inside .venv-xpu — reuse them for the
# llama.cpp SYCL build instead of installing a system oneAPI toolkit.
XPU_VENV="$REPO_ROOT/.venv-xpu"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }
