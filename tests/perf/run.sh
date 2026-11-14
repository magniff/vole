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
#   passes        (0.29) --time-passes=passes at -O2: after the phases, a
#                 row per optimizer pass that ran (gvn, sccp, register
#                 allocation ...), the rest of each phase, the front end,
#                 and what the marks themselves cost; the rows add up to
#                 the phases' total less the marks (within a tenth); the
#                 object is the one a build without the option writes
#   refused       $VOLE_COUNTERS=off: the time.instructions error, its text
#   bad-value     --time-passes=bogus: `cannot read --time-passes=bogus`
#   vec-stats     --vec-stats=FN at -O2: a line per loop of FN, vectorized
#                 or the first reason it was not (a call, a gather, a
#                 branch, an unknown trip count, a float sum), the lines
#                 as below; the program runs the same
#   vec-counts    --vec-stats alone: the counts line only; -O0: no line
#                 for a loop
#   vec-headers   (0.30) --vec-stats=FN at -O2: `vec-headers: FN: known:
#                 writes ...`, the summary of the Vec headers FN may write
#                 (none; through an operand, the words; a static's), or
#                 `unknown: line N:` and the first instruction that made
#                 it so (a store through a loaded pointer, a call of C, a
#                 call of a function whose summary is unknown, which the
#                 line names to ask next); the object is the one a build
#                 without the option writes; -O0: no line
#   asm           (0.30) `volec query asm FN`: FN's machine code at -O2,
#                 from its label to its `ret`, and no other function's; a
#                 name the code has no function for: query.no-match
#   json          (0.30) --time-passes=json at -O2: one JSON object on
#                 stderr, `{"unit":"instructions","phases":[..],"total":N,
#                 "passes":[..],"rest":[..],"front_end":N,"mark":{..}}`,
#                 the counts whole; its total is the phases' sum
#   check-phases  (0.30) `volec check --time-passes=instructions`: the
#                 front end's phases in millions and the total; `=json`:
#                 the object, no passes in it
#   print-after   (0.30) --print-after-all=FN: the IR after every pass of
#                 function FN only (fewer `; after` blocks than without
#                 the name, each of that function)
#   help          (0.30) `volec build --help` (and `volec FILE.vl --help`)
#                 names the options that show what the compiler did:
#                 --emit-ir, --time-passes, --print-after-all, --verify-ir,
#                 --vec-stats, VOLE_INLINE_LOG; `volec --help` points there
#   perf-diff     (0.30) tools/perf-diff.sh A B FILE: a table of phases
#                 and one of passes with both compilers' instructions and
#                 the difference (the same compiler twice: every row's
#                 two counts within a quarter of each other: on a busy
#                 machine a small phase's count moves by several percent)

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

static mut N: i64 = 3;

#[inline(never)]
fn kernels(a: &mut [i64; 1024], idx: &[i64; 1024], f: &mut [f64; 1024]) -> i64 {
    let mut s = 0;
    for i in 0..1024 {
        s += a[i];
    }
    for i in 0..1024 {
        s += a[(idx[i] & 1023) as usize];
    }
    for i in 0..1024 {
        if a[i] > 5 {
            break;
        }
        a[i] = a[i] + 1;
    }
    let mut k = 0;
    while k < unsafe { N } {
        unsafe {
            putchar(65);
        }
        k += 1;
    }
    let mut p = 1;
    while p < unsafe { N } * 100 {
        p = p * 3 + a[(p & 1023) as usize];
    }
    let mut fs = 0.0;
    for i in 0..1024 {
        fs += f[i];
    }
    s + p + fs as i64
}

fn main() {
    let mut a: [i64; 1024] = [1; 1024];
    let mut idx: [i64; 1024] = [0; 1024];
    let mut f: [f64; 1024] = [0.5; 1024];
    for i in 0..1024 {
        idx[i] = ((i * 7) & 1023) as i64;
    }
    println("{}", kernels(&mut a, &idx, &mut f));
}
EOF
cat >loops.want <<'EOF'
vec-stats: kernels, loop at line 25: not vectorized: a call in the loop
vec-stats: kernels, loop at line 11: vectorized, 2 lanes, the body 4 times an iteration
vec-stats: kernels, loop at line 14: not vectorized: an address computed from a value loaded in the loop (a gather, a[idx[i]]) (shl)
vec-stats: kernels, loop at line 17: not vectorized: a branch in its body that is no bounds check (an if, a break)
vec-stats: kernels, loop at line 31: not vectorized: an unknown trip count: not a loop over a counter to a bound
vec-stats: kernels, loop at line 35: not vectorized: a float carried from one iteration to the next (a float sum: lanes would add in another order) (phi)
vec-headers: kernels: unknown: line 20: a store through an address the summary does not follow (a pointer loaded from memory, a raw pointer of unknown origin, a number made a pointer)
vector loops 3, overlap tests 0, tests dropped by noalias 0
EOF
# (0.30) --vec-stats=FN also says what is known of the Vec headers FN may
# write (middle/callfacts.vl), and for an unknown summary the first
# instruction that made it so: headers.vl's functions, one of each kind.
cat >headers.vl <<'EOF'
use std::alloc::Allocator;

// UNSAFE: a C function is declared.
// SAFETY: getpid's prototype: no argument, an int.
extern "C" {
    fn getpid() -> i32;
}

struct Bag<A: Allocator> {
    items: Vec<i64, A>,
    seen: Vec<i64, A>,
    total: i64,
}

#[inline(never)]
fn bump(b: &mut Bag<Gpa>) {
    b.total += 1;
}

#[inline(never)]
fn add(b: &mut Bag<Gpa>, x: i64) {
    b.items.push(x);
}

#[inline(never)]
fn poke(p: *mut *mut i64) {
    // UNSAFE: a store through a pointer loaded from memory.
    // SAFETY: the caller passes the address of a pointer to a live i64.
    unsafe {
        **p = 7;
    }
}

#[inline(never)]
fn pid(b: &mut Bag<Gpa>) {
    // UNSAFE: a C call.
    // SAFETY: getpid takes nothing and returns the process id.
    b.total += unsafe { getpid() } as i64;
}

#[inline(never)]
fn both(b: &mut Bag<Gpa>, x: i64) {
    add(b, x);
    pid(b);
}

fn main(gpa: Gpa) -> i32 {
    let mut b = Bag { items: Vec::new_in(gpa), seen: Vec::new_in(gpa), total: 0 };
    b.seen.push(1);
    let mut s: i64 = 0;
    for i in 0..4 {
        bump(&mut b);
        add(&mut b, i);
        both(&mut b, i);
        s += b.seen[0];
    }
    let mut k: i64 = 1;
    let mut q: *mut i64 = &mut k;
    poke(&mut q);
    println("{} {} {}", s, b.items.len(), k);
    0
}
EOF
cat >headers.want <<'EOF'
vec-headers: bump: known: writes none
vec-headers: add: known: writes through operand 0 (words 0..3)
vec-headers: poke: unknown: line 30: a store through an address the summary does not follow (a pointer loaded from memory, a raw pointer of unknown origin, a number made a pointer)
vec-headers: pid: unknown: line 38: a call of C's `getpid` (a C function other than the allocator's has no summary)
vec-headers: both: unknown: line 44: a call of `pid`, whose summary is unknown (--vec-stats=pid)
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

# passes
if build -O2 --time-passes=passes hello.vl -c -o hello_p.o; then
    total=$(sed -n 's/^\([0-9]*\) M  total (instructions retired)$/\1/p' err.out)
    rows=$(awk '/^passes \(instructions retired/ { on = 1; next }
        on && / marks themselves / { on = 0; next }
        on && /^[0-9]+\.[0-9] M  / { sum += $1 }
        END { print int(sum) }' err.out)
    marks=$(sed -n 's/^\([0-9]*\) M  the [0-9]* marks themselves ([0-9]* each), not in the rows$/\1/p' err.out)
    if [ -z "$total" ] || [ -z "$marks" ]; then
        fail passes "no total or no marks line: $(cat err.out)"
    elif ! grep -q '^[0-9]*\.[0-9] M  gvn$' err.out || ! grep -q '^[0-9]*\.[0-9] M  sccp$' err.out \
        || ! grep -q '^[0-9]*\.[0-9] M  register allocation$' err.out \
        || ! grep -q '^[0-9]*\.[0-9] M  rest of: lower to SSA$' err.out \
        || ! grep -q '^[0-9]*\.[0-9] M  the front end (its phases are above)$' err.out; then
        fail passes "a row is missing (gvn, sccp, register allocation, rest of: lower to SSA, the front end): $(cat err.out)"
    elif [ $((rows + marks)) -gt $((total + total / 10 + 1)) ] \
        || [ $((rows + marks + total / 10 + 1)) -lt "$total" ]; then
        fail passes "the rows add up to $rows M and the marks to $marks M; the phases' total is $total M"
    elif ! build -O2 hello.vl -c -o hello_q.o || ! cmp -s hello_p.o hello_q.o; then
        fail passes "the object differs from a build without the option"
    else
        pass passes
    fi
elif [ "$(cat err.out)" = "$REFUSED" ]; then
    pass "passes (the system refuses the counter here)"
else
    fail passes "$(cat err.out)"
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

# vec-counts (the program's loops, std's too: kernels' one, and two
# in what println brings in, 0.28)
if build -O2 --vec-stats loops.vl -c -o loops.o \
    && [ "$(cat err.out)" = "vector loops 3, overlap tests 0, tests dropped by noalias 0" ] \
    && build -O0 --vec-stats=kernels loops.vl -c -o loops.o && ! grep -q 'loop at' err.out; then
    pass vec-counts
else
    fail vec-counts "$(cat err.out)"
fi

# vec-headers
: >headers.got
for f in bump add poke pid both; do
    build -O2 --vec-stats=$f headers.vl -o headers
    grep '^vec-headers: ' err.out >>headers.got
done
if cmp -s headers.got headers.want && [ "$(./headers)" = "4 8 7" ] \
    && build -O2 headers.vl -c -o headers_a.o && build -O2 --vec-stats=both headers.vl -c -o headers_b.o \
    && cmp -s headers_a.o headers_b.o \
    && build -O0 --vec-stats=add headers.vl -c -o headers_c.o && ! grep -q '^vec-headers' err.out; then
    pass vec-headers
else
    fail vec-headers "$(diff headers.want headers.got 2>&1 | head -20)"
fi

# asm
if "$COMPILER" query asm bump --root headers.vl >asm.out 2>asm.err \
    && sed -n 1p asm.out | grep -q 'bump:$' && grep -q '^ *ret' asm.out \
    && [ "$(grep -c ':$' asm.out)" -le 3 ] \
    && ! "$COMPILER" query asm no_such_fn --root headers.vl >asm2.out 2>asm2.err \
    && grep -q "^error query.no-match: no function 'no_such_fn' in the program's code at -O2" asm2.err; then
    pass asm
else
    fail asm "$(head -5 asm.out asm.err asm2.err 2>&1)"
fi

# (an assignment before a function call, `VOLE_COUNTERS=off build` above,
# stays set in some shells)
unset VOLE_COUNTERS

# json
if build -O2 --time-passes=json hello.vl -c -o hello_j.o; then
    obj=$(grep '^{"unit":"instructions","phases":\[' err.out)
    if [ -z "$obj" ] || [ "$(grep -c '^{' err.out)" != 1 ]; then
        fail json "not one object: $(cut -c1-300 err.out)"
    elif ! echo "$obj" | grep -q '"passes":\[{"name":"sccp","value":[0-9]*,"marks":[0-9]*}' \
        || ! echo "$obj" | grep -q '{"name":"gvn","value":[0-9]*,"marks":[0-9]*}' \
        || ! echo "$obj" | grep -q '"rest":\[{"name":"lower to SSA","value":[0-9]*}' \
        || ! echo "$obj" | grep -q '"front_end":[0-9]*,"mark":{"count":[0-9]*,"each":[0-9]*}}$'; then
        fail json "a member is missing (passes with sccp and gvn, rest, front_end, mark): $(echo "$obj" | cut -c1-400)"
    elif ! echo "$obj" | sed 's/"passes":.*//' | awk '{
            n = split($0, part, /"value":/); sum = 0
            for (i = 2; i <= n; i++) { v = part[i]; sub(/[^0-9].*/, "", v); sum += v }
            t = $0; sub(/.*"total":/, "", t); sub(/[^0-9].*/, "", t)
            exit !(sum == t + 0 && t + 0 > 1000000) }'; then
        fail json "the total is not the phases' sum: $(echo "$obj" | cut -c1-400)"
    elif ! cmp -s hello_j.o hello_q.o; then
        fail json "the object differs from a build without the option"
    else
        pass json
    fi
elif [ "$(cat err.out)" = "$REFUSED" ]; then
    pass "json (the system refuses the counter here)"
else
    fail json "$(cat err.out)"
fi

# check-phases
if VOLE_CACHE=off build check --time-passes=instructions hello.vl; then
    if grep -q '^[0-9]*\.[0-9] M  parse$' err.out && grep -q '^[0-9]*\.[0-9] M  check$' err.out \
        && grep -q '^[0-9]* M  total (instructions retired)$' err.out \
        && VOLE_CACHE=off build check --time-passes=json hello.vl \
        && grep -q '^{"unit":"instructions","phases":\[.*{"name":"check","value":[0-9]*}.*\],"total":[0-9]*}$' err.out; then
        pass check-phases
    else
        fail check-phases "$(cut -c1-300 err.out)"
    fi
elif grep -q 'the system.s counter refused' err.out; then
    pass "check-phases (the system refuses the counter here)"
else
    fail check-phases "$(cat err.out)"
fi

# print-after
if build -O2 --print-after-all=kernels loops.vl -c -o loops_a.o; then
    named=$(grep -c '^; after ' err.out)
    others=$(awk '/^fn / && $0 != "fn kernels:" { n++ } END { print n + 0 }' err.out)
    build -O2 --print-after-all loops.vl -c -o loops_a.o
    all=$(grep -c '^; after ' err.out)
    if [ "$named" -ge 1 ] && [ "$others" = 0 ] && [ "$all" -gt "$named" ]; then
        pass print-after
    else
        fail print-after "$named blocks for kernels ($others of other functions), $all without the name"
    fi
else
    fail print-after "$(cut -c1-300 err.out)"
fi

# help
"$COMPILER" build --help >help.out 2>&1
"$COMPILER" hello.vl --help >help2.out 2>&1
"$COMPILER" --help >help3.out 2>&1
missing=""
for word in --emit-ir '--time-passes' '=instructions' '=passes' '=json' '--print-after-all\[=FN\]' --verify-ir \
    '--vec-stats\[=FN\]' VOLE_INLINE_LOG tools/perf-diff.sh tools/perf-experiment.sh 'bench/run.sh --instructions'; do
    grep -q -e "$word" help.out || missing="$missing $word"
done
if [ -n "$missing" ]; then
    fail help "volec build --help does not name:$missing"
elif ! cmp -s help.out help2.out; then
    fail help "volec FILE.vl --help is not volec build --help"
elif ! grep -q 'volec build --help' help3.out; then
    fail help "volec --help does not point to volec build --help"
else
    pass help
fi

# perf-diff
if ! command -v python3 >/dev/null 2>&1; then
    pass "perf-diff (no python3 here)"
elif ! "$COMPILER" --time-passes=instructions hello.vl -c -o hello.o >/dev/null 2>&1; then
    pass "perf-diff (the system refuses the counter here)"
elif sh "$ROOT/tools/perf-diff.sh" --all "$COMPILER" "$COMPILER" hello.vl >diff.out 2>&1 \
    && grep -q '^phases: -O2 hello.vl  *A (M)  *B (M)  *B-A (M)  *%$' diff.out \
    && grep -q '^passes: -O2 hello.vl ' diff.out \
    && awk '/^  (check|gvn|total) / { a = $(NF - 3); b = $(NF - 2); seen++
            if (a <= 0 || b <= 0 || b < a * 0.75 || b > a * 1.25) bad = 1 }
        END { exit !(seen >= 4 && !bad) }' diff.out; then
    pass perf-diff
else
    fail perf-diff "$(head -12 diff.out)"
fi

exit $STATUS
