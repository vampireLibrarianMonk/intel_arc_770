# Next session — pick up here

## State (2026-11-07)

Everything queued has finished: gpt-oss-20b, OpenVINO int4 7B and 14B (14B passed the 1.2x speed
gate at 1.53x) and the full eval-v2 run (11 candidates, 2 judges). Nothing is running.

- Findings: `reports/eval_v2/FINDINGS.md`; tables: `reports/eval_v2/results.md`.
- Method: `llm/eval-v2/README.md`. Registry and recommended configs:
  `llm/harness-alpha/MODELS.md`.

## Waiting on you: the blind writing review

`reports/eval_v2/review_packet.md` has 4 anonymous writers x 10 prompts (about 70 min to read in
full; the header lists a 28-minute subset). Fill in `reports/eval_v2/ballot.txt` (e.g.
`w01_premise_scene: B > D > A > C`; leave a line as `_` to skip it), then run
`python3 llm/eval-v2/tally.py`. It reveals who wrote what and writes
`reports/eval_v2/human_results.md`. The key lives in `artifacts/eval-v2/review_key.json` (not
committed; regenerate with `make_report.py` if lost, labels are seeded).

Please avoid `reports/data/eval-v2/` until you've ranked: it shows authorship.

## Open items

1. Add your own prompts to `llm/eval-v2/user_prompts/*.txt` and rerun (resumable) if the built-in
   ones don't reflect your real use. Judge and report again with `FORCE=1` only where needed.
2. gpt-oss-20b ran at low reasoning effort and overshoots requested lengths; try `medium`.
3. `xe` kernel driver and llama.cpp SYCL remain untested by choice (see
   `reports/followup_techniques.md`).
