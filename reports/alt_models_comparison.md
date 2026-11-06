# Non-Qwen model comparison — Arc A770 (Vulkan, kernel 7.0)

Answering "are we stuck with Qwen?" with measurements, not blog claims. Same card, backend,
flags, driver, and task set as the rest of this cycle; only the model varies. Scored on the
**hard** task set (the one that discriminates — see `reports/tuning_matrix_plan.md`).

- GPU: Intel Arc A770 16 GiB (`8086:56a0`), kernel 7.0.0-42, Mesa 25.2.8 (ANV Vulkan).
- Backend: llama.cpp Vulkan, full GPU offload (`-ngl 999`), ctx 4096, greedy.
- Harness: `llm/harness-alpha`, hard task set (5 coding + 5 writing), exec-timeout-hardened.
- All models Q4_K_M GGUF; all pinned 2400 MHz under load (no throttle).

## Results (hard task set)

| model | params | size | median tok/s | hard coding | hard writing | notes |
|:--|:--|--:|--:|:--:|:--:|:--|
| Phi-3.5-mini-instruct | 3.8B | 2.4 GB | **76.8** | 3/5 | 2/5 | ~2x faster; weak on tight length limits + edge cases |
| Qwen2.5-7B-Instruct | 7B | 4.4 GB | 42.7 | 4/5 | 2/5 | general baseline |
| Meta-Llama-3.1-8B-Instruct | 8B | 4.9 GB | 42.3 | 4/5 | **3/5** | strong writer; nailed 6-word story + acrostic + constrained scene |
| gemma-2-9b-it | 9B | 5.8 GB | 26.9 | 3/5 | 2/5 | slow for its size; misses edge cases (`'babad'` → `aba`, calculator ignores spaces) |
| Mistral-Nemo-Instruct-2407 | 12B | 7.5 GB | 27.9 | 4/5 | 1/5 | only the 6-word story passes; fails on length/forbidden-word/line-count constraints |
| DeepSeek-Coder-V2-Lite-Instruct | 16B MoE (~2.4B active) | 10.4 GB | **58.6** | 4/5 | 0/5 | fastest model above ~4B; coding on par with 7-8B dense; writing fails every constraint |
| Qwen2.5-14B-Instruct | 14B | 8.4 GB | 21.7 | **5/5** | 3/5 | best quality so far, half the speed |

(Qwen rows are from the model sweep in `reports/tuning_matrix_plan.md`, same hard set, for
side-by-side reference.)

## Findings so far

- **We are NOT stuck with Qwen.** Llama-3.1-8B matches the Qwen-14B's writing score (3/5) at
  **half the parameters and ~2x the throughput** (42 vs 22 tok/s), and ties Qwen-7B on coding.
  For the writing half of the goal it's an excellent, faster default.
- **Speed scales inversely with size, cleanly:** Phi-3.5-mini (3.8B) runs 76.8 tok/s — nearly
  double the 7-8B class — because the A770 is clock-saturated and smaller = less compute per
  token. The quality cost is real (it can't hold tight word limits), so it's a
  speed-for-simple-work pick, not a quality pick.
- **A shared hard ceiling persists:** every model so far writes "hash" despite the ban in
  `explain_to_child`, and the subtext dialogue trips most of them. The hard set still has
  headroom — exactly what we want for ranking larger/better models.
- **MoE changes the speed curve.** DeepSeek-Coder-V2-Lite (16B total, ~2.4B active) runs
  **58.6 tok/s** — 1.4x the 7B dense models and 2.7x the Qwen-14B — while fitting in 16 GiB.
  Its coding score (4/5) matches Qwen-7B and Llama-3.1-8B, but it did not beat them: it fails
  `basic_calculator` (returns `None` for `'1 + 1'`). For coding it is a speed win, not a
  quality win.
- **DeepSeek-Coder is not a writer.** 0/5 on the writing set. This is a genuine result, not a
  harness fault: the raw outputs are fluent prose that violates the constraints (5-word
  "six-word" story, broken acrostic, uses the banned words "hash"/"time"/"home"/"key").
- **Bigger or newer is not better here.** Gemma-2-9B (3/5 + 2/5) and Mistral-Nemo-12B
  (4/5 + 1/5) both score at or below the 7-8B models on this set, at ~27 tok/s (~35% slower
  than Llama-3.1-8B). Llama-3.1-8B remains the best speed/writing trade-off tested; Qwen-14B
  remains the best quality.
- **Limitations:** each model was run once (greedy, ctx 4096, max_tokens 512) on 5+5 tasks, so
  a one-task difference is within noise; "writing constraints" checks measurable properties
  only, not prose quality. gemma-2 and Mistral-Nemo speeds were not investigated further
  (e.g. whether llama.cpp's Vulkan path lacks a fast kernel for gemma-2's attention
  soft-capping) — the cause of their lower tok/s is unverified.
- **Download note:** the earlier "throttled HF mirror" explanation was wrong. A non-HF test
  showed the same ~0.3-0.6 MiB/s cap, i.e. a local uplink limit; `HF_TOKEN` did not change
  throughput. All three files passed the size + sha256 gate before being benchmarked.

## Reproduce

```bash
cd ~/projects/intel_arc_770
bash llm/harness-alpha/run_alt_models.sh vulkan           # all five models, hard set by default
bash llm/harness-alpha/run_alt_models_pending.sh vulkan   # only gemma / Mistral-Nemo / DeepSeek
tail -f artifacts/harness-alpha/ALT_STATUS.txt
```

Raw per-task JSON (including model outputs): `reports/data/tuning-24.04-kernel7.0/`.
Optional: export `HF_TOKEN` before running; the fetcher sends it as a Bearer header without
logging it.
