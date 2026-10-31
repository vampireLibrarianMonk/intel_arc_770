# User Guide — using the full 16 GiB on the Arc A770

This guide shows how to use the whole card, how to verify it, and the one caveat that
matters. It assumes the bring-up is already done (kernel 6.8, OpenCL + Level Zero, GuC,
PyTorch `2.6.0+xpu` in `.venv-xpu`). If you are setting a fresh box up, see
[CHANGELOG](../CHANGELOG.md) and the `scripts/bringup/b*.sh` operator scripts in order.

---

## The one thing to know

The A770 has 15.11 GiB of VRAM but caps a **single** allocation at **4.00 GiB** by default.
This is a driver policy, not the card running out of memory. Two separate goals:

| goal | needs |
|:--|:--|
| many buffers that total > 4 GiB | nothing — allowed by default |
| ONE buffer/tensor larger than 4 GiB | the unlock below |

---

## PyTorch: use the full card (no code change)

torch.xpu exposes no large-allocation flag, so set the NEO debug key before launching.
**Both** variables are required.

```bash
source scripts/xpu_env.sh      # sets NEOReadDebugKeys=1 and AllowUnrestrictedSize=1
python your_training_script.py
```

Other ways to apply it:

```bash
scripts/xpu_env.sh python your_training_script.py   # wrap one command
eval "$(scripts/xpu_env.sh)"                         # print-and-eval
export NEOReadDebugKeys=1 AllowUnrestrictedSize=1    # by hand
```

Verify it took, on this card:

```bash
source scripts/xpu_env.sh
python scripts/bringup/b8_max_and_matmul.py   # prints the largest correct single tensor
```

Expected: a single tensor up to ~15.0 GiB allocates and computes correctly. Without the key,
anything over 4 GiB fails with `torch.OutOfMemoryError` even though the card is empty.

### ⚠️ Caveat — this is a debug key
`AllowUnrestrictedSize` is Intel's **driver-development debug key**. It is not part of any
spec and may change or be removed. It is fine for local experiments and large-tensor work on
this box. For a product you ship, use the real API flags (next section), which means
C++/SYCL — plain torch.xpu cannot pass them.

---

## C++ (OpenCL / Level Zero): the stable, supported path

For a single buffer > 4 GiB you need **both** halves. Either one alone is wrong.

### OpenCL
```c
// 1) allocate with the relaxed-size flag
cl_mem_flags flags = CL_MEM_READ_WRITE | CL_MEM_ALLOW_UNRESTRICTED_SIZE_INTEL;
cl_mem buf = clCreateBuffer(ctx, flags, bytes /* > 4 GiB */, NULL, &err);

// 2) build the kernel in stateless mode
clBuildProgram(prog, 1, &dev, "-cl-intel-greater-than-4GB-buffer-required", NULL, NULL);
```

### Level Zero
```c
ze_relaxed_allocation_limits_exp_desc_t relaxed = {
    ZE_STRUCTURE_TYPE_RELAXED_ALLOCATION_LIMITS_EXP_DESC };
relaxed.flags = ZE_RELAXED_ALLOCATION_LIMITS_EXP_FLAG_MAX_SIZE;

ze_device_mem_alloc_desc_t desc = { ZE_STRUCTURE_TYPE_DEVICE_MEM_ALLOC_DESC };
desc.pNext = &relaxed;                       // 1) relaxed allocation
zeMemAllocDevice(ctx, &desc, bytes, 64, dev, &ptr);

// 2) build the module stateless
moduleDesc.pBuildFlags = "-ze-opt-greater-than-4GB-buffer-required";
```

### The traps (proven on hardware)
| you do | result |
|:--|:--|
| relaxed alloc **+** stateless build | correct (use this) |
| relaxed alloc, **no** stateless build | allocates, then returns **wrong data** past 4 GiB — no error |
| stateless build, **no** relaxed alloc | allocation **rejected** |
| neither | rejected at 4 GiB |

**Never trust allocation success as proof of correctness.** Always verify values written
above the 4 GiB (2³² byte) offset. The harnesses in `tests/` do this against a CPU oracle.

---

## Reproduce the measurements

```bash
# OpenCL boundary + the two-flag matrix
cd tests/opencl && cmake -S . -B build && cmake --build build
./build/large_buffer --kernel kernels/sentinel.cl --json ../../artifacts/baseline/opencl_boundary.json

# Level Zero: same boundary + fix
cd ../tests/level-zero && cmake -S . -B build && cmake --build build && ./build/l0_large_buffer

# Stateless-vs-stateful speed (H2)
cd ../../benchmarks && cmake -S . -B build && cmake --build build
./build/addr_bench --size-gib 3.5 --reps 20 --kernel workloads/addr_bench.cl

# PyTorch full-card training stress
source ../scripts/xpu_env.sh
TARGET_GiB=14 python ../scripts/bringup/b10_near_full_vram.py
```

Results land in `artifacts/baseline/*.json`. Full analysis:
[`reports/FINDINGS_memory_4gib.md`](../reports/FINDINGS_memory_4gib.md).

---

## Troubleshooting

| symptom | cause | fix |
|:--|:--|:--|
| `torch.OutOfMemoryError` at >4 GiB, card empty | debug key not set | `source scripts/xpu_env.sh` (BOTH vars) |
| key set but still capped | only `AllowUnrestrictedSize` set | also set `NEOReadDebugKeys=1` |
| matmul hangs forever (EXIT 124) | torch too new for the driver | use torch `2.6.0+xpu` (matches NEO 24.39) |
| `CL_INVALID_BUFFER_SIZE (-61)` | >4 GiB without the relaxed flag | add `CL_MEM_ALLOW_UNRESTRICTED_SIZE_INTEL` + stateless build |
| wrong numbers past 4 GiB, no error | relaxed alloc without stateless build | add `-cl-intel-greater-than-4GB-buffer-required` |
| render node missing / card not bound | on kernel 5.15 | boot kernel 6.8 (`uname -r`) |
