#!/bin/sh
# The tests of `volec query` (0.11). POSIX sh and awk only.
#
# usage: tests/query/run.sh [-c COMPILER] [-j JOBS] [-u] [--grep TEXT] [-l] [-n NAME] [FILTER...]
#
#   -c COMPILER   the volec binary (default: target/volec)
#   -j JOBS       (0.30) transcripts and checks run at once (default 1);
#                 the verdicts are the same for every JOBS
#   -u            rewrite the .q files that fail with the output they get
#                 now (the real numbers, std's too). (0.30) Only the
#                 transcripts run then, and only without the cache (the
#                 mode -u writes from): run again without -u for the
#                 cache mode and the checks
#   --grep TEXT   (0.30) only the transcripts whose file holds TEXT (a
#                 fixed string), and no check: `-u --grep query.no-match`
#                 rewrites the transcripts a changed message is in
#   -l            (0.30) list what would run, `transcript NAME` and
#                 `check NAME`, and run nothing
#   -n NAME       (0.30) only the transcript or check named NAME exactly
#                 (repeatable)
#   FILTER...     (0.30) only the transcripts (NAME.q) and the checks of
#                 the compiler's own source below whose name contains a
#                 FILTER (before 0.30: NAME, exactly, and transcripts
#                 only); several, and -n, select the union. Selecting
#                 nothing is an error (`no case matches`), not a pass.
#
# The first line is the plan (`query: N transcripts (off cache), M checks,
# -j J`); then each transcript's and check's result as it ends (0.30: not
# when the run ends); the last line counts them, with the seconds taken.
#
# Each tests/query/NAME.q is a transcript: a line `$ ARGS` runs
# `volec query ARGS` in tests/query (ARGS are split as the shell
# splits them: quote a name with spaces), with VOLE_ROOT set to
# NAME/main.vl when that directory exists (unset otherwise); the lines
# after it, up to the next `$` line, are its output: stdout, then stderr
# (the compiler's path in `try:` lines written `volec`), then `[exit N]`
# when N is not 0. Lines starting with `##` are comments (`#` starts
# the file headers of refs).
# A test passes when the transcript it makes is the file, comments aside,
# std's positions and counts compared normalized (0.25.3, tests/stdpos.awk:
# `<std>:L:C`), so that a std change breaks no transcript that is not
# about std; one with a line `## exact-std` compares them exactly.
#
# Then the compiler's own source, compiler/src/main.vl, is asked a few
# questions whose answers must be plausible (it changes too often for a
# transcript): a definition is found and shown, references are counted.
# (cache_used, the cache answering some lines of the transcripts, is
# checked when all of them ran: without a FILTER, -n, --grep or -u.)
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
. "$ROOT/tests/jobs.sh"
COMPILER="$ROOT/target/volec"
UPDATE=0
LIST=0
JOBS=1
GREP=
HAVE_GREP=0
FILTERS=
USAGE="usage: tests/query/run.sh [-c COMPILER] [-j JOBS] [-u] [--grep TEXT] [-l] [-n NAME] [FILTER...]"
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
        -*) echo "tests/query/run.sh: unknown option '$1'" >&2; echo "$USAGE" >&2; exit 2 ;;
        *) FILTERS="$FILTERS$1
"
            shift ;;
    esac
done
case "$JOBS" in
    ''|*[!0-9]*|0) echo "tests/query/run.sh: -j takes a number, 1 or more (got '$JOBS')" >&2; exit 2 ;;
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

# The checks besides the transcripts, in the order they run, the long
# ones first (job_check has an arm for each: tests/runner/run.sh compares
# the two).
CHECKS="effects_agree_effagree_host effects_agree_effagree_aarch64-linux effects_agree_effagree_x86_64-linux roundtrip_clash roundtrip_closures self_show self_refs_count self_refs_budget self_refs_in_file self_refs_in_module_limit self_refs_all self_callers self_def_variant self_items self_show_ambiguous self_line_max self_banners self_section self_grep self_grep_strings default_root std_items_no_program std_show_no_program std_def_in_repo std_show_by_file std_tree_checks self_examples self_similar"

# The jobs: every transcript and check, then the ones selected.
WORK=$(mktemp -d "${TMPDIR:-/tmp}/vole-query.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
trap 'exit 130' INT TERM
# (the checks first: the longest of them take minutes, and a long job
# that starts last runs alone at the end)
: >"$WORK/all"
if [ $UPDATE -eq 0 ] && [ $HAVE_GREP -eq 0 ]; then
    for c in $CHECKS; do
        echo "check $c"
    done >>"$WORK/all"
fi
for file in "$HERE"/*.q; do
    [ -f "$file" ] || continue
    if [ $HAVE_GREP -eq 1 ] && ! grep -q -F -- "$GREP" "$file"; then
        continue
    fi
    echo "transcript $(basename "$file" .q)"
done >>"$WORK/all"
jobs_select "$FILTERS" <"$WORK/all" >"$WORK/jobs"
if [ ! -s "$WORK/jobs" ]; then
    what=$(jobs_filters_text "$FILTERS")
    [ $HAVE_GREP -eq 1 ] && what="$what${what:+, }--grep '$GREP'"
    [ $UPDATE -eq 1 ] && what="$what${what:+, }-u (transcripts only)"
    echo "tests/query/run.sh: no case matches ${what:-anything} (tests/query/run.sh -l lists the transcripts and checks)" >&2
    exit 2
fi
# (cache_used: when every transcript ran in both modes)
CACHE_USED=0
[ -z "$FILTERS" ] && [ $HAVE_GREP -eq 0 ] && [ "$MODES" = "off cache" ] && CACHE_USED=1
if [ $LIST -eq 1 ]; then
    cat "$WORK/jobs"
    [ $CACHE_USED -eq 1 ] && echo "check cache_used"
    exit 0
fi
[ -x "$COMPILER" ] || { echo "query/run.sh: no compiler at $COMPILER" >&2; exit 2; }
START=$(date +%s)
echo "query: $(grep -c '^transcript ' "$WORK/jobs") transcripts ($MODES), $(($(grep -c '^check ' "$WORK/jobs") + CACHE_USED)) checks, -j $JOBS"

# One run of `volec query ARGS` (in $1, the line's ARGS), its output as
# the transcript has it, into $JW/run ($JW: the job's own directory).
run_line() {
    (
        cd "$HERE" || exit 1
        eval "set -- $1"
        "$COMPILER" query "$@" >"$JW/out" 2>"$JW/err"
        rc=$?
        # (`try:` lines name the compiler as it was run: `volec` here)
        cat "$JW/out" "$JW/err" | sed "s|$COMPILER|volec|g"
        [ $rc -eq 0 ] || echo "[exit $rc]"
    ) >"$JW/run"
}

# The transcript of test file $1 (its `$` lines run again), on stdout, in
# mode $2 (0.13): `off`, without the tools' cache; `cache`, each line run
# twice with a cache of the transcript's own ($JW/cache; 0.30: before,
# one for all the transcripts, which ran one after the other): the first
# run may make it, the second must answer the same, and from the cache
# when the first made it (VOLE_CACHE_TRACE says which).
transcript() {
    name=$(basename "$1" .q)
    if [ -d "$HERE/$name" ]; then
        VOLE_ROOT="$name/main.vl"
        export VOLE_ROOT
    else
        unset VOLE_ROOT
    fi
    grep '^\$ ' "$1" | while IFS= read -r line; do
        printf '%s\n' "$line"
        args=${line#\$ }
        if [ "$2" = off ]; then
            VOLE_CACHE=off run_line "$args"
            cat "$JW/run"
            continue
        fi
        : >"$JW/trace"
        VOLE_CACHE="$JW/cache" VOLE_CACHE_TRACE="$JW/trace" run_line "$args"
        mv "$JW/run" "$JW/run1"
        saved=$(grep -c '^save$' "$JW/trace")
        : >"$JW/trace"
        VOLE_CACHE="$JW/cache" VOLE_CACHE_TRACE="$JW/trace" run_line "$args"
        cat "$JW/run"
        cmp -s "$JW/run1" "$JW/run" || echo "[cache: the second run answered otherwise]"
        if [ "$saved" != 0 ]; then
            grep -q '^hit$' "$JW/trace" || echo "[cache: made, then not used]"
        fi
        grep '^hit$' "$JW/trace" >>"$JW/hits"
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
    file="$HERE/$name.q"
    : >"$JW/hits"
    for mode in $MODES; do
        transcript "$file" $mode >"$JW/$name.got"
        grep -v '^##' "$file" >"$JW/$name.want"
        if [ $UPDATE -eq 1 ] && [ $mode = off ] && ! same_transcript "$file" "$JW/$name.want" "$JW/$name.got"; then
            # (0.16: a failing transcript only, its `##` comments kept
            # above the `$` line they were above; 0.25.5: a line that
            # differs only in std's numbers kept as it was, tests/stdkeep.sh)
            if ! grep -q '^## exact-std' "$file"; then
                sh "$ROOT/tests/stdkeep.sh" "$JW/$name.want" "$JW/$name.got" >"$JW/$name.kept"
                cp "$JW/$name.kept" "$JW/$name.got"
            fi
            awk 'NR == FNR {
                    if ($0 ~ /^##/) { pend = pend $0 "\n" }
                    else if ($0 ~ /^\$ /) { c[++n] = pend; pend = "" }
                    next
                }
                /^\$ / { printf "%s", c[++k] }
                { print }
                END { printf "%s", pend }' "$file" "$JW/$name.got" >"$JW/$name.new"
            cp "$JW/$name.new" "$file"
            grep -v '^##' "$file" >"$JW/$name.want"
        fi
        if same_transcript "$file" "$JW/$name.want" "$JW/$name.got"; then
            echo "pass $name ($mode)"
        else
            echo "FAIL $name ($mode): the transcript differs (< expected, > got; std's numbers as L:C, N):"
            diff "$JW/$name.got.w" "$JW/$name.got.g" | sed 's/^/    /' | head -40
        fi
    done
    cp "$JW/hits" "$WORK/hits.$name"
    rm -rf "$JW/cache"
}

# The compiler's own source.
check() { # <name> <condition> <output>
    if [ "$2" = 1 ]; then
        echo "pass $1"
    else
        echo "FAIL $1:"
        printf '%s\n' "$3" | head -20 | sed 's/^/    /'
    fi
}

# Every name a tool prints is accepted back (0.15): the paths, positions
# (FILE:L:C, FILE:A-B, FILE:L:C: of a short diagnostic), enclosing items
# and modules that def, show, refs, callers, items, type and check print,
# and the symbols of the generated code (closures, instances; not the
# runtime's, nor std's statics: 0.20.0 names `vole.static.std.X` for a
# static of a std submodule, which `query def` does not take back yet, a
# 0.20.1 item; aarch64-linux's argv statics showed it; nor, 0.26.1, the
# places IR's drop shims, `vole.$drop.T`: glue with no item of its own;
# nor, 0.28.0, std's methods of the integer types, `vole.Ty.max`: the
# compiler's `#[builtin_impls]` text, `<builtin>`, which the tools do not
# index yet),
# each given to `query def` (positions and modules to `show` and `items`).
roundtrip() { # <program dir> <seed names...>
    prog=$1
    shift
    VOLE_ROOT="$prog/main.vl"
    export VOLE_ROOT
    {
        "$COMPILER" query def "$@" 2>/dev/null | awk -F "$TAB" '{ print "def " $1; print "show " $2 }'
        "$COMPILER" query show "$@" 2>/dev/null | awk -F "$TAB" '/^\/\/ [^ ]*\t/ { sub(/^\/\/ /, "", $1); print "def " $1; print "show " $2 }'
        "$COMPILER" query refs "$@" --all 2>/dev/null | awk -F "$TAB" '
            /^# / { file = substr($0, 3); next }
            { print "show " file ":" $1; if ($2 != "def") print "def " $3 }'
        "$COMPILER" query items 2>/dev/null | awk -F "$TAB" '{ print "items " $1; print "items " $2 }'
        "$COMPILER" check --diagnostics=short "$prog/main.vl" 2>&1 | awk '/^[^ ]*:[0-9]+:[0-9]+:/ { print "show " $1 }'
        "$COMPILER" "$prog/main.vl" -O0 -S -o "$JW/rt.s" >/dev/null 2>&1 \
            && awk '/^_?vole\.[^ \t]*:$/ && !/^_?vole\.rt\./ && !/^_?vole\.static\.std\./ && !/^_?vole\.\$drop\./ && !/^_?vole\.T[asilhtjmyx]\./ { sub(/:$/, ""); print "def " $0 }' "$JW/rt.s"
    } | sort -u >"$JW/rt.names"
    : >"$JW/rt.bad"
    n=0
    while read -r cmd name; do
        [ -n "$name" ] || continue
        n=$((n + 1))
        "$COMPILER" query "$cmd" "$name" >/dev/null 2>"$JW/rt.err" \
            || echo "query $cmd $name: $(head -1 "$JW/rt.err")" >>"$JW/rt.bad"
    done <"$JW/rt.names"
    unset VOLE_ROOT
    ok=0
    [ "$n" -ge 10 ] && [ ! -s "$JW/rt.bad" ] && ok=1
    check "roundtrip_$prog" "$ok" "$n names; $(cat "$JW/rt.bad")"
}
# (0.28.0) A set's text is the list its function may declare, no more
# and no less (the effects' rule: the lists are honest). For each
# function of program $1 named by a `//@ NAME` line, the answer of
# `query effects NAME`, written there as `#[effects(..)]`, is accepted by
# `volec check` (for target $2, or the host's), and the list without any
# one of its words (an allocator of `alloc(..)` is a word) is refused
# with an effect error. The set is the host's: where another target's
# differs, its check says so here.
effects_agree() { # <program dir> <host|TARGET>
    prog=$1
    target=
    [ "$2" = host ] || target="--target $2"
    mkdir -p "$JW/ea"
    : >"$JW/ea.bad"
    fns=0
    lists=0
    sed -n 's|^ *//@ ||p' "$prog/main.vl" >"$JW/ea.names"
    while IFS= read -r name; do
        fns=$((fns + 1))
        VOLE_CACHE=off "$COMPILER" query effects "$name" --root "$prog/main.vl" >"$JW/ea.set" 2>&1
        if [ "$(wc -l <"$JW/ea.set")" -ne 1 ] || ! grep -q "$TAB" "$JW/ea.set" \
            || grep -q '(unknown)' "$JW/ea.set"; then
            echo "$name: query effects answered: $(head -3 "$JW/ea.set")" >>"$JW/ea.bad"
            continue
        fi
        # (the lists: `=<TAB>LIST` the whole one, then `WORD<TAB>LIST`, LIST
        # without WORD)
        awk -F "$TAB" '
            function list(skip,   i, a, s, t) {
                a = ""
                for (i = 1; i <= na; i++) {
                    if (i != skip) a = a (a == "" ? "" : ", ") al[i]
                }
                s = (a == "" ? "" : "alloc(" a ")")
                if (any && skip != -1) s = "alloc"
                for (i = 1; i <= nw; i++) {
                    if (na + i != skip) s = s (s == "" ? "" : ", ") w[i]
                }
                return s
            }
            {
                t = $2
                na = 0; nw = 0; any = 0
                if (t ~ /^alloc\(/) {
                    # (the allocators, split at the commas outside <..>)
                    depth = 0; cur = ""
                    for (i = 7; i <= length(t); i++) {
                        c = substr(t, i, 1)
                        if (c == "<") depth++
                        if (c == ">") depth--
                        if (c == ")" && depth == 0) break
                        if (c == "," && depth == 0) { al[++na] = cur; cur = ""; i++; continue }
                        cur = cur c
                    }
                    al[++na] = cur
                    t = substr(t, i + 2)
                } else if (t ~ /^alloc( |$)/) {
                    any = 1
                    t = substr(t, 7)
                }
                if (t != "none" && t != "") nw = split(t, w, " ")
                print "=\t" list(0)
                if (any) print "alloc\t" list(-1)
                for (i = 1; i <= na; i++) print "alloc(" al[i] ")\t" list(i)
                for (i = 1; i <= nw; i++) print w[i] "\t" list(na + i)
            }' "$JW/ea.set" >"$JW/ea.lists"
        while IFS="$TAB" read -r word list; do
            lists=$((lists + 1))
            awk -v name="$name" -v list="$list" '
                /^ *\/\/@ / {
                    t = $0
                    sub(/^ *\/\/@ /, "", t)
                    if (t == name) {
                        sub(/\/\/@ .*/, "")
                        print $0 "#[effects(" list ")]"
                        next
                    }
                }
                { print }' "$prog/main.vl" >"$JW/ea/main.vl"
            # shellcheck disable=SC2086
            VOLE_CACHE=off "$COMPILER" check $target "$JW/ea/main.vl" >"$JW/ea.out" 2>&1
            rc=$?
            if [ "$word" = "=" ]; then
                [ $rc -eq 0 ] || echo "$name: #[effects($list)], the query's answer, is refused: $(grep 'error' "$JW/ea.out" | head -2)" >>"$JW/ea.bad"
            elif [ $rc -eq 0 ] || ! grep -q 'error\[effect\]' "$JW/ea.out"; then
                echo "$name: #[effects($list)], the query's answer without '$word', is not refused with an effect error: $(grep 'error' "$JW/ea.out" | head -2)" >>"$JW/ea.bad"
            fi
        done <"$JW/ea.lists"
    done <"$JW/ea.names"
    ok=0
    [ "$fns" -ge 10 ] && [ "$lists" -gt "$fns" ] && [ ! -s "$JW/ea.bad" ] && ok=1
    check "effects_agree_${prog}_$2" "$ok" "$fns functions, $lists lists; $(cat "$JW/ea.bad")"
}
# The job of check $1 (one of CHECKS).
job_check() {
    cd "$ROOT" || exit 2
    unset VOLE_ROOT
    # (the checks' queries of the compiler's source share a cache of the
    # run's own, as when they ran one after the other)
    VOLE_CACHE="$WORK/cache-checks"
    export VOLE_CACHE
    TAB=$(printf '\t')
    case "$1" in
        self_show)
            out=$("$COMPILER" query show gvn::run_gvn compiler/src/main.vl 2>&1)
            ok=0
            printf '%s\n' "$out" | head -1 | grep -q "^// crate::middle::gvn::run_gvn${TAB}compiler/src/middle/gvn.vl:[0-9]*-[0-9]*${TAB}effects: [A-Za-z(), ]*\$" \
                && printf '%s\n' "$out" | grep -q '^pub fn run_gvn(' && ok=1
            check self_show "$ok" "$out"
            ;;
        self_refs_count)
            out=$("$COMPILER" query refs --count crate::middle::gvn::run_gvn compiler/src/main.vl 2>&1)
            ok=0
            [ "$out" -ge 3 ] 2>/dev/null && ok=1
            check self_refs_count "$ok" "$out"
            ;;
        self_refs_budget)
            # (the root found by default: ./compiler/src/main.vl)
            # More refs than the budget (60): a summary per file, and how to narrow.
            out=$("$COMPILER" query refs IntVec::push 2>"$JW/err")
            err=$(cat "$JW/err")
            ok=0
            n=$(printf '%s\n' "$out" | grep -c "^compiler/src/[a-z_0-9/]*\.vl${TAB}[0-9]*\$")
            [ "$n" -ge 10 ] && [ "$n" = "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" ] \
                && printf '%s\n' "$err" | head -1 | grep -q '^note query.truncated: [0-9]* refs in [0-9]* files$' \
                && [ "$(printf '%s\n' "$err" | grep -c '^try: .* query refs IntVec::push --')" = 3 ] && ok=1
            check self_refs_budget "$ok" "$(printf '%s\n' "$out" "$err" | tail -6)"
            ;;
        self_refs_in_file)
            # (0.29: buf_reserve, which base/mod.vl still calls; IntVec::push has no
            # caller left there)
            out=$("$COMPILER" query refs base::buf_reserve --in compiler/src/base/mod.vl 2>&1)
            ok=0
            n=$(printf '%s\n' "$out" | grep -c "^[0-9]*:[0-9]*${TAB}call${TAB}base::[A-Za-z_:]*${TAB}")
            [ "$n" -ge 1 ] && printf '%s\n' "$out" | head -1 | grep -q '^# compiler/src/base/mod.vl$' \
                && printf '%s\n' "$out" | grep -q "^[0-9]*:[0-9]*${TAB}def${TAB}pub fn buf_reserve(" && ok=1
            check self_refs_in_file "$ok" "$(printf '%s\n' "$out" | head -5)"
            ;;
        self_refs_in_module_limit)
            out=$("$COMPILER" query refs ir_val --in gvn --limit 5 2>&1)
            ok=0
            [ "$(printf '%s\n' "$out" | grep -cE "^[0-9]*:[0-9]*${TAB}(call|use)${TAB}middle::gvn")" = 5 ] \
                && printf '%s\n' "$out" | grep -q '^note query.truncated: showing 5 of [0-9]* refs$' && ok=1
            check self_refs_in_module_limit "$ok" "$out"
            ;;
        self_refs_all)
            n=$("$COMPILER" query refs IntVec::push --all 2>/dev/null | grep -c "^[0-9]*:[0-9]*${TAB}")
            ok=0
            [ "$n" -ge 100 ] && ok=1
            check self_refs_all "$ok" "$n"
            ;;
        self_callers)
            out=$("$COMPILER" query callers check_program 2>&1)
            ok=0
            printf '%s\n' "$out" | grep -q "^[0-9]*:[0-9]*${TAB}call${TAB}gen0::gen::compile_program${TAB}" && ok=1
            check self_callers "$ok" "$out"
            ;;
        self_def_variant)
            out=$("$COMPILER" query def NodeKind::Fn 2>&1)
            ok=0
            [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 1 ] && printf '%s\n' "$out" | grep -q "^crate::front::ast::NodeKind::Fn${TAB}compiler/src/front/ast.vl:[0-9]*:[0-9]*${TAB}variant${TAB}Fn\$" && ok=1
            check self_def_variant "$ok" "$out"
            ;;
        self_items)
            out=$("$COMPILER" query items gvn 2>&1)
            ok=0
            printf '%s\n' "$out" | head -1 | grep -q "^# crate::middle::gvn${TAB}compiler/src/middle/gvn.vl\$" \
                && printf '%s\n' "$out" | grep -q "^[0-9]*${TAB}fn${TAB}pub fn run_gvn(cx: &mut FnCtx<Comp>, fi: i64, pcx: &Ctx<Comp>) -> bool\$" && ok=1
            check self_items "$ok" "$(printf '%s\n' "$out" | head -5)"
            ;;
        self_show_ambiguous)
            # More than 5 definitions for show: their paths, and an error.
            out=$("$COMPILER" query show .name 2>&1)
            rc=$?
            ok=0
            [ $rc = 1 ] && printf '%s\n' "$out" | grep -q '^crate::front::modules::Module.name$' \
                && printf '%s\n' "$out" | grep -q "^error query.ambiguous: [0-9]* definitions match '.name'; showing paths only\$" \
                && printf '%s\n' "$out" | grep -q '^try: .* query show crate::[a-z_0-9:]*::[A-Za-z]*\.name$' && ok=1
            check self_show_ambiguous "$ok" "$out"
            ;;
        self_line_max)
            # A long source line is cut at 100 bytes, with `…`.
            out=$("$COMPILER" query refs ir_val --in vectorize --all 2>&1 | awk -F "$TAB" 'length($3) > 100')
            ok=0
            [ -z "$out" ] && ok=1
            check self_line_max "$ok" "$out"
            ;;
        self_banners)
            # Banners and text search (0.13).
            out=$("$COMPILER" query items gvn --comments 2>&1)
            ok=0
            printf '%s\n' "$out" | grep -q "^[0-9]*-[0-9]*${TAB}section${TAB}The value table\$" && ok=1
            check self_banners "$ok" "$(printf '%s\n' "$out" | head -5)"
            ;;
        self_section)
            out=$("$COMPILER" query show gvn::section 'value table' 2>&1)
            ok=0
            printf '%s\n' "$out" | head -1 | grep -q "^// crate::middle::gvn::section The value table${TAB}compiler/src/middle/gvn.vl:[0-9]*-[0-9]*\$" \
                && [ "$(printf '%s\n' "$out" | sed -n 2p)" = "// ---- The value table ----" ] && ok=1
            check self_section "$ok" "$(printf '%s\n' "$out" | head -3)"
            ;;
        self_grep)
            out=$("$COMPILER" query grep 'fn run_gvn(' 2>&1)
            ok=0
            printf '%s\n' "$out" | grep -q "^[0-9]*:[0-9]*${TAB}code${TAB}middle::gvn::run_gvn${TAB}pub fn run_gvn(" && ok=1
            check self_grep "$ok" "$out"
            ;;
        self_grep_strings)
            n=$("$COMPILER" query grep 'query.no-match' --strings --in compiler/src/tools/ --count 2>&1)
            ok=0
            [ "$n" -ge 3 ] 2>/dev/null && ok=1
            check self_grep_strings "$ok" "$n"
            ;;
        default_root)
            # (./main.vl, found by default)
            out=$(cd "$HERE/clash" && "$COMPILER" query def a::helper 2>&1)
            ok=0
            [ "$out" = "crate::a::helper${TAB}a.vl:2:8${TAB}fn${TAB}pub fn helper() -> i64${TAB}effects: none" ] && ok=1
            check default_root "$ok" "$out"
            ;;
        std_items_no_program)
            # std where there is no program (0.15): its API by `items std` (no
            # private item), an item by a name std defines. (0.20: all of it, past the
            # default budget: std::io comes after std::slice. 0.28: the rust edition's
            # std, named until the edition is the only one.)
            mkdir -p "$JW/empty"
            out=$(cd "$JW/empty" && "$COMPILER" query items std --budget 40000 2>&1)
            ok=0
            [ "$(printf '%s\n' "$out" | wc -l)" -ge 100 ] && printf '%s\n' "$out" | head -1 | grep -q "^# std${TAB}<std>\$" \
                && printf '%s\n' "$out" | grep -q "${TAB}pub fn read_line<A: Allocator>(&self, buf: &mut String<A>) -> Result<usize>\$" \
                && ! printf '%s\n' "$out" | grep -q 'fn malloc' && ok=1
            check std_items_no_program "$ok" "$(printf '%s\n' "$out" | head -5)"
            ;;
        std_show_no_program)
            mkdir -p "$JW/empty"
            # (0.17: a name outside the prelude, which needs no `use`)
            out=$(cd "$JW/empty" && "$COMPILER" query show FixedBuf::used 2>&1)
            ok=0
            printf '%s\n' "$out" | head -2 | grep -q '^// use std::alloc::FixedBuf;$' && ok=1
            check std_show_no_program "$ok" "$(printf '%s\n' "$out" | head -5)"
            ;;
        std_def_in_repo)
            # (0.17) In the repository, std's items are where its files have them,
            # every function of std checks with them, and the "add an X" queries
            # answer: `query examples` for every kind (its items still exist),
            # `query similar`.
            out=$(env -u VOLE_STD_TREE "$COMPILER" query def str::trim 2>&1)
            loc=$(printf '%s\n' "$out" | awk -F "$TAB" '$1 == "str::trim" { print $2 }')
            ok=0
            case "$loc" in compiler/std/*.vl:*) ok=1 ;; esac
            check std_def_in_repo "$ok" "$out"
            ;;
        std_show_by_file)
            # (std_def_in_repo's place, asked for again: this check runs by itself)
            out=$(env -u VOLE_STD_TREE "$COMPILER" query def str::trim 2>&1)
            loc=$(printf '%s\n' "$out" | awk -F "$TAB" '$1 == "str::trim" { print $2 }')
            out=$(env -u VOLE_STD_TREE "$COMPILER" query show "${loc%:*}" 2>&1)
            ok=0
            printf '%s\n' "$out" | head -1 | grep -q '^// str::trim' && ok=1
            check std_show_by_file "$ok" "$(printf '%s\n' "$out" | head -3)"
            ;;
        std_tree_checks)
            out=$("$COMPILER" check --std-tree compiler/std 2>&1)
            rc=$?
            ok=0
            # (0.18.1: a clean check says so in one line; 0.29: with no warning: the
            # compiler's source has no unsafe site without its comments)
            clean=$(printf '%s\n' "$out" | sed -e 's/ ([0-9]* files, 0 shaders)$//')
            # (0.29: the line ends with what was read, ` (N files, 0 shaders)`)
            [ $rc -eq 0 ] && [ "$clean" = "ok: 0 errors in compiler/src/main.vl" ] && printf '%s\n' "$out" | grep -q '^ok: .* in compiler/src/main.vl ([0-9]* files, 0 shaders)$' && ok=1
            check std_tree_checks "$ok" "$out"
            ;;
        self_examples)
            bad=""
            for kind in $("$COMPILER" query examples | cut -f1); do
                "$COMPILER" query examples "$kind" >"$JW/ex.out" 2>"$JW/ex.err" || bad="$bad $kind"
                [ -s "$JW/ex.err" ] && bad="$bad $kind($(head -1 "$JW/ex.err"))"
            done
            n=$("$COMPILER" query examples | wc -l)
            ok=0
            [ -z "$bad" ] && [ "$n" -ge 8 ] && ok=1
            check self_examples "$ok" "$n kinds; failing:$bad"
            ;;
        self_similar)
            out=$("$COMPILER" query similar std::mem::swap crate::middle::fold::combine_not 2>&1)
            ok=0
            [ "$(printf '%s\n' "$out" | grep -c '^// 3 of [0-9]* fns like ')" = 2 ] && ok=1
            check self_similar "$ok" "$(printf '%s\n' "$out" | grep '^// ' | head -8)"
            ;;
        roundtrip_clash)
            cd "$HERE" || exit 2
            roundtrip clash a::helper geom::V2::len main Shape::Circle MyVec::push
            ;;
        roundtrip_closures)
            cd "$HERE" || exit 2
            roundtrip closures double apply main
            ;;
        effects_agree_effagree_host)
            cd "$HERE" || exit 2
            effects_agree effagree host
            ;;
        effects_agree_effagree_aarch64-linux)
            cd "$HERE" || exit 2
            effects_agree effagree aarch64-linux
            ;;
        effects_agree_effagree_x86_64-linux)
            cd "$HERE" || exit 2
            effects_agree effagree x86_64-linux
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

jobs_run "$WORK/jobs" "$JOBS"
# (the cache was made and used: by some lines of every program)
if [ $CACHE_USED -eq 1 ]; then
    hits=$(cat "$WORK"/hits.* 2>/dev/null | grep -c hit)
    if [ "$hits" -ge 10 ]; then
        echo "pass cache_used ($hits lines)" | tee "$WORK/res/cache_used"
    else
        echo "FAIL cache_used: the cache answered $hits lines" | tee "$WORK/res/cache_used"
    fi
fi
failed=$(jobs_count FAIL)
echo "query: $(jobs_count pass) passed, $failed failed, $(($(date +%s) - START)) s$([ $UPDATE -eq 1 ] && echo " (-u: without the cache only, and no check; run again without -u)")"
[ "$failed" -eq 0 ] || exit 1
exit 0
