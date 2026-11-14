#!/bin/sh
# (0.30) Removes the directories a failed `bootstrap/gate.sh --self-test`
# left in $TMPDIR (`gate: self-test: FAIL (outputs in DIR)` keeps DIR for
# a look; 0.29's work on the gate left 247 of them), and nothing else: a
# directory is removed only when all of this holds
#
#   - its name is the self-test's: vole-gate-selftest.XXXXXX (mktemp's
#     six characters), directly in the temporary directory;
#   - it is a directory, not a link, and this user's;
#   - it was last changed more than a day ago;
#   - no gate of it still runs: the pid of its lock (gate.lock/owner),
#     when it has one, is of no live process;
#   - it holds only what the self-test writes there: gate.lock, runs,
#     stubN, bin and *.out (or nothing).
#
# Anything else is left, and one that looks like the self-test's but
# fails a condition is named with the reason.
#
# usage: bootstrap/selftest-prune.sh [-n] [DIR]
#
#   -n     say what would be removed, remove nothing
#   DIR    the temporary directory (default: $TMPDIR, or /tmp)
#
# Prints `selftest-prune: removed N of M (K left: ...)`. Not yet called
# by gate.sh: its self-test is to run it when it starts.
set -u
LC_ALL=C
export LC_ALL
DRY=0
DIR=""
while [ $# -gt 0 ]; do
    case "$1" in
        -n) DRY=1; shift ;;
        -*) sed -n '2,/^set -u/p' "$0" | sed '$d; s/^# \{0,1\}//' >&2; exit 2 ;;
        *) DIR=$1; shift ;;
    esac
done
[ -n "$DIR" ] || DIR=${TMPDIR:-/tmp}
DIR=${DIR%/}
[ -d "$DIR" ] || { echo "selftest-prune: no directory $DIR" >&2; exit 2; }

# Why directory $1 is not to be removed; nothing when it is.
keep_reason() {
    [ -h "$1" ] && { echo "a link"; return; }
    [ -d "$1" ] || { echo "not a directory"; return; }
    [ -O "$1" ] || { echo "another user's"; return; }
    # (-mtime +1: more than a day by BSD find, which rounds a part of a
    # day up, two days and more by GNU find, which rounds it down)
    [ -n "$(find "$1" -maxdepth 0 -mtime +1 2>/dev/null)" ] || { echo "changed within a day"; return; }
    if [ -f "$1/gate.lock/owner" ]; then
        pid=$(sed -n 's/^pid=//p' "$1/gate.lock/owner" | head -1)
        case "$pid" in
            ''|*[!0-9]*) ;;
            *) kill -0 "$pid" 2>/dev/null && { echo "its gate (pid $pid) runs"; return; } ;;
        esac
    fi
    for e in "$1"/* "$1"/.[!.]* "$1"/..?*; do
        [ -e "$e" ] || [ -h "$e" ] || continue
        case "${e##*/}" in
            gate.lock|runs|bin|stub[0-9]|stub[0-9][0-9]|*.out) ;;
            *) echo "holds ${e##*/}, which the self-test does not write"; return ;;
        esac
    done
}

found=0
removed=0
left=""
for d in "$DIR"/vole-gate-selftest.??????; do
    # (the pattern itself, when nothing matches; a name with more in it)
    case "${d##*/}" in
        vole-gate-selftest.[A-Za-z0-9][A-Za-z0-9][A-Za-z0-9][A-Za-z0-9][A-Za-z0-9][A-Za-z0-9]) ;;
        *) continue ;;
    esac
    [ -e "$d" ] || [ -h "$d" ] || continue
    found=$((found + 1))
    why=$(keep_reason "$d")
    if [ -n "$why" ]; then
        left="$left${left:+; }${d##*/}: $why"
        continue
    fi
    if [ $DRY -eq 1 ]; then
        echo "would remove $d"
    else
        rm -rf -- "$d"
    fi
    removed=$((removed + 1))
done
echo "selftest-prune: $([ $DRY -eq 1 ] && echo "would remove" || echo removed) $removed of $found in $DIR${left:+ (left: $left)}"
