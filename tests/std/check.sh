#!/bin/sh
# The gate's std-check row (0.27.2, borrowck.md Z7): std's bodies are
# checked bodies. `volec --std-check` on a rust program that names
# nothing type-checks every non-generic std function and each template's
# region-free instance (i64, or Gpa for an allocator), and runs the borrow
# checker on every body that type-checked; then each std case
# (tests/run/std_*.vl) is compiled with it, which solves the instances
# the case makes.
#
# Prints `std-check: N bodies: C clean, E with borrowck errors, F failed
# the type check, U not solved; cases: K, B with borrowck errors in std`.
#
# (0.27.2) The row fails on E, F, and B, a passing case's borrowck error
# in std. It prints U, the bodies whose region-free instance does not
# type-check (an i64 or Gpa stand-in for a bound it cannot meet), and X,
# the XFAIL cases with borrowck errors in std (rustc's implied outlives
# bounds, 0.27.2.1), as known gaps, without failing on them.
#
# usage: tests/std/check.sh [-c COMPILER] [-n] [-r RESULTS] [-v]
#   -c COMPILER   the volec to run (default: target/volec)
#   -n            the region-free run only, not the cases
#   -r RESULTS    (0.27.2.1) a suite run's case results (tests/run.sh's
#                 VOLE_TEST_RESULTS, the gate's suite-O0 row): the cases it
#                 passed are not compiled again (that compile had no error,
#                 and solved every body it reached, std's too); only the
#                 others are, the XFAIL ones
#   -v            print each failing case's tally and borrowck errors
set -u
LC_ALL=C
export LC_ALL
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
C="$ROOT/target/volec"
CASES=1
RESULTS=""
VERBOSE=0
while [ $# -gt 0 ]; do
    case "$1" in
        -c) [ $# -ge 2 ] || exit 2; C=$2; shift ;;
        -n) CASES=0 ;;
        -r) [ $# -ge 2 ] || exit 2; RESULTS=$2; shift ;;
        -v) VERBOSE=1 ;;
        *) echo "usage: tests/std/check.sh [-c COMPILER] [-n] [-r RESULTS] [-v]" >&2; exit 2 ;;
    esac
    shift
done
case "$C" in /*) ;; *) C="$(pwd)/$C" ;; esac
[ -x "$C" ] || { echo "std-check: no compiler at $C"; exit 2; }
T=$(mktemp -d "${TMPDIR:-/tmp}/stdcheck.XXXXXX")
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/p"
printf 'fn main() {}\n' > "$T/p/main.vl"
(cd "$T/p" && "$C" --std-check --max-errors=0 main.vl -c -o "$T/p/main.o") \
    > "$T/first.out" 2> "$T/first.err"
tally=$(grep '^std-check: ' "$T/first.out" | tail -1)
if [ -z "$tally" ]; then
    echo "std-check: FAIL: no tally from the region-free run"
    head -5 "$T/first.err"
    exit 1
fi
set -- $(echo "$tally" | sed 's/^std-check: //; s/[^0-9 ]//g')
N=$1 CL=$2 E=$3 F=$4 U=$5 NC=$6
[ $VERBOSE -eq 1 ] && grep 'error\[borrowck' "$T/first.err"
K=0
B=0
X=0
if [ $CASES -eq 1 ]; then
    # (4 at a time: each case's run writes the borrowck errors at std
    # positions, `<std>:L:C`, to its own file)
    mkdir -p "$T/cases"
    if [ -n "$RESULTS" ]; then
        # (0.27.2.1) the cases the suite passed: each compiled without an
        # error, and a compile with no type error solves every body it
        # reaches, std's included; the others (XFAIL ones: a type error
        # stops a compile before the borrow checker) as below
        set -- $(awk '$1 ~ /^std_/ && $2 == "pass" { k++; if ($3 > 0) b++ } END { print k + 0, b + 0 }' "$RESULTS")
        K=$1 B=$2
        awk '$1 ~ /^std_/ && $2 != "pass" { print $1 }' "$RESULTS" |
            while read -r n; do echo "$ROOT/tests/run/$n.vl"; done >"$T/list"
    else
        ls "$ROOT"/tests/run/std_*.vl >"$T/list" 2>/dev/null
    fi
    awk '{ print NR " " $0 }' "$T/list" | xargs -P 4 -n 2 sh -c '
        # ($0 the work directory, $1 the compiler, $2 the number, $3 the case)
        out=$(cd "$0" && "$1" --std-check --max-errors=0 "$3" -c -o "$0/cases/$2.o" 2>&1)
        echo "$out" | grep "^<std>:[0-9]*:[0-9]*: error\[borrowck" > "$0/cases/$2.bck"
        echo "$3" > "$0/cases/$2.name"
        rm -f "$0/cases/$2.o"' "$T" "$C"
    for b in "$T"/cases/*.name; do
        [ -f "$b" ] || continue
        K=$((K + 1))
        e=${b%.name}.bck
        if [ -s "$e" ] && grep -q '^// XFAIL' "$(cat "$b")"; then
            X=$((X + 1))
        elif [ -s "$e" ]; then
            B=$((B + 1))
            if [ $VERBOSE -eq 1 ]; then
                echo "$(cat "$b"):"
                head -3 "$e"
            fi
        fi
    done
fi
line="std-check: $N bodies: $CL clean, $E with borrowck errors, $F failed the type check, $U not solved, $NC not checked; cases: $K, $B with borrowck errors in std; known gaps: $U not solved, $X XFAIL cases with borrowck errors in std"
if [ "$E" -eq 0 ] && [ "$F" -eq 0 ] && [ "$B" -eq 0 ]; then
    echo "$line"
    exit 0
fi
echo "$line (FAIL)"
exit 1
