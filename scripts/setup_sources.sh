#!/usr/bin/env bash
# setup_sources.sh — OPT-IN clone of P0 source repos into vendor/ (git-ignored).
# Does NOT build, install, or replace any driver. Does NOT clone the IGC+LLVM tree.
# Pin a release before comparing performance or compiling a modified NEO.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="${ROOT}/vendor"
mkdir -p "${VENDOR}"

clone() { # clone <url> <dir>
  local url="$1" dir="$2"
  if [ -d "${VENDOR}/${dir}/.git" ]; then
    echo "[skip] ${dir} already cloned"
  else
    echo "[clone] ${url} -> vendor/${dir}"
    git clone --filter=blob:none "${url}" "${VENDOR}/${dir}"
  fi
}

echo "Cloning P0 repositories (documentation/inspection stage)..."
clone https://github.com/intel/compute-runtime.git        compute-runtime
clone https://github.com/intel/compute-benchmarks.git      compute-benchmarks
clone https://github.com/intel/opencl-intercept-layer.git  opencl-intercept-layer

echo
echo "P0 clones complete. NOT cloned yet (compiler phase): IGC, gmmlib, llvm-project,"
echo "opencl-clang, SPIRV-LLVM-Translator, vc-intrinsics, level-zero(+tests)."
echo
echo "Next: inspect NEO's dependency manifest to pin IGC/GmmLib versions:"
echo "  sed -n '1,100p' vendor/compute-runtime/manifests/manifest.yml"
echo "Record pins in docs/REPOSITORIES.md before any build."
