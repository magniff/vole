#!/bin/sh
# Benchmarks: every bench/*.vl (and examples/md5/main.vl over 8 MB) compiled
# by vole at -O0, -O1 and -O2, by the previous release and the seed when
# given, and the C equivalents (bench/*.c) by cc -O2. Prints the fastest of
# RUNS runs of each, in milliseconds, and checks that all outputs agree;
# then, for each variant, the geometric mean over the programs with a C
# version of its time divided by cc -O2's (below 1: faster than C);
# last (0.14), the time of bench/iterchain.vl (iterator chains) over
# that of bench/iterloop.vl (the same loops by hand) at -O2, which fails
# the run above 1.05, and (0.15) the same for bench/fmtloop.vl
# (f-strings) over bench/fmtints.vl (Buf's push_int), and (0.16) for
# bench/purecall.vl (calls of pure functions left in loops) over
# bench/purecall_hoisted.vl (hoisted and merged by hand). Those ratios are
# measured on their own, robust to a busy machine: the two -O2 programs
# run alternately, RUNS rounds of one run each, and each side's time is
# its fastest round.
#
# usage: bench/run.sh [-c COMPILER] [-p PREVIOUS] [-s SEED] [-r RUNS] [-t TARGET]
#
#   -c COMPILER   the volec to measure (default: target/volec)
#   -p PREVIOUS   another volec (e.g. the previous release), at its
#                 default level
#   -s SEED       the seed binary (`vole build -O`)
#   -r RUNS       runs per measurement (default 5)
#   -t TARGET     the target (default: the host)
#
# (0.29) A run that fails ends with one line that says which program and
# why, `bench: PROGRAM VARIANT: ...` (a program that does not build with
# the compiler measured, or stops: its exit status or signal and the last
# line it wrote to stderr, a panic's message; an output that differs; a
# ratio above its bound), or, for anything else, `bench: failed (exit N)
# while ...`: bootstrap/gate.sh's bench row shows that line. In 0.28.0 a
# program that panicked ended the run in the middle of its row, and the
# gate's row was empty.

set -eu
LC_ALL=C
export LC_ALL
ROOT=$(cd "$(dirname "$0")/.." && pwd)
COMPILER="$ROOT/target/volec"
PREVIOUS=""
SEED=""
RUNS=5
TARGET=""
CC=${CC:-cc}
while [ $# -gt 0 ]; do
    case "$1" in
        -c) COMPILER=$2; shift 2 ;;
        -p) PREVIOUS=$2; shift 2 ;;
        -s) SEED=$2; shift 2 ;;
        -r) RUNS=$2; shift 2 ;;
        -t) TARGET=$2; shift 2 ;;
        *) sed -n '2,34p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
    esac
done
if [ -z "$TARGET" ]; then
    case "$(uname -s)-$(uname -m)" in
        Darwin-arm64) TARGET=aarch64-macos ;;
        Darwin-x86_64) TARGET=x86_64-macos ;;
        Linux-x86_64) TARGET=x86_64-linux ;;
        *) echo "bench: unknown host" >&2; exit 2 ;;
    esac
fi
case "$TARGET" in
    aarch64-macos) ARCH="-arch arm64"; SEED_TARGET=macos-aarch64 ;;
    x86_64-macos) ARCH="-arch x86_64"; SEED_TARGET=macos-x86_64 ;;
    *) ARCH=""; SEED_TARGET=linux-x86_64 ;;
esac

WORK=$(mktemp -d "${TMPDIR:-/tmp}/vole-bench.XXXXXX")
# (0.29) the last line of a failed run: fail's, or what was being done
SAID=0
STAGE="starting"
fail() {
    echo
    echo "bench: $*"
    SAID=1
    exit 1
}
trap 'rc=$?; [ $rc -eq 0 ] || [ $SAID -eq 1 ] || { echo; echo "bench: failed (exit $rc) while $STAGE"; }; rm -rf "$WORK"' EXIT
trap 'exit 130' INT TERM
# Times command $5 as timer does (RUNS INPUT OUTPUT command), printing
# the milliseconds. When the program stops: false, and $WORK/why says
# which ($1) and how, the last line it wrote to stderr (a panic's
# message) and timer's (its exit status or signal); the caller, not in a
# `$(...)`, fails the run with it: `ms=$(timed ...) || fail "$(cat "$WORK/why")"`.
timed() { # <what> <runs> <input> <output> <command>
    td_what=$1
    shift
    "$WORK/timer" "$@" 2>"$WORK/timed.err" && return 0
    echo "$td_what: the program failed: $(sed "s|$WORK/||g" "$WORK/timed.err" | grep -v '^$' | tail -2 | tr '\n' ' ' | sed 's/ $//')" >"$WORK/why"
    return 1
}
STAGE="building bench/timer.c"
# shellcheck disable=SC2086
"$CC" -O2 -o "$WORK/timer" "$ROOT/bench/timer.c"
dd if=/dev/zero of="$WORK/md5.in" bs=1048576 count=8 2>/dev/null
: >"$WORK/empty"
: >"$WORK/times"

# Builds variant $2 of program $1 (a .vl file) into $3; fails when that
# compiler does not know the program's language (the previous release and
# the seed do not know what came after them).
build() {
    case "$2" in
        # (from 0.7 the compiler writes objects; the previous release may
        # only write assembly)
        # (0.18.1: a build's `ok:` line is not the table's; its errors are
        # shown when it fails)
        O0|O1|O2) "$COMPILER" --target "$TARGET" "-$2" "$1" -o "$3.o" >"$3.out" 2>&1 \
                || { cat "$3.out" >&2; return 1; }
            # shellcheck disable=SC2086
            "$CC" $ARCH -o "$3" "$3.o" -lm
            return ;;
        previous) "$PREVIOUS" --target "$TARGET" "$1" -o "$3.s" >/dev/null 2>&1 || return 1 ;;
        seed)
            # The seed knows only 0.2's declarations of C functions.
            awk -f "$ROOT/tests/seed-compat.awk" "$1" >"$3.vl"
            "$SEED" build -O --target "$SEED_TARGET" "$3.vl" -o "$3" >/dev/null 2>&1
            return ;;
    esac
    # shellcheck disable=SC2086
    "$CC" $ARCH -o "$3" "$3.s" -lm
}

VARIANTS="O0 O1 O2"
[ -n "$PREVIOUS" ] && VARIANTS="previous $VARIANTS"
[ -n "$SEED" ] && VARIANTS="$VARIANTS seed"
printf "%-10s" "program"
for v in $VARIANTS; do printf " %9s" "$v"; done
printf " %9s\n" "cc -O2"

for source in "$ROOT"/bench/*.vl "$ROOT/examples/md5/main.vl"; do
    name=$(basename "$source" .vl)
    # (an example is a directory: its name)
    [ "$name" = main ] && name=$(basename "$(dirname "$source")")
    input="$WORK/empty"
    [ "$name" = md5 ] && input="$WORK/md5.in"
    printf "%-10s" "$name"
    reference=""
    row=""
    for v in $VARIANTS; do
        STAGE="building $name $v"
        if ! build "$source" "$v" "$WORK/$name.$v"; then
            # (0.29) the compiler measured builds every program; the
            # previous release and the seed may not know its language
            case "$v" in
                O0|O1|O2) fail "$name $v: does not build: $(grep -m1 -i 'error' "$WORK/$name.$v.out" 2>/dev/null || echo "the link failed")" ;;
            esac
            printf " %9s" "-"
            row="$row -"
            continue
        fi
        ms=$(timed "$name $v" "$RUNS" "$input" "$WORK/$name.$v.out" "$WORK/$name.$v") || fail "$(cat "$WORK/why")"
        printf " %9s" "$ms"
        row="$row $ms"
        if [ "$v" = O2 ]; then
            case "$name" in
                iterchain) CHAIN_MS=$ms ;;
                iterloop) LOOP_MS=$ms ;;
                fmtloop) FMT_MS=$ms ;;
                fmtints) INTS_MS=$ms ;;
                purecall) PURE_MS=$ms ;;
                purecall_hoisted) HOISTED_MS=$ms ;;
            esac
        fi
        if [ -z "$reference" ]; then
            reference="$WORK/$name.$v.out"
        elif ! cmp -s "$reference" "$WORK/$name.$v.out"; then
            fail "$name $v: the output differs from $(basename "$reference" .out | sed "s/^$name\.//")'s"
        fi
    done
    c="$ROOT/bench/$name.c"
    if [ -f "$c" ]; then
        # shellcheck disable=SC2086
        STAGE="building bench/$name.c with $CC -O2"
        "$CC" $ARCH -O2 -o "$WORK/$name.c.bin" "$c" -lm
        ms=$(timed "$name cc -O2" "$RUNS" "$input" "$WORK/$name.c.out" "$WORK/$name.c.bin") || fail "$(cat "$WORK/why")"
        cmp -s "$reference" "$WORK/$name.c.out" || fail "$name cc -O2: the C program's output differs"
        STAGE="the table"
        printf " %9s\n" "$ms"
        echo "$row $ms" >>"$WORK/times"
    else
        printf " %9s\n" "-"
    fi
done

# The geometric means of the ratios to cc -O2 (a time of 0 counts as 1 ms).
STAGE="the geometric means"
printf "%-10s" "geomean"
awk -v n="$(echo $VARIANTS | wc -w)" '
    { c = $NF < 1 ? 1 : $NF
      for (i = 1; i <= n; i++) if ($i != "-") { t = $i < 1 ? 1 : $i; sum[i] += log(t / c); cnt[i]++ } }
    END { for (i = 1; i <= n; i++) {
              if (cnt[i] > 0) printf " %9.3f", exp(sum[i] / cnt[i]); else printf " %9s", "-" }
          printf " %9s\n", "1" }' "$WORK/times"

# (0.14) Iterator chains against the same loops written by hand, at -O2:
# zero cost is a ratio of 1; above 1.05 is a failure. The two run
# alternately, the fastest of RUNS rounds each (noise from other work on
# the machine hits both sides alike, and the minimum drops most of it).
# (0.15) The same for f-strings (bench/fmtloop.vl) against the text
# made by hand with Buf's push_int (bench/fmtints.vl).
# usage: ratio NAME MS OTHER OTHER_MS WHAT
ratio() {
    STAGE="the ratio $1/$3"
    a_ms=$2
    b_ms=$4
    round=0
    while [ $round -lt "$RUNS" ]; do
        ms=$(timed "$1 O2" 1 "$WORK/empty" "$WORK/$1.round.out" "$WORK/$1.O2") || fail "$(cat "$WORK/why")"
        [ "$ms" -lt "$a_ms" ] && a_ms=$ms
        ms=$(timed "$3 O2" 1 "$WORK/empty" "$WORK/$3.round.out" "$WORK/$3.O2") || fail "$(cat "$WORK/why")"
        [ "$ms" -lt "$b_ms" ] && b_ms=$ms
        round=$((round + 1))
    done
    printf "%-10s %9s %9s\n" "$1" "$a_ms" "(min of $((RUNS * 2)))"
    printf "%-10s %9s\n" "$3" "$b_ms"
    r=$(awk -v a="$a_ms" -v b="$b_ms" 'BEGIN { if (b < 1) b = 1; if (a < 1) a = 1; printf "%.3f", a / b }')
    printf "%-10s %9s\n" "$1/$3" "$r"
    if awk -v r="$r" 'BEGIN { exit !(r > 1.05) }'; then
        fail "$1/$3 is $r, above 1.05: $5 are not zero cost"
    fi
}
if [ -n "${CHAIN_MS:-}" ] && [ -n "${LOOP_MS:-}" ]; then
    ratio iterchain "$CHAIN_MS" iterloop "$LOOP_MS" "iterator chains"
fi
if [ -n "${FMT_MS:-}" ] && [ -n "${INTS_MS:-}" ]; then
    ratio fmtloop "$FMT_MS" fmtints "$INTS_MS" "f-strings"
fi
if [ -n "${PURE_MS:-}" ] && [ -n "${HOISTED_MS:-}" ]; then
    ratio purecall "$PURE_MS" purecall_hoisted "$HOISTED_MS" "calls of pure functions"
fi
