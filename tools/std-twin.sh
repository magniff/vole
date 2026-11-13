#!/bin/sh
# std's rustc twin (0.27.2): a tests/run/std_*.vl case's EXPECT and EXIT
# lines checked against what Rust's std prints for the same program.
#
# usage: tools/std-twin.sh [-v] [-j N] [-r RUSTC] CASE...
#
#   -v        print every case's line (default: differ, rejected and the
#             summary)
#   -j N      cases at once (default 4)
#   -r RUSTC  the rustc to run (default: rustc on PATH, else
#             ~/.cargo/bin/rustc); none found: exit 77 (a gate SKIP)
#
# A case becomes Rust by plan-0272 §4's textual inverse of the capability:
#   `fn main(gpa: Gpa)` -> `fn main()`, `, Gpa>` and `<Gpa>` dropped,
#   `X_in(.., gpa)` -> `X(..)` (new_in -> new, from_in -> from,
#   to_string_in -> to_string, collect_in -> collect, sort_in -> sort, ...),
#   `format_in("..", args, gpa)` -> `format!("..", args)`, `println(` and
#   the other format functions (print, eprint, eprintln, format_args,
#   write, writeln, panic, assert, assert_eq, assert_ne, todo,
#   unreachable) -> their macros (a first argument that is no literal is
#   printed: `println(s)` -> `println!("{}", s)`), std-only imports
#   (ToStringIn, DefaultIn, FromIteratorIn) dropped.
# Then `rustc --edition 2021 -A warnings` builds it and it runs: its stdout
# lines must be the EXPECT lines, its exit code the EXIT line's (default 0;
# a Rust panic is 101, as std's); its stdin is the STDIN lines, as the
# runner gives them.
#
# Each case is one of:
#   agree     rustc builds it and the output and exit code are the case's
#   differ    rustc builds it and they are not: the case or std is wrong
#   outside   the inverse cannot make it Rust: an allocator or vole-only
#             item is left (Gpa, Arena, Formatter::new, ...), rustc
#             rejects what the inverse made, or the case says
#             `// RUSTC: none (WHY)` (std's API differs from Rust's on
#             purpose there)
# Exit: 0 when no case differs, 1 otherwise.
# Scratch: target/std-twin/ (each case's .rs, binary and output).

V=0
J=4
RUSTC=
while [ $# -gt 0 ]; do
    case "$1" in
        -v) V=1; shift ;;
        -j) J="$2"; shift 2 ;;
        -r) RUSTC="$2"; shift 2 ;;
        --) shift; break ;;
        -*) echo "std-twin: unknown option $1" >&2; exit 2 ;;
        *) break ;;
    esac
done
[ $# -gt 0 ] || { echo "usage: tools/std-twin.sh [-v] [-j N] [-r RUSTC] CASE..." >&2; exit 2; }
if [ -z "$RUSTC" ]; then
    RUSTC=$(command -v rustc 2>/dev/null || true)
    [ -n "$RUSTC" ] || { [ -x "$HOME/.cargo/bin/rustc" ] && RUSTC="$HOME/.cargo/bin/rustc"; }
fi
[ -n "$RUSTC" ] && [ -x "$RUSTC" ] || { echo "std-twin: SKIP: no rustc"; exit 77; }
ROOT=$(cd "$(dirname "$0")/.." && pwd)
exec python3 -I - "$ROOT" "$RUSTC" "$V" "$J" "$@" <<'PY'
import os
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

ROOT, RUSTC, VERBOSE, JOBS = sys.argv[1], sys.argv[2], sys.argv[3] == "1", int(sys.argv[4])
CASES = sys.argv[5:]
WORK = os.path.join(ROOT, "target", "std-twin")
os.makedirs(WORK, exist_ok=True)

MACROS = ["println", "print", "eprintln", "eprint", "format_args", "write", "writeln",
          "panic", "assert", "assert_eq", "assert_ne", "debug_assert", "todo",
          "unimplemented", "unreachable"]
# where the format string is: the argument index (assert's message is a
# format string after its condition)
FMT_ARG = {"write": 1, "writeln": 1, "assert": 1, "debug_assert": 1, "assert_eq": 2, "assert_ne": 2}
# X_in -> Rust's name, when it is not X
RENAME = {"from_utf8_lossy": "from_utf8_lossy"}
DROP_USES = ("ToStringIn", "DefaultIn", "FromIteratorIn", "ToOwnedIn", "CollectIn", "FixedState")
# left after the inverse: the case is outside
VOLE_ONLY = [r"\bGpa\b", r"\bgpa\b", r"\bArena\b", r"\bAnyAlloc\b", r"\bFixedBuf\b",
             r"Formatter::new\b", r"\ballocator\(\)", r"\blive_blocks\b", r"\bcheck_leaks\b",
             r"\bFixedState\b", r"\bFoldHasher\b", r"\b\w+_in\(", r"#\[array_builtin",
             r"\bToStringIn\b", r"\bDefaultIn\b", r"\bFromIteratorIn\b",
             r"\bTypedArena\b", r"\bArenaScope\b", r"\barena_scope\b"]


def scan_args(s, i):
    """s[i] == '(': (the top-level arguments' spans, the index after ')')."""
    depth, j, start, args = 0, i, i + 1, []
    while j < len(s):
        c = s[j]
        if c == '"':
            j += 1
            while j < len(s) and s[j] != '"':
                j += 2 if s[j] == "\\" else 1
        elif c == "'" and re.match(r"'(\\.|[^\\'])+'", s[j:]):
            j += re.match(r"'(\\.|[^\\'])+'", s[j:]).end() - 1
        elif c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
            if depth == 0:
                if s[start:j].strip():
                    args.append((start, j))
                return args, j + 1
        elif c == "," and depth == 1:
            args.append((start, j))
            start = j + 1
        j += 1
    return None, None


def inverse_in(s):
    """`X_in(.., gpa)` -> `X(..)`; format_in -> format!."""
    out, pos = [], 0
    for m in re.finditer(r"\b(\w+)_in(::<[^()]*?>)?\(", s):
        if m.start() < pos:
            continue
        args, end = scan_args(s, m.end() - 1)
        if args is None or not args or s[args[-1][0]:args[-1][1]].strip() != "gpa":
            continue
        kept = [s[a:b].strip() for a, b in args[:-1]]
        name = m.group(1)
        if name == "format":
            call = "format!(" + ", ".join(kept) + ")"
        else:
            call = RENAME.get(name, name) + (m.group(2) or "") + "(" + ", ".join(kept) + ")"
        out.append(s[pos:m.start()])
        out.append(call)
        pos = end
    out.append(s[pos:])
    return "".join(out)


def macros(s):
    """println( -> println!(, a first argument that is no literal printed."""
    out, pos = [], 0
    pat = re.compile(r"(?<![\w.:!])(" + "|".join(MACROS) + r")\(")
    for m in pat.finditer(s):
        if m.start() < pos or re.search(r"\bfn\s*$", s[max(0, m.start() - 4):m.start()]):
            continue
        name = m.group(1)
        args, end = scan_args(s, m.end() - 1)
        if args is None:
            continue
        parts = [s[a:b].strip() for a, b in args]
        k = FMT_ARG.get(name, 0)
        if len(parts) > k and not parts[k].startswith('"'):
            parts.insert(k, '"{}"')
        out.append(s[pos:m.start()])
        out.append(name + "!(" + ", ".join(parts) + ")")
        pos = end
    out.append(s[pos:])
    return "".join(out)


def translate(src):
    lines = []
    for line in src.split("\n"):
        if re.match(r"\s*//", line):
            continue
        if line.startswith("use ") and any(d in line for d in DROP_USES):
            m = re.match(r"use (.*)::\{(.*)\};$", line)
            if m:
                keep = [x.strip() for x in m.group(2).split(",") if x.strip() not in DROP_USES]
                if keep:
                    lines.append(f"use {m.group(1)}::{{{', '.join(keep)}}};")
            continue
        lines.append(line)
    s = "\n".join(lines)
    s = re.sub(r"fn main\(gpa: Gpa\)", "fn main()", s)
    # (0.29.0) a map's hasher is written, after the allocator: Rust's default
    s = re.sub(r",\s*Gpa,\s*FixedState>", ">", s)
    s = re.sub(r",\s*Gpa>", ">", s)
    s = re.sub(r"<Gpa>", "", s)
    while True:
        t = inverse_in(s)  # nested calls: the outer one first, then the inner
        if t == s:
            break
        s = t
    s = re.sub(r"\bDefaultIn::default\(\)", "Default::default()", s)
    # std's fixed-seed hasher: Rust's (the cases compare hashes, not values)
    s = re.sub(r"\bFixedState::new\(\)", "std::hash::BuildHasherDefault::<std::collections::hash_map::DefaultHasher>::default()", s)
    s = macros(s)
    return s


def directives(src):
    exp, exitc, none, stdin = [], 0, None, []
    for line in src.split("\n"):
        m = re.match(r"// EXPECT: ?(.*)$", line)
        if m:
            exp.append(m.group(1))
        m = re.match(r"// EXIT: (\d+)", line)
        if m:
            exitc = int(m.group(1))
        m = re.match(r"// STDIN: ?(.*)$", line)
        if m:
            stdin.append(m.group(1))
        m = re.match(r"// RUSTC: none(.*)$", line)
        if m:
            none = m.group(1).strip() or "(no reason)"
    return exp, exitc, none, "\n".join(stdin)


def run(path):
    name = os.path.basename(path)[:-3]
    src = open(path).read()
    exp, exitc, none, stdin = directives(src)
    if none:
        return name, "outside", "RUSTC: none " + none
    rs = translate(src)
    left = [p for p in VOLE_ONLY if re.search(p, rs)]
    d = os.path.join(WORK, name)
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "main.rs"), "w") as f:
        f.write(rs)
    if left:
        return name, "outside", "vole-only: " + re.sub(r"\\b|\\", "", left[0])
    exe = os.path.join(d, "main")
    r = subprocess.run([RUSTC, "--edition", "2021", "-A", "warnings", "-o", exe,
                        os.path.join(d, "main.rs")], capture_output=True, text=True)
    if r.returncode != 0:
        first = next((l for l in r.stderr.split("\n") if l.startswith("error")), "error")
        return name, "outside", "rustc rejects: " + first[:160]
    try:
        p = subprocess.run([exe], input=stdin, capture_output=True, text=True, timeout=20)
    except subprocess.TimeoutExpired:
        return name, "differ", "no exit after 20 s"
    got = p.stdout.split("\n")
    if got and got[-1] == "":
        got.pop()
    why = []
    if got != exp:
        for i in range(max(len(got), len(exp))):
            g = got[i] if i < len(got) else "<none>"
            e = exp[i] if i < len(exp) else "<none>"
            if g != e:
                why.append(f"line {i + 1}: expected {e!r}, rustc's prints {g!r}")
                break
    if p.returncode != exitc:
        why.append(f"exit {p.returncode}, expected {exitc}")
    return name, ("differ" if why else "agree"), "; ".join(why)


with ThreadPoolExecutor(max_workers=JOBS) as ex:
    results = list(ex.map(run, CASES))
counts = {"agree": 0, "differ": 0, "outside": 0}
for name, verdict, why in sorted(results):
    counts[verdict] += 1
    if verdict == "differ" or VERBOSE or why.startswith("rustc rejects"):
        print(f"{verdict:8} {name}: {why}" if why else f"{verdict:8} {name}")
print(f"std-twin: {len(results)} cases: {counts['agree']} agree, {counts['differ']} differ, "
      f"{counts['outside']} outside")
sys.exit(1 if counts["differ"] else 0)
PY
