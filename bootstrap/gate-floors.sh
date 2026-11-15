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
#   suite-O*   one plan, every case the tree lists (tests/run.sh -l),
#              and one `cases:` line: each listed case run once (the
#              digest of the names it ran, `-l`'s), passed, xfailed or
#              skipped, none failed, the table's total at least as much,
#              and the skipped ones by name exactly those the tree's
#              REQUIRES lines skip on HOST (`metal` off aarch64-macos,
#              `macos` off macOS, `clang` when the log's `cc:` line says
#              cc is not clang);
#   objcheck   every compilation the same as cc's (N of N), its tests/run
#              programs by name the tree's (their digest), and N at
#              least four (-O0, -O2, with -g and without, as
#              tests/objcheck.sh compiles each) of each program of
#              tests/run the suite runs and compiles (no XFAIL,
#              REQUIRES, ERROR, WARNING or FIX* directive);
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
# the containers' logs print these lines as macOS's do (the same scripts
# print them), and the corpus objcheck compiles there.
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
        # (tests/run.sh's `cases:` line: the cases alone, not the suites'
        # checks the table's total adds; one plan and one cases line, or
        # the log is two runs')
        [ "$(grep -cE '^plan: [0-9]+ cases' "$LOG")" -le 1 ] || refuse "more than one plan in its log"
        [ "$(grep -cE '^cases: ' "$LOG")" -le 1 ] || refuse "more than one cases line in its log"
        plan=$(grep -E '^plan: [0-9]+ cases' "$LOG" | awk '{print $2}')
        tot=$(grep -E '^cases: [0-9]+ passed, [0-9]+ xfail, [0-9]+ failed, [0-9]+ skipped of [0-9]+, names [0-9]+-[0-9]+$' "$LOG")
        [ -n "$plan" ] && [ -n "$tot" ] || refuse "no plan or no cases line in its log: the row passed without saying what it checked"
        sh "$ROOT/tests/run.sh" -l 2>/dev/null | sed -n 's/^case //p' | sort >"$LOG.listed"
        listed=$(wc -l <"$LOG.listed" | tr -d ' ')
        dlisted=$(cksum <"$LOG.listed" | tr ' ' -)
        rm -f "$LOG.listed"
        dran=${tot##*names }
        set -- $(echo "${tot%, names *}" | tr -dc '0-9 \n' | tr -s ' ')
        pass=$1; xf=$2; fl=$3; sk=$4; ran=$5
        [ "$plan" -eq "$listed" ] || refuse "it planned $plan cases of the tree's $listed"
        # (the names it ran, as a digest: each listed case once, none other)
        [ "$dran" = "$dlisted" ] || refuse "the cases it ran (names $dran) are not the tree's (names $dlisted)"
        # (the table's total counts the cases and the suites' checks: at
        # least the cases' passes and xfails, and no failure)
        ttot=$(grep -E '^ +total +[0-9]+ +[0-9]+ +[0-9]+ +[0-9]+' "$LOG" | tail -1)
        [ -n "$ttot" ] || refuse "no table total in its log"
        set -- $ttot
        [ "$2" -ge "$pass" ] && [ "$3" -ge "$xf" ] && [ "$4" -eq 0 ] \
            || refuse "its table's total ($2 passed, $3 xfail, $4 failed) is not its cases' and more"
        set -- $(echo "${tot%, names *}" | tr -dc '0-9 \n' | tr -s ' ')
        ccl=$(grep -E '^cc: (clang|not clang)$' "$LOG" | tail -1)
        [ -n "$ccl" ] || refuse "no cc line in its log (whether REQUIRES: clang holds)"
        [ "$ran" -eq "$plan" ] && [ $((pass + xf + fl + sk)) -eq "$plan" ] \
            || refuse "$pass passed, $xf xfail, $fl failed and $sk skipped of $ran are not its $plan cases"
        [ "$fl" -eq 0 ] || refuse "$fl cases failed"
        # (the skipped cases by name, `skip case NAME: REQUIRES ...`, are
        # the ones the tree's REQUIRES lines skip on HOST, as tests/run.sh
        # decides: `metal` off aarch64-macos, `macos` off macOS, `clang`
        # when its `cc:` line says cc is not clang; no other case)
        sed -n 's/^skip case \([^:]*\): .*/\1/p' "$LOG" | sort >"$LOG.skipped"
        named=$(wc -l <"$LOG.skipped" | tr -d ' ')
        [ "$named" -eq "$sk" ] || refuse "$sk cases skipped, $named of them named"
        # (one grep of the REQUIRES lines; NAME as tests/run.sh names it)
        : >"$LOG.must"
        (cd "$ROOT" && grep -H '^// REQUIRES:' tests/run/*.vl tests/run/*/main.vl tests/examples/*.test 2>/dev/null) \
            | awk -v host="$HOST" -v clang="$ccl" -v must="$LOG.must" '
                { f = $0; sub(/:\/\/ REQUIRES:.*/, "", f); w = $0; sub(/^[^:]*:\/\/ REQUIRES: */, "", w)
                  words[f] = words[f] " " w " " }
                END {
                    for (f in words) {
                        n = f; sub(/^.*\//, "", n)
                        if (f ~ /\.test$/) { sub(/\.test$/, "", n); n = "example_" n }
                        else if (f ~ /\/main\.vl$/) { n = f; sub(/\/main\.vl$/, "", n); sub(/^.*\//, "", n) }
                        else sub(/\.vl$/, "", n)
                        w = words[f]
                        skip = 0
                        if (w ~ / metal / && host != "aarch64-macos") skip = 1
                        if (w ~ / macos / && host !~ /-macos$/) skip = 1
                        if (w ~ / clang / && clang != "cc: clang") skip = 1
                        if (skip) print n > must
                    }
                }'
        sort -o "$LOG.must" "$LOG.must"
        missing=$(comm -23 "$LOG.must" "$LOG.skipped" | head -3 | tr '\n' ' ')
        [ -z "$missing" ] || refuse "cases the tree skips on $HOST ($ccl) ran or were not named skipped: $missing"
        extra=$(comm -23 "$LOG.skipped" "$LOG.must" | head -3 | tr '\n' ' ')
        [ -z "$extra" ] || refuse "cases skipped that no REQUIRES skips on $HOST ($ccl): $extra"
        echo "floor $STEP: $pass passed, $xf xfail, $sk skipped of the tree's $plan cases, by name (the $(wc -l <"$LOG.must" | tr -d ' ') its REQUIRES skips on $HOST, $ccl)"
        rm -f "$LOG.skipped" "$LOG.must"
        exit 0 ;;
    # (each program asked for is counted: -n FZ)
    fuzz-plain|fuzz-loops|fuzz-generics|fuzz-pressure|fuzz-calls|fuzz-lang06|fuzz-vector|fuzz-div|fuzz-range|fuzz-arch|fuzz-guard|fuzz-seed)
        judge "$(count 'fuzz: ')" "$FZ" "programs" ;;
    # (five runs of SFZ programs each)
    fuzz-sem)
        n=$(lines "^fuzz: $SFZ value-semantics programs, 0 failing \\($SFZ ok\\)")
        judge "$n" 5 "runs of $SFZ value-semantics programs all checked" ;;
    abi-plain|abi-import|abi-header)
        judge "$(count 'abi: ')" "$AB" "programs" ;;
    # (0.30.0: 13048 of 13048; 0.30.1: against the tree, the header)
    objcheck)
        [ "$(grep -cE '^objcheck: [0-9]+ of [0-9]+ ' "$LOG")" -eq 1 ] || refuse "not one count of compilations in its log"
        line=$(grep -E '^objcheck: [0-9]+ of [0-9]+ ' "$LOG")
        ok=$(echo "$line" | awk '{print $2}')
        all=$(echo "$line" | awk '{print $4}')
        [ "$ok" -eq "$all" ] || refuse "$ok of $all compilations the same"
        # (its programs by name: tests/objcheck.sh prints the digest of
        # its corpus's tests/run programs, each compiled at 4 settings,
        # which must be the tree's: the programs of tests/run but those
        # objcheck leaves out, by one grep each, as it does)
        [ "$(grep -c '^objcheck programs: ' "$LOG")" -eq 1 ] || refuse "not one line of its programs in its log"
        pl=$(grep '^objcheck programs: ' "$LOG")
        nrun=$(echo "$pl" | sed -nE 's/.*; of tests\/run ([0-9]+), names ([0-9]+-[0-9]+)$/\1/p')
        drun=$(echo "$pl" | sed -nE 's/.*; of tests\/run ([0-9]+), names ([0-9]+-[0-9]+)$/\2/p')
        [ -n "$nrun" ] && [ -n "$drun" ] || refuse "its programs' line has no names: $pl"
        ccl=$(grep -E '^cc: (clang|not clang)$' "$LOG" | tail -1)
        [ -n "$ccl" ] || refuse "no cc line in its log"
        (cd "$ROOT" && ls tests/run/*.vl tests/run/*/main.vl 2>/dev/null) | sort >"$LOG.all"
        (cd "$ROOT" && grep -l '// ERROR\|// CSOURCE\|// CHEADER\|// FIXIMPORTS\|// FIXUNSAFE' tests/run/*.vl tests/run/*/main.vl 2>/dev/null
         grep -lE "^[[:space:]]*// ?XFAIL(\\($HOST\\))?:" tests/run/*.vl tests/run/*/main.vl 2>/dev/null
         [ "$ccl" = "cc: clang" ] || grep -lwE '^[[:space:]]*// ?REQUIRES:.*clang' tests/run/*.vl tests/run/*/main.vl 2>/dev/null
         case "$HOST" in *-macos) ;; *) grep -lwE '^[[:space:]]*// ?REQUIRES:.*metal' tests/run/*.vl tests/run/*/main.vl 2>/dev/null ;; esac) \
            | sort -u >"$LOG.out"
        comm -23 "$LOG.all" "$LOG.out" >"$LOG.want"
        want=$(wc -l <"$LOG.want" | tr -d ' ')
        dwant=$(cksum <"$LOG.want" | tr ' ' -)
        rm -f "$LOG.all" "$LOG.out" "$LOG.want"
        [ "$nrun" -eq "$want" ] && [ "$drun" = "$dwant" ] \
            || refuse "its tests/run programs ($nrun, names $drun) are not the tree's ($want, names $dwant)"
        judge "$all" $((4 * want)) "compilations compared with cc -c (4 of each of the tree's $want programs of tests/run at least, each by name: -O0 and -O2, with -g and without)" ;;
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
