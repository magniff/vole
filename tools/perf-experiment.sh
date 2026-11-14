#!/bin/sh
# An experiment's cost in one table (0.30): the compiler of a worktree
# against a baseline compiler, in instructions retired, on the workloads
# every speed claim of 0.29 was made with by hand:
#
#   self-build -O2   the compiler's source built at -O2 (an object), on
#                    one thread (-j1)
#   self-build -O0   the same at -O0
#   check            `volec check` of the compiler's source
#   hello            a hello world built (an object)
#   std_heavy        tests/cost/std_heavy.vl built (most of std read)
#   regions          `volec check` of tests/cost/regions_heavy.vl
#
# Each is run by both compilers on the same input, RUNS times, and the
# row is each side's fewest: instructions hardly move with the machine's
# load, where times do. The source both compile is a copy of the
# worktree's compiler/src (without compiler/std beside it: each compiler
# reads the std built into it), or -s SRC's.
#
# usage: tools/perf-experiment.sh [-b BASELINE] [-n RUNS] [-s SRC] [--build]
#                                 [--passes] [--bench] [--only ROWS] [WORKTREE]
#
#   WORKTREE      a checkout of vole (default: the one this script is in);
#                 its compiler is WORKTREE/target/volec
#   -c COMPILER   the compiler under test, instead of WORKTREE/target/volec
#   -b BASELINE   the compiler to compare with (default: the previous
#                 release's, from the bootstrap cache of the worktree or
#                 of the main checkout, as tests/affected.sh's cost row)
#   -n RUNS       runs per measurement (default 3)
#   -s SRC        the compiler source both build and check (a directory
#                 with main.vl; default WORKTREE/compiler/src)
#   --build       first `bootstrap/bootstrap.sh --dev --no-suite` in the
#                 worktree (its compiler from its source, fixpoint checked)
#   --passes      after the table, the self-build's phases and optimizer
#                 passes by both compilers and their difference
#                 (tools/perf-diff.sh)
#   --bench       after the table, the benchmarks' run-time instructions
#                 by both compilers (bench/run.sh --instructions)
#   --only ROWS   only the rows named, comma separated (self-O2, self-O0,
#                 check, hello, std_heavy, regions)
#
# A build row is counted by the compiler itself (`--time-passes=
# instructions`: the phases, on its own thread; macOS's thread counter,
# Linux's perf_event_open) when both compilers do; the other rows, and a
# build's when one does not, are the whole process's: /usr/bin/time -l on
# macOS ("instructions retired"); on Linux `perf stat -e instructions:u`
# when perf is there and permitted. A host with neither exits 77.
#
# Prints the load before and after (a loaded machine moves a whole
# process's instructions by some tenths of a percent, the kernel's work
# for it; times by tens), the two compilers, the table, and with a
# difference of 1% or more in a build row the command that splits it by
# pass (tools/perf-diff.sh counts each phase on the compiler's own
# thread, in user mode: the number to trust for a small difference). Exit status: 0; 1 when a workload fails with
# the compiler under test; 2 usage; 77 no counter.
set -u
LC_ALL=C
export LC_ALL
HERE=$(cd "$(dirname "$0")/.." && pwd)
TREE=""
C=""
B=""
RUNS=3
SRC=""
BUILD=0
PASSES=0
BENCH=0
ONLY=""
usage() {
    sed -n '2,49p' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 2
}
while [ $# -gt 0 ]; do
    case "$1" in
        -c) [ $# -ge 2 ] || usage; C=$2; shift ;;
        -b) [ $# -ge 2 ] || usage; B=$2; shift ;;
        -n) [ $# -ge 2 ] || usage; RUNS=$2; shift ;;
        -s) [ $# -ge 2 ] || usage; SRC=$2; shift ;;
        --build) BUILD=1 ;;
        --passes) PASSES=1 ;;
        --bench) BENCH=1 ;;
        --only) [ $# -ge 2 ] || usage; ONLY=",$2," ; shift ;;
        -h|--help) usage ;;
        -*) echo "perf-experiment: unknown option '$1'" >&2; usage ;;
        *) [ -z "$TREE" ] || usage; TREE=$1 ;;
    esac
    shift
done
[ -n "$TREE" ] || TREE=$HERE
TREE=$(cd "$TREE" 2>/dev/null && pwd) || { echo "perf-experiment: no directory $TREE" >&2; exit 2; }
[ -f "$TREE/compiler/src/main.vl" ] || { echo "perf-experiment: $TREE is no vole checkout (no compiler/src/main.vl)" >&2; exit 2; }
if [ $BUILD -eq 1 ]; then
    (cd "$TREE" && bootstrap/bootstrap.sh --dev --no-suite) >"${TMPDIR:-/tmp}/perf-experiment-build.$$" 2>&1 \
        || { tail -5 "${TMPDIR:-/tmp}/perf-experiment-build.$$" >&2; rm -f "${TMPDIR:-/tmp}/perf-experiment-build.$$"
             echo "perf-experiment: the worktree's compiler does not build" >&2; exit 1; }
    rm -f "${TMPDIR:-/tmp}/perf-experiment-build.$$"
fi
[ -n "$C" ] || C="$TREE/target/volec"
case "$C" in /*) ;; *) C="$(pwd)/$C" ;; esac
[ -x "$C" ] || { echo "perf-experiment: no compiler at $C (bootstrap/bootstrap.sh --dev --no-suite there, or --build)" >&2; exit 2; }
# The baseline: the newest release in a bootstrap cache that is not the
# worktree's own HEAD (tests/affected.sh: previous_release).
if [ -z "$B" ]; then
    head=$(git -C "$TREE" rev-parse HEAD 2>/dev/null | cut -c1-12)
    common=$(git -C "$TREE" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
    caches="$TREE/target/bootstrap"
    [ -z "$common" ] || caches="$caches $(dirname "$common")/target/bootstrap"
    for tag in $(cd "$TREE" && sh bootstrap/release-tags.sh 2>/dev/null); do
        for b in $caches; do
            for p in "$b"/*/"$tag"-*/volec; do
                [ -x "$p" ] || continue
                case "$p" in *-"$head"/volec) continue ;; esac
                B=$p
            done
        done
    done
fi
case "$B" in /*|'') ;; *) B="$(pwd)/$B" ;; esac
[ -n "$B" ] && [ -x "$B" ] || { echo "perf-experiment: no baseline compiler (-b BASELINE; bootstrap/bootstrap.sh builds the releases)" >&2; exit 2; }
[ -n "$SRC" ] || SRC="$TREE/compiler/src"
[ -f "$SRC/main.vl" ] || { echo "perf-experiment: no $SRC/main.vl" >&2; exit 2; }

# The counter.
COUNTER=""
if /usr/bin/time -l true 2>&1 | grep -q 'instructions retired'; then
    COUNTER=time
elif command -v perf >/dev/null 2>&1 && perf stat -x, -e instructions:u true 2>&1 | grep -q 'instructions'; then
    COUNTER=perf
else
    echo "perf-experiment: this host counts no instructions (/usr/bin/time -l on macOS, perf stat on Linux)"
    exit 77
fi

W=$(mktemp -d "${TMPDIR:-/tmp}/vole-perf.XXXXXX")
trap 'rm -rf "$W"' EXIT
trap 'exit 130' INT TERM
printf 'fn main() {\n    println("hello");\n}\n' >"$W/hello.vl"
cp "$TREE/tests/cost/std_heavy.vl" "$W/std_heavy.vl" 2>/dev/null || true
cp "$TREE/tests/cost/regions_heavy.vl" "$W/regions_heavy.vl" 2>/dev/null || true
mkdir -p "$W/src"
cp -R "$SRC/." "$W/src/"
VOLE_CACHE=off
VOLE_CODE_CACHE=off
export VOLE_CACHE VOLE_CODE_CACHE

# The fewest instructions of $RUNS runs of the command (in $W), or
# nothing when it fails.
count() {
    best=""
    i=0
    while [ $i -lt "$RUNS" ]; do
        if [ "$COUNTER" = time ]; then
            (cd "$W" && /usr/bin/time -l "$@" >/dev/null 2>"$W/time.out") || return 1
            n=$(awk '/instructions retired/ { print $1 }' "$W/time.out")
        else
            (cd "$W" && perf stat -x, -e instructions:u -o "$W/time.out" "$@" >/dev/null 2>&1) || return 1
            n=$(awk -F, '/instructions/ { print $1 }' "$W/time.out")
        fi
        [ -n "$n" ] || return 1
        if [ -z "$best" ] || [ "$n" -lt "$best" ]; then best=$n; fi
        i=$((i + 1))
    done
    echo "$best"
}

# The same for a build, by the compiler's own counter: the total of
# `--time-passes=instructions` (0.25.5 on), the phases' instructions on
# the compiler's thread in user mode, in millions as it prints them.
# Nothing when the compiler or the system does not count so.
count_phases() {
    best=""
    i=0
    while [ $i -lt "$RUNS" ]; do
        (cd "$W" && "$@" >/dev/null 2>"$W/time.out") || return 1
        n=$(sed -n 's/^\([0-9][0-9]*\) M  total (instructions retired)$/\1/p' "$W/time.out" | head -1)
        [ -n "$n" ] || return 1
        if [ -z "$best" ] || [ "$n" -lt "$best" ]; then best=$n; fi
        i=$((i + 1))
    done
    echo "$((best * 1000000))"
}

FAILED=0
SPLIT=""
# <row> <label> <is a build: 1|0> <command args...>
measure() {
    row=$1
    label=$2
    build=$3
    shift 3
    case "$ONLY" in ''|*",$row,"*) ;; *) return ;; esac
    # (a build: both compilers' own phase counts when both give them,
    # which a loaded machine does not move; else the process's)
    how=""
    if [ "$build" = 1 ] && new=$(count_phases "$C" --time-passes=instructions "$@") \
        && old=$(count_phases "$B" --time-passes=instructions "$@"); then
        how="  (the phases)"
    else
        new=$(count "$C" "$@") || { printf '%-16s %12s %12s   fails with the compiler under test (%s)\n' "$label" "-" "-" "$*"; FAILED=1; return; }
        old=$(count "$B" "$@") || { printf '%-16s %12s %12.1f   the baseline cannot do it\n' "$label" "-" "$(awk -v n="$new" 'BEGIN { print n / 1e6 }')"; return; }
    fi
    awk -v l="$label" -v a="$old" -v b="$new" -v h="$how" 'BEGIN {
        printf "%-16s %12.1f %12.1f %+11.1f %+7.2f%%%s\n", l, a / 1e6, b / 1e6, (b - a) / 1e6, 100 * (b - a) / a, h
    }'
    if [ "$build" = 1 ] && awk -v a="$old" -v b="$new" 'BEGIN { d = (b - a) / a; exit !(d >= 0.01 || d <= -0.01) }'; then
        SPLIT="$SPLIT $row"
    fi
}

echo "perf-experiment: $C"
echo "       against: $B"
echo "        source: $SRC ($(find "$W/src" -name '*.vl' | wc -l | tr -d ' ') files), the fewest of $RUNS runs, counted by $([ $COUNTER = time ] && echo '/usr/bin/time -l' || echo 'perf stat')"
echo "          load: $(uptime | sed 's/.*load averages*: //')"
printf '%-16s %12s %12s %11s %8s\n' "workload" "baseline (M)" "tested (M)" "diff (M)" "diff"
# (A build row is the phases' total by the compiler's own counter,
# `--time-passes=instructions`, which runs on one thread and counts it in
# user mode: marked `(the phases)`. The whole process's count, the
# kernel's work for it included, moved with the machine: at load 10 to 27
# it said +0.5% and +0.8% for two compilers whose phases differ by -0.2%.
# The check rows are the process's: a release before 0.30 counts no
# instructions in `check`.)
measure self-O2 "self-build -O2" 1 --no-cache -j1 src/main.vl -c -o out.o
measure self-O0 "self-build -O0" 1 --no-cache -j1 -O0 src/main.vl -c -o out.o
measure check "check" 0 check src/main.vl
measure hello "hello" 1 hello.vl -c -o hello.o
[ ! -f "$W/std_heavy.vl" ] || measure std_heavy "std_heavy" 1 std_heavy.vl -c -o std_heavy.o
[ ! -f "$W/regions_heavy.vl" ] || measure regions "regions" 0 check regions_heavy.vl
echo "    load after: $(uptime | sed 's/.*load averages*: //')"
for row in $SPLIT; do
    case "$row" in
        self-O2) echo "by pass: tools/perf-diff.sh $B $C $SRC/main.vl" ;;
        self-O0) echo "by pass: tools/perf-diff.sh -O0 $B $C $SRC/main.vl" ;;
        std_heavy) echo "by pass: tools/perf-diff.sh $B $C tests/cost/std_heavy.vl" ;;
    esac
done
if [ $PASSES -eq 1 ]; then
    echo
    (cd "$W" && sh "$HERE/tools/perf-diff.sh" --min 20 "$B" "$C" src/main.vl) || FAILED=1
fi
if [ $BENCH -eq 1 ]; then
    echo
    sh "$TREE/bench/run.sh" --instructions -c "$C" -p "$B" -r "$RUNS" || FAILED=1
fi
exit $FAILED
