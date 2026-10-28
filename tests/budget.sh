#!/bin/sh
# (0.25.2) The time budgets a test program missed: its `slow NAME: why`
# lines (in FILE) become `FAIL PREFIXNAME: why` on an idle machine and
# `skip PREFIXNAME: machine loaded (load L on N CPUs): why` on a loaded one
# (tests/load.sh), so a measurement the load made slow is counted and
# listed as skipped, never passed, and a real regression on an idle
# machine still fails. Exits 1 when it printed a FAIL.
#
# usage: tests/budget.sh PREFIX FILE

[ $# -eq 2 ] || { echo "usage: tests/budget.sh PREFIX FILE" >&2; exit 2; }
grep -q '^slow ' "$2" || exit 0
if load=$(sh "$(dirname "$0")/load.sh"); then
    sed -n "s/^slow \([^:]*\): /skip $1\1: machine loaded ($load): /p" "$2"
    exit 0
fi
sed -n "s/^slow /FAIL $1/p" "$2"
exit 1
