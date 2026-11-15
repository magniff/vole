#!/bin/sh
# (0.30.1) The gate's floors (bootstrap/gate-floors.sh) are shown to catch:
# for each row with a floor, its line from 0.30.0's release gate passes,
# and the same line with its count made zero, and made a quarter of it,
# fails (voltty-fuzz, whose count is what fits in a minute: one below its
# floor); a log with no count line fails too. (The fuzz and ABI rows are
# asked for 60 and 100 programs, value semantics for 300, as --release
# asks.) Prints `gate-floors: N rows, each caught at zero, at a quarter and
# without its line`; exits 1 when a floor passes what it must not.
set -u
LC_ALL=C
export LC_ALL
ROOT=$(cd "$(dirname "$0")/.." && pwd)
F="$ROOT/bootstrap/gate-floors.sh"
W=$(mktemp -d "${TMPDIR:-/tmp}/gate_floors.XXXXXX")
trap 'rm -rf "$W"' EXIT
failed=0
rows=0
# STEP, a separator, the row's 0.30.0 line(s) with @N@ for its count, and
# the count 0.30.0 had.
check() { # <step> <count> <line>...
    step=$1
    n=$2
    shift 2
    rows=$((rows + 1))
    for c in "$n" 0 half none; do
        log="$W/$step.$c.log"
        : >"$log"
        if [ "$c" != none ]; then
            v=$c
            [ "$c" = half ] && v=$((n / 4))
            [ "$c" = half ] && [ -n "${LOW:-}" ] && v=$LOW
            for l in "$@"; do
                printf '%s\n' "$l" | sed "s/@N@/$v/g" >>"$log"
            done
        else
            echo "some other line" >"$log"
        fi
        out=$(sh "$F" "$step" "$log" 60 100 300 2>&1)
        rc=$?
        if [ "$c" = "$n" ] && [ $rc -ne 0 ]; then
            echo "FAIL $step: its 0.30.0 count $n fails: $out"
            failed=1
        elif [ "$c" != "$n" ] && [ $rc -eq 0 ]; then
            echo "FAIL $step: a count of $c passes: $out"
            failed=1
        fi
    done
}
check suite-O2 6556 "  total       @N@    717     0     1"
check fuzz-loops 60 "fuzz: @N@ programs for aarch64-macos, 0 failing"
check fuzz-seed 60 "fuzz: @N@ programs for aarch64-macos, 0 failing"
check abi-plain 100 "abi: @N@ programs (992 signatures) for aarch64-macos, 0 failing"
check objcheck 13048 "objcheck: @N@ of @N@ compilations for aarch64-macos give the same program as cc -c, 0 differ"
check objcheck-x86-arch 260 "objcheck: @N@ of @N@ compilations for x86_64-macos give the same program as cc -c, 0 differ"
check layout 111 "layout: @N@ records, 582 fields agree"
check threads 16015 "threads: @N@ of @N@ compilations the same at -j1 and -j8 (aarch64-macos)"
check borrowck-twin 469 "borrowck-twin: @N@ cases, 427 agree, 8 divergences (L13 1), 34 outside the subset, 0 mismatches"
check stdtools 41 "stdtools: @N@ passed, 0 failed"
check std-check 3966 "std-check: @N@ bodies: 3963 clean, 0 with borrowck errors"
check std-tests 1581 "std-tests: @N@ passed at -O0 and -O2 under --check-alloc (gate 1: 1000)"
check cachediff 171 "cachediff: @N@ transcripts, 1604 lines compared, 487 answered from the cache"
check compiler-memcheck 783 "compiler-memcheck: @N@ of @N@ compilations clean (checkalloc gmalloc, aarch64-macos)"
check examples-checkalloc 196 "examples-checkalloc: @N@ passed, 0 failed with --check-alloc"
check chain-fresh 52 "chain-fresh: @N@ releases rebuilt from the seed, each the same bytes as recorded and as cached"
check chain-diverse 63420 "  same-output: identical @N@ compilations 5285 programs 4 targets -O0 -O1 -O2"
# (a count of what fits in 60 s: its floor is 100, checked one below it)
LOW=99
check voltty-fuzz 1610 "pass oracle (@N@ scripts from seed 672166)"
unset LOW
check incremental 172 "incremental pairs: 24 of 24 warm builds the same as clean builds" "incremental: @N@ of @N@ edit series rebuilt the same as clean builds (aarch64-macos, hits 86%)"
# (the rows that count lines: their line repeated, or missing)
for step in debug fuzz-sem compile-cost unsafe-audit chain stress-grow; do
    rows=$((rows + 1))
    case $step in
        debug) good="ok -O0
ok -O2" ;;
        fuzz-sem) good=$(for i in 1 2 3 4 5; do echo "fuzz: 300 value-semantics programs, 0 failing (300 ok)"; done) ;;
        compile-cost) good=$(for p in hello std check regions; do echo "  $p 1.0 M instructions, was 1.0 M: 1.00x (at most 1.50x)"; done) ;;
        unsafe-audit) good="unsafe-audit: compiler/src 299 sites, 0 unjustified, 0 unneeded; std 910 sites, 0 unjustified, 0 unneeded; the canary caught (4 unjustified, 1 unneeded)" ;;
        chain) good="  head     the working tree, built by 0.30.0, fixpoint ok, tests: not run (--no-suite)" ;;
        stress-grow) good="stress-grow: the self-compile is the same; the suite passes at -O0 and -O2" ;;
    esac
    printf '%s\n' "$good" >"$W/$step.good"
    printf '%s\n' "$good" | sed '1d' >"$W/$step.short"
    echo "other" >"$W/$step.none"
    sh "$F" "$step" "$W/$step.good" 60 100 300 >/dev/null 2>&1 || { echo "FAIL $step: its good log fails"; failed=1; }
    for bad in short none; do
        if sh "$F" "$step" "$W/$step.$bad" 60 100 300 >/dev/null 2>&1; then
            echo "FAIL $step: a log with a line fewer ($bad) passes"
            failed=1
        fi
    done
done
# (fuzz-sem's programs are the count asked for: 299 of 300 fails)
printf 'fuzz: 299 value-semantics programs, 0 failing (299 ok)\n' >"$W/sem.low"
sh "$F" fuzz-sem "$W/sem.low" 60 100 300 >/dev/null 2>&1 && { echo "FAIL fuzz-sem: 299 programs of 300 pass"; failed=1; }
# (a fuzz row counts every program asked for: 59 of 60 fails)
echo "fuzz: 59 programs for aarch64-macos, 0 failing" >"$W/fz.low"
sh "$F" fuzz-plain "$W/fz.low" 60 100 300 >/dev/null 2>&1 && { echo "FAIL fuzz-plain: 59 programs of 60 pass"; failed=1; }
if [ $failed -eq 0 ]; then
    echo "gate-floors: $rows rows, each caught at zero, at a quarter and without its line"
fi
[ $failed -eq 0 ]
