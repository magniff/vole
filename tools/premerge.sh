#!/bin/sh
# The checks a branch passes before it is merged into an integration
# branch (AGENTS.md, "Before a merge"): run in the branch's worktree.
#
# usage: tools/premerge.sh [BASE]     (default: the release-* branch it forked from, the nearest merge-base; else main)
#
#   base     the branch contains BASE's tip (else: merge BASE first)
#   unsafe   no new unsafe without // UNSAFE: and // SAFETY: (tools/unsafe-diff-check.py)
#   fmt      every changed .vl outside tests/ is in the standard style
#            (by the branch's own target/volec when the last tested build
#            cannot read it: 0.27.0, a rust-edition file)
#   check    every program a changed file belongs to (a .vl, a shader it embeds,
#            a file beside its main.vl) checks with no error and no warning;
#            SKIP, never PASS, when the change touches no program
#            (but one whose main.vl says `// premerge: broken on purpose`)
#            (but unsafe.unjustified: legacy sites are the baseline's, and new
#            ones the unsafe row's)
#   std      the committed compiler/src/front/stdsrc_rust.vl is what compiler/std/embed.sh
#            makes of the committed std (0.25.3: made by the commit hook and the
#            merge driver, tools/git-hooks/setup.sh; said when they are not set up)
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

# (0.25.3) A branch that changes the compiler checks and formats its
# programs with its own build, target/volec: they may use what it adds
# (a new literal, a new std item) that the last tested build does not read.
if [ -x target/volec ] && printf '%s\n' "$CHANGED" | grep -q '^compiler/src/\|^compiler/std/'; then
    VOLEC=$PWD/target/volec
fi

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
    for f in $(printf '%s\n' "$CHANGED" | grep '\.vl$' | grep -v -e '^tests/' -e '^editors/vscode/test/samples/' | grep -v 'front/stdsrc_rust\.vl$'); do
        # (or by the branch's own build: a build before 0.28.0 reads a
        # module of compiler/src alone as the old edition's)
        "$VOLEC" fmt --check "$f" > /dev/null 2>&1 \
            || { [ -x target/volec ] && target/volec fmt --check "$f" > /dev/null 2>&1; } || echo "  $f: not formatted (try: volec fmt $f)" >> "$TMP/fmt"
    done
    if [ -s "$TMP/fmt" ]; then row fmt FAIL "$(wc -l < "$TMP/fmt" | tr -d ' ') file(s)"; else row fmt PASS "changed .vl files formatted"; fi
fi

# check: the programs the change touches. Every changed file counts, not
# only a .vl: a shader a program embeds, a README beside its main.vl (the
# nearest main.vl above the file is its program; a .vl that is a program
# of its own, with `fn main`, is checked alone). Files under tests/ are
# their suites' (a case names the errors it expects, a tool's fixture is
# broken on purpose): tests/affected.sh runs them. The row never passes
# on nothing: with no program it is SKIP and says why.
if [ -z "$VOLEC" ]; then
    row check SKIP "no volec (bootstrap/bootstrap.sh --dev --no-suite)"
else
    : > "$TMP/roots.all"
    : > "$TMP/check.tests"
    : > "$TMP/check.none"
    printf '%s\n' "$CHANGED" | while read -r f; do
        [ -n "$f" ] || continue
        case "$f" in
            tests/*) echo "$f" >> "$TMP/check.tests" ;;
            compiler/src/*|compiler/std/*) echo compiler/src/main.vl ;;
            *) d=$(dirname "$f")
               while [ "$d" != . ] && [ ! -f "$d/main.vl" ]; do d=$(dirname "$d"); done
               if [ -f "$d/main.vl" ]; then echo "$d/main.vl"
               elif [ "${f%.vl}" != "$f" ] && grep -q '^\(pub \)\{0,1\}fn main(' "$f"; then echo "$f"
               else echo "$f" >> "$TMP/check.none"; fi ;;
        esac
    done >> "$TMP/roots.all"
    sort -u "$TMP/roots.all" > "$TMP/roots"
    : > "$TMP/check"
    checked=0
    onpurpose=0
    while read -r r; do
        # (a program that fails on purpose, e.g. a walkthrough's: its
        # main.vl has the line `// premerge: broken on purpose (why)`)
        if grep -q '^// premerge: broken on purpose' "$r"; then onpurpose=$((onpurpose + 1)); continue; fi
        checked=$((checked + 1))
        out=$( (cd "$(dirname "$r")" && "$VOLEC" check "$(basename "$r")") 2>&1 )
        # (0.25.3: not unsafe.unjustified, the unsafe row's and the baseline's)
        out=$(printf '%s\n' "$out" | grep -v 'warning\[unsafe\.unjustified\]')
        printf '%s\n' "$out" | grep -E '(error|warning)\[|^error ' > /dev/null && \
            printf '  %s:\n%s\n' "$r" "$(printf '%s\n' "$out" | grep -E '(error|warning)\[|^error ' | head -5 | sed 's/^/    /')" >> "$TMP/check"
    done < "$TMP/roots"
    nt=$(wc -l < "$TMP/check.tests" | tr -d ' ')
    nn=$(wc -l < "$TMP/check.none" | tr -d ' ')
    rest=""
    [ "$onpurpose" = 0 ] || rest="$rest; $onpurpose broken on purpose"
    [ "$nt" = 0 ] || rest="$rest; $nt file(s) under tests/: tests/affected.sh"
    [ "$nn" = 0 ] || rest="$rest; $nn file(s) of no program"
    if [ -s "$TMP/check" ]; then
        row check FAIL "errors or warnings in the touched programs"
    elif [ "$checked" = 0 ]; then
        row check SKIP "no program to check${rest:-; nothing changed}"
    else
        row check PASS "$checked program(s) check clean, shaders included: $(tr '\n' ' ' < "$TMP/roots" | sed 's/ $//')$rest"
    fi
fi

# std: the embedded std is up to date, as committed (0.25.3: made from
# HEAD's compiler/std in a copy, so the work tree is left as it is)
setup=""
[ -n "$(git config merge.stdsrc.driver)" ] || setup="; the stdsrc merge driver is not set up: tools/git-hooks/setup.sh"
if printf '%s\n' "$CHANGED" | grep -q -e '^compiler/std/' -e '^compiler/src/front/stdsrc_rust\.vl$'; then
    mkdir -p "$TMP/std/compiler/src/front"
    git archive HEAD compiler/std | tar -xf - -C "$TMP/std"
    # (the committed file, whose index of units embed.sh keeps when no
    # compiler here makes it; this tree's compiler makes it when it can)
    git show HEAD:compiler/src/front/stdsrc_rust.vl > "$TMP/std/compiler/src/front/stdsrc_rust.vl"
    if ! VOLE_EMBED_VOLEC="${VOLE_EMBED_VOLEC:-$PWD/target/volec}" sh "$TMP/std/compiler/std/embed.sh" > "$TMP/std.out" 2>&1; then
        row std FAIL "compiler/std/embed.sh failed: $(head -1 "$TMP/std.out")"
    elif git show HEAD:compiler/src/front/stdsrc_rust.vl | cmp -s - "$TMP/std/compiler/src/front/stdsrc_rust.vl"; then
        row std PASS "the committed stdsrc_rust.vl matches compiler/std$setup"
    else
        row std FAIL "the committed stdsrc_rust.vl is stale: compiler/std/embed.sh, then commit it$setup"
    fi
else
    row std SKIP "compiler/std unchanged$setup"
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
