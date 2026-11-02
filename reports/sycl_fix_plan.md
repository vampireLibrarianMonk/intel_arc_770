# Plan: fix (or rule out) the llama.cpp SYCL crash on the Arc A770

## The problem, precisely

`llama.cpp` SYCL build **compiles cleanly but SEGVs during model load** (`llama-cli` and
`llama-server`), reproducibly, on this stack:

| component | our version | notes |
|:--|:--|:--|
| llama.cpp | `dde879b` (2026-11-01) | current HEAD |
| oneAPI DPC++/C++ | **2026.2.0** | compiler used to build |
| oneDNN / oneMKL | 3.13.2 / 2026.2 | |
| **NEO compute-runtime** | **24.39.31294** | the loaded GPU driver (from bring-up) |
| Level-Zero loader | `/usr/lib/x86_64-linux-gnu/libze_loader.so` | distro package |
| kernel | 6.8.0-138 | i915 |

Crash signatures seen:
- With oneDNN: `ggml_sycl_dnnl_detect_optimized_gemm: oneDNN matmul probe failed on device 0
  (could not create an engine)` → SEGV.
- With `-DGGML_SYCL_DNN=OFF`: SEGV in "Loading model…".
- `-fa 0` (disable Flash Attention) did **not** reliably fix it (one run survived, next SEGV'd).

## Leading hypothesis (most likely first)

1. **Toolchain ⇄ driver version skew.** We built against oneAPI **2026.2** but the GPU is
   driven by **NEO 24.39** (Sept-2024) and the distro Level-Zero loader. A SYCL binary from a
   year-newer toolchain running on an older Level-Zero/NEO runtime is a classic cause of
   load-time SEGV. Our own steering flags exactly this ("a compiled runtime is not
   necessarily the one that loads").
2. **oneDNN GPU-engine incompatibility** with NEO 24.39 ("could not create an engine").
3. **A real llama.cpp SYCL regression** at HEAD for Arc/Qwen2 (the GitHub issues show a
   moving target: #20423 Qwen3.5 needs `-fa 0`; #8294 multi-GPU SEGV; #5469 F16 SEGV).

## Fix strategy — cheapest / most-local first

### Step 0 — prove which Level-Zero/NEO actually loads (no downloads)
```bash
source /opt/intel/oneapi/setvars.sh --force
ZE_ENABLE_LOADER_DEBUG=1 SYCL_UICI=1 sycl-ls           # which platforms/drivers resolve
ldd artifacts/harness-alpha/build/llama.cpp/build-sycl/bin/llama-cli | grep -iE "ze_loader|sycl|pi_"
```
Record the resolved `libze_intel_gpu.so` / NEO path. If the loaded NEO ≠ what oneAPI 2026.2
expects, that confirms hypothesis #1. **This is free and must be done before any rebuild.**

### Step 1 — align the toolchain DOWN to the driver (local, no driver change)
The steering says driver changes are human-approval-required, so **don't upgrade NEO**.
Instead build llama.cpp SYCL with an **older oneAPI that matches NEO 24.39** (oneAPI 2024.2 /
2025.0 era). Install a second, pinned compiler into `/opt/intel` (apt supports versioned
packages) and rebuild:
```bash
apt-get install -y intel-oneapi-compiler-dpcpp-cpp-2025.0.4   # matches the NEO 24.39 era
source /opt/intel/oneapi/2025.0/oneapi-vars.sh
# rebuild build-sycl with CC=icx CXX=icpx from 2025.0, GGML_SYCL_DNN=OFF first
```
Cost: ~1 GB download, one rebuild. **Highest expected payoff.**

### Step 2 — try a KNOWN-GOOD llama.cpp tag, not HEAD (local git, tiny download)
HEAD moves fast and Arc SYCL regressions are common. Check out a release tag that the
community reports working on Arc, e.g. a recent `b####` tag referenced in a working issue:
```bash
cd artifacts/harness-alpha/build/llama.cpp
git fetch --tags --depth=1
git checkout <known-good-tag>      # e.g. a build cited in issue #20423 as working
# rebuild build-sycl
```
Cost: a few MB. Bisect between a known-good tag and HEAD if needed.

### Step 3 — apply the community workarounds as build/run flags (free)
From the forums (ggml-org/llama.cpp issues #20423, #8294; Intel community thread on B70):
- Run with `-fa 0` AND single slot (`--parallel 1`) AND `-DGGML_SYCL_DNN=OFF`.
- `export GGML_SYCL_DISABLE_OPT=1` / try `SYCL_PI_LEVEL_ZERO_USE_IMMEDIATE_COMMANDLISTS=0`.
- Try `-DGGML_SYCL_F16=OFF` (issue #5469 tied a SYCL SEGV to F16).
- Reduce `-ngl` to find a safe layer ceiling (markaicode: SYCL/OpenCL SEGV often = VRAM
  layout/OOM, not a pure bug).
Each is a rebuild-or-rerun with no new downloads; cheap to sweep.

### Step 4 — if still broken, cherry-pick the specific fix commit (local patch)
The repo `Hal9000AIML/arc-pro-b70-ubuntu-gpu-speedup-bugfixes` publishes **11 llama.cpp
cherry-picks** fixing Arc SYCL crashes (slot-init SEGV, Q8_0 reorder crash, OOM reorder,
wrong Xe2 warptile, etc.). Clone it, read which commits apply to A770 (Alchemist, not just
B70/Xe2), and apply the relevant ones onto our checkout as a reviewable patch under
`patches/`:
```bash
git clone --depth 50 https://github.com/Hal9000AIML/arc-pro-b70-ubuntu-gpu-speedup-bugfixes vendor/arc-b70-fixes
# review its cherry-picks; apply the A770-relevant ones to build-sycl; rebuild
```
Cost: small clone. This is the "do work locally" path if upstream hasn't fixed it.

### Step 5 — file / confirm upstream (if we find a genuine new bug)
If Steps 1-4 isolate a real regression at a specific commit with our exact stack, open a
llama.cpp issue with: GPU PCI id, NEO 24.39, oneAPI version, the `b####` tag, exact repro
command, and the backtrace. This matches our AGENTS.md reporting contract and may get an
upstream fix faster than maintaining a local patch.

## Repos to clone for this work (all git-ignored under vendor/)

| repo | why | size |
|:--|:--|:--|
| `ggml-org/llama.cpp` (already have `dde879b`) | bisect tags, rebuild per step | have it |
| `Hal9000AIML/arc-pro-b70-ubuntu-gpu-speedup-bugfixes` | ready-made Arc SYCL crash cherry-picks | small |
| `intel/compute-runtime` (NEO) | ONLY to read release notes / match versions — **do not** replace the loaded driver without human approval | n/a (docs) |
| `oneapi-src/oneDNN` | read GPU-engine support matrix vs NEO 24.39 (hypothesis #2) | docs only |

## Decision gates (keep it honest)

- A SYCL build that runs but is **slower than Vulkan** is not worth adopting — Vulkan already
  gives 40 tok/s and 4/4 correctness. SYCL is only worth fixing if it is **faster AND
  correct** (verify tok/s and the coding/writing scores, not just "it loads").
- Stop after Step 2 if a known-good tag works — that's the cheapest win.
- Do not change NEO/kernel/driver packages to chase this; that is out of scope per steering
  and risks the verified bring-up. Align the toolchain to the driver, not the reverse.

## Order of operations (recommended)

1. Step 0 (prove loaded driver) — 5 min, free.
2. Step 2 (known-good llama.cpp tag, rebuild, retest) — cheapest likely fix.
3. Step 1 (oneAPI 2025.0 matched to NEO 24.39) — if HEAD-vs-tag wasn't it.
4. Step 3 flag sweep — in parallel, free.
5. Step 4 cherry-picks — only if 1-3 fail.
6. Step 5 upstream report — if a genuine new bug is isolated.

---

## RESOLUTION (alpha exploration complete)

SYCL is **fixed and now runs correctly** on this A770 stack. The exploration found the crash
was **not** the toolchain⇄driver version skew (that was a red herring) but **two distinct
bugs**, both dodged at build/run time with no driver change:

### Root cause 1 — Level-Zero Sysman memory query SEGV (model-load crash)
`gdb` backtrace showed the first SEGV in `query_free_memory_by_ze` →
`zesDeviceEnumMemoryModules` inside `libze_intel_gpu.so` (NEO 24.39). llama.cpp's SYCL
backend calls the Level-Zero **Sysman** API to query free VRAM during load; NEO 24.39 SEGVs
on it instead of returning an error.
**Fix:** build with `-DGGML_SYCL_SUPPORT_LEVEL_ZERO_API=OFF` (plus `-DGGML_SYCL_DNN=OFF` for
the separate oneDNN "could not create an engine" failure). Falls back to the pure SYCL
memory query, which NEO 24.39 handles.

### Root cause 2 — oneAPI 2026.2 persistent device-code cache SEGV (first-kernel crash)
After fixing #1, a second `gdb` backtrace showed a SEGV in `__strcmp_avx2` ←
`sycl::detail::getSortedImages` ← `PersistentDeviceCodeCache::getItemFromDisc` inside
`libsycl.so.9` (oneAPI 2026.2), on the first GPU kernel launch (`ggml_sycl_op_bin_bcast`).
The persistent device-code cache is buggy on this stack (crashes whether the cache is warm,
cleared, or being written).
**Fix:** run with `SYCL_CACHE_PERSISTENT=0`. Trade-off: SYCL kernels recompile each process
start (slower first token); steady-state throughput is unaffected.

### Both fixes are now wired in
- `llm/harness-alpha/setup/llamacpp_sycl.sh`: `-DGGML_SYCL_SUPPORT_LEVEL_ZERO_API=OFF
  -DGGML_SYCL_DNN=OFF`.
- `llm/harness-alpha/run/run_llamacpp.sh`: exports `SYCL_CACHE_PERSISTENT=0` for the SYCL
  backend (keeps it `=1` for Vulkan).

### Verified result

| candidate | backend | coding (exec) | writing | median tok/s |
|:--|:--|:--:|:--:|--:|
| llamacpp-vulkan | Vulkan | 4/4 | 4/4 | **40.2** |
| lmstudio | Vulkan | 4/4 | 4/4 | 37.4 |
| **llamacpp-sycl** | SYCL | **4/4** | **4/4** | **33.9** |
| ipex-llm | XPU | 3/4 | 4/4 | 16.6 |

### The honest punchline
SYCL now works and is correct — but at **33.9 tok/s it is SLOWER than Vulkan (40.2)**, because
stability required disabling oneDNN (optimized GEMM) and the persistent kernel cache. So on
this exact stack (NEO 24.39 + oneAPI 2026.2 + llama.cpp HEAD), **Vulkan remains the
recommended backend** — the theoretically faster SYCL path loses its advantage once made
stable. A future NEO driver upgrade (human-approval-gated) that fixes the Sysman + cache
crashes would let us re-enable oneDNN + persistent cache and re-test whether SYCL regains the
lead. Until then, the recommendation stands: **llama.cpp Vulkan**.
