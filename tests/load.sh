#!/bin/sh
# (0.25.2) Whether the machine is loaded now: the 1-minute load average
# above the number of CPUs (parallel agents, the gate's runners). Prints
# `load L on N CPUs`; exits 0 when loaded, 1 when not.
# $VOLE_TEST_LOAD stands for the load average (the runner's self-test).
# Used by tests/watchdog.sh (time limits) and by the runners whose checks
# have time budgets (tests/voltty-render, tests/window): over its budget
# on a loaded machine a check is a SKIP with this line, on an idle one a
# FAIL.

LC_ALL=C
export LC_ALL

n=$(sysctl -n hw.ncpu 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)
case "$n" in ''|*[!0-9]*) n=1 ;; esac
l=${VOLE_TEST_LOAD:-}
if [ -z "$l" ]; then
    l=$(sysctl -n vm.loadavg 2>/dev/null | tr -d '{}' | awk '{ print $1 }')
    [ -n "$l" ] || l=$(cut -d' ' -f1 /proc/loadavg 2>/dev/null)
fi
l=${l:-0}
echo "load $l on $n CPUs"
awk -v l="$l" -v n="$n" 'BEGIN { exit !(l + 0 > n + 0) }'
