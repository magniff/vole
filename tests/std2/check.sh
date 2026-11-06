#!/bin/sh
# The gate's std2-check row (0.27.2, borrowck.md Z7): std2's bodies are
# checked bodies. `volec --std2-check` on a rust program that names
# nothing type-checks every non-generic std2 function and each template's
# region-free instance (i64, or Gpa for an allocator), and runs the borrow
# checker on every body that type-checked; then each std2 case
# (tests/run/std2_*.vl) is compiled with it, which solves the instances
# the case makes. The row passes when the first run's tally has no error
# of either kind and no body left unsolved, and no case's run reports a
# borrowck error in a std2 body.
#
# Prints `std2-check: N bodies: C clean, E with borrowck errors, F failed
# the type check, U not solved; cases: K, B with borrowck errors in std2`.
#
# usage: tests/std2/check.sh [-c COMPILER] [-n] [-v]
#   -c COMPILER   the volec to run (default: target/volec)
#   -n            the region-free run only, not the cases
#   -v            print each failing case's tally and borrowck errors
set -u
LC_ALL=C
export LC_ALL
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
C="$ROOT/target/volec"
CASES=1
VERBOSE=0
while [ $# -gt 0 ]; do
    case "$1" in
        -c) [ $# -ge 2 ] || exit 2; C=$2; shift ;;
        -n) CASES=0 ;;
        -v) VERBOSE=1 ;;
        *) echo "usage: tests/std2/check.sh [-c COMPILER] [-n] [-v]" >&2; exit 2 ;;
    esac
    shift
done
case "$C" in /*) ;; *) C="$(pwd)/$C" ;; esac
[ -x "$C" ] || { echo "std2-check: no compiler at $C"; exit 2; }
T=$(mktemp -d "${TMPDIR:-/tmp}/std2check.XXXXXX")
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/p"
printf '// EDITION: rust\nfn main() {}\n' > "$T/p/main.vl"
(cd "$T/p" && VOLE_STD2=1 "$C" --edition rust --std2-check --max-errors=0 main.vl -c -o "$T/p/main.o") \
    > "$T/first.out" 2> "$T/first.err"
tally=$(grep '^std2-check: ' "$T/first.out" | tail -1)
if [ -z "$tally" ]; then
    echo "std2-check: FAIL: no tally from the region-free run"
    head -5 "$T/first.err"
    exit 1
fi
set -- $(echo "$tally" | sed 's/^std2-check: //; s/[^0-9 ]//g')
N=$1 CL=$2 E=$3 F=$4 U=$5 NC=$6
[ $VERBOSE -eq 1 ] && grep 'error\[borrowck' "$T/first.err"
K=0
B=0
if [ $CASES -eq 1 ]; then
    # (4 at a time: each case's run writes the borrowck errors at std2
    # positions, `<std>:L:C`, to its own file)
    mkdir -p "$T/cases"
    ls "$ROOT"/tests/run/std2_*.vl 2>/dev/null | awk '{ print NR " " $0 }' | xargs -P 4 -n 2 sh -c '
        # ($0 the work directory, $1 the compiler, $2 the number, $3 the case)
        out=$(cd "$0" && VOLE_STD2=1 "$1" --edition rust --std2-check --max-errors=0 "$3" -c -o "$0/cases/$2.o" 2>&1)
        echo "$out" | grep "^<std>:[0-9]*:[0-9]*: error\[borrowck" > "$0/cases/$2.bck"
        echo "$3" > "$0/cases/$2.name"
        rm -f "$0/cases/$2.o"' "$T" "$C"
    for b in "$T"/cases/*.name; do
        [ -f "$b" ] || continue
        K=$((K + 1))
        e=${b%.name}.bck
        if [ -s "$e" ]; then
            B=$((B + 1))
            if [ $VERBOSE -eq 1 ]; then
                echo "$(cat "$b"):"
                head -3 "$e"
            fi
        fi
    done
fi
line="std2-check: $N bodies: $CL clean, $E with borrowck errors, $F failed the type check, $U not solved, $NC not checked; cases: $K, $B with borrowck errors in std2"
if [ "$E" -eq 0 ] && [ "$F" -eq 0 ] && [ "$U" -eq 0 ] && [ "$B" -eq 0 ]; then
    echo "$line"
    exit 0
fi
echo "$line (FAIL)"
exit 1
