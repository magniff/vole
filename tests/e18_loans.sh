#!/bin/sh
# E1.8's two lists compared (0.30.1, docs/design/contracts-effects.md
# E1.8): every borrow the places IR makes of a local a proof reads (a
# divisor proven not 0, a counted loop's variable) must be one the effect
# walk saw as a borrow site. The IR's borrows are every borrow made,
# whatever the syntax (places::build::emit_ref); a borrow the walk does not
# see is taken as one that goes anywhere (sound), but it is a form the walk
# should know: VOLE_E18_CHECK=1 makes each an error, `internal: E1.8: a
# borrow of a local the effect walk did not see`. This runs it over every
# tests/run program and every example, and fails on any (with PATTERN:
# only the tests/run programs whose name contains it, no example).
#
# usage: tests/e18_loans.sh [-c COMPILER] [-j N] [PATTERN]
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
C="$ROOT/target/volec"
J=2
PAT=
while [ $# -gt 0 ]; do
    case "$1" in
        -c) C=$2; shift ;;
        -j) J=$2; shift ;;
        -*) echo "usage: tests/e18_loans.sh [-c COMPILER] [-j N] [PATTERN]" >&2; exit 2 ;;
        *) PAT=$1 ;;
    esac
    shift
done
cd "$ROOT" || exit 2
OUT=$(mktemp "${TMPDIR:-/tmp}/e18.XXXXXX")
LIST=$(mktemp "${TMPDIR:-/tmp}/e18l.XXXXXX")
if [ -n "$PAT" ]; then
    git ls-files "tests/run/*$PAT*.vl" | sed 's/^/f /' > "$LIST"
else
    { git ls-files 'tests/run/*.vl' | sed 's/^/f /'
      git ls-files 'examples/*main.vl' | sed 's/^/r /'; } > "$LIST"
fi
xargs -P "$J" -L 1 sh -c '
    if [ "$0" = r ]; then
        VOLE_CACHE=off VOLE_E18_CHECK=1 "'"$C"'" check --root "$1" --max-errors=0 2>&1
    else
        VOLE_CACHE=off VOLE_E18_CHECK=1 "'"$C"'" check --max-errors=0 "$1" 2>&1
    fi | grep "did not see" | sed "s|^|$1: |"; exit 0' < "$LIST" > "$OUT"
n=$(grep -c . "$OUT")
programs=$(grep -c . "$LIST")
rm -f "$LIST"
if [ "$programs" -eq 0 ]; then
    echo "e18-loans: FAIL: no program matches '$PAT'"; rm -f "$OUT"; exit 1
fi
if [ "$n" -gt 0 ]; then
    cat "$OUT"
    echo "e18-loans: FAIL: $n borrows the effect walk did not see, over $programs programs"
    rm -f "$OUT"
    exit 1
fi
rm -f "$OUT"
echo "e18-loans: ok: every IR borrow of a proof's local is a walk's borrow site, over $programs programs"
