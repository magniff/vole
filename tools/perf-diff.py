#!/usr/bin/env python3
"""Two compilers on one input: where the instructions go, and the difference.

usage: tools/perf-diff.sh [OPTIONS] A B FILE.vl...

  A, B       two volec binaries (A the baseline, B the one under test)
  FILE.vl    a program's root; each is compiled by both (an object, to
             /dev/null: no link)

  -O LEVEL   the optimization level of the build (default 2)
  --check    `volec check FILE` instead of a build: the front end's phases
  -n RUNS    each compiler RUNS times; a row is its fewest (default 1:
             instruction counts hardly move with the machine's load)
  --min M    leave out the rows where both are under M million (default 1)
  --all      every row (--min 0)
  --inline   also the inliner's decisions that differ (VOLE_INLINE_LOG of
             both, compared by tools/inline-log-diff.py)
  --json     the tables as one JSON object, not text
  --         the words after it go to both compilers (`-- --no-vectorize`)

For each FILE it runs `COMPILER --no-cache -j1 --time-passes=json -O LEVEL
FILE -c -o /dev/null` (the tools' and the code cache off), reads the
phases and the optimizer's passes of both, and prints a table of each:
the instructions retired in millions by A and by B, the difference and
its percentage; then the totals. A compiler before 0.30 has no
`--time-passes=json`: its `--time-passes=passes` text is read instead
(to 0.1 M). The rows are the compiler's own (docs/optimizer.md, "0.29":
a pass's row is what ran between two marks; `rest of: PHASE` what a phase
did outside its passes).

The counter is the compiler's own: macOS's thread counter
(thread_selfcounts), Linux's perf_event_open (instructions in user mode;
a container may refuse it: `error[time.instructions]`, and this script
stops saying so). A build that counts runs on one thread.

Exit status: 0; 1 when a compiler fails on an input; 2 for a usage error.
"""
import json
import os
import re
import subprocess
import sys
import tempfile


def usage(message=None):
    if message:
        sys.stderr.write("perf-diff: %s\n" % message)
    sys.stderr.write("usage: tools/perf-diff.sh [-O LEVEL] [--check] [-n RUNS] [--min M] [--all] "
                     "[--inline] [--json] A B FILE.vl... [-- COMPILER OPTIONS]\n")
    sys.exit(2)


def parse_text(text):
    """The rows of `--time-passes=instructions|passes` as text: (phases,
    passes, rest), each a list of (name, instructions)."""
    phases, passes, rest = [], [], []
    in_passes = False
    for line in text.splitlines():
        if line.startswith("passes ("):
            in_passes = True
            continue
        m = re.match(r"^([\d.]+) M  (.*)$", line)
        if not m:
            continue
        value, name = int(float(m.group(1)) * 1e6), m.group(2).strip()
        if name.startswith("total (") or "marks themselves" in name or name.startswith("the front end"):
            continue
        if not in_passes:
            phases.append((name, value))
        elif name.startswith("rest of: "):
            rest.append((name[len("rest of: "):], value))
        else:
            passes.append((name, value))
    return phases, passes, rest


def parse_json(obj):
    phases = [(p["name"], p["value"]) for p in obj.get("phases", [])]
    passes = [(p["name"], p["value"]) for p in obj.get("passes", [])]
    rest = [(p["name"], p["value"]) for p in obj.get("rest", [])]
    return phases, passes, rest


def run_once(compiler, args, form, env):
    """One run: (phases, passes, rest) or None with the error printed."""
    cmd = [compiler] + [a.replace("@FORM@", form) for a in args]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, env=env)
    except OSError as e:
        sys.stderr.write("perf-diff: cannot run %s: %s\n" % (compiler, e))
        return None
    err = r.stderr or ""
    if r.returncode != 0:
        if form == "json" and "--time-passes=json" in err:
            return "no-json"
        sys.stderr.write("perf-diff: %s failed (exit %d):\n" % (" ".join(cmd), r.returncode))
        for line in err.splitlines()[:8]:
            sys.stderr.write("    %s\n" % line[:300])
        return None
    if form == "json":
        for line in err.splitlines():
            if line.startswith('{"unit"'):
                obj = json.loads(line)
                if obj.get("unit") != "instructions":
                    sys.stderr.write("perf-diff: %s counted %s, not instructions\n" % (compiler, obj.get("unit")))
                    return None
                return parse_json(obj)
        sys.stderr.write("perf-diff: %s printed no --time-passes=json object\n" % compiler)
        return None
    return parse_text(err)


def measure(compiler, args, runs, env):
    """The fewest of `runs` runs, row by row: (phases, passes, rest) as
    ordered lists, or None."""
    form = "json"
    best = None
    for _ in range(runs):
        got = run_once(compiler, args, form, env)
        if got == "no-json":
            # (a compiler before 0.30: the text form; a check has no
            # `=passes`, only the flag's CPU time)
            form = "passes"
            got = run_once(compiler, args, form, env)
        if got is None or got == "no-json":
            return None
        if best is None:
            best = [list(part) for part in got]
            continue
        for part, new in zip(best, got):
            seen = dict(new)
            for i, (name, value) in enumerate(part):
                if name in seen and seen[name] < value:
                    part[i] = (name, seen[name])
    return best


def table(title, a, b, least):
    """The rows of one table: [(name, a, b)], A's order then B's own."""
    da, db = dict(a), dict(b)
    names = [n for n, _ in a] + [n for n, _ in b if n not in da]
    rows = [(n, da.get(n, 0), db.get(n, 0)) for n in names]
    shown = [r for r in rows if max(r[1], r[2]) >= least * 1e6]
    return {"title": title, "rows": shown, "left_out": len(rows) - len(shown),
            "total": (sum(da.values()), sum(db.values()))}


def put_table(t, out):
    out.append("%-46s %10s %10s %10s %8s" % (t["title"], "A (M)", "B (M)", "B-A (M)", "%"))
    for name, a, b in t["rows"]:
        pct = ("%+7.1f%%" % (100.0 * (b - a) / a)) if a else "     new"
        out.append("  %-44s %10.1f %10.1f %+10.1f %8s" % (name[:44], a / 1e6, b / 1e6, (b - a) / 1e6, pct))
    a, b = t["total"]
    if t["left_out"]:
        out.append("  (%d rows under the --min left out)" % t["left_out"])
    pct = ("%+7.1f%%" % (100.0 * (b - a) / a)) if a else ""
    out.append("  %-44s %10.1f %10.1f %+10.1f %8s" % ("total", a / 1e6, b / 1e6, (b - a) / 1e6, pct))


def inline_diff(a, b, args, env, here):
    """tools/inline-log-diff.py's lines for the two compilers' decisions."""
    out = []
    logs = []
    with tempfile.TemporaryDirectory() as d:
        for k, c in enumerate((a, b)):
            log = os.path.join(d, "inline%d.log" % k)
            e = dict(env)
            e["VOLE_INLINE_LOG"] = log
            cmd = [c] + [x for x in args if not x.startswith("--time-passes")]
            r = subprocess.run(cmd, capture_output=True, text=True, env=e)
            if r.returncode != 0 or not os.path.exists(log):
                return ["  (no inline log from %s: VOLE_INLINE_LOG is 0.29's)" % c]
            logs.append(log)
        r = subprocess.run([sys.executable, os.path.join(here, "inline-log-diff.py")] + logs,
                           capture_output=True, text=True)
        out = [("  " + line) for line in (r.stdout or "").splitlines()[:40]]
    return out or ["  (the same decisions)"]


def main(argv):
    level, check, runs, least, inline, as_json = "2", False, 1, 1.0, False, False
    words, extra = [], []
    i = 0
    while i < len(argv):
        w = argv[i]
        if w == "--":
            extra = argv[i + 1:]
            break
        if w in ("-h", "--help"):
            sys.stdout.write(__doc__)
            return 0
        if w == "-O" and i + 1 < len(argv):
            level = argv[i + 1]
            i += 1
        elif w.startswith("-O") and len(w) == 3:
            level = w[2]
        elif w == "--check":
            check = True
        elif w == "-n" and i + 1 < len(argv):
            runs = int(argv[i + 1])
            i += 1
        elif w == "--min" and i + 1 < len(argv):
            least = float(argv[i + 1])
            i += 1
        elif w == "--all":
            least = 0.0
        elif w == "--inline":
            inline = True
        elif w == "--json":
            as_json = True
        elif w.startswith("-"):
            usage("unknown option '%s'" % w)
        else:
            words.append(w)
        i += 1
    if len(words) < 3:
        usage("two compilers and at least one FILE.vl")
    if level not in ("0", "1", "2") or runs < 1:
        usage("-O 0|1|2, -n RUNS from 1")
    a, b, files = os.path.abspath(words[0]), os.path.abspath(words[1]), words[2:]
    for c in (a, b):
        if not os.access(c, os.X_OK):
            usage("no compiler at %s" % c)
    env = dict(os.environ)
    env["VOLE_CACHE"] = "off"
    env["VOLE_CODE_CACHE"] = "off"
    here = os.path.dirname(os.path.abspath(__file__))
    status = 0
    results = []
    out = []
    for f in files:
        if check:
            args = ["check", "--time-passes=@FORM@", f] + extra
        else:
            args = ["--no-cache", "-j1", "--time-passes=@FORM@", "-O" + level, f, "-c", "-o", os.devnull] + extra
        ma = measure(a, args, runs, env)
        mb = measure(b, args, runs, env)
        if ma is None or mb is None:
            status = 1
            continue
        what = ("check" if check else "-O" + level) + " " + f
        tables = [table("phases: " + what, ma[0], mb[0], least)]
        if ma[1] or mb[1]:
            tables.append(table("passes: " + what, ma[1], mb[1], least))
            tables.append(table("rest of each phase (outside its passes)", ma[2], mb[2], least))
        results.append({"file": f, "tables": tables})
        for t in tables:
            put_table(t, out)
            out.append("")
        if inline and not check:
            out.append("inlining decisions that differ (A, then B):")
            out += inline_diff(a, b, [x.replace("@FORM@", "passes") for x in args], env, here)
            out.append("")
    if as_json:
        json.dump({"a": a, "b": b, "runs": runs, "results": results}, sys.stdout)
        sys.stdout.write("\n")
    else:
        sys.stdout.write("A: %s\nB: %s\n" % (a, b))
        sys.stdout.write("instructions retired, in millions; the fewest of %d run%s\n\n"
                         % (runs, "" if runs == 1 else "s"))
        sys.stdout.write("\n".join(out).rstrip("\n") + "\n")
    return status


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
