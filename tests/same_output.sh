#!/bin/sh
# The same-output row (0.27.1, borrowck.md D17.7): every rust-edition case
# that runs (tests/run/rust_t_*.vl and rust_b_ok_*.vl, not XFAIL) prints
# the same output and exits the same at -O0, at -O2 and at -O2 with
# --no-noalias. The parameters' alias facts are the optimizer's only for a
# body the borrow checker passed: a difference is a fact taken where it
# does not hold (0.27.0 took them for every rust body: f(&mut x, &mut x)
# printed 1 at -O2 and 2 at -O0).
#
# usage: tests/same_output.sh [-c COMPILER] [-j JOBS] [CASE...]
#
# A case with ARGS, STDIN, ENV, LINK or REQUIRES is left out (counted).
# Prints one line per difference and `same-output: N cases, D differ, S
# left out`; exits 1 when one differs or fails to build.

ROOT=$(cd "$(dirname "$0")/.." && pwd)
COMPILER="$ROOT/target/volec"
JOBS=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)
while [ $# -gt 0 ]; do
    case "$1" in
        -c) COMPILER=$2; shift ;;
        -j) JOBS=$2; shift ;;
        -h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "same-output: unknown option $1" >&2; exit 2 ;;
        *) break ;;
    esac
    shift
done
case "$COMPILER" in /*) ;; *) COMPILER="$(pwd)/$COMPILER" ;; esac
[ -x "$COMPILER" ] || { echo "same-output: no compiler at $COMPILER" >&2; exit 2; }
[ $# -gt 0 ] || set -- "$ROOT"/tests/run/rust_t_*.vl "$ROOT"/tests/run/rust_b_ok_*.vl
WORK=$(mktemp -d "${TMPDIR:-/tmp}/same-output.XXXXXX") || exit 2
trap 'rm -rf "$WORK"' EXIT INT TERM

: >"$WORK/list"
LEFT=0
for f in "$@"; do
    if grep -qE '^// (ERROR|XFAIL)' "$f"; then continue; fi
    if grep -qE '^// (ARGS|STDIN|ENV|LINK|REQUIRES):' "$f"; then LEFT=$((LEFT + 1)); continue; fi
    echo "$f" >>"$WORK/list"
done

# one case: its three builds and runs; prints a line when they differ
cat >"$WORK/one.sh" <<'EOF'
f=$1; C=$2; W=$3
n=$(basename "$f" .vl); d="$W/$n"; mkdir -p "$d"
flags=$(awk '/^\/\/ FLAGS:/ { sub(/^\/\/ FLAGS: */, ""); printf "%s ", $0 }' "$f")
i=0
for mode in "-O0" "-O2" "-O2 --no-noalias"; do
    i=$((i + 1))
    # shellcheck disable=SC2086
    if ! "$C" $mode --allow=borrowck.unchecked $flags "$f" -o "$d/p$i" >"$d/c$i" 2>&1; then
        echo "FAIL $n: does not build with $mode: $(grep -m 1 error "$d/c$i")"; exit 0
    fi
    (cd "$d" && ./p$i >"$d/o$i" 2>/dev/null; echo "exit $?" >>"$d/o$i")
done
cmp -s "$d/o1" "$d/o2" || echo "DIFF $n: -O0 and -O2 differ: $(diff "$d/o1" "$d/o2" | grep '^[<>]' | head -2 | tr '\n' ' ')"
cmp -s "$d/o2" "$d/o3" || echo "DIFF $n: -O2 and -O2 --no-noalias differ: $(diff "$d/o2" "$d/o3" | grep '^[<>]' | head -2 | tr '\n' ' ')"
rm -f "$d"/p1 "$d"/p2 "$d"/p3
EOF
xargs -P "$JOBS" -I{} sh "$WORK/one.sh" {} "$COMPILER" "$WORK" <"$WORK/list" >"$WORK/out"
sort "$WORK/out"
N=$(wc -l <"$WORK/list" | tr -d ' ')
D=$(grep -c '^DIFF' "$WORK/out")
F=$(grep -c '^FAIL' "$WORK/out")
echo "same-output: $N cases, $D differ, $F fail to build, $LEFT left out"
[ "$D" -eq 0 ] && [ "$F" -eq 0 ]
