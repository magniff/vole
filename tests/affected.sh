#!/bin/sh
# The tests a change touches (0.25.2), for an agent's checks before it
# reports (AGENTS.md, tier 2): the paths changed since BASE (`git diff
# --name-only BASE...HEAD`, plus the work tree's changes and new files)
# are looked up in tests/affected.map, which names for each path prefix
# the tests/run.sh filters (cases, suites, checks), example builds and
# other test scripts that would see the change; the union runs, in one
# tests/run.sh per level. A changed test runs itself; a path no rule
# names gets the smoke set, never nothing.
#
# usage: tests/affected.sh [BASE] [-O LEVEL]... [--list] [--linux] [--head REV] [-c COMPILER] [-j JOBS]
#
#   BASE          what the change is against (default: the release-*
#                 branch, or main, whose merge-base with HEAD is the
#                 nearest)
#   -O LEVEL      a level to run at (0, 1 or 2; repeatable, or -O 0,2;
#                 default -O0 and -O2): the cases and the suites that take
#                 a level at each, the other suites at the first only
#   --list        print the plan, each item with the paths and the rule
#                 that put it there, and its size; run nothing
#   --linux       also run the plan in the aarch64-linux container
#                 (bootstrap/aarch64-linux-check.sh --slice; docker must
#                 run): for platform-relevant changes (the map's +linux;
#                 --list says when)
#   --head REV    the change is BASE...REV, without the work tree (an
#                 integrator's look at another branch; the tests named
#                 are this tree's)
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

{
    git diff --name-only "$MB" "$HEAD_IS"
    if [ -z "$HEAD_REV" ]; then
        git diff --name-only HEAD
        git ls-files --others --exclude-standard
    fi
} | sort -u | sed '/^$/d' >"$WORK/changed"
NCHANGED=$(wc -l <"$WORK/changed" | tr -d ' ')

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
while IFS='|' read -r path prefix items why raw; do
    got=""
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
                case "$path" in */README.md) got="$got =walkthrough" ;; esac ;;
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
sort -u -o "$WORK/plan" "$WORK/plan"
sort -u -o "$WORK/cmds" "$WORK/cmds"
sort -u -o "$WORK/builds" "$WORK/builds"

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
    if grep -q '^broad ' "$WORK/flags"; then
        echo "  broad: the change can alter what any program means ($(grep '^broad ' "$WORK/flags" | cut -d' ' -f2 | sort -u | head -3 | tr '\n' ' ' | sed 's/ $//')$( [ "$(grep -c '^broad ' "$WORK/flags")" -gt 3 ] && echo ', ...')): most of the suite"
    fi
    if grep -q '^linux ' "$WORK/flags"; then
        echo "  linux: platform-relevant ($(grep '^linux ' "$WORK/flags" | cut -d' ' -f2 | sort -u | head -3 | tr '\n' ' ' | sed 's/ $//')$( [ "$(grep -c '^linux ' "$WORK/flags")" -gt 3 ] && echo ', ...')): $( [ $LINUX = 1 ] && echo 'runs in the container (--linux)' || echo 'add --linux to run the plan on aarch64-linux too')"
    fi
}

echo "affected: ${HEAD_REV:-$(git rev-parse --abbrev-ref HEAD)} against $BASE (merge-base $(git rev-parse --short "$MB")): $NCHANGED changed paths"
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
    if tests/run.sh -c "$COMPILER" -O "$l" $JFLAG -f "$pf" >"$WORK/run-O$l.log" 2>&1; then
        tail -n +1 "$WORK/run-O$l.log" | awk '/^tests for /{ p = 1 } p' | grep -E '^tests for|  total'
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
