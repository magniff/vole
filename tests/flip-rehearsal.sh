#!/bin/sh
# The 0.28 flip rehearsal (0.27.6, docs/design/rust-surface-plan.md §7):
# how far compiler/src's rust-edition translation is from being the
# compiler. A copy is translated as gate 3 translates it, the hand fixes
# of tests/flip28/hand.patch are applied, and the result is pushed
# through the stages the flip needs:
#
#   type      `check --edition rust`: its type errors (gate 3's N)
#   borrowck  then the borrow checker's errors (counted once the types
#             check; before, `check --borrowck-partial`'s, in parentheses)
#   build     the translation built by COMPILER (stage 1)
#   fixpoint  stage 1 builds the translation (stage 2), stage 2 builds it
#             (stage 3): stage 2's and stage 3's objects must be the same,
#             and stage 1's should be too (COMPILER and the translation
#             compile the translation alike)
#   suite     tests/run.sh with stage 2 (-c) on the cases given (default:
#             the smoke set, then rust_ and std2_), against COMPILER's
#             own run of the same cases: a case one passes and the other
#             fails is a difference (a miscompile or a translation bug)
#
# It prints one line per stage reached, and last the summary:
#   flip: type 0, borrowck 96, build -, fixpoint -, suite -
# (`-`: not reached; `ok`: passed; a number: what is left.)
#
# usage: tests/flip-rehearsal.sh [-c COMPILER] [-k DIR] [-j N] [--to STAGE]
#            [FILTER...]
#
#   -c COMPILER   the volec that translates, checks and builds stage 1
#                 (default: target/volec)
#   -k DIR        work in DIR and keep it: DIR/src (a git repository: the
#                 translation, then one commit per hand fix), the logs, the
#                 stages' binaries (default: a temporary directory, removed)
#   -j N          tests/run.sh's jobs (default 2)
#   --to STAGE    stop after STAGE (type, borrowck, build, fixpoint, suite)
#   FILTER...     the suite's cases (tests/run.sh filters)
#
# tests/flip28/hand.patch is a list of hand fixes, each a section: a line
#   #! CLASS: what it fixes (and, for T, F or S, the item it is routed as)
# then a `git diff` against the translation with the fixes before it
# applied (paths src/...). CLASS is T (the translator should do it), F (a
# front gap: rustc accepts it), S (a std2 gap) or H (a hand fix the flip
# keeps). The sections are applied in order; one that does not apply
# stops the rehearsal (the translation moved under it).
# `tests/flip-rehearsal.sh --export DIR` writes hand.patch from DIR/src's
# commits after the translation's (each commit's subject is its `#!` line).

set -u
LC_ALL=C
export LC_ALL
ROOT=$(cd "$(dirname "$0")/.." && pwd)
PATCH="$ROOT/tests/flip28/hand.patch"
COMPILER="$ROOT/target/volec"
KEEP=""
JOBS=2
TO=suite
EXPORT=""
while [ $# -gt 0 ]; do
    case "$1" in
        -c) COMPILER=$2; shift ;;
        -k) KEEP=$2; shift ;;
        -j) JOBS=$2; shift ;;
        --to) TO=$2; shift ;;
        --export) EXPORT=$2; shift ;;
        -h|--help) sed -n '2,45p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "flip: unknown option '$1' (see --help)" >&2; exit 2 ;;
        *) break ;;
    esac
    shift
done
case "$COMPILER" in /*) ;; *) COMPILER="$(pwd)/$COMPILER" ;; esac
[ -x "$COMPILER" ] || { echo "flip: no compiler at $COMPILER" >&2; exit 2; }

if [ -n "$EXPORT" ]; then
    S=$(cd "$EXPORT/src" && pwd) || exit 2
    base=$(cd "$S" && git rev-list --max-parents=0 HEAD)
    : >"$PATCH.new"
    for c in $(cd "$S" && git rev-list --reverse "$base..HEAD"); do
        (cd "$S" && printf '#! %s\n' "$(git log -1 --format=%s "$c")" \
            && git diff --no-color "$c^" "$c" --src-prefix=a/src/ --dst-prefix=b/src/) >>"$PATCH.new"
    done
    mv "$PATCH.new" "$PATCH"
    echo "flip: wrote $(grep -c '^#! ' "$PATCH") hand fixes to tests/flip28/hand.patch"
    exit 0
fi

if [ -n "$KEEP" ]; then
    mkdir -p "$KEEP" || exit 2
    W=$(cd "$KEEP" && pwd)
    rm -rf "$W/src" "$W/stage1" "$W/stage2" "$W/stage3" "$W"/stage*.o "$W/suite"
else
    W=$(mktemp -d "${TMPDIR:-/tmp}/flip.XXXXXX") || exit 2
    trap 'rm -rf "$W"' EXIT INT TERM
fi
case "$(uname -s)-$(uname -m)" in
    Darwin-arm64) HOST=aarch64-macos; LINK="-arch arm64" ;;
    Darwin-x86_64) HOST=x86_64-macos; LINK="-arch x86_64" ;;
    Linux-aarch64) HOST=aarch64-linux; LINK="" ;;
    *) HOST=x86_64-linux; LINK="" ;;
esac
CC=${CC:-cc}

T_TYPE=- T_BC=- T_BUILD=- T_FIX=- T_SUITE=-
summary() {
    echo "flip: type $T_TYPE, borrowck $T_BC, build $T_BUILD, fixpoint $T_FIX, suite $T_SUITE"
}
count() { # <log>: the errors in it
    grep -c ': error\[' "$1" 2>/dev/null || true
}

# (a) the translation, as gate 3 makes it
cp -R "$ROOT/compiler/src" "$W/src" || exit 2
(cd "$W" && "$COMPILER" fix --edition rust src/main.vl --force) >"$W/fix.log" 2>&1
if ! grep -q '^fixed' "$W/fix.log"; then
    echo "flip: the translator did not run:"
    tail -5 "$W/fix.log"
    summary
    exit 1
fi
(cd "$W/src" && git init -q && git add -A \
    && git -c user.name=flip -c user.email=flip@localhost commit -qm translation) || exit 2

# (b) the hand fixes, section by section
n=0
if [ -f "$PATCH" ]; then
    awk -v dir="$W" '/^#! /{ n++; f = sprintf("%s/hand.%03d.patch", dir, n); print > (dir "/hand.list"); next }
        { print > f }' "$PATCH"
    for p in $(ls "$W"/hand.*.patch 2>/dev/null); do
        n=$((n + 1))
        line=$(sed -n "${n}p" "$W/hand.list")
        if ! git -C "$W/src" apply -p2 "$p" 2>"$W/apply.err"; then
            echo "flip: hand fix $n does not apply: ${line#\#! }"
            sed 's/^/  /' "$W/apply.err" | head -5
            summary
            exit 1
        fi
        (cd "$W/src" && git add -A && git -c user.name=flip -c user.email=flip@localhost \
            commit -qm "${line#\#! }") || exit 2
    done
fi
[ -f "$W/hand.list" ] || : >"$W/hand.list"
echo "flip: hand fixes: $n ($(awk '/^#! [TFSH]:/ { c[substr($2, 1, 1)]++ }
    END { printf "%d T, %d F, %d S, %d H", c["T"], c["F"], c["S"], c["H"] }' "$W/hand.list"))"

# (c) the check: types, then borrowck
(cd "$W" && "$COMPILER" check --edition rust --max-errors=0 src/main.vl) >"$W/check.log" 2>&1
types=$(grep ': error\[' "$W/check.log" | grep -vc ': error\[borrowck')
bc=$(grep -c ': error\[borrowck' "$W/check.log")
T_TYPE=$types
if [ "$types" -gt 0 ]; then
    (cd "$W" && "$COMPILER" check --edition rust --max-errors=0 --borrowck-partial src/main.vl) \
        >"$W/borrowck.log" 2>&1
    T_BC="($(grep -c ': error\[borrowck' "$W/borrowck.log"))"
    echo "flip: type: $types errors (check.log)"
    summary
    exit 0
fi
echo "flip: type: ok"
T_BC=$bc
if [ "$bc" -gt 0 ] || ! grep -q '^ok:' "$W/check.log"; then
    echo "flip: borrowck: $bc errors (check.log)"
    summary
    exit 0
fi
T_BC=ok
echo "flip: borrowck: ok"
[ "$TO" != borrowck ] || { summary; exit 0; }

# (d) the build, then the fixpoint
build() { # <compiler> <out>
    "$1" --target "$HOST" "$W/src/main.vl" -o "$2.o" >"$2.log" 2>&1 \
        && $CC $LINK -o "$2" "$2.o" -lm >>"$2.log" 2>&1
}
if ! build "$COMPILER" "$W/stage1"; then
    T_BUILD=fail
    echo "flip: build: stage 1 failed (stage1.log)"
    tail -5 "$W/stage1.log" | sed 's/^/  /'
    summary
    exit 0
fi
T_BUILD=ok
echo "flip: build: ok (stage 1, by $("$COMPILER" --version 2>&1 | head -1))"
[ "$TO" != build ] || { summary; exit 0; }
if ! build "$W/stage1" "$W/stage2"; then
    T_FIX="stage2 fails"
    echo "flip: fixpoint: stage 2 failed (stage2.log)"
    tail -5 "$W/stage2.log" | sed 's/^/  /'
    summary
    exit 0
fi
if ! build "$W/stage2" "$W/stage3"; then
    T_FIX="stage3 fails"
    echo "flip: fixpoint: stage 3 failed (stage3.log)"
    tail -5 "$W/stage3.log" | sed 's/^/  /'
    summary
    exit 0
fi
if ! cmp -s "$W/stage2.o" "$W/stage3.o"; then
    T_FIX=differs
    echo "flip: fixpoint: stage2.o and stage3.o differ"
    summary
    exit 0
fi
# (stage 1 is the translation built by COMPILER, stage 2 the translation
# built by itself: the same object unless the translated compiler compiles
# differently from COMPILER's source, a miscompile or a translation bug;
# `--emit-ir` from both on the translation shows where)
if cmp -s "$W/stage1.o" "$W/stage2.o"; then
    T_FIX=ok
    echo "flip: fixpoint: ok (stage 1's object is stage 2's too)"
else
    T_FIX="ok, stage1.o differs"
    echo "flip: fixpoint: stage 2 = stage 3, but stage1.o differs from stage2.o: the translated compiler compiles differently from $(basename "$COMPILER") (diff their --emit-ir of src/main.vl)"
fi
[ "$TO" != fixpoint ] || { summary; exit 0; }

# (e) the suite, stage 2 against COMPILER on the same cases
# (the smoke set: tests/affected.map's `set smoke`)
[ $# -gt 0 ] || set -- $(awk '$1 == "set" && $2 == "smoke" { for (i = 3; i <= NF; i++) print $i }' \
    "$ROOT/tests/affected.map") rust_ std2_
mkdir -p "$W/suite"
names() { # <log>: `pass NAME` / `FAIL NAME` lines, sorted
    grep -E '^(PASS|FAIL|pass|fail|XFAIL|xfail|XPASS) ' "$1" | sort
}
"$ROOT/tests/run.sh" -j "$JOBS" -c "$W/stage2" "$@" >"$W/suite/flip.log" 2>&1
"$ROOT/tests/run.sh" -j "$JOBS" -c "$COMPILER" "$@" >"$W/suite/mvs.log" 2>&1
grep -E '^FAIL ' "$W/suite/flip.log" | sed 's/:.*//' | sort -u >"$W/suite/flip.fail"
grep -E '^FAIL ' "$W/suite/mvs.log" | sed 's/:.*//' | sort -u >"$W/suite/mvs.fail"
d=$(comm -3 "$W/suite/flip.fail" "$W/suite/mvs.fail" | wc -l | tr -d ' ')
total=$(grep -E '^  total' "$W/suite/flip.log" | tail -1)
if [ "$d" -gt 0 ]; then
    T_SUITE=$d
    echo "flip: suite: $d differ (suite/flip.fail against suite/mvs.fail); stage 2's$total"
    comm -3 "$W/suite/flip.fail" "$W/suite/mvs.fail" | head -20 | sed 's/^/  /'
else
    T_SUITE=ok
    echo "flip: suite: ok, the same results as $(basename "$COMPILER") ($*);$total"
fi
summary
