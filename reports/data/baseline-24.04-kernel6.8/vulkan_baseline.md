# Vulkan baseline — Ubuntu 24.04.5, kernel 6.8.0-147, A770 (i915)

First on-hardware LLM baseline after the 22.04 → 24.04 reinstall. Captured 2026-11-04.
Purpose: a before-number on the stock 6.8 kernel so the planned 7.0 HWE kernel upgrade and
the compute-stack install can be measured against it (one variable at a time, per AGENTS.md).

## Environment

See `env.txt` in this directory for the full capture. Key facts:

- GPU: Intel Arc A770 16 GiB (DG2, `8086:56a0`), kernel driver **i915** (xe loaded, not bound).
- OS: Ubuntu 24.04.5 LTS, kernel **6.8.0-147-generic** (stock; HWE 7.0 not yet installed).
- Vulkan: Mesa ANV **25.2.8**, apiVersion 1.4.318, `DRIVER_ID_INTEL_OPEN_SOURCE_MESA`.
- Build headers: system `libvulkan-dev` **1.3.275** (the 1.4-header worry was moot — the
  Vulkan backend built and ran fine against the stock noble headers; no LunarG repo needed).
- llama.cpp: tag `b22` / repo SHA `dde879bc4f954b809892fd0d660515f42536394a`
  (fetched as a source tarball; `git clone` kept stalling on this network).
- Model: Qwen2.5-7B-Instruct Q4_K_M GGUF, sha256 `65b8fcd9…1423` (verified).
- CPU: AMD Ryzen 9 5900X (12c/24t), 125 GiB RAM.

## Provisioning facts worth carrying forward

- **Groups gate the GPU.** The fresh user was not in `render`/`video`, so Vulkan silently fell
  back to `llvmpipe` (software) and reported `llvmpipe` as GPU0. Fix: `usermod -aG render,video`.
  Confirmed afterward: `vulkaninfo --summary` lists `Intel(R) Arc(tm) A770 Graphics (DG2)`.
- **Download link is flaky + CDN URLs expire.** The HF signed URL 403'd at 99%. `aria2c -x16`
  (~0.9 MiB/s) beat single-stream curl (~0.26 MiB/s) ~3.5×; finish the last piece with a
  fresh signed URL. sha256-gate before use.
- Build target list in `setup/llamacpp_vulkan.sh` only builds `llama-server` + `llama-cli`
  (no `llama-bench`). Used `llama-cli -st` for the GPU/CPU spot check instead.
- `-no-cnv` is no longer a valid `llama-cli` flag on b22.

## Results — llama.cpp Vulkan (harness alpha task set)

| metric | result |
|:--|:--|
| coding (executed vs hidden tests) | **4/4** |
| writing constraints | **4/4** |
| median tok/s (harness, server, concurrent-ish) | **27.2** |
| GPU generation, single-stream (`llama-cli -ngl 999`) | **30.4 t/s** |
| CPU baseline, single-stream (`llama-cli -ngl 0`) | **8.1 t/s** |

GPU confirmed the project's way (Mesa ANV exposes no per-process VRAM in fdinfo): GPU/CPU =
30.4 / 8.1 = **3.75×**, and 8.1 t/s matches the documented ~8.5 t/s CPU baseline. So this is
genuinely on the A770, not a silent CPU fallback.

Raw harness JSON: `artifacts/harness-alpha/llamacpp-vulkan_20261104-181700.json` (git-ignored).

## The one real finding: throughput regressed vs 22.04

Same model, same task set, same Vulkan backend family, **correctness identical (4/4, 4/4)** —
but tok/s is **down ~32%**:

| stack | median tok/s (harness) |
|:--|:--|
| 22.04, kernel 6.8.0-138, Mesa (22.04), llama.cpp b1-dde879b | 40.2 |
| 24.04.5, kernel 6.8.0-147, Mesa 25.2.8, llama.cpp b22-dde879b | 27.2 |

Not yet root-caused. Candidate variables that changed with the reinstall (test one at a time):
1. **Mesa ANV version** (biggest suspect — Vulkan perf lives here, and the version moved).
2. **llama.cpp HEAD moved** (b1 → b22 is many commits; the Vulkan backend changed).
3. Kernel 6.8.0-138 → -147 (minor; unlikely to cost 32%).
4. GPU clocks / power state (D0 observed; no throttle checked yet — worth an `intel_gpu_top`).

This is a clean "throughput" regression in the three-claims sense; correctness is unaffected.

## ROOT CAUSE FOUND + FIXED — it was the build-time shader toolchain, not the driver

Ruled out, with evidence:
- **GPU clocks / power:** monitored `rps_act_freq_mhz` during a run — hits full **2400 MHz**,
  all `throttle_reason_*` = 0 (no thermal, no PL1). Hardware runs at full speed. Not it.
- **llama.cpp version:** the "b1" vs "b22" tag difference is only `git describe` count — BOTH
  22.04 and 24.04 built the **same SHA `dde879b`**. Identical source. Not it.

The real cause was in the **Vulkan build log**. llama.cpp probes glslc at configure time for
which SPIR-V extensions it can compile. On stock Ubuntu `glslc` (shaderc **2023.8**):

```
-- GL_KHR_cooperative_matrix supported by glslc      (coopmat ON)
-- GL_EXT_integer_dot_product NOT supported by glslc  <-- quantized-matmul accel OFF
-- GL_EXT_bfloat16 NOT supported by glslc
-- GL_NV_cooperative_matrix2 NOT supported by glslc
```

`GL_EXT_integer_dot_product` is the shader path llama.cpp's Vulkan backend uses to accelerate
**integer/quantized matmul** — the hot path for a Q4_K_M model. Stock noble's glslc (2023.8)
is too old to compile it, so the backend silently fell back to a slower path. The 22.04 host
built with LunarG **shaderc 2025.2** (recorded in `host_provisioning_22.04.txt`), which has it.

### Fix (no driver touched — a build tool only)

Add the LunarG **noble** Vulkan SDK apt repo and install its `shaderc` 2025.2 (same version
22.04 used), replacing stock `glslc`/`libshaderc-dev`/`glslang-tools` (file-conflict: remove
those stock pkgs first). Then `rm -rf build-vulkan` and rebuild. The configure log flips to:

```
-- GL_EXT_integer_dot_product supported by glslc
-- GL_EXT_bfloat16 supported by glslc
-- Enabling coopmat2 / dot / bfloat16 glslc support
```

### Result — regression resolved and slightly beaten

| stack | coding | writing | median tok/s (harness) | single-stream |
|:--|:--:|:--:|--:|--:|
| 22.04, kernel 6.8.0-138, LunarG shaderc 2025.2 | 4/4 | 4/4 | 40.2 | — |
| 24.04.5, kernel 6.8.0-147, **stock** glslc 2023.8 | 4/4 | 4/4 | **27.2** | 30.4 |
| 24.04.5, kernel 6.8.0-147, **LunarG** shaderc 2025.2 | 4/4 | 4/4 | **41.9** | 44.6 |

Same model, same llama.cpp SHA, same card, same stock Mesa 25.2.8 — the **only** change was
the glslc used to compile the Vulkan shaders. +54% over the broken build, +4% over the old
22.04 number. Correctness unchanged (4/4, 4/4). Raw result JSONs tracked alongside this
report (verbatim model output for human review, per the project convention of keeping raw
results in `reports/data/`):
- `llamacpp-vulkan_BROKEN-stock-glslc_20261104-181700.json` (27.2 tok/s)
- `llamacpp-vulkan_FIXED-lunarg-glslc_20261104-183218.json` (41.9 tok/s)

### Carry-forward for provisioning

`setup/llamacpp_vulkan.sh` needs a modern glslc. On 24.04 the stock `shaderc` (2023.8) is too
old and quietly halves Q4 throughput — add the LunarG noble repo and pin `shaderc` before the
Vulkan build. This should be scripted so the fast build is the default, not a manual fix.

## Next levers (now that the Vulkan path is at/above the old number)

Mesa itself has not been changed (still stock 25.2.8) and was NOT the culprit, so the Intel
GPU-repo Mesa test is lower priority. Remaining: 7.0 HWE kernel upgrade (the user's main
goal — unlocks newer NEO/xe driver options), then the compute stack (NEO/L0/IGC) + SYCL
re-enable of oneDNN. A coopmat2-enabled build may also help larger models/context.
