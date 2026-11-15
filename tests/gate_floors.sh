#!/bin/sh
# (0.30.1) The gate's floors (bootstrap/gate-floors.sh) are shown to catch:
# for each row with a floor, its line from 0.30.0's release gate passes,
# and the same line with its count made zero, and made a quarter of it,
# fails (voltty-fuzz, whose count is at least what the gate asks: one
# below its floor); a log with no count line fails too, and voltty-fuzz's
# skipped oracle is a SKIP (77). (The fuzz and ABI rows are
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
# (its floor is the 200 scripts the gate asks for, checked one below it)
LOW=199
check voltty-fuzz 1610 "pass oracle (@N@ scripts from seed 672166)"
unset LOW
# (a skipped oracle is a SKIP, exit 77: not a pass, not a failure)
rows=$((rows + 1))
printf 'pass build\npass seeds\nskip oracle (no cargo)\nvoltty: all passed\n' >"$W/voltty.skip.log"
out=$(sh "$F" voltty-fuzz "$W/voltty.skip.log" 60 100 300 2>&1)
rc=$?
[ $rc -eq 77 ] || { echo "FAIL voltty-fuzz: a skipped oracle exits $rc, not 77: $out"; failed=1; }
# (0.30.0's line, an oracle that did not build, is no skip: a FAIL)
rows=$((rows + 1))
printf 'pass build\npass seeds\nskip oracle (no cargo, or the oracle does not build offline)\nvoltty: all passed\n' >"$W/voltty.nobuild.log"
out=$(sh "$F" voltty-fuzz "$W/voltty.nobuild.log" 60 100 300 2>&1)
rc=$?
[ $rc -eq 1 ] || { echo "FAIL voltty-fuzz: an oracle that does not build exits $rc, not 1: $out"; failed=1; }
check incremental 172 "incremental pairs: 48 of 48 warm builds the same as clean builds" "incremental: @N@ of @N@ edit series rebuilt the same as clean builds (aarch64-macos, hits 86%)"
# (0.30.1's reviews: the suite rows are judged against the tree's cases
# on every host, never a fraction of macOS's count, and the skipped cases
# by name. L the cases the tree lists; LX the ones a REQUIRES of metal or
# macos skips off macOS (the examples' included), CL those needing clang.
# Each row: the host, the plan, the `cases:` line's pass, xfail and fail,
# the skipped names (none; lx: LX; lx-1: LX but one; lxcl: LX and CL; any:
# as many arbitrary cases as LX; metal: those of metal alone), the exit wanted; the table's total,
# which counts the suites' checks too, is 400 more and not read.)
L=$(sh "$ROOT/tests/run.sh" -l 2>/dev/null | grep -c '^case ')
names() { # <word...>: the cases whose REQUIRES has one of the words
    for file in "$ROOT"/tests/run/*.vl "$ROOT"/tests/run/*/main.vl "$ROOT"/tests/examples/*.test; do
        [ -f "$file" ] || continue
        words=" $(sed -n 's|^// REQUIRES: *||p' "$file" | tr '\n' ' ') "
        hit=no
        for w in "$@"; do case "$words" in *" $w "*) hit=yes ;; esac; done
        [ $hit = yes ] || continue
        base=${file##*/}; name=${base%.*}
        case "$file" in *.test) name="example_$name" ;; */main.vl) name=${file%/main.vl}; name=${name##*/} ;; esac
        echo "$name"
    done
}
names metal macos >"$W/lx"
names metal >"$W/mt"
names clang | grep -vxF -f "$W/lx" >"$W/cl"
LX=$(wc -l <"$W/lx" | tr -d ' ')
CL=$(wc -l <"$W/cl" | tr -d ' ')
sh "$ROOT/tests/run.sh" -l 2>/dev/null | sed -n 's/^case //p' | grep -vxF -f "$W/lx" | grep -vxF -f "$W/cl" | head -"$LX" >"$W/any"
while read -r host plan pass xf fl skips want; do
    rows=$((rows + 1))
    case "$skips" in
        none) : >"$W/skips" ;;
        lx) cp "$W/lx" "$W/skips" ;;
        lx-1) sed 1d "$W/lx" >"$W/skips" ;;
        lxcl) cat "$W/lx" "$W/cl" >"$W/skips" ;;
        any) cp "$W/any" "$W/skips" ;;
        metal) cp "$W/mt" "$W/skips" ;;
    esac
    sk=$(wc -l <"$W/skips" | tr -d ' ')
    [ "$pass" = rest ] && pass=$((L - xf - fl - sk))
    { [ "$plan" = none ] || echo "plan: $plan cases, 26 suites (query), -j 4, $host"
      printf '  total       %s    %s     %s     %s\n' "$((pass + 400))" "$xf" "$fl" "$sk"
      echo "cases: $pass passed, $xf xfail, $fl failed, $sk skipped of $((pass + xf + fl + sk))"
      sed 's/^\(.*\)$/skip case \1: REQUIRES metal/' "$W/skips"; } >"$W/suite.log"
    out=$(sh "$F" suite-O2 "$W/suite.log" 60 100 300 "$host" 2>&1)
    rc=$?
    [ $rc -eq "$want" ] || { echo "FAIL suite-O2 on $host, plan $plan, $pass $xf $fl, skipped $skips: exits $rc, not $want: $out"; failed=1; }
done <<EOT
aarch64-macos $L rest 717 0 none 0
aarch64-linux $L rest 717 0 lx 0
aarch64-linux $L rest 717 0 lxcl 0
aarch64-linux $L rest 717 0 lx-1 1
aarch64-macos $L rest 717 0 any 1
aarch64-macos $L rest 717 0 lx 1
aarch64-linux 1501 1501 0 0 none 1
aarch64-macos $((L - 1)) rest 717 0 none 1
aarch64-macos $L rest 717 1 none 1
aarch64-macos none rest 717 0 none 1
x86_64-macos $L rest 717 0 metal 0
x86_64-macos $L rest 717 0 none 1
EOT
# (a log with the table and no `cases:` line fails; so do two cases lines,
# the bad one first, and two plans)
rows=$((rows + 1))
{ echo "plan: $L cases, 26 suites (query), -j 4, aarch64-macos"
  printf '  total       %s    717     0     0\n' "$((L - 717 + 400))"; } >"$W/suite.log"
sh "$F" suite-O2 "$W/suite.log" 60 100 300 >/dev/null 2>&1 \
    && { echo "FAIL suite-O2: a log without its cases line passes"; failed=1; }
rows=$((rows + 1))
{ echo "plan: $L cases, 26 suites (query), -j 4, aarch64-macos"
  echo "cases: 100 passed, 0 xfail, $((L - 100)) failed, 0 skipped of $L"
  echo "cases: $((L - 717)) passed, 717 xfail, 0 failed, 0 skipped of $L"; } >"$W/suite.log"
sh "$F" suite-O2 "$W/suite.log" 60 100 300 >/dev/null 2>&1 \
    && { echo "FAIL suite-O2: two cases lines, the bad one first, pass"; failed=1; }
rows=$((rows + 1))
{ echo "plan: $L cases, 26 suites (query), -j 4, aarch64-macos"
  echo "plan: 3 cases, 0 suites, -j 2, aarch64-macos"
  echo "cases: 3 passed, 0 xfail, 0 failed, 0 skipped of 3"; } >"$W/suite.log"
sh "$F" suite-O2 "$W/suite.log" 60 100 300 >/dev/null 2>&1 \
    && { echo "FAIL suite-O2: two plans pass"; failed=1; }
# (a row that runs on the macOS host only has no floor elsewhere: it fails)
rows=$((rows + 1))
printf 'threads: 16015 of 16015 compilations the same at -j1 and -j8 (aarch64-linux)\n' >"$W/threads.log"
sh "$F" threads "$W/threads.log" 60 100 300 aarch64-linux >/dev/null 2>&1 \
    && { echo "FAIL threads on aarch64-linux: passes on a floor of macOS's"; failed=1; }
# (incremental: the review's 38 of 172 with 134 skipped fails; 4 skipped,
# each named, passes)
rows=$((rows + 1))
printf 'incremental pairs: 48 of 48 warm builds the same as clean builds\nincremental: 38 of 172 edit series rebuilt the same as clean builds (aarch64-linux, hits 86%%), 134 skipped\n' >"$W/inc.log"
sh "$F" incremental "$W/inc.log" 60 100 300 aarch64-linux >/dev/null 2>&1 \
    && { echo "FAIL incremental: 38 of 172 with 134 skipped passes"; failed=1; }
printf 'incremental pairs: 48 of 48 warm builds the same as clean builds\nskip a: 20 edits in a row at 2 do not build (x)\nskip b: 20 edits in a row at 2 do not build (x)\nskip c: 20 edits in a row at 2 do not build (x)\nskip d: 20 edits in a row at 2 do not build (x)\nincremental: 168 of 172 edit series rebuilt the same as clean builds (aarch64-linux, hits 86%%), 4 skipped\n' >"$W/inc4.log"
sh "$F" incremental "$W/inc4.log" 60 100 300 aarch64-linux >/dev/null 2>&1 \
    || { echo "FAIL incremental: 168 of 172 with 4 named skips fails"; failed=1; }
# (objcheck: 7000 of 7000 fails, fewer than 4 of each program; 0.30.0
# made 13048)
rows=$((rows + 1))
printf 'objcheck: 7000 of 7000 compilations for aarch64-macos give the same program as cc -c, 0 differ\n' >"$W/obj.log"
sh "$F" objcheck "$W/obj.log" 60 100 300 >/dev/null 2>&1 \
    && { echo "FAIL objcheck: 7000 of 7000 passes"; failed=1; }
# (objcheck: one compilation that differs fails)
rows=$((rows + 1))
printf 'objcheck: 13047 of 13048 compilations for aarch64-linux give the same program as cc -c, 1 differ\n' >"$W/obj.log"
sh "$F" objcheck "$W/obj.log" 60 100 300 aarch64-linux >/dev/null 2>&1 \
    && { echo "FAIL objcheck: 13047 of 13048 passes"; failed=1; }
printf 'layout: 40 records, 200 fields agree\n' >"$W/linuxl.log"
sh "$F" layout "$W/linuxl.log" 60 100 300 x86_64-linux >/dev/null 2>&1 \
    || { echo "FAIL layout on x86_64-linux: 40 records fails"; failed=1; }
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
