#!/bin/sh
# The test runner's own checks (0.25.2): the pieces of tests/run.sh that
# decide an outcome without a compiler, on small fixtures made here: the
# EXPECT holes (tests/expect.awk), the golden-image comparison
# (tests/ppmdiff.sh), the directives' parse (tests/directives.awk) and
# the load-aware time limit (tests/watchdog.sh) and the time budgets
# (tests/budget.sh), and (0.25.2) tests/run.sh's filters and tests/affected.map.
# The same directives on real programs are tests/run/runner_*.vl.
#
# usage: tests/runner/run.sh
#
# Prints `pass NAME` or `FAIL NAME` (and why) for each check; exits 1 if
# one failed.

set -u
LC_ALL=C
export LC_ALL

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/vole-runner.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
trap 'exit 130' INT TERM
BAD=0

ok() { echo "pass runner_$1"; }
bad() {
    echo "FAIL runner_$1: $2"
    BAD=1
}

# ---- EXPECT holes ----

# expect NAME WANT ACTUAL RC [MESSAGE]: tests/expect.awk on the two texts
# (printf formats) exits RC, and prints MESSAGE when given.
expect() {
    printf -- "$2" >"$WORK/want"
    printf -- "$3" >"$WORK/actual"
    out=$(awk -v want="$WORK/want" -f "$ROOT/tests/expect.awk" "$WORK/actual")
    rc=$?
    if [ $rc -ne "$4" ]; then
        bad "$1" "exit $rc, expected $4 ($out)"
    elif [ $# -ge 5 ] && [ "$out" != "$5" ]; then
        bad "$1" "printed '$out', expected '$5'"
    else
        ok "$1"
    fi
}

expect holes_exact 'a b\nc' 'a b\nc' 0
expect holes_num 'step {num} ms, {num} fps' 'step 0.25 ms, 120 fps' 0
expect holes_num_forms '{num} {num} {num} {num}' '-3 1.5e-3 .5 +7' 0
expect holes_int 'n={int}' 'n=-42' 0
expect holes_int_not_float 'n={int}' 'n=4.2' 1 "line 1: expected 'n={int}', got 'n=4.2'"
expect holes_num_not_word 'took {num} ms' 'took many ms' 1
expect holes_any 'built in {..}!' 'built in 3 s (cached)!' 0
expect holes_any_empty '[{..}]' '[]' 0
expect holes_any_one_line 'a {..}' 'a b\nc' 1 "line 2: expected the end of the output, got 'c'"
expect holes_backtrack '{..}x{num}' 'axbx12' 0
expect holes_braces_literal 'P { a: {int} }' 'P { a: 3 }' 0
expect holes_missing_line 'a\n{num}' 'a' 1 "line 2: expected '{num}', got the end of the output"
expect holes_second_line 'ok\nt={num}s\ndone' 'ok\nt=0.3s\nnot done' 1 "line 3: expected 'done', got 'not done'"

# ---- golden images ----

# ppm FILE W H R G B...: a P3 image of W x H pixels; each pixel's colour
# from a function of x and y given as an awk expression for r, g, b.
ppm() {
    awk -v w="$2" -v h="$3" -v r="$4" -v g="$5" -v b="$6" 'BEGIN {
        printf "P3\n# made by tests/runner/run.sh\n%d %d\n255\n", w, h
        for (y = 0; y < h; y++)
            for (x = 0; x < w; x++) {
                # the expressions name x and y: substitute them
                printf "%d %d %d\n", ev(r, x, y), ev(g, x, y), ev(b, x, y)
            }
    }
    function ev(e, x, y) {
        if (e == "x") return x * 10
        if (e == "y") return y * 10
        if (e == "xy") return (x + y) * 5
        return e + 0
    }' >"$1"
}

# pdiff NAME RC MESSAGE-PART -- ARGS...: tests/ppmdiff.sh ARGS exits RC
# and its line contains MESSAGE-PART ("": anything).
pdiff() {
    name=$1
    want=$2
    part=$3
    shift 4
    out=$(sh "$ROOT/tests/ppmdiff.sh" "$@" 2>&1)
    rc=$?
    if [ $rc -ne "$want" ]; then
        bad "$name" "exit $rc, expected $want ($out)"
    elif [ -n "$part" ]; then
        case "$out" in
            *"$part"*) ok "$name" ;;
            *) bad "$name" "printed '$out', not containing '$part'" ;;
        esac
    else
        ok "$name"
    fi
}

ppm "$WORK/a.ppm" 8 6 x y xy
ppm "$WORK/same.ppm" 8 6 x y xy
ppm "$WORK/black.ppm" 8 6 0 0 0
# near: one pixel off by 3 in red
awk 'NR == 4 + 9 { $1 = $1 + 3 } { print }' "$WORK/a.ppm" >"$WORK/near.ppm"
pdiff ppm_same 0 "" -- "$WORK/a.ppm" "$WORK/same.ppm"
pdiff ppm_differs 1 "47 of 48 pixels (97.92%) differ by more than 0" -- "$WORK/a.ppm" "$WORK/black.ppm"
pdiff ppm_worst 1 "the worst at (7,0) of the region (7,0 in the image): expected 0,0,0, got 70,0,35" -- "$WORK/a.ppm" "$WORK/black.ppm"
pdiff ppm_one_off 1 "1 of 48 pixels (2.08%)" -- "$WORK/near.ppm" "$WORK/a.ppm"
pdiff ppm_tolerance 0 "" -- -t 3 "$WORK/near.ppm" "$WORK/a.ppm"
pdiff ppm_allow 0 "" -- -p 2.5 "$WORK/near.ppm" "$WORK/a.ppm"
pdiff ppm_allow_short 1 "(allowed: 2%)" -- -p 2% "$WORK/near.ppm" "$WORK/a.ppm"
pdiff ppm_no_reference 3 "no reference" -- -o "$WORK/crop0.ppm" "$WORK/a.ppm" "$WORK/none.ppm"
[ -s "$WORK/crop0.ppm" ] && ok ppm_no_reference_kept || bad ppm_no_reference_kept "no image written with -o"
# a region: the crop written (P6) is the reference the region then matches
pdiff ppm_crop_written 3 "" -- -r 2,1,4,3 -o "$WORK/crop.ppm" "$WORK/a.ppm" "$WORK/none.ppm"
pdiff ppm_region_crop 0 "" -- -r 2,1,4,3 "$WORK/a.ppm" "$WORK/crop.ppm"
pdiff ppm_region_full_ref 0 "" -- -r 2,1,4,3 "$WORK/a.ppm" "$WORK/same.ppm"
pdiff ppm_region_elsewhere 1 "12 of 12 pixels" -- -r 0,0,4,3 "$WORK/a.ppm" "$WORK/crop.ppm"
pdiff ppm_region_outside 2 "is not inside" -- -r 6,4,4,3 "$WORK/a.ppm" "$WORK/crop.ppm"
pdiff ppm_size_mismatch 2 "the reference" -- -r 0,0,2,2 "$WORK/a.ppm" "$WORK/crop.ppm"
printf 'not an image\n' >"$WORK/text.ppm"
pdiff ppm_not_ppm 2 "is not a PPM image" -- "$WORK/text.ppm" "$WORK/a.ppm"
# the crop is a P6 file of the region's size
case "$(head -c 11 "$WORK/crop.ppm" | tr '\n' ' ')" in
    "P6 4 3 255 ") ok ppm_crop_p6 ;;
    *) bad ppm_crop_p6 "the crop's header is '$(head -c 11 "$WORK/crop.ppm" | tr '\n' ' ')'" ;;
esac

# ---- the load-aware time limit (tests/watchdog.sh) ----

# dog NAME LOAD EXTEND: a 600-second sleep under a 1-second limit, the
# load average pretended; prints the seconds it took, the sleep's exit
# status (137: killed) and the watchdog's line. The seconds are checked
# only against the limit (at least) and the sleep (well before it ends):
# on a loaded machine, or in a container whose host is (the gate's
# linux-aarch64 row), a second of the watchdog's can take many.
dog() {
    rm -f "$WORK/dog.$1"
    sleep 600 &
    spid=$!
    t0=$(date +%s)
    VOLE_WATCHDOG_LOAD=$2 VOLE_WATCHDOG_EXTEND=$3 sh "$ROOT/tests/watchdog.sh" 1 "$spid" "$WORK/dog.$1"
    wait "$spid" 2>/dev/null
    rc=$?
    echo "$(($(date +%s) - t0)) $rc $(cat "$WORK/dog.$1" 2>/dev/null)"
}
# in_time NAME MIN WANT GOT: GOT is `SECONDS 137 WANT...`, SECONDS at
# least MIN and under 300
in_time() {
    secs=${4%% *}
    rest=${4#* }
    case "$rest" in
        "137 "$3) [ "$secs" -ge "$2" ] && [ "$secs" -lt 300 ] && ok "$1" && return ;;
    esac
    bad "$1" "got '$4'"
}
in_time watchdog_idle 1 "killed after 1 s, the limit (load average 0 on "*" CPUs): a hang, or too slow" "$(dog idle 0 8)"
in_time watchdog_loaded 3 "killed after 3 s: the limit, 1 s, extended 2 times while the load average was above the "*" CPUs (now 100000): a hang, or a machine loaded beyond that" \
    "$(dog loaded 100000 2)"
# a program that ends in time: no line, and the watchdog ends with it
# (long before its limit)
sleep 1 &
spid=$!
t0=$(date +%s)
sh "$ROOT/tests/watchdog.sh" 600 "$spid" "$WORK/dog.quick"
if [ $(($(date +%s) - t0)) -lt 300 ] && [ ! -e "$WORK/dog.quick" ]; then
    ok watchdog_in_time
else
    bad watchdog_in_time "waited $(($(date +%s) - t0)) s, wrote '$(cat "$WORK/dog.quick" 2>/dev/null)'"
fi
# the CPUs and the load, as tests/load.sh reads them here
got=$(VOLE_TEST_LOAD= sh "$ROOT/tests/load.sh")
case "$got" in
    "load "[0-9]*" on "[1-9]*" CPUs") ok load_line ;;
    *) bad load_line "got '$got'" ;;
esac

# ---- time budgets (tests/budget.sh, tests/load.sh) ----

printf 'ok fast\nslow bench_x: took 552 us (budget 500 us)\n' >"$WORK/slow.out"
got=$(VOLE_TEST_LOAD=0 sh "$ROOT/tests/budget.sh" t_ "$WORK/slow.out"; echo "rc=$?")
case "$got" in
    "FAIL t_bench_x: took 552 us (budget 500 us)
rc=1") ok budget_idle_fails ;;
    *) bad budget_idle_fails "got '$got'" ;;
esac
got=$(VOLE_TEST_LOAD=100000 sh "$ROOT/tests/budget.sh" t_ "$WORK/slow.out"; echo "rc=$?")
case "$got" in
    "skip t_bench_x: machine loaded (load 100000 on "*" CPUs): took 552 us (budget 500 us)
rc=0") ok budget_loaded_skips ;;
    *) bad budget_loaded_skips "got '$got'" ;;
esac
printf 'ok fast\n' >"$WORK/fast.out"
got=$(VOLE_TEST_LOAD=0 sh "$ROOT/tests/budget.sh" t_ "$WORK/fast.out"; echo "rc=$?")
[ "$got" = "rc=0" ] && ok budget_within || bad budget_within "got '$got'"

# ---- the directives ----

cat >"$WORK/case.vl" <<'EOF'
// EXPECT: took {num} ms
// EXPECT-PPM: out.ppm tests/golden/x.ppm region 0,0,4,4 tolerance 2
// EXPECT-PPM: second.ppm tests/golden/y.ppm
EOF
mkdir "$WORK/d"
awk -v dir="$WORK/d" -v target=aarch64-macos -f "$ROOT/tests/directives.awk" "$WORK/case.vl"
if [ "$(cat "$WORK/d/expect")" = "took {num} ms" ] && [ "$(wc -l <"$WORK/d/ppms" | tr -d ' ')" = 2 ] \
        && [ "$(head -1 "$WORK/d/ppms")" = "out.ppm tests/golden/x.ppm region 0,0,4,4 tolerance 2" ]; then
    ok directives_ppm
else
    bad directives_ppm "expect '$(cat "$WORK/d/expect")', ppms '$(cat "$WORK/d/ppms")'"
fi

# ---- the filters and the plan (tests/run.sh -l, tests/affected.sh) ----

# Every `case $(want NAME)` of run.sh is in its SUITES (what -l lists),
# and every one of SUITES has its site.
sites=$(sed -n 's/^ *case \$(want \([a-z_-]*\)) in$/\1/p' "$ROOT/tests/run.sh" | sort -u | tr '\n' ' ')
listed=$(sed -n 's/^SUITES="\(.*\)"$/\1/p' "$ROOT/tests/run.sh" | tr ' ' '\n' | sort -u | tr '\n' ' ')
[ -n "$sites" ] && [ "$sites" = "$listed" ] && ok filters_suites_listed \
    || bad filters_suites_listed "the want sites '$sites' are not SUITES '$listed'"
# A FILTER selects the names containing it, =NAME one name, -f a file's.
got=$(sh "$ROOT/tests/run.sh" -l runner_ =runner | sort | tr '\n' ',')
want=$(ls "$ROOT"/tests/run/ | sed -n 's/^\(runner_[^.]*\)\.vl$/case \1/p'; echo "suite runner")
want=$(printf '%s\n' "$want" | sort | tr '\n' ',')
[ "$got" = "$want" ] && ok filters_union || bad filters_union "got '$got', expected '$want'"
printf '# a comment\n=readme_sync\n\n=example_helloworld  \n' >"$WORK/filters"
got=$(sh "$ROOT/tests/run.sh" -l -f "$WORK/filters" | tr '\n' ',')
[ "$got" = "case example_helloworld,suite readme_sync," ] && ok filters_file || bad filters_file "got '$got'"
# (0.25.5) -n NAME: one name, as '=NAME', in a form zsh leaves alone.
got=$(sh "$ROOT/tests/run.sh" -l -n readme_sync -n example_helloworld | sort | tr '\n' ',')
[ "$got" = "case example_helloworld,suite readme_sync," ] && ok filters_dash_n || bad filters_dash_n "got '$got'"
# (0.25.5) the failing cases' try: line names them with -n (a compiler
# that fails every case)
printf '#!/bin/sh\necho "error: no" >&2\nexit 1\n' >"$WORK/failing-volec"
chmod +x "$WORK/failing-volec"
got=$(sh "$ROOT/tests/run.sh" -c "$WORK/failing-volec" -j 2 -n abi_callee_alignment -n abi_extern_small_struct 2>&1 | tail -1)
[ "$got" = "try: tests/run.sh -n abi_callee_alignment -n abi_extern_small_struct   (the failing cases alone)" ] \
    && ok filters_try_dash_n || bad filters_try_dash_n "got '$got'"
# ---- the transcript runners' jobs (0.30: tests/jobs.sh) ----

# A FILTER selects the transcripts and checks whose name contains it, -n
# and =NAME one name; -l lists them and runs nothing.
got=$(sh "$ROOT/tests/query/run.sh" -l -n clash effects_agree =self_show | tr '\n' ',')
[ "$got" = "check effects_agree_effagree_host,check effects_agree_effagree_aarch64-linux,check effects_agree_effagree_x86_64-linux,check self_show,transcript clash," ] \
    && ok jobs_filter || bad jobs_filter "got '$got'"
# Selecting nothing is an error that says so, not a pass (every runner
# that takes names).
why=""
for r in query refactor lsp fmt; do
    got=$(sh "$ROOT/tests/$r/run.sh" no_such_name_here 2>&1)
    rc=$?
    case "$rc:$got" in
        "2:tests/$r/run.sh: no case matches no_such_name_here "*) ;;
        *) why="$why $r: exit $rc, '$got';" ;;
    esac
done
[ -z "$why" ] && ok jobs_no_match || bad jobs_no_match "$why"
# --grep TEXT: the transcripts whose file holds TEXT, and no check; -u:
# no check either.
want=$(grep -l -F 'query.no-match' "$ROOT"/tests/query/*.q | sed 's|.*/\(.*\)\.q$|transcript \1|' | tr '\n' ',')
got=$(sh "$ROOT/tests/query/run.sh" -l --grep 'query.no-match' | tr '\n' ',')
[ -n "$want" ] && [ "$got" = "$want" ] && ok jobs_grep || bad jobs_grep "got '$got', expected '$want'"
got=$(sh "$ROOT/tests/refactor/run.sh" -l -u | grep -c '^check ')
[ "$got" = 0 ] && ok jobs_update_no_checks || bad jobs_update_no_checks "$got checks listed with -u"
# Every check a runner lists has its arm in job_check, and every arm is
# listed.
why=""
for r in query refactor; do
    listed=$(sed -n 's/^CHECKS="\(.*\)"$/\1/p' "$ROOT/tests/$r/run.sh" | tr ' ' '\n' | sort | tr '\n' ' ')
    arms=$(awk '/^job_check\(\) \{/ { on = 1 } on && /^}/ { on = 0 } on && /^        [a-z][A-Za-z0-9_-]*\)$/ { sub(/\)$/, ""); print $1 }' \
        "$ROOT/tests/$r/run.sh" | sort | tr '\n' ' ')
    [ -n "$listed" ] && [ "$listed" = "$arms" ] || why="$why $r: CHECKS '$listed', arms '$arms';"
done
[ -z "$why" ] && ok jobs_checks_listed || bad jobs_checks_listed "$why"
# The jobs run some at once, each one's report printed when it ends (the
# quick one first when two run at once, the file's order with one); a
# job that reports nothing is a failure of its name.
(
    . "$ROOT/tests/jobs.sh"
    run_job() {
        case "$2" in
            slow) sleep 2; echo "pass slow" ;;
            quick) echo "pass quick" ;;
            silent) : ;;
        esac
    }
    printf 'check slow\ncheck quick\ncheck silent\n' >"$WORK/jobs"
    two=$(jobs_run "$WORK/jobs" 2 | tr '\n' ',')
    one=$(jobs_run "$WORK/jobs" 1 | tr '\n' ',')
    [ "$two" = "pass quick,FAIL silent: the job reported nothing,pass slow," ] \
        && [ "$one" = "pass slow,pass quick,FAIL silent: the job reported nothing," ] \
        && [ "$(jobs_count pass)" = 2 ] && [ "$(jobs_count FAIL)" = 1 ] \
        && ok jobs_stream || bad jobs_stream "-j 2: '$two'; -j 1: '$one'"
)
[ $? -eq 0 ] || BAD=1
# A run's first line is its plan, its last the counts; a transcript that
# differs fails the run (a compiler that prints nothing).
printf '#!/bin/sh\nexit 0\n' >"$WORK/silent-volec"
chmod +x "$WORK/silent-volec"
got=$(sh "$ROOT/tests/query/run.sh" -c "$WORK/silent-volec" -j 2 -n clash 2>&1)
rc=$?
case "$rc:$(printf '%s\n' "$got" | head -1):$(printf '%s\n' "$got" | grep -c '^FAIL clash (\(off\|cache\)): '):$(printf '%s\n' "$got" | tail -1)" in
    "1:query: 1 transcripts (off cache), 0 checks, -j 2:2:query: 0 passed, 2 failed, "*" s") ok jobs_plan_and_counts ;;
    *) bad jobs_plan_and_counts "exit $rc: $(printf '%s\n' "$got" | head -1) ... $(printf '%s\n' "$got" | tail -1)" ;;
esac
# tests/run.sh SUITE:FILTER: the suite, its runner given the filter.
got=$(sh "$ROOT/tests/run.sh" -l refactor:rename query:=clash query:self_ | tr '\n' ',')
[ "$got" = "suite query only =clash self_,suite refactor only rename," ] && ok filters_suite_names || bad filters_suite_names "got '$got'"
# (the suite itself selected too: all of it)
got=$(sh "$ROOT/tests/run.sh" -l -n query query:=clash lsp:embed lsp | tr '\n' ',')
[ "$got" = "suite query,suite lsp," ] && ok filters_suite_whole || bad filters_suite_whole "got '$got'"

# (0.30) An option after a FILTER is an error that says where it goes.
got=$(sh "$ROOT/tests/run.sh" -j 2 pathtrace -O 2 2>&1)
rc=$?
want="tests/run.sh: the option '-O' comes after the FILTER 'pathtrace': options go before the FILTERs
try: tests/run.sh -j 2 -O 2 pathtrace"
[ $rc -eq 2 ] && [ "$got" = "$want" ] && ok filters_option_after || bad filters_option_after "exit $rc: '$got'"
# (0.30) A FILTER of digits only: a warning, with how many it selects.
got=$(sh "$ROOT/tests/run.sh" -l 2 2>&1 >/dev/null)
case "$got" in
    "tests/run.sh: warning: the FILTER '2' is only digits: it selects every name containing '2' ("*" cases); "*) ok filters_digits ;;
    *) bad filters_digits "got '$got'" ;;
esac
# (0.30) --cases-only: no suite.
got=$(sh "$ROOT/tests/run.sh" -l --cases-only runner_ fmt | grep -c '^suite ')
all=$(sh "$ROOT/tests/run.sh" -l runner_ fmt | grep -c '^suite ')
[ "$got" = 0 ] && [ "$all" -ge 1 ] && ok filters_cases_only || bad filters_cases_only "$got suites with --cases-only, $all without"
# (0.30) The first line is the plan; a suite's line comes as it ends; a
# FILTER that selects nothing is an error, and a suite given a name it
# has not fails saying so (a compiler that fails every case).
got=$(sh "$ROOT/tests/run.sh" -c "$WORK/failing-volec" -j 2 -n abi_callee_alignment -n readme_sync lsp:no_such_session 2>&1)
case "$(printf '%s\n' "$got" | sed -n 1p)" in
    "plan: 1 case, 2 suites (lsp: no_such_session, readme_sync), -j 2, "*) ok plan_first ;;
    *) bad plan_first "$(printf '%s\n' "$got" | sed -n 1p)" ;;
esac
if printf '%s\n' "$got" | sed -n 2p | grep -q '^suite lsp: 0 pass, 0 FAIL, exit 2, [0-9]* s$' \
    && printf '%s\n' "$got" | grep -q '^FAIL lsp: tests/lsp/run.sh reported nothing:$' \
    && printf '%s\n' "$got" | grep -q 'tests/lsp/run.sh: no case matches no_such_session'; then
    ok plan_suite_line
else
    bad plan_suite_line "$(printf '%s\n' "$got" | sed -n 2,6p | tr '\n' ';')"
fi
got=$(sh "$ROOT/tests/run.sh" -c "$WORK/failing-volec" -j 2 no_such_case_at_all 2>&1)
rc=$?
case "$rc:$got" in
    "2:tests/run.sh: no case matches 'no_such_case_at_all' "*) ok filters_no_match ;;
    *) bad filters_no_match "exit $rc: '$got'" ;;
esac
got=$(sh "$ROOT/tests/run.sh" -c "$WORK/failing-volec" -j 2 -n readme_sync no_such_case_at_all 2>&1 | sed -n 1p)
[ "$got" = "tests/run.sh: warning: no case matches 'no_such_case_at_all' (the other FILTERs select the plan below)" ] \
    && ok filters_no_match_one || bad filters_no_match_one "got '$got'"

# tests/affected.map: every set, cmd and prefix it names exists.
problems=$(awk '
    { sub(/#.*/, "") }
    NF == 0 { next }
    $1 == "set" { sets[$2] = 1; for (i = 3; i <= NF; i++) use[$i] = 1; next }
    $1 == "cmd" { cmds[$2] = 1; next }
    { prefixes[$1] = 1; for (i = 2; i <= NF; i++) use[$i] = 1 }
    END {
        for (u in use) {
            if (u ~ /^@(self|example|mentions|none)$/) continue
            if (u ~ /^@/ && !(substr(u, 2) in sets)) print "no set " u
            if (u ~ /^!/ && !(substr(u, 2) in cmds)) print "no cmd " u
        }
        for (p in prefixes) print "prefix " p
    }' "$ROOT/tests/affected.map" | while read -r kind what; do
        if [ "$kind" != prefix ]; then
            echo "$kind $what"
        elif [ "$what" != "*" ] && [ ! -e "$ROOT/$what" ]; then
            echo "no path $what"
        fi
    done)
[ -z "$problems" ] && ok affected_map || bad affected_map "$(echo $problems)"

# (0.29) tests/affected.sh's plan, in a small repository of its own (the
# script, the map and run.sh; two examples, one whose README has a
# session): prose in an example gets the layout checks, and the
# walkthroughs only when its README is one they run; a file git does not
# track is named in the plan and not counted, unless --untracked.
A="$WORK/affected"
mkdir -p "$A/tests/run" "$A/tests/examples" "$A/examples/plain" "$A/examples/session"
cp "$ROOT/tests/affected.sh" "$ROOT/tests/affected.map" "$ROOT/tests/run.sh" "$A/tests/"
printf 'fn main() -> i32 { 0 }\n' >"$A/examples/plain/main.vl"
cp "$A/examples/plain/main.vl" "$A/examples/session/main.vl"
printf '# plain\n' >"$A/examples/plain/README.md"
printf '# session\n\n```console\n$ volec check\n```\n' >"$A/examples/session/README.md"
printf '// SOURCE: examples/plain/main.vl\n' >"$A/tests/examples/plain.test"
if (cd "$A" && git init -q -b main . && git add -A \
    && git -c user.name=t -c user.email=t@t commit -q -m base) >/dev/null 2>&1; then
    echo more >>"$A/examples/plain/README.md"
    got=$(cd "$A" && sh tests/affected.sh --list 2>&1)
    case "$got" in
        *"examples/plain/README.md) -> @example:=example_layout,=readme_sync"*"suites: example_layout readme_sync (2 of"*)
            ok affected_readme_prose ;;
        *) bad affected_readme_prose "$got" ;;
    esac
    (cd "$A" && git checkout -q -- . && echo more >>examples/session/README.md)
    got=$(cd "$A" && sh tests/affected.sh --list 2>&1)
    case "$got" in
        *"=example_layout,=readme_sync,=walkthrough"*) ok affected_readme_session ;;
        *) bad affected_readme_session "$got" ;;
    esac
    (cd "$A" && git checkout -q -- . && echo more >>examples/plain/main.vl && mkdir old-output && echo x >old-output/a.ppm)
    got=$(cd "$A" && sh tests/affected.sh --list 2>&1)
    case "$got" in
        *"1 changed paths"*"untracked, not counted: 1 file(s): old-output/a.ppm (git add"*) ok affected_untracked_named ;;
        *) bad affected_untracked_named "$got" ;;
    esac
    got=$(cd "$A" && sh tests/affected.sh --list --untracked 2>&1)
    case "$got" in
        *"2 changed paths"*"(1 path: old-output/a.ppm) -> "*"untracked, counted (--untracked): 1 file(s)"*) ok affected_untracked_counted ;;
        *) bad affected_untracked_counted "$got" ;;
    esac
else
    bad affected_readme_prose "git could not make the repository"
fi

# ---- tests/run.sh --bless (0.30) ----

# In a small tree of its own (run.sh, the directives' parse, two cases)
# with a compiler that reports two errors: the case whose errors are
# those at other positions gets the positions of now (a position in a
# note too), and passes; the one whose message differs is left as it was,
# with why, and fails.
BL="$WORK/bless"
mkdir -p "$BL/tests/run" "$BL/compiler/src"
cp "$ROOT/tests/run.sh" "$ROOT/tests/directives.awk" "$BL/tests/"
cat >"$BL/volec" <<'EOF'
#!/bin/sh
for a in "$@"; do
    case "$a" in
        --check-rules) exit 0 ;;
        --version) echo "volec (the runner's own)"; exit 0 ;;
    esac
done
echo "error[type error]: expected 'i32', got 'i64'" >&2
echo " --> case.vl: line 11, column 5" >&2
echo "error[own.moved]: v was moved" >&2
echo " --> case.vl: line 20, column 9" >&2
echo "  = note: moved at line 18, column 13" >&2
exit 1
EOF
chmod +x "$BL/volec"
printf '%s\n' "// ERROR: error[type error]: expected 'i32', got 'i64'" '// ERROR: line 10, column 5' '// ERROR: error[own.moved]' \
    '// ERROR: line 19, column 9' '// ERROR: moved at line 17, column 13' '// ERROR-COUNT: 2' 'fn main() {}' >"$BL/tests/run/err_moved.vl"
printf '%s\n' "// ERROR: error[type error]: expected 'i32', got 'u8'" '// ERROR: line 10, column 5' 'fn main() {}' >"$BL/tests/run/err_changed.vl"
cp "$BL/tests/run/err_changed.vl" "$BL/changed.orig"
printf '%s\n' "// ERROR: error[type error]: expected 'i32', got 'i64'" '// ERROR: line 11, column 5' '// ERROR: error[own.moved]' \
    '// ERROR: line 20, column 9' '// ERROR: moved at line 18, column 13' '// ERROR-COUNT: 2' 'fn main() {}' >"$BL/moved.want"
got=$(sh "$BL/tests/run.sh" -c "$BL/volec" -j 2 --bless err_ 2>&1)
rc=$?
if [ $rc -eq 1 ] && cmp -s "$BL/tests/run/err_moved.vl" "$BL/moved.want" && cmp -s "$BL/tests/run/err_changed.vl" "$BL/changed.orig" \
    && printf '%s\n' "$got" | grep -q -x -F "blessed err_moved: 3 directives: line 10, column 5 -> line 11, column 5; line 19, column 9 -> line 20, column 9; moved at line 17, column 13 -> moved at line 18, column 13" \
    && printf '%s\n' "$got" | grep -q "^not blessed err_changed: the compiler does not report 'error\[type error\]: expected 'i32', got 'u8'', positions aside" \
    && printf '%s\n' "$got" | grep -q '^  total  *1  *0  *1  *0$'; then
    ok bless_positions
else
    bad bless_positions "exit $rc: $(printf '%s\n' "$got" | tr '\n' ';')"
fi
# --bless without a case named is refused.
got=$(sh "$BL/tests/run.sh" -c "$BL/volec" --bless 2>&1)
rc=$?
case "$rc:$got" in
    "2:tests/run.sh: --bless takes the cases to bless"*) ok bless_needs_names ;;
    *) bad bless_needs_names "exit $rc: $got" ;;
esac

exit $BAD
