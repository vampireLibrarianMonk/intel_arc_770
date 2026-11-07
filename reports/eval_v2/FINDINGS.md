# eval-v2 findings (2026-11-07)

Interpretation of `results.md`. Method: `llm/eval-v2/README.md`. Environment as in
`reports/followup_techniques.md`: A770 16 GiB, kernel 7.0.0-42, llama.cpp Vulkan with default
flags (`-ngl 999 -c 8192 -np 1`), OpenVINO GenAI 2026.4.1 / NEO 26.40 for the two OpenVINO rows,
11 candidates, one run each. The creative-writing **human ranking is not done yet**, so every
writing conclusion below is provisional.

## Coding — a clear leader, then a pack

| model | greedy (of 15) | sampled passes (of 45) | median tok/s |
|:--|:--:|:--:|--:|
| **gpt-oss-20b** | **13** | **41** | 37.5 |
| DeepSeek-Coder-V2-Lite | 10 | 28 | 63.5 |
| Qwen2.5-14B (GGUF) / OpenVINO int4 | 10 / 10 | 24 / 25 | 23.0 / 33.6 |
| Qwen2.5-7B / OpenVINO int4 | 9 / 8 | 25 / 21 | 45.2 / 59.2 |
| Qwen2.5-Coder-7B | 9 | 29 | 45.2 |
| Llama-3.1-8B / Mistral-Nemo-12B | 8 / 8 | 25 / 21 | 44.0 / 28.8 |
| Gemma-2-9B / Phi-3.5-mini | 6 / 4 | 18 / 13 | 27.8 / 77.0 |

- **gpt-oss-20b leads on both measures:** 3 tasks ahead greedy, and ~12 attempts ahead of the
  next best when sampled. It's the only model to pass `split_quoted_csv` greedy, and the only one
  to pass `parse_duration` with any consistency. The next eight models are packed within two
  tasks of each other (8 to 10 of 15), so their order is not meaningful with 15 tasks.
- **Bigger or specialised is not better on this set:** Qwen2.5-Coder-7B ties the general 7B,
  and the 14B is no better than DeepSeek's 16B MoE.
- **OpenVINO int4 keeps the 14B's quality and adds ~46% speed** (10/15 greedy both ways,
  24 vs 25 sampled). For the 7B it is 31% faster, with one fewer task greedy and 4 fewer
  sampled passes (21 vs 25). That's within noise but not zero, so the 7B result is
  inconclusive rather than clean.
- **The hard tasks are real model errors, not bad tests.** Each new task's reference solution
  passes, and the failures are specific and reproducible. `topo_sort`: 33 attempts failed even the first,
  simplest case. The two I traced (Qwen2.5-14B, Llama-3.1-8B) built the graph from the dict keys
  only, missing names that appear solely as dependencies (a requirement the prompt states), and
  falsely reported a cycle. `split_quoted_csv`: e.g. Qwen2.5-14B returned
  `[',b', 'c']` for `"a,b",c`. `parse_duration`: accepted `'1h 30m'` against an explicit
  rule. `basic_calculator`: failures are mostly spaces
  (`'1 + 1'`) and parentheses.

## Creative writing — judges separate tiers, not the top

Scores are standardised per judge (each judge's own mean and spread), because the judges differ
a lot: Qwen2.5-14B averages 6.85 and gpt-oss-20b 5.25. On the 8 models that both can score without judging
themselves, their rankings agree strongly (Spearman 0.93, and the same bottom four). That says
little about gpt-oss-20b or Qwen2.5-14B, which only one judge can rate.

| tier | models | judge z |
|:--|:--|--:|
| top, indistinguishable | Qwen2.5-14B (+ its OpenVINO twin), Llama-3.1-8B, Mistral-Nemo-12B, gpt-oss-20b, Gemma-2-9B | +0.4 to +0.6 |
| middle | Qwen2.5-7B (+ OpenVINO twin) | −0.2 to −0.3 |
| bottom | DeepSeek-Coder-V2-Lite, Qwen2.5-Coder-7B, Phi-3.5-mini | −0.6 to −0.9 |

- **What is solid:** specialised or tiny models write worse (both judges agree), and Phi-3.5
  fails length badly (3 of 20 in range, 6 truncated).
- **What is not:** the order within the top tier. They are within about 0.2 z of each other.
- **gpt-oss-20b is two-sided.** The Qwen-14B judge (the only one that can rate it) puts it
  above every other candidate on craft, originality and voice (z +0.70 to +0.76), but it **ignores requested lengths**: 13 of 20 samples in range,
  often far over (938 words for a 400-500 word opening; 1165 for 600-800), none cut off. That
  drags its adherence score to z −0.26 and matters if you need a specific length. Its stock-phrase
  rate is the lowest of the top tier (2.9 per 1,000 words).
- **Llama-3.1-8B follows instructions best:** 20/20 samples in range, adherence z +0.86.
- Three candidates (gpt-oss-20b and the two Qwen2.5-14B variants) were scored by one judge only
  because a judge cannot rate itself or a variant of itself. Compare those with extra caution.

**AI reviewer ranking (not a human).** I (the assistant that built this harness) read all 40 pieces
in the blind packet and ranked each prompt *before* opening the answer key; the ballot and
per-prompt reasons are in `ballot_ai_reviewer.txt` and `ai_reviewer_notes.md`. It is a third
opinion next to the two judge models, not the independent human check. Borda points (max 30):

| writer | points | first places | average rank (1 = best) |
|:--|--:|--:|--:|
| Mistral-Nemo-12B | 22 | 5 | 1.8 |
| gpt-oss-20b | 21 | 4 | 1.9 |
| Qwen2.5-14B | 10 | 1 | 3.0 |
| Llama-3.1-8B | 7 | 0 | 3.3 |

- **Two clear tiers and one tie:** Mistral-Nemo and gpt-oss-20b are tied at the top (one point
  apart over ten prompts, which is nothing), and both beat Qwen2.5-14B and Llama-3.1-8B.
- **Where it agrees with the judges:** gpt-oss-20b is a strong writer on craft and voice. Where
  it disagrees: the judges put Qwen2.5-14B and Llama-3.1-8B at the top of the group, but I ranked
  them last, mostly for generic, telling prose (letters that announce "from beyond the grave",
  summary instead of scene). So the judge ordering within the top tier did not survive a human-style
  read.
- **I weighted craft over length.** gpt-oss had 6 of 10 samples in the requested length range and
  Llama 10 of 10, yet I ranked gpt-oss higher. A reader who needs exact lengths would rank
  differently.
- **Limits:** one rater, one sample per writer per prompt (4 writers, 10 prompts), no second
  read. A language model may favour the prose habits of other language models. Treat the ranking
  as a hypothesis for you to confirm or overturn with your own ranking in `ballot.txt`.

**Human review.** Still optional but valuable: `review_packet.md` (about 70 minutes in full or 28
for the six shortest prompts) and `ballot.txt` are untouched, so a human ranking can be tallied
the same way (`python3 llm/eval-v2/tally.py`) and compared with the one above.

## Changes made while analysing (disclosed)

1. **Judge aggregation.** The first report pooled raw scores across judges, which made
   gpt-oss-20b look #1 (it was only scored by the lenient judge) and Qwen2.5-14B look weak (only
   the harsh judge). Replaced with per-judge standardisation, and the Qwen-14B judge's scores of
   its own OpenVINO int4 variant are now excluded.
2. **Coding scorer.** A crash in a model's own example-usage code used to abort scoring before
   the function was tested. Fixed to run top-level statements separately. I re-scored all 660
   saved attempts: **no verdict changed**, so no coding number depends on this.
3. **Shortlist rule** (one writer per family) was defined after seeing the judge results.

## Limits

- 15 coding tasks and 10 writing prompts, one run per model; small gaps are noise.
- The coding tests are mine. They are validated against reference solutions but not against an
  external benchmark, and they reward edge-case care.
- Local judges are about as capable as the candidates and tend to reward polish.
- gpt-oss-20b ran at `--reasoning-effort low`; higher effort might do better at far greater
  token cost.
- These are 4-bit quantisations on one GPU, not the full-precision models.
