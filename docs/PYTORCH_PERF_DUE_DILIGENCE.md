# PyTorch-on-A770 Performance Due Diligence

Research backlog for improving PyTorch performance against the Intel Arc A770 via the
`torch.xpu` backend. **This is an investigation plan, not a list of promised speedups.**
Every item resolves to a measured A/B comparison with a CPU-oracle correctness check first.

Ground rules (from `AGENTS.md`):
- Correctness before performance. A faster wrong answer is a failed change.
- Never conflate "allocation works", "workload runs", and "throughput improved".
- Every finding records: torch/IPEX/NEO/IGC versions, flags, repro command, raw samples, uncertainty.
- Pin versions; prove which runtime actually loaded.

---

## Tier 0 — Establish a trustworthy baseline (do first)

| ID | Question | How to check | Deliverable |
|:--|:--|:--|:--|
| PT-000 | Is the stack even correctly wired? | `scripts/check_prereqs.sh` + `scripts/check_pytorch_xpu.py` | capability JSON |
| PT-001 | Which torch build / backend is loaded? | `torch.__version__`, native-XPU vs IPEX, Level Zero vs OpenCL path | version record |
| PT-002 | What is stock throughput on fixed workloads? | matmul / conv / elementwise at fixed sizes, 20 reps, median+p95 | baseline CSV |
| PT-003 | Is the GPU actually busy during the op? | `intel_gpu_top` / `xpu-smi` during a run | utilization trace |

Without PT-000..PT-003 locked, any later "speedup" is unverifiable.

---

## Tier 1 — Framework / API level (highest ROI, lowest risk)

These are configuration and usage changes inside PyTorch — no driver rebuilds.

| ID | Lever | Why it may matter on A770 | Verification |
|:--|:--|:--|:--|
| PT-010 | **dtype / mixed precision** (`torch.autocast("xpu")`, bf16/fp16) | Xe-HPG has strong fp16/bf16 throughput; fp32 may leave perf on the table | A/B time + `allclose` tolerance vs fp32 oracle |
| PT-011 | **Memory format** (channels-last for conv) | Layout changes vectorization/bandwidth | A/B on conv workloads |
| PT-012 | **`torch.compile` backend** availability/quality for XPU | Graph fusion can cut kernel-launch overhead | A/B eager vs compiled; verify identical outputs |
| PT-013 | **Operator coverage / CPU fallback** | Ops silently falling back to CPU destroy throughput | profiler device-time per op; flag any CPU fallback |
| PT-014 | **Batch size / tensor shape alignment** | Sub-optimal shapes underutilize EUs | sweep shapes; record occupancy |
| PT-015 | **H2D/D2H transfer overhead** | PCIe copies can dominate small ops; pinned memory, fewer syncs | separate transfer vs compute timers |
| PT-016 | **Allocator behavior / fragmentation** | Repeated alloc/free churn; caching allocator stats | `max_memory_allocated`, reserved vs allocated |
| PT-017 | **Stream / async execution & sync points** | Unnecessary `synchronize()` serializes work | count syncs; overlap copy+compute |

---

## Tier 2 — The >4 GiB large-buffer angle (project's core thesis)

Ties the PyTorch work back to the allocation investigation.

| ID | Question | Check |
|:--|:--|:--|
| PT-020 | Can a single tensor exceed 4 GiB on XPU, and are values past 2^32 correct? | `tests/pytorch/xpu_large_tensor.py` sentinels vs CPU ref |
| PT-021 | Does the framework trigger the stateless/relaxed path automatically, or silently cap/segment? | inspect allocation behavior + correctness at >4 GiB |
| PT-022 | Perf cost of large contiguous tensor vs chunked/segmented equivalent | A/B equal-work implementations |
| PT-023 | Does activation/KV-cache memory for a model cross the boundary and break? | end-to-end model with >4 GiB working set |

---

## Tier 3 — Profiling & bottleneck attribution (before any driver work)

| ID | Tool | What it tells us |
|:--|:--|:--|
| PT-030 | `torch.profiler` (XPU activities) | per-op device time, launch overhead, CPU vs GPU split |
| PT-031 | `intel_gpu_top` / `xpu-smi dump` | EU occupancy, memory bandwidth, power/clock, thermal throttle |
| PT-032 | Level Zero tracing / `ZE_DEBUG` | kernel submissions, copies, sync granularity |
| PT-033 | VTune / `unitrace` (if available) | stalls, spills, memory-bound vs compute-bound classification |
| PT-034 | Clock/thermal check | confirm results are not throttling artifacts |

Rule: **classify the bottleneck (memory-bound / compute-bound / launch-bound / fallback / transfer-bound) before proposing a fix.**

---

## Tier 4 — Runtime / compiler level (only if Tier 1–3 implicate it)

Highest cost, highest risk; requires local-prefix builds and pinned versions.

| ID | Question |
|:--|:--|
| PT-040 | Does a NEO/IGC version bump change op throughput for the profiled bottleneck? |
| PT-041 | Does the stateless addressing path cost measurable throughput for the hot kernels? (ties to ADR-0001) |
| PT-042 | Is there a specific op whose generated code shows register spills / poor addressing? |

Enter Tier 4 only with a profiled, reproducible bottleneck and a human-approved plan.

---

## Comparison hygiene (applies to every tier)

- Warm up; >= 10 (prefer 20) measured reps; randomize/alternate A/B order.
- Report median, p95, dispersion, and **all** raw samples.
- Pin and record: torch, IPEX, NEO, IGC, GmmLib, Level Zero, kernel, OS, firmware, clocks, thermals.
- Validate numerics against a CPU oracle every time; state the tolerance.
- One variable per experiment. Revert anything that regresses correctness.
- Distinguish throttled runs from real differences (PT-034).

## Tooling to confirm present during Phase 0 (read-only)

`intel_gpu_top` (intel-gpu-tools), `xpu-smi`, `clinfo`, `ze_info`, `torch.profiler`,
and optionally `unitrace` / VTune. Record which are available in the baseline capture.
