#!/bin/sh
# (0.25.2) Whether the machine is loaded now: the 1-minute load average
# above the number of CPUs (parallel agents, the gate's runners). Prints
# `load L on N CPUs`; exits 0 when loaded, 1 when not.
# $VOLE_TEST_LOAD stands for the load average (the runner's self-test).
# Used by tests/watchdog.sh (time limits) and by the runners whose checks
# have time budgets (tests/voltty-render, tests/window): over its budget
# on a loaded machine a check is a SKIP with this line, on an idle one a
# FAIL.
#
# The CPUs: macOS's hw.ncpu; on Linux the processors online, or fewer
# when the cgroup's CPU quota allows fewer (a container's --cpus, as the
# gate's linux-aarch64 row runs). The load: macOS's vm.loadavg, Linux's
# /proc/loadavg (in a container, the virtual machine's, not the host's).

LC_ALL=C
export LC_ALL

n=$(sysctl -n hw.ncpu 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 1)
case "$n" in ''|*[!0-9]*|0) n=1 ;; esac
# the cgroup's quota: v2's cpu.max (`QUOTA PERIOD`, or `max PERIOD`), v1's
# cpu.cfs_quota_us and cpu.cfs_period_us (-1: none); rounded up
q=""
if [ -r /sys/fs/cgroup/cpu.max ]; then
    q=$(awk '$1 != "max" && $2 > 0 { print int(($1 + $2 - 1) / $2) }' /sys/fs/cgroup/cpu.max 2>/dev/null)
elif [ -r /sys/fs/cgroup/cpu/cpu.cfs_quota_us ] && [ -r /sys/fs/cgroup/cpu/cpu.cfs_period_us ]; then
    q=$(awk -v p="$(cat /sys/fs/cgroup/cpu/cpu.cfs_period_us)" '$1 > 0 && p > 0 { print int(($1 + p - 1) / p) }' \
        /sys/fs/cgroup/cpu/cpu.cfs_quota_us 2>/dev/null)
fi
case "$q" in ''|*[!0-9]*|0) ;; *) [ "$q" -lt "$n" ] && n=$q ;; esac
l=${VOLE_TEST_LOAD:-}
if [ -z "$l" ]; then
    l=$(sysctl -n vm.loadavg 2>/dev/null | tr -d '{}' | awk '{ print $1 }')
    [ -n "$l" ] || l=$(cut -d' ' -f1 /proc/loadavg 2>/dev/null)
fi
case "$l" in ''|*[!0-9.]*) l=0 ;; esac
echo "load $l on $n CPUs"
awk -v l="$l" -v n="$n" 'BEGIN { exit !(l + 0 > n + 0) }'
