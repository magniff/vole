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
# Per platform (0.30.1's review): no floor is a fraction of another
# host's count. The rows the Linux containers run (gate.sh --inside: the
# suite rows, fuzz, ABI, layout, objcheck, debug, valgrind, smoke) are
# judged by what they report against the tree, on every host:
#   suite-O*   from its records (STEP.results beside the log, one per
#              case, `NAME STATUS BCK REASON CC`, tests/run.sh's): every
#              case the tree lists has one and no other case has one,
#              none failed, each skipped one for the REQUIRES word that
#              does not hold on HOST (its REASON), and every case whose
#              REQUIRES does not hold skipped;
#   objcheck   from its records (STEP.results, one per compilation,
#              `PROGRAM SETTING STATUS CC`, tests/objcheck.sh's): each ok,
#              none twice, the programs of tests/run the tree's (those
#              objcheck leaves out left out) each at the four settings
#              (-O0, -O2, with -g and without);
#   layout     its row's own floor for the host (100 macOS, 30 Linux);
#   fuzz, ABI, value semantics, voltty: the count the row was asked for;
#   debug, compile-cost, chain, stress-grow, unsafe-audit: their lines.
# incremental's plan is the tree's (its programs and levels), the same on
# every host: N of M with at most 4 skipped (each with its reason) and
# the rest rebuilt the same, M at least 150. The other rows run on the
# macOS host only, and their floors are 0.30.0's counts there
# (aarch64-macos); on any other host such a row fails, `no floor for
# HOST`, until it has one of its own (a gate there would otherwise pass
# it on any count). What this cannot check without a Linux machine: that
# the containers' rows write their records (gate.sh sets the same files
# for them) and print the other rows' lines as macOS's do (the same
# scripts print them).
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
ROOT=$(cd "$(dirname "$0")/.." && pwd)

# The first number after the text $1 on the last line of the log that
# matches the pattern $1 (an extended regular expression ending where the
# number starts), or nothing.
count() {
    grep -E "$1" "$LOG" | tail -1 | sed -E "s/^.*$1([0-9]+).*$/\\1/" | grep -E '^[0-9]+$'
}
# Floor $1, 0.30.0's count on aarch64-macos, of a row that runs on the
# macOS host only: elsewhere the row fails (the header).
hfloor() {
    if [ "$HOST" != aarch64-macos ]; then
        echo "floor $STEP: no floor for $HOST: its floor is aarch64-macos's count; give it one from a gate of this host" >&2
        echo 999999999
        return
    fi
    echo "$1"
}
# The fail of the row: message $1.
refuse() {
    echo "floor $STEP: $1"
    exit 1
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
    # (0.30.0: 6556 passed of 7274 at each level; 0.30.1: judged against
    # the tree, the header)
    suite-O0|suite-O1|suite-O2)
        # (0.30.1) Judged from the row's records, one per case (tests/run.sh
        # writes them to $VOLE_TEST_RESULTS, which gate.sh gives as
        # $RUN/STEP.results beside the log): `NAME STATUS BCK REASON CC`.
        # Every case the tree lists has one record and no other case has
        # one; none failed (fail, xpass); a skipped case's REASON is the
        # REQUIRES word that does not hold on HOST (`requires:metal` off
        # aarch64-macos, `requires:macos` off macOS, `requires:clang` where
        # its CC, one for every record, is cc:other), and every case whose
        # REQUIRES does not hold is skipped. No count is read from the log:
        # a count cannot pass without its names.
        R="${LOG%.log}.results"
        [ -s "$R" ] || refuse "no records of its cases ($R): the row passed without saying what it ran"
        T=$(mktemp -d "${TMPDIR:-/tmp}/vole-floor.XXXXXX") || exit 1
        trap 'rm -rf "$T"' EXIT
        bad=$(awk 'NF != 5 || $2 !~ /^(pass|xfail|fail|xpass|skip)$/ || $5 !~ /^cc:(clang|other)$/ \
                || ($2 == "skip") != ($4 ~ /^requires:(clang|metal|macos)$/) || ($2 != "skip" && $4 != "-") { print; exit }' "$R")
        [ -z "$bad" ] || refuse "a record not NAME STATUS BCK REASON CC: $bad"
        [ "$(awk '{ print $5 }' "$R" | sort -u | wc -l | tr -d ' ')" -eq 1 ] || refuse "its records disagree on cc"
        cc=$(awk 'NR == 1 { print $5 }' "$R")
        awk '{ print $1 }' "$R" | sort >"$T/ran"
        dup=$(uniq -d "$T/ran" | head -3 | tr '\n' ' ')
        [ -z "$dup" ] || refuse "cases with two records: $dup"
        sh "$ROOT/tests/run.sh" -l 2>/dev/null | sed -n 's/^case //p' | sort >"$T/listed"
        missing=$(comm -23 "$T/listed" "$T/ran" | head -3 | tr '\n' ' ')
        [ -z "$missing" ] || refuse "cases of the tree with no record: $missing"
        extra=$(comm -13 "$T/listed" "$T/ran" | head -3 | tr '\n' ' ')
        [ -z "$extra" ] || refuse "records of cases the tree does not list: $extra"
        failed=$(awk '$2 == "fail" || $2 == "xpass" { print $1 }' "$R" | head -3 | tr '\n' ' ')
        [ -z "$failed" ] || refuse "cases failed: $failed"
        # (the skips the tree's REQUIRES lines make on HOST, by one grep:
        # `NAME requires:WORD` for each word that does not hold)
        (cd "$ROOT" && grep -H '^// REQUIRES:' tests/run/*.vl tests/run/*/main.vl tests/examples/*.test 2>/dev/null) \
            | awk -v host="$HOST" -v cc="$cc" '
                { f = $0; sub(/:\/\/ REQUIRES:.*/, "", f); w = $0; sub(/^[^:]*:\/\/ REQUIRES: */, "", w)
                  words[f] = words[f] " " w " " }
                END {
                    for (f in words) {
                        n = f; sub(/^.*\//, "", n)
                        if (f ~ /\.test$/) { sub(/\.test$/, "", n); n = "example_" n }
                        else if (f ~ /\/main\.vl$/) { n = f; sub(/\/main\.vl$/, "", n); sub(/^.*\//, "", n) }
                        else sub(/\.vl$/, "", n)
                        w = words[f]
                        if (w ~ / metal / && host != "aarch64-macos") print n, "requires:metal"
                        if (w ~ / macos / && host !~ /-macos$/) print n, "requires:macos"
                        if (w ~ / clang / && cc != "cc:clang") print n, "requires:clang"
                    }
                }' | sort >"$T/allowed"
        awk '{ print $1 }' "$T/allowed" | sort -u >"$T/must"
        awk '$2 == "skip" { print $1 }' "$R" | sort >"$T/skipped"
        unskipped=$(comm -23 "$T/must" "$T/skipped" | head -3 | tr '\n' ' ')
        [ -z "$unskipped" ] || refuse "cases the tree skips on $HOST ($cc) not skipped: $unskipped"
        wrong=$(awk '$2 == "skip" { print $1, $4 }' "$R" | sort | comm -23 - "$T/allowed" | head -3 | tr '\n' ';')
        [ -z "$wrong" ] || refuse "cases skipped for no REQUIRES that fails on $HOST ($cc): $wrong"
        echo "floor $STEP: $(awk '$2 == "pass"' "$R" | wc -l | tr -d ' ') passed, $(awk '$2 == "xfail"' "$R" | wc -l | tr -d ' ') xfail, $(wc -l <"$T/skipped" | tr -d ' ') skipped (each for its REQUIRES on $HOST, $cc) of the tree's $(wc -l <"$T/listed" | tr -d ' ') cases, each by its record"
        exit 0 ;;
    # (each program asked for is counted: -n FZ)
    fuzz-plain|fuzz-loops|fuzz-generics|fuzz-pressure|fuzz-calls|fuzz-lang06|fuzz-vector|fuzz-div|fuzz-range|fuzz-arch|fuzz-guard|fuzz-seed)
        judge "$(count 'fuzz: ')" "$FZ" "programs" ;;
    # (0.30.1) the moves rows ask at least 20 programs (gate.sh's MFZ); the
    # x86-64 ones are a SKIP on a host without Rosetta, which the log says
    fuzz-moves|fuzz-moves-vec|fuzz-moves-x86|fuzz-moves-vec-x86|fuzz-moves-frame|fuzz-moves-frame-x86)
        if grep -q '^skip: no x86_64-macos here' "$LOG"; then
            echo "floor $STEP: SKIP: $(grep '^skip: no x86_64-macos here' "$LOG" | tail -1)"
            exit 77
        fi
        mfz=$FZ
        [ "$mfz" -ge 20 ] || mfz=20
        judge "$(count 'fuzz: ')" "$mfz" "programs" ;;
    # (five runs of SFZ programs each)
    fuzz-sem)
        n=$(lines "^fuzz: $SFZ value-semantics programs, 0 failing \\($SFZ ok\\)")
        judge "$n" 5 "runs of $SFZ value-semantics programs all checked" ;;
    abi-plain|abi-import|abi-header)
        judge "$(count 'abi: ')" "$AB" "programs" ;;
    # (0.30.0: 13048 of 13048; 0.30.1: against the tree, the header)
    objcheck)
        # (0.30.1) Judged from the row's records, one per compilation
        # (tests/objcheck.sh writes them to $VOLE_OBJCHECK_RESULTS, which
        # gate.sh gives as $RUN/STEP.results): `PROGRAM SETTING STATUS CC`.
        # Each is ok; no program and setting twice; the programs of
        # tests/run are the tree's, each at all four settings (0, 2, 0g,
        # 2g): the programs of tests/run but those objcheck leaves out, by
        # one grep each, as it does (tests/gate_floors.sh shows the set is
        # `tests/objcheck.sh --list`'s); and as many in all as four of each.
        R="${LOG%.log}.results"
        [ -s "$R" ] || refuse "no records of its compilations ($R)"
        T=$(mktemp -d "${TMPDIR:-/tmp}/vole-floor.XXXXXX") || exit 1
        trap 'rm -rf "$T"' EXIT
        bad=$(awk 'NF != 4 || $2 !~ /^(0|2|0g|2g)$/ || $3 !~ /^(ok|differ)$/ || $4 !~ /^cc:(clang|other)$/ { print; exit }' "$R")
        [ -z "$bad" ] || refuse "a record not PROGRAM SETTING STATUS CC: $bad"
        [ "$(awk '{ print $4 }' "$R" | sort -u | wc -l | tr -d ' ')" -eq 1 ] || refuse "its records disagree on cc"
        cc=$(awk 'NR == 1 { print $4 }' "$R")
        differ=$(awk '$3 != "ok" { print $1 " " $2 }' "$R" | head -3 | tr '\n' ';')
        [ -z "$differ" ] || refuse "compilations that differ from cc's: $differ"
        dup=$(awk '{ print $1, $2 }' "$R" | sort | uniq -d | head -3 | tr '\n' ';')
        [ -z "$dup" ] || refuse "compilations recorded twice: $dup"
        (cd "$ROOT" && ls tests/run/*.vl tests/run/*/main.vl 2>/dev/null) | sort >"$T/all"
        (cd "$ROOT" && grep -l '// ERROR\|// CSOURCE\|// CHEADER\|// FIXIMPORTS\|// FIXUNSAFE' tests/run/*.vl tests/run/*/main.vl 2>/dev/null
         grep -lE "^[[:space:]]*// ?XFAIL(\\($HOST\\))?:" tests/run/*.vl tests/run/*/main.vl 2>/dev/null
         [ "$cc" = cc:clang ] || grep -lwE '^[[:space:]]*// ?REQUIRES:.*clang' tests/run/*.vl tests/run/*/main.vl 2>/dev/null
         case "$HOST" in *-macos) ;; *) grep -lwE '^[[:space:]]*// ?REQUIRES:.*metal' tests/run/*.vl tests/run/*/main.vl 2>/dev/null ;; esac) \
            | sort -u >"$T/out"
        comm -23 "$T/all" "$T/out" >"$T/want"
        awk '$1 ~ /^tests\/run\// { n[$1]++ } END { for (p in n) print p, n[p] }' "$R" | sort >"$T/got"
        short=$(awk '$2 != 4 { print $1 " " $2 }' "$T/got" | head -3 | tr '\n' ';')
        [ -z "$short" ] || refuse "programs not compiled at the four settings: $short"
        awk '{ print $1 }' "$T/got" >"$T/gotn"
        missing=$(comm -23 "$T/want" "$T/gotn" | head -3 | tr '\n' ' ')
        [ -z "$missing" ] || refuse "programs of the tree not compiled: $missing"
        extra=$(comm -13 "$T/want" "$T/gotn" | head -3 | tr '\n' ' ')
        [ -z "$extra" ] || refuse "programs compiled that it leaves out of the tree: $extra"
        want=$(wc -l <"$T/want" | tr -d ' ')
        judge "$(wc -l <"$R" | tr -d ' ')" $((4 * want)) "compilations the same as cc -c's, each by its record (the tree's $want programs of tests/run at four settings each, by name)" ;;
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
    # in two versions, both orders, -O1 and -O2, -S and -c. Its plan is the
    # tree's, on every host: N of M, at most 4 skipped, each named.)
    incremental)
        p=$(count 'incremental pairs: ')
        [ -n "$p" ] && [ "$p" -ge 48 ] || refuse "${p:-no} warm builds of the pairs, below its floor of 48"
        line=$(grep -E '^incremental: [0-9]+ of [0-9]+ edit series' "$LOG" | tail -1)
        [ -n "$line" ] || refuse "no count of edit series in its log"
        ok=$(echo "$line" | awk '{print $2}')
        all=$(echo "$line" | awk '{print $4}')
        sk=$(echo "$line" | sed -nE 's/.*, ([0-9]+) skipped.*/\1/p')
        sk=${sk:-0}
        named=$(grep -cE '^skip .*: .+' "$LOG")
        [ "$sk" -le 4 ] || refuse "$sk edit series skipped, more than 4"
        [ "$named" -ge "$sk" ] || refuse "$sk series skipped, $named with a reason"
        [ $((ok + sk)) -eq "$all" ] || refuse "$ok of $all series the same and $sk skipped"
        judge "$all" 150 "edit series of the tree, $ok the same, $sk skipped (and $p warm builds of the pairs)" ;;
    # (four measures: hello, std, check, regions)
    compile-cost)
        judge "$(lines 'M instructions, was ')" 4 "programs measured" ;;
    # (0.30.2: its canary, a planted finding it must report; 95 findings
    # at 0.30.2's start)
    redteam-cases)
        [ "$(lines 'redteam-cases: the canary caught')" -ge 1 ] \
            || refuse "no canary line in its log: the audit ran without its fault shown caught"
        judge "$(count 'redteam-cases: ')" 90 "red-team findings held to their cases" ;;
    # (0.30.1: the audit's canary, planted sites it must find)
    unsafe-audit)
        judge "$(lines 'the canary caught \(4 unjustified, 1 unneeded\)')" 1 "canaries caught" ;;
    # (0.30.0: 469)
    borrowck-twin)
        judge "$(count 'borrowck-twin: ')" "$(hfloor 420)" "cases compared with rustc" ;;
    # (0.30.1: 5581 programs swept, after a self-test that names 4
    # verdicts; a SKIP of main-stack off macOS is its line's)
    e18-loans)
        [ "$(lines 'e18-loans: self-test ok: .* [0-9]+ verdicts changed by one')" -ge 1 ] \
            || refuse "no self-test line in its log: the sweep ran without its faults shown caught"
        judge "$(count 'borrow site, over ')" "$(hfloor 5000)" "programs swept" ;;
    main-stack)
        if grep -q '^main-stack: SKIP' "$LOG"; then
            echo "floor $STEP: SKIP: $(grep '^main-stack: SKIP' "$LOG" | tail -1)"
            exit 77
        fi
        judge "$(lines '^main-stack: ok: ')" 1 "checks" ;;
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
    # and not a failure; any other `skip oracle` line is not a skip.)
    voltty-fuzz)
        # (only a missing cargo is a skip: an oracle that does not build
        # is the row's FAIL, tests/voltty/run.sh)
        if grep -q '^skip oracle (no cargo)$' "$LOG"; then
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
