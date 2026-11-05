#!/bin/sh
# The checks survey (0.27.1, the gate record's; the first since 0.18.1's
# in docs/optimizer.md, "The survey"): every bench/*.vl and every
# example's main.vl built at -O2 with --print-checks, and the run-time
# checks (index, slice, contract, ...) each site of which the build left
# or removed, summed: in all, in user code and in std, by what removed
# them (ranges or otherwise) and by kind.
#
# usage: tools/checks-survey.sh [-c COMPILER] [-j JOBS] [PROGRAM...]
#
# A program that does not build (it needs a C toolchain's library, a
# framework, its own build step) is left out and named; one broken on
# purpose (`// premerge: broken on purpose`) is not tried. Prints the
# table's rows, then `checks-survey: N programs, LEFT left / REMOVED
# removed`.

ROOT=$(cd "$(dirname "$0")/.." && pwd)
COMPILER="$ROOT/target/volec"
JOBS=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)
while [ $# -gt 0 ]; do
    case "$1" in
        -c) COMPILER=$2; shift ;;
        -j) JOBS=$2; shift ;;
        -h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "checks-survey: unknown option $1" >&2; exit 2 ;;
        *) break ;;
    esac
    shift
done
case "$COMPILER" in /*) ;; *) COMPILER="$(pwd)/$COMPILER" ;; esac
[ -x "$COMPILER" ] || { echo "checks-survey: no compiler at $COMPILER" >&2; exit 2; }
if [ $# -eq 0 ]; then
    set -- "$ROOT"/bench/*.vl
    for m in "$ROOT"/examples/*/main.vl "$ROOT"/examples/*/*/main.vl; do
        [ -f "$m" ] || continue
        grep -q '^// premerge: broken on purpose' "$m" && continue
        set -- "$@" "$m"
    done
fi
WORK=$(mktemp -d "${TMPDIR:-/tmp}/checks-survey.XXXXXX") || exit 2
trap 'rm -rf "$WORK"' EXIT INT TERM

for p in "$@"; do echo "$p"; done >"$WORK/list"
cat >"$WORK/one.sh" <<'EOF'
p=$1; C=$2; W=$3
k=$(printf '%s' "$p" | cksum | awk '{ print $1 }')
if (cd "$(dirname "$p")" && "$C" -O2 --print-checks "$(basename "$p")" -o "$W/$k.bin") >"$W/$k.out" 2>&1; then
    awk -F'\t' -v prog="$p" 'NF == 4 { split($1, a, ":"); print prog "\t" (a[1] == "<std>" ? "std" : "user") "\t" $3 "\t" $4 }' "$W/$k.out" >"$W/$k.rows"
else
    echo "$p" >"$W/$k.failed"
fi
rm -f "$W/$k.bin"
EOF
xargs -P "$JOBS" -I{} sh "$WORK/one.sh" {} "$COMPILER" "$WORK" <"$WORK/list"
cat "$WORK"/*.rows 2>/dev/null >"$WORK/all"
N=$(cat "$WORK"/*.rows 2>/dev/null | cut -f1 | sort -u | wc -l | tr -d ' ')
cat "$WORK"/*.failed 2>/dev/null | sed "s|^$ROOT/||" | sort >"$WORK/failed"
awk -F'\t' -v n="$N" '
    { how = ($4 == "left" ? "left" : ($4 ~ /ranges/ ? "ranges" : "other"))
      t[how]++; w[$2, how]++; k[$3, how]++; kinds[$3] = 1 }
    END {
        printf "  %-14s %7s %9s %9s\n", "", "left", "ranges", "otherwise"
        printf "  %-14s %7d %9d %9d\n", "all", t["left"], t["ranges"], t["other"]
        printf "  %-14s %7d %9d %9d\n", "user code", w["user", "left"], w["user", "ranges"], w["user", "other"]
        printf "  %-14s %7d %9d %9d\n", "std", w["std", "left"], w["std", "ranges"], w["std", "other"]
        for (x in kinds) printf "  %-14s %7d %9d %9d\n", "kind " x, k[x, "left"], k[x, "ranges"], k[x, "other"]
        printf "checks-survey: %d programs, %d left / %d removed\n", n, t["left"], t["ranges"] + t["other"]
    }' "$WORK/all"
if [ -s "$WORK/failed" ]; then
    echo "  left out (they do not build here): $(tr '\n' ' ' <"$WORK/failed")"
fi
