#!/bin/sh
# The tests of the refactoring tools (0.11): volec edit, undo, check,
# fix, lint, same-output and the planning queries (query stats, deps,
# unused, impact). POSIX sh and awk only.
#
# usage: tests/refactor/run.sh [-c COMPILER] [-u] [NAME...]
#
#   -c COMPILER   the volec binary (default: target/volec)
#   -u            rewrite the .t files that fail with the output they get
#                 now (the real numbers, std's too)
#   NAME          only these transcripts (NAME.t), and not the checks of
#                 the compiler's own source below
#
# Each tests/refactor/NAME.t is a transcript run in a fresh copy of the
# program tests/refactor/NAME/ (a git repository of its own, so that
# edits are journaled for undo; plain*.t: a directory that is none):
#   $ ARGS    runs `volec ARGS` there (ARGS are evaluated by the shell:
#             `< $T/inputs/x.vl` gives stdin from tests/refactor/inputs)
#   % CMD     runs shell command CMD there (`cat geom.vl`, to see what
#             an edit wrote; 0.25.5: a bare `volec` in it is the
#             compiler under test, first in PATH)
# the lines after it, up to the next `$` or `%` line, are its output:
# stdout, then stderr, then `[exit N]` when N is not 0. The compiler's
# path is written `volec`, the copy's `WORK`, the shell's own errors'
# prefix `tests/refactor/run.sh:` however the runner was called. Lines starting with `##`
# are comments. A test passes when the transcript it makes is the file,
# comments aside, std's positions compared normalized (0.25.3,
# tests/stdpos.awk: `<std>:L:C`; a transcript with a line `## exact-std`
# compares them exactly); one with a `## XFAIL: reason` line is expected to differ
# (counted xfail), and fails when it does not.
#
# Then the compiler's own source is asked for its stats, deps, unused
# items and lint, which must be plausible, and same-output compares the
# compiler with itself (identical) and with a copy that differs.
#
# Prints `pass NAME` or `FAIL NAME` (and why) for each test; exits 1 if
# one failed.

set -u
LC_ALL=C
export LC_ALL

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
COMPILER="$ROOT/target/volec"
UPDATE=0
ONLY=
while [ $# -gt 0 ]; do
    case "$1" in
        -c) [ $# -ge 2 ] || exit 2; COMPILER=$2; shift 2 ;;
        -u) UPDATE=1; shift ;;
        -*) echo "usage: tests/refactor/run.sh [-c COMPILER] [-u] [NAME...]" >&2; exit 2 ;;
        *) ONLY="$ONLY $1"; shift ;;
    esac
done
case "$COMPILER" in
    /*) ;;
    *) COMPILER="$(pwd)/$COMPILER" ;;
esac
[ -x "$COMPILER" ] || { echo "refactor/run.sh: no compiler at $COMPILER" >&2; exit 2; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/vole-refactor.XXXXXX")
WORK=$(cd "$WORK" && pwd -P)
trap 'rm -rf "$WORK"' EXIT
trap 'exit 130' INT TERM
STATUS=0
T=$HERE
export T
unset VOLE_ROOT
# (0.25.4) $TMPDIR in the work directory, removed with it: what the tools
# keep there (`volec run`'s programs without a cache, try's slots) goes too
mkdir -p "$WORK/tmp"
TMPDIR="$WORK/tmp"
export TMPDIR
# (0.25.5) a bare `volec` in a `%` line is the compiler under test, first
# in PATH, not whatever is installed (mod254 #13)
mkdir -p "$WORK/bin"
ln -s "$COMPILER" "$WORK/bin/volec"
PATH="$WORK/bin:$PATH"
export PATH

# The transcript of test file $1, run in a copy of its program, on stdout;
# (0.13) with $2 `off`, without the tools' cache, with `cache`, with a
# cache of its own (the queries and checks after each edit see the files
# changed under it).
transcript() {
    name=$(basename "$1" .t)
    if [ "$2" = off ]; then
        VOLE_CACHE=off
    else
        VOLE_CACHE="$WORK/cache-$name"
    fi
    export VOLE_CACHE
    dir="$WORK/$name"
    rm -rf "$dir"
    mkdir -p "$dir"
    [ -d "$HERE/$name" ] && cp -R "$HERE/$name/." "$dir/"
    # (0.14: plain*.t run in a directory that is no git checkout, as a
    # user's program may be: the journal is then .volec/edits)
    case "$name" in
        plain*) ;;
        *) (cd "$dir" && git init -q . && git -c user.name=t -c user.email=t@t add -A \
            && git -c user.name=t -c user.email=t@t commit -q -m fixture) >/dev/null 2>&1 ;;
    esac
    grep -E '^[$%] ' "$1" | while IFS= read -r line; do
        printf '%s\n' "$line"
        args=${line#? }
        (
            cd "$dir" || exit 1
            case "$line" in
                \$*) eval "\"\$COMPILER\" $args" >"$WORK/out" 2>"$WORK/err" </dev/null ;;
                *) eval "$args" >"$WORK/out" 2>"$WORK/err" </dev/null ;;
            esac
            rc=$?
            cat "$WORK/out" "$WORK/err" | sed -e "s|$WORK/bin/volec|volec|g" -e "s|$COMPILER|volec|g" -e "s|$dir|WORK|g" -e "s|$WORK|WORK|g" \
                -e "s|^$0: |tests/refactor/run.sh: |"
            [ $rc -eq 0 ] || echo "[exit $rc]"
        )
    done
}

STDPOS="$ROOT/tests/stdpos.awk"
# Whether transcript file $1's text $2 matches what it got, $3 (0.25.3):
# std's numbers normalized unless $1 says `## exact-std`; with
# VOLE_STD_SHIFT=1 (tests/stdpos/run.sh) $2's std numbers are moved first,
# as a std change would move them. Leaves the texts compared in $3.w, $3.g.
same_transcript() {
    if [ "${VOLE_STD_SHIFT:-0}" = 1 ]; then
        awk -v mode=shift -f "$STDPOS" "$2" >"$3.s"
    else
        cp "$2" "$3.s"
    fi
    if grep -q '^## exact-std' "$1"; then
        cp "$3.s" "$3.w"
        cp "$3" "$3.g"
    else
        awk -f "$STDPOS" "$3.s" >"$3.w"
        awk -f "$STDPOS" "$3" >"$3.g"
    fi
    cmp -s "$3.w" "$3.g"
}
# (VOLE_STD_SHIFT=1: once, without the cache; the shift is the check)
MODES="off cache"
[ "${VOLE_STD_SHIFT:-0}" = 1 ] && MODES=off
for file in "$HERE"/*.t; do
    [ -f "$file" ] || continue
    name=$(basename "$file" .t)
    if [ -n "$ONLY" ]; then
        case " $ONLY " in *" $name "*) ;; *) continue ;; esac
    fi
    for mode in $MODES; do
    transcript "$file" $mode >"$WORK/$name.got"
    grep -v '^##' "$file" >"$WORK/$name.want"
    if [ $UPDATE -eq 1 ] && [ $mode = off ] && ! same_transcript "$file" "$WORK/$name.want" "$WORK/$name.got"; then
        # (each comment stays before the command it was before; 0.25.5: a
        # line that differs only in std's numbers kept, tests/stdkeep.sh)
        if ! grep -q '^## exact-std' "$file"; then
            sh "$ROOT/tests/stdkeep.sh" "$WORK/$name.want" "$WORK/$name.got" >"$WORK/$name.kept"
            cp "$WORK/$name.kept" "$WORK/$name.got"
        fi
        awk 'NR == FNR {
                if ($0 ~ /^##/) { pending = pending $0 "\n" }
                else if ($0 ~ /^[$%] /) { before[++n] = pending; pending = "" }
                next
            }
            /^[$%] / { printf "%s", before[++k] }
            { print }
            END { printf "%s", pending }' "$file" "$WORK/$name.got" >"$WORK/$name.new"
        cp "$WORK/$name.new" "$file"
    fi
    grep -v '^##' "$file" >"$WORK/$name.want"
    # (0.25) `## XFAIL: reason` in a transcript: known to differ, for that
    # reason; one that passes says so (remove the line)
    xfail=$(sed -n 's/^## XFAIL: //p' "$file" | head -1)
    if same_transcript "$file" "$WORK/$name.want" "$WORK/$name.got"; then
        if [ -n "$xfail" ]; then
            echo "FAIL $name ($mode): passes but is marked XFAIL ($xfail); remove the line"
            STATUS=1
        else
            echo "pass $name ($mode)"
        fi
    elif [ -n "$xfail" ]; then
        echo "xfail $name ($mode): $xfail"
    else
        echo "FAIL $name ($mode): the transcript differs (< expected, > got; std's numbers as L:C, N):"
        diff "$WORK/$name.got.w" "$WORK/$name.got.g" | sed 's/^/    /' | head -40
        STATUS=1
    fi
    done
done
unset VOLE_CACHE
# (NAME given: those transcripts only)
[ -z "$ONLY" ] || exit $STATUS

# The compiler's own source.
check() { # <name> <condition> <output>
    if [ "$2" = 1 ]; then
        echo "pass $1"
    else
        echo "FAIL $1:"
        printf '%s\n' "$3" | head -20 | sed 's/^/    /'
        STATUS=1
    fi
}
cd "$ROOT" || exit 2
TAB=$(printf '\t')
# stats: every file of the compiler, largest first (the largest over 300
# lines), a total.
out=$("$COMPILER" query stats --over 300 2>&1)
ok=0
n=$(printf '%s\n' "$out" | grep -c "^[0-9]*${TAB}[0-9]*${TAB}compiler/src/[a-z_0-9/]*\.vl")
[ "$n" -ge 40 ] && printf '%s\n' "$out" | head -1 | grep -q "^[0-9]*${TAB}[0-9]*${TAB}compiler/src/[a-z_0-9/]*\.vl${TAB}over\$" \
    && printf '%s\n' "$out" | grep -q "^[0-9]*${TAB}[0-9]*${TAB}total\$" \
    && printf '%s\n' "$out" | grep -q '^note query.over: [0-9]* files over 300 lines$' && ok=1
check self_stats "$ok" "$(printf '%s\n' "$out" | head -8)"
out=$("$COMPILER" query stats gvn 2>&1)
ok=0
printf '%s\n' "$out" | head -1 | grep -q "^# crate::middle::gvn${TAB}compiler/src/middle/gvn.vl${TAB}[0-9]* lines${TAB}[0-9]* items\$" \
    && printf '%s\n' "$out" | grep -q "^[0-9]*${TAB}fn${TAB}run_gvn\$" && ok=1
check self_stats_module "$ok" "$(printf '%s\n' "$out" | head -5)"
# deps: every item of a module, and groups of at most N lines, each at
# most N lines unless one item is larger.
out=$("$COMPILER" query deps check --max-lines 60 2>&1)
ok=0
items=$(printf '%s\n' "$out" | head -1 | sed -n "s/.*${TAB}\([0-9]*\) items\$/\1/p")
rows=$(printf '%s\n' "$out" | grep -v "^groups${TAB}" | grep -c "^[A-Za-z_][A-Za-z_0-9:]*${TAB}[0-9]*${TAB}")
groups=$(printf '%s\n' "$out" | grep -c "^group [0-9]*${TAB}")
big=$(printf '%s\n' "$out" | awk -F "$TAB" '/^group / && $2 > 60 && $4 != "over"' | wc -l | tr -d ' ')
[ -n "$items" ] && [ "$rows" = "$items" ] && [ "$groups" -ge 5 ] && [ "$big" = 0 ] \
    && printf '%s\n' "$out" | grep -q "^check_program${TAB}" \
    && printf '%s\n' "$out" | grep -q "^groups${TAB}[0-9]*${TAB}at most 60 lines${TAB}[0-9]* references between them\$" && ok=1
check self_deps "$ok" "$(printf '%s\n' "$out" | head -3; printf '%s\n' "$out" | grep '^groups')"
# unused: something, by file, and every listed definition really has no
# reference; or (0.12, after the clean-up) nothing.
out=$("$COMPILER" query unused --all 2>&1)
ok=0
[ "$out" = "note query.empty: nothing unused" ] && ok=1
n=$(printf '%s\n' "$out" | grep -c "${TAB}compiler/src/[a-z_0-9/]*\.vl:[0-9]*:[0-9]*${TAB}")
first=$(printf '%s\n' "$out" | grep "${TAB}fn\$" | head -1 | cut -f1)
[ "$n" -ge 1 ] && [ -n "$first" ] && [ "$("$COMPILER" query refs --count "$first" 2>/dev/null)" = 1 ] \
    && ! printf '%s\n' "$out" | grep -q "^crate::main${TAB}" && ok=1
check self_unused "$ok" "$(printf '%s\n' "$out" | head -5)"
# impact: the calls of a function used in several files.
out=$("$COMPILER" query impact base::grow 2>&1)
ok=0
printf '%s\n' "$out" | head -1 | grep -q "^crate::base::grow${TAB}compiler/src/base/mod.vl:" \
    && printf '%s\n' "$out" | grep -q "^instances${TAB}[0-9]*${TAB}grow<" \
    && printf '%s\n' "$out" | grep -q "^total${TAB}[0-9]*${TAB}[0-9]*${TAB}[0-9]* files" && ok=1
check self_impact "$ok" "$(printf '%s\n' "$out" | head -3)"
# lint: the files over 300 lines, each with the deps of its module.
out=$("$COMPILER" lint --max-lines 300 2>&1)
rc=$?
ok=0
[ $rc = 1 ] && printf '%s\n' "$out" | head -1 | grep -q '^error lint.max-lines: compiler/src/[a-z_0-9/]*\.vl: [0-9]* lines (at most 300)$' \
    && printf '%s\n' "$out" | grep -q "^try: .* query deps crate::[a-z_0-9:]* --max-lines 300\$" && ok=1
check self_lint "$ok" "$(printf '%s\n' "$out" | head -4)"
"$COMPILER" lint --max-lines 100000 >/dev/null 2>&1
check self_lint_ok "$([ $? = 0 ] && echo 1)" "lint --max-lines 100000 failed"
# check: the compiler's source has no errors, quickly.
"$COMPILER" check compiler/src/main.vl >"$WORK/check.out" 2>&1
rc=$?
# (0.18.1: a clean check says so in one line; 0.25.3: but for one
# unsafe.unjustified warning, the compiler's legacy unsafe, which
# docs/unsafe-baseline.md counts)
clean=$(grep -v 'warning\[unsafe\.unjustified\]' "$WORK/check.out" | sed 's/^ok: 0 errors, 1 warning in /ok: 0 errors in /')
check self_check "$([ $rc = 0 ] && [ "$clean" = "ok: 0 errors in compiler/src/main.vl" ] && echo 1)" "$(cat "$WORK/check.out")"
# same-output: the compiler against a copy of itself (identical), and
# against a wrapper that changes one compilation (different).
cp "$COMPILER" "$WORK/old-volec"
out=$("$COMPILER" same-output "$WORK/old-volec" --corpus examples --corpus tests/refactor/edits --work "$WORK/so" 2>&1)
ok=0
printf '%s\n' "$out" | grep -q "^identical${TAB}[0-9]* compilations${TAB}[0-9]* programs${TAB}[0-9]* targets${TAB}-O0 -O1 -O2\$" && ok=1
check same_output_identical "$ok" "$out"
# (0.16) OLD named without a `/`: looked up in $PATH.
out=$(PATH="$WORK:$PATH" "$COMPILER" same-output old-volec --corpus tests/refactor/edits --work "$WORK/so-path" 2>&1)
ok=0
printf '%s\n' "$out" | grep -q "^identical${TAB}" && ok=1
check same_output_in_path "$ok" "$out"
# (0.25.5) A compilation whose error has a `try:` line naming the compiler
# (`try: OLD fix --suggested ...`): the two compilers' own paths are taken
# as equal, so a copy of the compiler is identical.
mkdir -p "$WORK/sotry"
printf 'fn count() -> i32 {\n    3\n}\n\nfn main() -> i32 {\n    coutn() - 3\n}\n' >"$WORK/sotry/try.vl"
out=$("$COMPILER" same-output "$WORK/old-volec" --corpus "$WORK/sotry" --work "$WORK/so-try" 2>&1)
ok=0
printf '%s\n' "$out" | grep -q "^identical${TAB}" \
    && "$WORK/old-volec" "$WORK/sotry/try.vl" -o "$WORK/sotry/out.s" --diagnostics=human 2>&1 \
        | grep -q "try: $WORK/old-volec fix --suggested" && ok=1
check same_output_own_paths "$ok" "$out"
cat >"$WORK/differs.sh" <<EOS
#!/bin/sh
# volec, but its assembly for md5/main.vl at -O1 has one more line
"$WORK/old-volec" "\$@"
st=\$?
out=
prev=
for a in "\$@"; do [ "\$prev" = -o ] && out=\$a; prev=\$a; done
case "\$*" in *-O1*md5/main.vl*) printf '\t// differs\n' >>"\$out" ;; esac
exit \$st
EOS
chmod +x "$WORK/differs.sh"
out=$("$COMPILER" same-output "$WORK/differs.sh" --corpus examples --work "$WORK/so2" 2>&1)
rc=$?
ok=0
[ $rc = 1 ] && printf '%s\n' "$out" | head -1 | grep -q "^examples/md5/main.vl${TAB}[a-z0-9_-]*${TAB}-O1${TAB}asm line [0-9]*\$" \
    && printf '%s\n' "$out" | grep -q "^-${TAB}${TAB}// differs\$" \
    && printf '%s\n' "$out" | grep -q '^error same-output.differs: [0-9]* of [0-9]* compilations differ' \
    && printf '%s\n' "$out" | grep -q '^try: diff .*/old/out.s .*/new/out.s$' && ok=1
check same_output_differs "$ok" "$out"
# (0.13) items moved to another module and back: every file as it was.
out=$(sh "$HERE/roundtrip.sh" -c "$COMPILER" -n 40 2>&1)
check roundtrip "$([ $? = 0 ] && echo 1)" "$out"
# (0.15) A module path without `crate::`, as a user writes it: made,
# then an item moved to it.
mkdir -p "$WORK/nocrate"
printf 'fn helper() -> i64 {\n    2\n}\n\nfn main() -> i32 {\n    (helper() - 2) as i32\n}\n' >"$WORK/nocrate/main.vl"
out=$(cd "$WORK/nocrate" && git init -q . 2>/dev/null; "$COMPILER" refactor new-module report 2>&1 \
    && "$COMPILER" refactor move helper --to report 2>&1 && "$COMPILER" query def report::helper 2>&1)
ok=0
printf '%s\n' "$out" | grep -q '^made module report' \
    && printf '%s\n' "$out" | grep -q "^crate::report::helper${TAB}report.vl:1:8${TAB}" && ok=1
check module_path_without_crate "$ok" "$out"
# (0.26.0) rename and fix leave an embedded block's text as it is: a vole
# `helper` renamed, the WGSL `helper` in the block not
mkdir -p "$WORK/embedren"
printf 'embed wgsl K {\n    fn helper(x: f32) -> f32 { return x; }\n    @compute @workgroup_size(1)\n    fn main() { _ = helper(1.0); }\n}\n\nfn helper(x: i64) -> i64 {\n    x\n}\n\nfn main() -> i32 {\n    helper(0) as i32\n}\n' >"$WORK/embedren/main.vl"
out=$(cd "$WORK/embedren" && git init -q . 2>/dev/null; "$COMPILER" refactor rename helper assist 2>&1 && "$COMPILER" fix 2>&1)
ok=0
sed -n 1,5p "$WORK/embedren/main.vl" | grep -c helper | grep -q '^2$' \
    && grep -q '^fn assist(x: i64)' "$WORK/embedren/main.vl" && grep -q '^    assist(0)' "$WORK/embedren/main.vl" && ok=1
check rename_embed_body "$ok" "$out
$(cat "$WORK/embedren/main.vl")"
# explain (0.13): every code the compiler's source can print has an
# entry: the tools' codes (`c"query.no-match"`; 0.17: the own pass's,
# `c"own.moved"`), the kinds of the
# compiler's errors (ERR_KIND; 0.25.3: main.missing) and warnings and keyed errors (their
# third argument); and every entry is such a code. (0.25.3: lex.* and
# embed.*, text blocks and include_str; `embed.sh`, a script's name, is
# not one. 0.26.0: gpu.* and wgsl.*, and std's own: the shader compiler's
# `"wgsl.X"` and `error wgsl.target`, std::gpu's `gpu.X:` texts.)
{
    grep -rhoE --exclude-dir=.volec 'c"(query|edit|patch|undo|check|fix|lint|fmt|same-output|refactor|rewrite|explain|batch|conflict|try|test|probe|reduce|own|fuzz|distinct|contract|conv|syntax|sync|extension|use|link|cli|lex|embed|unsafe|run|gpu|wgsl)\.[a-z0-9_-]+"' \
        compiler/src
    grep -rhoE '"wgsl\.[a-z]+"|error wgsl\.[a-z]+' compiler/std/gpu/wgsl | sed -e 's/^"\(.*\)"$/c"\1"/' -e 's/^error \(.*\)$/c"\1"/'
    grep -rhoE 'gpu\.[a-z]+:' compiler/std/gpu | sed -e 's/^\(.*\):$/c"\1"/'
    grep -rhoE --exclude-dir=.volec 'ERR_KIND = c"[^"]*"' compiler/src
    grep -rhoE --exclude-dir=.volec 'report_(warning|error_once)\([^,]*, [^,]*, c"[^"]*"' compiler/src
    # (0.15: guide's codes, written into its own messages)
    grep -rhoE --exclude-dir=.volec '"(error|note) guide\.[a-z-]+' compiler/src | sed -e 's/^"[a-z]* \(.*\)$/c"\1"/'
    # (0.25.5: a build error printed whole, `error[time.instructions]`)
    grep -rhoE --exclude-dir=.volec 'c"error\[time\.[a-z0-9_-]+\]' compiler/src | sed -e 's/^c"error\[\(.*\)\]$/c"\1"/'
} | sed -e 's/.*c"\([^"]*\)"$/\1/' | grep -v '^embed\.sh$' | sort -u >"$WORK/codes"
"$COMPILER" explain --list | sort >"$WORK/explained"
missing=$(comm -23 "$WORK/codes" "$WORK/explained")
extra=$(comm -13 "$WORK/codes" "$WORK/explained")
bad=
while IFS= read -r code; do
    "$COMPILER" explain "$code" >"$WORK/explain.out" 2>&1 \
        && [ "$(sed -n 1p "$WORK/explain.out")" != "" ] && grep -q '^fix: ' "$WORK/explain.out" \
        && grep -q '^example:$' "$WORK/explain.out" || bad="$bad $code"
done <"$WORK/codes"
check self_explain "$([ "$(wc -l <"$WORK/codes")" -ge 90 ] && [ -z "$missing$extra$bad" ] && echo 1)" \
    "$(wc -l <"$WORK/codes") codes; no entry:$(echo $missing); not a code:$(echo $extra); bad:$bad"
# The own pass (0.17, front/own): compiler/src walks clean under
# --values=report (the default only walks when its findings are printed).
out=$(VOLE_CACHE="$WORK/owncache" "$COMPILER" check --values=report compiler/src/main.vl 2>&1)
check own_report_compiler "$(printf '%s\n' "$out" | grep -q '^own: 0 findings' && echo 1)" "$out"
exit $STATUS
