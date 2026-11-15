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
# only the tests/run programs whose name contains it, no example). A
# borrow the IR settles as only read through (places::build::settle_loans)
# needs no site of the walk's. A check that dies by a signal is a crash:
# reported with its file, and the run fails (0.30.1).
#
# --self-test: the check is shown to catch: VOLE_E18_CHECK=blind (the
# walk's sites and the IR's settling not used) must report the borrows of
# effect_format_arg_kept.vl, a compiler that dies by SIGSEGV must fail the
# run naming its file, and VOLE_E18_CHECK=all must list the forms of
# effect_format_arg_kept.vl and err_effect_format_arg_escapes.vl as they
# are settled, each line whole (the holes only read through, a reference
# only read through, an alias's use, borrows that go on).
#
# usage: tests/e18_loans.sh [-c COMPILER] [-j N] [--self-test] [PATTERN]
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
C="$ROOT/target/volec"
J=2
PAT=
SELF=0
while [ $# -gt 0 ]; do
    case "$1" in
        -c) C=$2; shift ;;
        -j) J=$2; shift ;;
        --self-test) SELF=1 ;;
        -*) echo "usage: tests/e18_loans.sh [-c COMPILER] [-j N] [--self-test] [PATTERN]" >&2; exit 2 ;;
        *) PAT=$1 ;;
    esac
    shift
done
cd "$ROOT" || exit 2
if [ "$SELF" -eq 1 ]; then
    T=$(mktemp -d "${TMPDIR:-/tmp}/e18s.XXXXXX")
    bad=0
    # (1) the walk made blind: the borrows must be reported, the run fail
    printf '#!/bin/sh\nVOLE_E18_CHECK=blind exec "%s" "$@"\n' "$C" > "$T/blind"
    chmod +x "$T/blind"
    sh "$0" -c "$T/blind" -j 1 effect_format_arg_kept > "$T/o1" 2>&1
    if [ $? -eq 0 ] || ! grep -q "effect_format_arg_kept.vl:.*did not see" "$T/o1"; then
        echo "e18-loans: self-test FAIL: a blind walk's borrows were not reported"; bad=1
    fi
    # (2) a check that dies by SIGSEGV: the run fails, naming the file
    printf '#!/bin/sh\nkill -SEGV $$\n' > "$T/crash"
    chmod +x "$T/crash"
    sh "$0" -c "$T/crash" -j 1 effect_format_arg_kept > "$T/o2" 2>&1
    if [ $? -eq 0 ] || ! grep -q "effect_format_arg_kept.vl: crash: the check died by signal 11" "$T/o2"; then
        echo "e18-loans: self-test FAIL: a crash was not reported with its file"; bad=1
    fi
    # (3) every form of the cases, as the IR and the walk settled it
    f=tests/run/err_effect_format_arg_escapes.vl
    VOLE_CACHE=off VOLE_E18_CHECK=all "$C" check --each --max-errors=0 $f > "$T/o3" 2>&1
    for want in "$f:47:31: error[type error] E1.8: a borrow the walk saw" \
        "$f:57:27: error[type error] E1.8: a borrow the walk saw" \
        "$f:68:17: error[type error] E1.8: a borrow the walk saw" \
        "$f:69:17: error[type error] E1.8: an alias's use the walk saw, only read through"; do
        if ! grep -qxF "$want" "$T/o3"; then
            echo "e18-loans: self-test FAIL: not listed: $want"; bad=1
        fi
    done
    f=tests/run/effect_format_arg_kept.vl
    VOLE_CACHE=off VOLE_E18_CHECK=all "$C" check --each --max-errors=0 $f > "$T/o4" 2>&1
    want="$f:60:17: error[type error] E1.8: a borrow the walk saw, only read through"
    if ! grep -qxF "$want" "$T/o4"; then
        echo "e18-loans: self-test FAIL: not listed: $want"; bad=1
    fi
    if [ "$(grep -c 'E1.8: a borrow only read through$' "$T/o4")" -ne 8 ]; then
        echo "e18-loans: self-test FAIL: effect_format_arg_kept.vl's 8 holes are not all read through"
        bad=1
    fi
    if grep -q "did not see" "$T/o3" "$T/o4"; then
        echo "e18-loans: self-test FAIL: a borrow of the cases the walk did not see"; bad=1
    fi
    rm -rf "$T"
    if [ "$bad" -ne 0 ]; then
        exit 1
    fi
    echo "e18-loans: self-test ok: a blind walk's borrows and a crash are reported, the forms settled"
    if [ -z "$PAT" ]; then
        exit 0
    fi
fi
OUT=$(mktemp "${TMPDIR:-/tmp}/e18.XXXXXX")
LIST=$(mktemp "${TMPDIR:-/tmp}/e18l.XXXXXX")
if [ -n "$PAT" ]; then
    git ls-files "tests/run/*$PAT*.vl" | sed 's/^/f /' > "$LIST"
else
    { git ls-files 'tests/run/*.vl' | sed 's/^/f /'
      git ls-files 'examples/*main.vl' | sed 's/^/r /'; } > "$LIST"
fi
# (--each: one line a borrow, not one a file; a status above 128 is a
# signal, the check's crash)
xargs -P "$J" -L 1 sh -c '
    if [ "$0" = r ]; then
        out=$(VOLE_CACHE=off VOLE_E18_CHECK=1 "'"$C"'" check --each --root "$1" --max-errors=0 2>&1)
    else
        out=$(VOLE_CACHE=off VOLE_E18_CHECK=1 "'"$C"'" check --each --max-errors=0 "$1" 2>&1)
    fi
    s=$?
    printf "%s\n" "$out" | grep "did not see" | sed "s|^|$1: |"
    if [ "$s" -gt 128 ]; then
        echo "$1: crash: the check died by signal $((s - 128))"
    fi
    exit 0' < "$LIST" > "$OUT"
crashes=$(grep -c ": crash: the check died" "$OUT")
n=$(grep -c "did not see" "$OUT")
programs=$(grep -c . "$LIST")
rm -f "$LIST"
if [ "$programs" -eq 0 ]; then
    echo "e18-loans: FAIL: no program matches '$PAT'"; rm -f "$OUT"; exit 1
fi
if [ "$n" -gt 0 ] || [ "$crashes" -gt 0 ]; then
    cat "$OUT"
    echo "e18-loans: FAIL: $n borrows the effect walk did not see, $crashes crashes, over $programs programs"
    rm -f "$OUT"
    exit 1
fi
rm -f "$OUT"
echo "e18-loans: ok: every IR borrow of a proof's local is a walk's borrow site, over $programs programs"
