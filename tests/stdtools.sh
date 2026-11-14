#!/bin/sh
# (0.30) std inside the tools: in a vole repository std is files
# (compiler/std), and the tools name, search and change them there.
#
#   - an error in std's code prints as compiler/std/FILE.vl:L:C (and as
#     <std>:L:C where std is the compiler's own text: $VOLE_STD_TREE=none,
#     what the transcripts compare);
#   - `fix --suggested` makes the fix of an error in std's own code in
#     std's file, and says `run: sh compiler/std/embed.sh`;
#   - `query grep --in compiler/std/FILE.vl`, `query grep --std`, `query
#     refs --in compiler/std/FILE.vl` and `query items compiler/std/FILE.vl`
#     answer with std's files and their lines;
#   - `edit patch compiler/std/FILE.vl` patches the file (as text) and
#     says `run: sh compiler/std/embed.sh`; an edit of a std item by name
#     is refused with the command that works;
#   - `volec query effects std --templates` lists std's public functions
#     once each, a generic one by its template, and
#     tools/std-effects-diff.sh the ones whose effects differ from a
#     revision's;
#   - `volec check --std` checks every body of std (the templates no
#     program instantiates too): an undeclared effect and an unsafe
#     operation outside `unsafe` in a generic function nothing calls are
#     errors, at std's file.
#
# It works in a copy: std's files of this tree in a temporary directory
# (a git repository of its own), never the tree's.
#
# usage: tests/stdtools.sh [-c COMPILER]
# Prints `pass NAME` or `FAIL NAME` (and what it saw) for each check, then
# `stdtools: N passed, M failed`; exits 1 if one failed.

set -u
LC_ALL=C
export LC_ALL

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
COMPILER="$ROOT/target/volec"
while [ $# -gt 0 ]; do
    case "$1" in
        -c) [ $# -ge 2 ] || exit 2; COMPILER=$2; shift 2 ;;
        *) echo "usage: tests/stdtools.sh [-c COMPILER]" >&2; exit 2 ;;
    esac
done
case "$COMPILER" in
    /*) ;;
    *) COMPILER="$(pwd)/$COMPILER" ;;
esac
[ -x "$COMPILER" ] || { echo "stdtools.sh: no compiler at $COMPILER" >&2; exit 2; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/vole-stdtools.XXXXXX")
WORK=$(cd "$WORK" && pwd -P)
trap 'rm -rf "$WORK"' EXIT
trap 'exit 130' INT TERM

# The tools' cache off (a copy per run), std from the copy's files (the
# directory the commands run in holds compiler/std), no git identity or
# hooks of the user's.
VOLE_CACHE=off
export VOLE_CACHE
unset VOLE_STD_TREE

T="$WORK/tree"
mkdir -p "$T/compiler/src/front"
cp -R "$ROOT/compiler/std" "$T/compiler/std"
cp "$ROOT/compiler/src/front/stdsrc.vl" "$T/compiler/src/front/stdsrc.vl"
cat >"$T/main.vl" <<'EOF'
fn main() {
    let mut a = 1;
    let mut b = 2;
    std::mem::swap(&mut a, &mut b);
    println("{}", a);
}
EOF
(
    cd "$T" && git init -q . && git add -A . \
        && git -c user.name=t -c user.email=t@example.com commit -q -m base
) >/dev/null 2>&1 || { echo "stdtools.sh: cannot make the copy's repository" >&2; exit 2; }

PASSED=0
FAILED=0
# check NAME STATUS: the last command's output is in $WORK/out.
ok() {
    PASSED=$((PASSED + 1))
    echo "pass $1"
}
bad() {
    FAILED=$((FAILED + 1))
    echo "FAIL $1"
    sed 's/^/    /' "$WORK/out" | cut -c1-400 | head -12
}
# has NAME TEXT: $WORK/out holds TEXT.
has() {
    if grep -qF -- "$2" "$WORK/out"; then ok "$1"; else bad "$1"; echo "    (wanted: $2)"; fi
}
hasnot() {
    if grep -qF -- "$2" "$WORK/out"; then bad "$1"; echo "    (not wanted: $2)"; else ok "$1"; fi
}
run() {
    (cd "$T" && "$COMPILER" "$@") >"$WORK/out" 2>&1
}

MEM=compiler/std/mem.vl
LINE=$(grep -n 'crate::ptr::write(pb, t);' "$T/$MEM" | head -1 | cut -d: -f1)
[ -n "$LINE" ] || { echo "stdtools.sh: std::mem::swap has changed: adjust the test" >&2; exit 2; }

# ---- the queries ----
run query grep 'ptr::write(pb' --in $MEM main.vl
has grep_in_std_file_header "# $MEM"
has grep_in_std_file_line "$LINE:"
run query grep 'ptr::write(pb' --std main.vl
has grep_std_flag "# $MEM"
run query items $MEM main.vl
has items_std_file "# std::mem	$MEM"
run query refs std::mem::swap --in compiler/std/cell.vl main.vl
has refs_in_std_file "# compiler/std/cell.vl"
(cd "$T" && VOLE_STD_TREE=none "$COMPILER" query grep 'ptr::write(pb' --in std main.vl) >"$WORK/out" 2>&1
has grep_without_files "# <std>"

# ---- an edit of a std item by name: refused, with the edit that works ----
run edit patch std::mem::swap --old 'crate::ptr::write(pb, t);' --new 'crate::ptr::writ(pb, t);' main.vl
has edit_by_name_refused "error edit.not-source"
has edit_by_name_try "edit patch $MEM --old"

# ---- edit patch of std's file: written, and what to run ----
run edit patch $MEM --old 'crate::ptr::write(pb, t);' --new 'crate::ptr::writ(pb, t);'
has edit_std_file "patched $MEM"
has edit_std_file_run "run: sh compiler/std/embed.sh"
if grep -qF 'crate::ptr::writ(pb, t);' "$T/$MEM"; then ok edit_std_file_written; else bad edit_std_file_written; fi

# ---- the error, in std's file; in std's text without the files ----
run check main.vl
has error_in_std_file "$MEM:$LINE:9: error[type error] no 'writ' in module 'std::ptr'"
has error_names_fix "fix --suggested"
run check --json main.vl
has error_json_file "\"file\":\"$MEM\",\"line\":$LINE"
(cd "$T" && VOLE_STD_TREE=none "$COMPILER" check main.vl) >"$WORK/out" 2>&1
has without_files_ok "ok: 0 errors"

# ---- fix --suggested: std's file fixed ----
run fix --suggested --dry-run main.vl
has fix_dry_run "would fix $MEM:$LINE: writ -> write"
if grep -qF 'crate::ptr::writ(pb, t);' "$T/$MEM"; then ok fix_dry_run_wrote_nothing; else bad fix_dry_run_wrote_nothing; fi
run fix --suggested main.vl
has fix_std "fixed $MEM:$LINE: writ -> write"
has fix_std_run "run: sh compiler/std/embed.sh"
if cmp -s "$T/$MEM" "$ROOT/$MEM"; then ok fix_std_file_restored; else bad fix_std_file_restored; fi
run check main.vl
has fixed_checks "ok: 0 errors"

# ---- check --std: a body no program instantiates ----
# (std::mem::replace: main.vl does not call it. Its declaration loses
# `unsafe`, then its body the `unsafe` block.)
RLINE=$(grep -n '^pub fn replace<T>' "$T/$MEM" | head -1 | cut -d: -f1)
[ -n "$RLINE" ] || { echo "stdtools.sh: std::mem::replace has changed: adjust the test" >&2; exit 2; }
run check --std
has check_std_clean "ok: 0 errors"
has check_std_note "note check.std: "
awk -v n="$RLINE" 'NR == n - 1 && /^#\[effects\(unsafe, T\)\]$/ { print "#[effects(T)]"; next } { print }' \
    "$T/$MEM" >"$WORK/mem.vl" && cp "$WORK/mem.vl" "$T/$MEM"
run check main.vl
has check_plain_misses_it "ok: 0 errors"
run check --std
has check_std_effect "$MEM:$RLINE:5: error[effect] 'std::mem::replace' is #[effects(T)], but it has unsafe operations"
run check --std main.vl
has check_std_effect_with_root "$MEM:$RLINE:5: error[effect]"
cp "$ROOT/$MEM" "$T/$MEM"
awk -v n="$RLINE" 'NR > n && NR < n + 8 && /^    unsafe \{$/ { print "    {"; next } { print }' \
    "$T/$MEM" >"$WORK/mem.vl" && cp "$WORK/mem.vl" "$T/$MEM"
run check --std
has check_std_unsafe "error[unsafe] calling an \`unsafe fn\` is unsafe"
hasnot check_std_no_model_errors "error[type error]"
cp "$ROOT/$MEM" "$T/$MEM"

# ---- query unsafe: std's unneeded blocks, exactly ----
# (main.vl instantiates swap only. No block of std is listed as unneeded
# for it: until 0.30 every block of a generic function the program did
# not instantiate was, 25 for a small program. A block with nothing unsafe
# inside, put into replace, is the one listed; replace's own block, which
# holds ptr::read and ptr::write, is not.)
run query unsafe std --unneeded --root main.vl
has unsafe_none_unneeded "unneeded: 0"
hasnot unsafe_no_false_unneeded "none (unneeded)"
awk -v n="$RLINE" '{ print } NR == n {
    print "    // UNSAFE: a block of the test.\n    // SAFETY: it holds nothing unsafe."
    print "    unsafe {\n        let n: i64 = 0;\n        crate::mem::drop(n);\n    }" }' \
    "$T/$MEM" >"$WORK/mem.vl" && cp "$WORK/mem.vl" "$T/$MEM"
run query unsafe std --unneeded --root main.vl
has unsafe_unneeded_listed "$MEM:$((RLINE + 3))	block	std::mem::replace	other	justified	none (unneeded)"
has unsafe_unneeded_count "unneeded: 1"
cp "$ROOT/$MEM" "$T/$MEM"

# ---- the effects of std's public functions, against a revision ----
# (the copy's own repository: HEAD is std as copied. replace's declaration
# and body gain `diverge`: it and what calls it are listed; nothing is for
# std as committed.)
mkdir -p "$T/tools" && cp "$ROOT/tools/std-effects-diff.sh" "$T/tools/std-effects-diff.sh"
(cd "$T" && sh tools/std-effects-diff.sh -c "$COMPILER" --check) >"$WORK/out" 2>&1
rc=$?
has effects_diff_none "std-effects-diff: 0 changed, 0 added, 0 removed since HEAD"
if [ $rc -eq 0 ]; then ok effects_diff_none_status; else bad effects_diff_none_status; fi
awk -v n="$RLINE" 'NR == n - 1 && /^#\[effects\(unsafe, T\)\]$/ { print "#[effects(diverge, unsafe, T)]"; next }
    { print }
    NR > n && NR < n + 9 && /let old = crate::ptr::read\(p as \*const T\);/ {
        print "        let mut n: i64 = 0;\n        while n != 7 {\n            n = (n * 3 + 1) % 11;\n        }" }' \
    "$T/$MEM" >"$WORK/mem.vl" && cp "$WORK/mem.vl" "$T/$MEM"
(cd "$T" && sh tools/std-effects-diff.sh -c "$COMPILER" --check) >"$WORK/out" 2>&1
rc=$?
has effects_diff_changed "std::mem::replace	unsafe -> diverge unsafe"
has effects_diff_caller "std::option::Option::take	none -> diverge"
if [ $rc -eq 1 ]; then ok effects_diff_check_status; else bad effects_diff_check_status; fi
run query effects std::mem::replace --templates --std-tree compiler/std
has effects_templates "std::mem::replace	diverge unsafe"
cp "$ROOT/$MEM" "$T/$MEM"

echo "stdtools: $PASSED passed, $FAILED failed"
[ "$FAILED" = 0 ]
