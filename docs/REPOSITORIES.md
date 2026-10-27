# Repository map & pinned revisions

Clone into `vendor/` (git-ignored). **Pin a release before comparing performance or compiling a
modified NEO.** NEO's `manifests/manifest.yml` is the source of truth for matching IGC/GmmLib.

## Priority order

| Priority | Repository | Role | Clone timing |
|:--|:--|:--|:--|
| P0 | [intel/compute-runtime](https://github.com/intel/compute-runtime) | NEO: OpenCL + Level Zero, allocation limits | Immediately |
| P0 | [intel/compute-benchmarks](https://github.com/intel/compute-benchmarks) | Intel compute-driver microbenchmarks | Immediately |
| P0 | [intel/opencl-intercept-layer](https://github.com/intel/opencl-intercept-layer) | OpenCL call interception; `RelaxAllocationLimits` | Immediately |
| P1 | [intel/intel-graphics-compiler](https://github.com/intel/intel-graphics-compiler) | IGC: stateful/stateless code generation | Read now, build after baseline |
| P1 | [intel/gmmlib](https://github.com/intel/gmmlib) | Graphics memory management lib used by NEO | When assembling source builds |
| P1 | [oneapi-src/level-zero](https://github.com/oneapi-src/level-zero) | L0 headers, loader, validation layers | When adding L0 harness |
| P1 | [oneapi-src/level-zero-tests](https://github.com/oneapi-src/level-zero-tests) | L0 conformance/stress/perf | L0 phase |
| P2 | [intel/opencl-clang](https://github.com/intel/opencl-clang) | IGC OpenCL front-end | Compiler phase |
| P2 | [KhronosGroup/SPIRV-LLVM-Translator](https://github.com/KhronosGroup/SPIRV-LLVM-Translator) | SPIR-V ↔ LLVM | Compiler phase |
| P2 | [llvm/llvm-project](https://github.com/llvm/llvm-project) | LLVM/Clang dependency | Compiler phase |
| P2 | [intel/vc-intrinsics](https://github.com/intel/vc-intrinsics) | Vector compiler intrinsics | Compiler phase |
| P3 | [mesa/mesa](https://gitlab.freedesktop.org/mesa/mesa) | Vulkan/OpenGL user-space driver | Only if a graphics issue appears |
| P3 | [torvalds/linux](https://github.com/torvalds/linux) | `i915`/`xe` kernel components | Only after kernel-level evidence |

**Historical reference only:** [intel/compute-samples](https://github.com/intel/compute-samples) is
archived/unsupported; do not rely on it as a maintained suite.

## Pinned SHA table — fill in during Phase 0

| Component | Release tag | SHA | Source of pin | Date recorded |
|:--|:--|:--|:--|:--|
| compute-runtime (NEO) | `TO_RECORD` | `TO_RECORD` | release tag | `TO_RECORD` |
| intel-graphics-compiler (IGC) | `TO_RECORD` | `TO_RECORD` | NEO manifest.yml | `TO_RECORD` |
| gmmlib | `TO_RECORD` | `TO_RECORD` | NEO manifest.yml | `TO_RECORD` |
| level-zero (loader) | `TO_RECORD` | `TO_RECORD` | release tag | `TO_RECORD` |
| opencl-clang | `TO_RECORD` | `TO_RECORD` | IGC build guide | `TO_RECORD` |
| SPIRV-LLVM-Translator | `TO_RECORD` | `TO_RECORD` | IGC build guide | `TO_RECORD` |
| llvm-project | `TO_RECORD` | `TO_RECORD` | IGC build guide | `TO_RECORD` |
| vc-intrinsics | `TO_RECORD` | `TO_RECORD` | IGC build guide | `TO_RECORD` |

## Essential documentation

- NEO large-allocation guide: <https://github.com/intel/compute-runtime/blob/master/programmers-guide/ALLOCATIONS_GREATER_THAN_4GB.md>
- NEO build: <https://github.com/intel/compute-runtime/blob/master/documentation/BUILD.md>
- NEO manifest: <https://github.com/intel/compute-runtime/blob/master/manifests/manifest.yml>
- IGC Ubuntu build: <https://github.com/intel/intel-graphics-compiler/blob/master/documentation/build_ubuntu.md>
- OpenCL Intercept Layer controls: <https://github.com/intel/opencl-intercept-layer/blob/main/docs/controls.md>
- Intel i915 supported hardware: <https://dgpu-docs.intel.com/overview/supported-hardware/i915-driver-gpus.html>
