# eval-v2 — coding + creative-writing evaluation regime

Replaces the harness-alpha hard set as the way to decide which model to use. The old set is
kept for continuity, but it had three problems this regime fixes:

1. **Writing was never judged for quality.** It checked word counts and banned words on five
   short puzzles. Nobody read the saved text, so "good writer" really meant "follows
   constraints".
2. **Everything was greedy and ran once.** Greedy decoding isn't how anyone writes fiction, and
   with 5 tasks a one-task difference was noise.
3. **Coding was five algorithm puzzles,** executed in-process where a hang in C code or a memory
   blowup could take the scorer down.

## What runs

Every model is served by the same llama.cpp Vulkan build with identical flags (`-ngl 999
-c 8192 -np 1`, everything else default). Only the model changes. The one exception is
gpt-oss-20b, a reasoning model, which runs with `--reasoning-effort low` so its hidden reasoning
doesn't use up the answer budget. Its reasoning text is excluded from what gets scored.
The tenth candidate, `qwen2.5-7b-ov-int4`, is Qwen2.5-7B in OpenVINO's int4 format, served on
the GPU by `harness-alpha/run/ov_server.py` with the same request fields. It checks whether
OpenVINO's ~43% speed gain costs quality.

### Coding — 15 tasks, executed (`tasks_coding.py`)

| category | tasks |
|:--|:--|
| algorithm | longest palindrome, edit distance, merge intervals, coin change, expression parser (the 5 old hard tasks), spiral matrix |
| bugfix | fix a broken binary search; fix a mutable-default-argument bug without mutating the caller's list |
| class | O(1) LRU cache |
| parsing | strict duration parser with ValueError cases; quoted-CSV field splitter (no `csv` module) |
| graph | topological sort with tie-breaking + cycle detection; Dijkstra returning distance and path |
| utility | greedy word wrap; nested-dict flattening |

- **Protocol:** each task once greedy → **pass@1** (deterministic), plus 3 sampled attempts
  (temperature 0.6, top_p 0.95, seeds 11/22/33) → **sampled pass rate**, which shows how
  reliable a model is, not just whether it can.
- **Execution:** every attempt runs in a fresh `python3 -I` subprocess in a temp dir with a
  10 s timeout and a 2 GiB memory cap (`executor.py`). A wrong function name, prose instead of
  code, an infinite loop or a crash all count as a failure.
- **The tests are themselves tested.** Each new task carries a reference solution, and
  `python3 tasks_coding.py --selftest` proves all of them pass. The original buggy code for
  the bugfix tasks fails its tests.

### Creative writing — 10 prompts × 2 samples (`tasks_writing.py`)

| id | request | words |
|:--|:--|:--|
| w01 | scene from a premise (lighthouse keeper, letter from a drowned brother) | 600-800 |
| w02 | continue a given passage matching its voice, tense and POV | 400-600 |
| w03 | revise a cliché-ridden paragraph into strong prose | 120-220 |
| w04 | dialogue scene carried entirely by subtext | 300-450 |
| w05 | free-verse poem with an unexpected angle, two banned words | 12-20 lines |
| w06 | first-person monologue with a distinctive voice | 350-500 |
| w07 | mystery-novel opening ending on a hook | 400-500 |
| w08 | humor: three reviews of a haunted toaster | 250-400 |
| w09 | flash fiction with a *fair* twist | 200-300 |
| w10 | sensory description of an invented night market | 250-350 |

- **Sampling:** temperature 0.8, top_p 0.95, seeds 101 and 202. That's how people actually use
  models for fiction, and two samples keep one lucky draw from deciding things. The answer
  budget is 1600 tokens; a response cut off by it is recorded as truncated.
- **Your own prompts:** put `*.txt` files in `llm/eval-v2/user_prompts/`, one prompt per file.
  An optional first line `words: 300-500` sets the length range. They're run and judged like the
  built-in prompts.

### How writing is scored — three layers, in increasing order of trust

1. **Automatic diagnostics (never the score):** length within the requested range (±15%),
   repetition collapse, overused stock phrases per 1,000 words ("a testament to", "the
   weight of", ...), clichés kept in the revision task, banned words in the poem.
2. **Blind LLM rubric (`judge.py`):** Qwen2.5-14B and gpt-oss-20b each score every sample 1-10
   on adherence, craft, originality, voice and coherence, at temperature 0, in shuffled order,
   without knowing which model wrote it.
   - **Measured facts:** the judge is told the measured word count and whether the response
     was cut off.
   - **Calibration rules:** competent output is 4-6; a cut-off piece caps coherence at 3; more
     than 15% off the requested length caps adherence at 5.
   - **Self-scoring:** a judge's scores of its own outputs are **excluded** from the rankings.
   - **Smoke-test check:** a deliberately off-task, cliché-ridden control scored 2.4 overall
     while real attempts scored ~5.8. Before the calibration rules were added, the judge
     gave 9-10 to everything, and that's why they exist.
   - **Limits:** local judges are about as weak as the candidates and still reward polish
     over substance, so treat these scores as a shortlist filter.
3. **Blind human ranking (primary):** `make_report.py` takes the top 4 writers by judge score
   and writes `reports/eval_v2/review_packet.md`.
   - **The packet:** each prompt has one sample per writer under shuffled labels (A-D,
     reshuffled per prompt). The label→model key goes to `artifacts/eval-v2/review_key.json`,
     outside the reports, so you can't see it while reading.
   - **Ranking:** fill in `reports/eval_v2/ballot.txt` (e.g. `w01_premise_scene: B > D > A > C`)
     and run `python3 llm/eval-v2/tally.py`. It reports Borda points and first places per
     model in `reports/eval_v2/human_results.md`.

## Running it

```bash
# full run; waits for the download chain (run_pending_evals.sh) to finish first
systemd-run --user --unit=eval-v2 --working-directory="$PWD" bash llm/eval-v2/run_eval_v2.sh
tail -f artifacts/eval-v2/STATUS.txt

SKIP_WAIT=1 bash llm/eval-v2/run_eval_v2.sh   # start now
SMOKE=1     bash llm/eval-v2/run_eval_v2.sh   # 2 tasks of each kind, Phi only, separate dirs
python3 llm/eval-v2/tasks_coding.py --selftest
```

It's resumable: a model or judge with existing output is skipped (`FORCE=1` redoes it).
Outputs:
- `reports/eval_v2/results.md` (tables) and `review_packet.md` / `ballot.txt` (human review)
- `reports/data/eval-v2/` (raw JSON with every model output and every judgment)

Expected runtime is roughly 2.5 h for the 10 candidates plus ~1.5 h for the two judges, measured from
smoke-run speeds and extrapolated.

## Known limitations

- **Small writing sample:** 10 prompts × 2 samples is still modest. Treat a gap of under ~0.5
  judge points as a tie unless the human ranking agrees.
- **Coding scope:** tests check behaviour, not code quality, readability or explanation.
  Multi-file or agentic coding isn't covered.
- **gpt-oss settings:** at low reasoning effort it may score below what it can do at higher
  effort, which costs far more tokens.
- **The judges are candidates too:** Qwen2.5-14B and gpt-oss-20b also judge, and their
  self-scores are excluded, but they may still favour models with a similar style.
