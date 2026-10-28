#!/bin/sh
# The test runner's own checks (0.25.2): the pieces of tests/run.sh that
# decide an outcome without a compiler, on small fixtures made here: the
# EXPECT holes (tests/expect.awk), the golden-image comparison
# (tests/ppmdiff.sh), the directives' parse (tests/directives.awk) and
# the load-aware time limit (tests/watchdog.sh).
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

# dog NAME LOAD EXTEND: a 30-second sleep under a 1-second limit, the
# load average pretended; prints the watchdog's line and the seconds.
dog() {
    rm -f "$WORK/dog.$1"
    sleep 30 &
    spid=$!
    t0=$(date +%s)
    VOLE_WATCHDOG_LOAD=$2 VOLE_WATCHDOG_EXTEND=$3 sh "$ROOT/tests/watchdog.sh" 1 "$spid" "$WORK/dog.$1"
    wait "$spid" 2>/dev/null
    echo "$(($(date +%s) - t0)) $(cat "$WORK/dog.$1" 2>/dev/null)"
}
got=$(dog idle 0 8)
case "$got" in
    [1-3]" killed after 1 s, the limit (load average 0 on "*) ok watchdog_idle ;;
    *) bad watchdog_idle "got '$got'" ;;
esac
got=$(dog loaded 100000 2)
case "$got" in
    [3-6]" killed after 3 s: the limit, 1 s, extended 2 times while the load average was above the "*" CPUs (now 100000): a hang, or a machine loaded beyond that") ok watchdog_loaded ;;
    *) bad watchdog_loaded "got '$got'" ;;
esac
# a program that ends in time: no line, and the watchdog ends with it
sleep 1 &
spid=$!
t0=$(date +%s)
sh "$ROOT/tests/watchdog.sh" 20 "$spid" "$WORK/dog.quick"
if [ $(($(date +%s) - t0)) -le 3 ] && [ ! -e "$WORK/dog.quick" ]; then
    ok watchdog_in_time
else
    bad watchdog_in_time "waited $(($(date +%s) - t0)) s, wrote '$(cat "$WORK/dog.quick" 2>/dev/null)'"
fi

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

exit $BAD
