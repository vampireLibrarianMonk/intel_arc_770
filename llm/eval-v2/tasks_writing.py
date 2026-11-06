"""tasks_writing.py — eval-v2 creative-writing prompts (10 built-in + optional user prompts).

Unlike the harness-alpha hard set (short puzzles checked only for word counts and banned
words), these are realistic, longer requests of the kind a writer actually makes. Quality is
judged by a blind LLM rubric and a blind human ranking (see README.md). The automatic metrics
here are secondary diagnostics, never the score:
  - length within the requested range
  - repetition collapse
  - "stock phrase" count (phrases models overuse) and, for the revision task, how many of the
    source's clichés survived.

User prompts: drop plain-text files into llm/eval-v2/user_prompts/*.txt (one prompt per file;
an optional first line `words: 300-500` sets the length range). They are picked up
automatically and judged the same way.
"""

import glob
import os
import re

CONTINUATION_SOURCE = (
    "The ferry to Kessel Point ran twice a week, and Mara had missed it by the width of a gull. "
    "She stood on the pier with her suitcase between her boots, watching the boat shrink into the "
    "grey, and understood that she would have to ask the harbourmaster for a room. Everyone on the "
    "island knew the harbourmaster. Nobody she had spoken to on the mainland would say his name."
)

REVISION_SOURCE = (
    "It was a dark and stormy night. Detective Jack Stone was a tough, no-nonsense cop who had "
    "seen it all. He walked into the room and his heart was pounding like a drum. The victim was "
    "lying on the floor, dead as a doornail. 'This is going to be a long night,' he thought to "
    "himself, as a shiver ran down his spine. Little did he know that this case would change his "
    "life forever."
)
REVISION_CLICHES = ["dark and stormy", "no-nonsense", "seen it all", "pounding like a drum",
                    "dead as a doornail", "long night", "shiver ran down", "little did he know",
                    "change his life forever", "thought to himself"]

# Phrases instruction-tuned models overuse. Counted per 1,000 words; a diagnostic, not a score.
STOCK_PHRASES = [
    "tapestry", "testament to", "a dance of", "palpable", "shiver down", "shivers down",
    "sent a shiver", "barely above a whisper", "in the grand scheme", "little did",
    "a mix of", "a sense of", "couldn't help but", "the weight of", "hung in the air",
    "air was thick", "eyes widened", "breath she didn't know", "time seemed to",
    "unspoken", "intricate", "symphony of", "kaleidoscope", "whispers of", "ethereal",
    "delve", "a stark reminder", "every fiber",
]

WRITING_TASKS = [
    {"id": "w01_premise_scene", "words": (600, 800), "prompt": (
        "Write a 600-800 word scene. Premise: a lighthouse keeper on a remote island receives a "
        "letter, postmarked yesterday, from her brother, who drowned eleven years ago. Show, "
        "don't explain. End the scene before the mystery is solved. Return only the scene.")},
    {"id": "w02_style_continuation", "words": (400, 600), "prompt": (
        "Continue the following passage for 400-600 words. Match its voice, past tense and "
        "close-third point of view on Mara. Do not fully reveal who the harbourmaster is. "
        "Return only the continuation, without repeating the passage.\n\n" + CONTINUATION_SOURCE)},
    {"id": "w03_revision", "words": (120, 220), "prompt": (
        "Rewrite this paragraph as strong, specific prose of 120-220 words. Keep the same events "
        "but remove every cliché and every stock phrase. Return only the rewrite.\n\n"
        + REVISION_SOURCE), "cliches": REVISION_CLICHES},
    {"id": "w04_subtext_dialogue", "words": (300, 450), "prompt": (
        "Write a 300-450 word scene, mostly dialogue, between two old friends meeting at the "
        "funeral of a third. One of them is secretly the reason the friendship ended years ago. "
        "They talk only about the weather, the food and the drive. Never state the secret; the "
        "reader must infer it. Return only the scene.")},
    {"id": "w05_poem", "words": (60, 200), "forbidden": ["silence", "echo"], "prompt": (
        "Write a free-verse poem of 12-20 lines about a vending machine in an empty hospital "
        "corridor at 3 a.m. Find an unexpected angle. Do not use the words 'silence' or 'echo'. "
        "Return only the poem.")},
    {"id": "w06_voice_monologue", "words": (350, 500), "prompt": (
        "Write a 350-500 word first-person monologue: a retired safecracker opens the first "
        "night of a community-college class on locks, talking to the students. Give them a "
        "distinctive, consistent voice and let their history leak out without a confession. "
        "Return only the monologue.")},
    {"id": "w07_mystery_opening", "words": (400, 500), "prompt": (
        "Write the opening 400-500 words of a mystery novel. Establish the detective, the "
        "setting and the crime, and end on a hook that makes the reader turn the page. Avoid "
        "weather openings and hard-boiled clichés. Return only the opening.")},
    {"id": "w08_humor", "words": (250, 400), "prompt": (
        "Write three one-paragraph customer reviews of a haunted toaster, from three clearly "
        "different customers, each starting with a star rating out of 5. It should be genuinely "
        "funny. 250-400 words in total. Return only the reviews.")},
    {"id": "w09_flash_twist", "words": (200, 300), "prompt": (
        "Write a 200-300 word flash-fiction story with a twist ending that is fair: plant the "
        "clues so a careful reader could see it coming. Return only the story.")},
    {"id": "w10_sensory_setting", "words": (250, 350), "prompt": (
        "Describe a night market in a city that does not exist, in 250-350 words of continuous "
        "prose (no lists or headings). Engage at least four senses and make the place feel "
        "specific rather than generic. Return only the description.")},
]


def load_user_prompts(directory=None):
    directory = directory or os.path.join(os.path.dirname(os.path.abspath(__file__)), "user_prompts")
    tasks = []
    for path in sorted(glob.glob(os.path.join(directory, "*.txt"))):
        text = open(path).read().strip()
        words = (0, 100000)
        m = re.match(r"words:\s*(\d+)\s*-\s*(\d+)\s*\n", text)
        if m:
            words, text = (int(m[1]), int(m[2])), text[m.end():].strip()
        if text:
            tasks.append({"id": "user_" + os.path.splitext(os.path.basename(path))[0],
                          "words": words, "prompt": text})
    return tasks


def all_writing_tasks():
    return WRITING_TASKS + load_user_prompts()


def writing_metrics(text, task):
    """Secondary diagnostics only (see module docstring)."""
    low = text.lower()
    words = len(text.split())
    lo, hi = task.get("words", (0, 100000))
    toks = re.findall(r"\w+", low)
    top_share = max((toks.count(t) for t in set(toks)), default=0) / len(toks) if toks else 0
    stock = sum(low.count(p) for p in STOCK_PHRASES)
    m = {
        "words": words,
        "length_ok": lo * 0.85 <= words <= hi * 1.15,  # 15% grace either side
        "repetition_collapse": top_share >= 0.35,
        "stock_phrases": stock,
        "stock_per_1k_words": round(1000 * stock / words, 2) if words else 0.0,
        "empty": words == 0,
    }
    if "cliches" in task:
        m["cliches_kept"] = [c for c in task["cliches"] if c in low]
    if "forbidden" in task:
        m["forbidden_used"] = [w for w in task["forbidden"] if re.search(r"\b" + w + r"\b", low)]
    return m
