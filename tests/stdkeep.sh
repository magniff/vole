#!/bin/sh
# (0.25.5) What a runner's -u writes: the transcript it got, but each line
# that differs from the one it replaces only in std's numbers (positions,
# counts: tests/stdpos.awk) kept as it was, so that rewriting a
# transcript for a real change does not also rewrite the std numbers a
# std change moved (stdunsafe254 #14: a 354-line diff for two real
# changes). The comparison ignores those numbers anyway; a transcript
# about them (`## exact-std`) gets what it got. POSIX sh and awk only.
#
# usage: tests/stdkeep.sh OLD GOT [STDFILES]   (the merged text on stdout)
#
#   OLD       the transcript as it is (its commands and their answers)
#   GOT       what the runner got now, in the same form
#   STDFILES  std's file names (the LSP runner's -v stdfiles, stdpos.awk)
#
# Each line of GOT is matched with the next line of OLD (at most 400
# lines on) whose text, std's numbers normalized line by line (stdpos.awk
# mode=lines), is the same: that line of OLD is written; a line with no
# match (new, or changed otherwise) is written as GOT has it.
set -u
[ $# -ge 2 ] || { echo "usage: tests/stdkeep.sh OLD GOT [STDFILES]" >&2; exit 2; }
AWK="$(cd "$(dirname "$0")" && pwd)/stdpos.awk"
old=$1
got=$2
files=${3:-}
tmp=$(mktemp -d "${TMPDIR:-/tmp}/vole-stdkeep.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
awk -v mode=lines -v stdfiles="$files" -f "$AWK" "$old" >"$tmp/old.n"
awk -v mode=lines -v stdfiles="$files" -f "$AWK" "$got" >"$tmp/got.n"
awk -v old="$old" -v oldn="$tmp/old.n" -v gotn="$tmp/got.n" '
    BEGIN {
        while ((getline l < old) > 0) o[++no] = l
        while ((getline l < oldn) > 0) on[++non] = l
        while ((getline l < gotn) > 0) gn[++ngn] = l
        # (the two normalized texts line for line, or no keeping)
        keep = (no == non)
        j = 1
    }
    {
        i++
        if (keep) {
            for (k = j; k <= no && k < j + 400; k++) {
                if (on[k] == gn[i]) {
                    print o[k]
                    j = k + 1
                    next
                }
            }
        }
        print
    }' "$got"
