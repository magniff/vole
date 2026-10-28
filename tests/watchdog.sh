#!/bin/sh
# (0.25.2) A load-aware time limit for a test's program: kills process PID
# (kill -9) once it has run SECONDS of wall time, unless the machine is
# loaded then. While the 1-minute load average is above the number of
# CPUs (parallel agents, the gate's runners), a program is slow, not hung:
# the limit is extended by SECONDS again, up to $VOLE_WATCHDOG_EXTEND times
# (default 8). A genuine hang is still killed: after SECONDS on an idle
# machine, after (1 + extensions) x SECONDS on a loaded one.
#
# usage: tests/watchdog.sh SECONDS PID [FILE]
#
# When it kills, it writes one line to FILE saying why (the time, the
# limit, the extensions and the load), for the runner's failure message;
# it exits by itself as soon as PID is gone. Used by tests/run.sh and the
# runners of tests/book, tests/guide and tests/fuzz.
# $VOLE_WATCHDOG_LOAD stands for the load average (tests/runner/run.sh
# checks the extensions with it).

LC_ALL=C
export LC_ALL

[ $# -ge 2 ] || { echo "usage: tests/watchdog.sh SECONDS PID [FILE]" >&2; exit 2; }
LIMIT=$1
PID=$2
FILE=${3:-}
EXTEND=${VOLE_WATCHDOG_EXTEND:-8}

cpus() {
    n=$(sysctl -n hw.ncpu 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)
    case "$n" in ''|*[!0-9]*) echo 1 ;; *) echo "$n" ;; esac
}

load1() {
    if [ -n "${VOLE_WATCHDOG_LOAD:-}" ]; then
        echo "$VOLE_WATCHDOG_LOAD"
        return
    fi
    l=$(sysctl -n vm.loadavg 2>/dev/null | tr -d '{}' | awk '{ print $1 }')
    [ -n "$l" ] || l=$(cut -d' ' -f1 /proc/loadavg 2>/dev/null)
    echo "${l:-0}"
}

waited=0
deadline=$LIMIT
ext=0
while kill -0 "$PID" 2>/dev/null; do
    if [ "$waited" -ge "$deadline" ]; then
        load=$(load1)
        ncpu=$(cpus)
        if [ "$ext" -lt "$EXTEND" ] && awk -v l="$load" -v n="$ncpu" 'BEGIN { exit !(l + 0 > n + 0) }'; then
            ext=$((ext + 1))
            deadline=$((deadline + LIMIT))
            continue
        fi
        kill -9 "$PID" 2>/dev/null
        if [ -n "$FILE" ]; then
            if [ "$ext" -gt 0 ]; then
                times=times
                [ "$ext" -eq 1 ] && times=time
                echo "killed after $waited s: the limit, $LIMIT s, extended $ext $times while the load average was above the $ncpu CPUs (now $load): a hang, or a machine loaded beyond that" >"$FILE"
            else
                echo "killed after $waited s, the limit (load average $load on $ncpu CPUs): a hang, or too slow" >"$FILE"
            fi
        fi
        exit 0
    fi
    sleep 1
    waited=$((waited + 1))
done
exit 0
