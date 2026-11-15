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
check fuzz-moves-vec 60 "fuzz: @N@ programs for aarch64-macos, 0 failing"
check fuzz-moves-vec-x86 60 "fuzz: @N@ programs for x86_64-macos, 0 failing"
check abi-plain 100 "abi: @N@ programs (992 signatures) for aarch64-macos, 0 failing"
# (objcheck's programs by name, from tests/objcheck.sh --list itself: the
# floor's own greps must give the same set)
sh "$ROOT/tests/objcheck.sh" --list -t aarch64-macos | grep '^tests/run/' | sort >"$W/ocrun"
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
# (0.30.1) the x86-64 moves rows on a host without Rosetta: a SKIP; the
# quick gate's 10 programs are below the moves rows' 20: a FAIL
rows=$((rows + 1))
printf 'skip: no x86_64-macos here (Rosetta: softwareupdate --install-rosetta)\n' >"$W/moves.skip.log"
out=$(sh "$F" fuzz-moves-x86 "$W/moves.skip.log" 60 100 300 2>&1)
rc=$?
[ $rc -eq 77 ] || { echo "FAIL fuzz-moves-x86: no Rosetta exits $rc, not 77: $out"; failed=1; }
rows=$((rows + 1))
printf 'fuzz: 10 programs for aarch64-macos, 0 failing\n' >"$W/moves.quick.log"
out=$(sh "$F" fuzz-moves-vec "$W/moves.quick.log" 10 20 20 2>&1)
rc=$?
[ $rc -eq 1 ] || { echo "FAIL fuzz-moves-vec: 10 programs at FZ=10 exits $rc, not 1: $out"; failed=1; }
printf 'fuzz: 20 programs for aarch64-macos, 0 failing\n' >"$W/moves.quick20.log"
out=$(sh "$F" fuzz-moves-vec "$W/moves.quick20.log" 10 20 20 2>&1)
rc=$?
[ $rc -eq 0 ] || { echo "FAIL fuzz-moves-vec: 20 programs at FZ=10 exits $rc, not 0: $out"; failed=1; }
# (0.30.0's line, an oracle that did not build, is no skip: a FAIL)
rows=$((rows + 1))
printf 'pass build\npass seeds\nskip oracle (no cargo, or the oracle does not build offline)\nvoltty: all passed\n' >"$W/voltty.nobuild.log"
out=$(sh "$F" voltty-fuzz "$W/voltty.nobuild.log" 60 100 300 2>&1)
rc=$?
[ $rc -eq 1 ] || { echo "FAIL voltty-fuzz: an oracle that does not build exits $rc, not 1: $out"; failed=1; }
check incremental 172 "incremental pairs: 48 of 48 warm builds the same as clean builds" "incremental: @N@ of @N@ edit series rebuilt the same as clean builds (aarch64-macos, hits 86%)"
# (0.30.1's reviews, the owner's rule: the suite rows are judged from
# their records, one per case (STEP.results beside the log: `NAME STATUS
# BCK REASON CC`), never from a count in the log. LX: the cases a REQUIRES
# of metal or macos skips off macOS (the examples' included; MT those of
# metal, MO of macos alone), CL those needing clang. Each row: the host,
# the records' cc, the skipped (none; lx; lx-1: LX but one; lxcl: LX and
# CL; cl; any: as many arbitrary cases; metal: MT), a change to the records
# (ok; dup: one case twice, another none; extra: a case the tree does not
# list; fail: one failed; why: a metal skip given clang's reason; form: a
# field missing; mixcc: one record of the other cc), the exit wanted. 717
# cases are xfail, the rest pass.)
sh "$ROOT/tests/run.sh" -l 2>/dev/null | sed -n 's/^case //p' | sort >"$W/listed"
L=$(wc -l <"$W/listed" | tr -d ' ')
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
    done | sort
}
names metal >"$W/mt"
names macos | grep -vxF -f "$W/mt" >"$W/mo"
sort "$W/mt" "$W/mo" >"$W/lx"
names clang | grep -vxF -f "$W/lx" >"$W/cl"
LX=$(wc -l <"$W/lx" | tr -d ' ')
grep -vxF -f "$W/lx" "$W/listed" | grep -vxF -f "$W/cl" | head -"$LX" >"$W/any"
grep -vxF -f "$W/lx" "$W/listed" | grep -vxF -f "$W/cl" | head -717 >"$W/xf"
while read -r host cc skips change want; do
    rows=$((rows + 1))
    : >"$W/skips"
    case "$skips" in
        lx) sed 's/$/ requires:metal/' "$W/mt" >"$W/skips"; sed 's/$/ requires:macos/' "$W/mo" >>"$W/skips" ;;
        lx-1) { sed 's/$/ requires:metal/' "$W/mt"; sed 's/$/ requires:macos/' "$W/mo"; } | sed 1d >"$W/skips" ;;
        lxcl) { sed 's/$/ requires:metal/' "$W/mt"; sed 's/$/ requires:macos/' "$W/mo"; sed 's/$/ requires:clang/' "$W/cl"; } >"$W/skips" ;;
        cl) sed 's/$/ requires:clang/' "$W/cl" >"$W/skips" ;;
        any) sed 's/$/ requires:metal/' "$W/any" >"$W/skips" ;;
        metal) sed 's/$/ requires:metal/' "$W/mt" >"$W/skips" ;;
    esac
    awk -v cc="cc:$cc" -v skips="$W/skips" -v xf="$W/xf" '
        BEGIN { while ((getline l < skips) > 0) { split(l, a, " "); why[a[1]] = a[2] }
                while ((getline l < xf) > 0) x[l] = 1 }
        { if ($1 in why) print $1, "skip", 0, why[$1], cc
          else if ($1 in x) print $1, "xfail", 0, "-", cc
          else print $1, "pass", 0, "-", cc }' "$W/listed" >"$W/suite.results"
    case "$change" in
        dup) awk 'NR == 2 { print; print; next } NR == 3 { next } { print }' "$W/suite.results" >"$W/r" ;;
        extra) { cat "$W/suite.results"; echo "no_such_case pass 0 - cc:$cc"; } >"$W/r" ;;
        fail) awk -v n="$(sed -n 1p "$W/any")" '$1 == n { $2 = "fail" } { print }' "$W/suite.results" >"$W/r" ;;
        why) awk -v n="$(sed -n 1p "$W/mt")" '$1 == n { $4 = "requires:clang" } { print }' "$W/suite.results" >"$W/r" ;;
        form) awk 'NR == 5 { print $1, $2, $3, $4; next } { print }' "$W/suite.results" >"$W/r" ;;
        mixcc) awk 'NR == 5 { $5 = ($5 == "cc:clang" ? "cc:other" : "cc:clang") } { print }' "$W/suite.results" >"$W/r" ;;
        ok) cp "$W/suite.results" "$W/r" ;;
    esac
    mv "$W/r" "$W/suite.results"
    # (the log a count: right, and never read)
    echo "cases: $L passed, 0 xfail, 0 failed, 0 skipped of $L" >"$W/suite.log"
    out=$(sh "$F" suite-O2 "$W/suite.log" 60 100 300 "$host" 2>&1)
    rc=$?
    [ $rc -eq "$want" ] || { echo "FAIL suite-O2 on $host ($cc), skipped $skips, $change: exits $rc, not $want: $out"; failed=1; }
done <<EOT
aarch64-macos clang none ok 0
aarch64-linux other lxcl ok 0
aarch64-linux clang lx ok 0
aarch64-linux clang lxcl ok 1
aarch64-linux other lx ok 1
aarch64-linux clang lx-1 ok 1
aarch64-linux clang lx why 1
aarch64-macos clang any ok 1
aarch64-macos clang lx ok 1
aarch64-macos clang cl ok 1
aarch64-macos other cl ok 0
aarch64-macos clang none dup 1
aarch64-macos clang none extra 1
aarch64-macos clang none fail 1
aarch64-macos clang none form 1
aarch64-macos clang none mixcc 1
x86_64-macos clang metal ok 0
x86_64-macos clang none ok 1
EOT
# (no records beside a log with every count right fails)
rows=$((rows + 1))
rm -f "$W/suite.results"
{ echo "plan: $L cases, 26 suites (query), -j 4, aarch64-macos"
  echo "cases: $((L - 717)) passed, 717 xfail, 0 failed, 0 skipped of $L"; } >"$W/suite.log"
sh "$F" suite-O2 "$W/suite.log" 60 100 300 >/dev/null 2>&1 \
    && { echo "FAIL suite-O2: a log with no records passes"; failed=1; }
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
# (objcheck, from its records, `PROGRAM SETTING STATUS CC`: the tree's
# programs of tests/run, by tests/objcheck.sh --list itself, each at the
# four settings, pass; a change fails: one setting missing, one differs,
# one compilation twice, one program missing, one it leaves out (an XFAIL
# case) compiled, only 1750 programs, a field missing)
for change in ok noset differ twice missing extra few form; do
    rows=$((rows + 1))
    awk '{ for (i = 0; i < 4; i++) print $1, (i == 0 ? "0" : i == 1 ? "2" : i == 2 ? "0g" : "2g"), "ok", "cc:clang" }' "$W/ocrun" >"$W/obj.results"
    case $change in
        noset) sed 4d "$W/obj.results" >"$W/r" ;;
        differ) sed '5s/ ok / differ /' "$W/obj.results" >"$W/r" ;;
        twice) { cat "$W/obj.results"; sed -n 1p "$W/obj.results"; } >"$W/r" ;;
        missing) sed 1,4d "$W/obj.results" >"$W/r" ;;
        extra) { cat "$W/obj.results"; x=$(grep -l '^// XFAIL:' "$ROOT"/tests/run/*.vl | head -1 | sed "s|^$ROOT/||")
                 for st in 0 2 0g 2g; do echo "$x $st ok cc:clang"; done; } >"$W/r" ;;
        few) head -7000 "$W/obj.results" >"$W/r" ;;
        form) sed '3s/ cc:clang$//' "$W/obj.results" >"$W/r" ;;
        ok) cp "$W/obj.results" "$W/r" ;;
    esac
    mv "$W/r" "$W/obj.results"
    echo "objcheck: 13048 of 13048 compilations for aarch64-macos give the same program as cc -c, 0 differ" >"$W/obj.log"
    out=$(sh "$F" objcheck "$W/obj.log" 60 100 300 2>&1)
    rc=$?
    want=1; [ $change = ok ] && want=0
    [ $rc -eq $want ] || { echo "FAIL objcheck, $change: exits $rc, not $want: $out"; failed=1; }
done
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
