#!/bin/sh
# The tests a change touches (0.25.2), for an agent's checks before it
# reports (AGENTS.md, tier 2): the paths changed since BASE (`git diff
# --name-only BASE...HEAD`, plus the work tree's changes to the files
# git tracks, a new file once it is added) are looked up in tests/affected.map, which names for each path prefix
# the tests/run.sh filters (cases, suites, checks), example builds and
# other test scripts that would see the change; the union runs, in one
# tests/run.sh per level. A changed test runs itself; a path no rule
# names gets the smoke set, never nothing.
#
# (0.29) A file git does not track is not the branch's until it is added
# (`git add`): a leftover of another run (an output directory, a tool's
# temporary file under compiler/src) made the plan of a branch that
# changed one example 3079 of 5270 cases. Such files are named in the
# plan, not counted; --untracked counts them (a new test not added yet).
# The index is what says a file belongs to the branch: a rule that
# guesses (a file beside a changed one) would have counted the temporary
# file, which sat beside the file it was made for.
#
# (0.30) The changed items: for a changed .vl of compiler/std or
# compiler/src, the names of the functions and types the change's lines
# are in (`names:` in the plan). A std item's name adds the transcripts
# (tests/query, tests/refactor: `query:=NAME`), the examples' sessions
# (=walkthrough) and the book (=book) that print it: std's positions are
# compared normalized there, but an item's name, signature or message is
# not. --narrow uses the names for the cases too.
#
# usage: tests/affected.sh [BASE] [-O LEVEL]... [--list] [--narrow] [--path PATH]... [--linux] [--head REV] [--untracked] [-c COMPILER] [-j JOBS]
#
#   BASE          what the change is against (default: the release-*
#                 branch, or main, whose merge-base with HEAD is the
#                 nearest)
#   -O LEVEL      a level to run at (0, 1 or 2; repeatable, or -O 0,2;
#                 default -O0 and -O2): the cases and the suites that take
#                 a level at each, the other suites at the first only
#   --list        print the plan, each item with the paths and the rule
#                 that put it there, and its size; run nothing
#   --narrow      (0.30) for a plan too large to run (over 600 cases:
#                 a front end or std change is "most of the suite"): the
#                 changed tests, the rules' own items (not their sets, nor
#                 a filter of more than 200 cases), the cases, transcripts
#                 and sessions that name a changed item (at most 40 cases
#                 a name and 300 in all; a name more than 400 cases hold
#                 is left out) and the smoke set. The plan says how it chose, name by
#                 name. It is a sample, said so in the report: the
#                 integrator's full suite sees the rest
#   --path PATH   (0.30) the plan as if PATH had changed (repeatable),
#                 instead of the branch's changes: what a change to a
#                 file would run (`--list --path compiler/src/back/dwarf.vl`)
#   --linux       also run the plan in the aarch64-linux container
#                 (bootstrap/aarch64-linux-check.sh --slice; docker must
#                 run): for platform-relevant changes (the map's +linux;
#                 --list says when)
#   --head REV    the change is BASE...REV, without the work tree (an
#                 integrator's look at another branch; the tests named
#                 are this tree's)
#   --untracked   count the files git does not track (and does not
#                 ignore) as changes too; without it the plan names them
#                 and leaves them out
#   -c COMPILER   the compiler (default target/volec)
#   -j JOBS       tests/run.sh's -j
#
# Exits 1 when something failed, 0 otherwise; the last lines say what
# ran and how it went.
set -u
LC_ALL=C
export LC_ALL

ROOT=$(cd "$(dirname "$0")/.." && pwd)
MAP="$ROOT/tests/affected.map"
cd "$ROOT" || exit 2
BASE=""
LEVELS=""
LIST=0
LINUX=0
COMPILER="$ROOT/target/volec"
JOBS=""
HEAD_REV=""
UNTRACKED=0
NARROW=0
PATHS=""
NARROW_OVER=600     # a plan over this many cases: --narrow is offered
NAME_CASES=40       # --narrow: the cases one name adds, at most
NAME_COMMON=400     # a name more cases hold says nothing
NAMES_TOTAL=300     # --narrow: the cases all the names add, at most
FILTER_CASES=200    # --narrow: a rule's filter of more cases is left out

die() {
    echo "tests/affected.sh: $*" >&2
    exit 2
}
while [ $# -gt 0 ]; do
    case "$1" in
        -O) [ $# -ge 2 ] || die "-O needs a level"; LEVELS="$LEVELS $(echo "$2" | tr ',' ' ')"; shift 2 ;;
        -O[0-2]) LEVELS="$LEVELS ${1#-O}"; shift ;;
        --list) LIST=1; shift ;;
        --linux) LINUX=1; shift ;;
        --head) [ $# -ge 2 ] || die "--head needs a revision"; HEAD_REV=$2; shift 2 ;;
        --untracked) UNTRACKED=1; shift ;;
        --narrow) NARROW=1; shift ;;
        --path) [ $# -ge 2 ] || die "--path needs a path"; PATHS="$PATHS$2
"; shift 2 ;;
        -c) [ $# -ge 2 ] || die "-c needs a compiler"; COMPILER=$2; shift 2 ;;
        -j) [ $# -ge 2 ] || die "-j needs a number"; JOBS=$2; shift 2 ;;
        -h|--help) sed -n '2,/^set -u/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
        -*) die "unknown option '$1' (tests/affected.sh -h)" ;;
        *) [ -z "$BASE" ] || die "one BASE only ('$BASE', '$1')"; BASE=$1; shift ;;
    esac
done
[ -n "$LEVELS" ] || LEVELS="0 2"
for l in $LEVELS; do
    case "$l" in 0|1|2) ;; *) die "-O $l: the levels are 0, 1 and 2" ;; esac
done
case "$COMPILER" in /*) ;; *) COMPILER="$ROOT/$COMPILER" ;; esac

# ---- the base and the changed paths ----

HEAD_IS=${HEAD_REV:-HEAD}
git rev-parse -q --verify "$HEAD_IS^{commit}" >/dev/null || die "no commit '$HEAD_IS'"
if [ -z "$BASE" ]; then
    current=$(git rev-parse --abbrev-ref "$HEAD_IS" 2>/dev/null)
    BASE=$(git for-each-ref --format='%(refname:short)' 'refs/heads/release-*' refs/heads/main | while read -r b; do
        [ "$b" = "$current" ] && continue
        mb=$(git merge-base "$b" "$HEAD_IS" 2>/dev/null) || continue
        echo "$(git rev-list --count "$mb..$HEAD_IS") $b"
    done | sort -n -k1,1 | head -1 | cut -d' ' -f2)
    [ -n "$BASE" ] || BASE=main
fi
git rev-parse -q --verify "$BASE^{commit}" >/dev/null || die "no commit '$BASE'"
MB=$(git merge-base "$BASE" "$HEAD_IS") || die "no merge-base of $BASE and $HEAD_IS"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/vole-affected.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
trap 'exit 130' INT TERM

# (the files git does not track: named, and counted only with --untracked)
: >"$WORK/untracked"
[ -n "$HEAD_REV" ] || git ls-files --others --exclude-standard | sed '/^$/d' >"$WORK/untracked"
NUNTRACKED=$(wc -l <"$WORK/untracked" | tr -d ' ')
{
    git diff --name-only "$MB" "$HEAD_IS"
    if [ -z "$HEAD_REV" ]; then
        git diff --name-only HEAD
        [ $UNTRACKED = 1 ] && cat "$WORK/untracked"
    fi
} | sort -u | sed '/^$/d' >"$WORK/changed"
# (0.30, --path: those paths, as if they had changed)
if [ -n "$PATHS" ]; then
    printf '%s' "$PATHS" | sort -u | sed '/^$/d' >"$WORK/changed"
    : >"$WORK/untracked"
    NUNTRACKED=0
fi
NCHANGED=$(wc -l <"$WORK/changed" | tr -d ' ')

# ---- the changed items' names (0.30) ----

# `KIND NAME` (KIND std or src) for each function or type of a changed
# .vl of compiler/std or compiler/src that the change's lines are in
# (the generated files aside): the item a changed line of the new text is
# in (the last `fn`, `struct`, ... line above it), and an item whose own
# first line was removed.
: >"$WORK/names"
grep -E '^compiler/(std|src)/.*\.vl$' "$WORK/changed" \
    | grep -v -e '^compiler/src/front/stdsrc\.vl$' -e '^compiler/src/guide/text/' | while IFS= read -r p; do
    case "$p" in compiler/std/*) kind=std ;; *) kind=src ;; esac
    if [ -n "$HEAD_REV" ]; then
        git diff -U0 "$MB" "$HEAD_REV" -- "$p" >"$WORK/item.diff" 2>/dev/null
        git show "$HEAD_REV:$p" >"$WORK/item.new" 2>/dev/null || : >"$WORK/item.new"
    else
        git diff -U0 "$MB" -- "$p" >"$WORK/item.diff" 2>/dev/null
        cat "$p" >"$WORK/item.new" 2>/dev/null || : >"$WORK/item.new"
    fi
    awk -v kind="$kind" -v diff="$WORK/item.diff" '
        function item(l,   t) {
            t = l
            sub(/^[ \t]*/, "", t)
            sub(/^pub(\([a-z]+\))?[ \t]+/, "", t)
            while (t ~ /^(unsafe|const|extern)[ \t]+/ && t !~ /^const[ \t]+[A-Z_]/) {
                sub(/^[a-z]+[ \t]+/, "", t)
                sub(/^"[A-Za-z]*"[ \t]+/, "", t)
            }
            if (t !~ /^(fn|struct|enum|trait|union|type|const|static)[ \t]+/) return ""
            sub(/^[a-z]+[ \t]+/, "", t)
            sub(/^mut[ \t]+/, "", t)
            if (!match(t, /^[A-Za-z_][A-Za-z0-9_]*/)) return ""
            return substr(t, 1, RLENGTH)
        }
        BEGIN {
            any = 0
            while ((getline l < diff) > 0) {
                any = 1
                if (l ~ /^@@ /) {
                    split(l, f, " ")
                    r = f[3]
                    sub(/^\+/, "", r)
                    n = split(r, g, ",")
                    from = g[1] + 0
                    len = (n > 1) ? g[2] + 0 : 1
                    if (len == 0) { ch[from] = 1; ch[from + 1] = 1 }
                    for (i = 0; i < len; i++) ch[from + i] = 1
                } else if (l ~ /^-/ && l !~ /^---/) {
                    name = item(substr(l, 2))
                    if (name != "") print kind, name
                }
            }
            # (a file with no difference listed that is here: a new one,
            # counted with --untracked: all of it)
            whole = !any
        }
        {
            name = item($0)
            if (name != "") cur = name
            if ((whole || (NR in ch)) && cur != "") print kind, cur
        }' "$WORK/item.new"
done | awk 'length($2) >= 3 && $2 != "main"' | sort -u >"$WORK/names"

# Where each name is: `NAME FILE` for the cases' files, the transcripts
# (and their programs), the examples' READMEs with a session and the
# book's chapters that hold it as a word.
: >"$WORK/namehits"
if [ -s "$WORK/names" ]; then
    # shellcheck disable=SC2046
    awk -v names="$WORK/names" '
        BEGIN { while ((getline l < names) > 0) { split(l, f, " "); want[f[2]] = 1 } }
        {
            line = $0
            gsub(/[^A-Za-z0-9_]+/, " ", line)
            n = split(line, w, " ")
            for (i = 1; i <= n; i++)
                if ((w[i] in want) && !((w[i], FILENAME) in seen)) { seen[w[i], FILENAME] = 1; print w[i], FILENAME }
        }' $(ls tests/run/*.vl tests/run/*/*.vl tests/query/*.q tests/query/*/*.vl tests/refactor/*.t tests/refactor/*/*.vl \
            book/[0-9][0-9]-*.md 2>/dev/null; grep -l '^```console' examples/*/*/README.md 2>/dev/null) /dev/null >"$WORK/namehits"
fi
# The transcripts and sessions that print a changed std item, for the
# plan: `query:=T`, `refactor:=T`, =walkthrough, =book.
: >"$WORK/nameplan"
# (a name more than $NAME_COMMON cases hold, `new` or `len`, says nothing
# of where the change shows: left out, and said)
awk -v max="$NAME_COMMON" '$2 ~ /^tests\/run\// { n[$1]++ } END { for (k in n) if (n[k] > max) print k }' "$WORK/namehits" | sort >"$WORK/common"
awk '$1 == "std" { print $2 }' "$WORK/names" >"$WORK/stdnames"
awk -v std="$WORK/stdnames" -v common="$WORK/common" '
    BEGIN { while ((getline l < std) > 0) is[l] = 1; while ((getline l < common) > 0) delete is[l] }
    !($1 in is) { next }
    {
        f = $2
        if (f ~ /^tests\/(query|refactor)\//) {
            split(f, part, "/")
            t = part[3]
            sub(/\.[qt]$/, "", t)
            print part[2] ":=" t
        } else if (f ~ /^book\//) print "=book"
        else if (f ~ /^examples\//) print "=walkthrough"
    }' "$WORK/namehits" | sort -u >"$WORK/nameplan.all"
# (a transcript's program names it: only when the transcript exists)
while IFS= read -r np; do
    case "$np" in
        query:=*) [ -f "tests/query/${np#query:=}.q" ] && echo "$np" ;;
        refactor:=*) [ -f "tests/refactor/${np#refactor:=}.t" ] && echo "$np" ;;
        *) echo "$np" ;;
    esac
done <"$WORK/nameplan.all" >"$WORK/nameplan"

# ---- the rules ----

# Each changed path with its rule, the rule's items (sets expanded) and
# its reason: `path|prefix|items|why|items as written` (`|` is in no
# path or rule).
awk -v changed="$WORK/changed" '
    function expand(items,    n, a, i, out, s) {
        n = split(items, a, " ")
        out = ""
        for (i = 1; i <= n; i++) {
            s = a[i]
            if (s ~ /^@/ && (substr(s, 2) in sets)) {
                if (depth[s]++ > 5) continue
                out = out " " expand(sets[substr(s, 2)])
                depth[s]--
            } else
                out = out " " s
        }
        return out
    }
    {
        line = $0
        why = ""
        k = index(line, "#")
        if (k > 0) { why = substr(line, k + 1); line = substr(line, 1, k - 1) }
        sub(/^[ \t]+/, "", why)
        if (split(line, f, /[ \t]+/) == 0 || f[1] == "") next
        if (f[1] == "set") { s = ""; for (i = 3; i in f; i++) s = s " " f[i]; sets[f[2]] = s; next }
        if (f[1] == "cmd") next
        s = ""
        for (i = 2; i in f; i++) if (f[i] != "") s = s " " f[i]
        n++
        prefix[n] = f[1]; items[n] = s; reason[n] = why
        delete f
    }
    END {
        while ((getline p < changed) > 0) {
            best = 0; bl = -1
            for (r = 1; r <= n; r++) {
                if (prefix[r] == "*") { if (bl < 0) { best = r; bl = 0 } continue }
                L = length(prefix[r])
                if (substr(p, 1, L) == prefix[r] && L > bl) { best = r; bl = L }
            }
            e = expand(items[best])
            gsub(/^ +| +$/, "", e)
            raw = items[best]
            gsub(/^ +| +$/, "", raw)
            printf "%s|%s|%s|%s|%s\n", p, prefix[best], e, reason[best], raw
        }
    }' "$MAP" >"$WORK/rules"

# (0.25.5) The newest release built in a bootstrap cache (this tree's,
# the main checkout's), not HEAD's own: what the gate's compile-cost row
# compares with; empty when none is built.
previous_release() {
    head=$(git rev-parse HEAD 2>/dev/null | cut -c1-12)
    common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
    caches="$ROOT/target/bootstrap"
    [ -z "$common" ] || caches="$caches $(dirname "$common")/target/bootstrap"
    found=""
    for tag in $(sh bootstrap/release-tags.sh 2>/dev/null); do
        for b in $caches; do
            for p in "$b"/*/"$tag"-*/volec; do
                [ -x "$p" ] || continue
                case "$p" in *-"$head"/volec) continue ;; esac
                found=$p
            done
        done
    done
    echo "$found"
}
PREVIOUS=""

# The command of a `cmd NAME ...` line, with @C the compiler and (0.25.5)
# @P the previous release (previous_release).
map_cmd() {
    if [ -z "$PREVIOUS" ] && grep -q "^cmd $1 .*@P" "$MAP"; then
        PREVIOUS=$(previous_release)
        PREVIOUS=${PREVIOUS:-none}
    fi
    awk -v n="$1" '$1 == "cmd" && $2 == n { $1 = ""; $2 = ""; sub(/^ +/, ""); print; exit }' "$MAP" \
        | sed "s|@C|$COMPILER|g; s|@P|$PREVIOUS|g"
}

# A case's filter from its file: tests/run/X.vl is =X, tests/run/D/... is
# =D (a program of several modules), tests/examples/X.test =example_X.
case_of() {
    case "$1" in
        tests/run/*/*) d=${1#tests/run/}; d=${d%%/*}; [ -f "tests/run/$d/main.vl" ] && echo "=$d" ;;
        tests/run/*.vl) n=${1#tests/run/}; echo "=${n%.vl}" ;;
        tests/examples/*.test) n=${1#tests/examples/}; echo "=example_${n%.test}" ;;
    esac
}
# The cases whose file names $1 (by its path, else its file name).
mentions() {
    m=$(grep -lF "$1" tests/run/*.vl tests/run/*/*.vl tests/examples/*.test 2>/dev/null)
    [ -n "$m" ] || m=$(grep -lF "${1##*/}" tests/run/*.vl tests/run/*/*.vl tests/examples/*.test 2>/dev/null)
    for f in $m; do case_of "$f"; done | sort -u
}

: >"$WORK/plan"      # filters, for tests/run.sh -f
: >"$WORK/cmds"      # other commands, once each
: >"$WORK/builds"    # example builds: examples/X/main.vl
: >"$WORK/why"       # rule<TAB>items<TAB>path<TAB>why, for --list
: >"$WORK/flags"     # linux / broad, with the path
: >"$WORK/dropped"   # --narrow: the sets and filters left out
SMOKE=$(awk '$1 == "set" && $2 == "smoke" { sub(/#.*/, ""); $1 = ""; $2 = ""; print }' "$MAP")
while IFS='|' read -r path prefix items why raw; do
    got=""
    if [ $NARROW = 1 ]; then
        # (0.30) the rule's own items; of its sets, only the smoke set
        items=""
        for it in $raw; do
            case "$it" in
                @smoke) items="$items $SMOKE" ;;
                @self|@mentions|@example|@none) items="$items $it" ;;
                @*) echo "$it" >>"$WORK/dropped" ;;
                *) items="$items $it" ;;
            esac
        done
    fi
    for it in $items; do
        case "$it" in
            @none) ;;
            \?*)
                g=${it#?}
                if grep -v -x -F "$path" "$WORK/changed" | awk -v g="$g" 'index($0, g) == 1 { f = 1 } END { exit !f }'; then
                    got=""
                    raw="(through $g)"
                    break
                fi ;;
            @self)
                if [ -e "$path" ]; then
                    c=$(case_of "$path")
                    [ -n "$c" ] || c=$(mentions "$path")
                    got="$got $c"
                fi ;;
            @mentions)
                c=$(mentions "$path")
                if [ -n "$c" ]; then got="$got $c"; else got="$got =example_helloworld"; fi ;;
            @example)
                # (0.29) Prose in an example (a README, a note): no case
                # reads it and no build changes, so the layout checks
                # alone; the walkthroughs only when the README is one
                # they run (it has a ```console session).
                case "$path" in
                    *.md)
                        got="$got =example_layout =readme_sync"
                        if [ "${path##*/}" = README.md ] && grep -q '^```console' "$path" 2>/dev/null; then
                            got="$got =walkthrough"
                        fi
                        continue ;;
                esac
                rest=${path#examples/}
                ex=""
                acc=""
                for part in $(echo "${rest%/*}" | tr '/' ' '); do
                    [ "$rest" = "${rest%/*}" ] && break     # a file at examples/ itself
                    acc="$acc${acc:+/}$part"
                    [ -f "examples/$acc/main.vl" ] && { ex=$acc; break; }
                done
                got="$got =example_layout"
                if [ -n "$ex" ]; then
                    for t in $(grep -l "^// SOURCE: examples/$ex/" tests/examples/*.test 2>/dev/null); do
                        got="$got $(case_of "$t")"
                    done
                    case "$ex" in
                        tools/*|c-mixed-build) ;;
                        *) echo "examples/$ex/main.vl" >>"$WORK/builds"; got="$got build:examples/$ex" ;;
                    esac
                fi
                ;;
            !*) map_cmd "${it#!}" >>"$WORK/cmds"; got="$got $it" ;;
            +linux) echo "linux $path" >>"$WORK/flags" ;;
            +broad) echo "broad $path" >>"$WORK/flags" ;;
            *) got="$got $it" ;;
        esac
    done
    for g in $got; do
        case "$g" in build:*|!*) ;; *) echo "$g" >>"$WORK/plan" ;; esac
    done
    # (shown as written, @self, @example and @mentions by what they gave)
    shown=""
    for it in $raw; do
        case "$it" in
            @self|@example|@mentions)
                shown="$shown $it:"
                for g in $got; do
                    case " $items " in *" $g "*) ;; *) shown="$shown$g," ;; esac
                done
                shown=${shown%,} ;;
            *) shown="$shown $it" ;;
        esac
    done
    shown=$(echo $shown)
    printf '%s\t%s\t%s\t%s\n' "$prefix" "${shown:-nothing}" "$path" "$why" >>"$WORK/why"
done <"$WORK/rules"
# (0.30) the transcripts and sessions that print a changed std item
cat "$WORK/nameplan" >>"$WORK/plan"
: >"$WORK/narrow"    # --narrow: how it chose, line by line
: >"$WORK/narrow.common"
: >"$WORK/narrow.none"
if [ $NARROW = 1 ]; then
    tests/run.sh -l | awk '$1 == "case" { print $2 }' >"$WORK/allcases"
    # a rule's filter of too many cases: left out, the names stand for it
    sort -u "$WORK/plan" | while IFS= read -r g; do
        case "$g" in
            =*|*:*) echo "$g" ;;
            *)
                n=$(awk -v g="$g" 'index($0, g) { n++ } END { print n + 0 }' "$WORK/allcases")
                if [ "$n" -gt "$FILTER_CASES" ]; then
                    echo "$g ($n cases)" >>"$WORK/dropped"
                else
                    echo "$g"
                fi ;;
        esac
    done >"$WORK/plan.narrow"
    # the smoke set, and the cases that name a changed item
    for g in $SMOKE; do echo "$g"; done >>"$WORK/plan.narrow"
    : >"$WORK/plan.names"
    cut -d' ' -f2 "$WORK/names" | sort -u | while IFS= read -r name; do
        awk -v n="$name" '$1 == n { print $2 }' "$WORK/namehits" | while IFS= read -r f; do case_of "$f"; done | sort -u >"$WORK/name.cases"
        n=$(wc -l <"$WORK/name.cases" | tr -d ' ')
        others=$(awk -v n="$name" '$1 == n && $2 !~ /^tests\/run\// { k++ } END { print k + 0 }' "$WORK/namehits")
        kind=$(awk -v n="$name" '$2 == n { printf "%s%s", sep, $1; sep = "+" }' "$WORK/names")
        if [ "$n" -gt "$NAME_COMMON" ]; then
            echo "$name ($n)" >>"$WORK/narrow.common"
        elif [ "$n" -gt "$NAME_CASES" ]; then
            awk -v n="$n" -v m="$NAME_CASES" 'int((NR - 1) * m / n) != int((NR - 2) * m / n) || NR == 1' "$WORK/name.cases" >>"$WORK/plan.names"
            echo "$name ($kind): $n cases name it: $NAME_CASES of them, evenly through the list$([ "$others" -gt 0 ] && echo "; $others transcripts, sessions or chapters")" >>"$WORK/narrow"
        elif [ "$n" -gt 0 ] || [ "$others" -gt 0 ]; then
            cat "$WORK/name.cases" >>"$WORK/plan.names"
            echo "$name ($kind): $n cases$([ "$others" -gt 0 ] && echo ", $others transcripts, sessions or chapters")" >>"$WORK/narrow"
        else
            echo "$name" >>"$WORK/narrow.none"
        fi
    done
    # (all the names' cases: at most $NAMES_TOTAL, evenly through them)
    sort -u -o "$WORK/plan.names" "$WORK/plan.names"
    n=$(wc -l <"$WORK/plan.names" | tr -d ' ')
    if [ "$n" -gt "$NAMES_TOTAL" ]; then
        awk -v n="$n" -v m="$NAMES_TOTAL" 'int((NR - 1) * m / n) != int((NR - 2) * m / n) || NR == 1' "$WORK/plan.names" >>"$WORK/plan.narrow"
        echo "(all the names: $n cases: $NAMES_TOTAL of them, evenly through the list)" >"$WORK/narrow.total"
    else
        cat "$WORK/plan.names" >>"$WORK/plan.narrow"
    fi
    # (a compiler item's transcripts too, not only std's)
    awk -v common="$WORK/common" 'BEGIN { while ((getline l < common) > 0) skip[l] = 1 }
        !($1 in skip) && $2 ~ /^tests\/(query|refactor)\/[^\/]*\.[qt]$/ { split($2, part, "/"); t = part[3]; sub(/\.[qt]$/, "", t); print part[2] ":=" t }' \
        "$WORK/namehits" >>"$WORK/plan.narrow"
    cp "$WORK/plan.narrow" "$WORK/plan"
fi
sort -u -o "$WORK/plan" "$WORK/plan"
sort -u -o "$WORK/cmds" "$WORK/cmds"
sort -u -o "$WORK/builds" "$WORK/builds"
# (0.30) Every command of the plan can run, said now and not after the
# cases ran: each is run as `sh FILE ARGS`, so FILE is there and an sh
# script.
while read -r cfile crest; do
    [ -n "$cfile" ] || continue
    if [ ! -f "$cfile" ]; then
        die "the map's command '$cfile $crest' cannot run: there is no $cfile (tests/affected.map: a cmd line is a script of the tree and its arguments)"
    elif ! head -1 "$cfile" | grep -q -E '^#! ?(/usr/bin/env +)?(/bin/)?sh( |$)'; then
        die "the map's command '$cfile $crest' cannot run: $cfile is not an sh script (its first line is '$(head -1 "$cfile" | cut -c1-40)'; commands are run as sh FILE ARGS: tests/affected.map)"
    fi
done <"$WORK/cmds"

# What tests/run.sh selects: `case NAME`, `suite NAME [leveled]`.
if [ -s "$WORK/plan" ]; then
    tests/run.sh -l -f "$WORK/plan" >"$WORK/selected"
else
    : >"$WORK/selected"
fi
NCASES=$(grep -c '^case ' "$WORK/selected")
SUITES=$(awk '$1 == "suite" { printf "%s%s", sep, $2; sep = " " }' "$WORK/selected")
TOTAL=$(tests/run.sh -l | grep -c '^case ')
NSUITES_ALL=$(tests/run.sh -l | grep -c '^suite ')
# Later levels: the selected cases by name, but those that must fail to
# compile (the same at every level), and the suites that take -O.
for f in $(grep -l '^// ERROR:' tests/run/*.vl tests/run/*/main.vl tests/examples/*.test 2>/dev/null); do
    case_of "$f"
done | sed 's/^=//' >"$WORK/errorcases"
awk -v errs="$WORK/errorcases" 'BEGIN { while ((getline e < errs) > 0) err[e] = 1 }
    $1 == "case" && !($2 in err) { print "=" $2 }
    $1 == "suite" && $3 == "leveled" { print "=" $2 }' "$WORK/selected" >"$WORK/plan-leveled"
NLEVELED=$(grep -c '^=' "$WORK/plan-leveled")

summary_plan() {
    first_level=$(echo $LEVELS | cut -d' ' -f1)
    echo "plan: $NCASES of $TOTAL cases; suites: ${SUITES:-none} ($(echo $SUITES | wc -w | tr -d ' ') of $NSUITES_ALL)"
    echo "  levels: $(echo $LEVELS | sed 's/\([0-2]\)/-O\1/g'): all of it at -O$first_level$( [ "$(echo $LEVELS | wc -w)" -gt 1 ] && echo "; at the others $NLEVELED (the cases that compile, and gpu/arch-gen when in)")"
    [ -s "$WORK/builds" ] && echo "  builds: $(tr '\n' ' ' <"$WORK/builds")(volec FILE -o x, as example_build)"
    [ -s "$WORK/cmds" ] && sed 's/^/  command: /' "$WORK/cmds"
    if [ -s "$WORK/names" ]; then
        nn=$(wc -l <"$WORK/names" | tr -d ' ')
        echo "  names: $nn changed item$([ "$nn" = 1 ] || echo s) ($(awk '{ printf "%s%s", sep, $2; sep = " " } NR == 8 { exit }' "$WORK/names")$([ "$nn" -gt 8 ] && echo ' ...'))$([ -s "$WORK/nameplan" ] && echo "; std's are printed by: $(head -12 "$WORK/nameplan" | tr '\n' ' ' | sed 's/ $//')$([ "$(wc -l <"$WORK/nameplan")" -gt 12 ] && echo " ... ($(wc -l <"$WORK/nameplan" | tr -d ' ') in all)")")$([ -s "$WORK/common" ] && echo "; too common to choose by: $(head -6 "$WORK/common" | tr '\n' ' ' | sed 's/ $//')$([ "$(wc -l <"$WORK/common")" -gt 6 ] && echo ' ...')")"
    fi
    if [ $NARROW = 1 ]; then
        echo "  narrow: a sample, not the rules' plan: the changed tests, the rules' own items, the smoke set, and by name:"
        head -30 "$WORK/narrow" | sed 's/^/    /'
        nl=$(wc -l <"$WORK/narrow" | tr -d ' ')
        [ "$nl" -gt 30 ] && echo "    ... ($((nl - 30)) more names with tests)"
        [ -s "$WORK/narrow.common" ] && echo "    too common to choose by (over $NAME_COMMON cases name it), left out: $(head -8 "$WORK/narrow.common" | tr '\n' ',' | sed 's/,$//; s/,/, /g')$([ "$(wc -l <"$WORK/narrow.common")" -gt 8 ] && echo ', ...')"
        [ -s "$WORK/narrow.none" ] && echo "    no test names: $(wc -l <"$WORK/narrow.none" | tr -d ' ') of the items ($(head -6 "$WORK/narrow.none" | tr '\n' ' ' | sed 's/ $//')$([ "$(wc -l <"$WORK/narrow.none")" -gt 6 ] && echo ' ...'))"
        [ -s "$WORK/narrow.total" ] && sed 's/^/    /' "$WORK/narrow.total"
        [ -s "$WORK/dropped" ] && echo "    left out: $(sort -u "$WORK/dropped" | tr '\n' ',' | sed 's/,$//; s/,/, /g')"
        [ "$NCASES" -gt "$NARROW_OVER" ] && echo "    still over $NARROW_OVER cases: choose filters by hand (tests/run.sh -l FILTER)"
    elif [ "$NCASES" -gt "$NARROW_OVER" ]; then
        echo "  over $NARROW_OVER cases: tests/affected.sh --narrow plans the changed tests, the cases that name a changed item and the smoke set (--narrow --list shows it)"
    fi
    if [ "$NUNTRACKED" -gt 0 ]; then
        names="$(head -4 "$WORK/untracked" | tr '\n' ' ' | sed 's/ $//')$( [ "$NUNTRACKED" -gt 4 ] && echo ', ...')"
        if [ $UNTRACKED = 1 ]; then
            echo "  untracked, counted (--untracked): $NUNTRACKED file(s): $names"
        else
            echo "  untracked, not counted: $NUNTRACKED file(s): $names (git add what is the branch's, or --untracked counts them all)"
        fi
    fi
    if grep -q '^broad ' "$WORK/flags"; then
        echo "  broad: the change can alter what any program means ($(grep '^broad ' "$WORK/flags" | cut -d' ' -f2 | sort -u | head -3 | tr '\n' ' ' | sed 's/ $//')$( [ "$(grep -c '^broad ' "$WORK/flags")" -gt 3 ] && echo ', ...')): most of the suite"
    fi
    if grep -q '^linux ' "$WORK/flags"; then
        echo "  linux: platform-relevant ($(grep '^linux ' "$WORK/flags" | cut -d' ' -f2 | sort -u | head -3 | tr '\n' ' ' | sed 's/ $//')$( [ "$(grep -c '^linux ' "$WORK/flags")" -gt 3 ] && echo ', ...')): $( [ $LINUX = 1 ] && echo 'runs in the container (--linux)' || echo 'add --linux to run the plan on aarch64-linux too')"
    fi
}

if [ -n "$PATHS" ]; then
    echo "affected: as if $NCHANGED path$([ "$NCHANGED" = 1 ] || echo s) had changed (--path)"
else
    echo "affected: ${HEAD_REV:-$(git rev-parse --abbrev-ref HEAD)} against $BASE (merge-base $(git rev-parse --short "$MB")): $NCHANGED changed paths"
fi
if [ $LIST = 1 ]; then
    # One line per rule: its paths (a few), what it adds, why.
    awk -F'\t' '
        { k = $1 "\t" $2; if (!(k in n)) { order[++m] = k; why[k] = $4 } n[k]++; if (n[k] <= 3) paths[k] = paths[k] (n[k] > 1 ? ", " : "") $3 }
        END {
            for (i = 1; i <= m; i++) {
                k = order[i]; split(k, f, "\t")
                printf "  %s (%d path%s: %s%s) -> %s%s\n", f[1], n[k], (n[k] > 1 ? "s" : ""), paths[k], (n[k] > 3 ? ", ..." : ""), f[2], (why[k] != "" ? "  # " why[k] : "")
            }
        }' "$WORK/why"
    summary_plan
    exit 0
fi

# ---- the run ----

[ -x "$COMPILER" ] || die "no compiler at $COMPILER (bootstrap/bootstrap.sh --dev --no-suite)"
summary_plan
RESULTS="$WORK/results"
: >"$RESULTS"
result() { # <PASS|FAIL> <what> <seconds>
    echo "  $1 $2 ($3 s)" >>"$RESULTS"
}
JFLAG=""
[ -n "$JOBS" ] && JFLAG="-j $JOBS"
first=1
for l in $LEVELS; do
    if [ $first = 1 ]; then
        pf="$WORK/plan"
    else
        pf="$WORK/plan-leveled"
    fi
    first=0
    [ -s "$pf" ] || continue
    echo "==> tests/run.sh -O$l ($(grep -c . "$pf") filters)" >&2
    t0=$(date +%s)
    # shellcheck disable=SC2086
    # (0.30) its plan and each suite's line as they come, the rest in the log
    {
        tests/run.sh -c "$COMPILER" -O "$l" $JFLAG -f "$pf" 2>&1
        echo "$?" >"$WORK/run.rc"
    } | tee "$WORK/run-O$l.log" | awk '/^(plan: |suite [a-z_-]+: [0-9]+ pass)/ { print "    " $0; fflush() }' >&2
    if [ "$(cat "$WORK/run.rc" 2>/dev/null)" = 0 ]; then
        tail -n +1 "$WORK/run-O$l.log" | awk '/^tests for /{ p = 1 } p' | grep -E '^tests for|  total|^lazy std:'
        result PASS "tests/run.sh -O$l: $(awk '$1 == "total" { print $2 " passed, " $3 " xfail" }' "$WORK/run-O$l.log")" $(( $(date +%s) - t0 ))
    else
        cat "$WORK/run-O$l.log"
        result FAIL "tests/run.sh -O$l" $(( $(date +%s) - t0 ))
    fi
done
while read -r m; do
    [ -n "$m" ] || continue
    t0=$(date +%s)
    if "$COMPILER" "$m" -o "$WORK/example.bin" >"$WORK/build.out" 2>&1; then
        result PASS "volec $m -o x" $(( $(date +%s) - t0 ))
    else
        tail -5 "$WORK/build.out"
        result FAIL "volec $m -o x" $(( $(date +%s) - t0 ))
    fi
done <"$WORK/builds"
while read -r c; do
    [ -n "$c" ] || continue
    echo "==> $c" >&2
    t0=$(date +%s)
    # shellcheck disable=SC2086
    sh $c >"$WORK/cmd.out" 2>&1
    rc=$?
    if [ $rc = 0 ]; then
        # (0.25.5: the compile-cost row's lines, its ratios)
        case "$c" in *compile_cost.sh*) cat "$WORK/cmd.out" ;; esac
        result PASS "$c" $(( $(date +%s) - t0 ))
    elif [ $rc = 77 ]; then
        # (0.25.5: a command that cannot run here, said why: compile-cost
        # without a release built, or /usr/bin/time -l)
        result SKIP "$c: $(tail -1 "$WORK/cmd.out")" $(( $(date +%s) - t0 ))
    else
        tail -20 "$WORK/cmd.out"
        result FAIL "$c" $(( $(date +%s) - t0 ))
    fi
done <"$WORK/cmds"
if [ $LINUX = 1 ] && [ -s "$WORK/plan" ]; then
    echo "==> the plan on aarch64-linux (bootstrap/aarch64-linux-check.sh --slice)" >&2
    t0=$(date +%s)
    if sh bootstrap/aarch64-linux-check.sh --worktree --dev --compiler "$COMPILER" \
        --slice "$(tr '\n' ' ' <"$WORK/plan")" --slice-levels "$LEVELS" >"$WORK/linux.log" 2>&1; then
        result PASS "aarch64-linux: $(grep -c '^gate-row.*pass' "$WORK/linux.log") rows" $(( $(date +%s) - t0 ))
    else
        # (0.25.5) each failure with its difference (its indented lines, at
        # most 30 of each, 300 in all), not only its name (mod254 #13)
        awk '/^(FAIL|XPASS) / { p = 1; k = 0; print; next }
            p && (/^[ \t]/ || /^$/) { if (++k <= 30 && ++n <= 300) print; else if (k == 31) print "    (more lines cut)"; next }
            { p = 0 }
            /^gate-row|^--- / { print }' "$WORK/linux.log" | grep . || tail -40 "$WORK/linux.log"
        result FAIL "aarch64-linux: $(grep -c '^FAIL ' "$WORK/linux.log") failed" $(( $(date +%s) - t0 ))
    fi
fi
echo "affected: done"
cat "$RESULTS"
if grep -q '^  FAIL' "$RESULTS"; then
    echo "affected: FAIL"
    exit 1
fi
echo "affected: ok"
