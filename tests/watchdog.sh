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
# The load and the CPUs are tests/load.sh's (on Linux, a container's CPU
# quota). $VOLE_WATCHDOG_LOAD stands for the load average
# (tests/runner/run.sh checks the extensions with it).

LC_ALL=C
export LC_ALL

[ $# -ge 2 ] || { echo "usage: tests/watchdog.sh SECONDS PID [FILE]" >&2; exit 2; }
LIMIT=$1
PID=$2
FILE=${3:-}
EXTEND=${VOLE_WATCHDOG_EXTEND:-8}

LOAD_SH="$(dirname "$0")/load.sh"

waited=0
deadline=$LIMIT
ext=0
while kill -0 "$PID" 2>/dev/null; do
    if [ "$waited" -ge "$deadline" ]; then
        # tests/load.sh: `load L on N CPUs`, and whether L is above N
        line=$(VOLE_TEST_LOAD=${VOLE_WATCHDOG_LOAD:-${VOLE_TEST_LOAD:-}} sh "$LOAD_SH")
        loaded=$?
        load=$(echo "$line" | awk '{ print $2 }')
        ncpu=$(echo "$line" | awk '{ print $4 }')
        if [ "$ext" -lt "$EXTEND" ] && [ "$loaded" -eq 0 ]; then
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
