"""tasks.py — the fixed, shared task set for the harness alpha cycle.

Two categories, chosen to exercise the two use cases we care about:

  CODING          — scored objectively by EXECUTING the model's output against unit tests.
  CREATIVE_WRITING — scored on measurable properties (length, structure, constraint
                     adherence) AND saved verbatim so a human judges actual quality.

Keep this list stable across candidates: every harness must see the exact same prompts so
the comparison is fair. Deterministic/greedy decoding is used by the driver.
"""

# Each coding task: a prompt, the entry-point function name, and hidden tests.
# The scorer executes the generated function against these (see score.py).
CODING_TASKS = [
    {
        "id": "two_sum",
        "prompt": (
            "Write a Python function `solve(nums, target)` that returns a list of the two "
            "indices (0-based) of the two numbers in `nums` that add up to `target`. "
            "Assume exactly one solution exists. Return only a fenced python code block."
        ),
        "entry": "solve",
        "tests": [
            (([2, 7, 11, 15], 9), [0, 1]),
            (([3, 2, 4], 6), [1, 2]),
            (([3, 3], 6), [0, 1]),
        ],
        # some tasks have order-insensitive answers; mark them
        "compare": "as_set",
    },
    {
        "id": "group_anagrams_count",
        "prompt": (
            "Write a Python function `solve(words)` that returns the number of distinct "
            "groups of anagrams in the list `words`. Two words are anagrams if one is a "
            "permutation of the other. Return only a fenced python code block."
        ),
        "entry": "solve",
        "tests": [
            ((["eat", "tea", "tan", "ate", "nat", "bat"],), 3),
            (([],), 0),
            ((["abc"],), 1),
            ((["a", "a", "a"],), 1),
        ],
        "compare": "eq",
    },
    {
        "id": "valid_parentheses",
        "prompt": (
            "Write a Python function `solve(s)` that returns True if the string `s` of "
            "brackets (){}[] is correctly balanced and nested, else False. "
            "Return only a fenced python code block."
        ),
        "entry": "solve",
        "tests": [
            (("()",), True),
            (("()[]{}",), True),
            (("(]",), False),
            (("([)]",), False),
            (("{[]}",), True),
            (("",), True),
        ],
        "compare": "eq",
    },
    {
        "id": "longest_run",
        "prompt": (
            "Write a Python function `solve(nums)` that returns the length of the longest "
            "run of strictly increasing consecutive elements in the list `nums`. "
            "Return only a fenced python code block."
        ),
        "entry": "solve",
        "tests": [
            (([1, 2, 3, 1, 2],), 3),
            (([5, 4, 3],), 1),
            (([],), 0),
            (([1, 2, 2, 3],), 2),
        ],
        "compare": "eq",
    },
]

# Each writing task: a prompt plus measurable acceptance checks. "quality" is NOT scored
# automatically — the raw text is saved for human review. These checks only catch gross
# failure (too short, ignored a hard constraint, repetition collapse).
CREATIVE_WRITING_TASKS = [
    {
        "id": "microfiction_constraint",
        "prompt": (
            "Write a piece of micro-fiction of exactly three sentences about a lighthouse "
            "keeper who has never seen the sea. Do not use the word 'water'. "
            "Return only the three sentences."
        ),
        "min_words": 25,
        "max_words": 120,
        "forbidden": ["water"],
        "min_sentences": 3,
    },
    {
        "id": "opening_paragraph",
        "prompt": (
            "Write the opening paragraph of a mystery novel set in a rainy coastal town. "
            "Establish mood and introduce one character by name. 4 to 6 sentences. "
            "Return only the paragraph."
        ),
        "min_words": 60,
        "max_words": 200,
        "forbidden": [],
        "min_sentences": 4,
    },
    {
        "id": "rewrite_tone",
        "prompt": (
            "Rewrite this sentence in a warm, encouraging tone, keeping it to one sentence: "
            "'Your code failed every test and the build is broken.' Return only the sentence."
        ),
        "min_words": 6,
        "max_words": 60,
        "forbidden": [],
        "min_sentences": 1,
    },
    {
        "id": "poem_structure",
        "prompt": (
            "Write a four-line poem (a quatrain) about debugging at 3am. "
            "Return only the four lines, one per line."
        ),
        "min_words": 10,
        "max_words": 80,
        "forbidden": [],
        "min_lines": 4,
    },
]


def all_tasks():
    """Return (coding, writing) task lists."""
    return CODING_TASKS, CREATIVE_WRITING_TASKS
