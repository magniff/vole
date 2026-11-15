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
# (objcheck's programs by name, from tests/objcheck.sh --list itself: the
# floor's own greps must give the same set)
sh "$ROOT/tests/objcheck.sh" --list -t aarch64-macos | grep '^tests/run/' | sort >"$W/ocrun"
OCR="of tests/run $(wc -l <"$W/ocrun" | tr -d ' '), names $(cksum <"$W/ocrun" | tr ' ' -)"
check objcheck 13048 "cc: clang" "objcheck: @N@ of @N@ compilations for aarch64-macos give the same program as cc -c, 0 differ" "objcheck programs: 3245, each at 4 settings, names 1-1; $OCR"
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
# on every host, never a fraction of macOS's count: each case by name (the
# digest of the names run), and the skipped ones by name. LX: the cases a
# REQUIRES of metal or macos skips off macOS (the examples' included), CL
# those needing clang, MT metal's alone. Each row: the host, cc's line,
# the plan, the `cases:` line's pass, xfail and fail, the skipped names
# (none; lx; lx-1: LX but one; lxcl: LX and CL; cl; any: as many
# arbitrary cases as LX; metal), the names run (all; dup: one twice and
# another left out), the table total's pass (+400: the suites' checks
# too; or a number), the exit wanted.)
sh "$ROOT/tests/run.sh" -l 2>/dev/null | sed -n 's/^case //p' | sort >"$W/listed"
L=$(wc -l <"$W/listed" | tr -d ' ')
DL=$(cksum <"$W/listed" | tr ' ' -)
{ sed 1d "$W/listed"; sed -n 2p "$W/listed"; } | sort >"$W/dup"
DD=$(cksum <"$W/dup" | tr ' ' -)
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
grep -vxF -f "$W/lx" "$W/listed" | grep -vxF -f "$W/cl" | head -"$LX" >"$W/any"
while read -r host cc plan pass xf fl skips ran total want; do
    rows=$((rows + 1))
    case "$skips" in
        none) : >"$W/skips" ;;
        lx) cp "$W/lx" "$W/skips" ;;
        lx-1) sed 1d "$W/lx" >"$W/skips" ;;
        lxcl) cat "$W/lx" "$W/cl" >"$W/skips" ;;
        cl) cp "$W/cl" "$W/skips" ;;
        any) cp "$W/any" "$W/skips" ;;
        metal) cp "$W/mt" "$W/skips" ;;
    esac
    sk=$(wc -l <"$W/skips" | tr -d ' ')
    [ "$pass" = rest ] && pass=$((L - xf - fl - sk))
    [ "$total" = more ] && total=$((pass + 400))
    d=$DL; [ "$ran" = dup ] && d=$DD
    { [ "$plan" = none ] || echo "plan: $plan cases, 26 suites (query), -j 4, $host"
      echo "cc: $cc" | tr _ ' '
      printf '  total       %s    %s     %s     %s\n' "$total" "$xf" "$fl" "$sk"
      echo "cases: $pass passed, $xf xfail, $fl failed, $sk skipped of $((pass + xf + fl + sk)), names $d"
      sed 's/^\(.*\)$/skip case \1: REQUIRES metal/' "$W/skips"; } >"$W/suite.log"
    out=$(sh "$F" suite-O2 "$W/suite.log" 60 100 300 "$host" 2>&1)
    rc=$?
    [ $rc -eq "$want" ] || { echo "FAIL suite-O2 on $host ($cc), plan $plan, $pass $xf $fl, skipped $skips, ran $ran, total $total: exits $rc, not $want: $out"; failed=1; }
done <<EOT
aarch64-macos clang $L rest 717 0 none all more 0
aarch64-linux not_clang $L rest 717 0 lxcl all more 0
aarch64-linux clang $L rest 717 0 lx all more 0
aarch64-linux clang $L rest 717 0 lxcl all more 1
aarch64-linux not_clang $L rest 717 0 lx all more 1
aarch64-linux clang $L rest 717 0 lx-1 all more 1
aarch64-macos clang $L rest 717 0 any all more 1
aarch64-macos clang $L rest 717 0 lx all more 1
aarch64-macos clang $L rest 717 0 cl all more 1
aarch64-macos not_clang $L rest 717 0 cl all more 0
aarch64-macos clang $L rest 717 0 none dup more 1
aarch64-macos clang $L rest 717 0 none all 3000 1
aarch64-linux clang 1501 1501 0 0 none all more 1
aarch64-macos clang $((L - 1)) rest 717 0 none all more 1
aarch64-macos clang $L rest 717 1 none all more 1
aarch64-macos clang none rest 717 0 none all more 1
x86_64-macos clang $L rest 717 0 metal all more 0
x86_64-macos clang $L rest 717 0 none all more 1
EOT
# (a log with the table and no `cases:` line fails; so do two cases lines,
# the bad one first, and two plans)
rows=$((rows + 1))
{ echo "plan: $L cases, 26 suites (query), -j 4, aarch64-macos"; echo "cc: clang"
  printf '  total       %s    717     0     0\n' "$((L - 717 + 400))"; } >"$W/suite.log"
sh "$F" suite-O2 "$W/suite.log" 60 100 300 >/dev/null 2>&1 \
    && { echo "FAIL suite-O2: a log without its cases line passes"; failed=1; }
rows=$((rows + 1))
{ echo "plan: $L cases, 26 suites (query), -j 4, aarch64-macos"; echo "cc: clang"
  printf '  total       %s    717     0     0\n' "$((L - 717 + 400))"
  echo "cases: 100 passed, 0 xfail, $((L - 100)) failed, 0 skipped of $L, names $DL"
  echo "cases: $((L - 717)) passed, 717 xfail, 0 failed, 0 skipped of $L, names $DL"; } >"$W/suite.log"
sh "$F" suite-O2 "$W/suite.log" 60 100 300 >/dev/null 2>&1 \
    && { echo "FAIL suite-O2: two cases lines, the bad one first, pass"; failed=1; }
rows=$((rows + 1))
{ echo "plan: $L cases, 26 suites (query), -j 4, aarch64-macos"
  echo "plan: 3 cases, 0 suites, -j 2, aarch64-macos"; echo "cc: clang"
  printf '  total       %s    717     0     0\n' "$((L - 717 + 400))"
  echo "cases: $((L - 717)) passed, 717 xfail, 0 failed, 0 skipped of $L, names $DL"; } >"$W/suite.log"
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
printf 'cc: clang\nobjcheck: 7000 of 7000 compilations for aarch64-macos give the same program as cc -c, 0 differ\nobjcheck programs: 1750, each at 4 settings, names 1-1; %s\n' "$OCR" >"$W/obj.log"
sh "$F" objcheck "$W/obj.log" 60 100 300 >/dev/null 2>&1 \
    && { echo "FAIL objcheck: 7000 of 7000 passes"; failed=1; }
# (objcheck: one compilation that differs fails)
rows=$((rows + 1))
printf 'objcheck: 13047 of 13048 compilations for aarch64-linux give the same program as cc -c, 1 differ\n' >"$W/obj.log"
sh "$F" objcheck "$W/obj.log" 60 100 300 aarch64-linux >/dev/null 2>&1 \
    && { echo "FAIL objcheck: 13047 of 13048 passes"; failed=1; }
# (objcheck: the right count with its tests/run programs not the tree's,
# one left out and another twice, fails)
rows=$((rows + 1))
{ sed 1d "$W/ocrun"; sed -n 2p "$W/ocrun"; } | sort >"$W/ocdup"
printf 'cc: clang\nobjcheck: 21660 of 21660 compilations for aarch64-macos give the same program as cc -c, 0 differ\nobjcheck programs: 5415, each at 4 settings, names 1-1; of tests/run %s, names %s\n' "$(wc -l <"$W/ocdup" | tr -d ' ')" "$(cksum <"$W/ocdup" | tr ' ' -)" >"$W/obj.log"
sh "$F" objcheck "$W/obj.log" 60 100 300 >/dev/null 2>&1 \
    && { echo "FAIL objcheck: programs not the tree's pass"; failed=1; }
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
