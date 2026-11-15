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
# take).
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
for mode in nosize nobig; do
    SHIM_MODE=$mode DYLD_INSERT_LIBRARIES="$T/shim.dylib" VOLE_CACHE=off "$C" check "$T/ok.vl" \
        > "$T/o" 2> "$T/e"
    s=$?
    n=$(grep -c "$W" "$T/e")
    if [ $s -ne 0 ] || [ "$n" -ne 1 ]; then
        echo "main-stack: FAIL: SHIM_MODE=$mode: exit $s, the warning $n times (1 wanted):"
        cat "$T/e"; bad=1
    fi
done
if [ $bad -ne 0 ]; then
    exit 1
fi
echo "main-stack: ok: the compiler's own thread, and its planted refusals said once"
