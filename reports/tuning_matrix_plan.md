# Arc A770 — Vulkan tuning matrix plan

## Context

- **GPU:** Intel Arc A770 16 GiB, PCI `8086:56a0` (DG2), rev 08.
- **OS/kernel:** Ubuntu 24.04, kernel `7.0.0-42-generic` (upgraded from `6.8.0-147`).
- **Driver bound:** `i915` (xe also loaded, 0 refs).
- **Vulkan stack:** Mesa 25.2.8 (ANV), Vulkan API 1.4.318; `glslc` shaderc v2023.8.
- **Harness:** `llm/harness-alpha`, llama.cpp Vulkan build, model
  `Qwen2.5-7B-Instruct-Q4_K_M.gguf`, shared OpenAI-compatible benchmark (`bench_openai.py`).
- **Verified baseline (post-reboot, kernel 7.0):** median **41.0 tok/s**, coding 4/4,
  writing 4/4. Reproduction: `bash llm/harness-alpha/run/run_llamacpp.sh vulkan`.

This matches the pre-reboot post-fix result (41.9 tok/s), confirming the glslc throughput
regression fix (`940e691`) held across the kernel upgrade.

## Objective

Find launch-flag levers that improve decode throughput and/or usable context on the A770
Vulkan path, without changing the model, the task set, or the shared driver. Each variant is
a **single controlled change** from the baseline so any delta is attributable.

## Levers under test

| variant | flags | hypothesis |
|:--|:--|:--|
| `-baseline` | *(defaults)* | control; reproduces ~41 tok/s |
| `-fa-on` | `-fa on` | force flash attention (build defaults to `auto`; confirm it engages and helps) |
| `-fa-kvq8` | `-fa on -ctk q8_0 -ctv q8_0` | 8-bit KV cache cuts memory-bandwidth pressure, the likely A770 bottleneck |
| `-ub256` | `-ub 256` | smaller physical batch may suit the A770's execution width |
| `-ub1024` | `-ub 1024` | larger physical batch may raise GPU occupancy |
| `-fa-kvq8-ub256` | `-fa on -ctk q8_0 -ctv q8_0 -ub 256` | stack the individually-winning levers |

## Method

- Shared benchmark driver + fixed task set (coding executed against unit tests; writing
  checked for measurable properties + saved verbatim).
- Greedy decoding (temperature 0) for run-to-run comparability.
- One server per variant, full GPU offload (`-ngl 999`), context 4096.
- Each variant recorded as its own candidate id → `aggregate.py` lists it as a row.
- GPU-use confirmed by throughput regime (CPU 7B ~8 t/s vs GPU ~40+ t/s); Mesa ANV does not
  export per-process VRAM via fdinfo, a known limitation documented in `gpu_probe.sh`.

## What this does NOT do

- No GPU clock/power changes (AGENTS.md: human-approval-required; not touched here).
- No model swap (that is a separate capability-vs-speed tradeoff, tracked separately).
- No driver/firmware/kernel changes.

## Reproduction

```bash
cd ~/projects/intel_arc_770
bash llm/harness-alpha/run_tuning_matrix.sh            # vulkan
tail -f artifacts/harness-alpha/TUNING_STATUS.txt      # progress
python3 llm/harness-alpha/aggregate.py                 # comparison table
```

## Results

_Pending run — populated from `artifacts/harness-alpha/TUNING_STATUS.txt` and the per-variant
JSON records below._
