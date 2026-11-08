#!/bin/sh
# Gate 3 (0.27.4, docs/design/rust-surface-plan.md §6): the translator on
# the compiler itself. A copy of compiler/src is translated by
# `volec fix --edition rust` (--force: guide/text/mod.vl is generated) and
# checked in the rust edition; N is the errors the check reports, by code.
# Informational: N is printed every point release, and 0.28 starts when it
# is 0. The tree is never translated, only the copy.
#
# (0.28.0) After the flip compiler/src is in the rust edition (its root's
# `// EDITION: rust`), and gate 3 checks it stays a fixed point of the
# translator: `fix --edition rust` on the copy says there is nothing to
# translate (fix.edition_none) and leaves every file as it was, and the
# copy checks in the rust edition with no error (N, as before). A
# translator that rewrites rust-edition source, or a compiler/src the
# rust check refuses, is a failure: `gate3: not a fixed point`, exit 1.
#
# usage: tests/gate3.sh [-c COMPILER] [-k DIR] [-v]
#
#   -c COMPILER   the volec that translates and checks (default:
#                 target/volec, else target/tools/volec)
#   -k DIR        translate into DIR/src (made empty first) and keep it,
#                 with DIR/fix.log and DIR/check.log, for whoever reads the
#                 errors (default: a temporary directory, removed)
#   -v            print the check's errors too
#
# Prints `gate3: N errors (by code: COUNT CODE, ...)`, the largest first,
# last; before it `gate3: borrowck (partial): ...`, the borrow checker's
# errors in the bodies that type-checked (`check --borrowck-partial`:
# borrowck runs only on a program without type errors otherwise, so N
# hides them; DIR/borrowck.log keeps them); after the flip, first
# `gate3: fixed point: ...`.
# (0.27.6) MVS's `static var SRC: [u8]` is translated `static mut SRC:
# &'static [u8]`, which holds: SRC is a view of base's region, which is
# never moved, unmapped or written again where SRC has been given it
# (docs/design/src-buffer.md), and the translator gives a function whose
# every result is static, a part of SRC among them, a `'static` result
# (sig.vl: static_returns). (0.28.0: read through get_src(), its
# accessor, tools/translate/statics.vl.)
#
# Exits 1 only when the translator or the check could not run (a crash,
# no output), or (0.28.0) when the flipped compiler/src is not a fixed
# point; errors left before the flip are the measurement, not a failure.

set -u
LC_ALL=C
export LC_ALL
ROOT=$(cd "$(dirname "$0")/.." && pwd)
COMPILER=""
KEEP=""
VERBOSE=0
while [ $# -gt 0 ]; do
    case "$1" in
        -c) [ $# -ge 2 ] || { echo "gate3: -c needs a compiler" >&2; exit 2; }; COMPILER=$2; shift ;;
        -k) [ $# -ge 2 ] || { echo "gate3: -k needs a directory" >&2; exit 2; }; KEEP=$2; shift ;;
        -v) VERBOSE=1 ;;
        -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "gate3: unknown argument '$1' (see --help)" >&2; exit 2 ;;
    esac
    shift
done
if [ -z "$COMPILER" ]; then
    COMPILER="$ROOT/target/volec"
    [ -x "$COMPILER" ] || COMPILER="$ROOT/target/tools/volec"
fi
case "$COMPILER" in /*) ;; *) COMPILER="$(pwd)/$COMPILER" ;; esac
[ -x "$COMPILER" ] || { echo "gate3: no compiler at $COMPILER" >&2; exit 2; }

if [ -n "$KEEP" ]; then
    mkdir -p "$KEEP" || exit 2
    W=$(cd "$KEEP" && pwd)
    rm -rf "$W/src"
else
    W=$(mktemp -d "${TMPDIR:-/tmp}/gate3.XXXXXX") || exit 2
    trap 'rm -rf "$W"' EXIT INT TERM
fi
cp -R "$ROOT/compiler/src" "$W/src" || exit 2

start=$(date +%s)
# (0.28.0) a flipped compiler/src: the translator must leave it as it is
FLIPPED=0
grep -q '^// EDITION: rust *$' "$W/src/main.vl" && FLIPPED=1
[ $FLIPPED -eq 0 ] || cp -R "$W/src" "$W/before"
# (its exit code says the translation left errors: the check counts them)
(cd "$W" && "$COMPILER" fix --edition rust src/main.vl --force) >"$W/fix.log" 2>&1
fix_rc=$?
FIXED_POINT=ok
if [ $FLIPPED -eq 1 ]; then
    if ! grep -q 'fix.edition_none' "$W/fix.log"; then
        FIXED_POINT="the translator did not say fix.edition_none (exit $fix_rc; fix.log)"
    elif ! diff -r "$W/before" "$W/src" >"$W/fixpoint.diff" 2>&1; then
        FIXED_POINT="the translator changed $(grep -c '^diff\|^Only' "$W/fixpoint.diff") file(s) (fixpoint.diff)"
    fi
    rm -rf "$W/before"
elif ! grep -q '^fixed' "$W/fix.log"; then
    echo "gate3: the translator did not run (exit $fix_rc):"
    tail -5 "$W/fix.log"
    exit 1
fi
(cd "$W" && "$COMPILER" check --edition rust --max-errors=0 src/main.vl) >"$W/check.log" 2>&1
check_rc=$?
secs=$(( $(date +%s) - start ))
# (a check that crashed prints no `ok:` and no error)
if [ $check_rc -ne 0 ] && ! grep -q ': error\[' "$W/check.log"; then
    echo "gate3: the check did not run (exit $check_rc):"
    tail -5 "$W/check.log"
    exit 1
fi
(cd "$W" && "$COMPILER" check --edition rust --max-errors=0 --borrowck-partial src/main.vl) \
    >"$W/borrowck.log" 2>&1
[ $VERBOSE -eq 0 ] || grep ': error\[' "$W/check.log"
if [ $FLIPPED -eq 1 ]; then
    echo "gate3: fixed point: $FIXED_POINT (compiler/src is in the rust edition)"
else
    grep '^fixed' "$W/fix.log" | cut -f1 | sed 's/^/gate3: translator: /'
fi
[ -z "$KEEP" ] || echo "gate3: the translation and its logs: $W"
grep -o ': error\[borrowck[^]]*\]' "$W/borrowck.log" \
    | sed 's/^: error\[borrowck\.//; s/\]$//' | sort | uniq -c | sort -k1,1nr -k2 \
    | awk '{ n += $1; c = $1; $1 = ""; sub(/^ /, ""); by = by sep c " " $0; sep = ", " }
        END { printf "gate3: borrowck (partial): %d errors%s\n", n, (n > 0 ? " (by code: " by ")" : "") }'
grep -o ': error\[[^]]*\]' "$W/check.log" \
    | sed 's/^: error\[//; s/\]$//' | sort | uniq -c | sort -k1,1nr -k2 \
    | awk -v secs="$secs" '{ n += $1; c = $1; $1 = ""; sub(/^ /, ""); by = by sep c " " $0; sep = ", " }
        END { printf "gate3: %d errors%s (%ds)\n", n, (n > 0 ? " (by code: " by ")" : ""), secs }'
if [ $FLIPPED -eq 1 ]; then
    # (the flipped tree must check: N and the borrow checker's 0)
    n=$(grep -c ': error\[' "$W/check.log")
    if [ "$FIXED_POINT" != ok ] || [ "$n" -gt 0 ]; then
        echo "gate3: not a fixed point${n:+ ($n errors)}"
        exit 1
    fi
fi
exit 0
