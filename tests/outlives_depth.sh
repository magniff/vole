#!/bin/sh
# (0.30.1) A declaration's inferred outlives requirements (D4.6) are found
# once per declaration: compile time stays linear in the depth of
# declarations that name the one before twice. Before, each use walked the
# declaration again, so `struct Si<'a, T> { x: S(i-1)<'a, T>, y:
# S(i-1)<'a, T> }` cost 2^i (depth 25: 26 s to check; depth 32 never
# ended). Three programs, each checked and built within LIMIT seconds
# (they take a tenth of a second; the exponential never ends at depth 60,
# so the limit needs no care for the machine's load):
#
#   d60  60 declarations, each two of the one before: accepted
#   s60  the same, the second with its lifetimes swapped, and a function
#        that needs `T: 'b`, which only the swapped uses imply: accepted
#   e60  s60 with a function that needs `T: 'static`: refused
#        (borrowck.outlives)
#
# usage: tests/outlives_depth.sh [-c COMPILER] [-t LIMIT]
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
C="$ROOT/target/volec"
LIMIT=20
while [ $# -gt 0 ]; do
    case "$1" in
        -c) C=$2; shift ;;
        -t) LIMIT=$2; shift ;;
        *) echo "usage: tests/outlives_depth.sh [-c COMPILER] [-t LIMIT]" >&2; exit 2 ;;
    esac
    shift
done
case "$C" in /*) ;; *) C="$(pwd)/$C" ;; esac
[ -x "$C" ] || { echo "outlives-depth: no compiler $C"; exit 2; }
W=$(mktemp -d "${TMPDIR:-/tmp}/vole-outlives-depth.XXXXXX")
trap 'rm -rf "$W"' EXIT
VOLE_CACHE=off
VOLE_CODE_CACHE=off
export VOLE_CACHE VOLE_CODE_CACHE

# dag DEPTH: S0 .. S<DEPTH>, each two of the one before
dag() {
    echo "struct S0<'a, T> { r: &'a T }"
    i=1
    while [ $i -le "$1" ]; do
        echo "struct S$i<'a, T> { x: S$((i - 1))<'a, T>, y: S$((i - 1))<'a, T> }"
        i=$((i + 1))
    done
    echo "fn f<'a, T>(s: &S$1<'a, T>) -> i64 { let _ = s; 1 }"
    echo "fn main() { println(\"{}\", 1); }"
}
# swapped DEPTH RESULT: the second use swaps the lifetimes; conv returns
# the `&'c i64` its T holds as RESULT
swapped() {
    echo "struct S0<'a, 'b, T> { r: &'a T, q: &'b i64 }"
    i=1
    while [ $i -le "$1" ]; do
        echo "struct S$i<'a, 'b, T> { x: S$((i - 1))<'a, 'b, T>, y: S$((i - 1))<'b, 'a, T> }"
        i=$((i + 1))
    done
    echo "fn conv<'a, 'b, 'c>(s: &S$1<'a, 'b, &'c i64>, r: &'c i64) -> $2 { let _ = s; r }"
    echo "fn main() { println(\"{}\", 1); }"
}
dag 60 >"$W/d60.vl"
swapped 60 "&'b i64" >"$W/s60.vl"
swapped 60 "&'static i64" >"$W/e60.vl"

FAILED=0
# run NAME WANT ARGS...: the command (in $W) within LIMIT seconds, its
# exit status 0 (WANT ok) or refused by borrowck.outlives (WANT refused)
run() {
    name=$1
    want=$2
    shift 2
    (cd "$W" && perl -e 'alarm shift; exec @ARGV or exit 127' "$LIMIT" "$C" "$@" >"$W/out" 2>&1)
    rc=$?
    if [ $rc -eq 142 ]; then
        echo "FAIL outlives-depth $name: not done in $LIMIT s (a declaration walked again for each use?)"
        FAILED=1
    elif [ "$want" = ok ] && [ $rc -ne 0 ]; then
        echo "FAIL outlives-depth $name: exit $rc"
        sed -n '1,5p' "$W/out"
        FAILED=1
    elif [ "$want" = refused ] && ! grep -q 'borrowck.outlives' "$W/out"; then
        echo "FAIL outlives-depth $name: not refused by borrowck.outlives (exit $rc)"
        sed -n '1,5p' "$W/out"
        FAILED=1
    else
        echo "ok outlives-depth $name"
    fi
}
for p in d60 s60; do
    run "check $p" ok check "$p.vl"
    run "build $p" ok "$p.vl" -o "$p"
done
run "check e60" refused check e60.vl
exit $FAILED
