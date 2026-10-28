#!/bin/sh
# The release gate (docs/roadmap.md) in one command, as parallel as the
# machine allows: the chain builds the compiler from the working tree
# (bootstrap.sh --dev), then the test suite at every level, the random
# programs in every mode, the C interop fuzzer in every mode, the object
# and layout checks and the debugger check all run at once, next to the
# two Linux containers (x86_64-linux, from its own chain; aarch64-linux,
# cross-built here). Ends with one table (step, result, time) and the
# failures' details; exits 1 when a step failed.
#
# usage: bootstrap/gate.sh [--quick | --release] [options]
#
#   --quick          a developer's smoke test (a few minutes): the chain,
#                    the suite at -O2, a short fuzz, and (0.25.2) the
#                    linux-smoke row: the compiler cross-built for
#                    aarch64-linux and a slice of the suite in the
#                    container (SKIP, saying so, when colima is not running)
#   (default)        every step, with modest fuzz counts
#   --release        every step, with the release's fuzz counts
#   --no-linux       without the containers (and without linux-smoke)
#   --no-x86         without x86_64 (the x86_64-linux container); the
#                    default since 0.15, set in bootstrap/gate.conf (X86=0)
#                    or by $VOLE_GATE_X86 (0 or 1)
#   --with-x86       with x86_64, whatever the default
#   --only STEPS     only these steps (comma-separated; `fuzz-*` patterns;
#                    the chain is added when they need the compiler)
#   --bench          then the benchmarks (bench/run.sh), alone, at the end
#                    (they need an idle machine); `--only bench` for just
#                    them
#   -j N             slots for the macOS (or host) steps, shared by all of
#                    them through $VOLE_JOBSERVER (default: the number
#                    of CPUs)
#   --cpus N         CPUs of each container (default 8, at most docker's)
#   --fuzz N         random programs per fuzz mode (overrides the mode's)
#   --abi N          C interop programs per ABI mode (the same)
#   --history MODE   fast (the default) or full: bootstrap.sh's --history,
#                    here and in the x86_64-linux container
#   --fresh          the x86_64-linux chain without its cache (a docker
#                    volume): from nothing, as on a new machine
#   -c COMPILER      test this compiler instead of building one (no chain)
#   --no-wait        (0.25.2) fail at once when another gate of this
#                    repository runs, instead of waiting for it (one gate at
#                    a time, across all its worktrees: a lock directory in
#                    the git common dir, gate.lock; a dead holder's lock is
#                    taken over)
#   --list           print the steps, in the order they start, and exit
#   --self-test      check the gate's own machinery (the lock, the stall
#                    check, the steps of each mode) and exit
#
# Steps: chain; suite-O0, suite-O1, suite-O2; fuzz-plain, fuzz-loops,
# fuzz-generics, fuzz-pressure, fuzz-calls, fuzz-lang06, fuzz-vector,
# fuzz-div, fuzz-range, fuzz-arch (0.19: intrinsics), fuzz-guard (0.25:
# guarded accesses, never run where the program does not), fuzz-seed
# (against the Rust seed), fuzz-sem (0.25: value semantics, drops and
# leaks against tools/semfuzz/semfuzz.py's model); abi-plain,
# abi-import, abi-header; objcheck; layout (tests/cimport/layout.sh); debug (tests/debug.sh);
# objcheck-x86-arch (0.19: the std::arch cases for x86_64-macos, compiled
# and assembled both ways, nothing run);
# threads (tests/threads.sh: the same output at -j1 and -j8, 0.18.1);
# incremental (tests/incremental.sh: rebuilds with the code cache after
# edits the same as clean builds, 0.18.1);
# stress-grow (the compiler with every table growth moving, 0.14);
# examples-checkalloc (every example's test built with --check-alloc, 0.16);
# voltty-fuzz (tests/voltty/run.sh -s 60: the terminal's core against
# alacritty_terminal, 60 s of the differential fuzzer, 0.23; skipped
# without cargo);
# compile-cost (tests/compile_cost.sh: the instructions of a hello world,
# a std-heavy program and `check` of compiler/src against the previous
# release's, 0.21.1: fails above 1.5x, 1.5x and 1.15x);
# valgrind (tests/valgrind.sh: the compiler under memcheck, 0.18.1; run by
# --release in the linux-aarch64 container, where valgrind is);
# compiler-memcheck (tests/compiler_memcheck.sh: the compiler built with
# --check-alloc, and under Guard Malloc, on its self-compile and a sample
# of the suite, 0.25);
# chain-diverse (bootstrap/chain-diverse.sh: HEAD's compiler by the
# normal chain, by a path without the optimizer and at -j1, the same
# bytes and the same output on the corpus, 0.25; --release);
# chain-fresh (bootstrap/chain-fresh.sh: the seed and every release
# rebuilt from their tags into an empty cache, compared with
# bootstrap/chain-hashes/, 0.25; --release);
# linux-x86_64 (bootstrap/linux-check.sh); linux-aarch64
# (bootstrap/aarch64-linux-check.sh: in the container, the fixpoint,
# the suite at -O0 and -O2 (0.25.2: not -O1; the optimizer is the same
# for every target and -O1 runs on macOS, while what is Linux's own, the
# ABI, libc and the link, -O0 and -O2 exercise), fuzz, ABI, objcheck,
# debug, (--release) valgrind; the longest started first);
# linux-smoke (0.25.2, --quick: aarch64-linux-check.sh --smoke, the
# cross-built compiler on the container's smoke-* steps: the runner's
# self-test, the language server, the examples' builds, every case and
# the walkthroughs' and book's sessions; a few minutes beside the macOS
# steps); bench.
#
# (0.25.2) One gate at a time: a second one waits for the first, saying
# whose it is (or, with --no-wait, fails). A step whose processes neither
# use the CPU nor change for $VOLE_GATE_STALL seconds (default 600) is
# stopped and fails, with the free slots of the pool: a hang (a slot lost
# by a killed job) is reported, not waited for.
#
# Logs: target/gate/<date>/ (target/gate/last), one STEP.log per step;
# failing random programs are kept in failures/STEP/ there.
#
# Inside the Linux containers the check scripts run the host's steps with
# `gate.sh --inside -c COMPILER --only ...`, which prints the rows for the
# outer table too.

set -u
LC_ALL=C
export LC_ALL
# (0.18.1) The steps build without the code cache (back::codecache), but
# the incremental step and the suite at -O2 (a smoke row: its cache in the
# run's directory, removed after).
VOLE_CODE_CACHE=off
export VOLE_CODE_CACHE

ROOT=$(cd "$(dirname "$0")/.." && pwd)
GATE_ARGS="$*"
MODE=default
# (0.16) Each test program may run for a minute, not 20 s: the gate runs
# its steps side by side with the containers, and the heavier examples
# (algorithms at -O0) took longer than 20 s on a loaded machine. A hang
# is still caught.
VOLE_TEST_TIMEOUT=${VOLE_TEST_TIMEOUT:-60}
export VOLE_TEST_TIMEOUT
LINUX=1
# (0.15) x86_64: bootstrap/gate.conf's X86, then $VOLE_GATE_X86, then
# --no-x86/--with-x86
X86=1
[ ! -f "$ROOT/bootstrap/gate.conf" ] || X86=$(sed -n 's/^X86=\([01]\)$/\1/p' "$ROOT/bootstrap/gate.conf" | tail -1)
[ -n "$X86" ] || X86=1
[ -z "${VOLE_GATE_X86:-}" ] || X86=$VOLE_GATE_X86
ONLY=""
BENCH=0
JOBS=""
CPUS=8
FUZZ_N=""
ABI_N=""
HISTORY=fast
FRESH=0
COMPILER=""
INSIDE=0
SEED_BIN=""
LIST=0
NO_WAIT=0
SELF_TEST=0

die() {
    echo "gate: error: $*" >&2
    exit 2
}

while [ $# -gt 0 ]; do
    case "$1" in
        --quick) MODE=quick ;;
        --release) MODE=release ;;
        --no-linux) LINUX=0 ;;
        --no-x86) X86=0 ;;
        --with-x86) X86=1 ;;
        --only) [ $# -ge 2 ] || die "--only needs steps"; ONLY=$2; shift ;;
        --only=*) ONLY=${1#--only=} ;;
        --bench) BENCH=1 ;;
        -j) [ $# -ge 2 ] || die "-j needs a number"; JOBS=$2; shift ;;
        -j*) JOBS=${1#-j} ;;
        --cpus) [ $# -ge 2 ] || die "--cpus needs a number"; CPUS=$2; shift ;;
        --cpus=*) CPUS=${1#--cpus=} ;;
        --fuzz) [ $# -ge 2 ] || die "--fuzz needs a number"; FUZZ_N=$2; shift ;;
        --fuzz=*) FUZZ_N=${1#--fuzz=} ;;
        --abi) [ $# -ge 2 ] || die "--abi needs a number"; ABI_N=$2; shift ;;
        --abi=*) ABI_N=${1#--abi=} ;;
        --history) [ $# -ge 2 ] || die "--history needs fast or full"; HISTORY=$2; shift ;;
        --history=*) HISTORY=${1#--history=} ;;
        --fresh) FRESH=1 ;;
        -c) [ $# -ge 2 ] || die "-c needs a compiler"; COMPILER=$2; shift ;;
        --seed) [ $# -ge 2 ] || die "--seed needs a binary"; SEED_BIN=$2; shift ;;
        --inside) INSIDE=1; LINUX=0 ;;
        --list) LIST=1 ;;
        --no-wait) NO_WAIT=1 ;;
        --self-test) SELF_TEST=1 ;;
        -h|--help) awk 'NR > 1 && !/^#/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$0"; exit 0 ;;
        *) die "unknown option '$1' (see --help)" ;;
    esac
    shift
done
case "$HISTORY" in fast|full) ;; *) die "--history is fast or full" ;; esac
case "$X86" in 0|1) ;; *) die "X86 (bootstrap/gate.conf, \$VOLE_GATE_X86) is 0 or 1, not '$X86'" ;; esac
for n in "$CPUS" ${JOBS:+"$JOBS"} ${FUZZ_N:+"$FUZZ_N"} ${ABI_N:+"$ABI_N"}; do
    case "$n" in ''|*[!0-9]*) die "'$n' is not a number" ;; esac
done

# ---- The host ----

case "$(uname -s)-$(uname -m)" in
    Darwin-arm64) HOST=aarch64-macos ;;
    Darwin-x86_64) HOST=x86_64-macos ;;
    Linux-x86_64) HOST=x86_64-linux ;;
    Linux-aarch64) HOST=aarch64-linux ;;
    *) die "unsupported host $(uname -s) $(uname -m)" ;;
esac
NCPU=$(sysctl -n hw.ncpu 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 4)
case "$NCPU" in ''|*[!0-9]*) NCPU=4 ;; esac
# (On macOS more slots than CPUs do not help: a new program's first launch
# waits for the system's check of it, and those checks are taken about
# one at a time; more programs waiting made the gate slower. See
# docs/releases.md, "The gate".)
[ -n "$JOBS" ] || JOBS=$NCPU

# ---- The steps ----

# The counts of each mode: this host's fuzz and ABI programs per mode,
# then x86_64-linux's (emulated on Apple silicon) and aarch64-linux's.
# On macOS every program costs a launch check (docs/releases.md, "The
# gate"), so the volume of random programs is in aarch64-linux, the same
# code generator, natively; tests/fuzz/forever.sh adds more between
# releases.
case "$MODE" in
    quick) FZ=10; AB=20; XFZ=0; XAB=0; AFZ=0; AAB=0 ;;
    default) FZ=30; AB=30; XFZ=25; XAB=20; AFZ=100; AAB=60 ;;
    release) FZ=60; AB=100; XFZ=50; XAB=40; AFZ=300; AAB=150 ;;
esac
# (0.25) fuzz-sem's programs (tools/semfuzz/semfuzz.py: value semantics
# against its own model; each program is built five times)
case "$MODE" in
    quick) SFZ=20 ;;
    default) SFZ=60 ;;
    release) SFZ=300 ;;
esac
[ -z "$FUZZ_N" ] || { FZ=$FUZZ_N; XFZ=$FUZZ_N; AFZ=$FUZZ_N; SFZ=$FUZZ_N; }
[ -z "$ABI_N" ] || { AB=$ABI_N; XAB=$ABI_N; AAB=$ABI_N; }

FUZZ_STEPS="fuzz-plain fuzz-loops fuzz-generics fuzz-pressure fuzz-calls fuzz-lang06 fuzz-vector fuzz-div fuzz-range fuzz-arch fuzz-guard fuzz-seed fuzz-sem"
ABI_STEPS="abi-plain abi-import abi-header"
HOST_STEPS="suite-O0 suite-O1 suite-O2 $FUZZ_STEPS $ABI_STEPS objcheck objcheck-x86-arch layout debug threads incremental stress-grow examples-checkalloc compiler-memcheck voltty-fuzz compile-cost"
# (0.25) the chain's integrity, by --release (or --only): slow, and they
# rebuild compilers rather than test one
RELEASE_STEPS="chain-diverse chain-fresh"
LINUX_STEPS="linux-x86_64 linux-aarch64"
# (0.25.2) --quick's container row, and the steps it runs in the
# container (gate.sh --inside --only 'smoke-*'; run_step says what they
# are)
SMOKE_STEPS="linux-smoke"
INSIDE_SMOKE_STEPS="smoke-runner smoke-lsp smoke-examples smoke-cases smoke-walkthrough smoke-book"
# (steps only --only names: valgrind runs in the linux-aarch64 container)
OTHER_STEPS="valgrind $INSIDE_SMOKE_STEPS"
# (the self-test's steps, only for it)
[ -z "${VOLE_GATE_SELFTEST:-}" ] || OTHER_STEPS="$OTHER_STEPS selftest-sleep selftest-leak selftest-slow"
[ "$X86" = 1 ] || LINUX_STEPS="linux-aarch64"
case "$MODE" in
    quick)
        STEPS="suite-O2 $FUZZ_STEPS abi-plain threads incremental objcheck-x86-arch voltty-fuzz compile-cost"
        [ $LINUX -eq 1 ] && STEPS="$SMOKE_STEPS $STEPS" ;;
    *) STEPS="$HOST_STEPS"; [ $LINUX -eq 1 ] && STEPS="$STEPS $LINUX_STEPS" ;;
esac
[ "$MODE" != release ] || STEPS="$STEPS $RELEASE_STEPS"
if [ -n "$ONLY" ]; then
    # (every known step that one of the patterns matches; the patterns are
    # not file names)
    set -f
    selected=""
    for s in $HOST_STEPS $RELEASE_STEPS $LINUX_STEPS $SMOKE_STEPS $OTHER_STEPS bench; do
        for p in $(echo "$ONLY" | tr ',' ' '); do
            # shellcheck disable=SC2254
            case "$s" in $p) selected="$selected $s"; break ;; esac
        done
    done
    for p in $(echo "$ONLY" | tr ',' ' '); do
        [ "$p" = chain ] && continue
        found=0
        for s in $HOST_STEPS $RELEASE_STEPS $LINUX_STEPS $SMOKE_STEPS $OTHER_STEPS bench; do
            # shellcheck disable=SC2254
            case "$s" in $p) found=1 ;; esac
        done
        [ $found -eq 1 ] || die "no step matches '$p' (see --list$([ "$X86" = 1 ] || echo '; x86_64 is off: --with-x86'))"
    done
    set +f
    STEPS=""
    for s in $selected; do
        if [ "$s" = bench ]; then BENCH=1; else STEPS="$STEPS $s"; fi
    done
fi
# The chain, when a step needs the compiler and none was given.
CHAIN=0
if [ -z "$COMPILER" ]; then
    for s in $STEPS; do
        [ "$s" = linux-x86_64 ] || CHAIN=1
    done
    [ $BENCH -eq 1 ] && CHAIN=1
    case ",$ONLY," in *,chain,*) CHAIN=1 ;; esac
fi
# (0.25.2) The longest steps first: the containers' rows, then the
# runners with the most work (in the aarch64-linux container objcheck and
# the suites were its critical path); the rest after them.
LONG_FIRST="linux-aarch64 linux-smoke objcheck suite-O0 suite-O2 suite-O1 valgrind smoke-cases smoke-book compiler-memcheck stress-grow examples-checkalloc"
ORDERED=""
for s in $LONG_FIRST; do
    case " $STEPS " in *" $s "*) ORDERED="$ORDERED $s" ;; esac
done
for s in $STEPS; do
    case " $LONG_FIRST " in *" $s "*) ;; *) ORDERED="$ORDERED $s" ;; esac
done
if [ $LIST -eq 1 ]; then
    # (in the order they start)
    [ $CHAIN -eq 1 ] && echo chain
    for s in $ORDERED; do echo "$s"; done
    [ $BENCH -eq 1 ] && echo bench
    exit 0
fi

# ---- The gate's own checks (--self-test) ----

# (0.25.2) The lock, the stall check and the steps of each mode, each
# checked on gates of the self-test's steps (selftest-*, a few seconds)
# with a lock and run directories of their own.
self_test() {
    st=$(mktemp -d "${TMPDIR:-/tmp}/vole-gate-selftest.XXXXXX") || exit 2
    trap 'rm -rf "$st"' EXIT
    st_failed=0
    st_row() { printf '  %-28s %s\n' "$1" "$2"; case "$2" in FAIL*) st_failed=1 ;; esac; }
    g() { VOLE_GATE_SELFTEST=1 VOLE_GATE_LOCK="$st/gate.lock" VOLE_GATE_RUNS="$st/runs" sh "$0" -c /bin/sh "$@"; }
    echo "gate: self-test (in $st)"
    # The steps of each mode.
    q=$(sh "$0" --quick --no-x86 --list | tr '\n' ' ')
    case " $q " in *" linux-smoke "*) st_row "quick has linux-smoke" pass ;; *) st_row "quick has linux-smoke" "FAIL: $q" ;; esac
    q=$(sh "$0" --quick --no-linux --list | tr '\n' ' ')
    case " $q " in *" linux-smoke "*) st_row "--no-linux drops it" "FAIL: $q" ;; *) st_row "--no-linux drops it" pass ;; esac
    q=$(sh "$0" --release --list | tr '\n' ' ')
    case " $q " in
        *" linux-smoke "*) st_row "release: no linux-smoke" "FAIL: $q" ;;
        *" linux-aarch64 "*) st_row "release: no linux-smoke" pass ;;
        *) st_row "release: no linux-smoke" "FAIL: no linux-aarch64: $q" ;;
    esac
    # A second gate waits for the first, saying whose it is, then runs.
    g --only selftest-sleep >"$st/a.out" 2>&1 &
    first=$!
    i=0
    while [ ! -f "$st/gate.lock/owner" ] && [ $i -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
    # (the first gate's pid, as its lock says)
    a=$(sed -n 's/^pid=//p' "$st/gate.lock/owner")
    if g --no-wait --only selftest-sleep >"$st/nowait.out" 2>&1; then
        st_row "--no-wait while held" "FAIL: it ran"
    elif grep -q "pid $a" "$st/nowait.out"; then
        st_row "--no-wait while held" "pass ($(head -1 "$st/nowait.out" | cut -c1-60)...)"
    else
        st_row "--no-wait while held" "FAIL: $(head -1 "$st/nowait.out")"
    fi
    if g --only selftest-sleep >"$st/b.out" 2>&1 && grep -q "waiting for the gate .*pid $a" "$st/b.out"; then
        st_row "a second gate waits" pass
    else
        st_row "a second gate waits" "FAIL: $(head -3 "$st/b.out" | tr '\n' ' ')"
    fi
    wait $first || st_row "the first gate" "FAIL: $(tail -3 "$st/a.out" | tr '\n' ' ')"
    [ ! -d "$st/gate.lock" ] && st_row "the lock is released" pass || st_row "the lock is released" "FAIL: $st/gate.lock is left"
    # A dead holder's lock is taken over.
    sh -c 'exit 0' &
    dead=$!
    wait $dead
    mkdir "$st/gate.lock"
    printf 'pid=%s\nstart=gone\nworktree=/nowhere\nargs=--quick\n' "$dead" >"$st/gate.lock/owner"
    if g --no-wait --only selftest-sleep >"$st/stale.out" 2>&1 && grep -q 'took over' "$st/stale.out"; then
        st_row "a dead holder's lock" pass
    else
        st_row "a dead holder's lock" "FAIL: $(head -3 "$st/stale.out" | tr '\n' ' ')"
    fi
    # Without docker running, linux-smoke is a skip that says so.
    mkdir "$st/bin"
    printf '#!/bin/sh\necho "Cannot connect to the Docker daemon" >&2\nexit 1\n' >"$st/bin/docker"
    chmod +x "$st/bin/docker"
    if PATH="$st/bin:$PATH" g --only linux-smoke >"$st/nodocker.out" 2>&1 \
        && grep -q 'linux-smoke .*SKIP .*colima is not running: colima start' "$st/nodocker.out"; then
        st_row "no docker: linux-smoke skips" pass
    else
        st_row "no docker: linux-smoke skips" "FAIL: $(grep 'linux-smoke ' "$st/nodocker.out" | tail -1)"
    fi
    # A slot lost by a killed job: the step waiting for it is stopped and
    # fails, and the gate ends.
    s0=$(date +%s)
    VOLE_GATE_STALL=4 g -j 1 --only selftest-leak,selftest-slow >"$st/leak.out" 2>&1
    rc=$?
    if [ $rc -ne 0 ] && grep -q 'selftest-leak .*FAIL' "$st/leak.out" && grep -q 'stalled' "$st/leak.out" \
        && grep -q 'selftest-slow .*pass' "$st/leak.out"; then
        st_row "a lost slot is reported" "pass (in $(( $(date +%s) - s0 )) s)"
    else
        st_row "a lost slot is reported" "FAIL (exit $rc): $(grep -E 'selftest|stalled' "$st/leak.out" | tr '\n' ' ')"
    fi
    if [ $st_failed -eq 0 ]; then echo "gate: self-test: ok"; else echo "gate: self-test: FAIL (outputs in $st)"; trap - EXIT; fi
    exit $st_failed
}
[ $SELF_TEST -eq 0 ] || self_test

# ---- One gate at a time ----

# (0.25.2) A lock directory for all the worktrees of the repository (in
# the git common dir): its owner file names the gate holding it (pid, the
# process's start time, worktree, arguments). Another gate waits for it,
# saying whose it is, or with --no-wait fails; a lock whose holder is gone
# (no such process, or another process with its pid) is taken over. Not
# taken inside a container, nor by bootstrap.sh --dev (the inner loop).
LOCK=${VOLE_GATE_LOCK:-}
if [ -z "$LOCK" ]; then
    common=$(cd "$ROOT" && git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
    if [ -n "$common" ]; then LOCK="$common/gate.lock"; else LOCK="$ROOT/target/gate.lock"; fi
fi
LOCK_HELD=0
proc_start() { ps -o lstart= -p "$1" 2>/dev/null | sed 's/  */ /g; s/^ //; s/ $//'; }
owner_field() { sed -n "s/^$1=//p" "$LOCK/owner" 2>/dev/null | head -1; }
# The holder is alive: its pid runs, and is the same process.
holder_alive() { # <pid> <start>
    [ -n "$1" ] && kill -0 "$1" 2>/dev/null || return 1
    [ "$2" = "$(proc_start "$1")" ]
}
release_lock() {
    [ $LOCK_HELD -eq 1 ] && [ "$(owner_field pid)" = $$ ] && rm -rf "$LOCK"
    LOCK_HELD=0
}
take_lock() {
    tl_said=""
    tl_since=$(date +%s)
    tl_missing=0
    mkdir -p "$(dirname "$LOCK")"
    while :; do
        if mkdir "$LOCK" 2>/dev/null; then
            printf 'pid=%s\nstart=%s\nworktree=%s\nsince=%s\nargs=%s\n' $$ "$(proc_start $$)" "$ROOT" \
                "$(date '+%H:%M:%S')" "$GATE_ARGS" >"$LOCK/owner.new" && mv "$LOCK/owner.new" "$LOCK/owner"
            LOCK_HELD=1
            [ -z "$tl_said" ] || echo "gate: the lock is ours, after $(( $(date +%s) - tl_since )) s"
            return 0
        fi
        pid=$(owner_field pid)
        if [ -z "$pid" ]; then
            # (being written; or its gate died before writing it)
            tl_missing=$((tl_missing + 1))
            if [ $tl_missing -ge 3 ]; then
                mv "$LOCK" "$LOCK.stale.$$" 2>/dev/null && rm -rf "$LOCK.stale.$$"
                echo "gate: took over the lock $LOCK (no owner)"
                tl_missing=0
            fi
            sleep 2
            continue
        fi
        tl_missing=0
        who="the gate in $(owner_field worktree) (pid $pid, since $(owner_field since), gate.sh $(owner_field args))"
        if ! holder_alive "$pid" "$(owner_field start)"; then
            # (moved away first, so only one of several waiters takes it;
            # the owner checked again, the lock may have just changed hands)
            if [ "$(owner_field pid)" = "$pid" ] && mv "$LOCK" "$LOCK.stale.$$" 2>/dev/null; then
                rm -rf "$LOCK.stale.$$"
                echo "gate: took over the lock of $who: it is gone"
            fi
            continue
        fi
        [ $NO_WAIT -eq 0 ] || { echo "gate: error: $who holds the gate lock ($LOCK); without --no-wait this waits for it" >&2; exit 3; }
        if [ "$tl_said" != "$pid" ]; then
            echo "gate: waiting for $who: one gate at a time ($LOCK; --no-wait fails instead)"
            tl_said=$pid
        fi
        sleep 3
    done
}
[ $INSIDE -eq 1 ] || { take_lock; trap release_lock EXIT; }

# ---- The run's directory, the slots ----

if [ $INSIDE -eq 1 ]; then
    RUN="$ROOT/target/gate/inside"
    rm -rf "$RUN"
else
    RUN="${VOLE_GATE_RUNS:-$ROOT/target/gate}/$(date +%Y%m%d-%H%M%S)"
fi
mkdir -p "$RUN"
[ $INSIDE -eq 1 ] || ln -sfn "$(basename "$RUN")" "${VOLE_GATE_RUNS:-$ROOT/target/gate}/last"
rm -f "$RUN/jobs"
mkfifo "$RUN/jobs"
exec 9<>"$RUN/jobs"
i=0
while [ $i -lt "$JOBS" ]; do
    echo >&9
    i=$((i + 1))
done
VOLE_JOBSERVER="$RUN/jobs"
export VOLE_JOBSERVER

# (0.21, for 0.24's rename) The compiler's name and root at HEAD, from
# bootstrap/releases.toml's [head].
HEAD_BIN=$(sh "$ROOT/bootstrap/release-tags.sh" --head bin)
HEAD_ROOT="$ROOT/$(sh "$ROOT/bootstrap/release-tags.sh" --head compiler)/$(sh "$ROOT/bootstrap/release-tags.sh" --head root)"
if [ -n "$COMPILER" ]; then
    case "$COMPILER" in /*) ;; *) COMPILER="$(pwd)/$COMPILER" ;; esac
    [ -x "$COMPILER" ] || die "no compiler at $COMPILER"
    cp "$COMPILER" "$RUN/$HEAD_BIN"
fi
C="$RUN/$HEAD_BIN"

# The bootstrap caches: this checkout's, then the shared one (bootstrap.sh:
# $VOLE_BOOTSTRAP_CACHE, or the main checkout's in a linked worktree).
BOOT_CACHES="$ROOT/target/bootstrap"
if [ -n "${VOLE_BOOTSTRAP_CACHE:-}" ]; then
    BOOT_CACHES="$BOOT_CACHES $VOLE_BOOTSTRAP_CACHE"
else
    common=$(cd "$ROOT" && git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
    [ -z "$common" ] || [ "$(dirname "$common")" = "$ROOT" ] \
        || BOOT_CACHES="$BOOT_CACHES $(dirname "$common")/target/bootstrap"
fi

# The seed (the third oracle of fuzz-seed): given, or the bootstrap's.
find_seed() {
    [ -n "$SEED_BIN" ] && { echo "$SEED_BIN"; return; }
    for s in $(for b in $BOOT_CACHES; do echo "$b"/"$HOST"/seed-*/target/release/tachyon; done); do
        [ -x "$s" ] && { echo "$s"; return; }
    done
}

# The newest release built here (for bench/run.sh -p), in the order of
# releases.toml; (0.21) each by its compiler's name.
find_previous() {
    fp=""
    sh "$ROOT/bootstrap/release-tags.sh" --bins >"$RUN/release-bins"
    while read -r tag bin; do
        for b in $BOOT_CACHES; do
            for p in "$b"/"$HOST"/"$tag"-*/"$bin"; do
                [ -x "$p" ] && { fp=$p; break 2; }
            done
        done
    done <"$RUN/release-bins"
    echo "$fp"
}

# (0.21.1) The newest release built here that is not this commit (for
# compile-cost: on the tagged commit, the one before it).
find_previous_release() {
    head=$(cd "$ROOT" && git rev-parse HEAD 2>/dev/null | cut -c1-12)
    fp=""
    for tag in $(sh "$ROOT/bootstrap/release-tags.sh"); do
        for b in $BOOT_CACHES; do
            # (0.24: the releases up to 0.23 are tachyonc, releases.toml's bin)
            for p in "$b"/"$HOST"/"$tag"-*/volec "$b"/"$HOST"/"$tag"-*/tachyonc; do
                [ -x "$p" ] || continue
                case "$p" in *-"$head"/volec|*-"$head"/tachyonc) continue ;; esac
                fp=$p
                break 2
            done
        done
    done
    echo "$fp"
}

# Runs step $1 (its output is its log). Exit 77: skipped, the reason on the
# last line.
run_step() {
    k="$RUN/failures/$1"
    case "$1" in
        chain)
            sh "$ROOT/bootstrap/bootstrap.sh" --dev --no-head-tests --history "$HISTORY" </dev/null \
                && cp "$ROOT/target/$HEAD_BIN" "$C" ;;
        suite-O2)
            VOLE_CODE_CACHE=on VOLE_CACHE="$RUN/code-cache" sh "$ROOT/tests/run.sh" -c "$C" -O 2
            st=$?
            rm -rf "$RUN/code-cache"
            return $st ;;
        suite-O*) sh "$ROOT/tests/run.sh" -c "$C" -O "${1#suite-O}" ;;
        fuzz-plain) sh "$ROOT/tests/fuzz/run.sh" -c "$C" -n "$FZ" -k "$k" ;;
        fuzz-loops) sh "$ROOT/tests/fuzz/run.sh" -c "$C" -n "$FZ" -k "$k" -l ;;
        fuzz-generics) sh "$ROOT/tests/fuzz/run.sh" -c "$C" -n "$FZ" -k "$k" -g ;;
        fuzz-pressure) sh "$ROOT/tests/fuzz/run.sh" -c "$C" -n "$FZ" -k "$k" -p ;;
        fuzz-calls) sh "$ROOT/tests/fuzz/run.sh" -c "$C" -n "$FZ" -k "$k" -C ;;
        fuzz-lang06) sh "$ROOT/tests/fuzz/run.sh" -c "$C" -n "$FZ" -k "$k" -N ;;
        fuzz-vector) sh "$ROOT/tests/fuzz/run.sh" -c "$C" -n "$FZ" -k "$k" -V ;;
        fuzz-div) sh "$ROOT/tests/fuzz/run.sh" -c "$C" -n "$FZ" -k "$k" -D ;;
        fuzz-range) sh "$ROOT/tests/fuzz/run.sh" -c "$C" -n "$FZ" -k "$k" -R ;;
        fuzz-arch) sh "$ROOT/tests/fuzz/run.sh" -c "$C" -n "$FZ" -k "$k" -A ;;
        fuzz-guard) sh "$ROOT/tests/fuzz/run.sh" -c "$C" -n "$FZ" -k "$k" -G ;;
        # (0.25) value semantics: seeded (the same programs every run of
        # a mode), failing ones shrunk and kept with their expected output;
        # 0.25.2: as many again with --assign-calls (owned
        # assignments whose right side is a call, lending temporaries)
        fuzz-sem) python3 "$ROOT/tools/semfuzz/semfuzz.py" -c "$C" -n "$SFZ" -f 1 -k "$k" \
            && python3 "$ROOT/tools/semfuzz/semfuzz.py" -c "$C" -n "$SFZ" -f 1 -k "$k" --assign-calls ;;
        fuzz-seed)
            seed=$(find_seed)
            if [ -z "$seed" ]; then
                echo "no seed binary for $HOST"
                return 77
            fi
            sh "$ROOT/tests/fuzz/run.sh" -c "$C" -n "$FZ" -k "$k" -s "$seed" ;;
        abi-plain) sh "$ROOT/tests/abi/run.sh" -c "$C" -n "$AB" -k "$k" ;;
        abi-import) sh "$ROOT/tests/abi/run.sh" -c "$C" -n "$AB" -k "$k" -i ;;
        abi-header) sh "$ROOT/tests/abi/run.sh" -c "$C" -n "$AB" -k "$k" -H ;;
        objcheck) sh "$ROOT/tests/objcheck.sh" -c "$C" ;;
        # (0.19: x86-64's intrinsics are encoded and checked against cc on
        # any host; no x86 CPU needed, so --no-x86 keeps it)
        objcheck-x86-arch) sh "$ROOT/tests/objcheck.sh" -c "$C" -t x86_64-macos arch_ ;;
        layout)
            (cd "$ROOT" && sh tests/cimport/layout.sh -c "$C" stdio.h stdlib.h string.h math.h \
                time.h fcntl.h unistd.h signal.h sys/stat.h sys/time.h sys/socket.h \
                netinet/in.h dirent.h pthread.h) ;;
        debug) sh "$ROOT/tests/debug.sh" -c "$C" ;;
        threads) sh "$ROOT/tests/threads_writes.sh" -c "$C" && sh "$ROOT/tests/threads.sh" -c "$C" ;;
        incremental) sh "$ROOT/tests/incremental.sh" -c "$C" ;;
        voltty-fuzz) sh "$ROOT/tests/voltty/run.sh" -c "$C" -s 60 -k "$k" ;;
        stress-grow)
            # (0.14) The compiler with VOLE_STRESS_GROW=1 (base::grow):
            # every growth of its tables moves them and poisons the old
            # block, so a read through a stale table pointer shows. Its
            # self-compile gives the same object as without, and the suite
            # passes at -O0 and -O2.
            o="$RUN/stress-grow"
            mkdir -p "$o"
            "$C" "$HEAD_ROOT" -o "$o/plain.o" || return 1
            VOLE_STRESS_GROW=1 "$C" "$HEAD_ROOT" -o "$o/stress.o" || return 1
            cmp -s "$o/plain.o" "$o/stress.o" \
                || { echo "stress-grow: the self-compile differs: $o/plain.o $o/stress.o"; return 1; }
            for level in 0 2; do
                VOLE_STRESS_GROW=1 sh "$ROOT/tests/run.sh" -c "$C" -O $level || return 1
            done
            echo "stress-grow: the self-compile is the same; the suite passes at -O0 and -O2" ;;
        valgrind) sh "$ROOT/tests/valgrind.sh" -c "$C" ;;
        compiler-memcheck) sh "$ROOT/tests/compiler_memcheck.sh" -c "$C" ;;
        chain-diverse)
            previous=$(find_previous_release)
            sh "$ROOT/bootstrap/chain-diverse.sh" ${previous:+-p "$previous"} -w "$RUN/chain-diverse" ;;
        chain-fresh) sh "$ROOT/bootstrap/chain-fresh.sh" -w "$RUN/chain-fresh" --history "$HISTORY" ;;
        compile-cost)
            previous=$(find_previous_release)
            sh "$ROOT/tests/compile_cost.sh" -c "$C" ${previous:+-p "$previous"} ;;
        examples-checkalloc)
            # (0.16) Every example's test (tests/examples/*.test) with the
            # program built by --check-alloc (the checking Gpa: blocks on
            # pages of their own, never reused): a use after free, a double
            # free or a wrong free in an example stops it, so one cannot
            # come back unnoticed (examples/errors-and-results had one).
            # (a case whose output differs by design with the flag says
            # NO-EXTRA-FLAGS; a checked program runs slower: 2 minutes)
            VOLE_TEST_FLAGS=--check-alloc VOLE_TEST_TIMEOUT=120 \
                sh "$ROOT/tests/run.sh" -c "$C" example >"$RUN/examples-checkalloc.out" 2>&1
            rc=$?
            cat "$RUN/examples-checkalloc.out"
            awk '$1 == "total" { printf "examples-checkalloc: %d passed, %d failed with --check-alloc\n", $2, $4 }' \
                "$RUN/examples-checkalloc.out"
            return $rc ;;
        linux-x86_64)
            command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 \
                || { echo "docker is not running (start it, e.g. colima start; or --no-linux)"; return 1; }
            sh "$ROOT/bootstrap/linux-check.sh" --worktree --dev --cpus "$CPUS" \
                --history "$HISTORY" $([ $FRESH -eq 1 ] && echo --fresh) \
                --all-levels --fuzz="$XFZ" --abi="$XAB" --objcheck </dev/null ;;
        linux-aarch64)
            command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 \
                || { echo "docker is not running (start it, e.g. colima start; or --no-linux)"; return 1; }
            # (0.25.2) the suite at -O0 and -O2, not -O1: the optimizer is
            # the same for every target and -O1 runs on macOS; what is
            # Linux's own (the ABI, libc, the link) -O0 and -O2 exercise.
            # It was a third of the row, the gate's longest.
            sh "$ROOT/bootstrap/aarch64-linux-check.sh" --worktree --dev --compiler "$C" --cpus "$CPUS" \
                --levels=0,2 --fuzz="$AFZ" --abi="$AAB" --objcheck --debugger \
                $([ "$MODE" = release ] && echo --valgrind) </dev/null ;;
        linux-smoke)
            # (0.25.2) --quick's look at Linux: the compiler cross-built for
            # aarch64-linux, then in the container the smoke-* steps (no
            # fixpoint, no fuzz: the full gate's linux-aarch64 has them).
            # Not run is said, not passed.
            command -v docker >/dev/null 2>&1 \
                || { echo "docker is not installed (brew install colima docker; colima start)"; return 77; }
            docker info >/dev/null 2>&1 || { echo "colima is not running: colima start"; return 77; }
            sh "$ROOT/bootstrap/aarch64-linux-check.sh" --worktree --dev --compiler "$C" --cpus "$CPUS" \
                --smoke </dev/null ;;
        # (0.25.2) linux-smoke's steps, in the container, at -O2: the test
        # runner's own checks (tests/runner/run.sh, the runner_* cases),
        # the language server's sessions, every example built
        # (example_build), every case (all their names have a `_`: 2,800
        # programs, about a minute) and the walkthroughs' and the book's
        # sessions, which differed on Linux before. Not query's and
        # refactor's transcripts (serial, 6 and 8 minutes beside the rest),
        # the formatter's (the same on every host) or the other tools'
        # small suites: the full gate's linux-aarch64 runs them.
        smoke-runner) sh "$ROOT/tests/run.sh" -c "$C" -O 2 runner ;;
        smoke-lsp) sh "$ROOT/tests/run.sh" -c "$C" -O 2 lsp ;;
        smoke-examples) sh "$ROOT/tests/run.sh" -c "$C" -O 2 example_build ;;
        smoke-cases) sh "$ROOT/tests/run.sh" -c "$C" -O 2 _ ;;
        smoke-walkthrough|smoke-book) sh "$ROOT/tests/run.sh" -c "$C" -O 2 "${1#smoke-}" ;;
        # (the self-test's steps: a few seconds; a slot taken and never
        # given back, as by a job killed with -9; a step busy for a while)
        selftest-sleep) sleep 3; echo "selftest: slept 3 s" ;;
        selftest-leak)
            exec 3<>"$VOLE_JOBSERVER"
            read -r _ <&3
            echo "selftest: took the slot, and wait for another"
            read -r _ <&3 ;;
        selftest-slow)
            e=$(( $(date +%s) + 7 ))
            while [ "$(date +%s)" -lt $e ]; do awk 'BEGIN { while (i < 2e6) i++ }'; done
            echo "selftest: busy, done" ;;
        bench)
            previous=$(find_previous)
            seed=$(find_seed)
            echo "load average before: $(uptime | sed 's/.*load averages*: //')"
            sh "$ROOT/bench/run.sh" -c "$C" ${previous:+-p "$previous"} ${seed:+-s "$seed"} -r 5 ;;
        *) echo "unknown step $1"; return 1 ;;
    esac
}

# ---- The scheduler ----

now() { date +%s; }
GATE_START=$(now)
STARTED=""
REPORTED=""

start() { # <step>
    now >"$RUN/$1.start"
    (
        # (the gate's lock is not this subshell's to release)
        LOCK_HELD=0
        s=$(now)
        run_step "$1" </dev/null >"$RUN/$1.log" 2>&1
        rc=$?
        echo "$rc $(( $(now) - s ))" >"$RUN/$1.status"
    ) &
    echo $! >"$RUN/$1.pid"
    STARTED="$STARTED $1"
}

# ---- Stalls (0.25.2) ----

# A step none of whose processes used the CPU, started or ended for
# $VOLE_GATE_STALL seconds (default 600) has stalled: a release gate once
# waited 2.5 hours on runners whose slots had all been lost with killed
# jobs. Such a step is stopped and fails, saying how many slots were
# free. (Not the containers' rows: their work is in the VM, and the gate
# inside a container checks its own steps. `sleep` does not count: a
# step that only sleeps is waiting.)
STALL=${VOLE_GATE_STALL:-600}
case "$STALL" in ''|*[!0-9]*|0) STALL=600 ;; esac
STALL_EVERY=15
[ "$STALL" -ge 60 ] || STALL_EVERY=1
STALL_NEXT=0

# The processes: pid, parent, CPU time, command (ps; in a container
# without ps, /proc).
proc_table() {
    if command -v ps >/dev/null 2>&1; then
        ps -A -o pid= -o ppid= -o time= -o comm= 2>/dev/null
    elif [ -d /proc/self ]; then
        cat /proc/[0-9]*/stat 2>/dev/null | awk '{
            l = $0; i = index(l, "("); j = 0
            for (k = length(l); k > i; k--) if (substr(l, k, 1) == ")") { j = k; break }
            if (j == 0) next
            split(substr(l, j + 2), f, " ")
            print $1, f[2], f[12] + f[13], substr(l, i + 1, j - i - 1)
        }'
    fi
}

# The free slots of the pool (the bytes in its FIFO), or "?".
free_slots() {
    case "$(uname -s)" in Darwin) fionread=1074030207 ;; Linux) fionread=21531 ;; *) echo "?"; return ;; esac
    perl -e 'open(my $f, "+<", $ARGV[0]) or exit 1; my $n = pack("L", 0);
        ioctl($f, $ARGV[1], $n) or exit 1; print unpack("L", $n), "\n"' "$RUN/jobs" "$fionread" 2>/dev/null || echo "?"
}

# Kills step $1's processes (its subshell and everything below it):
# TERM, which lets the runners' jobs give their slots back, then KILL.
kill_tree() { # <pid>
    kt=$(proc_table | awk -v root="$1" '
        { parent[$1] = $2 }
        END {
            for (p in parent) {
                q = p
                while ((q in parent) && q != root && q > 1) q = parent[q]
                if (q == root) print p
            }
        }')
    [ -n "$kt" ] || return 0
    # shellcheck disable=SC2086
    kill -TERM $kt 2>/dev/null
    sleep 2
    # shellcheck disable=SC2086
    kill -KILL $kt 2>/dev/null
}

check_stalls() {
    t=$(now)
    [ "$t" -ge "$STALL_NEXT" ] || return 0
    STALL_NEXT=$((t + STALL_EVERY))
    roots=""
    for s in $STARTED; do
        case " $REPORTED " in *" $s "*) continue ;; esac
        case "$s" in linux-*) continue ;; esac
        [ -f "$RUN/$s.status" ] || [ ! -f "$RUN/$s.pid" ] || roots="$roots $s=$(cat "$RUN/$s.pid")"
    done
    [ -n "$roots" ] || return 0
    # One signature per step: its processes (but sleep) and their CPU times.
    proc_table | awk -v roots="$roots" '
        BEGIN { n = split(roots, r, " "); for (i = 1; i <= n; i++) { split(r[i], kv, "="); step[kv[2]] = kv[1] } }
        { parent[$1] = $2; line[$1] = $1 ":" $3; if ($0 ~ /(^| |\/)sleep$/) skip[$1] = 1 }
        END {
            for (p in parent) {
                if (p in skip) continue
                q = p
                while (!(q in step) && (q in parent) && q > 1) q = parent[q]
                if (q in step) sig[step[q]] = sig[step[q]] " " line[p]
            }
            for (i = 1; i <= n; i++) { split(r[i], kv, "="); print kv[1], (kv[1] in sig ? sig[kv[1]] : "") }
        }' >"$RUN/stall.sigs"
    while read -r s sig; do
        if [ ! -f "$RUN/$s.sig" ] || [ "$(cat "$RUN/$s.sig")" != "$sig" ]; then
            printf '%s\n' "$sig" >"$RUN/$s.sig"
            echo "$t" >"$RUN/$s.sigt"
            continue
        fi
        [ $(( t - $(cat "$RUN/$s.sigt") )) -ge "$STALL" ] || continue
        free=$(free_slots)
        why="stalled: no process of it ran, started or ended for $STALL s, with $free of $JOBS slots free$([ "$free" = 0 ] && echo ' (slots lost with killed jobs?)'); stopped"
        [ $INSIDE -eq 1 ] || echo "  $s: $why" >&2
        kill_tree "$(cat "$RUN/$s.pid")"
        echo "--- $s: $why" >>"$RUN/$s.log"
        echo "$why" >"$RUN/$s.stalled"
        echo "1 $(( t - $(cat "$RUN/$s.start") ))" >"$RUN/$s.status"
    done <"$RUN/stall.sigs"
}

mmss() { printf '%d:%02d' $(( $1 / 60 )) $(( $1 % 60 )); }

result_of() { # <step>: pass, FAIL, SKIP or "not run"
    if [ -f "$RUN/$1.status" ]; then
        read -r rc _ <"$RUN/$1.status"
        case "$rc" in
            0) echo pass ;;
            77) echo SKIP ;;
            *) echo FAIL ;;
        esac
    else
        echo "not run"
    fi
}

# Reports the steps that finished since the last call; sets RUNNING to
# the number still running.
poll() {
    RUNNING=0
    for s in $STARTED; do
        case " $REPORTED " in *" $s "*) continue ;; esac
        if [ -f "$RUN/$s.status" ]; then
            read -r _ secs <"$RUN/$s.status"
            REPORTED="$REPORTED $s"
            [ $INSIDE -eq 1 ] || printf '  %-16s %-5s %6s   (at %s)\n' "$s" "$(result_of "$s")" "$(mmss "$secs")" "$(mmss $(( $(now) - GATE_START )))"
        else
            RUNNING=$((RUNNING + 1))
        fi
    done
}

wait_all() {
    poll
    while [ $RUNNING -gt 0 ]; do
        sleep 1
        check_stalls
        poll
    done
}

cleanup() {
    trap - INT TERM
    echo "gate: interrupted; logs in $RUN" >&2
    # Every process below this one (the containers are stopped by their
    # scripts' traps); without ps, the process group.
    if command -v ps >/dev/null 2>&1; then
        # shellcheck disable=SC2046
        kill $(ps -A -o pid= -o ppid= | awk -v root=$$ '
            { parent[$1] = $2 }
            END {
                for (p in parent) {
                    q = p
                    while ((q in parent) && q != root && q > 1) q = parent[q]
                    if (q == root && p != root) print p
                }
            }') 2>/dev/null
    else
        kill 0 2>/dev/null
    fi
    exit 130
}
trap cleanup INT TERM

[ $INSIDE -eq 1 ] || {
    echo "gate: $MODE on $HOST, $JOBS slots${COMPILER:+, compiler $COMPILER}; logs in $RUN"
    echo "  steps: $(echo $([ $CHAIN -eq 1 ] && echo chain) $STEPS $([ $BENCH -eq 1 ] && echo bench))"
}

# On macOS, the first launch of every new executable waits for the
# system's check of it (syspolicyd and XProtect), unless the program that
# runs the gate (the terminal) is a developer tool. Every test program is
# new: measured here, on a new program.
LAUNCH_NOTE=""
case "$HOST" in
    *-macos)
        if command -v perl >/dev/null 2>&1 && printf 'int main(void) { return 0; }\n' >"$RUN/probe.c" \
            && ${CC:-cc} -o "$RUN/probe" "$RUN/probe.c" 2>/dev/null; then
            ms=$(perl -MTime::HiRes=time -e '$t = time; system($ARGV[0]); printf "%d", (time - $t) * 1000' "$RUN/probe")
            if [ "${ms:-0}" -ge 50 ]; then
                LAUNCH_NOTE="a new program's first launch took ${ms} ms here (macOS checks it: about one per test); adding the terminal to System Settings > Privacy & Security > Developer Tools removes that wait (docs/releases.md, \"The gate\")"
                [ $INSIDE -eq 1 ] || echo "  note: $LAUNCH_NOTE"
            fi
        fi ;;
esac

# The x86_64-linux container builds its own chain: it starts at once.
case " $STEPS " in *" linux-x86_64 "*) start linux-x86_64 ;; esac
if [ $CHAIN -eq 1 ]; then
    start chain
    while [ ! -f "$RUN/chain.status" ]; do
        sleep 1
        check_stalls
    done
    poll
fi
if [ $CHAIN -eq 0 ] || [ "$(result_of chain)" = pass ]; then
    for s in $ORDERED; do
        [ "$s" = linux-x86_64 ] || start "$s"
    done
fi
wait_all
if [ $BENCH -eq 1 ] && { [ $CHAIN -eq 0 ] || [ "$(result_of chain)" = pass ]; }; then
    [ $INSIDE -eq 1 ] || echo "  (the benchmarks, alone)"
    start bench
    wait_all
fi
GATE_SECS=$(( $(now) - GATE_START ))

# ---- The summary ----

# One line about step $1's outcome, from its log.
note_of() {
    l="$RUN/$1.log"
    [ -f "$l" ] || return
    [ -f "$RUN/$1.stalled" ] && { cat "$RUN/$1.stalled"; return; }
    case "$1" in
        chain) awk '/^  head / { sub(/^  head +/, ""); print; exit }' "$l" ;;
        suite-*|smoke-*) awk '$1 == "total" { printf "%d passed, %d xfail, %d failed%s\n", $2, $3, $4, ($5 > 0 ? ", " $5 " SKIPPED" : "") }' "$l" ;;
        fuzz-*|abi-*|objcheck|objcheck-*|layout|debug|threads|incremental|stress-grow|examples-checkalloc|valgrind|compiler-memcheck|chain-*)
            grep -E '^(fuzz|abi|objcheck|objcheck-*|layout|debug|threads|incremental|stress-grow|examples-checkalloc|valgrind|compiler-memcheck|chain-diverse|chain-fresh):' "$l" | tail -1 ;;
        voltty-fuzz) grep -E '^(pass|FAIL|skip) oracle' "$l" | tail -1 ;;
        compile-cost) awk '$2 ~ /^[0-9.]+$/ && $3 == "M" { printf "%s%s %s M %s", sep, $1, $2, $8; sep = ", " } END { print "" }' "$l" ;;
        # (no rows: it failed before the container's steps, e.g. docker)
        linux-*)
            if grep -q '^gate-row' "$l"; then
                grep '^gate-row' "$l" | awk -F'\t' '$3 != "pass" && $3 != "SKIP" && $3 != "skip" { bad = bad " " $2 } END { n = NR; print n " steps in the container" (bad == "" ? "" : "; failed:" bad) }'
            elif [ "$(result_of "$1")" != SKIP ]; then
                grep -E 'error' "$l" | tail -1
            fi ;;
        bench) grep '^geomean' "$l" | tail -1 ;;
    esac
    [ "$(result_of "$1")" = SKIP ] && tail -1 "$l"
}

ROWS="$RUN/rows"
: >"$ROWS"
FAILED=0
for s in $([ $CHAIN -eq 1 ] && echo chain) $STEPS $([ $BENCH -eq 1 ] && echo bench); do
    r=$(result_of "$s")
    secs=0
    [ -f "$RUN/$s.status" ] && read -r _ secs <"$RUN/$s.status"
    case "$r" in pass|SKIP) ;; *) FAILED=$((FAILED + 1)) ;; esac
    printf '%s\t%s\t%s\t%s\n' "$s" "$r" "$secs" "$(note_of "$s" | head -1)" >>"$ROWS"
    # The containers' own steps, under theirs.
    case "$s" in
        linux-*) grep '^gate-row' "$RUN/$s.log" 2>/dev/null | cut -f2- | sed "s|^|$s/|" >>"$ROWS" ;;
    esac
done

if [ $INSIDE -eq 1 ]; then
    sed 's/^/gate-row	/' "$ROWS"
fi
echo
echo "gate: $MODE on $HOST$([ $INSIDE -eq 1 ] && echo " (inside a container)")"
awk -F'\t' '{ printf "  %-28s %-7s %7s  %s\n", $1, $2, sprintf("%d:%02d", $3 / 60, $3 % 60), $4 }' "$ROWS"
printf '  %-28s %-7s %7s\n' "total (wall)" "$([ $FAILED -eq 0 ] && echo pass || echo FAIL)" "$(mmss "$GATE_SECS")"
[ -z "$LAUNCH_NOTE" ] || echo "  note: $LAUNCH_NOTE"

# The failures' details.
for s in $([ $CHAIN -eq 1 ] && echo chain) $STEPS $([ $BENCH -eq 1 ] && echo bench); do
    case "$(result_of "$s")" in pass|SKIP) continue ;; esac
    echo
    echo "--- $s: $(result_of "$s") (log: $RUN/$s.log)"
    l="$RUN/$s.log"
    [ -f "$l" ] || { echo "    not run (the chain failed)"; continue; }
    case "$s" in
        suite-*|smoke-*|examples-checkalloc) awk '/^tests for / { exit } { print }' "$l" | head -60 ;;
        fuzz-*|abi-*|objcheck|objcheck-*|threads|incremental|voltty-fuzz|compiler-memcheck|chain-*) grep -E '^FAIL' "$l" | head -20; [ -d "$RUN/failures/$s" ] && echo "    kept in $RUN/failures/$s" ;;
        compile-cost) cat "$l" ;;
        linux-*) awk '/^--- / { p = 1 } p' "$l" | head -80; grep -q '^--- ' "$l" || tail -30 "$l" ;;
        *) tail -30 "$l" ;;
    esac
done
# (0.25.2) The suites' skipped checks, with their reasons (a window test
# without a display giving frames, ...): skipped is not passed.
for s in $STEPS; do
    case "$s" in suite-*|smoke-*|examples-checkalloc) ;; *) continue ;; esac
    l="$RUN/$s.log"
    [ -f "$l" ] && grep -q '^SKIP ' "$l" || continue
    echo
    echo "--- $s: skipped, not passed (log: $l)"
    grep '^SKIP ' "$l" | head -20 | sed 's/^/    /'
done
[ $INSIDE -eq 1 ] || [ $FAILED -eq 0 ] || echo
[ $FAILED -eq 0 ]
