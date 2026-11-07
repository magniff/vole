#!/bin/sh
# Gate 2's round trip (0.27.3, docs/design/rust-surface-plan.md §6): every
# MVS program of a set is translated into the rust edition by a
# translator, compiled with `--edition rust`, run, and its output compared
# with the MVS program's. One count per set, and a cause per failure.
#
# usage: tests/translate.sh [-c COMPILER] [-j N] [-O LEVEL] [-s SETS]
#            [--translator CMD | --identity] [--ref expect|build]
#            [--causes FILE] [--triage] [-f LIST] [-l] [-v] [FILTER...]
#
#   -c COMPILER     the volec to build with (default: target/volec, else
#                   target/tools/volec)
#   -j N            programs at once (default 4)
#   -O LEVEL        the level every program is built at (default 0)
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
#                   COMPILER fix --edition rust). Its exit code 1 with the
#                   root's first line `// EDITION: rust` is a translation
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
OPT=0
SETS=examples,bench,run
TRANSLATOR=""
IDENTITY=0
REF=expect
CLASSES="$ROOT/tests/translate/causes.tsv"
LISTS=""
TRIAGE=0
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
[ -n "$TRANSLATOR" ] || TRANSLATOR="$COMPILER fix --edition rust"
[ $IDENTITY = 1 ] && TRANSLATOR=""
exec python3 -I - "$ROOT" "$COMPILER" "$JOBS" "$OPT" "$SETS" "$TRANSLATOR" "$REF" \
    "$CLASSES" "$TRIAGE" "$LIST" "$VERBOSE" "$LISTS" "$@" <<'PY'
import os
import re
import shlex
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

(ROOT, COMPILER, JOBS, OPT, SETS, TRANSLATOR, REF, CLASSES, TRIAGE, LIST,
 VERBOSE, LISTS) = sys.argv[1:13]
FILTERS = sys.argv[13:]


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
    if s not in ("examples", "bench", "run", "rust"):
        sys.exit(f"tests/translate.sh: no set {s} (examples, bench, run, rust)")


def directives(path):
    """tests/directives.awk's reading: a `//` line's KEY: VALUE."""
    d = {"expect": [], "stdin": [], "env": [], "stderr": [], "csource": [], "flags": [],
         "exit": 0, "timeout": 1, "has": set()}
    try:
        text = open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return d
    for line in text.split("\n"):
        line = line.rstrip("\r").lstrip(" \t")
        if not line.startswith("//"):
            continue
        c = line[2:]
        if c.startswith(" "):
            c = c[1:]
        i = c.find(":")
        if i < 0:
            continue
        key, value = c[:i], c[i + 1:]
        if value.startswith(" "):
            value = value[1:]
        d["has"].add(key)
        if key == "EXPECT":
            d["expect"].append(value)
        elif key == "STDIN":
            d["stdin"].append(value)
        elif key == "ENV":
            d["env"].append(value)
        elif key == "STDERR":
            d["stderr"].append(value)
        elif key == "EXIT":
            d["exit"] = int(value.split()[0]) if value.split() else 0
        elif key == "CSOURCE":
            d["csource"] += value.split()
        elif key == "FLAGS":
            d["flags"] += value.split()
        elif key in ("ARGS", "SOURCE", "CHEADER", "EDITION"):
            d[key.lower()] = value.strip() if key != "ARGS" else value
        elif key == "TIMEOUT":
            try:
                d["timeout"] = max(1, int(value.split()[0]))
            except (ValueError, IndexError):
                pass
    return d


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
                out.append(("bench", name, p, None, directives(p), False))
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


def trimmed(text):
    return re.sub(r"[ \t\r\n]+$", "", text)


NUM = r"[-+]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][-+]?[0-9]+)?"


def same_line(want, got):
    if want == got:
        return True
    if "{num}" not in want and "{int}" not in want and "{..}" not in want:
        return False
    rx = ""
    for part in re.split(r"(\{num\}|\{int\}|\{\.\.\})", want):
        rx += {"{num}": NUM, "{int}": r"[-+]?[0-9]+", "{..}": r".*"}.get(part, re.escape(part))
    return re.fullmatch(rx, got, re.S) is not None


def stdout_differs(want, got):
    """tests/expect.awk's comparison: None, or the first line that differs."""
    want, got = trimmed(want), trimmed(got)
    if want == got:
        return None
    w = want.split("\n") if want else []
    a = got.split("\n") if got else []
    for i in range(max(len(w), len(a))):
        if i >= len(w):
            return f"line {i + 1}: expected the end of the output, got {a[i]!r}"
        if i >= len(a):
            return f"line {i + 1}: expected {w[i]!r}, got the end of the output"
        if not same_line(w[i], a[i]):
            return f"line {i + 1}: expected {w[i]!r}, got {a[i]!r}"
    return None


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
    level = "1" if OPT == "0" and "--check-unsafe" in flags else OPT
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
    """(stdout, stderr, exit code) or None when it ran out of time."""
    env = dict(os.environ)
    for kv in d["env"]:
        k, _, v = kv.replace("@ROOT@", ROOT).partition("=")
        env[k] = v
    args = d.get("args", "").replace("@ROOT@", ROOT).split()
    try:
        p = subprocess.run([prog] + args, input="\n".join(d["stdin"]).encode(), capture_output=True,
                           cwd=cwd, env=env, timeout=60 * d["timeout"])
    except subprocess.TimeoutExpired:
        return None
    dec = lambda b: b.decode("utf-8", errors="replace")
    return dec(p.stdout), dec(p.stderr), p.returncode


def one(prog):
    s, name, entry, copy, d, has_ref = prog
    key = f"{s}/{name}"
    w = os.path.join(WORK, s, name)
    shutil.rmtree(w, ignore_errors=True)
    src = os.path.join(w, "src")
    if copy:
        shutil.copytree(copy, src, symlinks=True)
        mine = os.path.join(src, os.path.relpath(entry, copy))
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
            first = open(mine, encoding="utf-8", errors="replace").readline().strip()
        except OSError:
            first = ""
        if r.returncode != 0 and not (r.returncode == 1 and first == "// EDITION: rust"):
            last = [l for l in (r.stdout + r.stderr).split("\n") if l.strip()]
            return key, "no-translation", f"exit {r.returncode}: " + (last[-1] if last else "")[:160]
    bad = build(mine, w, d, os.path.join(w, "prog"), True, os.path.join(w, "compile.out"))
    if bad:
        return key, bad[0], bad[1][:200]
    if "BUILD" in d["has"]:
        return key, "ok", ""
    r = run_prog(os.path.join(w, "prog"), w, d)
    if r is None:
        return key, "timeout", f"killed after {60 * d['timeout']} s"
    out, err, rc = r
    why = stdout_differs(want[0], out)
    if why:
        return key, "output", why
    if rc != want[1]:
        return key, "exit", f"exit {rc}, expected {want[1]}" + (": " + trimmed(err).split("\n")[-1][:120] if err.strip() else "")
    for m in want[2]:
        if m not in err:
            return key, "stderr", f"no stderr line containing {m!r}"
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
    results = list(ex.map(one, progs))
cls = read_classes()
with open(os.path.join(WORK, "results.tsv"), "w") as f:
    for key, status, why in results:
        cause = status.split(" ", 1)
        f.write(f"{key}\t{'ok' if status == 'ok' else 'fail'}\t{status}\t{why}\n")
for key, status, why in sorted(results):
    if status != "ok":
        c = cls.get(key) or cls.get(key.split("/", 1)[1])
        print(f"FAIL {key}: {status}: {why}" + (f" [{c[0]}]" if c else ""))
    elif VERBOSE:
        print(f"ok   {key}")
tot_ok = tot = 0
for s in SETS:
    rs = [r for r in results if r[0].startswith(s + "/")]
    if not rs and FILTERS:
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
    tot_ok += ok
    tot += len(rs) - refs
# the type and borrowck codes, most frequent first
codes = {}
for r in results:
    if r[1].startswith(("type ", "borrowck ")):
        codes[r[1]] = codes.get(r[1], 0) + 1
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
print(f"translate: {tot_ok} of {tot} round-trip (translator: {TRANSLATOR or 'identity'})")
PY
