#!/bin/sh
# (0.30.2) Every red-team finding has a case in the tree, open (XFAIL)
# or fixed: a finding that only lives in the red team's notes is seen by
# no count, no branch and no release note (in 0.30.1, 31 verified
# findings were never committed). The gate's row redteam-cases.
#
# usage: tests/redteam_cases.sh [-d DIR] [--self-test]
#   -d DIR       the red team's notes: every FINDINGS.md under DIR (default:
#                .claude/briefs/redteam beside the main checkout's .git);
#                DIR/no-case.txt lists the findings excused, `TAG reason`
#   --self-test  only the canary: a finding planted without a case must be
#                reported, and the same finding with a case must not
#
# A finding is a `## TAG` heading, TAG one of RT-N, RT-CG-N, RT-STD-N,
# RT-TL-N, RT-M2-N, RT-C301-N, RT-B301-N (a letter may follow N). Its case
# is a file or directory under tests/ whose name begins with the tag's
# prefix (RT-46: rt_046, RT-TL-1: rt_tl_001, RT-C301-8: rt_c301_008), or
# a file under tests/ that names the tag (its XFAIL line, or the header of
# a fixed case). A heading of a round's own number (`## R302B-4:`), not
# yet an RT number, has no case by definition. Exit 0 when every finding has one, 1 when one has not,
# 77 when there are no notes (the row skips, saying so).
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DIR=""
SELF=0
while [ $# -gt 0 ]; do
    case "$1" in
        -d) DIR=$2; shift 2 ;;
        --self-test) SELF=1; shift ;;
        *) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
    esac
done

# audit <notes dir> <tests dir>: prints `no case: TAG (FILE)` lines and the
# summary; returns the number of findings without a case (at most 255)
audit() {
    names=$(mktemp)
    find "$2" \( -type f -o -type d \) | sed 's|.*/||' >"$names"
    total=0
    missing=0
    for f in $(find "$1" -name FINDINGS.md | sort); do
        for tag in $(grep -oE '^## RT-[A-Z0-9-]*[0-9]+[a-z]?' "$f" | sed 's/^## //' | sort -u); do
            total=$((total + 1))
            grep -q "^$tag " "$1/no-case.txt" 2>/dev/null && continue
            series=$(echo "$tag" | sed -E 's/^RT-//; s/-?[0-9]+[a-z]?$//' | tr 'A-Z' 'a-z')
            num=$(echo "$tag" | sed -E 's/.*-([0-9]+)[a-z]?$/\1/')
            if [ -n "$series" ]; then pre=$(printf 'rt_%s_%03d' "$series" "$num"); else pre=$(printf 'rt_%03d' "$num"); fi
            grep -qE "^${pre}([_a-z.]|$)" "$names" && continue
            grep -rqE "(^|[^A-Z0-9-])$tag([^0-9a-z]|$)" "$2" 2>/dev/null && continue
            echo "no case: $tag (${f#$1/})"
            missing=$((missing + 1))
        done
        # a finding not yet given its RT number (a round's own R302B-N): it
        # has no case yet, by definition
        for tag in $(grep -oE '^## R[0-9][0-9A-Z]*-[0-9]+[a-z]?:' "$f" | sed 's/^## //; s/:$//' | sort -u); do
            total=$((total + 1))
            echo "no case: $tag, not yet given its RT number (${f#$1/})"
            missing=$((missing + 1))
        done
    done
    rm -f "$names"
    echo "redteam-cases: $total findings, $missing without a case"
    [ $missing -gt 255 ] && missing=255
    return $missing
}

# The canary: RT-9999 planted in notes of its own, first with no case (it
# must be reported), then with one (it must not).
canary() {
    t=$(mktemp -d)
    mkdir -p "$t/notes" "$t/tests/run"
    printf '## RT-9999: a planted finding\n' >"$t/notes/FINDINGS.md"
    out1=$(audit "$t/notes" "$t/tests")
    r1=$?
    printf '// XFAIL: RT-9999: planted\n' >"$t/tests/run/rt_9999_planted.vl"
    out2=$(audit "$t/notes" "$t/tests")
    r2=$?
    rm -rf "$t"
    if [ $r1 -eq 1 ] && echo "$out1" | grep -q '^no case: RT-9999' && [ $r2 -eq 0 ]; then
        echo "redteam-cases: the canary caught (a planted finding without a case reported, with one not)"
        return 0
    fi
    echo "redteam-cases: FAIL: the canary was not caught (without a case: exit $r1; with one: exit $r2)"
    return 1
}

canary || exit 1
[ $SELF -eq 1 ] && exit 0
if [ -z "$DIR" ]; then
    common=$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
    [ -n "$common" ] && DIR="$(dirname "$common")/.claude/briefs/redteam"
fi
if [ -z "$DIR" ] || [ ! -d "$DIR" ]; then
    echo "redteam-cases: SKIP: no red team notes here (${DIR:-no git checkout}): nothing to hold the tree to"
    exit 77
fi
audit "$DIR" "$ROOT/tests"
[ $? -eq 0 ] || { echo "redteam-cases: FAIL: commit each finding above as a case (XFAIL: TAG), or excuse it in no-case.txt with its reason"; exit 1; }
exit 0
