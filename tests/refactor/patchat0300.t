## 0.30: patches by position, one check (the 0.29 tool diaries, theme B:
## a check names FILE:LINE:COL, `edit patch` wanted an item's name and an
## OLD unique in the item, and each call paid a whole check).
## --at FILE:LINE: OLD is looked for on that line only; the pairs after
## an --at are that line's. One edit, one check.
$ edit patch --at main.vl:4 --old '0, 10' --new '1, 9' --at calc.vl:6 --old 'v > hi' --new 'v >= hi' --show
patched 2 sites	2 files	+2 -2 lines
// main.vl:4
4	    let x = calc::clamp(a, 1, 9);
// calc.vl:6
6	    if v >= hi {
% git checkout -q .
## A column, as a diagnostic prints it: OLD starts there (the second `x`
## of line 6); an empty OLD inserts NEW at the column.
$ edit patch --at main.vl:6:13 --old x --new y --at main.vl:10:15 --old '' --new ' + 1' --show
patched 2 sites	main.vl	+2 -2 lines
// main.vl:6
6	    x + y + y
// main.vl:10
10	    total(3, 4 + 1) as i32
% git checkout -q .
## OLD twice on the line and no column: the columns are named.
$ edit patch --at main.vl:6 --old x --new y
error patch.ambiguous: patch 1 (main.vl:6): OLD 'x' is on that line 2 times (columns 5, 13): name one, main.vl:6:5
error patch.sites: 1 of 1 patch does not match; nothing written
[exit 1]
## --from LIST: a patch a line, FILE:LINE[:COL]<TAB>OLD<TAB>NEW.
% cat $T/inputs/patchat-list.txt
main.vl:4	0, 10	1, 9
# a comment, and a blank line

main.vl:5:31	10	9
calc.vl:6	v > hi	v >= hi
$ edit patch --from $T/inputs/patchat-list.txt
patched 3 sites	2 files	+3 -3 lines
% git diff --stat | tail -1
 2 files changed, 3 insertions(+), 3 deletions(-)
% git checkout -q .
## The same list on stdin: `--from -`, and `edit apply --at`.
$ edit patch --from - < $T/inputs/patchat-list.txt
patched 3 sites	2 files	+3 -3 lines
% git checkout -q .
$ edit apply --at < $T/inputs/patchat-list.txt
patched 3 sites	2 files	+3 -3 lines
% git checkout -q .
## Every patch is placed before any is written: the ones that do not
## match are named, each by its number and position, and nothing is
## written.
% cat $T/inputs/patchat-bad.txt
main.vl:4	0, 10	1, 9
main.vl:6	x	z
main.vl:5	nothere	q
calc.vl:99	v	w
main.vl:6:9	y	b
$ edit patch --from $T/inputs/patchat-bad.txt
error patch.ambiguous: patch 2 (main.vl:6): OLD 'x' is on that line 2 times (columns 5, 13): name one, main.vl:6:5
error patch.no-match: patch 3 (main.vl:5): OLD 'nothere' is not on that line: let y = calc::clamp(b, 0, 10);
error patch.no-match: patch 4 (calc.vl:99): OLD 'v': the file has no such line
error patch.sites: 3 of 5 patches do not match; nothing written (--keep-going writes the 2 that do)
[exit 1]
% git status --short
## --keep-going writes the ones that match (exit 1: some were left out).
$ edit patch --from $T/inputs/patchat-bad.txt --keep-going
patched 2 sites of 5	main.vl	+2 -2 lines
error patch.ambiguous: patch 2 (main.vl:6): OLD 'x' is on that line 2 times (columns 5, 13): name one, main.vl:6:5
error patch.no-match: patch 3 (main.vl:5): OLD 'nothere' is not on that line: let y = calc::clamp(b, 0, 10);
error patch.no-match: patch 4 (calc.vl:99): OLD 'v': the file has no such line
warning patch.sites: 3 of 5 patches do not match and are left out; the other 2 are written
[exit 1]
% git diff | grep '^[-+] '
-    let x = calc::clamp(a, 0, 10);
+    let x = calc::clamp(a, 1, 9);
-    x + y + x
+    x + b + x
% git checkout -q .
## The edit is checked as any other: new errors, nothing written.
$ edit patch --at main.vl:4 --old 'calc::clamp' --new 'calc::clump'
main.vl:4:13: error[type error] no 'clump' in module 'calc' | help: did you mean 'clamp'? | try: volec fix --suggested main.vl  [edited: crate::total]
error edit.breaks: 1 new error; nothing written; the error: main.vl:4:13: no 'clump' in module 'calc'
note edit.together: several steps are one call, checked at its end: `edit patch NAME --old A --new B --old C --new D` (`--in OTHER` before another item's pairs), `edit apply FILE`; or this step alone with --no-check
try: volec edit patch --at main.vl:4 --old calc::clamp --new calc::clump --no-check
[exit 1]
## Usage.
$ edit patch total --at main.vl:4 --old a --new b
error edit.usage: --at and --from name positions: no TARGET, --in, --pairs, --loose, --nth or --all with them
try: volec edit patch NAME --old OLD --new NEW
[exit 2]
$ edit patch --at main.vl --old a --new b
error edit.usage: --at takes a position, FILE:LINE or FILE:LINE:COL
try: volec edit patch NAME --old OLD --new NEW
[exit 2]
$ edit patch --old a --new b --at main.vl:4
error edit.usage: with --at, every pair follows an --at FILE:LINE
try: volec edit patch NAME --old OLD --new NEW
[exit 2]
$ edit patch --from $T/inputs/batch-queries.txt
error patch.format: the list's line 2: three fields, two tabs between them, are needed; a line is FILE:LINE[:COL]<TAB>OLD<TAB>NEW (\t, \n, \\ in the texts)
[exit 2]
$ edit apply --keep-going < $T/inputs/patchat-list.txt
error edit.usage: --keep-going is for --at
try: volec edit apply items.vl --dry-run
[exit 2]
