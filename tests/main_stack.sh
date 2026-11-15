#!/bin/sh
# (0.30.1, RT-28) The compilation runs on a thread of its own with a 1 GiB
# stack (main.vl main, middle::threads::run_on_thread). When the system
# makes no such thread, pthread_attr_setstacksize or pthread_create
# refusing, main compiles on the process's first thread and says so,
# once, on stderr. This plants both refusals with a shim interposed on
# them (tests/main_stack/shim.c, macOS's DYLD_INSERT_LIBRARIES; SKIP
# elsewhere): the check must still pass, with the warning once; without
# the shim there is no warning, and an 8000-term chain checks
# (rt_028_long_operator_chain.vl, which the first thread's 8 MB does not
# take). (0.30.1, the review's) The warning is a diagnostic,
# thread.main-stack: once in a build that fails too (a lazy std's build
# with errors is made again, and the first run's is not printed), JSON
# under --json, and not said by --version or explain, which compile
# nothing; with every stack size refused (nosize: the workers' 64 MB
# too), a -j 4 build at -O2 builds, on fewer threads, and its program
# runs.
#
# usage: tests/main_stack.sh [-c COMPILER]
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
C="$ROOT/target/volec"
if [ "${1:-}" = -c ]; then
    C=$2
fi
cd "$ROOT" || exit 2
if [ "$(uname -s)" != Darwin ]; then
    echo "main-stack: SKIP: the shim is macOS's (DYLD_INSERT_LIBRARIES)"
    exit 0
fi
T=$(mktemp -d "${TMPDIR:-/tmp}/mainstack.XXXXXX")
trap 'rm -rf "$T"' EXIT
if ! cc -dynamiclib -o "$T/shim.dylib" tests/main_stack/shim.c 2> "$T/cc.txt"; then
    echo "main-stack: FAIL: the shim does not build:"; cat "$T/cc.txt"; exit 1
fi
cat > "$T/ok.vl" <<'VL'
fn main() {
    println("{}", 1 + 2);
}
VL
W="no thread with a 1 GiB stack could be made"
bad=0
VOLE_CACHE=off "$C" check "$T/ok.vl" > "$T/o" 2> "$T/e"
s=$?
if [ $s -ne 0 ] || grep -q "$W" "$T/e"; then
    echo "main-stack: FAIL: without the shim: exit $s"; cat "$T/e"; bad=1
fi
VOLE_CACHE=off "$C" check tests/run/rt_028_long_operator_chain.vl > "$T/o" 2> "$T/e"
s=$?
if [ $s -ne 0 ]; then
    echo "main-stack: FAIL: an 8000-term chain: exit $s"; bad=1
fi
cat > "$T/bad.vl" <<'VL'
fn main() {
    let x: u64 = "s";
}
VL
# (each: the shim's mode, the exit status wanted, the command line)
while read -r mode want args; do
    # shellcheck disable=SC2086
    SHIM_MODE=$mode DYLD_INSERT_LIBRARIES="$T/shim.dylib" VOLE_CACHE=off "$C" $args \
        > "$T/o" 2> "$T/e"
    s=$?
    n=$(cat "$T/o" "$T/e" | grep -c "$W")
    if [ $s -ne "$want" ] || [ "$n" -ne 1 ]; then
        echo "main-stack: FAIL: SHIM_MODE=$mode volec $args: exit $s ($want wanted), the warning $n times (1 wanted):"
        cat "$T/o" "$T/e"; bad=1
    fi
done <<LINES
nosize 0 check $T/ok.vl
nobig 0 check $T/ok.vl
nobig 1 $T/bad.vl -o $T/bad
nosize 0 -O2 -j 4 $T/ok.vl -o $T/ok4
LINES
if [ ! -x "$T/ok4" ] || [ "$("$T/ok4")" != 3 ]; then
    echo "main-stack: FAIL: the -j 4 build on no worker's stack did not run"; bad=1
fi
SHIM_MODE=nobig DYLD_INSERT_LIBRARIES="$T/shim.dylib" VOLE_CACHE=off "$C" --json check "$T/ok.vl" \
    > "$T/o" 2> "$T/e"
if ! cat "$T/o" "$T/e" | grep -q '^{"kind":"diagnostic","severity":"warning","code":"thread.main-stack"'; then
    echo "main-stack: FAIL: --json: the warning is not a JSON diagnostic:"; cat "$T/o" "$T/e"; bad=1
fi
for args in "--version" "explain lex.utf8"; do
    # shellcheck disable=SC2086
    SHIM_MODE=nobig DYLD_INSERT_LIBRARIES="$T/shim.dylib" VOLE_CACHE=off "$C" $args > "$T/o" 2> "$T/e"
    if cat "$T/o" "$T/e" | grep -q "$W"; then
        echo "main-stack: FAIL: volec $args, which compiles nothing, said the warning"; bad=1
    fi
done
if [ $bad -ne 0 ]; then
    exit 1
fi
echo "main-stack: ok: the compiler's own thread, and its planted refusals said once, as a diagnostic, by a compilation only; no worker's stack, a -j 4 build still builds"
