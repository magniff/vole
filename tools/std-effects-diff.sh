#!/bin/sh
# (0.30) What a change to std did to the effects of std's public
# functions: the inferred effect set of each, now and at a base revision,
# and the ones that differ.
#
# compiler/src declares few effects, so a std edit that gives a function
# an effect it did not have (a copy loop the compiler cannot count:
# `diverge` on every format, 0.29) passes the compiler's own check; and a
# generic function shows its effects only where a program instantiates
# it. `volec query effects std --templates` lists every public function
# of std once, a generic one by its template (its opaque instance), so
# the listing does not depend on a program; this script makes it for
# std's files as they are and for BASE's, and prints the difference:
#
#   std::mem::replace	unsafe T -> diverge unsafe T
#   + std::mem::fresh	panic
#   - std::mem::gone	none
#   std-effects-diff: 1 changed, 1 added, 1 removed since HEAD (2041 functions)
#
# usage: tools/std-effects-diff.sh [-c COMPILER] [--check] [BASE]
#
#   BASE          a revision (default HEAD: the edits not yet committed;
#                 `release-0.30.0`: what the branch did)
#   -c COMPILER   the volec to ask (default: target/volec, which must
#                 know `--templates`: 0.30)
#   --check       exit 1 when a function's effects changed or one was
#                 removed (an added function is no change)
#
# BASE's listing is kept in the tools' cache (target/volec-cache, by the
# revision's std tree and the compiler's checksum), so a second run reads
# std once: about 4 s. A function of std the opaque model does not cover
# (`volec check --std` counts them) has no line on either side.
set -u
LC_ALL=C
export LC_ALL
ROOT=$(cd "$(dirname "$0")/.." && pwd)
C="$ROOT/target/volec"
BASE=HEAD
CHECK=0
while [ $# -gt 0 ]; do
    case "$1" in
        -c) [ $# -ge 2 ] || exit 2; C=$2; shift ;;
        --check) CHECK=1 ;;
        -h|--help) sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "usage: tools/std-effects-diff.sh [-c COMPILER] [--check] [BASE]" >&2; exit 2 ;;
        *) BASE=$1 ;;
    esac
    shift
done
case "$C" in /*) ;; *) C="$(pwd)/$C" ;; esac
[ -x "$C" ] || { echo "std-effects-diff: no compiler at $C" >&2; exit 2; }
cd "$ROOT" || exit 2
TREE=$(git rev-parse --verify -q "$BASE:compiler/std") \
    || { echo "std-effects-diff: no compiler/std at revision '$BASE'" >&2; exit 2; }

W=$(mktemp -d "${TMPDIR:-/tmp}/vole-stdeff.XXXXXX")
trap 'rm -rf "$W"' EXIT
trap 'exit 130' INT TERM
VOLE_CACHE=off
export VOLE_CACHE

# <std's directory> <out>: the listing of that std (no program: std
# alone), sorted; false when the compiler fails.
listing() {
    (cd "$W" && "$C" query effects std --templates --budget 0 --std-tree "$1") >"$W/raw" 2>"$W/err" \
        || { if grep -q "unknown option '--templates'" "$W/err"; then
                 echo "std-effects-diff: $C does not know \`query effects --templates\` (before 0.30)" >&2
             else
                 echo "std-effects-diff: the listing failed for $1:" >&2; head -5 "$W/err" >&2
             fi
             return 1; }
    sort "$W/raw" >"$2"
}

# BASE's listing, from the cache when it is there.
KEY="$TREE-$(cksum <"$C" | tr ' ' '-')"
CACHE="$ROOT/target/volec-cache/std-effects-$KEY.txt"
if [ -s "$CACHE" ]; then
    cp "$CACHE" "$W/base.txt"
else
    mkdir -p "$W/base"
    git archive "$BASE" compiler/std | tar -x -C "$W/base" \
        || { echo "std-effects-diff: cannot read compiler/std at '$BASE'" >&2; exit 2; }
    listing "$W/base/compiler/std" "$W/base.txt" || exit 1
    if [ -d "$ROOT/target" ]; then
        mkdir -p "$ROOT/target/volec-cache" && cp "$W/base.txt" "$CACHE.$$" && mv "$CACHE.$$" "$CACHE"
    fi
fi
listing "$ROOT/compiler/std" "$W/now.txt" || exit 1

# A name's lines on each side (an impl's method of several impls has
# one a line), joined; the names whose lines differ.
awk -F '\t' -v base="$BASE" -v check="$CHECK" '
    FNR == NR { old[$1] = (($1 in old) ? old[$1] " | " : "") $2; next }
    { new[$1] = (($1 in new) ? new[$1] " | " : "") $2 }
    END {
        n = 0
        for (k in new) { names[k] = 1; n++ }
        for (k in old) names[k] = 1
        for (k in names) {
            if (!(k in old)) { added++; out[k] = "+ " k "\t" new[k] }
            else if (!(k in new)) { removed++; out[k] = "- " k "\t" old[k] }
            else if (old[k] != new[k]) { changed++; out[k] = k "\t" old[k] " -> " new[k] }
        }
        m = 0
        for (k in out) keys[++m] = k
        # (an insertion sort: the differences are few)
        for (i = 2; i <= m; i++) { v = keys[i]; j = i - 1; while (j >= 1 && keys[j] > v) { keys[j + 1] = keys[j]; j-- } keys[j + 1] = v }
        for (i = 1; i <= m; i++) print out[keys[i]]
        printf "std-effects-diff: %d changed, %d added, %d removed since %s (%d functions)\n", changed + 0, added + 0, removed + 0, base, n
        exit (check == 1 && (changed + removed) > 0) ? 1 : 0
    }' "$W/base.txt" "$W/now.txt"
