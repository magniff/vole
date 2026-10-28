#!/bin/sh
# Runs the NES conformance ROMs found in a directory against the emulator
# and prints one line per ROM (README.md, "Conformance ROMs"). No ROM is
# in this repository: download the suites yourself and point this at
# them; whatever is there is run, the rest is not looked for.
#
# usage: examples/nes/run-roms.sh [-n NES] [-f FRAMES] [-k] ROM_DIR
#   -n NES      the emulator to run (default: built from examples/nes/
#               with target/volec -O2, into a temporary directory)
#   -f FRAMES   frames for a ROM without NAME.frames (default 3000: 50
#               seconds of the console's time)
#   -k          keep each ROM's last frame as NAME.shot.ppm next to it
#
# Every *.nes under ROM_DIR (any depth) is one of three kinds, decided in
# this order:
#   nestest     a ROM named nestest.nes with nestest.log beside it: run
#               from $C000 (the automated mode) with --trace, every
#               instruction's PC, opcode, A, X, Y, P and SP compared with
#               the log's; the first line that differs is the failure
#   $6000       a ROM that reports at $6000 (blargg's protocol: $6001-
#               $6003 hold DE B0 61, $6000 is $80 while it runs, then the
#               result, 0 for passed; the text at $6004): run headless for
#               its frames, the status and the first line of the text
#               printed
#   picture     a ROM with NAME.ppm beside it (its final screen, the ROMs
#               that report only on screen: sprite_hit_tests, ...): its
#               last frame compared with that image (tests/ppmdiff.sh,
#               exact); without one, the ROM gets no verdict (`look`) and
#               its last frame is kept as NAME.shot.ppm to look at, or to
#               rename to NAME.ppm once it is right
# NAME.frames beside a ROM (one number) is its frame count. The results
# README.md lists as limits of the emulator (cpu_interrupts_v2 2-5,
# sprite_overflow_tests 1-4, mmc3_test_2's 6-MMC3_alt) are `xfail`, not
# failures.
#
# Prints `pass ROM: ...`, `FAIL ROM: ...`, `xfail ROM: ...` or `look ROM:
# ...` for each ROM, then a summary; exits 1 when a ROM failed, 2 on a
# usage error. POSIX sh and awk.

set -u
LC_ALL=C
export LC_ALL

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
NES=""
FRAMES=3000
KEEP=0
usage() {
    echo "usage: examples/nes/run-roms.sh [-n NES] [-f FRAMES] [-k] ROM_DIR" >&2
    exit 2
}
while [ $# -gt 0 ]; do
    case "$1" in
        -n) [ $# -ge 2 ] || usage; NES=$2; shift 2 ;;
        -f) [ $# -ge 2 ] || usage; FRAMES=$2; shift 2 ;;
        -k) KEEP=1; shift ;;
        -h|--help) sed -n '2,38p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) usage ;;
        *) break ;;
    esac
done
[ $# -eq 1 ] || usage
DIR=$1
[ -d "$DIR" ] || { echo "run-roms: no directory $DIR" >&2; exit 2; }
case "$FRAMES" in ''|*[!0-9]*) usage ;; esac

WORK=$(mktemp -d "${TMPDIR:-/tmp}/vole-nes-roms.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
trap 'exit 130' INT TERM

if [ -z "$NES" ]; then
    NES="$WORK/nes"
    if ! "$ROOT/target/volec" -O2 "$HERE/main.vl" -o "$NES" >"$WORK/build.out" 2>&1; then
        echo "run-roms: the emulator does not build:" >&2
        cat "$WORK/build.out" >&2
        exit 2
    fi
fi
[ -x "$NES" ] || { echo "run-roms: no emulator at $NES (-n)" >&2; exit 2; }

# The results README.md names as the emulator's limits.
known_failure() {
    case "$1" in
        *cpu_interrupts*/[2-5]-*|*cpu_interrupts*[2-5]-*) return 0 ;;
        *sprite_overflow*/[1-4].*|*sprite_overflow*/0[1-4]*) return 0 ;;
        *6-MMC3_alt*) return 0 ;;
    esac
    return 1
}

PASS=0
FAIL=0
XFAIL=0
LOOK=0
# outcome VERDICT ROM TEXT: one line; a FAIL of a known limit is an xfail.
outcome() {
    v=$1
    if [ "$v" = FAIL ] && known_failure "$2"; then
        v=xfail
    fi
    echo "$v $2: $3"
    case "$v" in
        pass) PASS=$((PASS + 1)) ;;
        FAIL) FAIL=$((FAIL + 1)) ;;
        xfail) XFAIL=$((XFAIL + 1)) ;;
        look) LOOK=$((LOOK + 1)) ;;
    esac
}

find "$DIR" -name '*.nes' -type f | sort >"$WORK/roms"
[ -s "$WORK/roms" ] || { echo "run-roms: no .nes file under $DIR"; exit 0; }

while IFS= read -r rom; do
    name=${rom#"$DIR"/}
    base=${rom%.nes}
    frames=$FRAMES
    if [ -f "$base.frames" ]; then
        frames=$(tr -dc '0-9' <"$base.frames")
        [ -n "$frames" ] || frames=$FRAMES
    fi
    # nestest: the trace against the log
    if [ "${rom##*/}" = nestest.nes ] && [ -f "${rom%/*}/nestest.log" ]; then
        log="${rom%/*}/nestest.log"
        n=$(wc -l <"$log" | tr -d ' ')
        "$NES" "$rom" --headless --pc c000 --frames 1 --trace "$n" </dev/null >"$WORK/trace" 2>&1
        # the log's columns, in --trace's shape: pc op A X Y P SP, lower case
        awk '{
            pc = tolower($1); op = tolower($2); a = x = y = p = sp = ""
            for (i = 3; i <= NF; i++) {
                if ($i ~ /^A:/) a = substr($i, 3)
                else if ($i ~ /^X:/) x = substr($i, 3)
                else if ($i ~ /^Y:/) y = substr($i, 3)
                else if ($i ~ /^P:/) p = substr($i, 3)
                else if ($i ~ /^SP:/) sp = substr($i, 4)
            }
            printf "%s %s A:%s X:%s Y:%s P:%s SP:%s\n", pc, op, tolower(a), tolower(x), tolower(y), tolower(p), tolower(sp)
        }' "$log" >"$WORK/want"
        grep -E '^[0-9a-f]{4} [0-9a-f]{2} A:' "$WORK/trace" >"$WORK/got"
        diffline=$(awk 'NR == FNR { w[FNR] = $0; nw = FNR; next }
            { g[FNR] = $0; ng = FNR }
            END {
                for (i = 1; i <= nw; i++)
                    if (g[i] != w[i]) { printf "line %d: the log has \"%s\", the emulator \"%s\"", i, w[i], (i > ng ? "(nothing)" : g[i]); exit }
            }' "$WORK/want" "$WORK/got")
        if [ -z "$diffline" ]; then
            outcome pass "$name" "all $n instructions match nestest.log"
        else
            outcome FAIL "$name" "$diffline"
        fi
        continue
    fi
    shot="$WORK/shot.ppm"
    "$NES" "$rom" --headless --frames "$frames" --state --shot "$shot" </dev/null >"$WORK/state" 2>"$WORK/stderr"
    rc=$?
    [ $KEEP -eq 1 ] && [ -f "$shot" ] && cp "$shot" "$base.shot.ppm"
    if [ $rc -gt 1 ] || ! grep -q '^cpu pc=' "$WORK/state"; then
        outcome FAIL "$name" "the emulator stopped (exit $rc): $(head -1 "$WORK/stderr")"
        continue
    fi
    # --state: line 3 is $6000-$602F in hex, then the text at $6004 up to
    # the `ppu ctrl=` line
    status=$(awk 'NR == 3 { if ($2 == "de" && $3 == "b0" && $4 == "61") print $1; exit }' "$WORK/state")
    if [ -n "$status" ]; then
        text=$(awk 'NR > 3 && /^ppu ctrl=/ { exit } NR > 3 && NF { print; exit }' "$WORK/state")
        case "$status" in
            00) outcome pass "$name" "\$6000 = 00${text:+: $text}" ;;
            80) outcome FAIL "$name" "still running after $frames frames (\$6000 = 80; ${base##*/}.frames beside it gives it more)" ;;
            81) outcome FAIL "$name" "asks for a reset (\$6000 = 81), which this runner does not press" ;;
            *) outcome FAIL "$name" "\$6000 = $status${text:+: $text}" ;;
        esac
        continue
    fi
    if [ -f "$base.ppm" ]; then
        if d=$(sh "$ROOT/tests/ppmdiff.sh" "$shot" "$base.ppm" 2>&1); then
            outcome pass "$name" "the last frame is ${base##*/}.ppm"
        else
            outcome FAIL "$name" "the last frame is not ${base##*/}.ppm: $d"
        fi
        continue
    fi
    [ -f "$shot" ] && cp "$shot" "$base.shot.ppm"
    outcome look "$name" "no \$6000 status and no ${base##*/}.ppm: its last frame is ${base##*/}.shot.ppm"
done <"$WORK/roms"

echo "run-roms: $PASS passed, $FAIL failed, $XFAIL known failures, $LOOK without a verdict"
[ $FAIL -eq 0 ]
