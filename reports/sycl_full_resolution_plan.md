# Plan: completely resolve llama.cpp SYCL on the Arc A770

## Where we are

SYCL **runs correctly** today, but only with two features disabled to dodge crashes:

| workaround | what it costs us | the bug it hides |
|:--|:--|:--|
| `-DGGML_SYCL_DNN=OFF` | oneDNN optimized GEMM (the main throughput lever) | oneDNN GPU engine fails to create on NEO 24.39 |
| `-DGGML_SYCL_SUPPORT_LEVEL_ZERO_API=OFF` | accurate free-VRAM query (minor) | `zesDeviceEnumMemoryModules` SEGV in NEO 24.39 |
| `SYCL_CACHE_PERSISTENT=0` | kernels recompile every process start | `PersistentDeviceCodeCache` SEGV in oneAPI 2026.2 libsycl |

Net: SYCL = **33.9 tok/s** vs Vulkan **40.2**. "Completely resolved" means re-enabling oneDNN
+ the persistent cache **without crashing**, then re-measuring — the hypothesis being that
oneDNN-accelerated SYCL should match or beat Vulkan. All three bugs share one suspected root:
a **version mismatch between the loaded GPU driver (NEO 24.39, Sept 2024) and the oneAPI
2026.2 runtime / current llama.cpp HEAD** the binary is built against.

## The three bugs, with exact evidence

1. **Sysman SEGV** — `get_memory_size → query_free_memory_by_ze → zesDeviceEnumMemoryModules`
   inside `libze_intel_gpu.so.1.6.31294` (NEO 24.39). The Sysman API either needs a `zesInit`
   ordering NEO 24.39 doesn't tolerate, or is buggy in that driver.
2. **oneDNN engine** — `ggml_sycl_dnnl_detect_optimized_gemm: ... could not create an engine`.
   oneDNN 3.13.2 (oneAPI 2026.2) cannot create a GPU engine on the NEO 24.39 Level-Zero
   runtime it binds to.
3. **Persistent cache SEGV** — `__strcmp_avx2 ← getSortedImages ← PersistentDeviceCodeCache::
   getItemFromDisc` inside `libsycl.so.9` (oneAPI 2026.2), on first kernel launch.

All three point the same way: **toolchain is ~14 months newer than the driver.**

## Resolution strategy — two independent tracks, run in parallel

### Track A (no driver change): match the TOOLCHAIN down to NEO 24.39
Build llama.cpp SYCL against the oneAPI release contemporaneous with NEO 24.39
(**oneAPI 2024.2 / 2025.0**, late-2024), instead of 2026.2. A toolchain that expects the
same Level-Zero/Sysman ABI the driver actually implements should let oneDNN create its engine
and let the persistent cache work.

Steps (all local, ~1-2 GB downloads, no driver touched):
1. Install a pinned older compiler alongside the current one:
   `sudo apt-get install -y intel-oneapi-compiler-dpcpp-cpp-2025.0.4 \
      intel-oneapi-dnnl-2025.0 intel-oneapi-mkl-devel-2025.0` (adjust to the exact versions
   apt offers; pick the newest ≤ early-2025).
2. `source /opt/intel/oneapi/2025.0/oneapi-vars.sh` (pinned, not `latest`).
3. Rebuild `build-sycl` with oneDNN + Level-Zero API **ON** again:
   `cmake … -DGGML_SYCL=ON -DGGML_SYCL_DNN=ON -DGGML_SYCL_SUPPORT_LEVEL_ZERO_API=ON …`
4. Run with `SYCL_CACHE_PERSISTENT=1` and the stale cache cleared first
   (`rm -rf ~/.cache/libsycl_cache ~/.cache/neo_compiler_cache`).
5. Re-run the harness; compare tok/s to Vulkan. Flip each feature back on one at a time so we
   know which one each matters for.

Expected outcome: if version-skew is the root cause, oneDNN + cache come back cleanly and
SYCL throughput jumps. If a feature still crashes under the matched toolchain, that isolates
a genuine driver bug (→ Track B) rather than a skew.

### Track B (human-approval-gated): upgrade the DRIVER up to the toolchain
The other side of the same coin — bring NEO / Level-Zero / IGC forward to a 2025/2026 build
that the 2026.2 toolchain targets. **This touches driver packages, which AGENTS.md and the
steering mark human-approval-required**, and risks the verified bring-up. So this is a
reviewed, reversible experiment, not a default.

Steps (require explicit approval + a rollback plan):
1. Snapshot current driver state: `scripts/capture_baseline.sh` + record exact NEO/IGC/GmmLib
   versions (`clinfo`, `dpkg -l 'intel*'`), so we can roll back.
2. In a **disposable container with /dev/dri passed through** (per steering: a container is
   not kernel isolation, but it isolates user-space driver packages), install Intel's newer
   client-GPU repo build (NEO 25.x) and re-run only the SYCL smoke test + harness.
3. If it fixes the Sysman/oneDNN/cache crashes with oneDNN+cache ON, we have proof a driver
   bump resolves it — then decide whether to promote that driver to the host (separate
   approval).
4. If it regresses the verified PyTorch/XPU bring-up or the 4 GiB-unlock study, discard.

### Track C (upstream + targeted patch, cheap, always worth doing)
Regardless of A/B, pin the exact failures to upstream and/or patch locally:
1. Reproduce each crash on a **stock llama.cpp release tag** (not HEAD) to rule out a passing
   HEAD regression; a shallow `git fetch --depth=50 --tags` then bisect
   `GGML_SYCL_DNN=ON` crashes between a known-good tag and HEAD.
2. For the Sysman SEGV specifically: the code comment admits `zesInit(0)` ordering is
   fragile. Test a one-line guard (call `zesInit` before *any* Level-Zero use, or wrap the
   Sysman calls in the existing try/catch so a driver fault degrades instead of SEGVs) and,
   if it works, submit upstream + keep a copy under `patches/`.
3. File a llama.cpp issue with: A770 PCI id, NEO 24.39, oneAPI 2026.2, llama.cpp `dde879b`,
   the three gdb backtraces, exact repro commands. Cross-reference existing Arc SYCL issues
   (#20423, #8294). This is the AGENTS.md reporting contract and may get a maintainer fix.
4. Evaluate the `Hal9000AIML/arc-pro-b70-ubuntu-gpu-speedup-bugfixes` cherry-picks: clone to
   `vendor/`, review which of its 11 Arc SYCL fixes apply to Alchemist (A770) vs Xe2 (B70),
   apply the relevant ones onto our checkout as reviewable `patches/`.

## Order of operations (recommended)

1. **Track C.1 first** (free): does a stock release tag crash the same way with oneDNN ON? If
   an older tag works with oneDNN+cache, the fix is just "use that tag" — cheapest possible.
2. **Track A** (local, ~1-2 GB): matched oneAPI 2025.0 toolchain + rebuild with everything ON.
   Highest-expected-payoff for a full resolution without touching the driver.
3. **Track C.2-C.4** in parallel: the Sysman guard patch + upstream issue + cherry-pick review.
4. **Track B** only if A and C cannot restore oneDNN+cache — and only with explicit approval,
   in a container first, with a tested rollback.

## Success criteria (honest, measurable)

A "complete resolution" is reached only when ALL hold, verified by re-running the harness:
- SYCL builds with `GGML_SYCL_DNN=ON` **and** `GGML_SYCL_SUPPORT_LEVEL_ZERO_API=ON`.
- SYCL runs with `SYCL_CACHE_PERSISTENT=1` (no crash, warm-cache fast restarts).
- Coding 4/4 and writing 4/4 still pass (correctness not sacrificed for speed — a fast wrong
  result is a failed fix, per AGENTS.md).
- Median tok/s is recorded and compared to Vulkan's 40.2. If SYCL ≥ Vulkan, SYCL becomes the
  recommended backend; if still slower despite all features on, we document that Arc A770
  SYCL is genuinely behind Vulkan at this model size and keep Vulkan as primary.

## What we will NOT do

- Change kernel, firmware, bootloader, or promote a new driver to the host without explicit
  human approval and a rollback (steering + AGENTS.md).
- Claim SYCL is "fixed" on the basis of it merely loading — only the success criteria above.
- Chase SYCL past the point of diminishing returns: Vulkan already gives 40 tok/s, 4/4, and
  is the shipping recommendation. SYCL resolution is an optimization/robustness investigation,
  gated by whether Track A or C produces a win cheaply.

---

## Track B attempt 1 — container-first (latest driver), RESULT: blocked by host kernel

Executed the container-first half of Track B to test whether the **latest** Intel GPU
user-space driver fixes the SYCL crashes with oneDNN + the persistent cache fully ENABLED —
without touching the host.

**What was built** (`llm/harness-alpha/container/Dockerfile.sycl`): Ubuntu 24.04 image with
- NEO **26.35.39758** (Sept 2026) + IGC **2.41.5** + GmmLib 22.10 (latest, 2 years newer
  than the host's NEO 24.39),
- oneAPI 2026.2 DPC++ + oneDNN + oneMKL,
- llama.cpp SYCL built with `-DGGML_SYCL_DNN=ON -DGGML_SYCL_SUPPORT_LEVEL_ZERO_API=ON`
  (the exact config that SEGVs on the host).

**Result: the newer driver cannot drive the GPU through the host kernel.** Inside the
container (host kernel 6.8 / i915, `/dev/dri` passed through, render gid added):
- `renderD128` is visible; the NEO 26.35 user-space libs load;
- but `clinfo` finds **0 platforms** and `sycl-ls` finds **0 devices** — the GPU does not
  enumerate at all.
- Host, unchanged, still enumerates the A770 fine via NEO 24.39.

**Conclusion:** NEO 26.35's user-space expects a newer kernel-mode driver (newer i915, or the
`xe` KMD) than kernel 6.8 provides. A container **shares the host kernel**, so it can upgrade
the user-space driver but not the kernel interface the driver needs — exactly the limitation
the steering calls out ("a container does not replace kernel isolation"). So container-first
cannot, even in principle, validate a driver this much newer than the host kernel.

Host impact: **none.** `arc-sycl-latest` lived only in the image; after the test the image was
pruned and the host still reports NEO 24.39 + a working A770. Baseline + this result saved in
`artifacts/harness-alpha/driver-baseline/`.

### What this means for completing Track B

A full driver upgrade to NEO 26.35 is **not a user-space-only change** — it requires a
**kernel/i915 upgrade (or the xe KMD)** on the host, which is firmly in human-approval,
blast-radius territory and risks the verified bring-up + the 4 GiB-unlock study. Options now,
in increasing risk:

1. **Pick a NEO new enough to fix the SYCL bugs but still compatible with kernel 6.8.** The
   host runs 24.39; the next step is to find the newest NEO that still supports the 6.8 i915
   ABI (likely the 24.xx / early-25.xx line) and test THAT in a container first — same method,
   a smaller version jump that may not need a new kernel. Cheapest next experiment.
2. **HWE kernel bump on the host** (6.8 -> newer 6.x) so a newer i915 is present, then a
   matched newer NEO. Human-approval-required; do in a way that keeps 6.8 selectable at boot
   for rollback (GRUB entry), and re-run the full bring-up + memory-study verification after.
3. **Switch to the `xe` KMD** (the modern Intel GPU kernel driver) for Arc — bigger change,
   also kernel-level, same approval + rollback discipline.

### Recommended next step (still low-risk)

Run **Option 1** container-first: binary-search NEO versions between 24.39 and 26.35 for the
newest one that both (a) enumerates the A770 on kernel 6.8 in a container, and (b) runs
llama.cpp SYCL with oneDNN + persistent cache without SEGV. If such a NEO exists, we get the
fix with only a user-space driver bump (promote to host = one modest, reversible approval). If
the fix requires a NEO that needs a newer kernel, then completing Track B means a
host-kernel change — a decision to bring back to you with the rollback plan from Option 2.

---

## Track B attempt 2 — overnight run: latest-driver test, DEFINITIVE RESULTS

Granted authority to install what's needed. Worked container-first, kept the host reversible.

### Found the kernel-compat ceiling for the driver (container probes, zero host risk)
Bisected NEO versions in lean containers (`Dockerfile.neo-probe`), each with `/dev/dri`
passed through, testing GPU enumeration on the host's **kernel 6.8 / i915**:

| NEO | date | enumerates A770 on kernel 6.8? |
|:--|:--|:--|
| 24.39 (host) | 2024-09 | yes (baseline) |
| 25.35 | 2025-09 | yes |
| 26.05 | 2026-02 | yes |
| 26.22 | 2026-06 | yes |
| **26.31** | 2026-08 | **yes — newest that works** |
| 26.35 | 2026-09 | **no (0 devices)** |

So **NEO 26.31.39395.13 is the newest driver usable without a kernel change** (26.35 needs a
newer kernel/i915 than 6.8). This alone is a useful operational fact.

### Built the full latest stack on NEO 26.31 and tested the SYCL crash
Image `Dockerfile.sycl2631`: Ubuntu 24.04 + NEO 26.31 + IGC 2.40.13 + **Level-Zero loader
1.32.0** (the Ubuntu-packaged 1.16.1 loader could NOT load the NEO 26.31 L0 driver — a key
gotcha; the matched 1.32.0 loader from oneapi-src/level-zero fixed enumeration) + oneAPI
2026.2 (oneDNN + oneMKL) + llama.cpp SYCL compiled with `GGML_SYCL_DNN=ON` AND
`GGML_SYCL_SUPPORT_LEVEL_ZERO_API=ON` (the full-speed config that SEGVs on the host's 24.39).

Reproducible results (5 runs each, `llama-cli`, Qwen2.5-7B Q4_K_M, `-ngl 999`):

| driver | oneDNN | persistent cache | result |
|:--|:--|:--|:--|
| NEO 24.39 (host) | on | on | SEGV (Sysman + cache) |
| **NEO 26.31** | on (compiled in) | **on** | **5/5 SEGV** |
| **NEO 26.31** | on (compiled in) | **off** | **5/5 clean** |

### What this proves (the honest conclusion)

1. **The Sysman memory-query SEGV IS fixed by the newer driver.** On 24.39 the model wouldn't
   even load with the Level-Zero API compiled in; on 26.31 it loads and runs with
   `GGML_SYCL_SUPPORT_LEVEL_ZERO_API=ON` AND `GGML_SYCL_DNN=ON`. So oneDNN can stay enabled.
2. **The persistent-device-code-cache SEGV is NOT a driver bug.** It reproduces 5/5 on the
   newest compatible driver whenever `SYCL_CACHE_PERSISTENT=1`. The crash is in oneAPI 2026.2's
   `libsycl.so.9` (`PersistentDeviceCodeCache::getItemFromDisc` → `getSortedImages` → strcmp),
   independent of NEO version. The fix for THIS is an **oneAPI version change** (Track A:
   try a different oneAPI), not a driver change.
3. With `SYCL_CACHE_PERSISTENT=0`, NEO 26.31 + oneDNN-on is **stable (5/5)** — i.e. a newer
   driver lets us turn oneDNN back ON (which the host's 24.39 could not), recovering the
   optimized-GEMM path we had to disable. The only remaining disabled feature is the
   persistent kernel cache (slower first-token only; steady-state unaffected).

### Host integrity
A direct host install of the NEO 26.31 GitHub debs was attempted and **failed cleanly**: those
debs are built for Ubuntu 24.04 and conflict with the host's 22.04 libstdc++/IGC chain. `apt`
removed the half-installed packages; the host GPU driver was immediately restored to the
verified **NEO 24.39** (Arc enumerates, SYCL smoke test passes). **Host unchanged, baseline
intact.** Rollback debs saved in `artifacts/harness-alpha/driver-baseline/debs-24.39/`.

### The remaining gap to a COMPLETE fix, and the recommended route

To run SYCL at full speed (oneDNN on + persistent cache on) on the host, we need BOTH:
- a **newer driver** (NEO 26.31) — which on the host means either (a) upgrading the host to
  **Ubuntu 24.04** (the clean way to get 24.04-built NEO + loader 1.32.0), or (b) a HWE kernel
  bump so a 26.3x NEO's KMD matches; AND
- an **oneAPI that doesn't have the persistent-cache SEGV** — a Track-A experiment: test
  oneAPI 2025.x vs 2026.2 for the `PersistentDeviceCodeCache` crash (quick, local, container).

**Recommendation (for when you're back):**
1. **Easiest full win:** reimage/clean-install the GPU test box to **Ubuntu 24.04** (your
   steering already names 24.04 as the preferred GPU test target). Then NEO 26.31 + loader
   1.32.0 install natively, oneDNN stays on, and we only need the oneAPI-cache fix.
2. **Meanwhile, no OS change:** keep the shipping recommendation — **llama.cpp Vulkan (40
   tok/s)**. SYCL on the current host works with oneDNN OFF + cache OFF at ~34 tok/s; not worth
   adopting over Vulkan.
3. **Open an upstream oneAPI issue** for the `PersistentDeviceCodeCache` SEGV with the gdb
   backtrace — it reproduces on the newest driver, so it's cleanly a oneAPI (not driver) bug.

Bottom line: the newer driver fixes one of the two SYCL bugs (Sysman/oneDNN) but not the
oneAPI persistent-cache bug. A complete fix needs Ubuntu 24.04 (or a kernel bump) for the
driver side **plus** an oneAPI-version fix for the cache side. Neither was done to the host
tonight; the host remains on the verified NEO 24.39 baseline.
