#!/usr/bin/env python3
"""Compares two volec binaries' command lines (0.25, the move to std::cli).

usage: tools/cli-compat.py OLD NEW [--only WORD] [-j N] [--show N]

Runs every command line of a corpus with OLD and with NEW, each in a
fresh copy of its program, and compares stdout, stderr and the exit
status (the binaries' paths and the copies' replaced by placeholders).
The corpus:

  - the transcripts, tests/query/*.q and tests/refactor/*.t: each one's
    commands in order, in a copy of its program (as the transcript runs);
  - the command lines of docs/query.md and docs/refactor.md, in a copy of
    tests/query/context;
  - bad inputs (BAD below): typos, missing values, unknown commands.

A difference in a line of `--help` (or `-h`, `help`) is reported apart:
help may change layout. Prints one line per difference and a summary;
exits 1 when anything but help differs.
"""

import os
import re
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Bad inputs, run in a copy of tests/query/context (main.vl, stock.vl).
BAD = """
--bogus main.vl
-O3 main.vl
-O main.vl
-o
main.vl -o
--target
--target foo main.vl
-j
-j x main.vl
-jx main.vl
-C
-C bogus main.vl
-I
-l
-L
-framework
--overlay
--overlay a
--profile-use
--profile-generate main.vl
--linker=ld main.vl
--diagnostics=long main.vl
--atomics=x main.vl
--stats=x main.vl
--cache=maybe main.vl
--emit-ir=1 main.vl
--values=bogus main.vl
--syntax=mixed main.vl
--allow-unsafe main.vl
--version
--version main.vl
--tokens main.vl
nosuch.vl
main.vl --bogus
-x main.vl
-gx main.vl
query
query foo
query refz report
query refs
query refs report --cnt
query refs report --in
query refs report --limit
query refs report --limit x
query refs report --kind
query context report --budget
query context report --budget x
query show
query def report extra
query items --bogus
query grep
query text
query type
query type nosuch.vl:1:1
query --help
query refs --help
edit
edit bogus
edit patch
edit patch report --old
edit patch report --old a
edit patch report --new b
edit patch report --old a --new
edit replace
edit replace report --bogus
edit insert report
edit delete
edit delete report extra
edit wrap
edit wrap report --in
edit new-file
edit apply --bogus
edit --help
edit patch --help
refactor
refactor renam
refactor rename
refactor rename report
refactor move
refactor move report
refactor signature
refactor signature report
refactor signature report --add
refactor field
refactor variant
refactor extract-function
refactor inline
refactor --script
refactor --help
refactor rename --help
rewrite
rewrite a
rewrite --bogus a b
fix --onli x
fix --only bogus
fix --only
fix --in
fix --bogus
fix --suggested --at
check --bogus
check nosuch.vl
check --root
undo --bogus
lint
lint --max-lines
lint --max-lines x
fmt --bogus
fmt
fmt nosuch.vl
guide --bogus
guide nosuchtopic
guide --find
guide --budget
explain
explain nosuch.code
test --bogus
test --budget
test --timeout x
probe
probe main.vl
probe main.vl:1 --max
reduce
reduce main.vl
fuzz
same-output
try
try --file
batch
batch --bogus
lsp --bogus
assemble
help
help query
--help
-h
bogus-command
""".strip().split("\n")


def transcripts():
    """(name, program dir, [command lines]) of each transcript."""
    out = []
    for sub, ext, prefix in (("query", ".q", "query "), ("refactor", ".t", "")):
        d = os.path.join(ROOT, "tests", sub)
        for f in sorted(os.listdir(d)):
            if not f.endswith(ext):
                continue
            prog = os.path.join(d, f[: -len(ext)])
            lines = []
            with open(os.path.join(d, f)) as fh:
                for line in fh:
                    if line.startswith("$ "):
                        lines.append(prefix + line[2:].rstrip("\n"))
            if not os.path.isdir(prog):
                prog = os.path.join(ROOT, "tests", "query", "context")
            out.append((sub + "/" + f, prog, lines))
    return out


def doc_lines():
    lines = []
    for doc in ("docs/query.md", "docs/refactor.md"):
        with open(os.path.join(ROOT, doc)) as fh:
            for line in fh:
                m = re.match(r"^\s*(?:\$ )?volec (\S.*)$", line)
                if m:
                    # the command, without the comment column
                    cmd = re.split(r"\s{3,}", m.group(1).rstrip())[0]
                    # `a|b|c` alternatives: the first (not a shell pipe)
                    if "'" not in cmd and '"' not in cmd:
                        cmd = " ".join(w.split("|")[0] or w for w in cmd.split())
                        cmd = re.sub(r"\s\|\s.*$", "", cmd)
                    lines.append(cmd)
    return lines


def run(binary, prog, lines, timeout):
    """Runs lines in order in a fresh copy of prog: [(stdout, stderr, code)]."""
    work = tempfile.mkdtemp(prefix="clicompat-")
    try:
        dst = os.path.join(work, "p")
        shutil.copytree(prog, dst)
        res = []
        env = dict(os.environ)
        env["VOLE_OK"] = env.get("VOLE_OK", "1")
        for line in lines:
            sh = "exec " + binary + " " + line
            if "<" not in line:
                sh += " </dev/null"
            try:
                p = subprocess.run(["/bin/sh", "-c", sh], cwd=dst, capture_output=True,
                                   timeout=timeout, env=env)
                o = p.stdout.decode("utf-8", "replace")
                e = p.stderr.decode("utf-8", "replace")
                code = p.returncode
            except subprocess.TimeoutExpired:
                o, e, code = "", "", "timeout"
            norm = lambda s: s.replace(binary, "VOLEC").replace(work, "WORK").replace(
                os.path.realpath(work), "WORK")
            res.append((norm(o), norm(e), code))
        return res
    finally:
        shutil.rmtree(work, ignore_errors=True)


def is_help(line):
    words = line.split()
    return "--help" in words or "-h" in words or (words and words[0] == "help")


def main():
    args = sys.argv[1:]
    if len(args) < 2:
        print(__doc__)
        return 2
    old, new = os.path.abspath(args[0]), os.path.abspath(args[1])
    only = None
    jobs = 6
    show = 3
    i = 2
    while i < len(args):
        if args[i] == "--only":
            only = args[i + 1]
            i += 2
        elif args[i] == "-j":
            jobs = int(args[i + 1])
            i += 2
        elif args[i] == "--show":
            show = int(args[i + 1])
            i += 2
        else:
            print("unknown option " + args[i])
            return 2
    ctx = os.path.join(ROOT, "tests", "query", "context")
    groups = transcripts()
    groups.append(("docs", ctx, doc_lines()))
    # bad inputs one by one (each independent of the others)
    for b in BAD:
        groups.append(("bad", ctx, [b]))
    if only:
        groups = [g for g in groups if any(only in l for l in g[2]) or only in g[0]]

    def compare(g):
        name, prog, lines = g
        a = run(old, prog, lines, 60)
        b = run(new, prog, lines, 60)
        diffs = []
        for line, x, y in zip(lines, a, b):
            if x != y:
                diffs.append((name, line, x, y))
        return len(lines), diffs

    total = 0
    alld = []
    with ThreadPoolExecutor(jobs) as ex:
        for n, d in ex.map(compare, groups):
            total += n
            alld.extend(d)
    helpd = [d for d in alld if is_help(d[1])]
    real = [d for d in alld if not is_help(d[1])]
    for name, line, x, y in real:
        what = [k for k, i in (("stdout", 0), ("stderr", 1), ("exit", 2)) if x[i] != y[i]]
        print(f"DIFF {name}: volec {line}  ({', '.join(what)})")
        if show > 0:
            show -= 1
            for k, i in (("stdout", 0), ("stderr", 1), ("exit", 2)):
                if x[i] != y[i]:
                    print(f"  old {k}: {str(x[i])[:600]!r}")
                    print(f"  new {k}: {str(y[i])[:600]!r}")
    for name, line, x, y in helpd:
        print(f"help {name}: volec {line}")
    print(f"cli-compat: {total} command lines, {len(real)} differ, {len(helpd)} help lines differ")
    return 1 if real else 0


if __name__ == "__main__":
    sys.exit(main())
