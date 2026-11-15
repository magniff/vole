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
# usage: bootstrap/gate-floors.sh STEP LOG FZ AB SFZ [HOST]
#   STEP   the gate's step (suite-O2, fuzz-loops, objcheck, ...)
#   LOG    its log
#   FZ AB SFZ   the programs gate.sh asked of the fuzz, ABI and value
#          semantics rows (its --quick, default or --release counts)
#   HOST   where the row ran (default aarch64-macos): gate.sh's $HOST,
#          inside the Linux containers aarch64-linux or x86_64-linux
#
# Per platform: a floor that is 0.30.0's count is aarch64-macos's (the
# only host its gate ran on). Elsewhere it is a quarter of it (hfloor):
# the containers run the same corpora less what is the platform's own
# (the 8 cases of `// REQUIRES: metal` or `clang`, the examples of
# std::gpu and std::window, another set of intrinsics' programs on x86-64,
# glibc's headers for layout), which no count of macOS's gives exactly;
# a quarter still fails a row that ran next to nothing. layout has its
# row's own floor there (30). The floors that are a count the row was
# asked for (fuzz, ABI, value semantics, voltty's scripts), a corpus the
# same everywhere read whole (the pairs, the unsafe audit's canary) or
# one line (debug, compile-cost, chain, stress-grow) hold on every host.
# Prints one line, `floor STEP: ...`; exits 1 when the row is below its
# floor, 77 when the row skipped what it counts and said so (a SKIP).
#
# tests/gate_floors.sh checks this script: each row's 0.30.0 line passes,
# the same line with a zero or a low count fails.
set -u
LC_ALL=C
export LC_ALL
[ $# -eq 5 ] || [ $# -eq 6 ] || { echo "usage: bootstrap/gate-floors.sh STEP LOG FZ AB SFZ [HOST]" >&2; exit 2; }
STEP=$1
LOG=$2
FZ=$3
AB=$4
SFZ=$5
HOST=${6:-aarch64-macos}
[ -f "$LOG" ] || { echo "floor $STEP: no log $LOG"; exit 1; }

# The first number after the text $1 on the last line of the log that
# matches the pattern $1 (an extended regular expression ending where the
# number starts), or nothing.
count() {
    grep -E "$1" "$LOG" | tail -1 | sed -E "s/^.*$1([0-9]+).*$/\\1/" | grep -E '^[0-9]+$'
}
# Floor $1, 0.30.0's count on aarch64-macos, for this host: the same
# there, a quarter elsewhere (the header).
hfloor() {
    if [ "$HOST" = aarch64-macos ]; then echo "$1"; else echo $(($1 / 4)); fi
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
        judge "$(grep -E '^ +total +[0-9]+' "$LOG" | tail -1 | awk '{print $2}')" "$(hfloor 6000)" "cases passed" ;;
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
        judge "$(count 'objcheck: ')" "$(hfloor 12000)" "compilations compared with cc -c" ;;
    # (0.30.0: 260)
    objcheck-x86-arch)
        judge "$(count 'objcheck: ')" "$(hfloor 230)" "compilations compared with cc -c" ;;
    # (layout.sh has its own floor, -m: 100 records on macOS, 30 on Linux,
    # as the row asks)
    layout)
        case "$HOST" in *-macos) lf=100 ;; *) lf=30 ;; esac
        judge "$(count 'layout: ')" "$lf" "records" ;;
    # (one program at two levels)
    debug)
        judge "$(lines '^ok -O[02]$')" 2 "levels run under the debugger" ;;
    # (0.30.0: 16015)
    threads)
        judge "$(count 'threads: ')" "$(hfloor 14000)" "compilations compared at -j1 and -j8" ;;
    # (0.30.0: 172 series; 0.30.1: and the pairs, 48 builds: six programs
    # in two versions, both orders, -O1 and -O2, -S and -c)
    incremental)
        p=$(count 'incremental pairs: ')
        [ -n "$p" ] && [ "$p" -ge 48 ] || { echo "floor $STEP: ${p:-no} warm builds of the pairs, below its floor of 48"; exit 1; }
        judge "$(count 'incremental: ')" "$(hfloor 150)" "edit series (and $p warm builds of the pairs)" ;;
    # (four measures: hello, std, check, regions)
    compile-cost)
        judge "$(lines 'M instructions, was ')" 4 "programs measured" ;;
    # (0.30.1: the audit's canary, planted sites it must find)
    unsafe-audit)
        judge "$(lines 'the canary caught \(4 unjustified, 1 unneeded\)')" 1 "canaries caught" ;;
    # (0.30.0: 469)
    borrowck-twin)
        judge "$(count 'borrowck-twin: ')" "$(hfloor 420)" "cases compared with rustc" ;;
    # (0.30.0: 41)
    stdtools)
        judge "$(count 'stdtools: ')" "$(hfloor 38)" "cases" ;;
    # (0.30.0: 3966 bodies)
    std-check)
        judge "$(count 'std-check: ')" "$(hfloor 3500)" "bodies" ;;
    # (0.30.0: 1581; gate 1's 1000 is the release's own rule)
    std-tests)
        judge "$(count 'std-tests: ')" "$(hfloor 1400)" "std cases passed at -O0 and -O2" ;;
    # (0.30.0: 171 transcripts)
    cachediff)
        judge "$(count 'cachediff: ')" "$(hfloor 150)" "transcripts" ;;
    # (0.30.0: 783)
    compiler-memcheck)
        judge "$(count 'compiler-memcheck: ')" "$(hfloor 700)" "compilations" ;;
    # (0.30.0: 196)
    examples-checkalloc)
        judge "$(count 'examples-checkalloc: ')" "$(hfloor 175)" "examples" ;;
    # (0.30.0: 52 releases)
    chain-fresh)
        judge "$(count 'chain-fresh: ')" "$(hfloor 52)" "releases rebuilt" ;;
    # (0.30.0: 63420 compilations of the corpus, A2 against B2)
    chain-diverse)
        judge "$(count 'same-output: identical ')" "$(hfloor 50000)" "compilations of the corpus the same by both compilers" ;;
    # (0.30.0: 1610 scripts of the oracle in its 60 s. The row asks for at
    # least 200 however long they take (tests/voltty/run.sh -n 200 -s 60),
    # so no load lowers the count below its floor. Without cargo the
    # oracle is skipped, which the log says: the row is a SKIP, not a pass
    # and not a failure.)
    voltty-fuzz)
        if grep -q '^skip oracle' "$LOG"; then
            echo "floor $STEP: SKIP: $(grep '^skip oracle' "$LOG" | tail -1)"
            exit 77
        fi
        judge "$(count 'pass oracle \(')" 200 "scripts against the oracle" ;;
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
