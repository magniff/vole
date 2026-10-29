#!/usr/bin/env python3
"""Agent harness hook (0.17): a check at the end of the agent's turn (a
Claude Code Stop hook), so that a turn does not end on vole source
nobody checked: a file written by a shell command (`cat > main.vl`, a
Python script), or an edit after which errors were left
(docs/research/applying-to-vole.md, item 4: checks once at turn exit).

Registered in .claude/settings.json for Stop, and by the agent eval
(tools/agent-hooks/settings-eval.json). Reads the hook event (JSON) on
stdin. For each program root this session touched (the check hook's
state, hookstate.py) and the one of the event's directory (its
compiler/src/main.vl, else its main.vl):

- nothing when its sources (fingerprint: the .vl files and tests'
  names, sizes and times) are as they were at the last check in this
  session and that check was clean (and its tests, when it has fast ones,
  ran on those sources); nothing when a root never checked has no .vl
  file changed since the session began;
- else `volec check` once (and its fast tests, check-after-edit.py's
  verify), and when there are errors or failing tests the stop is blocked
  once with them as the reason (`{"decision": "block", "reason": ...}`):
  the agent sees `turn-end: unchecked changes in main.vl: 2 errors`
  and the errors; never twice for the same sources (the state records
  the fingerprint it reported on).

(0.25.2) Then the examples' own checks, for the example programs of the
checkout (examples/.../main.vl) this session changed: uncommitted changes
(git status) or ones committed since the session began (git log). The
examples that landed broken were caught by the suite only after the
commit; these are the parts of it that concern the changed examples:

- `volec fmt --check` of each changed .vl file;
- a tests/examples case whose SOURCE is the example's main.vl, and no case
  naming a SOURCE or CSOURCE that does not exist (a moved example);
- the example's cases, `tests/run.sh example_NAME` (the slow part: once
  per state of the changed files, like the rest).

Reported like errors, once per state. VOLE_TURN_END_EXAMPLES=0 turns
these off, =quick keeps all but running the cases.

VOLE_TURN_END=0 turns it off; VOLE_CHECK_TESTS=0 leaves the tests
out. Logged as `turn-end` records where the check hook logs. Development
tooling only.
"""
import json
import os
import sys
import time
import types

HERE = os.path.dirname(os.path.abspath(__file__))


def _load(name, file):
    mod = types.ModuleType(name)
    mod.__file__ = os.path.join(HERE, file)
    with open(mod.__file__) as fh:
        exec(compile(fh.read(), mod.__file__, "exec"), mod.__dict__)
    return mod


cae = _load("check_after_edit", "check-after-edit.py")


def candidates(event, st):
    """The roots to look at: the session's, then the event directory's."""
    roots = []
    for key, entry in (st.get("roots") or {}).items():
        r = entry.get("root")
        if r and os.path.exists(r) and r not in roots:
            roots.append(r)
    cwd = os.path.abspath(event.get("cwd") or os.getcwd())
    r = cae.default_root(cwd)
    if r and r not in roots:
        roots.append(r)
    return roots


def expects_errors(root):
    """A test case that is meant to fail to compile (`// ERROR:` or
    `// ERROR-COUNT:` directives, under a tests/ directory): its errors are
    the test, not unchecked changes."""
    if os.sep + "tests" + os.sep not in root:
        return False
    try:
        with open(root) as fh:
            head = fh.read(4096)
    except OSError:
        return False
    return "// ERROR" in head


def needs_check(event, st, root, start):
    """Whether root's sources changed since the last clean check (and test
    run) of this session, and the turn-end hook has not reported on them."""
    entry = (st.get("roots") or {}).get(root)
    fp, newest = cae.hs.fingerprint(root)
    if (st.get("turn_end") or {}).get(root) == fp:
        return False, fp
    if entry is None:
        # (never checked in this session: changed since it began?)
        return (start is None or newest > start), fp
    clean = not entry.get("errors")
    tested = not cae.hs.has_tests(root) or entry.get("slow") or \
        os.environ.get("VOLE_CHECK_TESTS", "1") == "0" or \
        (entry.get("tests") or {}).get("fp") == fp
    return not (entry.get("fp") == fp and clean and tested), fp


EXAMPLE_TIMEOUT = 300
EXAMPLE_LINES = 25


def git_paths(top, args):
    """The paths a git command lists (NUL separated), relative to top."""
    import subprocess
    try:
        r = subprocess.run(["git", "-C", top] + args, capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.TimeoutExpired):
        return []
    if r.returncode != 0:
        return []
    return [p for p in r.stdout.split("\0") if p.strip()]


def changed_example_paths(top, start):
    """The paths under examples/ and tests/examples/ changed in this session:
    uncommitted (git status, both sides of a rename), or committed since
    the session began."""
    paths = set()
    for entry in git_paths(top, ["status", "--porcelain=v1", "-z", "--untracked-files=all", "--",
                                 "examples", "tests/examples"]):
        # `XY path`, and after a rename's entry its old path alone
        paths.add(entry[3:] if len(entry) > 3 and entry[2] == " " else entry)
    if start:
        for p in git_paths(top, ["log", "-z", f"--since=@{int(start)}", "--name-only", "--format=", "--",
                                 "examples", "tests/examples"]):
            paths.add(p.strip("\n"))
    return sorted(p for p in paths if p)


def example_root(top, rel):
    """The example program (the folder of the nearest main.vl, under
    examples/, not examples/tools/) a changed path belongs to, relative to
    top; None outside one."""
    if not rel.startswith("examples/") or rel.startswith("examples/tools/"):
        return None
    d = os.path.dirname(rel)
    while d.startswith("examples/"):
        if os.path.exists(os.path.join(top, d, "main.vl")):
            return d
        d = os.path.dirname(d)
    return None


def example_cases(top):
    """{source path: [case names]} and the problems of tests/examples: each
    SOURCE or CSOURCE that does not exist."""
    cases, missing = {}, []
    d = os.path.join(top, "tests", "examples")
    try:
        names = sorted(os.listdir(d))
    except OSError:
        return cases, missing
    for n in names:
        if not n.endswith(".test"):
            continue
        try:
            with open(os.path.join(d, n), errors="replace") as fh:
                lines = fh.read(8192).splitlines()
        except OSError:
            continue
        for line in lines:
            for key in ("// SOURCE:", "// CSOURCE:"):
                if line.startswith(key):
                    p = line[len(key):].strip()
                    if key == "// SOURCE:":
                        cases.setdefault(p, []).append(n[:-len(".test")])
                    if p and not os.path.exists(os.path.join(top, p)):
                        missing.append(f"tests/examples/{n} names {p}, which does not exist "
                                       f"(moved? update its {key[3:-1]} line)")
    return cases, missing


def example_checks(event, st, top, start):
    """The examples' checks (the docstring above) for checkout top; the
    report, or None."""
    import subprocess
    mode = os.environ.get("VOLE_TURN_END_EXAMPLES", "1")
    if mode == "0" or not os.path.isdir(os.path.join(top, "tests", "examples")):
        return None
    changed = changed_example_paths(top, start)
    if not changed:
        return None
    parts = []
    for rel in changed:
        try:
            s_ = os.stat(os.path.join(top, rel))
            parts.append(f"{rel}:{s_.st_mtime_ns}:{s_.st_size}")
        except OSError:
            parts.append(f"{rel}:gone")
    fp = cae.hs.digest(parts + [mode])
    seen = st.setdefault("turn_end_examples", {})
    if seen.get(top) == fp:
        return None
    seen[top] = fp
    cases, problems = example_cases(top)
    roots = sorted({r for r in (example_root(top, rel) for rel in changed) if r})
    compiler = cae.compiler_for(top, root=os.path.join(top, roots[0], "main.vl")) if roots else None
    t0 = time.time()
    for root in roots:
        if compiler:
            for rel in changed:
                if rel.endswith(".vl") and example_root(top, rel) == root and os.path.exists(os.path.join(top, rel)):
                    r = cae.run_typed(compiler, top, ["fmt", "--check", rel])
                    if r is not None and r.returncode != 0:
                        problems.append(f"{rel} is not formatted; try: volec fmt {rel}")
        names = cases.get(f"{root}/main.vl", [])
        if not names:
            problems.append(f"{root}: no tests/examples/*.test has '// SOURCE: {root}/main.vl'")
            continue
        if mode == "quick" or not compiler or not os.path.exists(os.path.join(top, "tests", "run.sh")):
            continue
        for base in sorted({n.split("_")[0] for n in names}):
            try:
                r = subprocess.run(["sh", os.path.join(top, "tests", "run.sh"), "-c", compiler, f"example_{base}"],
                                   cwd=top, capture_output=True, text=True, timeout=EXAMPLE_TIMEOUT)
            except (OSError, subprocess.TimeoutExpired):
                problems.append(f"tests/run.sh example_{base}: did not finish in {EXAMPLE_TIMEOUT} s")
                continue
            if r.returncode != 0:
                out = []
                for line in r.stdout.splitlines():
                    if line.startswith("tests for "):
                        break
                    if line.strip():
                        out.append(line)
                problems.append(f"tests/run.sh example_{base} fails:\n" + "\n".join(out[:EXAMPLE_LINES]))
    cae.record(event, top, {"kind": "turn-end-examples", "examples": roots, "problems": len(problems),
                            "ms": int((time.time() - t0) * 1000)})
    if not problems:
        return None
    return (f"turn-end: changed examples ({', '.join(roots) or 'tests/examples'}): "
            f"{len(problems)} problem{'s' if len(problems) != 1 else ''} the suite would report\n"
            + "\n".join(problems))


def main():
    if os.environ.get("VOLE_TURN_END") == "0" or os.environ.get("VOLE_CHECK_HOOK") == "0":
        return 0
    try:
        event = json.load(sys.stdin)
    except ValueError:
        return 0
    if event.get("hook_event_name", "Stop") not in ("Stop", "SubagentStop"):
        return 0
    st = cae.hs.load(event)
    start = cae.hs.session_start(event)
    reports = []
    for root in candidates(event, st):
        if expects_errors(root):
            continue
        need, fp = needs_check(event, st, root, start)
        if not need:
            continue
        cwd = os.path.dirname(root)
        if root.endswith(os.path.join("compiler", "src", "main.vl")):
            cwd = os.path.dirname(os.path.dirname(cwd))
        compiler = cae.compiler_for(cwd)
        if not compiler:
            continue
        # (0.25.4) a tools binary older than the tree's source would report
        # the new release's syntax as errors: target/volec when current,
        # else no check; said once a session (the check hook's state)
        compiler, stale = cae.current_compiler(compiler, cwd, st)
        if not compiler:
            if stale:
                reports.append(f"turn-end: {os.path.basename(root)} not checked\n{stale}")
            continue
        t0 = time.time()
        got = cae.verify(event, st, compiler, root, cwd, None, at_turn_end=True)
        if got is None:
            continue
        text, rec = got
        entry = st["roots"].get(root) or {}
        st.setdefault("turn_end", {})[root] = entry.get("fp") or fp
        failing = (entry.get("tests") or {}).get("failed") if (entry.get("tests") or {}).get("fp") == entry.get("fp") else None
        rec = dict(rec, kind="turn-end", ms=int((time.time() - t0) * 1000))
        cae.record(event, cwd, rec)
        if entry.get("errors") or failing:
            n = len(entry.get("errors") or [])
            what = []
            if n:
                what.append(f"{n} error{'s' if n != 1 else ''}")
            if failing:
                what.append(f"{len(failing)} failing test{'s' if len(failing) != 1 else ''}")
            shown = os.path.relpath(root, os.path.abspath(event.get("cwd") or os.getcwd()))
            if shown.startswith(".."):
                shown = root
            reports.append(f"turn-end: unchecked changes in {shown}: {', '.join(what)}\n"
                           f"{stale + chr(10) if stale else ''}{text}".rstrip())
    tops = []
    for r in candidates(event, st) + [os.path.abspath(event.get("cwd") or os.getcwd())]:
        top = cae.checkout_root(r)
        if top and top not in tops:
            tops.append(top)
    for top in tops:
        rep = example_checks(event, st, top, start)
        if rep:
            reports.append(rep)
    cae.hs.save(event, st)
    if reports:
        json.dump({"decision": "block", "reason": "\n".join(reports)}, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
