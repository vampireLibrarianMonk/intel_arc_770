# Ubuntu 24.04 migration — what to carry over and what to test

Written before the reinstall. The old host was Ubuntu 22.04, kernel 6.8.0-138 (HWE), NEO
24.39.31294, IGC 1.0.17791, GmmLib 22.5.2, L0 loader 1.17.44, oneAPI 2026.2.

## 0. Before wiping anything (data that exists only on the old box)

Tracked now: `reports/data/harness-alpha/*.json` (raw per-candidate results incl. verbatim
model output), `reports/data/driver-baseline/` (old package list, clinfo/sycl-ls, extra apt
sources + packages in `host_provisioning_22.04.txt`).

NOT in git (gitignored, large, re-creatable): GGUF model (4.4 GiB, sha256
`65b8fcd92af6b4fefa935c625d1ac27ea29dcb6ee14589c55a8f115ceaaa1423`, bartowski
Qwen2.5-7B-Instruct-Q4_K_M), HF caches (Qwen2.5 1.5B x2; the 7B fp16 was deleted to free
disk), the llama.cpp builds, rollback debs for NEO 24.39, gdb backtraces in
`artifacts/harness-alpha/logs/`. Back up the GGUF if the mirror is slow (it took ~2.5 h).

## 1. Facts to use, not re-derive

- Kernel gates the driver. On the 6.8 kernel, NEO 26.31.39395.13 enumerates the A770 and
  26.35 does not (0 devices). Ubuntu 24.04's original GA kernel is 6.8, but per Ubuntu
  release coverage (not verified on this box) 24.04.4+ media ship the 6.17 HWE kernel and
  24.04.5 (Sept 2026) moves to 7.0. So a current 24.04.x image probably does move off 6.8;
  confirm with `uname -r` after install. Whether NEO 26.35 enumerates on 6.17/7.0 is
  untested. (An earlier draft of this file said plain 24.04 stays on 6.8; that was wrong for
  current install media.)
- NEO 26.31 needs Level-Zero loader 1.32.0 (Ubuntu's libze1 1.16.1 cannot load it) and
  IGC 2.40.13. NEO 26.35 pairs with IGC 2.41.5. The `.deb`s are built for 24.04.
- Two separate SYCL bugs: (1) Level-Zero Sysman memory query SEGV in NEO 24.39 — fixed by NEO
  26.31; (2) `PersistentDeviceCodeCache` SEGV in oneAPI 2026.2 libsycl — reproduced 5/5 on
  NEO 26.31 in a 24.04 userspace container, so it is not the distro userspace or the driver.
- Current shipping pick: llama.cpp Vulkan, 40.2 tok/s, 4/4 coding, 4/4 writing.

## 2. Tests, in priority order (all need the A770; none run so far)

1. Re-verify the baseline on 24.04 (human-approval items are install-time, not here):
   `.venv-xpu` torch 2.6.0+xpu `xpu_available`, the b5 matmul baseline, and the MEM-* 4 GiB
   boundary tests. Record kernel/NEO/IGC/GmmLib versions per AGENTS.md.
2. Native NEO 26.31 + loader 1.32.0: `sycl-ls` shows level_zero, then SYCL llama.cpp with
   `GGML_SYCL_DNN=ON`, `GGML_SYCL_SUPPORT_LEVEL_ZERO_API=ON`, `SYCL_CACHE_PERSISTENT=0`.
   Expect clean; record tok/s (host SYCL with oneDNN off was 33.9).
3. The remaining SYCL blocker: oneAPI version matrix for the persistent-cache SEGV. Run 5x
   each: oneAPI 2026.2 vs 2025.x (apt pins), `SYCL_CACHE_PERSISTENT` 0/1. This is the only
   test that can remove the last workaround. If no version works, file the upstream issue
   with the gdb backtrace (frames: `__strcmp_avx2` <- `getSortedImages` <-
   `PersistentDeviceCodeCache::getItemFromDisc` in `libsycl.so.9`).
4. Full harness re-run on 24.04 (`run_all.sh`) for all four candidates, same GGUF. Mesa is
   newer on 24.04, so Vulkan numbers may move; compare against the 22.04 table, not memory.
5. Kernel lever: install the 24.04 HWE kernel (keep the 6.8 entry selectable in GRUB), then
   retry NEO 26.35 enumeration with the lean probe (`container/Dockerfile.neo-probe`).
   Human-approval-required; re-run test 1 afterwards.
6. Decision gate: SYCL is adopted only if correct (4/4, 4/4) AND faster than Vulkan's 40.2.

## 3. Never tested (still open, optional)

Larger models / context-length sweep (the "spiral" idea: 14B, 8K-32K context), Ollama, vLLM
XPU, IPEX-LLM on the new stack (7B fp16 weights must be re-fetched), the `xe` kernel driver,
Flash Attention behavior on SYCL, and `-ngl` partial offload curves.

## 4. Provisioning gotchas to script for 24.04

- Vulkan build needs `libvulkan-dev` >= 1.4 headers, `glslc` (package `shaderc`), and
  `spirv-headers`. On 22.04 these came from the LunarG apt repo; check what noble ships
  before adding that repo.
- SYCL build needs oneAPI DPC++ + oneDNN + oneMKL; `setvars.sh` breaks under `set -u`, so
  source it with `set +u` (done in the scripts).
- LM Studio headless needs one first run of the Electron app under `xvfb-run` to register
  the install; then `lms` works. `lms import --copy` or it moves the shared GGUF.
- Downloads: this network drops long transfers. Use `fetch_all.sh` (sequential, resumable,
  sha256-gated). Never run two writers on one `.part` file (it corrupted a download once).
- Passwordless sudo and the git SSH key passphrase were set up by hand; pushes need an
  interactive `ssh-add`.
