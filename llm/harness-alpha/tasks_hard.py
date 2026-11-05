"""tasks_hard.py — a HARDER task set that discriminates model quality.

The alpha task set (tasks.py) is too easy: every 7B+ model scores ~4/4, so it cannot rank
quality. This set raises difficulty on both axes so stronger models can pull ahead:

  CODING   — real algorithmic problems with tricky edge cases (DP, recursion, parsing,
             intervals). A weak model typically passes the happy path but fails an edge
             case, so the executed-against-tests score spreads out.
  WRITING  — tighter, compound constraints (exact counts, multiple forbidden tokens,
             required inclusions, acrostics). Measurable checks only; raw text saved for
             human quality judgement as before.

Same schema as tasks.py so score.py scores it unchanged. Kept separate and stable so runs
stay comparable. Select at run time with bench_openai.py --task-set hard.
"""

CODING_TASKS = [
    {
        "id": "longest_palindrome_substring",
        "prompt": (
            "Write a Python function `solve(s)` that returns the longest palindromic "
            "substring of `s`. If several have the same maximal length, return the one that "
            "starts at the smallest index. Return only a fenced python code block."
        ),
        "entry": "solve",
        "tests": [
            (("babad",), "bab"),
            (("cbbd",), "bb"),
            (("a",), "a"),
            (("",), ""),
            (("forgeeksskeegfor",), "geeksskeeg"),
            (("abacdfgdcaba",), "aba"),
        ],
        "compare": "eq",
    },
    {
        "id": "edit_distance",
        "prompt": (
            "Write a Python function `solve(a, b)` that returns the Levenshtein edit distance "
            "between strings `a` and `b` (minimum single-character insertions, deletions, or "
            "substitutions to turn `a` into `b`). Return only a fenced python code block."
        ),
        "entry": "solve",
        "tests": [
            (("horse", "ros"), 3),
            (("intention", "execution"), 5),
            (("", ""), 0),
            (("", "abc"), 3),
            (("abc", "abc"), 0),
            (("kitten", "sitting"), 3),
        ],
        "compare": "eq",
    },
    {
        "id": "merge_intervals",
        "prompt": (
            "Write a Python function `solve(intervals)` that merges all overlapping intervals "
            "and returns the merged list sorted by start. Each interval is a [start, end] "
            "list; touching intervals (end == next start) merge. Return only a fenced python "
            "code block."
        ),
        "entry": "solve",
        "tests": [
            (([[1, 3], [2, 6], [8, 10], [15, 18]],), [[1, 6], [8, 10], [15, 18]]),
            (([[1, 4], [4, 5]],), [[1, 5]]),
            (([[1, 4], [2, 3]],), [[1, 4]]),
            (([],), []),
            (([[5, 6], [1, 2], [3, 4]],), [[1, 2], [3, 4], [5, 6]]),
        ],
        "compare": "eq",
    },
    {
        "id": "coin_change_min",
        "prompt": (
            "Write a Python function `solve(coins, amount)` that returns the minimum number "
            "of coins needed to make `amount` from the denominations in `coins` (unlimited "
            "supply). Return -1 if it cannot be made. Return only a fenced python code block."
        ),
        "entry": "solve",
        "tests": [
            (([1, 2, 5], 11), 3),
            (([2], 3), -1),
            (([1], 0), 0),
            (([1, 3, 4], 6), 2),
            (([2, 5, 10, 1], 27), 4),
        ],
        "compare": "eq",
    },
    {
        "id": "basic_calculator",
        "prompt": (
            "Write a Python function `solve(expr)` that evaluates a string arithmetic "
            "expression with non-negative integers and + - * / and parentheses, using normal "
            "precedence. Division is integer floor division. No eval(); parse it yourself. "
            "Return only a fenced python code block."
        ),
        "entry": "solve",
        "tests": [
            (("1 + 1",), 2),
            (("2*(3+4)",), 14),
            (("10 / 3",), 3),
            (("(1+2)*(3+4)",), 21),
            (("2*3+4*5",), 26),
            (("100",), 100),
        ],
        "compare": "eq",
    },
]

CREATIVE_WRITING_TASKS = [
    {
        "id": "six_word_story",
        "prompt": (
            "Write a complete story in EXACTLY six words. It must imply loss. "
            "Return only the six words, nothing else."
        ),
        "min_words": 6,
        "max_words": 6,
        "min_sentences": 1,
    },
    {
        "id": "constrained_scene",
        "prompt": (
            "Write a tense 5-sentence scene set in an elevator between two strangers. "
            "Do NOT use the words 'fear', 'nervous', or 'silence'. Include the word 'button'. "
            "Return only the scene."
        ),
        "min_words": 60,
        "max_words": 160,
        "forbidden": ["fear", "nervous", "silence"],
        "required": ["button"],
        "min_sentences": 5,
    },
    {
        "id": "acrostic_code",
        "prompt": (
            "Write a four-line poem where the first letters of the lines spell C-O-D-E "
            "(line 1 starts with C, line 2 with O, line 3 with D, line 4 with E). "
            "Return only the four lines, one per line."
        ),
        "min_words": 8,
        "max_words": 80,
        "min_lines": 4,
        "acrostic": "CODE",
    },
    {
        "id": "explain_to_child",
        "prompt": (
            "Explain what a hash map is to a 6-year-old in 3 to 4 sentences, using one "
            "everyday analogy and no jargon (no 'key', 'value', 'bucket', 'hash'). "
            "Return only the explanation."
        ),
        "min_words": 40,
        "max_words": 130,
        "forbidden": ["key", "value", "bucket", "hash"],
        "min_sentences": 3,
    },
    {
        "id": "dialogue_subtext",
        "prompt": (
            "Write a 6-line dialogue (3 exchanges) between a parent and teenager where they "
            "argue about curfew but neither says the words 'curfew', 'home', or 'time'. "
            "One line per speaker turn. Return only the dialogue lines."
        ),
        "min_words": 40,
        "max_words": 160,
        "forbidden": ["curfew", "home", "time"],
        "min_lines": 6,
    },
]


def all_tasks():
    return CODING_TASKS, CREATIVE_WRITING_TASKS
