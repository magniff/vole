#!/bin/sh
# The gate's unsafe-audit row (0.25.3) and the audit of tools/premerge.sh's
# unsafe row: every unsafe site of the compiler (compiler/src) and of std,
# as `volec query unsafe` lists them. (0.29) The rule is none, not a
# count that may only fall: it fails on
#   - any site of compiler/src or of std without `// UNSAFE:` and
#     `// SAFETY:` right above it (unjustified), and
#   - any unsafe block of compiler/src with nothing unsafe inside
#     (unneeded: `volec fix --only unneeded-unsafe` takes it away),
# and names each one, FILE:LINE (compiler/src's as `volec check
# --deny=unsafe` reports them, errors with their positions, when the
# compiler asked knows the option). docs/unsafe-baseline.md records the
# counts by class, module and file at the last `-u`; its three baseline
# lines are 0 and `-u` writes no other number.
#
# std's unneeded blocks are printed and not judged: `query unsafe` says
# `none (unneeded)` of a block in a generic function of std that the
# program asked about (the compiler) never instantiates, and those blocks
# hold what needs them (a C call, ptr::write); the count changes with the
# program. A block of std is unneeded when it is under every program.
#
# std's count is the host's (std's system file is sys/macos.vl or
# sys/linux.vl, the target's): the gate runs this row on macOS.
#
# usage: tests/unsafe_audit.sh [-c COMPILER] [-u]
#   -c COMPILER   the volec to ask (default: target/volec)
#   -u            write docs/unsafe-baseline.md from the counts now (all
#                 three must be 0)
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
unneeded() { printf '%s\n' "$1" | sed -n 's/^sites: .*; unneeded: \([0-9]*\)$/\1/p' | head -1; }
sites() { printf '%s\n' "$1" | sed -n 's/^sites: \([0-9]*\) .*$/\1/p' | head -1; }
n_src=$(unjustified "$src")
n_std=$(unjustified "$std")
u_src=$(unneeded "$src")
u_std=$(unneeded "$std")
[ -n "$n_src" ] && [ -n "$n_std" ] && [ -n "$u_src" ] && [ -n "$u_std" ] || { echo "unsafe-audit: no counts in the summaries"; printf '%s\n' "$src" | head -3; exit 1; }

# The sites that break the rule, FILE:LINE each: compiler/src's by `check
# --deny=unsafe` (0.29: errors with their positions), or, by a compiler
# before it, from the listing; std's from the listing.
TAB=$(printf '\t')
list_src() {
    denied=$("$C" check --deny=unsafe compiler/src/main.vl 2>&1)
    if printf '%s\n' "$denied" | grep -q 'error\[unsafe\.'; then
        printf '%s\n' "$denied" | grep -E 'error\[unsafe\.' | sed 's/ | help: .*$//; s/^/  /'
    else
        # (a compiler before --deny, or errors of another kind first)
        "$C" query unsafe --no-std --all 2>/dev/null | awk -F "$TAB" 'NF >= 6 && ($5 != "justified" || $6 == "none (unneeded)") { print "  " $1 ": " $2 " in " $3 ": " $5 ", " $6 }'
    fi
}
list_std() {
    "$C" query unsafe std --all 2>/dev/null | awk -F "$TAB" 'NF >= 6 && $5 != "justified" { print "  " $1 ": " $2 " in " $3 ": " $5 }'
}

if [ $UPDATE -eq 1 ]; then
    if [ "$n_src" -ne 0 ] || [ "$u_src" -ne 0 ] || [ "$n_std" -ne 0 ]; then
        echo "unsafe-audit: not written: the baseline is 0 (compiler/src $n_src unjustified, $u_src unneeded; std $n_std unjustified): justify each site or take it away"
        list_src
        list_std
        exit 1
    fi
    {
        echo "# The unsafe baseline"
        echo
        echo "Every unsafe site (an \`unsafe { }\` block, an \`unsafe fn\`, an \`extern\` block)"
        echo "of the compiler and of std, made by \`tests/unsafe_audit.sh -u\` from"
        echo
        echo "    $SRC_CMD     # compiler/src (the tree's root)"
        echo "    $STD_CMD          # std"
        echo
        echo "on $(uname -sm), $(git rev-parse --short HEAD 2>/dev/null || echo '?'). The rule (0.29) is none: the gate's"
        echo "unsafe-audit row and tools/premerge.sh's unsafe row (tests/unsafe_audit.sh)"
        echo "fail on any site of compiler/src or std without \`// UNSAFE:\` and"
        echo "\`// SAFETY:\` right above it (unjustified, AGENTS.md) and on any unsafe"
        echo "block of compiler/src with nothing unsafe inside (unneeded), and name"
        echo "each one; \`volec check --deny=unsafe\` reports them as errors where they"
        echo "are. The three lines below are 0 and stay 0; the counts by class, module"
        echo "and file are the record of what is left. The classes and the comments'"
        echo "rule: \`volec query unsafe --help\`, docs/query.md. std's unneeded count"
        echo "is not judged (tests/unsafe_audit.sh says why)."
        echo
        echo "baseline compiler/src unjustified: $n_src"
        echo "baseline compiler/src unneeded: $u_src"
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
    echo "unsafe-audit: wrote $BASELINE (compiler/src $(sites "$src") sites, std $(sites "$std"); none unjustified, none of compiler/src unneeded)"
    exit 0
fi

[ -f "$BASELINE" ] || { echo "unsafe-audit: no $BASELINE (tests/unsafe_audit.sh -u makes it)"; exit 1; }
status=0
# (the file's own lines: 0, whoever edits it)
for key in "compiler\/src unjustified" "compiler\/src unneeded" "std unjustified"; do
    b=$(sed -n "s/^baseline $key: \\([0-9]*\\)\$/\\1/p" "$BASELINE")
    if [ "$b" != 0 ]; then
        status=1
        echo "unsafe-audit: $BASELINE: 'baseline $(printf '%s' "$key" | sed 's/\\//g')' is '${b:-missing}', not 0 (tests/unsafe_audit.sh -u writes the file)"
    fi
done
if [ "$n_src" -ne 0 ] || [ "$u_src" -ne 0 ]; then
    status=1
    echo "compiler/src: $n_src unjustified unsafe sites and $u_src unneeded unsafe blocks; the rule is none: say why above each site (// UNSAFE:, // SAFETY:), take an unneeded block away (volec fix --only unneeded-unsafe):"
    list_src
fi
if [ "$n_std" -ne 0 ]; then
    status=1
    echo "std: $n_std unjustified unsafe sites; the rule is none (volec query unsafe std --unjustified):"
    list_std
fi
echo "unsafe-audit: compiler/src $(sites "$src") sites, $n_src unjustified, $u_src unneeded; std $(sites "$std") sites, $n_std unjustified ($u_std listed unneeded, not judged: generic functions the compiler does not instantiate)"
exit $status
