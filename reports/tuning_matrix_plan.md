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

## Addendum — model sweep (complete, 2026-11-05)

Holding backend/flags/task-set fixed and varying only the model (all Q4_K_M, Vulkan, ctx
4096, greedy). All three pinned 2400 MHz under load (no throttle), so throughput differences
are pure compute volume.

| model | size | median tok/s | coding | writing | fits 16 GiB |
|:--|--:|--:|:--:|:--:|:--:|
| Qwen2.5-7B-Instruct-Q4 | 4.4 GB | 42.0 | 4/4 | 4/4 | yes |
| Qwen2.5-Coder-7B-Instruct-Q4 | 4.4 GB | 42.1 | 4/4 | 4/4 | yes |
| Qwen2.5-14B-Instruct-Q4 | 8.4 GB | **21.9** | 4/4 | 3/4* | yes |

\* The 14B's one writing miss is a `min_sentences` constraint on `opening_paragraph` (64
words in 2 sentences, wanted ≥3) — a structural-checker miss, **not** a prose-quality
failure. The coarse constraint checks don't prove the 14B writes worse; raw text is saved
for human judgement.

### Findings

- **Parameter count is the dominant speed lever, inversely:** doubling 7B→14B roughly halves
  throughput (42 → 22 tok/s). Both are clock-saturated at 2400 MHz; the 14B is slower purely
  because it does ~2x the compute per token.
- **14B fits comfortably** (8.4 GB model + KV in 16 GiB) and 22 tok/s is still interactive
  (faster than typical reading speed). It's a reasonable "quality when you want it" option.
- **At 7B, model choice is free on speed** (general vs Coder both 42 tok/s). Prefer Coder-7B
  for coding-heavy use.
- **The task set is too easy to rank quality** — every model scores 4/4 coding, and writing
  "failures" are structural-check artifacts. To actually differentiate models we need a
  harder suite (see next step).

### Recommendation for the stated goal (creative writing + Python coding)

- **Default / interactive:** Qwen2.5-Coder-7B-Q4 — 42 tok/s, free coding specialization.
- **Quality pass / harder problems:** Qwen2.5-14B-Q4 — 22 tok/s, more capability, still fits
  and stays interactive.
- Speed is not improvable by flags or clocks (both already shown maxed); the only speed lever
  is picking the smaller model. The real remaining work is a **discriminating task set** to
  prove where the 14B's extra capability actually pays off.

Raw per-model JSON in `reports/data/tuning-24.04-kernel7.0/`.

## Addendum — hard discriminating task set (2026-11-05)

The alpha set saturated every model at ~4/4, so it could not rank quality. Built
`tasks_hard.py`: 5 real algorithmic coding problems (longest palindromic substring, edit
distance, interval merge, coin change, hand-written expression parser — each with edge-case
tests) and 5 tighter writing tasks (exact 6-word story, compound forbidden+required
constraints, C-O-D-E acrostic, jargon-free explanation, subtext dialogue). Run via
`run_hard_suite.sh` against on-disk models (no downloads).

| model | hard coding | hard writing | median tok/s |
|:--|:--:|:--:|--:|
| Qwen2.5-7B-Instruct-Q4 | 4/5 | 2/5 | 42.7 |
| Qwen2.5-14B-Instruct-Q4 | **5/5** | **3/5** | 21.7 |
| Qwen2.5-Coder-7B-Instruct-Q4 | not captured† | not captured† | ~42 |

† The Coder-7B hard run surfaced a **harness robustness bug** (see below) and the capture was
blocked by intermittent process-launch flakiness in the session environment. The bug is fixed
and unit-tested; re-running `run_hard_suite.sh` will complete it.

### The hard set discriminates (the point of building it)

- **7B fails where 14B succeeds.** The 7B failed the expression parser (`IndexError`, an
  edge-case bug), botched the exact-6-word story, and missed two writing constraint sets.
  The 14B went **5/5 coding** (including the parser) and **3/5 writing** (nailed the 6-word
  story and acrostic). On the alpha set both were 4/4 — the hard set makes the 14B's extra
  capability measurable.
- **Shared hard ceiling:** both missed `explain_to_child` (both wrote "hash" despite the ban)
  and the subtext dialogue — genuinely hard negative-constraint instruction-following that
  even 14B doesn't clear. Good signal that the set has headroom for bigger models.

### Harness robustness fix (prompted by the hard set)

Harder coding prompts make models more likely to emit **infinite loops**. `score_coding`
ran model code with no execution bound, so one looping generation hung the whole benchmark
(observed: a single task stalled the client ~14 min). Fixed with a `SIGALRM` watchdog
(`_time_limit`) around both the code-defining `exec` and every test call; a runaway now fails
as `timeout (>Ns) — likely infinite loop` instead of hanging. Unit-verified: a `while True`
solution aborts in 2 s, correct code still passes instantly.

## Addendum — are we stuck with Qwen? (model research, 2026-11-05)

**No.** Qwen2.5 is a strong default but several other open-weight families fit the A770's
16 GiB at Q4 and bring different strengths, especially for creative writing where Qwen's
"synthetic-data slop" is a known weakness. Candidates worth benchmarking on this card
(all have mature GGUF/llama.cpp support, all Q4 fit 16 GiB):

| family / model | ~Q4 size | why try it | license |
|:--|--:|:--|:--|
| **Mistral-Nemo-12B-Instruct** | ~7 GB | 128K ctx, strong reasoning/coding for its size; de-slopped community fine-tunes (e.g. "low-slop" storyteller variants) are popular for creative writing | Apache-2.0 |
| **Llama-3.1-8B-Instruct** | ~4.9 GB | widely cited best all-round small *writer*; clean grammar, strong instruction-following | Llama license |
| **Gemma-2-9B-it** | ~5.8 GB | noticeably tidy prose for its size; good for copy/email/explanatory writing | Gemma license |
| **DeepSeek-Coder-V2-Lite-Instruct (16B MoE, ~2.4B active)** | ~10 GB | coding-specialist; MoE means high quality at lower active compute → potentially faster than a dense 14B | DeepSeek license |
| **Phi-4 (14B)** | ~8.5 GB | strong reasoning/STEM for size; good coding | MIT |

Notes and next step:
- These span three different tradeoffs: **writing quality** (Llama-3.1-8B, Gemma-2-9B,
  Mistral-Nemo de-slop fine-tunes), **coding** (DeepSeek-Coder-V2-Lite, Phi-4), and **speed
  via MoE** (DeepSeek-Coder-V2-Lite's low active-parameter count is the one plausible way to
  beat the dense-model speed/quality curve we measured).
- The sweep harness already takes any GGUF via `get_model_generic.sh <repo> <file> <size>
  <sha256>`, so adding these is just more rows in `run_model_sweep.sh` once their authoritative
  sha256s are pulled from HF. The hard task set + exec-timeout fix make the comparison both
  discriminating and hang-proof.
- Licenses differ (Apache-2.0 for Qwen/Mistral vs model-specific terms for Llama/Gemma/
  DeepSeek) — worth noting if this ever ships beyond local use.
