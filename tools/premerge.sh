#!/bin/sh
# The checks a branch passes before it is merged into an integration
# branch (AGENTS.md, "Before a merge"): run in the branch's worktree.
#
# usage: tools/premerge.sh [BASE]     (default: the release-* branch it forked from, the nearest merge-base; else main)
#
#   base     the branch contains BASE's tip (else: merge BASE first)
#   unsafe   no new unsafe without // UNSAFE: and // SAFETY: (tools/unsafe-diff-check.py)
#   fmt      every changed .vl outside tests/ is in the standard style
#   check    every program the change touches checks with no error and no warning
#   std      compiler/src/front/stdsrc.vl is what compiler/std/embed.sh makes of std
#   layout   every tests/examples case names a SOURCE that exists
#
# One line per check (PASS, FAIL or SKIP and why), the details after;
# exits 1 if one failed. It is not the tests: with it, an agent runs
# tests/affected.sh (AGENTS.md, tier 2); the whole suite and the gate are
# the integrator's, once per merge batch (tier 3).
set -u
LC_ALL=C
export LC_ALL
cd "$(git rev-parse --show-toplevel)" || exit 2

BASE=${1:-}
if [ -z "$BASE" ]; then
    # (0.25.2: the one whose merge-base with HEAD is nearest, not the last
    # by name, release-0.9 sorting after release-0.25.2; one that moved
    # on since is still the base, and the check below says to merge it)
    current=$(git rev-parse --abbrev-ref HEAD)
    BASE=$(git for-each-ref --format='%(refname:short)' 'refs/heads/release-*' | while read -r b; do
        [ "$b" = "$current" ] && continue
        mb=$(git merge-base "$b" HEAD 2>/dev/null) || continue
        echo "$(git rev-list --count "$mb..HEAD") $b"
    done | sort -n -k1,1 | head -1 | cut -d' ' -f2)
    [ -n "$BASE" ] || BASE=main
fi
VOLEC=
for c in target/tools/volec target/volec; do
    [ -x "$c" ] && { VOLEC=$PWD/$c; break; }
done
[ -n "$VOLEC" ] || VOLEC=$(command -v volec || true)

TMP=${TMPDIR:-/tmp}/premerge.$$
mkdir -p "$TMP" || exit 2
trap 'rm -r "$TMP"' EXIT
FAILED=0
row() { printf '  %-7s %-5s %s\n' "$1" "$2" "$3"; [ "$2" = FAIL ] && FAILED=1; }

CHANGED=$(git diff --name-only "$BASE"...HEAD; git diff --name-only HEAD)
CHANGED=$(printf '%s\n' "$CHANGED" | sort -u | while read -r f; do [ -n "$f" ] && [ -e "$f" ] && echo "$f"; done)

echo "premerge: $(git rev-parse --abbrev-ref HEAD) against $BASE"

# base
if git merge-base --is-ancestor "$BASE" HEAD; then
    row base PASS "contains $BASE ($(git rev-parse --short "$BASE"))"
else
    row base FAIL "$BASE has moved: git merge $BASE first"
fi

# unsafe
if python3 -I tools/unsafe-diff-check.py "$BASE" > "$TMP/unsafe" 2>&1; then
    row unsafe PASS "$(tail -1 "$TMP/unsafe" | sed 's/^unsafe-diff-check: //; s/^$/no new unsafe/')"
else
    row unsafe FAIL "$(tail -1 "$TMP/unsafe" | sed 's/^unsafe-diff-check: //')"
fi

# fmt
if [ -z "$VOLEC" ]; then
    row fmt SKIP "no volec (bootstrap/bootstrap.sh --dev)"
else
    : > "$TMP/fmt"
    for f in $(printf '%s\n' "$CHANGED" | grep '\.vl$' | grep -v '^tests/' | grep -v 'front/stdsrc\.vl$'); do
        "$VOLEC" fmt --check "$f" > /dev/null 2>&1 || echo "  $f: not formatted (try: volec fmt $f)" >> "$TMP/fmt"
    done
    if [ -s "$TMP/fmt" ]; then row fmt FAIL "$(wc -l < "$TMP/fmt" | tr -d ' ') file(s)"; else row fmt PASS "changed .vl files formatted"; fi
fi

# check: the program roots the change touches
if [ -z "$VOLEC" ]; then
    row check SKIP "no volec"
else
    : > "$TMP/roots"
    for f in $(printf '%s\n' "$CHANGED" | grep '\.vl$' | grep -v '^tests/'); do
        case "$f" in
            compiler/src/*|compiler/std/*) echo compiler/src/main.vl ;;
            *) d=$(dirname "$f")
               while [ "$d" != . ] && [ ! -f "$d/main.vl" ]; do d=$(dirname "$d"); done
               [ -f "$d/main.vl" ] && echo "$d/main.vl" ;;
        esac
    done | sort -u > "$TMP/roots"
    : > "$TMP/check"
    while read -r r; do
        out=$( (cd "$(dirname "$r")" && "$VOLEC" check main.vl) 2>&1 )
        printf '%s\n' "$out" | grep -E '(error|warning)\[|^error ' > /dev/null && \
            printf '  %s:\n%s\n' "$r" "$(printf '%s\n' "$out" | grep -E '(error|warning)\[|^error ' | head -5 | sed 's/^/    /')" >> "$TMP/check"
    done < "$TMP/roots"
    n=$(wc -l < "$TMP/roots" | tr -d ' ')
    if [ -s "$TMP/check" ]; then row check FAIL "errors or warnings in the touched programs"; else row check PASS "$n program(s) check clean"; fi
fi

# std: the embedded std is up to date
if printf '%s\n' "$CHANGED" | grep -q '^compiler/std/'; then
    if ! git diff --quiet HEAD -- compiler/src/front/stdsrc.vl; then
        row std SKIP "stdsrc.vl has uncommitted changes"
    else
        sh compiler/std/embed.sh > /dev/null 2>&1
        if git diff --quiet -- compiler/src/front/stdsrc.vl; then
            row std PASS "stdsrc.vl matches compiler/std"
        else
            git checkout -q -- compiler/src/front/stdsrc.vl
            row std FAIL "stdsrc.vl is stale: run compiler/std/embed.sh and commit it"
        fi
    fi
else
    row std SKIP "compiler/std unchanged"
fi

# layout: tests/examples cases name sources that exist
: > "$TMP/layout"
for t in tests/examples/*.test; do
    awk '/^\/\/ (SOURCE|CSOURCE):/ { print $3 }' "$t" | while read -r s; do
        s=$(printf '%s' "$s" | sed "s|@ROOT@|$PWD|")
        [ -e "$s" ] || echo "  $t: no $s" >> "$TMP/layout"
    done
done
if [ -s "$TMP/layout" ]; then row layout FAIL "example cases name missing sources"; else row layout PASS "example cases' sources exist"; fi

for k in unsafe fmt check layout; do
    [ -s "$TMP/$k" ] || continue
    case "$k" in unsafe) grep -v '^unsafe-diff-check: .*moved' "$TMP/$k" | grep -v '^$' | sed 's/^/  /' ;; *) cat "$TMP/$k" ;; esac
done
[ "$FAILED" = 0 ] && echo "premerge: ok" || echo "premerge: FAILED"
exit "$FAILED"
