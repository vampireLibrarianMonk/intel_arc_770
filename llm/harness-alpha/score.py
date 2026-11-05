"""score.py — scorers for the harness alpha cycle.

Coding: extract the function, EXECUTE it against the task's tests. Pass = all tests match.
Writing: measurable property checks only (length, sentence/line count, forbidden words).
         Actual quality is a human call; the driver saves the raw text for that.

Security note: the coding scorer runs model-generated code via exec(). The tasks are tiny
and self-contained. Do NOT point this at untrusted/adversarial prompts. Same caveat as the
existing llm/ harness.
"""

import contextlib
import io
import re
import signal


class _Timeout(Exception):
    pass


@contextlib.contextmanager
def _time_limit(seconds):
    """Abort the wrapped block if it runs longer than `seconds` (SIGALRM, main thread only).

    The hard task set occasionally elicits model code with an infinite loop; without this,
    exec()/the test call would hang the whole benchmark (observed: a single task stalling the
    client for 14 min). SIGALRM only fires on the main thread — the benchmark runs scoring
    inline there, so this is sufficient. Falls back to a no-op if alarms are unavailable.
    """
    if not hasattr(signal, "SIGALRM"):
        yield
        return

    def _handler(signum, frame):
        raise _Timeout(f"execution exceeded {seconds}s")

    old = signal.signal(signal.SIGALRM, _handler)
    signal.setitimer(signal.ITIMER_REAL, seconds)
    try:
        yield
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, old)


def extract_code(text):
    """Pull a fenced python block if present, else the raw text."""
    if "```" in text:
        parts = text.split("```")
        for p in parts:
            s = p.strip()
            if s.startswith("python"):
                return s[len("python") :].strip()
        if len(parts) >= 2:
            return parts[1].strip()
    return text


def _compare(got, want, mode):
    if mode == "as_set":
        try:
            return set(got) == set(want)
        except TypeError:
            return got == want
    return got == want


def score_coding(output, task, exec_timeout=5):
    """Execute the generated function against the task tests. Returns (passed, detail).

    Each stage (defining the code, and every test call) is bounded by `exec_timeout` seconds
    so model output containing an infinite loop fails as a timeout instead of hanging the run.
    """
    code = extract_code(output)
    ns = {}
    try:
        with contextlib.redirect_stdout(io.StringIO()), _time_limit(exec_timeout):
            exec(code, ns)  # nosec B102 - intentional; see module docstring
    except _Timeout as e:
        return False, f"timeout_defining_code: {e}"
    except Exception as e:  # noqa: BLE001
        return False, f"exec_error: {type(e).__name__}: {e}"
    fn = ns.get(task["entry"])
    if not callable(fn):
        return False, f"no function named {task['entry']}"
    mode = task.get("compare", "eq")
    for args, want in task["tests"]:
        try:
            with _time_limit(exec_timeout):
                got = fn(*args)
        except _Timeout:
            return False, f"timeout (>{exec_timeout}s) on {args!r} — likely infinite loop"
        except Exception as e:  # noqa: BLE001
            return False, f"call_error on {args!r}: {type(e).__name__}: {e}"
        if not _compare(got, want, mode):
            return False, f"wrong: {task['entry']}{args!r} -> {got!r}, want {want!r}"
    return True, "all tests passed"


def _count_sentences(text):
    return len([s for s in re.split(r"[.!?]+", text) if s.strip()])


def score_writing(output, task):
    """Measurable property checks. Returns (passed, detail dict). Quality is human-judged."""
    text = output.strip()
    words = len(text.split())
    sentences = _count_sentences(text)
    lines = len([ln for ln in text.splitlines() if ln.strip()])
    detail = {"words": words, "sentences": sentences, "lines": lines, "checks": []}
    ok = True

    def check(name, cond):
        nonlocal ok
        detail["checks"].append({"name": name, "pass": bool(cond)})
        if not cond:
            ok = False

    check("min_words", words >= task.get("min_words", 0))
    if "max_words" in task:
        check("max_words", words <= task["max_words"])
    if "min_sentences" in task:
        check("min_sentences", sentences >= task["min_sentences"])
    if "min_lines" in task:
        check("min_lines", lines >= task["min_lines"])
    for w in task.get("forbidden", []):
        check(f"forbidden:{w}", w.lower() not in text.lower())
    for w in task.get("required", []):
        check(f"required:{w}", w.lower() in text.lower())
    # acrostic: first letters of the non-empty lines must spell the target (case-insensitive)
    if "acrostic" in task:
        target = task["acrostic"].upper()
        line_firsts = [ln.strip()[0].upper() for ln in text.splitlines() if ln.strip()]
        got = "".join(line_firsts[: len(target)])
        check(f"acrostic:{target}", got == target)
    # crude repetition-collapse guard: no single token should be >35% of the output
    toks = [t for t in re.findall(r"\w+", text.lower()) if t]
    if toks:
        top = max(toks.count(t) for t in set(toks))
        check("no_repetition_collapse", top / len(toks) < 0.35)

    return ok, detail
