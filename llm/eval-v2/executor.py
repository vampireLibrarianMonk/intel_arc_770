"""executor.py — run model-written code against tests in an isolated subprocess.

Why a subprocess (vs. the in-process exec() in harness-alpha/score.py): a SIGALRM cannot
interrupt a hang inside C code, and in-process exec lets a bad solution exhaust memory or
corrupt the scorer's state. Here every attempt runs in a fresh `python3 -I` in a temp dir,
with a wall-clock timeout and an address-space cap.

Security: this still executes untrusted model output on this machine. The prompts are fixed
and benign; do not point this at adversarial inputs.
"""

import json
import os
import resource
import subprocess  # nosec B404 - intentional, see module docstring
import sys
import tempfile

PRELUDE = '''
def _raises(fn, *args, exc=ValueError):
    try:
        fn(*args)
    except exc:
        return True
    except Exception:
        return False
    return False
'''

HARNESS = r'''
import ast, json, sys
ns = {}
src = open("solution.py").read()
# Run top-level statements one at a time. A crash in a bare expression/print statement (typically
# the model's own example usage) must not mask a correct function; a crash while defining
# functions/classes/imports/assignments is a real failure. SyntaxError is always a failure.
DEFS = (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef, ast.Import, ast.ImportFrom,
        ast.Assign, ast.AnnAssign)
ignored = []
try:
    tree = ast.parse(src, "solution.py")
    for node in tree.body:
        try:
            exec(compile(ast.Module([node], []), "solution.py", "exec"), ns)
        except BaseException as e:
            if isinstance(node, DEFS):
                raise
            ignored.append(f"{type(e).__name__}: {str(e)[:80]}")
except BaseException as e:
    print("\n__RESULT__" + json.dumps({"ok": False, "detail": f"exec_error: {type(e).__name__}: {e}"}))
    sys.exit(0)
exec(PRELUDE, ns)
tests = json.load(open("tests.json"))
for i, t in enumerate(tests):
    try:
        exec(t, ns)
    except BaseException as e:
        print("\n__RESULT__" + json.dumps({"ok": False, "passed_tests": i, "total_tests": len(tests),
              "demo_errors_ignored": ignored,
              "detail": f"test {i} failed: {t.strip()[:160]} -> {type(e).__name__}: {str(e)[:160]}"}))
        sys.exit(0)
print("\n__RESULT__" + json.dumps({"ok": True, "passed_tests": len(tests), "total_tests": len(tests),
      "demo_errors_ignored": ignored, "detail": "all tests passed"}))
'''


def extract_code(text):
    """First ```python fenced block, else first fenced block, else the raw text."""
    if "```" in text:
        parts = text.split("```")
        for p in parts[1::2]:
            s = p.strip()
            if s.startswith("python"):
                return s[len("python"):].strip()
        if len(parts) >= 2:
            body = parts[1]
            return body.split("\n", 1)[1] if body.split("\n", 1)[0].strip().isalpha() else body
    return text


def _limits():
    resource.setrlimit(resource.RLIMIT_AS, (2 * 1024**3, 2 * 1024**3))


def run_tests(model_output, tests, timeout=10):
    """Return dict(ok, detail, passed_tests, total_tests)."""
    code = extract_code(model_output)
    with tempfile.TemporaryDirectory(prefix="evalv2_") as d:
        with open(os.path.join(d, "solution.py"), "w") as f:
            f.write(code)
        with open(os.path.join(d, "tests.json"), "w") as f:
            json.dump(tests, f)
        with open(os.path.join(d, "harness.py"), "w") as f:
            f.write("PRELUDE = " + repr(PRELUDE) + "\n" + HARNESS)
        try:
            p = subprocess.run(  # nosec B603 - fixed argv, no shell
                [sys.executable, "-I", "harness.py"], cwd=d, capture_output=True, text=True,
                timeout=timeout, preexec_fn=_limits, stdin=subprocess.DEVNULL)
        except subprocess.TimeoutExpired:
            return {"ok": False, "detail": f"timeout (>{timeout}s)", "passed_tests": 0,
                    "total_tests": len(tests)}
    marker = p.stdout.rfind("__RESULT__")
    if marker < 0:
        return {"ok": False, "detail": f"crashed rc={p.returncode}: {p.stderr.strip()[-200:]}",
                "passed_tests": 0, "total_tests": len(tests)}
    res = json.loads(p.stdout[marker + len("__RESULT__"):].strip().splitlines()[0])
    res.setdefault("passed_tests", 0)
    res.setdefault("total_tests", len(tests))
    return res
