#!/bin/sh
# The rustc twin of rust-edition programs (0.27.3, gate 2; plan-0271 §2.2):
# a case's program built by stable rustc with the shim's prelude
# (tools/rustc-twin/prelude.rs: `Gpa`, the `_in` functions as extension
# traits) and run; its stdout and exit code must be the case's EXPECT and
# EXIT lines. The generalization of tools/std2-twin.sh: the program keeps
# its allocator calls, which resolve to the prelude's.
#
# usage: tools/rustc-twin.sh [-v] [-j N] [-r RUSTC] [--guide] [CASE...]
#
#   -v        print every case's line (default: differ, stale and the
#             summary; -v also each outside's reason)
#   -j N      cases at once (default 4)
#   -r RUSTC  the rustc to run (default: rustc on PATH, else
#             ~/.cargo/bin/rustc); none found: exit 77 (a gate SKIP)
#   --guide   also the guide's rust-edition programs: the blocks of
#             compiler/guide/*.md whose first line is `// EDITION: rust`
#             and that have an out block (tests/guide/run.sh --split)
#   CASE...   rust-edition programs with EXPECT (STDIN, ARGS, EXIT) lines,
#             tests/run/rust_*.vl for instance
#
# A case's `// RUSTC-EDITION: 2024` is rustc's edition (default 2021).
# The text's changes are tools/rustc-twin/twin.py's (main, the types'
# allocator argument, the format functions to macros, the prelude's
# `use`s, the free `X_in(.., gpa)` functions). Each program is one of:
#   agree     rustc builds it, and it prints what the case expects and
#             exits with its code
#   differ    it does not: vole or the case differs from Rust
#   named     it differs, and the case says why: `// RUSTC-DIFFERS: WHY`
#             or, rustc rejecting it, tools/borrowck-twin.sh's `// RUSTC:
#             rejects CLASS WHY`
#             (in the case, plan-0271 Q8), or a line `NAME<TAB>WHY` of
#             tools/rustc-twin/divergences.tsv (for a program that has no
#             case of its own: a guide block, a translation)
#   stale     it is named and agrees: the marker is wrong
#   outside   the shim cannot make it Rust: a vole-only item is left, or
#             rustc rejects the text (its first error), or the case says
#             `// RUSTC: none WHY`
# Prints `rustc-twin: N programs: A agree, D differ, K named, S stale, O
# outside` and the outside's reasons by frequency; exit 1 when one differs
# or is stale. Scratch: target/rustc-twin/NAME/ (main.rs, the binary, the
# output).

V=0
J=4
RUSTC=
GUIDE=0
while [ $# -gt 0 ]; do
    case "$1" in
        -v) V=1; shift ;;
        -j) J="$2"; shift 2 ;;
        -r) RUSTC="$2"; shift 2 ;;
        --guide) GUIDE=1; shift ;;
        -h|--help) sed -n '2,/^# output)/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        --) shift; break ;;
        -*) echo "rustc-twin: unknown option $1" >&2; exit 2 ;;
        *) break ;;
    esac
done
[ $# -gt 0 ] || [ $GUIDE = 1 ] || { echo "usage: tools/rustc-twin.sh [-v] [-j N] [-r RUSTC] [--guide] [CASE...]" >&2; exit 2; }
if [ -z "$RUSTC" ]; then
    RUSTC=$(command -v rustc 2>/dev/null || true)
    [ -n "$RUSTC" ] || { [ -x "$HOME/.cargo/bin/rustc" ] && RUSTC="$HOME/.cargo/bin/rustc"; }
fi
[ -n "$RUSTC" ] && [ -x "$RUSTC" ] || { echo "rustc-twin: SKIP: no rustc"; exit 77; }
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK="$ROOT/target/rustc-twin"
mkdir -p "$WORK"
if [ $GUIDE = 1 ]; then
    rm -rf "$WORK/guide-blocks"
    sh "$ROOT/tests/guide/run.sh" --split "$WORK/guide-blocks" || exit 2
fi
exec python3 -I - "$ROOT" "$RUSTC" "$V" "$J" "$GUIDE" "$@" <<'PY'
import os
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

ROOT, RUSTC, VERBOSE, JOBS, GUIDE = sys.argv[1], sys.argv[2], sys.argv[3] == "1", int(sys.argv[4]), sys.argv[5] == "1"
CASES = sys.argv[6:]
sys.path.insert(0, os.path.join(ROOT, "tools", "rustc-twin"))
from twin import directives, to_rust, rustc_build, rust_edition, stdout_differs, trimmed  # noqa: E402

WORK = os.path.join(ROOT, "target", "rustc-twin")
SIDE = {}
side = os.path.join(ROOT, "tools", "rustc-twin", "divergences.tsv")
if os.path.isfile(side):
    for line in open(side):
        if line.strip() and not line.startswith("#"):
            k, _, why = line.rstrip("\n").partition("\t")
            SIDE[k.strip()] = why.strip()

# (name, source text, stdout wanted, exit wanted, stdin, args, stdout+stderr together)
progs = []
for c in CASES:
    d = directives(c)
    name = os.path.basename(c)[:-3] if c.endswith(".vl") else os.path.basename(os.path.dirname(c))
    progs.append((name, open(c, encoding="utf-8", errors="replace").read(), "\n".join(d["expect"]),
                  d["exit"], "\n".join(d["stdin"]), d.get("args", "").split(), False))
if GUIDE:
    bdir = os.path.join(WORK, "guide-blocks", "blocks")
    for b in sorted(os.listdir(bdir)):
        p = os.path.join(bdir, b)
        src = open(os.path.join(p, "prog.vl")).read()
        if not src.startswith("// EDITION: rust") or not os.path.isfile(os.path.join(p, "out")):
            continue
        if [f for f in os.listdir(p) if f.endswith(".vl") and f != "prog.vl"]:
            continue  # (a program of several files: outside the twin)
        rd = lambda f, dflt="": open(os.path.join(p, f)).read() if os.path.isfile(os.path.join(p, f)) else dflt
        progs.append(("guide-" + b, src, rd("out"), int(rd("exit", "0") or 0), rd("stdin"), [], True))


def run(prog):
    name, src, want, wexit, stdin, args, merged = prog
    m = re.search(r"^\s*// RUSTC-DIFFERS:\s*(.*)$", src, re.M)
    named = (m.group(1).strip() or "(no reason)") if m else SIDE.get(name)
    rs, why = to_rust(src)
    d = os.path.join(WORK, name)
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "main.rs"), "w") as f:
        f.write(rs)
    if why:
        return name, "outside", why
    exe = os.path.join(d, "main")
    bad = rustc_build(RUSTC, os.path.join(d, "main.rs"), exe, rust_edition(src))
    if bad:
        # (a borrowck divergence the case names, tools/borrowck-twin.sh's)
        mk = re.search(r"^\s*// RUSTC: rejects\s+(\S+)\s*(.*)$", src, re.M)
        if mk:
            return name, "named", f"rustc rejects, named {mk.group(1)}: {mk.group(2)[:80]}"
        return name, "outside", "rustc rejects: " + bad
    try:
        p = subprocess.run([exe] + args, input=stdin.encode(), cwd=d, timeout=60,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT if merged else subprocess.PIPE)
    except subprocess.TimeoutExpired:
        return name, ("named" if named else "differ"), "no exit after 60 s"
    got = p.stdout.decode("utf-8", errors="replace")
    if merged:  # (the guide's out block: each line's trailing blanks aside)
        got = "\n".join(l.rstrip() for l in got.split("\n"))
        want = "\n".join(l.rstrip() for l in want.split("\n"))
    diff = stdout_differs(want, got)
    if not diff and p.returncode != wexit:
        diff = f"exit {p.returncode}, expected {wexit}"
    if diff:
        return name, ("named" if named else "differ"), diff + (f" (named: {named})" if named else "")
    if named:
        return name, "stale", f"named ({named}), and it agrees"
    return name, "agree", ""


with ThreadPoolExecutor(max_workers=JOBS) as ex:
    results = list(ex.map(run, progs))
counts = {k: 0 for k in ("agree", "differ", "named", "stale", "outside")}
reasons = {}
for name, verdict, why in sorted(results):
    counts[verdict] += 1
    if verdict == "outside":
        r = re.sub(r" at \S+$", "", why)
        r = re.sub(r"`[^`]*`", "`..`", r)[:90]
        reasons[r] = reasons.get(r, 0) + 1
    if verdict in ("differ", "stale") or VERBOSE:
        print(f"{verdict:8} {name}: {why}" if why else f"{verdict:8} {name}")
print(f"rustc-twin: {len(results)} programs: {counts['agree']} agree, {counts['differ']} differ, "
      f"{counts['named']} named, {counts['stale']} stale, {counts['outside']} outside")
for r, n in sorted(reasons.items(), key=lambda x: -x[1])[:12]:
    print(f"  outside {n}: {r}")
sys.exit(1 if counts["differ"] or counts["stale"] else 0)
PY
