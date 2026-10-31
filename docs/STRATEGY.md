# Intel Arc A770 16 GB — Agentic Driver Diagnostics & Optimization Lab

**Status:** Project strategy / Kiro ingestion brief
**Prepared:** 2026-10-27
**Target GPU:** Intel Arc A770, 16 GiB VRAM (Alchemist / Xe-HPG, PCI ID commonly `8086:56a0`)
**Target OS:** Ubuntu Linux, preferably an isolated Ubuntu 24.04+ test installation
**Primary engineering domains:** OpenCL, oneAPI Level Zero, Intel Compute Runtime (NEO), Intel Graphics Compiler (IGC), GPU memory management
**Project shorthand:** `arc-a770-lab`

> **Project charter:** Build a reproducible, agent-assisted laboratory to diagnose Intel Arc A770 compute-driver limitations; identify differences among hardware limits, API defaults, application behavior, compiler code generation, and fixable runtime defects; design, implement, benchmark, and validate narrowly scoped changes. Focus first on the historical 4 GiB **per-allocation** behavior, not on a supposed 4 GiB total-VRAM limit.

## 1. Executive decision

Start with **Intel Compute Runtime + a standalone C++ OpenCL/Level Zero diagnostic harness**, before modifying the compiler. Use the **stock installed driver** as a control. Introduce **Intel Graphics Compiler** source modifications only after evidence implicates generated machine code or compiler optimization. Do **not** begin by replacing the kernel or making Mesa changes: those target different portions of the graphics stack and are not the first place to look for the specific OpenCL allocation issue.

### What is already understood

- The Arc A770 has 16 GiB of VRAM, but Intel's **stateful addressing** model can limit a **single allocation** to around 4 GiB. Multiple smaller allocations may use more total VRAM, subject to availability and other limits.
- Intel documents a supported path for allocations greater than 4 GiB, provided **both** an allocation override and appropriate **stateless kernel compilation** are applied.
- In OpenCL, use `CL_MEM_ALLOW_UNRESTRICTED_SIZE_INTEL` for the allocation **and** `-cl-intel-greater-than-4GB-buffer-required` when building the relevant kernels.
- In Level Zero, use `ze_relaxed_allocation_limits_exp_desc_t` with `ZE_RELAXED_ALLOCATION_LIMITS_EXP_FLAG_MAX_SIZE` **and** `-ze-opt-greater-than-4GB-buffer-required` during module creation.
- These are not interchangeable with simply ignoring the maximum buffer size. Failing to compile kernels in the appropriate addressing model can silently produce **wrong calculations**, even when allocation creation succeeds.
- Intel engineers explained in May 2025 that older Alchemist hardware retains the smaller stateful default due to workload-specific overhead from stateless 64-bit messages, including register pressure, possible spills, and more complex address calculations. **Do not assume this hardware penalty can be removed by a driver patch.**

**Starting hypothesis:** Meaningful improvement is most likely in **selection of memory strategies, compiler-generated addressing, workload-specific buffer layout, diagnostic transparency, and error handling**. Removing a hardware addressing-mode limitation through software alone is not an achievable objective.

**Original investigation:** <https://github.com/intel/compute-runtime/issues/627>
**Authoritative Intel programming guide:** <https://github.com/intel/compute-runtime/blob/master/programmers-guide/ALLOCATIONS_GREATER_THAN_4GB.md>

---

## 2. Scope and non-goals

### In scope

1. Reproduce and document allocation-size behavior on an actual A770 16 GiB card.
2. Verify **correct data reads/writes above the 4 GiB offset**, not merely successful allocation.
3. Separate hardware, firmware, kernel (`i915`), compute-runtime, IGC, and application failures.
4. Benchmark stateful/split-buffer and stateless/large-buffer approaches where both are valid.
5. Improve benchmark reproducibility, failure reporting, and any demonstrable runtime/compiler defects.
6. Prototype **application-level** buffer chunking or compiler-assisted transformations for specific kernels; test semantic correctness.
7. Prepare upstream-quality issue reports and small pull requests with regression tests.
8. Optionally extend to Level Zero, SYCL, and PyTorch/XPU workloads after the OpenCL suite is stable.

### Out of scope for v1

- Modifying GPU microcode/firmware or bypassing hardware safety mechanisms.
- Reverse-engineering Intel's proprietary Windows driver.
- Assuming that one 16 GiB allocation should always be possible just because the card has 16 GiB VRAM.
- Pretending arbitrary >4 GiB allocations can be split transparently: **pointer semantics, indexing, kernel arguments, memory visibility, and synchronization can prevent this.**
- Using Kiro to install new system-wide drivers, reconfigure bootloader/kernel, flash firmware, or unload production GPU modules without explicit human approval.
- Claiming that a successful build or allocation equals a fixed defect.

---

## 3. Repository map: what to clone, when, and why

| Priority | Repository | Role | Clone timing | Notes |
|:--|:--|:--|:--|:--|
| **P0** | [`intel/compute-runtime`](https://github.com/intel/compute-runtime) | NEO implementation: OpenCL + Level Zero, allocation limits and driver policy | **Immediately** | Primary runtime codebase; pin tagged releases and dependency manifest |
| **P0** | [`intel/compute-benchmarks`](https://github.com/intel/compute-benchmarks) | Intel-maintained compute-driver microbenchmarks | **Immediately** | Use alongside custom address-boundary correctness harness |
| **P0** | [`intel/opencl-intercept-layer`](https://github.com/intel/opencl-intercept-layer) | Intercepts OpenCL calls, diagnostics; `RelaxAllocationLimits` control | **Immediately** | Useful comparison mechanism, not proof of automatic general correctness |
| **P1** | [`intel/intel-graphics-compiler`](https://github.com/intel/intel-graphics-compiler) | LLVM-based GPU kernel compilation; stateful/stateless code generation | **Read immediately, build after baseline** | Large, expensive toolchain; respect version matrix |
| **P1** | [`intel/gmmlib`](https://github.com/intel/gmmlib) | Graphics memory management support library used by NEO | **When assembling source builds** | Version must match NEO's manifest |
| **P1** | [`oneapi-src/level-zero`](https://github.com/oneapi-src/level-zero) | API headers, loader and tracing/validation layers | **When adding Level Zero harness** | Link applications to loader, not directly to NEO internals |
| **P1** | [`oneapi-src/level-zero-tests`](https://github.com/oneapi-src/level-zero-tests) | Conformance, stress and performance regression tests | **Level Zero phase** | Adds independent coverage |
| **P2** | [`intel/opencl-clang`](https://github.com/intel/opencl-clang) | IGC's OpenCL front-end dependency | **Compiler phase** | Pin the branch corresponding to selected LLVM/IGC release |
| **P2** | [`KhronosGroup/SPIRV-LLVM-Translator`](https://github.com/KhronosGroup/SPIRV-LLVM-Translator) | SPIR-V ↔ LLVM translation | **Compiler phase** | Compiler dependency; use IGC's prescribed revision |
| **P2** | [`llvm/llvm-project`](https://github.com/llvm/llvm-project) | LLVM and Clang dependency | **Compiler phase** | Avoid assuming arbitrary latest LLVM is compatible |
| **P2** | [`intel/vc-intrinsics`](https://github.com/intel/vc-intrinsics) | Vector compiler intrinsics | **Compiler phase** | IGC dependency |
| **P3** | [`mesa/mesa`](https://gitlab.freedesktop.org/mesa/mesa) | Vulkan/OpenGL user-space driver | **Only if graphics issue appears** | Not the first repository for NEO large-buffer limitation |
| **P3** | [`torvalds/linux`](https://github.com/torvalds/linux) | `drivers/gpu/drm/i915` and `xe` kernel components | **Only after kernel-level evidence** | Separate high-risk workstream, no unattended module updates |

**Historical reference only:** [`intel/compute-samples`](https://github.com/intel/compute-samples) contains example OpenCL/Level Zero code but has been marked archived/unsupported; do not rely on it as a maintained test suite.

### Essential documentation

- Intel NEO [large-allocation guide](https://github.com/intel/compute-runtime/blob/master/programmers-guide/ALLOCATIONS_GREATER_THAN_4GB.md)
- Intel NEO [build instructions](https://github.com/intel/compute-runtime/blob/master/documentation/BUILD.md) and [local build documentation](https://github.com/intel/compute-runtime/blob/master/documentation/BUILD_LOCAL.md)
- Intel NEO [release dependency manifest](https://github.com/intel/compute-runtime/blob/master/manifests/manifest.yml)
- Intel IGC [Ubuntu build instructions](https://github.com/intel/intel-graphics-compiler/blob/master/documentation/build_ubuntu.md)
- Intel OpenCL Intercept Layer [controls](https://github.com/intel/opencl-intercept-layer/blob/main/docs/controls.md)
- Intel [supported i915 hardware table](https://dgpu-docs.intel.com/overview/supported-hardware/i915-driver-gpus.html)
- Kiro [Steering](https://kiro.dev/docs/steering/), [Specs](https://kiro.dev/docs/specs/), [Hooks](https://kiro.dev/docs/hooks/), [Custom Agents](https://kiro.dev/docs/custom-agents/)

**Version policy:** Pin all source checkouts to specific release tags and SHAs. NEO's `manifests/manifest.yml` is the source of truth for matching **IGC and GmmLib** versions. Never mix random `master` HEADs for baseline and modified comparisons.

---

## 4. Environment architecture

### Recommended hardware approach

Use a **disposable or recoverable test OS** with the physical A770 visible to Linux. Bare metal is the first choice for reproducibility and simplicity. A dedicated KVM guest with **full PCIe passthrough** can be considered, but only if IOMMU grouping, reset behavior, ReBAR, and device binding are proven reliable; avoid confusing VM/host issues with driver bugs.

The existing Ubuntu 22.04 + KVM home-lab platform can be the initial **build host**, but a dedicated Ubuntu 24.04+ GPU test installation is preferable. Kiro's current IDE requires Ubuntu 24.04+; its CLI has different Linux requirements and can be used on Ubuntu 22.04 with a compatible glibc. The installed Intel IGC itself documents support for 22.04, 24.04 and 26.04.

| Layer | Baseline | Experimental |
|:--|:--|:--|
| Host OS | Stock, updated Ubuntu + kernel | Same OS/kernel, changed user-space stack only |
| Device | A770 selected by PCI ID + device name | Same card, clocks and thermal conditions |
| Firmware / BIOS | Record version, ReBAR state, PCIe negotiation | Keep unchanged in a given experiment |
| Kernel | `i915` for the baseline; record exact version | Do not replace initially |
| Compute driver | Known Intel NEO package and SHA/version | Isolated runtime build with one patch at a time |
| Compiler | Compatible released IGC | Matched baseline build versus one compiler patch |
| Tests | Custom OpenCL/Level Zero correctness + Intel benchmarks | Identical test workloads and seeds |
| Report | JSON raw results + Markdown summary | Baseline versus candidate and confidence intervals |

**Isolation requirement:** Keep experimental libraries in a per-test prefix or disposable VM/container using properly passed through `/dev/dri` devices. Merely compiling a runtime does not guarantee applications will load it. Record the loaded OpenCL ICD / Level Zero loader, vendor library paths and compiler versions; prove which driver a test actually used. A container does **not** replace kernel isolation.

### Read-only discovery commands

```bash
set -euo pipefail
uname -a
cat /etc/os-release
lspci -nnk | grep -A5 -Ei 'VGA|3D|Display'
ls -la /dev/dri /dev/dri/by-path 2>/dev/null || true
lsmod | grep -E '^(i915|xe)\b' || true
command -v clinfo >/dev/null && clinfo | grep -Ei 'Device Name|Global memory size|Max memory allocation' || true
command -v ze_info >/dev/null && ze_info || true
journalctl -k -b --no-pager | grep -Ei 'i915|xe|drm|guc|gpu|hang|reset' | tail -150 || true
```

Always record full unfiltered diagnostics in an artifact file as well; abbreviated `grep` is for quick inspection only. GPU selection must be explicit if another Intel integrated GPU or other accelerators are present.

---

## 5. Baseline experiment design

### Four independent hypotheses

- **H0: Driver default.** `CL_DEVICE_MAX_MEM_ALLOC_SIZE` reports about 4 GiB; a larger regular OpenCL allocation fails, even when total VRAM is much higher.
- **H1: Correct supported workaround.** Allocation-override flag **plus** stateless compiler flag allows >4 GiB access with correct values on offsets above the 4 GiB boundary.
- **H2: Performance trade-off.** Stateless addressing has a measurable, workload-dependent performance impact on A770; some kernels benefit from the existing stateful path.
- **H3: Improvement opportunity.** An adaptive application/kernel selection policy or narrowly scoped compiler/runtime patch improves measured behavior *without changing expected results*.

### Correctness test matrix

Use exact binary units (`GiB = 2^30 bytes`) and log the driver's reported maximum. Never assume an allocation at the exact reported maximum is available; reserve headroom and distinguish resource exhaustion from policy limits.

| Test ID | Logical size / scenario | Default OpenCL | Supported large-buffer path | Must verify |
|:--|:--|:--|:--|:--|
| `MEM-01` | 256 MiB | Run | Run | Standard read/write and checksum |
| `MEM-02` | 2 GiB | Run | Run | Checksum, throughput, repeatability |
| `MEM-03` | Reported max minus alignment unit | Run | Run | Correct near-limit behavior |
| `MEM-04` | Reported max plus alignment unit | Expect policy rejection if still limited | Run if VRAM permits | Exact error code vs pass |
| `MEM-05` | 6 GiB | Expect policy rejection if still limited | Run | Write/read values well beyond 4 GiB offset |
| `MEM-06` | 8 GiB | Expect policy rejection if still limited | Run | Strided/random reads and writes |
| `MEM-07` | 12 GiB | Not necessarily supported | Conditional | Capacity, fragmentation and headroom |
| `MEM-08` | Three separate 3 GiB buffers | Run if capacity permits | Run | More than 4 GiB **aggregate** VRAM usable |
| `MEM-09` | 6 GiB with allocation override **only** | Controlled negative test | **Never treat as supported** | Detect rejection or silent corruption, safely |
| `MEM-10` | 6 GiB with stateless compile flag **only** | Controlled negative test | Incomplete mechanism | Capture behavior; do not infer safety |

**Sentinel correctness rule:** A minimal kernel must write/read *distinct* locations on both sides of the 4 GiB boundary (e.g. offsets around `2^32-1`, `2^32`, and `2^32+4096`, within valid bounds). Include independent host-side reference values, fixed PRNG seeds, 64-bit indexes where appropriate, and checksums. **Allocation success alone is not evidence of correctness.** Avoid sampling only the first 4 GiB.

For large allocations, avoid repeatedly copying a full 12 GiB buffer to the CPU; use sparse sentinel checks and device-side digest generation, then run full checks selectively. Ensure digest code itself cannot wrap addresses or mask corruption.

### Performance workload classes

1. **Address-generation-heavy microkernel** — frequent indexed loads/stores, short computation.
2. **Bandwidth-bound streaming kernel** — sequential data traversal at 2/6/8 GiB.
3. **Random-access kernel** — scattered accesses, offset range beyond 4 GiB.
4. **Compute-heavy kernel** — less sensitive to address calculation.
5. **Segmented-buffer implementation** — only for kernels designed to handle segmentation.
6. **Real application workload** — e.g. a fluid simulation or AI tensor operation once the minimal harness is stable.

Capture host-to-device and device-to-host bandwidth separately from kernel time. Record compile time, execution time, buffer creation latency, correctness, driver messages, GPU hang/reset counters, total VRAM pressure, memory clock/temperature if available.

**Measurement protocol:** warm up; run at least 10 measured repetitions per case (prefer 20 where practical); randomize or alternate A/B execution order; report median, p95, dispersion, and raw samples; pin workload dimensions, thermal conditions, compiler flags, commits, OS/kernel and firmware. Never present a single lucky run as a speedup.

---

## 6. Agent-driven defect investigation loop

```text
Hardware/driver discovery
        ↓
Choose ONE hypothesis and acceptance test
        ↓
Reproduce on unchanged baseline → archive raw evidence
        ↓
Classify layer: app / OpenCL API / Level Zero / NEO / IGC / kernel / hardware
        ↓
Search issue trackers + relevant source and tests
        ↓
Propose smallest falsifiable intervention; human review
        ↓
Apply isolated patch; compile pinned dependencies
        ↓
Run correctness tests, then performance measurements
        ↓
Compare against identical baseline; check regressions
        ↓
Keep patch and document OR revert and revise hypothesis
```

### Diagnostic classification rules

| Symptom | First suspect | Next evidence |
|:--|:--|:--|
| `CL_INVALID_BUFFER_SIZE (-61)` at >4 GiB | OpenCL max-allocation policy | Query max, flag use, NEO guide |
| Large allocation succeeds, output corrupt | Compiler/addressing mismatch | Kernel build flags, offsets above 4 GiB, fixed sentinels |
| Correct results, much slower with stateless | Architecture / compiler code generation | Address calc, register occupancy/spills, profiling |
| GPU hangs or resets | Kernel / firmware / hardware / synchronization | Kernel logs, reset/error counters, independent workload |
| Only PyTorch/SYCL fails | Framework/integration-specific | Minimal OpenCL/Level Zero repro, backend versions |
| Error only in passthrough VM | PCIe/IOMMU/reBAR/reset or guest configuration | Bare-metal reproduction and PCIe state |
| Large allocation fails under VRAM pressure | OOM / fragmentation / overcommit policy | Available memory and allocations, not 4 GiB policy |

A Kiro agent must distinguish **'allocation capability improved,' 'application can handle the workload,' and 'GPU throughput improved'** as three different claims.

---

## 7. Workstreams and stage gates

### Phase 0 — Evidence capture and toolchain freeze

**Deliverables:** `artifacts/baseline/environment.json`, baseline log, GPU inventory, reproducible setup notes, pinned release list.

- Identify exact A770 card, PCI ID, driver, kernel, firmware, ReBAR status, memory size and max allocation.
- Confirm GPU selection and `/dev/dri/renderD*` permission.
- Verify stable stock OpenCL (and optionally Level Zero) access before any builds.
- Record correct NEO → IGC → GmmLib dependency versions from `manifests/manifest.yml`.

**Gate:** Stock driver passes a 256 MiB read/write test and environment is fully documented.

### Phase 1 — Reproduce 4 GiB behavior accurately

**Deliverables:** `tests/opencl/large_buffer.cpp`, test specification, CPU oracle, JUnit/JSON outputs.

- Implement OpenCL API discovery; regular versus relaxed allocation modes.
- Compile kernels with and without stateless build flag in separate cases.
- Validate data at offsets crossing 4 GiB, near max bounds, and multiple small buffers.
- Produce a table that distinguishes supported behavior, expected errors and defects.

**Gate:** Demonstrate either the documented behavior or a new, reproducible discrepancy; no silent corruption in supported configurations.

### Phase 2 — Establish performance cost

**Deliverables:** reproducible benchmark runner, Intel Compute Benchmarks integration, plots/reports, raw samples.

- Compare equivalent stateful/small-buffer, stateless/large-buffer and application-segmented implementations.
- Keep data layout and computations equivalent where feasible; flag cases with non-equivalent algorithms.
- Identify performance bottlenecks with profiling before editing the compiler.

**Gate:** At least one statistically credible bottleneck with an actionable hypothesis, or a documented negative result.

### Phase 3 — Runtime-level changes (lowest-risk first)

**Candidate experiments (not promised fixes):**

- Better diagnostics when allocation flags and kernel build flags are inconsistent.
- Capabilities query / adaptive selection helper that selects supported strategies per workload.
- Improved user-facing errors and documentation for policy versus resource exhaustion.
- Smaller internal allocation-policy patch *only* if a real bug is demonstrated by a regression test.

**Gate:** Patch passes all correctness tests, no new error paths, neutral-to-better measured behavior on tested workloads.

### Phase 4 — Intel Graphics Compiler experiments

**Enter only if Phase 2 implicates compiler behavior.**

- Inspect address calculations, memory-message choice, register usage and spills.
- Prototype targeted optimizations or transformations, not a blanket 64-bit switch.
- Include compiler tests and workloads that expose any perf regressions.
- Match LLVM / SPIR-V translator / OpenCL Clang versions to the IGC build guide.

**Gate:** Demonstrated correct code generation and reproducible improvement on at least one real workload without material regressions across the defined test suite.

### Phase 5 — Level Zero + application transfer

- Reproduce relaxed-allocation and module-build behavior through Level Zero APIs.
- Add `oneapi-src/level-zero-tests` for conformance/stress checks.
- Evaluate application-level impact on a chosen SYCL, PyTorch/XPU, or compute workload.
- Publish upstream report/PR with baseline, reproduction, patch and measurement evidence.

**Gate:** Fix shown outside a synthetic benchmark; no unsupported claim of universal performance gain.

---

## 8. Definition of success and stop conditions

### Minimum viable project (MVP)

- [ ] A reproducible Ubuntu hardware environment identifies the A770 correctly.
- [ ] A deterministic 4 GiB boundary test demonstrates the driver's actual behavior.
- [ ] The documented >4 GiB OpenCL workaround passes **independent correctness validation**.
- [ ] Stock driver and experimental driver measurements are stored with source SHA and environment metadata.
- [ ] Kiro produces a structured root-cause report for each investigated anomaly.
- [ ] Builds and experiments run without replacing system drivers or touching firmware.

### Scientific success (any one of these is valuable)

1. Confirm the previously reported limitation and quantify its real-world cost on current software.
2. Find and fix a **reproducible bug** in the driver/compiler, with an upstream-ready regression test.
3. Produce a measurable, repeatable **application-level optimization** for large-buffer use.
4. Show a credible speedup for a narrow class of kernels by improving addressing or code generation.
5. Deliver a public benchmark harness useful to Intel GPU developers even if no driver patch is warranted.

### Strict stop / manual review triggers

- GPU reset, repeated hang, thermals exceeding safe operating conditions, ECC/data corruption signals, unexplained kernel panic or host instability.
- Proposed root-level installation, `modprobe`/driver unbinding, GRUB edits, changing `i915`/`xe` parameters, BIOS/ReBAR changes, or firmware update.
- Any proposal to hardcode reported allocation capacity while ignoring kernel addressing semantics.
- Any attempt to claim success without correctness checks, or to use estimated performance numbers as measurements.

---

## 9. Kiro project structure

```text
arc-a770-lab/
├── README.md                         # Entry point; link to this strategy
├── AGENTS.md                         # Always-on guardrails for all agents
├── .kiro/
│   ├── steering/
│   │   ├── product.md                 # Goal, non-goals, exit criteria
│   │   ├── tech.md                    # Versions, language, host constraints
│   │   └── structure.md               # Folder layout, naming, quality gates
│   ├── specs/
│   │   ├── baseline-inventory/
│   │   ├── opencl-large-buffer-harness/
│   │   ├── addressing-performance-study/
│   │   └── runtime-patch-candidate/
│   └── skills/                        # Later: experiment-runner skill
├── docs/
│   ├── STRATEGY.md                    # This document
│   ├── REPOSITORIES.md                # Repo map + pinned SHA table
│   ├── EXPERIMENT_TEMPLATE.md         # Hypothesis, controls, results
│   └── ADR/                           # Architecture decision records
├── tests/
│   ├── opencl/                        # C++ API tests and kernels
│   ├── level-zero/                    # Follow-on tests
│   └── oracles/                       # Independent CPU references
├── benchmarks/
│   ├── workloads/                     # Fixed workloads
│   └── manifests/                     # Reproducible parameter sets
├── scripts/
│   ├── capture_baseline.sh            # Read-only inventory
│   ├── setup_sources.sh               # Opt-in clones, pins revisions
│   └── run_matrix.py                  # Planned: test orchestration
├── src/                               # Harness and optional policy experiments
├── patches/                           # Small diffs, never modify vendor by default
├── vendor/                             # Git ignored upstream clones
├── artifacts/                          # Git ignored bulky logs and outputs
└── reports/                            # Reviewed results and plots
```

### Kiro integration choices

- Put durable project policy in `AGENTS.md` and small `.kiro/steering/*.md` files; Kiro supports both.
- Use Kiro **Specs** to decompose each phase into requirements, design and testable tasks rather than one huge unconstrained prompt.
- Use **Hooks** later to run formatting/unit tests when harness source changes and to require a completed experiment record before approving a patch. Do not automate privileged installation.
- A custom *investigator agent* can propose root causes and read logs. A separate *implementer* can create patches. A *validator* should challenge both and re-run tests from clean builds. Initially these can be workflows or prompts, not necessarily independent paid agents.
- If creating a custom agent, explicitly load steering resources using its documented `resources` mechanism; do not assume project steering is always inherited automatically by custom agents.

### `AGENTS.md` baseline policy (copy into project root)

```markdown
# Intel Arc A770 Lab — Agent Rules

- Objective: reproducible OpenCL/Level Zero diagnostics and narrowly scoped improvements for Arc A770 16 GiB.
- Prefer a minimal falsifiable test over broad speculative refactoring.
- Every reported finding includes: GPU PCI ID, OS/kernel, NEO/IGC/GmmLib release and SHA, exact flags, reproduction command, evidence, and uncertainty.
- Do not confuse a ~4 GiB per-buffer limit with total VRAM capacity.
- For >4 GiB OpenCL access, verify BOTH relaxed allocation and stateless kernel compilation.
- A created allocation is never sufficient proof: verify values above the 4 GiB offset.
- Use pinned dependency versions. Use local prefixes; do not overwrite stock drivers.
- Treat shell commands that modify firmware, kernel modules, BIOS, boot configuration, driver packages, or system library paths as human-approval-required.
- Do not silently change GPU power or clocks. Stop on repeated hangs, faults, or data corruption.
- Prioritize correctness, then repeatability, then performance. Revert unsuccessful patches.
- Never invent measurements. Keep raw results and describe limitations.
- Keep driver source and test harness separate; submit small, reviewable changes upstream.
```

---

## 10. First session prompt for Kiro

> **Paste this entire strategy document into the project, then start with this prompt:**

```text
We are starting arc-a770-lab. Read docs/STRATEGY.md and AGENTS.md first.

Do NOT edit the kernel, install system-wide drivers, alter the bootloader, or flash firmware.
Do NOT begin by optimizing driver source. Start with evidence.

Create Kiro Specs for (1) baseline inventory and (2) an OpenCL >4-GiB
correctness harness for an Intel Arc A770 16-GiB GPU.

First: inspect the local system using read-only commands and report exact hardware,
PCI ID, kernel driver, firmware/driver versions, device permissions, OpenCL runtime,
reported global memory and max single allocation.

Second: design a C++17 CMake test harness with explicit A770 device selection,
small allocation tests, boundary tests, multi-buffer tests, supported relaxed
allocation plus stateless compile flag, negative controls, a CPU correctness oracle,
and sentinels that cross the 4-GiB byte offset.

Third: propose a machine-readable experiment schema including git SHAs, compiler
flags, workload parameters, error codes, data-integrity checks, timings, and logs.

Present the requirements, design, proposed tasks and safety review before executing
any privileged change. No compiler or NEO modifications until we have a complete
stock-driver baseline and a reproducible discrepancy or performance hypothesis.
```

---

## 11. Safe starter commands for the owner

The following **create a workspace and clone source**; they do not install or replace GPU drivers:

```bash
mkdir -p ~/src/arc-a770-lab/{docs,tests/opencl,tests/level-zero,benchmarks,scripts,patches,artifacts,reports,vendor}
cd ~/src/arc-a770-lab

git clone https://github.com/intel/compute-runtime.git vendor/compute-runtime
git clone https://github.com/intel/compute-benchmarks.git vendor/compute-benchmarks
git clone https://github.com/intel/opencl-intercept-layer.git vendor/opencl-intercept-layer

# Do not clone/build the IGC + LLVM dependency tree yet.
# First pin a NEO release and inspect its dependency manifest.
cat vendor/compute-runtime/manifests/manifest.yml | head -100
```

The source clone on `master` is useful for documentation inspection; **pin a release before comparing performance or compiling a modified NEO**. Use tagged baselines and record exact SHA. The official build guide additionally describes local-prefix installation and compatibility checking.

For stock driver diagnostics on Ubuntu, use package-managed utilities as appropriate (e.g., `clinfo`, `intel-gpu-tools`) and check access to `/dev/dri/renderD*`. The actual software loadout must be discovered, not assumed.

---

## 12. Experiment record template

Every investigated finding is one Markdown record plus a machine-readable JSON file:

```yaml
experiment_id: ARC-MEM-0001
question: "Does supported OpenCL allocation >4 GiB preserve values beyond 2^32 bytes?"
hypothesis: "With both flags and sufficient memory, out-of-boundary sentinels match the CPU oracle."
hardware: {gpu: "Arc A770 16 GiB", pci_id: "TO_RECORD", rebar: "TO_RECORD"}
software: {ubuntu: "TO_RECORD", kernel: "TO_RECORD", neo: "TO_RECORD", igc: "TO_RECORD", gmmlib: "TO_RECORD"}
source: {runtime_sha: "TO_RECORD", compiler_sha: "TO_RECORD", harness_sha: "TO_RECORD"}
control: "stock driver; regular allocation; matching kernel"
candidate: "stock driver; relaxed allocation + stateless kernel build flag"
input: {buffer_size_bytes: "TO_RECORD", offsets_bytes: "TO_RECORD", seed: 123456}
validation: ["allocation status", "sentinels around 2^32", "device digest", "CPU reference"]
metrics: ["kernel_time_ms", "allocation_time_ms", "throughput_gbps", "gpu_reset_count"]
result: "PENDING — do not prefill success"
artifacts: ["raw API results", "driver logs", "test output", "CSV or JSON samples"]
```

**Patch acceptance:** Every patch must link to an experiment, pass the original reproducer, pass regression tests, produce identical validated outputs, and include pre/post measurements with software versions and raw samples. A speedup with incorrect results is a failed patch.

---

## 13. Prioritized research backlog

| ID | Topic | Expected deliverable | Priority |
|:--|:--|:--|:--|
| ARC-001 | A770 environment and capability snapshot | Reproducible inventory JSON | P0 |
| ARC-002 | OpenCL allocation boundary reproducer | Executable + gold-standard expected results | P0 |
| ARC-003 | Large-buffer data integrity test crossing `2^32` | CPU-verified checksum report | P0 |
| ARC-004 | Multi-buffer >4 GiB total usage | Aggregate-capacity report | P0 |
| ARC-005 | Correct stateless vs stateful microbenchmarks | A/B raw results and summary | P0 |
| ARC-006 | OpenCL Intercept Layer evaluation | Controlled comparison and caveats | P1 |
| ARC-007 | NEO local-prefix pinned build | Build metadata, smoke tests | P1 |
| ARC-008 | Allocation-policy and diagnostics source audit | Call graph and issue candidates | P1 |
| ARC-009 | IGC generated-code analysis | Spill/addressing profile | P2 |
| ARC-010 | Segmentation proof of concept for one workload | Correct application-level alternative | P2 |
| ARC-011 | Level Zero large-buffer equivalence suite | L0 test report | P2 |
| ARC-012 | SYCL/PyTorch/XPU applied benchmark | Workload-specific benefit/risk | P3 |
| ARC-013 | Upstream-quality patch or issue report | Small PR/issue with reproducible evidence | P3 |

## 14. References and verification notes

**Checked against public upstream documentation as of 2026-10-27.** GitHub branches, build prerequisites, package availability and Kiro interfaces can change; resolve exact dependency pins during Phase 0.

1. Intel Compute Runtime issue #627, historical discussion and 2025 architectural clarification: <https://github.com/intel/compute-runtime/issues/627>
2. Intel large allocation guide, both API mechanisms and compiler flags: <https://github.com/intel/compute-runtime/blob/master/programmers-guide/ALLOCATIONS_GREATER_THAN_4GB.md>
3. Intel NEO README and supported devices: <https://github.com/intel/compute-runtime>
4. Intel NEO source build and release manifest rules: <https://github.com/intel/compute-runtime/blob/master/documentation/BUILD.md>
5. Intel IGC and Ubuntu build/version requirements: <https://github.com/intel/intel-graphics-compiler/blob/master/documentation/build_ubuntu.md>
6. Intel Compute Benchmarks: <https://github.com/intel/compute-benchmarks>
7. Intel OpenCL Intercept Layer controls: <https://github.com/intel/opencl-intercept-layer/blob/main/docs/controls.md>
8. oneAPI Level Zero tests: <https://github.com/oneapi-src/level-zero-tests>
9. Kiro system requirements: <https://kiro.dev/docs/getting-started/installation/>
10. Kiro project steering and AGENTS.md: <https://kiro.dev/docs/steering/>
11. Intel Arc A770 Linux i915 support reference: <https://dgpu-docs.intel.com/overview/supported-hardware/i915-driver-gpus.html>

**Final strategic principle:** Treat Kiro as an experiment designer and disciplined coding assistant, not as a source of GPU hardware truth. Measurement and correct computation determine whether a change is an improvement.
