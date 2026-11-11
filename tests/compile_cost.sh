#!/bin/sh
# The gate's compile-cost row (0.21.1, after 0.20's std made a hello
# world 5.5 times dearer to build unnoticed): the instructions retired by
# five compilations, with this compiler and the previous release's,
# each the fewest of a few runs, and their ratios:
#
#   hello   a hello world built (an object: no linker), at most 1.5x
#   std     tests/cost/std_heavy.vl built (most of std read), at most 1.5x
#   check   `volec check` of compiler/src (a copy without compiler/std,
#           so that both read their own std; no tools' cache), at most 1.15x
#   rust    (0.27.1) `volec check` of the borrow checker's biggest case
#           then, tests/cost/rust_heavy.vl, at most 1.5x
#   regions (0.27.8) `volec check` of tests/cost/regions_heavy.vl, many
#           calls of functions on structs with lifetimes (a callee's
#           signature, read at each call, reads its types' declared and
#           inferred bounds: made once per type), at most 1.5x
#
# (0.28.0) The programs are in the one edition there is; hello and
# std_heavy.vl carry the edition line 0.27.8 needs to read them so. One
# more row while the previous release is a 0.27 (it still has the MVS
# edition; a later one refuses the flag and the row is not printed):
#
#   hello-0.27  the hello world's build against the previous release's
#               build of it as an MVS program, at most 2.0x (the bound the
#               rust edition's hello had since 0.27.5 against MVS's)
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
printf '// EDITION: rust\nfn main() {\n    println("hello");\n}\n' >"$W/hello.vl"
printf 'fn main() {\n    println("hello");\n}\n' >"$W/hello_027.vl"
cp "$ROOT/tests/cost/std_heavy.vl" "$W/std_heavy.vl"
cp "$ROOT/tests/cost/rust_heavy.vl" "$W/rust_heavy.vl"
cp "$ROOT/tests/cost/regions_heavy.vl" "$W/regions_heavy.vl"
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
# (0.28.0) the hello world against the previous release's build of it as
# an MVS program: only while that release has the edition
hello_027() {
    [ -n "$1" ] || return
    old=$(count "$P" --edition mvs hello_027.vl -c -o hello_027.o) || return
    awk -v a="$old" -v b="$1" 'BEGIN {
        r = b / a
        bad = (r > 2.0)
        printf "  %-10s %8.1f M instructions, as an MVS program it was %8.1f M: %.2fx (at most 2.00x)%s\n", "hello-0.27", b / 1e6, a / 1e6, r, (bad ? "  TOO DEAR" : "")
        exit bad
    }' || FAILED=1
}
echo "compile cost against $P:"
echo "  binary: $(wc -c <"$C" | tr -d ' ') bytes ($C), was $(wc -c <"$P" | tr -d ' ')"
last_new=""
measure hello 1.5 hello.vl -c -o hello.o
hello_new=$last_new
measure std 1.5 std_heavy.vl -c -o std_heavy.o
measure check 1.15 check src/main.vl
# tests/cost/rust_heavy.vl is written against the old std: read with it
# until that std goes
VOLE_STD2=0
export VOLE_STD2
measure rust 1.5 check rust_heavy.vl
unset VOLE_STD2
measure regions 1.5 check regions_heavy.vl
hello_027 "$hello_new"
if [ $FAILED -ne 0 ]; then
    echo "compile-cost: a compilation is dearer than the previous release allows (see above; --time-passes splits it by phase, and std's sections: tests/std/core_sections.sh)"
    exit 1
fi
echo "compile-cost: hello, std, check, rust and regions within the bounds"
