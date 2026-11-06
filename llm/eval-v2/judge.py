#!/usr/bin/env python3
"""judge.py — blind rubric scoring of every eval-v2 writing sample by one local judge model.

The judge sees the task prompt and the response only, never the model name. Samples are
presented in a shuffled order (fixed seed) so no candidate is always judged first or last.
Scores are 1-10 on five criteria; the judge runs at temperature 0.

Known weaknesses, stated in the report: any model that fits on this card is roughly as weak
as the candidates, judges tend to prefer their own family's style, and they reward length.
Hence (a) two different judges, (b) self-judgments are flagged and excluded from rankings,
(c) the blind human review stays the primary signal.

  python judge.py --base-url http://127.0.0.1:8091/v1 --judge qwen2.5-14b \
      --judge-model-file Qwen2.5-14B-Instruct-Q4_K_M.gguf \
      --results-dir artifacts/eval-v2/results --out artifacts/eval-v2/judgments/qwen2.5-14b.jsonl
"""

import argparse
import glob
import json
import os
import random
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from run_eval import chat  # noqa: E402
from tasks_writing import all_writing_tasks  # noqa: E402

CRITERIA = ["adherence", "craft", "originality", "voice", "coherence"]
RUBRIC = """You are an exacting fiction editor grading one piece of creative writing.

TASK GIVEN TO THE WRITER:
<<<
{task}
>>>

RESPONSE:
<<<
{response}
>>>

MEASURED FACTS (computed by the test harness, trust them):
- Length: {words} words; the task asked for {lo}-{hi} words.
- {cutoff}

Score the response from 1 to 10 on each criterion:
- adherence: did it do exactly what was asked (form, length, constraints, point of view)?
- craft: sentence-level quality: specific concrete detail, rhythm, precise word choice.
- originality: avoids clichés, stock phrases and the most predictable choices.
- voice: a distinctive, consistent voice suited to the piece.
- coherence: logic, continuity and a satisfying shape.

Calibration (follow strictly):
- Typical competent model output is 4-6. 7-8 is clearly strong work. 9-10 is rare: writing you
  would expect in a top literary magazine.
- If the response was cut off before finishing, coherence is at most 3.
- If the length is more than 15% outside the requested range, adherence is at most 5.
- Each cliché or stock phrase ("a testament to", "shiver down her spine", "the weight of",
  "hung in the air", ...) should lower originality.
- Length is not quality. Do not reward a response for being longer.

Reply with ONLY a JSON object, no other text:
{{"adherence": n, "craft": n, "originality": n, "voice": n, "coherence": n, "comment": "<=25 words"}}"""


def parse(text):
    m = re.search(r"\{.*\}", text, re.S)
    if not m:
        return None
    try:
        d = json.loads(m.group(0))
        if all(isinstance(d.get(k), (int, float)) and 1 <= d[k] <= 10 for k in CRITERIA):
            return d
    except json.JSONDecodeError:
        return None
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base-url", required=True)
    ap.add_argument("--judge", required=True)
    ap.add_argument("--judge-model-file", required=True)
    ap.add_argument("--results-dir", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--max-tokens", type=int, default=700)
    a = ap.parse_args()

    tasks = {t["id"]: t for t in all_writing_tasks()}
    items = []
    for f in sorted(glob.glob(os.path.join(a.results_dir, "*.json"))):
        r = json.load(open(f))
        for w in r["writing"]:
            items.append((r["candidate"], r.get("model_file", ""), w))
    random.Random(1234).shuffle(items)

    done = set()
    if os.path.exists(a.out):  # resumable
        for ln in open(a.out):
            j = json.loads(ln)
            done.add((j["candidate"], j["id"], j["seed"]))
    chat(a.base_url, "Say hi.", 8, 0.0)
    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    with open(a.out, "a") as out:
        for cand, mfile, w in items:
            key = (cand, w["id"], w["seed"])
            if key in done or w["id"] not in tasks:
                continue
            row = {"judge": a.judge, "candidate": cand, "id": w["id"], "seed": w["seed"],
                   "self": os.path.basename(mfile) == os.path.basename(a.judge_model_file)}
            if not w["text"].strip():
                row.update(scores=None, error="empty response")
            else:
                lo, hi = tasks[w["id"]].get("words", (0, 100000))
                cutoff = ("The response was CUT OFF by the token limit before it finished."
                          if w.get("finish_reason") == "length" else "The response finished normally.")
                prompt = RUBRIC.format(task=tasks[w["id"]]["prompt"], response=w["text"],
                                       words=len(w["text"].split()), lo=lo,
                                       hi=hi if hi < 100000 else "any", cutoff=cutoff)
                d = None
                for attempt in range(2):
                    r = chat(a.base_url, prompt, a.max_tokens, 0.0, seed=7 + attempt)
                    d = parse(r["text"])
                    if d:
                        break
                row.update(scores={k: d[k] for k in CRITERIA} if d else None,
                           comment=(d or {}).get("comment", ""), error=None if d else "unparseable")
            out.write(json.dumps(row) + "\n")
            out.flush()
            print(f"[judge {a.judge}] {cand:28} {w['id']:24} {row.get('scores')}", flush=True)


if __name__ == "__main__":
    main()
