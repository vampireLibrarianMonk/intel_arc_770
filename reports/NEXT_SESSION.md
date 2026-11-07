# Next session — pick up here

## State (2026-11-07)

Everything queued has finished: gpt-oss-20b, OpenVINO int4 7B and 14B (14B passed the 1.2x speed
gate at 1.53x) and the full eval-v2 run (11 candidates, 2 judges). Nothing is running.

- Findings: `reports/eval_v2/FINDINGS.md`; tables: `reports/eval_v2/results.md`.
- Method: `llm/eval-v2/README.md`. Registry and recommended configs:
  `llm/harness-alpha/MODELS.md`.

## Writing quality: AI-reviewer result in, human check still open

The assistant ranked the blind packet itself (Mistral-Nemo-12B 22, gpt-oss-20b 21, Qwen2.5-14B 10,
Llama-3.1-8B 7 Borda points; see `reports/eval_v2/FINDINGS.md`). That is one model's opinion. If
you want an independent human check, `reports/eval_v2/review_packet.md` is unchanged: rank
`ballot.txt` (e.g. `w01_premise_scene: B > D > A > C`; skip lines with `_`; the six shortest
prompts take about 28 minutes), then run `python3 llm/eval-v2/tally.py`.
The key is in `artifacts/eval-v2/review_key.json` (not committed; regenerable with
`make_report.py`). `reports/data/eval-v2/` and `ai_reviewer_*` show authorship, so avoid them
until you have ranked.

## Open items

1. Add your own prompts to `llm/eval-v2/user_prompts/*.txt` and rerun (resumable) if the built-in
   ones don't reflect your real use. Judge and report again with `FORCE=1` only where needed.
2. gpt-oss-20b ran at low reasoning effort and overshoots requested lengths; try `medium`.
3. `xe` kernel driver and llama.cpp SYCL remain untested by choice (see
   `reports/followup_techniques.md`).
