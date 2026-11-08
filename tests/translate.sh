#!/bin/sh
# Gate 2's round trip (0.27.3, docs/design/rust-surface-plan.md §6): every
# MVS program of a set is translated into the rust edition by a
# translator, compiled with `--edition rust`, run, and its output compared
# with the MVS program's. One count per set, and a cause per failure.
#
# usage: tests/translate.sh [-c COMPILER] [-j N] [-O LEVEL] [-s SETS]
#            [--translator CMD | --identity] [--ref expect|build]
#            [--causes FILE] [--triage] [--twin] [-f LIST] [-l] [-v]
#            [FILTER...]
#        tests/translate.sh --record query|refactor [-c COMPILER]
#            [--translator CMD | --identity] [NAME...]
#
#   -c COMPILER     the volec to build with (default: target/volec, else
#                   target/tools/volec)
#   -j N            programs at once (default 4)
#   -O LEVEL        the level every program is built at (default 0, and 2
#                   for bench, whose programs are sized for it)
#   -s SETS         the sets, comma separated (default examples,bench,run):
#                     examples  tests/examples/*.test, each its SOURCE's
#                               directory, with the case's directives
#                     bench     bench/*.vl, bench/std/*.vl, bench/vecloop/*.vl
#                               (no directives: the MVS build's output is
#                               the reference)
#                     run       tests/run's MVS cases that run: no
#                               `// EDITION: rust`, no ERROR, no XFAIL, no
#                               FIXIMPORTS or FIXUNSAFE (a tests/run/NAME/
#                               main.vl is its directory)
#                     guide     the guide's MVS programs: the vole blocks of
#                               compiler/guide/*.md (tests/guide/run.sh
#                               --split), their out block the reference
#                               (stdout and stderr together); a block
#                               without one is only built
#                     rust      tests/run's rust-edition cases that run (the
#                               rust_* corpus: rust_t_ gate 0's hand
#                               translations, rust_b_, rust_f_): the
#                               identity translator's set, the runner's own
#                               check
#   --translator CMD
#                   the translator: CMD (split as a shell would, no
#                   expansion) is run with the copy's root file as its last
#                   argument, or in place of a `{}` word, in the copy's
#                   directory, and rewrites the copy in place (default:
#                   COMPILER fix --edition rust --force). Its exit code 1 with a
#                   line `// EDITION: rust` in the root (the translator puts
#                   it last, every other line kept where it is) is a translation
#                   that leaves errors (the build then names them); any
#                   other non-zero exit is the cause `no-translation`
#   --identity      no translator: the copy is compiled as it is (on the
#                   rust set, the runner's own check)
#   --ref expect    (the default) the reference is the case's EXPECT, EXIT
#                   and STDERR lines, which the suite holds the MVS build to;
#                   a program without a case (bench) is built as MVS
#   --ref build     every program is also built as MVS (the original, in
#                   place) and run: the reference is its stdout and exit code
#   --causes FILE   the classification (default tests/translate/causes.tsv,
#                   below)
#   --triage        add each unclassified failure to the classification as
#                   `?`, for whoever fills it
#   --twin          (gate 2's second half) each program that round-trips is
#                   built by stable rustc too, through the rustc twin's shim
#                   (tools/rustc-twin.sh, tools/rustc-twin/), and run: its
#                   output against the same reference, agree, differ
#                   (named: a `// RUSTC-DIFFERS: WHY` line in the
#                   translation, or `SET/NAME<TAB>WHY` in
#                   tools/rustc-twin/divergences.tsv) or outside (the shim
#                   cannot make it Rust, or rustc rejects it); one count
#                   per set
#   --alloc-api     the twin with Rust's own allocator_api (rustc as nightly,
#                   RUSTC_BOOTSTRAP=1: tools/rustc-twin.sh --alloc-api), so
#                   that a borrow of an allocator is checked as rustc's; its
#                   lines say `rustc twin (allocator_api)`
#   -f LIST         only the programs LIST names, one per line (# comments):
#                   NAME, SET/NAME or a path (tests/run/NAME.vl,
#                   tests/run/NAME/main.vl, tests/examples/NAME.test,
#                   bench/NAME.vl); repeatable, the union with FILTERs
#   -l              list the programs of the sets and FILTERs, run nothing
#   -v              a line for every program, not only the failures
#   FILTER...       only the programs whose `SET/NAME` contains a FILTER
#
# A program's copy is target/translate/SET/NAME/src (a file, or its
# directory for a program of several modules); it is built with the case's
# FLAGS (@ROOT@ the root), CSOURCE and CHEADER, and `--edition rust`, and
# runs in target/translate/SET/NAME with its ARGS, STDIN and ENV, for 60 s
# times its TIMEOUT. Each failure is one line, `FAIL SET/NAME: CAUSE:
# DETAIL`, CAUSE one of
#   no-translation   the translator failed (its exit code, its last line)
#   type CODE        the translation does not compile: the first error's
#                    code (`type parser error`, `type type error`,
#                    `type trait.unmet`, ...)
#   borrowck CODE    ... with a `borrowck.*` error first
#   link             it compiles and does not link
#   crash            the compiler stopped without a diagnostic (a signal)
#   output           its stdout is not the reference's (the first line that
#                    differs)
#   exit             its exit code is not the reference's
#   stderr           a STDERR line is missing
#   timeout          it ran out of time
#   ref              (--ref build, bench) the MVS build itself fails: not
#                    counted against the translator
# then one line per set:
#   translate: SET: N of M round-trip (CAUSE n, ...)
# and the total, `translate: N of M round-trip`. Informational until 0.27.4:
# the exit code is 0 unless the usage is wrong.
#
# --record SUITE (0.27.3, the migration surface): the transcripts of
# tests/query (SUITE query, NAME.q) or tests/refactor (refactor, NAME.t)
# regenerated under the rust edition, for review as a diff. A copy of the
# suite goes to target/translate/record/tests/SUITE (with the root's
# tests/stdpos.awk, tests/stdkeep.sh and compiler/); each transcript's program
# (SUITE/NAME/main.vl) is translated in place by the translator; the
# suite's runner then rewrites every transcript that differs (its -u: the
# record mode). Prints one line per transcript that changed, with its
# diff's size, the programs the translator failed on, and
# `translate: record SUITE: C of N transcripts change (T programs
# translated, F not)`; the diff is target/translate/record/SUITE.diff.
# NAME...: only these transcripts.
#
# The classification, tests/translate/causes.tsv, is the translator's
# owners' record of why a program does not round-trip yet: lines
# `CASE<TAB>CAUSE<TAB>NOTE` (# comments), CASE a NAME or SET/NAME, CAUSE
# translator, front, std2 or borrowck (`?`: not yet looked at; the NOTE
# names the item: FL10, Q7, ...). The runner prints
# the failures by class, the unclassified ones, and the stale lines (a
# classified program that round-trips). Every program's result, `SET/NAME
# STATUS CAUSE DETAIL` tab separated, is in target/translate/results.tsv.

set -u
# (as tests/run.sh: without the code cache, unless the caller says)
VOLE_CODE_CACHE=${VOLE_CODE_CACHE:-off}
export VOLE_CODE_CACHE
ROOT=$(cd "$(dirname "$0")/.." && pwd)
COMPILER=""
JOBS=4
OPT=""
SETS=examples,bench,run
TRANSLATOR=""
IDENTITY=0
REF=expect
CLASSES="$ROOT/tests/translate/causes.tsv"
LISTS=""
TRIAGE=0
TWIN=0
ALLOC=0
RECORD=""
LIST=0
VERBOSE=0
usage() { sed -n '2,/^# then one line/p' "$0" | sed '$d; s/^# \{0,1\}//' >&2; exit 2; }
while [ $# -gt 0 ]; do
    case "$1" in
        -c) [ $# -ge 2 ] || usage; COMPILER=$2; shift 2 ;;
        -j) [ $# -ge 2 ] || usage; JOBS=$2; shift 2 ;;
        -O) [ $# -ge 2 ] || usage; OPT=$2; shift 2 ;;
        -O[0-2]) OPT=${1#-O}; shift ;;
        -s) [ $# -ge 2 ] || usage; SETS=$2; shift 2 ;;
        --translator) [ $# -ge 2 ] || usage; TRANSLATOR=$2; shift 2 ;;
        --identity) IDENTITY=1; shift ;;
        --ref) [ $# -ge 2 ] || usage; REF=$2; shift 2 ;;
        --causes) [ $# -ge 2 ] || usage; CLASSES=$2; shift 2 ;;
        -f) [ $# -ge 2 ] || usage; [ -f "$2" ] || { echo "tests/translate.sh: no list $2" >&2; exit 2; }
            LISTS="$LISTS$(sed 's/#.*//; s/^[[:space:]]*//; s/[[:space:]]*$//; /^$/d' "$2")
"; shift 2 ;;
        --triage) TRIAGE=1; shift ;;
        --twin) TWIN=1; shift ;;
        --alloc-api) ALLOC=1; shift ;;
        --record) [ $# -ge 2 ] || usage; RECORD=$2; shift 2 ;;
        -l) LIST=1; shift ;;
        -v) VERBOSE=1; shift ;;
        -h|--help) usage ;;
        --) shift; break ;;
        -*) echo "tests/translate.sh: unknown option '$1' (tests/translate.sh -h)" >&2; exit 2 ;;
        *) break ;;
    esac
done
case "$REF" in expect|build) ;; *) echo "tests/translate.sh: --ref expect or build" >&2; exit 2 ;; esac
if [ -z "$COMPILER" ]; then
    COMPILER="$ROOT/target/volec"
    [ -x "$COMPILER" ] || COMPILER="$ROOT/target/tools/volec"
fi
case "$COMPILER" in /*) ;; *) COMPILER="$(pwd)/$COMPILER" ;; esac
[ -x "$COMPILER" ] || { echo "tests/translate.sh: no compiler $COMPILER" >&2; exit 2; }
# (--force: a generated case, tools/sinksweep's, is a program to translate
# too; its copy is never written back)
[ -n "$TRANSLATOR" ] || TRANSLATOR="$COMPILER fix --edition rust --force"
[ $IDENTITY = 1 ] && TRANSLATOR=""
if [ -n "$RECORD" ]; then
    case "$RECORD" in
        query) EXT=q ;;
        refactor) EXT=t ;;
        *) echo "tests/translate.sh: --record query or refactor" >&2; exit 2 ;;
    esac
    R="$ROOT/target/translate/record"
    rm -rf "$R/tests/$RECORD" "$R/logs-$RECORD"
    mkdir -p "$R/tests" "$R/logs-$RECORD"
    cp -R "$ROOT/tests/$RECORD" "$R/tests/" || exit 2
    for f in stdpos.awk stdkeep.sh; do ln -sf "$ROOT/tests/$f" "$R/tests/$f"; done
    # (std's files where the transcripts' relative paths find them)
    [ -e "$R/compiler" ] || ln -s "$ROOT/compiler" "$R/compiler"
    names="" n=0 ntr=0 nbad=0
    for t in "$R/tests/$RECORD"/*.$EXT; do
        name=$(basename "$t" .$EXT)
        if [ $# -gt 0 ]; then
            case " $* " in *" $name "*) ;; *) continue ;; esac
        fi
        names="$names $name"
        n=$((n + 1))
        d="$R/tests/$RECORD/$name"
        [ -f "$d/main.vl" ] && [ -n "$TRANSLATOR" ] || continue
        # shellcheck disable=SC2086
        (cd "$d" && $TRANSLATOR "$d/main.vl") >"$R/logs-$RECORD/$name.out" 2>&1
        rc=$?
        if [ $rc -eq 0 ] || { [ $rc -eq 1 ] && grep -q '^// EDITION: rust *$' "$d/main.vl"; }; then
            ntr=$((ntr + 1))
        else
            nbad=$((nbad + 1))
            echo "no-translation $RECORD/$name: exit $rc: $(grep . "$R/logs-$RECORD/$name.out" | tail -1 | cut -c1-160)"
        fi
    done
    # (the suite's own record mode: every transcript that differs rewritten)
    # shellcheck disable=SC2086
    sh "$R/tests/$RECORD/run.sh" -c "$COMPILER" -u $names >"$R/$RECORD.run" 2>&1
    : >"$R/$RECORD.diff"
    changed=0
    for name in $names; do
        if ! diff -u "$ROOT/tests/$RECORD/$name.$EXT" "$R/tests/$RECORD/$name.$EXT" \
            >"$R/logs-$RECORD/$name.diff" 2>&1; then
            changed=$((changed + 1))
            cat "$R/logs-$RECORD/$name.diff" >>"$R/$RECORD.diff"
            echo "changed $RECORD/$name.$EXT: $(grep -c '^[-+][^-+]' "$R/logs-$RECORD/$name.diff") lines"
        fi
    done
    echo "translate: record $RECORD: $changed of $n transcripts change ($ntr programs translated, $nbad not; translator: ${TRANSLATOR:-identity})"
    echo "translate: the diff: ${R#"$ROOT"/}/$RECORD.diff"
    exit 0
fi
case ",$SETS," in
    *,guide,*) sh "$ROOT/tests/guide/run.sh" --split "$ROOT/target/translate/guide-blocks" || exit 2 ;;
esac
exec python3 -I - "$ROOT" "$COMPILER" "$JOBS" "$OPT" "$SETS" "$TRANSLATOR" "$REF" \
    "$CLASSES" "$TRIAGE" "$LIST" "$VERBOSE" "$LISTS" "$TWIN" "$ALLOC" "$@" <<'PY'
import os
import re
import shlex
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

(ROOT, COMPILER, JOBS, OPT, SETS, TRANSLATOR, REF, CLASSES, TRIAGE, LIST,
 VERBOSE, LISTS, TWIN, ALLOC) = sys.argv[1:15]
FILTERS = sys.argv[15:]
ALLOC = ALLOC == "1"
OPT_GIVEN = OPT != ""
OPT = OPT or "0"
TWIN_NAME = "rustc twin (allocator_api, RUSTC_BOOTSTRAP=1)" if ALLOC else "rustc twin"
sys.path.insert(0, os.path.join(ROOT, "tools", "rustc-twin"))
from twin import directives, trimmed, stdout_differs, to_rust, rustc_build, rust_edition, find_rustc  # noqa: E402
TWIN = TWIN == "1"
RUSTC = find_rustc() if TWIN else ""
if TWIN and not RUSTC:
    print("translate: --twin: no rustc, the twin skipped")
    TWIN = False
SIDE = {}
_side = os.path.join(ROOT, "tools", "rustc-twin", "divergences.tsv")
if os.path.isfile(_side):
    for _l in open(_side):
        if _l.strip() and not _l.startswith("#"):
            _k, _, _why = _l.rstrip("\n").partition("\t")
            SIDE[_k.strip()] = _why.strip()


def list_name(x):
    """A -f line: NAME or SET/NAME, from a path too."""
    x = x.split()[0]
    m = re.match(r"(?:\./)?tests/run/([^/]+?)(?:\.vl|/main\.vl|/)?$", x)
    if m:
        return m.group(1)
    m = re.match(r"(?:\./)?tests/examples/([^/]+)\.test$", x)
    if m:
        return "examples/" + m.group(1)
    m = re.match(r"(?:\./)?bench/(.+)\.vl$", x)
    if m:
        return "bench/" + m.group(1)
    return x


NAMES = {list_name(x) for x in LISTS.split("\n") if x.strip()}
JOBS, TRIAGE, LIST, VERBOSE = int(JOBS), TRIAGE == "1", LIST == "1", VERBOSE == "1"
SETS = [s for s in SETS.split(",") if s]
WORK = os.path.join(ROOT, "target", "translate")
for s in SETS:
    if s not in ("examples", "bench", "run", "guide", "rust"):
        sys.exit(f"tests/translate.sh: no set {s} (examples, bench, run, guide, rust)")


# The programs: (set, name, entry, directory to copy or None, directives,
# whether it has a reference in its directives)
def programs():
    out = []
    if "examples" in SETS:
        tdir = os.path.join(ROOT, "tests", "examples")
        for f in sorted(os.listdir(tdir)):
            if not f.endswith(".test"):
                continue
            d = directives(os.path.join(tdir, f))
            if "XFAIL" in d["has"] or "ERROR" in d["has"] or not d.get("source"):
                continue
            entry = os.path.join(ROOT, d["source"])
            out.append(("examples", f[:-5], entry, os.path.dirname(entry), d, True))
    if "bench" in SETS:
        for sub in ("bench", "bench/std", "bench/vecloop"):
            bdir = os.path.join(ROOT, sub)
            for f in sorted(os.listdir(bdir)):
                if not f.endswith(".vl"):
                    continue
                p = os.path.join(bdir, f)
                src = open(p, encoding="utf-8", errors="replace").read()
                if "// bench-std: data" in src or not re.search(r"^fn main\(", src, re.M):
                    continue  # (reads a file bench/std/run.sh makes; a module)
                name = (sub[len("bench"):].lstrip("/") + "/" if sub != "bench" else "") + f[:-3]
                d = directives(p)
                if not OPT_GIVEN:
                    d["level"] = "2"  # (sized for -O2, as bench/run.sh builds them)
                out.append(("bench", name, p, None, d, False))
    if "guide" in SETS:
        gdir = os.path.join(WORK, "guide-blocks", "blocks")
        for b in sorted(os.listdir(gdir)):
            p = os.path.join(gdir, b)
            src = "".join(open(os.path.join(p, f)).read() for f in os.listdir(p) if f.endswith(".vl"))
            if (src.startswith("// EDITION: rust") or os.path.isfile(os.path.join(p, "edition"))
                    or os.path.isfile(os.path.join(p, "err"))):
                continue
            if re.search(r"std::(gpu|objc|window)", src):
                continue  # (built to an object only, or linked with Metal: tests/guide/run.sh's)
            d = directives(os.path.join(p, "none"))
            d["merged"] = True
            if os.path.isfile(os.path.join(p, "out")):
                d["expect"] = [open(os.path.join(p, "out")).read()]
                d["exit"] = int(open(os.path.join(p, "exit")).read() or 0)
            else:
                d["has"].add("BUILD")
            if os.path.isfile(os.path.join(p, "stdin")):
                d["stdin"] = [open(os.path.join(p, "stdin")).read()]
            out.append(("guide", b, os.path.join(p, "prog.vl"), p, d, True))
    for s in ("run", "rust"):
        if s not in SETS:
            continue
        rdir = os.path.join(ROOT, "tests", "run")
        for f in sorted(os.listdir(rdir)):
            p = os.path.join(rdir, f)
            if f.endswith(".vl") and os.path.isfile(p):
                entry, copy, name = p, None, f[:-3]
            elif os.path.isfile(os.path.join(p, "main.vl")):
                entry, copy, name = os.path.join(p, "main.vl"), p, f
            else:
                continue
            d = directives(entry)
            rust = d.get("edition") == "rust"
            if (s == "rust") != rust:
                continue
            if s == "rust" and not name.startswith("rust_"):
                continue
            if d["has"] & {"ERROR", "ERROR-COUNT", "XFAIL", "FIXIMPORTS", "FIXUNSAFE"}:
                continue
            if any(k.startswith("XFAIL(") for k in d["has"]):
                continue
            out.append((s, name, entry, copy, d, True))
    if FILTERS or NAMES:
        out = [p for p in out if any(flt in p[0] + "/" + p[1] for flt in FILTERS)
               or p[1] in NAMES or p[0] + "/" + p[1] in NAMES]
    return out


def first_error(out):
    """(cause, detail) of a failed compile's output."""
    for line in out.split("\n"):
        m = re.search(r"(?:^|: )error\[([^\]]+)\]\s*(.*)$", line)
        if m:
            code, msg = m.group(1), m.group(2)
            where = line[:m.start()].rsplit("/", 1)[-1]
            detail = (where + ": " if where else "") + msg
            if code.startswith("borrowck."):
                return "borrowck " + code[len("borrowck."):], detail
            if code.startswith("link."):
                return "link", detail
            return "type " + code, detail
    lines = [l for l in out.split("\n") if l.strip()]
    return "crash", (lines[-1] if lines else "no output")


def build(entry, cwd, d, out, rust, log):
    """Compile entry into out: None, or (cause, detail)."""
    flags = [f.replace("@ROOT@", ROOT) for f in d["flags"]]
    cs = [os.path.join(ROOT, c) for c in d["csource"]]
    # (as tests/run.sh: --check-unsafe needs the IR, -O1 for -O0)
    opt = d.get("level", OPT)
    level = "1" if opt == "0" and "--check-unsafe" in flags else opt
    cmd = [COMPILER, f"-O{level}"] + (["--edition", "rust"] if rust else []) + flags
    if d.get("cheader"):
        r = subprocess.run(cmd + ["--emit-header", entry, "-o", os.path.join(cwd, d["cheader"])],
                           capture_output=True, text=True, cwd=cwd)
        if r.returncode != 0:
            return first_error(r.stdout + r.stderr)
        cs = ["-I", cwd] + cs
    try:
        r = subprocess.run(cmd + [entry] + cs + ["-o", out], capture_output=True, text=True,
                           cwd=cwd, timeout=600)
    except subprocess.TimeoutExpired:
        return "crash", "the compiler ran for 600 s"
    with open(log, "w") as f:
        f.write(r.stdout + r.stderr)
    if r.returncode == 0:
        return None
    if r.returncode != 1:
        return "crash", f"exit {r.returncode}: " + (trimmed(r.stdout + r.stderr).split("\n")[-1])[:160]
    return first_error(r.stdout + r.stderr)


def run_prog(prog, cwd, d):
    """(stdout, stderr, exit code) or None when it ran out of time; a guide
    block's stdout and stderr together."""
    env = dict(os.environ)
    for kv in d["env"]:
        k, _, v = kv.replace("@ROOT@", ROOT).partition("=")
        env[k] = v
    args = d.get("args", "").replace("@ROOT@", ROOT).split()
    try:
        p = subprocess.run([prog] + args, input="\n".join(d["stdin"]).encode(), stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT if d.get("merged") else subprocess.PIPE,
                           cwd=cwd, env=env, timeout=60 * d["timeout"])
    except subprocess.TimeoutExpired:
        return None
    dec = lambda b: b.decode("utf-8", errors="replace")
    return dec(p.stdout), dec(p.stderr or b""), p.returncode


def compare(want, r, d):
    """None, or (cause, detail): a run r = (stdout, stderr, exit code) against
    the reference want = (stdout, exit code, stderr lines)."""
    out, err, rc = r
    if d.get("merged"):  # (tests/guide/run.sh's: each line's trailing blanks aside)
        out = "\n".join(l.rstrip() for l in out.split("\n"))
        want = ("\n".join(l.rstrip() for l in want[0].split("\n")),) + tuple(want[1:])
    why = stdout_differs(want[0], out)
    if why:
        return "output", why
    if rc != want[1]:
        return "exit", f"exit {rc}, expected {want[1]}" + (": " + trimmed(err).split("\n")[-1][:120] if err.strip() else "")
    for m in want[2]:
        if m not in err:
            return "stderr", f"no stderr line containing {m!r}"
    return None


Q7_RX = re.compile(r"(?<!&)&(?!&)\s*(mut\s+)?(-?[0-9]|\"|\[|\(|true\b|false\b|[A-Z][A-Z0-9_]+\b)")


def q7(cause, log):
    """Whether a borrowck failure is L2/Q7's (borrowck.md: rvalue static
    promotion, `let r: &'static i64 = &3;`): a temporary's region error at
    a line that borrows a literal or a constant."""
    if cause not in ("borrowck dropped_borrowed", "borrowck return_local", "borrowck outlives"):
        return False
    try:
        out = open(log).read()
    except OSError:
        return False
    m = re.search(r"^(.*?):(\d+):\d+: error\[borrowck\.", out, re.M)
    if not m or not os.path.isfile(m.group(1)):
        return False
    lines = open(m.group(1), encoding="utf-8", errors="replace").read().split("\n")
    k = int(m.group(2)) - 1
    return 0 <= k < len(lines) and Q7_RX.search(lines[k]) is not None


def twin(key, w, mine, src, d, want):
    """The rustc twin of a translation that round-trips: (verdict, why)."""
    if len([f for f in os.listdir(os.path.dirname(mine)) if f.endswith(".vl")]) > 1:
        return "outside", "a program of several files"
    text = open(mine, encoding="utf-8", errors="replace").read()
    m = re.search(r"^\s*// RUSTC-DIFFERS:\s*(.*)$", text, re.M)
    named = (m.group(1).strip() or "(no reason)") if m else SIDE.get(key)
    rs, why = to_rust(text, alloc_api=ALLOC)
    tw = os.path.join(w, "rustc")
    os.makedirs(tw, exist_ok=True)
    with open(os.path.join(tw, "main.rs"), "w") as f:
        f.write(rs)
    if why:
        return "outside", why
    level = next((f[2:] for f in d["flags"] if re.fullmatch(r"-O[0-2]", f)), d.get("level", OPT))
    checks = next((f.split("=", 1)[1] == "on" for f in d["flags"] if f.startswith("--overflow-checks=")),
                  level == "0")
    bad = rustc_build(RUSTC, os.path.join(tw, "main.rs"), os.path.join(tw, "prog"), rust_edition(text),
                      overflow=checks, alloc_api=ALLOC)
    if bad:
        # (a borrowck divergence the program names, tools/borrowck-twin.sh's)
        mk = re.search(r"^\s*// RUSTC: rejects\s+(\S+)\s*(.*)$", text, re.M)
        if mk:
            return "named", f"rustc rejects, named {mk.group(1)}: {mk.group(2)[:80]}"
        return "outside", "rustc rejects: " + bad
    r = run_prog(os.path.join(tw, "prog"), tw, d)
    # (stdout and the exit code: a message on stderr is vole's, not Rust's)
    diff = ("timeout", "ran out of time") if r is None else compare(want[:2] + ([],), r, d)
    if diff:
        return ("named" if named else "differ"), f"{diff[0]}: {diff[1]}" + (f" (named: {named})" if named else "")
    if named:
        return "stale", f"named ({named}), and it agrees"
    return "agree", ""


def one(prog):
    s, name, entry, copy, d, has_ref = prog
    key = f"{s}/{name}"
    w = os.path.join(WORK, s, name)
    shutil.rmtree(w, ignore_errors=True)
    src = os.path.join(w, "src")
    if copy:
        shutil.copytree(copy, src, symlinks=True)
        mine = os.path.join(src, os.path.relpath(entry, copy))
        if s == "guide":  # (compiled as main.vl, tests/guide/run.sh's)
            os.rename(mine, os.path.join(src, "main.vl"))
            mine = os.path.join(src, "main.vl")
            for f in ("out", "exit", "stdin", "name"):
                if os.path.isfile(os.path.join(src, f)):
                    os.remove(os.path.join(src, f))
    else:
        os.makedirs(src)
        mine = os.path.join(src, os.path.basename(entry))
        shutil.copy2(entry, mine)
    # the reference
    want = None
    if REF == "build" or not has_ref:
        mvs = os.path.join(w, "mvs")
        os.makedirs(mvs)
        bad = build(entry, mvs, d, os.path.join(mvs, "prog"), False, os.path.join(mvs, "compile.out"))
        if bad:
            return key, "ref", bad[0] + ": " + bad[1]
        r = run_prog(os.path.join(mvs, "prog"), mvs, d)
        if r is None:
            return key, "ref", "the MVS build ran out of time"
        want = (r[0], r[2], [])
    else:
        want = ("\n".join(d["expect"]), d["exit"], d["stderr"])
    # the translation
    if TRANSLATOR:
        words = shlex.split(TRANSLATOR)
        cmd = [mine if x == "{}" else x for x in words]
        if "{}" not in words:
            cmd.append(mine)
        try:
            r = subprocess.run(cmd, capture_output=True, text=True, cwd=os.path.dirname(mine),
                               timeout=600)
        except subprocess.TimeoutExpired:
            return key, "no-translation", "the translator ran for 600 s"
        with open(os.path.join(w, "translate.out"), "w") as f:
            f.write(r.stdout + r.stderr)
        try:
            marked = re.search(r"^// EDITION: rust\s*$", open(mine, encoding="utf-8", errors="replace").read(), re.M)
        except OSError:
            marked = None
        if r.returncode != 0 and not (r.returncode == 1 and marked):
            last = [l for l in (r.stdout + r.stderr).split("\n") if l.strip()]
            return key, "no-translation", f"exit {r.returncode}: " + (last[-1] if last else "")[:160]
    bad = build(mine, w, d, os.path.join(w, "prog"), True, os.path.join(w, "compile.out"))
    if bad:
        return key, bad[0], bad[1][:200] + (" [Q7?]" if q7(bad[0], os.path.join(w, "compile.out")) else "")
    if "BUILD" in d["has"]:
        return key, "ok", ""
    r = run_prog(os.path.join(w, "prog"), w, d)
    if r is None:
        return key, "timeout", f"killed after {60 * d['timeout']} s"
    bad = compare(want, r, d)
    if bad:
        return key, bad[0], bad[1]
    if TWIN:
        return key, "ok", "", twin(key, w, mine, src, d, want)
    return key, "ok", ""


def read_classes():
    cls = {}
    if os.path.isfile(CLASSES):
        for line in open(CLASSES):
            line = line.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            parts = line.split("\t")
            cls[parts[0].strip()] = (parts[1].strip() if len(parts) > 1 else "?", parts[2] if len(parts) > 2 else "")
    return cls


progs = programs()
if LIST:
    for p in progs:
        print(f"{p[0]}/{p[1]}\t{os.path.relpath(p[2], ROOT)}")
    print(f"translate: {len(progs)} programs")
    sys.exit(0)
os.makedirs(WORK, exist_ok=True)
with ThreadPoolExecutor(max_workers=JOBS) as ex:
    results = [r if len(r) == 4 else r + (None,) for r in ex.map(one, progs)]
cls = read_classes()
with open(os.path.join(WORK, "results.tsv"), "w") as f:
    for key, status, why, tw in results:
        f.write(f"{key}\t{'ok' if status == 'ok' else 'fail'}\t{status}\t{why}"
                + (f"\ttwin {tw[0]}\t{tw[1]}" if tw else "") + "\n")
for key, status, why, tw in sorted(results):
    if tw and tw[0] in ("differ", "stale"):
        print(f"TWIN {key}: {tw[0]}: {tw[1]}")
    elif tw and VERBOSE:
        print(f"twin {key}: {tw[0]}" + (f": {tw[1]}" if tw[1] else ""))
    if status != "ok":
        c = cls.get(key) or cls.get(key.split("/", 1)[1])
        print(f"FAIL {key}: {status}: {why}" + (f" [{c[0]}]" if c else ""))
    elif VERBOSE:
        print(f"ok   {key}")
tot_ok = tot = 0
twin_tot = [0, 0]
for s in SETS:
    rs = [r for r in results if r[0].startswith(s + "/")]
    if not rs and (FILTERS or NAMES):
        continue
    ok = sum(1 for r in rs if r[1] == "ok")
    refs = sum(1 for r in rs if r[1] == "ref")
    hist = {}
    for r in rs:
        if r[1] not in ("ok", "ref"):
            c = r[1].split(" ")[0]
            hist[c] = hist.get(c, 0) + 1
    order = ["no-translation", "type", "borrowck", "link", "crash", "output", "exit", "stderr", "timeout"]
    parts = [f"{c} {hist[c]}" for c in order if c in hist]
    if refs:
        parts.append(f"ref {refs} not counted")
    print(f"translate: {s}: {ok} of {len(rs) - refs} round-trip" + (f" ({', '.join(parts)})" if parts else ""))
    if TWIN:
        tws = [r[3] for r in rs if r[3]]
        tc = {v: sum(1 for t in tws if t[0] == v) for v in ("agree", "differ", "named", "stale", "outside")}
        print(f"translate: {s}: {TWIN_NAME}: {tc['agree']} of {len(tws)} agree ({tc['differ']} differ, "
              f"{tc['named']} named, {tc['stale']} stale, {tc['outside']} outside)")
        twin_tot[0] += tc["agree"]
        twin_tot[1] += len(tws)
    tot_ok += ok
    tot += len(rs) - refs
# the type and borrowck codes, most frequent first
codes = {}
for r in results:
    if r[1].startswith(("type ", "borrowck ")):
        codes[r[1]] = codes.get(r[1], 0) + 1
nq7 = sum(1 for r in results if r[2].endswith("[Q7?]"))
if nq7:
    print(f"translate: Q7 (rvalue static promotion, L2): {nq7} failures borrow a literal or a constant")
if codes:
    print("translate: codes: " + ", ".join(f"{c} {n}" for c, n in sorted(codes.items(), key=lambda x: (-x[1], x[0]))[:12]))
# the classification
fails = {r[0]: r for r in results if r[1] not in ("ok", "ref")}
byclass, unclassified = {}, []
def cls_of(key):
    return cls.get(key) or cls.get(key.split("/", 1)[1])


for key in sorted(fails):
    c = cls_of(key)
    if c and c[0] != "?":
        byclass[c[0]] = byclass.get(c[0], 0) + 1
    else:
        unclassified.append(key)
ok_keys = {r[0] for r in results if r[1] == "ok"}
stale = sorted(k for k in ok_keys if cls_of(k))
if fails:
    print(f"translate: classified {len(fails) - len(unclassified)}" +
          (" (" + ", ".join(f"{c} {n}" for c, n in sorted(byclass.items(), key=lambda x: -x[1])) + ")" if byclass else "") +
          f", unclassified {len(unclassified)}")
for k in stale:
    print(f"stale {k}: classified {cls_of(k)[0]}, and it round-trips")
unclassified = [k for k in unclassified if not cls_of(k)]
if TRIAGE and unclassified:
    os.makedirs(os.path.dirname(CLASSES), exist_ok=True)
    with open(CLASSES, "a") as f:
        for k in unclassified:
            f.write(f"{k.split('/', 1)[1] if k.startswith('run/') else k}\t?\t{fails[k][1]}: {fails[k][2][:120]}\n")
    print(f"translate: {len(unclassified)} added to {os.path.relpath(CLASSES, ROOT)} as ?")
if TWIN:
    reasons = {}
    for r in results:
        if r[3] and r[3][0] == "outside":
            k = re.sub(r"`[^`]*`", "`..`", re.sub(r" at \S+$", "", r[3][1]))[:90]
            reasons[k] = reasons.get(k, 0) + 1
    for k, n in sorted(reasons.items(), key=lambda x: -x[1])[:10]:
        print(f"  twin outside {n}: {k}")
    print(f"translate: {TWIN_NAME}: {twin_tot[0]} of {twin_tot[1]} round-tripped programs agree")
print(f"translate: {tot_ok} of {tot} round-trip"
      + (f"; {TWIN_NAME}: {twin_tot[0]} of {twin_tot[1]} agree" if TWIN else "")
      + f" (translator: {TRANSLATOR or 'identity'})")
PY
