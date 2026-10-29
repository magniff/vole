#!/bin/sh
# (0.25.3) A std change breaks no transcript that is not about std: the
# query, refactor and walkthrough runners compare std's positions and
# counts normalized (tests/stdpos.awk), and the transcripts with a line
# `## exact-std` (a README: `<!-- exact-std -->`) exactly. POSIX sh and
# awk only.
#
# usage: tests/stdpos/run.sh [-c COMPILER] [--real]
#
#   -c COMPILER   the volec binary (default: target/volec)
#   --real        also the change itself: in a copy of the tree, a line
#                 added at the top of compiler/std/gpu/mod.vl and one in
#                 std.vl's first comment (every position after it moves),
#                 std embedded again (compiler/std/embed.sh) and the
#                 compiler rebuilt (by COMPILER), whose runners then must
#                 pass and fail as below (a transcript whose program has
#                 its own compiler/std, tests/refactor/stdedit, is not
#                 moved by it: it must pass), and the three suites whole:
#                 nothing else of them may fail (a few minutes)
#
# The check: every transcript holding std's numbers is run with
# VOLE_STD_SHIFT=1, which moves the numbers in the transcript (lines by
# 7, columns by 3, counts by 7), as a std change would move them in the
# compiler's output. Each must still pass, but an exact-std one, which
# must fail (it compares std's positions: they moved). And the
# normalizer itself: shifting a transcript changes nothing it compares.
#
# Prints `pass NAME` or `FAIL NAME` (and why) for each; exits 1 if one
# failed.

set -u
LC_ALL=C
export LC_ALL

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
COMPILER="$ROOT/target/volec"
REAL=0
while [ $# -gt 0 ]; do
    case "$1" in
        -c) [ $# -ge 2 ] || exit 2; COMPILER=$2; shift 2 ;;
        --real) REAL=1; shift ;;
        *) echo "usage: tests/stdpos/run.sh [-c COMPILER] [--real]" >&2; exit 2 ;;
    esac
done
case "$COMPILER" in
    /*) ;;
    *) COMPILER="$(pwd)/$COMPILER" ;;
esac
[ -x "$COMPILER" ] || { echo "stdpos/run.sh: no compiler at $COMPILER" >&2; exit 2; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/vole-stdpos.XXXXXX")
WORK=$(cd "$WORK" && pwd -P)
trap 'rm -rf "$WORK"' EXIT
trap 'exit 130' INT TERM
STATUS=0
AWK="$ROOT/tests/stdpos.awk"

# The transcripts of tree $1 with std's numbers: `KIND NAME exact|norm`
# (KIND query, refactor or walkthrough).
transcripts() {
    for f in "$1"/tests/query/*.q "$1"/tests/refactor/*.t "$1"/examples/*/*/README.md; do
        [ -f "$f" ] || continue
        [ "$(awk -v mode=has -f "$AWK" "$f")" != 0 ] || continue
        case "$f" in
            *.q) kind=query; name=$(basename "$f" .q) ;;
            *.t) kind=refactor; name=$(basename "$f" .t) ;;
            *) grep -q '^```console' "$f" || continue
               kind=walkthrough; name=$(basename "$(dirname "$f")") ;;
        esac
        if grep -q -e '^## exact-std' -e '^<!-- exact-std -->' "$f"; then
            echo "$kind $name exact"
        else
            echo "$kind $name norm"
        fi
    done
}

# The normalizer: a shifted transcript compares the same, but an exact one.
transcripts "$ROOT" >"$WORK/list"
bad=
n=0
while read -r kind name how; do
    case $kind in
        query) f="$ROOT/tests/query/$name.q" ;;
        refactor) f="$ROOT/tests/refactor/$name.t" ;;
        *) f=$(ls "$ROOT"/examples/*/"$name"/README.md | head -1) ;;
    esac
    awk -f "$AWK" "$f" >"$WORK/a"
    awk -v mode=shift -f "$AWK" "$f" | awk -f "$AWK" >"$WORK/b"
    cmp -s "$WORK/a" "$WORK/b" || bad="$bad $name"
    awk -v mode=shift -f "$AWK" "$f" | cmp -s - "$f" && bad="$bad $name(not-shifted)"
    n=$((n + 1))
done <"$WORK/list"
if [ "$n" -ge 10 ] && [ -z "$bad" ]; then
    echo "pass stdpos_normalizer ($n transcripts)"
else
    echo "FAIL stdpos_normalizer: $n transcripts; differ shifted:$bad"
    STATUS=1
fi
if grep -q ' exact$' "$WORK/list"; then
    echo "pass stdpos_exact_listed ($(grep -c ' exact$' "$WORK/list") exact-std)"
else
    echo "FAIL stdpos_exact_listed: no exact-std transcript holds std's numbers"
    STATUS=1
fi

# Runs the runners of tree $1 with compiler $2 (env: $3) on the
# transcripts of the list; checks each norm passes and each exact fails.
# $4: the checks' prefix.
run_runners() {
    for kind in query refactor walkthrough; do
        names=$(awk -v k=$kind '$1 == k { print $2 }' "$WORK/list" | tr '\n' ' ')
        [ -n "$names" ] || continue
        # (--real: the whole suites, their other checks too)
        [ "$4" = moved ] && names=
        # shellcheck disable=SC2086
        env $3 sh "$1/tests/$kind/run.sh" -c "$2" $names >"$WORK/$4-$kind.out" 2>&1
    done
    while read -r kind name how; do
        out="$WORK/$4-$kind.out"
        if [ "$how" = exact ] && [ "$4" = moved ] && [ -d "$1/tests/$kind/$name/compiler/std" ]; then
            if grep -q "^pass $name\\( \\|\$\\)" "$out" && ! grep -q "^FAIL $name\\( \\|:\\)" "$out"; then
                echo "pass $4_$name (exact-std, its own std: unmoved, passes)"
            else
                echo "FAIL $4_$name: exact-std with its own std, which did not move, but it failed"
                STATUS=1
            fi
        elif [ "$how" = exact ]; then
            if grep -q "^FAIL $name\\( \\|:\\)" "$out"; then
                echo "pass $4_$name (exact-std: fails, as it should)"
            else
                echo "FAIL $4_$name: exact-std, and std's numbers moved, but it did not fail"
                STATUS=1
            fi
        elif grep -q "^pass $name\\( \\|\$\\)" "$out" && ! grep -q "^FAIL $name\\( \\|:\\)" "$out"; then
            echo "pass $4_$name"
        else
            echo "FAIL $4_$name: std's numbers moved, and the $kind transcript failed:"
            awk -v n="$name" '$2 == n || $2 == n ":" { p = ($1 == "FAIL") } p' "$out" | head -20 | sed 's/^/    /'
            STATUS=1
        fi
    done <"$WORK/list"
}

run_runners "$ROOT" "$COMPILER" "VOLE_STD_SHIFT=1" shifted

if [ "$REAL" = 1 ]; then
    # A copy of the tree (its files, as they are now, but the ignored), a line
    # added at the top of std::gpu, std embedded again, the compiler
    # rebuilt by COMPILER.
    T="$WORK/tree"
    mkdir -p "$T"
    (cd "$ROOT" && git ls-files -z -c -o --exclude-standard | tar --null -T - -cf - 2>/dev/null) | tar -xf - -C "$T"
    (cd "$T" && git init -q . && git add -A >/dev/null 2>&1)
    { echo '// (tests/stdpos/run.sh: a line that moves std'"'"'s positions)'; cat "$ROOT/compiler/std/gpu/mod.vl"; } >"$T/compiler/std/gpu/mod.vl"
    awk 'NR == 5 { print "// (tests/stdpos/run.sh: a line that moves all of std'"'"'s positions)" } { print }' \
        "$ROOT/compiler/std/std.vl" >"$T/compiler/std/std.vl"
    if ! sh "$T/compiler/std/embed.sh" >"$WORK/embed.out" 2>&1; then
        echo "FAIL real_build: embed.sh: $(head -3 "$WORK/embed.out")"
        exit 1
    fi
    if ! (cd "$T" && "$COMPILER" compiler/src/main.vl -o "$WORK/volec-moved") >"$WORK/build.out" 2>&1; then
        echo "FAIL real_build: $(head -5 "$WORK/build.out")"
        exit 1
    fi
    transcripts "$T" >"$WORK/list"
    run_runners "$T" "$WORK/volec-moved" "VOLE_STD_SHIFT=0" moved
    # and nothing else of the three suites failed
    others=$(cat "$WORK"/moved-*.out | awk '$1 == "FAIL" { n = $2; sub(/:$/, "", n); print n }' | sort -u | while read -r n; do
        grep -q " $n exact\$" "$WORK/list" || printf ' %s' "$n"
    done)
    if [ -z "$others" ]; then
        echo "pass moved_suites (query, refactor, walkthrough: $(cat "$WORK"/moved-*.out | grep -c '^pass') passed)"
    else
        echo "FAIL moved_suites: failed after std moved:$others"
        STATUS=1
    fi
fi
exit $STATUS
