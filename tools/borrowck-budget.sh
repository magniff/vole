#!/bin/sh
# The borrow checker's budget (0.27.1, docs/design/borrowck.md §15): the
# `borrowck` pass of `volec check --time-passes`, summed over the rust
# edition's corpus, against the `check` pass's (typeck: --time-passes
# prints it net of the passes it contains) and their ratio, which is to be
# at most 0.25. Each check runs with VOLE_CACHE=off (the program read in
# full: with the tools' cache, `check` also counts the cache's work).
#
# usage: tools/borrowck-budget.sh [-c COMPILER] [-r RUNS] [CASE...]
#
#   -c COMPILER  the volec to time (default: target/volec)
#   -r RUNS      each case's check is run RUNS times and the least time of
#                each pass kept (default: 1)
#   CASE...      the cases (default: tests/run/rust_*.vl)
#
# Prints the sums, the ratio and the largest case's (by its own check
# time), one line each; a compiler without the borrowck pass prints 0 for
# it. Times under load are not evidence: run it on an idle machine.

ROOT=$(cd "$(dirname "$0")/.." && pwd)
COMPILER="$ROOT/target/volec"
RUNS=1
while [ $# -gt 0 ]; do
    case "$1" in
        -c) COMPILER=$2; shift ;;
        -r) RUNS=$2; shift ;;
        -h|--help) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "borrowck-budget: unknown option $1" >&2; exit 2 ;;
        *) break ;;
    esac
    shift
done
[ -x "$COMPILER" ] || { echo "borrowck-budget: no compiler at $COMPILER" >&2; exit 2; }
[ $# -gt 0 ] || set -- "$ROOT"/tests/run/rust_*.vl
WORK=$(mktemp -d "${TMPDIR:-/tmp}/borrowck-budget.XXXXXX") || exit 2
trap 'rm -rf "$WORK"' EXIT INT TERM

# pass_times FILE: "CHECK BORROWCK" in ms, the least of RUNS runs
pass_times() {
    i=0
    while [ $i -lt "$RUNS" ]; do
        VOLE_CACHE=off "$COMPILER" check --time-passes --allow=borrowck.unchecked "$1" 2>&1
        i=$((i + 1))
    done | awk '
        $2 == "ms" && $3 == "check" && NF == 3 { if (c == "" || $1 < c) c = $1 }
        $2 == "ms" && $3 == "borrowck" { if (b == "" || $1 < b) b = $1 }
        END { printf "%s %s\n", (c == "" ? 0 : c), (b == "" ? 0 : b) }'
}

for f in "$@"; do
    echo "$(basename "$f" .vl) $(pass_times "$f")"
done >"$WORK/rows"
awk '
    { n++; c += $2; b += $3; if (big == "" || $2 > bigc) { big = $1; bigc = $2; bigb = $3 } }
    END {
        printf "borrowck-budget: %d cases\n", n
        printf "  borrowck %10.1f ms\n", b
        printf "  typeck   %10.1f ms\n", c
        printf "  ratio    %10.3f  borrowck / typeck (at most 0.25)\n", (c > 0 ? b / c : 0)
        printf "  largest  %s: borrowck %.1f ms, typeck %.1f ms, ratio %.3f\n", big, bigb, bigc, (bigc > 0 ? bigb / bigc : 0)
    }' "$WORK/rows"
