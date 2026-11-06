#!/bin/sh
# The gate's compile-cost row (0.21.1, after 0.20's std made a hello
# world 5.5 times dearer to build unnoticed): the instructions retired by
# four compilations, with this compiler and the previous release's,
# each the fewest of a few runs, and their ratios:
#
#   hello   a hello world built (an object: no linker), at most 1.5x
#   std     tests/cost/std_heavy.vl built (most of std read), at most 1.5x
#   check   `volec check` of compiler/src (a copy without compiler/std,
#           so that both read their own std; no tools' cache), at most 1.15x
#   rust    (0.27.1) `volec check` of the rust edition's corpus's biggest
#           case, tests/run/rust_t_iter_for_sources.vl (the borrow
#           checker's whole cost on it, against 0.27.0's unchecked
#           regions), at most 1.5x
#
# and (0.27.2) two of the rust edition on std2, with this compiler only
# (the previous release has no std2), against its own MVS rows above:
#
#   hello-rust  a rust hello world built, at most 2.0x hello's (target 1.5x;
#               printed, not failing: the ceiling 2.0x is enforced at the
#               0.27.2 cut)
#   std-rust    tests/cost/std2_heavy.vl built, at most 2.0x std's (target 1.5x)
#
# Instructions, not time: they hardly move with the machine's load. They
# are read from /usr/bin/time -l (macOS); a host without it skips (77).
#
# usage: tests/compile_cost.sh -c COMPILER -p PREVIOUS [-r RUNS]
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
C=""
P=""
RUNS=3
while [ $# -gt 0 ]; do
    case "$1" in
        -c) C=$2; shift ;;
        -p) P=$2; shift ;;
        -r) RUNS=$2; shift ;;
        *) echo "usage: tests/compile_cost.sh -c COMPILER -p PREVIOUS [-r RUNS]" >&2; exit 2 ;;
    esac
    shift
done
[ -x "$C" ] || { echo "compile-cost: no compiler (-c)"; exit 2; }
case "$C" in /*) ;; *) C="$(pwd)/$C" ;; esac
case "$P" in /*|'') ;; *) P="$(pwd)/$P" ;; esac
if [ -z "$P" ] || [ ! -x "$P" ]; then
    echo "compile-cost: no previous release built here (bootstrap/bootstrap.sh builds it)"
    exit 77
fi
if ! /usr/bin/time -l true 2>&1 | grep -q 'instructions retired'; then
    echo "compile-cost: /usr/bin/time -l counts no instructions on this host"
    exit 77
fi
W=$(mktemp -d "${TMPDIR:-/tmp}/vole-cost.XXXXXX")
trap 'rm -rf "$W"' EXIT
printf 'fn main() {\n    println("hello");\n}\n' >"$W/hello.vl"
cp "$ROOT/tests/cost/std_heavy.vl" "$W/std_heavy.vl"
cp "$ROOT/tests/cost/rust_heavy.vl" "$W/rust_heavy.vl"
printf '// EDITION: rust\nfn main() {\n    println("hello");\n}\n' >"$W/hello_rust.vl"
cp "$ROOT/tests/cost/std2_heavy.vl" "$W/std2_heavy.vl"
mkdir -p "$W/src"
cp -R "$ROOT/compiler/src/." "$W/src/"
VOLE_CACHE=off
VOLE_CODE_CACHE=off
export VOLE_CACHE VOLE_CODE_CACHE

# The fewest instructions of $RUNS runs of the command (in $W), or
# nothing when it fails.
count() {
    best=""
    i=0
    while [ $i -lt "$RUNS" ]; do
        (cd "$W" && /usr/bin/time -l "$@" >/dev/null 2>"$W/time.out") || return 1
        n=$(awk '/instructions retired/ { print $1 }' "$W/time.out")
        [ -n "$n" ] || return 1
        if [ -z "$best" ] || [ "$n" -lt "$best" ]; then best=$n; fi
        i=$((i + 1))
    done
    echo "$best"
}

FAILED=0
OVER=""
# <name> <limit> <command args...> (the compiler's place: COMPILER)
measure() {
    name=$1
    limit=$2
    shift 2
    new=$(count "$C" "$@") || { echo "compile-cost: $name fails with $C"; FAILED=1; return; }
    last_new=$new
    old=$(count "$P" "$@") || { echo "compile-cost: $name: skipped, the previous release cannot do it ($P $*)"; return; }
    awk -v n="$name" -v a="$old" -v b="$new" -v l="$limit" 'BEGIN {
        r = b / a
        bad = (r > l)
        printf "  %-6s %8.1f M instructions, was %8.1f M: %.2fx (at most %.2fx)%s\n", n, b / 1e6, a / 1e6, r, l, (bad ? "  TOO DEAR" : "")
        exit bad
    }' || FAILED=1
}
# (0.27.2) <name> <limit> <target> <enforced: 1, or 0: printed only>
# <MVS row's count> <command args...>: this compiler's count against its
# own MVS row's
measure_edition() {
    name=$1
    limit=$2
    target=$3
    enforced=$4
    base=$5
    shift 5
    [ -n "$base" ] || { echo "compile-cost: $name: skipped, its MVS row failed"; return; }
    new=$(count "$C" "$@") || { echo "compile-cost: $name fails with $C"; FAILED=1; return; }
    awk -v n="$name" -v a="$base" -v b="$new" -v l="$limit" -v t="$target" -v e="$enforced" 'BEGIN {
        r = b / a
        bad = (r > l)
        printf "  %-10s %8.1f M instructions, its MVS row %8.1f M: %.2fx (at most %.2fx%s, target %.2fx)%s\n", n, b / 1e6, a / 1e6, r, l, (e ? "" : ", enforced at the 0.27.2 cut"), t, (bad ? (e ? "  TOO DEAR" : "  over the ceiling") : "")
        exit (bad ? (e ? 1 : 2) : 0)
    }'
    case $? in 0) ;; 2) OVER="$OVER $name" ;; *) FAILED=1 ;; esac
}
echo "compile cost against $P:"
echo "  binary: $(wc -c <"$C" | tr -d ' ') bytes ($C), was $(wc -c <"$P" | tr -d ' ')"
last_new=""
measure hello 1.5 hello.vl -c -o hello.o
hello_new=$last_new
last_new=""
measure std 1.5 std_heavy.vl -c -o std_heavy.o
std_new=$last_new
measure check 1.15 check src/main.vl
# (0.27.2) tests/cost/rust_heavy.vl is written against MVS's std: read with
# it (rust_t_iter_for_sources, its std2 spelling, does not check on std2
# yet); the rows on std2 are hello-rust and std-rust below
VOLE_STD2=0
export VOLE_STD2
measure rust 1.5 check rust_heavy.vl
unset VOLE_STD2
measure_edition hello-rust 2.0 1.5 0 "$hello_new" hello_rust.vl -c -o hello_rust.o
measure_edition std-rust 2.0 1.5 1 "$std_new" std2_heavy.vl -c -o std2_heavy.o
if [ $FAILED -ne 0 ]; then
    echo "compile-cost: a compilation is dearer than the previous release allows (see above; --time-passes splits it by phase, and std's sections: tests/std/core_sections.sh)"
    exit 1
fi
if [ -n "$OVER" ]; then
    echo "compile-cost: within the bounds enforced now; over the ceiling enforced at the 0.27.2 cut:$OVER"
else
    echo "compile-cost: hello, std, check, rust, hello-rust and std-rust within the bounds"
fi
