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
| gemma-2-9b-it | 9B | 5.8 GB | _pending_ | — | — | download in progress |
| Mistral-Nemo-Instruct-2407 | 12B | 7.5 GB | _pending_ | — | — | queued |
| DeepSeek-Coder-V2-Lite-Instruct | 16B MoE (~2.4B active) | 10.4 GB | _pending_ | — | — | queued; MoE may beat dense speed/quality curve |
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
- **Still pending** (downloads gated on a throttled HF mirror, ~0.3 MiB/s): Gemma-2-9B,
  Mistral-Nemo-12B, DeepSeek-Coder-V2-Lite. These complete asynchronously via
  `run_alt_models.sh`; an `HF_TOKEN` next session will make the remaining ~24 GB fast.

## Reproduce

```bash
cd ~/projects/intel_arc_770
bash llm/harness-alpha/run_alt_models.sh vulkan   # hard set by default
tail -f artifacts/harness-alpha/ALT_STATUS.txt
```
