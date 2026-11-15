#!/bin/sh
# (0.30.1) A gate row that passed must also have counted what it exists to
# count: bootstrap/gate.sh runs this on the log of every row that passed,
# and a row whose count is missing, zero or far below its floor fails (it
# passed because it did not look). The floors are 0.30.0's release gate's
# counts (target/gate/20261114-170217 of its worktree) less a margin for
# cases that come and go, or the count the row was asked for (the fuzz
# and ABI rows: every program asked for is counted). A row without a line
# here has no count to hold (its log names one thing it checks): it says
# so, and passes.
#
# usage: bootstrap/gate-floors.sh STEP LOG FZ AB SFZ
#   STEP   the gate's step (suite-O2, fuzz-loops, objcheck, ...)
#   LOG    its log
#   FZ AB SFZ   the programs gate.sh asked of the fuzz, ABI and value
#          semantics rows (its --quick, default or --release counts)
# Prints one line, `floor STEP: ...`; exits 1 when the row is below its
# floor.
#
# tests/gate_floors.sh checks this script: each row's 0.30.0 line passes,
# the same line with a zero or a low count fails.
set -u
LC_ALL=C
export LC_ALL
[ $# -eq 5 ] || { echo "usage: bootstrap/gate-floors.sh STEP LOG FZ AB SFZ" >&2; exit 2; }
STEP=$1
LOG=$2
FZ=$3
AB=$4
SFZ=$5
[ -f "$LOG" ] || { echo "floor $STEP: no log $LOG"; exit 1; }

# The first number after the text $1 on the last line of the log that
# matches the pattern $1 (an extended regular expression ending where the
# number starts), or nothing.
count() {
    grep -E "$1" "$LOG" | tail -1 | sed -E "s/^.*$1([0-9]+).*$/\\1/" | grep -E '^[0-9]+$'
}
# The number of lines of the log matching $1.
lines() {
    grep -cE "$1" "$LOG"
}

# STEP's count against floor $2: $1 the count (empty: none found), $3 what
# it counts.
judge() { # <count> <floor> <what>
    if [ -z "$1" ]; then
        echo "floor $STEP: no count of $3 in its log: the row passed without saying what it checked"
        exit 1
    fi
    if [ "$1" -lt "$2" ]; then
        echo "floor $STEP: $1 $3, below its floor of $2: the row passed on too little"
        exit 1
    fi
    echo "floor $STEP: $1 $3 (floor $2)"
    exit 0
}

case "$STEP" in
    # (0.30.0: 6556 passed of 7274 at each level)
    suite-O0|suite-O1|suite-O2)
        judge "$(grep -E '^ +total +[0-9]+' "$LOG" | tail -1 | awk '{print $2}')" 6000 "cases passed" ;;
    # (each program asked for is counted: -n FZ)
    fuzz-plain|fuzz-loops|fuzz-generics|fuzz-pressure|fuzz-calls|fuzz-lang06|fuzz-vector|fuzz-div|fuzz-range|fuzz-arch|fuzz-guard|fuzz-seed)
        judge "$(count 'fuzz: ')" "$FZ" "programs" ;;
    # (five runs of SFZ programs each)
    fuzz-sem)
        n=$(lines "^fuzz: $SFZ value-semantics programs, 0 failing \\($SFZ ok\\)")
        judge "$n" 5 "runs of $SFZ value-semantics programs all checked" ;;
    abi-plain|abi-import|abi-header)
        judge "$(count 'abi: ')" "$AB" "programs" ;;
    # (0.30.0: 13048 of 13048)
    objcheck)
        judge "$(count 'objcheck: ')" 12000 "compilations compared with cc -c" ;;
    # (0.30.0: 260)
    objcheck-x86-arch)
        judge "$(count 'objcheck: ')" 230 "compilations compared with cc -c" ;;
    # (layout.sh has its own floor, -m: 100 records on macOS)
    layout)
        judge "$(count 'layout: ')" 100 "records" ;;
    # (one program at two levels)
    debug)
        judge "$(lines '^ok -O[02]$')" 2 "levels run under the debugger" ;;
    # (0.30.0: 16015)
    threads)
        judge "$(count 'threads: ')" 14000 "compilations compared at -j1 and -j8" ;;
    # (0.30.0: 172 series; 0.30.1: and the pairs, 24 builds)
    incremental)
        p=$(count 'incremental pairs: ')
        [ -n "$p" ] && [ "$p" -ge 24 ] || { echo "floor $STEP: ${p:-no} warm builds of the pairs, below its floor of 24"; exit 1; }
        judge "$(count 'incremental: ')" 150 "edit series (and $p warm builds of the pairs)" ;;
    # (four measures: hello, std, check, regions)
    compile-cost)
        judge "$(lines 'M instructions, was ')" 4 "programs measured" ;;
    # (0.30.1: the audit's canary, planted sites it must find)
    unsafe-audit)
        judge "$(lines 'the canary caught \(4 unjustified, 1 unneeded\)')" 1 "canaries caught" ;;
    # (0.30.0: 469)
    borrowck-twin)
        judge "$(count 'borrowck-twin: ')" 420 "cases compared with rustc" ;;
    # (0.30.0: 41)
    stdtools)
        judge "$(count 'stdtools: ')" 38 "cases" ;;
    # (0.30.0: 3966 bodies)
    std-check)
        judge "$(count 'std-check: ')" 3500 "bodies" ;;
    # (0.30.0: 1581; gate 1's 1000 is the release's own rule)
    std-tests)
        judge "$(count 'std-tests: ')" 1400 "std cases passed at -O0 and -O2" ;;
    # (0.30.0: 171 transcripts)
    cachediff)
        judge "$(count 'cachediff: ')" 150 "transcripts" ;;
    # (0.30.0: 783)
    compiler-memcheck)
        judge "$(count 'compiler-memcheck: ')" 700 "compilations" ;;
    # (0.30.0: 196)
    examples-checkalloc)
        judge "$(count 'examples-checkalloc: ')" 175 "examples" ;;
    # (0.30.0: 52 releases)
    chain-fresh)
        judge "$(count 'chain-fresh: ')" 52 "releases rebuilt" ;;
    # (0.30.0: 63420 compilations of the corpus, A2 against B2)
    chain-diverse)
        judge "$(count 'same-output: identical ')" 50000 "compilations of the corpus the same by both compilers" ;;
    # (0.30.0: 1610 scripts of the oracle; the row runs as many as fit in
    # 60 s, so its count is the machine's load: the floor is only for a
    # row that ran next to nothing)
    voltty-fuzz)
        judge "$(count 'pass oracle \(')" 100 "scripts against the oracle" ;;
    # (the fixpoint of the head, and the self-compile and the suite of
    # stress-grow: one thing each, named in the log)
    chain)
        judge "$(lines 'head +the working tree, built by .*fixpoint ok')" 1 "fixpoints of the working tree" ;;
    stress-grow)
        judge "$(lines 'stress-grow: the self-compile is the same; the suite passes at -O0 and -O2')" 1 "checks" ;;
    *)
        echo "floor $STEP: no floor (its log names what it checked)"
        exit 0 ;;
esac
