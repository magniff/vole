#!/bin/sh
# The gate's unsafe-audit row (0.25.3): every unsafe site of the compiler
# (compiler/src) and of std, as `volec query unsafe` lists them, against
# docs/unsafe-baseline.md. It fails when the unjustified sites (without
# `// UNSAFE:` and `// SAFETY:` right above them) of either rise above the
# baseline's count. Fewer is fine: a note says to lower the baseline
# (-u), which 0.25.4's removal of unsafe does as it goes.
#
# std's count is the host's (std's system file is sys/macos.vl or
# sys/linux.vl, the target's): the gate runs this row on macOS.
#
# usage: tests/unsafe_audit.sh [-c COMPILER] [-u]
#   -c COMPILER   the volec to ask (default: target/volec)
#   -u            write docs/unsafe-baseline.md from the counts now
set -u
LC_ALL=C
export LC_ALL
ROOT=$(cd "$(dirname "$0")/.." && pwd)
C="$ROOT/target/volec"
UPDATE=0
while [ $# -gt 0 ]; do
    case "$1" in
        -c) [ $# -ge 2 ] || exit 2; C=$2; shift ;;
        -u) UPDATE=1 ;;
        *) echo "usage: tests/unsafe_audit.sh [-c COMPILER] [-u]" >&2; exit 2 ;;
    esac
    shift
done
case "$C" in /*) ;; *) C="$(pwd)/$C" ;; esac
[ -x "$C" ] || { echo "unsafe-audit: no compiler at $C"; exit 2; }
cd "$ROOT" || exit 2
BASELINE=docs/unsafe-baseline.md
SRC_CMD="volec query unsafe --summary --no-std"
STD_CMD="volec query unsafe --summary std"

# shellcheck disable=SC2086
src=$("$C" ${SRC_CMD#volec } 2>&1) || { echo "unsafe-audit: $SRC_CMD failed:"; echo "$src" | tail -5; exit 1; }
# shellcheck disable=SC2086
std=$("$C" ${STD_CMD#volec } 2>&1) || { echo "unsafe-audit: $STD_CMD failed:"; echo "$std" | tail -5; exit 1; }
unjustified() { printf '%s\n' "$1" | sed -n 's/^sites: .*; unjustified: \([0-9]*\);.*$/\1/p' | head -1; }
n_src=$(unjustified "$src")
n_std=$(unjustified "$std")
[ -n "$n_src" ] && [ -n "$n_std" ] || { echo "unsafe-audit: no counts in the summaries"; printf '%s\n' "$src" | head -3; exit 1; }

if [ $UPDATE -eq 1 ]; then
    {
        echo "# The unsafe baseline"
        echo
        echo "Every unsafe site (an \`unsafe { }\` block, an \`unsafe fn\`, an \`extern\` block)"
        echo "of the compiler and of std, made by \`tests/unsafe_audit.sh -u\` from"
        echo
        echo "    $SRC_CMD     # compiler/src (the tree's root)"
        echo "    $STD_CMD          # std"
        echo
        echo "on $(uname -sm), $(git rev-parse --short HEAD 2>/dev/null || echo '?'). The gate's unsafe-audit row"
        echo "(bootstrap/gate.sh, tests/unsafe_audit.sh) fails when either count of"
        echo "unjustified sites (without \`// UNSAFE:\` and \`// SAFETY:\` right above them,"
        echo "AGENTS.md) rises above its line below; a lower count asks for this file"
        echo "to be made again. The classes and the comments' rule: \`volec query unsafe"
        echo "--help\`, docs/query.md; \`unneeded\`: unsafe blocks with nothing unsafe"
        echo "inside (statics are safe), removable as they are."
        echo
        echo "baseline compiler/src unjustified: $n_src"
        echo "baseline std unjustified: $n_std"
        echo
        echo "## compiler/src"
        echo
        echo '```'
        printf '%s\n' "$src"
        echo '```'
        echo
        echo "## std"
        echo
        echo '```'
        printf '%s\n' "$std"
        echo '```'
    } >"$BASELINE"
    echo "unsafe-audit: wrote $BASELINE (compiler/src $n_src unjustified, std $n_std)"
    exit 0
fi

[ -f "$BASELINE" ] || { echo "unsafe-audit: no $BASELINE (tests/unsafe_audit.sh -u makes it)"; exit 1; }
b_src=$(sed -n 's/^baseline compiler\/src unjustified: \([0-9]*\)$/\1/p' "$BASELINE")
b_std=$(sed -n 's/^baseline std unjustified: \([0-9]*\)$/\1/p' "$BASELINE")
[ -n "$b_src" ] && [ -n "$b_std" ] || { echo "unsafe-audit: $BASELINE has no baseline lines"; exit 1; }
status=0
note=""
if [ "$n_src" -gt "$b_src" ]; then
    status=1
    echo "compiler/src: $n_src unjustified unsafe sites, the baseline $b_src: the new ones need // UNSAFE: and // SAFETY: (try: volec query unsafe --no-std --unjustified)"
fi
if [ "$n_std" -gt "$b_std" ]; then
    status=1
    echo "std: $n_std unjustified unsafe sites, the baseline $b_std (try: volec query unsafe std --unjustified)"
fi
if [ $status -eq 0 ] && { [ "$n_src" -lt "$b_src" ] || [ "$n_std" -lt "$b_std" ]; }; then
    note="; fewer than the baseline: tests/unsafe_audit.sh -u lowers it"
fi
echo "unsafe-audit: compiler/src $n_src unjustified (baseline $b_src), std $n_std (baseline $b_std)$note"
exit $status
