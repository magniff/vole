#!/bin/sh
# (0.30.2) The red team's cases that are shell tests: what tests/run,
# the transcripts and the LSP transcripts cannot drive (a server fed a
# frame no client sends, a source file's time set back). Each is
# tests/redteam/rt_NNN_*.sh, run as `sh FILE VOLEC`: exit 0 is a pass. A
# `# XFAIL: RT-N: ...` line in its first three lines makes a failure
# expected (xfail) and a pass an error (XPASS: remove the line), as
# tests/run.sh's XFAIL does. Run by the gate's row redteam-cases.
#
# usage: tests/redteam/run.sh [-c VOLEC]
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
C="$ROOT/target/volec"
[ "${1:-}" = -c ] && { C=$2; shift 2; }
case "$C" in /*) ;; *) C="$(pwd)/$C" ;; esac
pass=0
xfail=0
fail=0
for t in "$ROOT"/tests/redteam/rt_*.sh; do
    [ -f "$t" ] || continue
    n=$(basename "$t" .sh)
    x=$(head -3 "$t" | sed -n 's/^# XFAIL: //p' | head -1)
    out=$(sh "$t" "$C" 2>&1)
    rc=$?
    if [ $rc -eq 0 ] && [ -z "$x" ]; then
        pass=$((pass + 1))
    elif [ $rc -ne 0 ] && [ -n "$x" ]; then
        xfail=$((xfail + 1))
        echo "xfail $n: $x"
    elif [ $rc -eq 0 ]; then
        fail=$((fail + 1))
        echo "XPASS $n: passes but is marked XFAIL ($x); remove the line"
    else
        fail=$((fail + 1))
        echo "FAIL $n (exit $rc):"
        echo "$out" | tail -5 | sed 's/^/    /'
    fi
done
echo "redteam shell cases: $pass passed, $xfail xfail, $fail failed"
[ $fail -eq 0 ]
