#!/bin/sh
# The tests of the refactoring tools (0.11): volec edit, undo, check,
# fix, lint, same-output and the planning queries (query stats, deps,
# unused, impact). POSIX sh and awk only.
#
# usage: tests/refactor/run.sh [-c COMPILER] [-j JOBS] [-u] [--grep TEXT] [-l] [-n NAME] [FILTER...]
#
#   -c COMPILER   the volec binary (default: target/volec)
#   -j JOBS       (0.30) transcripts and checks run at once (default 1);
#                 the verdicts are the same for every JOBS
#   -u            rewrite the .t files that fail with the output they get
#                 now (the real numbers, std's too). (0.30) Only the
#                 transcripts run then, and only without the cache (the
#                 mode -u writes from): run again without -u for the
#                 cache mode and the checks
#   --grep TEXT   (0.30) only the transcripts whose file holds TEXT (a
#                 fixed string), and no check: `-u --grep edit.breaks`
#                 rewrites the transcripts a changed message is in
#   -l            (0.30) list what would run, `transcript NAME` and
#                 `check NAME`, and run nothing
#   -n NAME       (0.30) only the transcript or check named NAME exactly
#                 (repeatable)
#   FILTER...     (0.30) only the transcripts (NAME.t) and the checks of
#                 the compiler's own source below whose name contains a
#                 FILTER (before 0.30: NAME, exactly, and transcripts
#                 only); several, and -n, select the union. Selecting
#                 nothing is an error (`no case matches`), not a pass.
#
# The first line is the plan (`refactor: N transcripts (off cache), M
# checks, -j J`); then each transcript's and check's result as it ends
# (0.30: not when the run ends); the last line counts them, with the
# seconds taken.
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
# (0.28.0) std is the compiler's own text here, `<std>`, wherever the
# runner's programs are: not the files of a vole repository around them
# (front/stdtree.vl: find_std_tree), which the tools would name instead.
VOLE_STD_TREE=none
export VOLE_STD_TREE

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
COMPILER="$ROOT/target/volec"
. "$ROOT/tests/jobs.sh"
COMPILER="$ROOT/target/volec"
UPDATE=0
LIST=0
JOBS=1
GREP=
HAVE_GREP=0
FILTERS=
USAGE="usage: tests/refactor/run.sh [-c COMPILER] [-j JOBS] [-u] [--grep TEXT] [-l] [-n NAME] [FILTER...]"
while [ $# -gt 0 ]; do
    case "$1" in
        -c) [ $# -ge 2 ] || { echo "$USAGE" >&2; exit 2; }; COMPILER=$2; shift 2 ;;
        -j) [ $# -ge 2 ] || { echo "$USAGE" >&2; exit 2; }; JOBS=$2; shift 2 ;;
        -u) UPDATE=1; shift ;;
        --grep) [ $# -ge 2 ] || { echo "$USAGE" >&2; exit 2; }; GREP=$2; HAVE_GREP=1; shift 2 ;;
        -l) LIST=1; shift ;;
        -n) [ $# -ge 2 ] || { echo "$USAGE" >&2; exit 2; }
            FILTERS="$FILTERS=$2
"
            shift 2 ;;
        -h|--help) sed -n '2,/^# Each tests/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
        -*) echo "tests/refactor/run.sh: unknown option '$1'" >&2; echo "$USAGE" >&2; exit 2 ;;
        *) FILTERS="$FILTERS$1
"
            shift ;;
    esac
done
case "$JOBS" in
    ''|*[!0-9]*|0) echo "tests/refactor/run.sh: -j takes a number, 1 or more (got '$JOBS')" >&2; exit 2 ;;
esac
case "$COMPILER" in
    /*) ;;
    *) COMPILER="$(pwd)/$COMPILER" ;;
esac

# (VOLE_STD_SHIFT=1: once, without the cache; the shift is the check.
# -u: the mode it writes from)
MODES="off cache"
[ "${VOLE_STD_SHIFT:-0}" = 1 ] && MODES=off
[ $UPDATE -eq 1 ] && MODES=off

# The checks besides the transcripts, in the order they run, the longest
# (roundtrip: two minutes) first (job_check has an arm for each:
# tests/runner/run.sh compares the two).
CHECKS="roundtrip self_stats self_stats_module self_deps self_unused self_impact self_lint self_lint_ok self_check same_output_identical same_output_in_path same_output_own_paths same_output_differs module_path_without_crate rename_embed_body self_explain"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/vole-refactor.XXXXXX")
WORK=$(cd "$WORK" && pwd -P)
trap 'rm -rf "$WORK"' EXIT
trap 'exit 130' INT TERM
# The jobs: every transcript and check, then the ones selected.
# (the checks first: the longest of them take minutes, and a long job
# that starts last runs alone at the end)
: >"$WORK/all"
if [ $UPDATE -eq 0 ] && [ $HAVE_GREP -eq 0 ]; then
    for c in $CHECKS; do
        echo "check $c"
    done >>"$WORK/all"
fi
for file in "$HERE"/*.t; do
    [ -f "$file" ] || continue
    if [ $HAVE_GREP -eq 1 ] && ! grep -q -F -- "$GREP" "$file"; then
        continue
    fi
    echo "transcript $(basename "$file" .t)"
done >>"$WORK/all"
jobs_select "$FILTERS" <"$WORK/all" >"$WORK/jobs"
if [ ! -s "$WORK/jobs" ]; then
    what=$(jobs_filters_text "$FILTERS")
    [ $HAVE_GREP -eq 1 ] && what="$what${what:+, }--grep '$GREP'"
    [ $UPDATE -eq 1 ] && what="$what${what:+, }-u (transcripts only)"
    echo "tests/refactor/run.sh: no case matches ${what:-anything} (tests/refactor/run.sh -l lists the transcripts and checks)" >&2
    exit 2
fi
if [ $LIST -eq 1 ]; then
    cat "$WORK/jobs"
    exit 0
fi
[ -x "$COMPILER" ] || { echo "refactor/run.sh: no compiler at $COMPILER" >&2; exit 2; }
START=$(date +%s)
echo "refactor: $(grep -c '^transcript ' "$WORK/jobs") transcripts ($MODES), $(grep -c '^check ' "$WORK/jobs") checks, -j $JOBS"
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
                \$*) eval "\"\$COMPILER\" $args" >"$JW/out" 2>"$JW/err" </dev/null ;;
                *) eval "$args" >"$JW/out" 2>"$JW/err" </dev/null ;;
            esac
            rc=$?
            cat "$JW/out" "$JW/err" | sed -e "s|$WORK/bin/volec|volec|g" -e "s|$COMPILER|volec|g" -e "s|$dir|WORK|g" -e "s|$WORK|WORK|g" \
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
# The job of transcript $1: run in each mode, compared (and with -u,
# rewritten when it differs).
job_transcript() {
    name=$1
    file="$HERE/$name.t"
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
            else
                echo "pass $name ($mode)"
            fi
        elif [ -n "$xfail" ]; then
            echo "xfail $name ($mode): $xfail"
        else
            echo "FAIL $name ($mode): the transcript differs (< expected, > got; std's numbers as L:C, N):"
            diff "$WORK/$name.got.w" "$WORK/$name.got.g" | sed 's/^/    /' | head -40
        fi
    done
    rm -rf "$WORK/$name" "$WORK/cache-$name"
}

# The compiler's own source.
# The compiler's own source.
check() { # <name> <condition> <output>
    if [ "$2" = 1 ]; then
        echo "pass $1"
    else
        echo "FAIL $1:"
        printf '%s\n' "$3" | head -20 | sed 's/^/    /'
    fi
}
# The job of check $1 (one of CHECKS).
job_check() {
    unset VOLE_CACHE
    cd "$ROOT" || exit 2
    TAB=$(printf '\t')
    case "$1" in
        self_stats)
            # stats: every file of the compiler, largest first (the largest over 300
            # lines), a total.
            out=$("$COMPILER" query stats --over 300 2>&1)
            ok=0
            n=$(printf '%s\n' "$out" | grep -c "^[0-9]*${TAB}[0-9]*${TAB}compiler/src/[a-z_0-9/]*\.vl")
            [ "$n" -ge 40 ] && printf '%s\n' "$out" | head -1 | grep -q "^[0-9]*${TAB}[0-9]*${TAB}compiler/src/[a-z_0-9/]*\.vl${TAB}over\$" \
                && printf '%s\n' "$out" | grep -q "^[0-9]*${TAB}[0-9]*${TAB}total\$" \
                && printf '%s\n' "$out" | grep -q '^note query.over: [0-9]* files over 300 lines$' && ok=1
            check self_stats "$ok" "$(printf '%s\n' "$out" | head -8)"
            ;;
        self_stats_module)
            out=$("$COMPILER" query stats gvn 2>&1)
            ok=0
            printf '%s\n' "$out" | head -1 | grep -q "^# crate::middle::gvn${TAB}compiler/src/middle/gvn.vl${TAB}[0-9]* lines${TAB}[0-9]* items\$" \
                && printf '%s\n' "$out" | grep -q "^[0-9]*${TAB}fn${TAB}run_gvn\$" && ok=1
            check self_stats_module "$ok" "$(printf '%s\n' "$out" | head -5)"
            ;;
        self_deps)
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
            ;;
        self_unused)
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
            ;;
        self_impact)
            # impact: the calls of a function used in several files.
            # (0.29: sized_table; base::grow, the raw arrays' growth, has one file's
            # callers left)
            out=$("$COMPILER" query impact base::sized_table 2>&1)
            ok=0
            printf '%s\n' "$out" | head -1 | grep -q "^crate::base::sized_table${TAB}compiler/src/base/mod.vl:" \
                && printf '%s\n' "$out" | grep -q "^instances${TAB}[0-9]*${TAB}sized_table<" \
                && printf '%s\n' "$out" | grep -q "^total${TAB}[0-9]*${TAB}[0-9]*${TAB}[0-9]* files" && ok=1
            check self_impact "$ok" "$(printf '%s\n' "$out" | head -3)"
            ;;
        self_lint)
            # lint: the files over 300 lines, each with the deps of its module.
            out=$("$COMPILER" lint --max-lines 300 2>&1)
            rc=$?
            ok=0
            [ $rc = 1 ] && printf '%s\n' "$out" | head -1 | grep -q '^error lint.max-lines: compiler/src/[a-z_0-9/]*\.vl: [0-9]* lines (at most 300)$' \
                && printf '%s\n' "$out" | grep -q "^try: .* query deps crate::[a-z_0-9:]* --max-lines 300\$" && ok=1
            check self_lint "$ok" "$(printf '%s\n' "$out" | head -4)"
            ;;
        self_lint_ok)
            "$COMPILER" lint --max-lines 100000 >/dev/null 2>&1
            check self_lint_ok "$([ $? = 0 ] && echo 1)" "lint --max-lines 100000 failed"
            ;;
        self_check)
            # check: the compiler's source has no errors, quickly.
            # (0.29: with --deny=unsafe: an unsafe site without its comments and an
            # unsafe block with nothing unsafe inside are errors in the compiler's
            # source, each where it is; docs/unsafe-baseline.md's counts are 0)
            "$COMPILER" check --deny=unsafe compiler/src/main.vl >"$JW/check.out" 2>&1
            rc=$?
            # (0.18.1: a clean check says so in one line, with no warning)
            clean=$(sed -e 's/ ([0-9]* files, 0 shaders)$//' "$JW/check.out")
            # (0.29: the line ends with what was read, ` (N files, 0 shaders)`)
            check self_check "$([ $rc = 0 ] && [ "$clean" = "ok: 0 errors in compiler/src/main.vl" ] && echo 1)" "$(cat "$JW/check.out")"
            ;;
        same_output_identical)
            # same-output: the compiler against a copy of itself (identical), and
            # against a wrapper that changes one compilation (different).
            out=$("$COMPILER" same-output "$WORK/old-volec" --corpus examples --corpus tests/refactor/edits --work "$JW/so" 2>&1)
            ok=0
            printf '%s\n' "$out" | grep -q "^identical${TAB}[0-9]* compilations${TAB}[0-9]* programs${TAB}[0-9]* targets${TAB}-O0 -O1 -O2\$" && ok=1
            check same_output_identical "$ok" "$out"
            ;;
        same_output_in_path)
            # (0.16) OLD named without a `/`: looked up in $PATH.
            out=$(PATH="$WORK:$PATH" "$COMPILER" same-output old-volec --corpus tests/refactor/edits --work "$JW/so-path" 2>&1)
            ok=0
            printf '%s\n' "$out" | grep -q "^identical${TAB}" && ok=1
            check same_output_in_path "$ok" "$out"
            ;;
        same_output_own_paths)
            # (0.25.5) A compilation whose error has a `try:` line naming the compiler
            # (`try: OLD fix --suggested ...`): the two compilers' own paths are taken
            # as equal, so a copy of the compiler is identical.
            mkdir -p "$JW/sotry"
            printf 'fn count() -> i32 {\n    3\n}\n\nfn main() -> i32 {\n    coutn() - 3\n}\n' >"$JW/sotry/try.vl"
            out=$("$COMPILER" same-output "$WORK/old-volec" --corpus "$JW/sotry" --work "$JW/so-try" 2>&1)
            ok=0
            printf '%s\n' "$out" | grep -q "^identical${TAB}" \
                && "$WORK/old-volec" "$JW/sotry/try.vl" -o "$JW/sotry/out.s" --diagnostics=human 2>&1 \
                    | grep -q "try: $WORK/old-volec fix --suggested" && ok=1
            check same_output_own_paths "$ok" "$out"
            ;;
        same_output_differs)
            # (the wrapper that changes one compilation)
            cat >"$JW/differs.sh" <<EOS
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
            chmod +x "$JW/differs.sh"
            out=$("$COMPILER" same-output "$JW/differs.sh" --corpus examples --work "$JW/so2" 2>&1)
            rc=$?
            ok=0
            [ $rc = 1 ] && printf '%s\n' "$out" | head -1 | grep -q "^examples/md5/main.vl${TAB}[a-z0-9_-]*${TAB}-O1${TAB}asm line [0-9]*\$" \
                && printf '%s\n' "$out" | grep -q "^-${TAB}${TAB}// differs\$" \
                && printf '%s\n' "$out" | grep -q '^error same-output.differs: [0-9]* of [0-9]* compilations differ' \
                && printf '%s\n' "$out" | grep -q '^try: diff .*/old/out.s .*/new/out.s$' && ok=1
            check same_output_differs "$ok" "$out"
            ;;
        roundtrip)
            # (0.13) items moved to another module and back: every file as it was.
            out=$(sh "$HERE/roundtrip.sh" -c "$COMPILER" -n 40 2>&1)
            check roundtrip "$([ $? = 0 ] && echo 1)" "$out"
            ;;
        module_path_without_crate)
            # (0.15) A module path without `crate::`, as a user writes it: made,
            # then an item moved to it.
            mkdir -p "$JW/nocrate"
            printf 'fn helper() -> i64 {\n    2\n}\n\nfn main() -> i32 {\n    (helper() - 2) as i32\n}\n' >"$JW/nocrate/main.vl"
            out=$(cd "$JW/nocrate" && git init -q . 2>/dev/null; "$COMPILER" refactor new-module report 2>&1 \
                && "$COMPILER" refactor move helper --to report 2>&1 && "$COMPILER" query def report::helper 2>&1)
            ok=0
            printf '%s\n' "$out" | grep -q '^made module report' \
                && printf '%s\n' "$out" | grep -q "^crate::report::helper${TAB}report.vl:1:8${TAB}" && ok=1
            check module_path_without_crate "$ok" "$out"
            ;;
        rename_embed_body)
            # (0.26.0) rename and fix leave an embedded block's text as it is: a vole
            # `helper` renamed, the WGSL `helper` in the block not
            mkdir -p "$JW/embedren"
            printf 'embed wgsl K {\n    fn helper(x: f32) -> f32 { return x; }\n    @compute @workgroup_size(1)\n    fn main() { _ = helper(1.0); }\n}\n\nfn helper(x: i64) -> i64 {\n    x\n}\n\nfn main() -> i32 {\n    helper(0) as i32\n}\n' >"$JW/embedren/main.vl"
            out=$(cd "$JW/embedren" && git init -q . 2>/dev/null; "$COMPILER" refactor rename helper assist 2>&1 && "$COMPILER" fix 2>&1)
            ok=0
            sed -n 1,5p "$JW/embedren/main.vl" | grep -c helper | grep -q '^2$' \
                && grep -q '^fn assist(x: i64)' "$JW/embedren/main.vl" && grep -q '^    assist(0)' "$JW/embedren/main.vl" && ok=1
            check rename_embed_body "$ok" "$out
$(cat "$JW/embedren/main.vl")"
            ;;
        self_explain)
            # explain (0.13): every code the compiler's source can print has an
            # entry: the tools' codes (`c"query.no-match"`; 0.17: the own pass's,
            # `c"own.moved"`), the kinds of the
            # compiler's errors (ERR_KIND; 0.25.3: main.missing) and warnings and keyed errors (their
            # third argument); and every entry is such a code. (0.25.3: lex.* and
            # embed.*, text blocks and include_str; `embed.sh`, a script's name, is
            # not one. 0.26.0: gpu.* and wgsl.*, and std's own: the shader compiler's
            # `"wgsl.X"` and `error wgsl.target`, std::gpu's `gpu.X:` texts. 0.26.1: cell.*.
            # 0.27.2.1: opaque.*, `impl Trait` results'. 0.30.1: places.*, a body
            # the places builder could not build; thread.*, the compiler's own
            # thread, written at once by base::diag::say_main_stack.)
            {
                grep -rhoE --exclude-dir=.volec 'c"(query|edit|patch|undo|check|fix|lint|fmt|same-output|refactor|rewrite|explain|batch|conflict|try|test|probe|reduce|own|fuzz|distinct|contract|conv|syntax|sync|cell|extension|use|link|cli|lex|embed|unsafe|run|gpu|wgsl|field|attr|borrowck|opaque|places|thread)\.[a-z0-9_-]+"' \
                    compiler/src
                grep -rhoE '"wgsl\.[a-z]+"|error wgsl\.[a-z]+' compiler/std/gpu/wgsl | sed -e 's/^"\(.*\)"$/c"\1"/' -e 's/^error \(.*\)$/c"\1"/'
                grep -rhoE 'gpu\.[a-z]+:' compiler/std/gpu | sed -e 's/^\(.*\):$/c"\1"/'
                # (0.26.5: the static ERR_KIND is the context's field `pcx.err_kind`)
                grep -rhoE --exclude-dir=.volec '(ERR_KIND|err_kind) = c"[^"]*"' compiler/src
                grep -rhoE --exclude-dir=.volec 'report_(warning|error_once)\([^,]*, [^,]*, c"[^"]*"' compiler/src
                # (0.15: guide's codes, written into its own messages)
                grep -rhoE --exclude-dir=.volec '"(error|note) guide\.[a-z-]+' compiler/src | sed -e 's/^"[a-z]* \(.*\)$/c"\1"/'
                # (0.25.5: a build error printed whole, `error[time.instructions]`)
                grep -rhoE --exclude-dir=.volec 'c"error\[time\.[a-z0-9_-]+\]' compiler/src | sed -e 's/^c"error\[\(.*\)\]$/c"\1"/'
            } | sed -e 's/.*c"\([^"]*\)"$/\1/' | grep -v '^embed\.sh$' | sort -u >"$JW/codes"
            "$COMPILER" explain --list | sort >"$JW/explained"
            missing=$(comm -23 "$JW/codes" "$JW/explained")
            extra=$(comm -13 "$JW/codes" "$JW/explained")
            bad=
            while IFS= read -r code; do
                "$COMPILER" explain "$code" >"$JW/explain.out" 2>&1 \
                    && [ "$(sed -n 1p "$JW/explain.out")" != "" ] && grep -q '^fix: ' "$JW/explain.out" \
                    && grep -q '^example:$' "$JW/explain.out" || bad="$bad $code"
            done <"$JW/codes"
            check self_explain "$([ "$(wc -l <"$JW/codes")" -ge 90 ] && [ -z "$missing$extra$bad" ] && echo 1)" \
                "$(wc -l <"$JW/codes") codes; no entry:$(echo $missing); not a code:$(echo $extra); bad:$bad"
            ;;
        *) echo "FAIL $1: no such check" ;;
    esac
}
run_job() { # <transcript|check> <name> <number>
    JW="$WORK/job.$3"
    mkdir -p "$JW"
    case "$1" in
        transcript) job_transcript "$2" ;;
        check) job_check "$2" ;;
    esac
    rm -rf "$JW"
}

# (the compiler's copy the same_output checks compare it with)
grep -q '^check same_output' "$WORK/jobs" && cp "$COMPILER" "$WORK/old-volec"
jobs_run "$WORK/jobs" "$JOBS"
failed=$(jobs_count FAIL)
echo "refactor: $(jobs_count pass) passed, $(jobs_count xfail) xfail, $failed failed, $(($(date +%s) - START)) s$([ $UPDATE -eq 1 ] && echo " (-u: without the cache only, and no check; run again without -u)")"
[ "$failed" -eq 0 ] || exit 1
exit 0
