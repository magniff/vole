#!/bin/sh
# The build's measuring options (0.25.5): --time-passes=instructions and
# --vec-stats=FN. POSIX sh only.
#
# usage: tests/perf/run.sh [-c COMPILER]
#
# Checks, each printed `pass NAME` or `FAIL NAME` (and why); exits 1 if
# one failed:
#   time          --time-passes: each phase's CPU time, `N ms  total`
#   instructions  --time-passes=instructions: each phase's instructions
#                 retired in millions, `N M  total (instructions
#                 retired)`, near what the whole process retired (macOS:
#                 /usr/bin/time -l); where the system refuses the counter
#                 (Linux: perf_event_open), the time.instructions error
#   refused       $VOLE_COUNTERS=off: the time.instructions error, its text
#   bad-value     --time-passes=bogus: `cannot read --time-passes=bogus`
#   vec-stats     --vec-stats=FN at -O2: a line per loop of FN, vectorized
#                 or the first reason it was not (a call, a gather, a
#                 branch, an unknown trip count, a float sum), the lines
#                 as below; the program runs the same
#   vec-counts    --vec-stats alone: the counts line only; -O0: no line
#                 for a loop

set -u
LC_ALL=C
export LC_ALL

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
COMPILER="$ROOT/target/volec"
while [ $# -gt 0 ]; do
    case "$1" in
        -c) [ $# -ge 2 ] || exit 2; COMPILER=$2; shift 2 ;;
        *) echo "usage: tests/perf/run.sh [-c COMPILER]" >&2; exit 2 ;;
    esac
done
case "$COMPILER" in
    /*) ;;
    *) COMPILER="$(pwd)/$COMPILER" ;;
esac
[ -x "$COMPILER" ] || { echo "perf/run.sh: no compiler at $COMPILER" >&2; exit 2; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/vole-perf.XXXXXX")
WORK=$(cd "$WORK" && pwd -P)
trap 'rm -rf "$WORK"' EXIT
trap 'exit 130' INT TERM
VOLE_CODE_CACHE=off
export VOLE_CODE_CACHE
unset VOLE_COUNTERS
STATUS=0
cd "$WORK" || exit 2

pass() { echo "pass $1"; }
fail() {
    echo "FAIL $1"
    echo "    $2"
    STATUS=1
}

cat >hello.vl <<'EOF'
fn main() {
    println("hello");
}
EOF
cat >loops.vl <<'EOF'
extern "C" {
    fn putchar(c: i32) -> i32;
}

static var N: i64 = 3;

#[inline(never)]
fn kernels(a: inout [i64; 1024], idx: [i64; 1024], f: inout [f64; 1024]) -> i64 {
    var s = 0;
    for i in 0..1024 {
        s += a[i];
    }
    for i in 0..1024 {
        s += a[idx[i] & 1023];
    }
    for i in 0..1024 {
        if a[i] > 5 {
            break;
        }
        a[i] = a[i] + 1;
    }
    var k = 0;
    while k < N {
        unsafe {
            putchar(65);
        }
        k += 1;
    }
    var p = 1;
    while p < N * 100 {
        p = p * 3 + a[p & 1023];
    }
    var fs = 0.0;
    for i in 0..1024 {
        fs += f[i];
    }
    s + p + fs as i64
}

fn main() {
    var a: [i64; 1024] = [1; 1024];
    var idx: [i64; 1024] = [0; 1024];
    var f: [f64; 1024] = [0.5; 1024];
    for i in 0..1024 {
        idx[i] = (i * 7) & 1023;
    }
    println(f"{kernels(&a, idx, &f)}");
}
EOF
cat >loops.want <<'EOF'
vec-stats: kernels, loop at line 25: not vectorized: a call in the loop
vec-stats: kernels, loop at line 11: vectorized, 2 lanes, the body 4 times an iteration
vec-stats: kernels, loop at line 14: not vectorized: an address computed from a value loaded in the loop (a gather, a[idx[i]]) (shl)
vec-stats: kernels, loop at line 17: not vectorized: a branch in its body that is no bounds check (an if, a break)
vec-stats: kernels, loop at line 31: not vectorized: an unknown trip count: not a loop over a counter to a bound
vec-stats: kernels, loop at line 35: not vectorized: a float carried from one iteration to the next (a float sum: lanes would add in another order) (phi)
vector loops 1, overlap tests 0, tests dropped by noalias 0
EOF
REFUSED="error[time.instructions] the instructions retired cannot be read here | help: the system's counter refused this process (Linux: perf_event_open, which /proc/sys/kernel/perf_event_paranoid above 2 or a container's seccomp profile forbids); --time-passes counts CPU time | try: volec --time-passes FILE.vl -c -o /dev/null"

# The compiler, its stderr in err.out (the compiler's path written volec,
# `ok:` lines dropped); its status.
build() {
    "$COMPILER" "$@" >out.out 2>err.raw
    rc=$?
    sed "s|$COMPILER|volec|g" err.raw | grep -v '^ok: ' >err.out
    return $rc
}

# time
if build --time-passes hello.vl -c -o hello.o && grep -q '^[0-9]* ms  total$' err.out \
    && grep -q ' ms  parse$' err.out; then
    pass time
else
    fail time "$(cat err.out)"
fi

# instructions
if build --time-passes=instructions hello.vl -c -o hello.o; then
    total=$(sed -n 's/^\([0-9]*\) M  total (instructions retired)$/\1/p' err.out)
    if [ -z "$total" ] || ! grep -q '^[0-9]*\.[0-9] M  parse$' err.out; then
        fail instructions "no phases in millions and total: $(cat err.out)"
    elif [ "$total" -lt 1 ]; then
        fail instructions "a total of $total M"
    elif /usr/bin/time -l true 2>&1 | grep -q 'instructions retired'; then
        whole=$( { /usr/bin/time -l "$COMPILER" --time-passes=instructions hello.vl -c -o hello.o >/dev/null; } 2>&1 \
            | awk '/^ *[0-9]+  instructions retired$/ { print int($1 / 1000000) }')
        # (the phases are the process but its start and end: within 2x)
        if [ "$total" -le "$whole" ] && [ $((total * 2)) -ge "$whole" ]; then
            pass instructions
        else
            fail instructions "the phases say $total M, the process retired $whole M"
        fi
    else
        pass instructions
    fi
elif [ "$(cat err.out)" = "$REFUSED" ]; then
    pass "instructions (the system refuses the counter here)"
else
    fail instructions "$(cat err.out)"
fi

# refused
if VOLE_COUNTERS=off build --time-passes=instructions hello.vl -c -o hello.o; then
    fail refused "built: $(cat err.out)"
elif [ "$(cat err.out)" != "$REFUSED" ]; then
    fail refused "not the time.instructions error: $(cat err.out)"
else
    pass refused
fi

# bad-value
if build --time-passes=bogus hello.vl -c -o hello.o; then
    fail bad-value "built"
elif ! grep -q 'cannot read --time-passes=bogus' err.out; then
    fail bad-value "$(cat err.out)"
else
    pass bad-value
fi

# vec-stats
if build -O2 --vec-stats=kernels loops.vl -o loops && [ "$(./loops | tr -d '\n')" = 3045AAA ] \
    && cmp -s err.out loops.want; then
    pass vec-stats
else
    fail vec-stats "$(diff loops.want err.out 2>&1 | head -20)"
fi

# vec-counts
if build -O2 --vec-stats loops.vl -c -o loops.o \
    && [ "$(cat err.out)" = "vector loops 1, overlap tests 0, tests dropped by noalias 0" ] \
    && build -O0 --vec-stats=kernels loops.vl -c -o loops.o && ! grep -q 'loop at' err.out; then
    pass vec-counts
else
    fail vec-counts "$(cat err.out)"
fi

exit $STATUS
