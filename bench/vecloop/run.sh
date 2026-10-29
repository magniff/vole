#!/bin/sh
# bench/vecloop (0.25.4): std's Vec against the compiler's older idiom,
# kernel by kernel (docs/design/modernize-0254.md §2; docs/optimizer.md,
# "0.25.4: Vec facts"). vec.vl and raw.vl are the same program, on a
# Vec<i64> and a static Vec<Node, Heap>, and on an IntVec-like struct
# and a raw static table; they print the same lines. Each is built at
# -O2, the outputs compared, then each kernel run alone (`vec K`: its
# CPU time on stderr), the two programs alternately, RUNS rounds, and the
# fastest of each printed, with the load average before and after. With
# -s DIR, the assembly of both (DIR/vec.s, DIR/raw.s) is kept: the
# evidence, as timings under load are not.
#
# usage: bench/vecloop/run.sh [-c COMPILER] [-r RUNS] [-s DIR]
set -eu
LC_ALL=C
export LC_ALL
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
COMPILER="$ROOT/target/volec"
RUNS=5
ASM=""
while [ $# -gt 0 ]; do
    case "$1" in
        -c) COMPILER=$2; shift 2 ;;
        -r) RUNS=$2; shift 2 ;;
        -s) ASM=$2; shift 2 ;;
        *) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
    esac
done
WORK=$(mktemp -d "${TMPDIR:-/tmp}/vole-vecloop.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
for p in vec raw; do
    "$COMPILER" -O2 "$HERE/$p.vl" -o "$WORK/$p" >/dev/null 2>&1 \
        || { echo "vecloop: $p.vl does not build" >&2; exit 1; }
    if [ -n "$ASM" ]; then
        mkdir -p "$ASM"
        "$COMPILER" -O2 --emit-asm "$HERE/$p.vl" -o "$ASM/$p.s" >/dev/null 2>&1
    fi
    "$WORK/$p" >"$WORK/$p.out"
done
cmp -s "$WORK/vec.out" "$WORK/raw.out" || { echo "vecloop: the outputs differ" >&2; exit 1; }
echo "load: $(uptime | sed 's/.*averages*: //')"
printf "%-8s %8s %8s\n" kernel "Vec ms" "raw ms"
for k in 1 2 3 4 5 6 7 8; do
    best_v=999999
    best_r=999999
    r=0
    while [ $r -lt "$RUNS" ]; do
        v=$("$WORK/vec" $k 2>&1 >/dev/null | sed 's/.*: \([0-9]*\) ms/\1/')
        [ "$v" -lt "$best_v" ] && best_v=$v
        w=$("$WORK/raw" $k 2>&1 >/dev/null | sed 's/.*: \([0-9]*\) ms/\1/')
        [ "$w" -lt "$best_r" ] && best_r=$w
        r=$((r + 1))
    done
    printf "%-8s %8s %8s\n" "$k" "$best_v" "$best_r"
done
echo "load: $(uptime | sed 's/.*averages*: //')"
