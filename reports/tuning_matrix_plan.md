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

Run 2026-11-04 (kernel 7.0.0-42, Mesa 25.2.8, model Qwen2.5-7B-Q4_K_M, ctx 4096, greedy).
Raw per-variant JSON in `artifacts/harness-alpha/llamacpp-vulkan-*_*.json`; status log in
`artifacts/harness-alpha/TUNING_STATUS.txt`.

| variant | flags | median tok/s | Δ vs baseline | coding | writing |
|:--|:--|--:|--:|:--:|:--:|
| `-baseline` | *(defaults)* | 41.2 | — | 4/4 | 4/4 |
| `-ub256` | `-ub 256` | 41.1 | −0.1 | 4/4 | 4/4 |
| `-fa-on` | `-fa on` | 41.0 | −0.2 | 4/4 | 4/4 |
| `-ub1024` | `-ub 1024` | 41.0 | −0.2 | 4/4 | 4/4 |
| `-fa-kvq8` | `-fa on -ctk q8_0 -ctv q8_0` | 39.6 | **−1.6** | 4/4 | 4/4 |
| `-fa-kvq8-ub256` | `-fa on -ctk q8_0 -ctv q8_0 -ub 256` | 39.7 | **−1.5** | 4/4 | 4/4 |

### Conclusion (negative result — stated plainly)

**No lever improved throughput.** `-fa on` and ubatch resizing are within run-to-run noise
(~±0.5 tok/s). 8-bit KV cache (`-ctk/-ctv q8_0`) measurably *hurt* (−1.5 tok/s): on the
Mesa/ANV Vulkan path the per-access dequant cost outweighs the bandwidth saving at this
model size and 4K context.

Takeaway: **for 7B-Q4 at 4K context on the A770 Vulkan backend, the default llama.cpp flags
are already near-optimal for decode throughput.** The ~41 tok/s ceiling is not set by these
knobs. Correctness held everywhere (coding 4/4, writing 4/4), so none of the flags broke
output.

### Uncertainty / limits

- Single run per variant; deltas under ~1 tok/s are not significant. Flash-attn and ubatch
  should be treated as "no effect", not "tiny effect".
- Only decode throughput measured. KV quant's real payoff is **larger context within VRAM**,
  not speed — not exercised here (4K fit comfortably in 16 GiB uncompressed).
- Mesa ANV does not expose per-process VRAM via fdinfo; GPU use inferred from the ~41 vs
  ~8 tok/s CPU regime.

### Where the real levers likely are (next tracks, not yet run)

1. **Model choice** — Qwen2.5-Coder-7B (coding quality) or a 14B-Q4 (~9 GiB, fits 16 GiB)
   for better output at still-usable speed. This trades tok/s for capability, which may be
   the better lever for the writing+coding goal than chasing tok/s.
2. **SYCL re-test on kernel 7.0** — prior cycle had SYCL slower (33.9) than Vulkan; the newer
   kernel + `xe` availability may change that. One controlled re-run.
3. **GPU clocks/power** — AGENTS.md gates this (human approval). Check for throttling headroom
   before assuming the 41 tok/s ceiling is the silicon's.

---

## Addendum — GPU clock/power headroom (resolved, 2026-11-04)

Sampled `/sys/class/drm/card1/gt/gt0/rps_act_freq_mhz` at 2 Hz during a live Vulkan baseline
(median 41.1 tok/s). Result:

- **Under load the A770 pins its maximum 2400 MHz** (RP0 = 2400; sampled median 2400, max
  2400). Idle sits at ~1000 MHz, ramps to 2400 immediately on load.
- **Zero throttle flags** across the whole `throttle_reason_*` set (pl1, pl2, pl4, thermal,
  prochot, vr_thermalert, vr_tdc, ratl all = 0).

**Conclusion:** 41 tok/s is **not** clock- or thermal-limited — the card already runs flat
out at full clock with no throttling. Raising clocks is therefore a non-lever (nothing to
raise), and there is no power/thermal headroom to reclaim. The bottleneck is the compute/
memory-bandwidth efficiency of the Vulkan path at this model size, which points back to
**model choice** (track 1) as the remaining meaningful lever, not power tuning. No
power/clock *changes* were made (AGENTS.md); this was read-only telemetry.

## Addendum — model sweep (in progress, 2026-11-04)

Holding backend/flags/task-set fixed and varying only the model (7B → Coder-7B → 14B, all
Q4_K_M).

| model | median tok/s | peak clock | coding | writing | notes |
|:--|--:|:--:|:--:|:--:|:--|
| Qwen2.5-7B-Instruct-Q4 | 42.0 | 2400 MHz | 4/4 | 4/4 | general baseline |
| Qwen2.5-Coder-7B-Instruct-Q4 | 42.1 | 2400 MHz | 4/4 | 4/4 | coding-tuned; same size/quant |
| Qwen2.5-14B-Instruct-Q4 | _pending_ | — | — | — | download gated on throttled mirror |

### Interim findings

- **Throughput at 7B-Q4 is model-independent:** general 7B and Coder-7B both run at ~42 tok/s
  (identical architecture size + quant → identical decode cost). Choosing the Coder model
  costs nothing in speed.
- **Our task set does not discriminate 7B quality:** both score coding 4/4, writing 4/4. The
  Coder model's advantage would only surface on harder problems than the current suite
  contains. Actionable: if coding quality matters, default to **Coder-7B** — it's free on
  speed and strictly better-aimed, even though the easy suite can't prove it here.
- **14B pending:** this is the data point that will quantify the speed cost of doubling
  parameters (expected: meaningfully slower but still interactive). Completes asynchronously
  via `run_model_sweep.sh`; results append to `SWEEP_STATUS.txt` and this table.

Raw per-model JSON kept in `reports/data/tuning-24.04-kernel7.0/`. Authoritative sha256s and
the sweep harness are committed so the sweep is reproducible regardless of mirror speed.
