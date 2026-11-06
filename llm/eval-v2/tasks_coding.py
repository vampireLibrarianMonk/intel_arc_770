"""tasks_coding.py — eval-v2 coding tasks (15): executed against hidden tests.

Five are the harness-alpha hard tasks (kept for continuity, tests converted to asserts).
Ten are new and cover what real coding help looks like beyond algorithm puzzles: fixing bugs
in given code, implementing a class, strict input parsing with error handling, graphs, and
edge-case-heavy utilities.

Every NEW task carries a `reference` solution, and `python3 tasks_coding.py --selftest`
proves its tests pass on it, so a failure means the model got it wrong rather than the test.
Test strings run in the solution's namespace; `_raises(fn, *args)` is available (ValueError).
"""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "harness-alpha"))
from tasks_hard import CODING_TASKS as _HARD  # noqa: E402

TAIL = " Return only a fenced python code block."


def _from_hard(t):
    return {
        "id": t["id"], "category": "algorithm", "prompt": t["prompt"],
        "tests": [f"assert {t['entry']}(*{args!r}) == {want!r}" for args, want in t["tests"]],
    }


NEW_TASKS = [
    {
        "id": "fix_binary_search", "category": "bugfix",
        "prompt": (
            "This function should return the index of `target` in the sorted list `xs`, or -1 "
            "if it is absent. It has bugs. Return a corrected version, keeping the name `find`."
            "\n```python\ndef find(xs, target):\n    lo, hi = 0, len(xs)\n    while lo < hi:\n"
            "        mid = (lo + hi) // 2\n        if xs[mid] < target:\n            lo = mid\n"
            "        elif xs[mid] > target:\n            hi = mid - 1\n        else:\n"
            "            return mid\n    return -1\n```" + TAIL),
        "tests": [
            "assert find([], 1) == -1", "assert find([1], 1) == 0",
            "assert find([1, 3, 5, 7, 9], 9) == 4", "assert find([1, 3, 5, 7, 9], 1) == 0",
            "assert find([1, 3, 5, 7, 9], 4) == -1", "assert find([1, 2], 3) == -1",
            "assert all(find(list(range(0, 100, 2)), x) == x // 2 for x in range(0, 100, 2))",
            "assert all(find(list(range(0, 100, 2)), x) == -1 for x in range(1, 100, 2))",
        ],
        "reference": (
            "def find(xs, target):\n    lo, hi = 0, len(xs)\n    while lo < hi:\n"
            "        mid = (lo + hi) // 2\n        if xs[mid] < target:\n            lo = mid + 1\n"
            "        elif xs[mid] > target:\n            hi = mid\n        else:\n"
            "            return mid\n    return -1\n"),
    },
    {
        "id": "fix_mutable_default", "category": "bugfix",
        "prompt": (
            "This function has a bug: calling `add_tag('a')` and then `add_tag('b')` returns "
            "['a', 'b'] the second time instead of ['b']. Fix it. It must also never modify a "
            "list passed in by the caller; it returns a new list with the tag appended."
            "\n```python\ndef add_tag(tag, tags=[]):\n    tags.append(tag)\n    return tags\n```"
            + TAIL),
        "tests": [
            "assert add_tag('a') == ['a']", "assert add_tag('b') == ['b']",
            "l = ['x']\nr = add_tag('c', l)\nassert r == ['x', 'c'] and l == ['x']",
            "assert add_tag('z', []) == ['z']",
        ],
        "reference": (
            "def add_tag(tag, tags=None):\n    out = list(tags) if tags is not None else []\n"
            "    out.append(tag)\n    return out\n"),
    },
    {
        "id": "lru_cache_class", "category": "class",
        "prompt": (
            "Implement a class `LRUCache` with `__init__(self, capacity)`, `get(self, key)` "
            "(returns the value, or -1 if missing) and `put(self, key, value)`. When inserting "
            "would exceed capacity, evict the least recently used key. Both `get` (on a hit) "
            "and `put` count as a use. `put` on an existing key updates its value. Each "
            "operation should be O(1)." + TAIL),
        "tests": [
            "c = LRUCache(2); c.put(1, 1); c.put(2, 2)\nassert c.get(1) == 1\nc.put(3, 3)\n"
            "assert c.get(2) == -1\nc.put(4, 4)\nassert c.get(1) == -1\nassert c.get(3) == 3\n"
            "assert c.get(4) == 4",
            "c = LRUCache(1); c.put(1, 1); c.put(1, 5)\nassert c.get(1) == 5",
            "c = LRUCache(2); c.put(1, 1); c.put(2, 2); c.put(1, 10); c.put(3, 3)\n"
            "assert c.get(2) == -1 and c.get(1) == 10 and c.get(3) == 3",
            "c = LRUCache(2)\nassert c.get(7) == -1",
        ],
        "reference": (
            "from collections import OrderedDict\nclass LRUCache:\n"
            "    def __init__(self, capacity):\n        self.cap = capacity\n        self.d = OrderedDict()\n"
            "    def get(self, key):\n        if key not in self.d:\n            return -1\n"
            "        self.d.move_to_end(key)\n        return self.d[key]\n"
            "    def put(self, key, value):\n        if key in self.d:\n            self.d.move_to_end(key)\n"
            "        self.d[key] = value\n        if len(self.d) > self.cap:\n"
            "            self.d.popitem(last=False)\n"),
    },
    {
        "id": "parse_duration", "category": "parsing",
        "prompt": (
            "Write `parse_duration(s)` that converts strings like '1h30m', '45s', '2h5s' or "
            "'1d2h' into a total number of seconds (int). Units are d, h, m, s; each unit may "
            "appear at most once and only in the order d, h, m, s; no whitespace is allowed. "
            "Raise ValueError for an empty string, unknown units, a unit without a number, a "
            "number without a unit, units out of order, or repeated units." + TAIL),
        "tests": [
            "assert parse_duration('1h30m') == 5400", "assert parse_duration('45s') == 45",
            "assert parse_duration('2h5s') == 7205", "assert parse_duration('1d2h') == 93600",
            "assert parse_duration('0s') == 0", "assert parse_duration('10m') == 600",
            "assert _raises(parse_duration, '')", "assert _raises(parse_duration, '1x')",
            "assert _raises(parse_duration, 'h')", "assert _raises(parse_duration, '1m1h')",
            "assert _raises(parse_duration, '1h1h')", "assert _raises(parse_duration, '1h 30m')",
            "assert _raises(parse_duration, '10')",
        ],
        "reference": (
            "import re\ndef parse_duration(s):\n"
            "    m = re.fullmatch(r'(?:(\\d+)d)?(?:(\\d+)h)?(?:(\\d+)m)?(?:(\\d+)s)?', s)\n"
            "    if not s or not m:\n        raise ValueError(s)\n"
            "    d, h, mi, se = (int(x) if x else 0 for x in m.groups())\n"
            "    return d * 86400 + h * 3600 + mi * 60 + se\n"),
    },
    {
        "id": "topo_sort", "category": "graph",
        "prompt": (
            "Write `topo_sort(deps)` where `deps` maps each task name to a list of task names "
            "it depends on (which must come before it). Return a list containing every task, "
            "including names that only appear as dependencies, with dependencies first. When "
            "several tasks are ready at the same time, take the alphabetically smallest first. "
            "Raise ValueError if there is a cycle." + TAIL),
        "tests": [
            "assert topo_sort({'b': ['a'], 'c': ['b']}) == ['a', 'b', 'c']",
            "assert topo_sort({}) == []",
            "assert topo_sort({'x': [], 'a': []}) == ['a', 'x']",
            "assert topo_sort({'d': ['b', 'c'], 'b': ['a'], 'c': ['a']}) == ['a', 'b', 'c', 'd']",
            "assert topo_sort({'z': ['y'], 'b': []}) == ['b', 'y', 'z']",
            "assert _raises(topo_sort, {'a': ['b'], 'b': ['a']})",
            "assert _raises(topo_sort, {'a': ['a']})",
        ],
        "reference": (
            "import heapq\ndef topo_sort(deps):\n    nodes = set(deps)\n"
            "    for v in deps.values():\n        nodes.update(v)\n"
            "    indeg = {n: 0 for n in nodes}\n    out = {n: [] for n in nodes}\n"
            "    for n, ds in deps.items():\n        for d in ds:\n"
            "            out[d].append(n)\n            indeg[n] += 1\n"
            "    ready = [n for n in nodes if indeg[n] == 0]\n    heapq.heapify(ready)\n    res = []\n"
            "    while ready:\n        n = heapq.heappop(ready)\n        res.append(n)\n"
            "        for m in out[n]:\n            indeg[m] -= 1\n"
            "            if indeg[m] == 0:\n                heapq.heappush(ready, m)\n"
            "    if len(res) != len(nodes):\n        raise ValueError('cycle')\n    return res\n"),
    },
    {
        "id": "split_quoted_csv", "category": "parsing",
        "prompt": (
            "Write `split_fields(line)` that splits one CSV line on commas while honouring "
            "double-quoted fields: commas inside quotes do not split, a doubled quote (\"\") "
            "inside a quoted field is a literal quote, and the surrounding quotes are removed. "
            "An empty line returns ['']. Do not use the csv module." + TAIL),
        "tests": [
            "assert split_fields('a,b,c') == ['a', 'b', 'c']",
            "assert split_fields('\"a,b\",c') == ['a,b', 'c']",
            "assert split_fields('\"say \"\"hi\"\"\",x') == ['say \"hi\"', 'x']",
            "assert split_fields('') == ['']", "assert split_fields('a,,b') == ['a', '', 'b']",
            "assert split_fields('a,') == ['a', '']", "assert split_fields('\"\",z') == ['', 'z']",
        ],
        "reference": (
            "def split_fields(line):\n    out, cur, q, i = [], [], False, 0\n"
            "    while i < len(line):\n        ch = line[i]\n        if q:\n"
            "            if ch == '\"':\n                if i + 1 < len(line) and line[i + 1] == '\"':\n"
            "                    cur.append('\"'); i += 1\n                else:\n                    q = False\n"
            "            else:\n                cur.append(ch)\n"
            "        elif ch == '\"':\n            q = True\n"
            "        elif ch == ',':\n            out.append(''.join(cur)); cur = []\n"
            "        else:\n            cur.append(ch)\n        i += 1\n"
            "    out.append(''.join(cur))\n    return out\n"),
    },
    {
        "id": "word_wrap", "category": "utility",
        "prompt": (
            "Write `wrap(text, width)` that greedily packs whitespace-separated words into lines "
            "of at most `width` characters, joining words on a line with single spaces, and "
            "returns the list of lines. A word longer than `width` goes on its own line, "
            "unbroken. Empty or whitespace-only text returns []." + TAIL),
        "tests": [
            "assert wrap('the quick brown fox', 10) == ['the quick', 'brown fox']",
            "assert wrap('', 5) == []", "assert wrap('   ', 5) == []",
            "assert wrap('a b c', 1) == ['a', 'b', 'c']",
            "assert wrap('supercalifragilistic is long', 5) == ['supercalifragilistic', 'is', 'long']",
            "assert wrap('one two', 7) == ['one two']",
            "assert wrap('aa bb cc dd', 5) == ['aa bb', 'cc dd']",
            "assert wrap('  spaced   out\\nwords ', 9) == ['spaced', 'out words']",
        ],
        "reference": (
            "def wrap(text, width):\n    lines, cur = [], ''\n    for w in text.split():\n"
            "        if not cur:\n            cur = w\n        elif len(cur) + 1 + len(w) <= width:\n"
            "            cur += ' ' + w\n        else:\n            lines.append(cur); cur = w\n"
            "    if cur:\n        lines.append(cur)\n    return lines\n"),
    },
    {
        "id": "flatten_dict", "category": "utility",
        "prompt": (
            "Write `flatten(d)` that flattens nested dicts into one dict with dot-joined keys, "
            "e.g. {'a': {'b': 1}} -> {'a.b': 1}. Non-dict values (including lists, even lists "
            "containing dicts) are kept as-is. Empty nested dicts produce no keys. All keys "
            "are strings." + TAIL),
        "tests": [
            "assert flatten({'a': {'b': 1, 'c': {'d': 2}}, 'e': 3}) == {'a.b': 1, 'a.c.d': 2, 'e': 3}",
            "assert flatten({}) == {}", "assert flatten({'a': {}}) == {}",
            "assert flatten({'a': [1, {'b': 2}]}) == {'a': [1, {'b': 2}]}",
            "assert flatten({'x': {'y': {'z': None}}}) == {'x.y.z': None}",
        ],
        "reference": (
            "def flatten(d, prefix=''):\n    out = {}\n    for k, v in d.items():\n"
            "        key = prefix + k\n        if isinstance(v, dict):\n"
            "            out.update(flatten(v, key + '.'))\n        else:\n            out[key] = v\n"
            "    return out\n"),
    },
    {
        "id": "dijkstra_path", "category": "graph",
        "prompt": (
            "Write `shortest(graph, start, goal)` where `graph` maps a node to a list of "
            "(neighbor, weight) pairs with non-negative weights (edges are directed; a node may "
            "appear only as a neighbor). Return (distance, path) for the cheapest path, with "
            "path as a list of nodes from start to goal. Return (None, []) if the goal is "
            "unreachable, and (0, [start]) when start == goal." + TAIL),
        "tests": [
            "g = {'a': [('b', 1), ('c', 4)], 'b': [('c', 1), ('d', 5)], 'c': [('d', 1)], 'd': []}\n"
            "assert shortest(g, 'a', 'd') == (3, ['a', 'b', 'c', 'd'])\n"
            "assert shortest(g, 'd', 'a') == (None, [])\nassert shortest(g, 'a', 'a') == (0, ['a'])",
            "assert shortest({'a': [('b', 2)]}, 'a', 'b') == (2, ['a', 'b'])",
            "assert shortest({'a': [('b', 0)], 'b': [('c', 0)]}, 'a', 'c') == (0, ['a', 'b', 'c'])",
            "assert shortest({'a': [('b', 10), ('c', 1)], 'c': [('b', 2)]}, 'a', 'b') == (3, ['a', 'c', 'b'])",
        ],
        "reference": (
            "import heapq\ndef shortest(graph, start, goal):\n    dist = {start: 0}\n    prev = {}\n"
            "    pq = [(0, start)]\n    while pq:\n        d, n = heapq.heappop(pq)\n"
            "        if n == goal:\n            path = [n]\n            while n in prev:\n"
            "                n = prev[n]; path.append(n)\n            return d, path[::-1]\n"
            "        if d > dist.get(n, float('inf')):\n            continue\n"
            "        for m, w in graph.get(n, []):\n            nd = d + w\n"
            "            if nd < dist.get(m, float('inf')):\n                dist[m] = nd; prev[m] = n\n"
            "                heapq.heappush(pq, (nd, m))\n    return None, []\n"),
    },
    {
        "id": "spiral_matrix", "category": "algorithm",
        "prompt": (
            "Write `spiral(matrix)` that returns the elements of a 2-D list in clockwise spiral "
            "order starting at the top-left. Handle empty and non-square matrices." + TAIL),
        "tests": [
            "assert spiral([[1, 2, 3], [4, 5, 6], [7, 8, 9]]) == [1, 2, 3, 6, 9, 8, 7, 4, 5]",
            "assert spiral([]) == []", "assert spiral([[]]) == []",
            "assert spiral([[1, 2, 3, 4]]) == [1, 2, 3, 4]",
            "assert spiral([[1], [2], [3]]) == [1, 2, 3]",
            "assert spiral([[1, 2], [3, 4], [5, 6]]) == [1, 2, 4, 6, 5, 3]",
        ],
        "reference": (
            "def spiral(matrix):\n    m = [list(r) for r in matrix if r]\n    out = []\n"
            "    while m:\n        out += m.pop(0)\n        m = [list(r) for r in zip(*m)][::-1]\n"
            "    return out\n"),
    },
]

CODING_TASKS = [_from_hard(t) for t in _HARD] + NEW_TASKS


def _selftest():
    from executor import run_tests
    bad = 0
    for t in NEW_TASKS:
        r = run_tests("```python\n" + t["reference"] + "\n```", t["tests"])
        print(("PASS " if r["ok"] else "FAIL ") + t["id"], "" if r["ok"] else r["detail"])
        bad += not r["ok"]
    print(f"{len(CODING_TASKS)} tasks total; references failing: {bad}")
    return bad


if __name__ == "__main__" and "--selftest" in sys.argv:
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    raise SystemExit(1 if _selftest() else 0)
