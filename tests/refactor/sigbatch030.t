## refactor signature --batch FILE, 0.30 (tests/refactor/sigbatch030/):
## the type changes of a file's lines, FN PARAM TYPE [DEFAULT], with one
## load and check before and one check after: one edit.
$ check
ok: 0 errors in main.vl (1 file, 0 shaders)
% cat changes.txt
# FN PARAM TYPE [DEFAULT]: a line each, quoted as in sh
first b &Buf
last b &Buf

scale k i64 '$k as i64'
scale x i64 '$x as i64'
$ refactor signature --batch changes.txt --dry-run
--- a/main.vl
+++ b/main.vl
@@ -7 +7 @@
-fn first(b: Buf) -> i64 {
+fn first(b: &Buf) -> i64 {
@@ -11 +11 @@
-fn last(b: Buf, n: i64) -> i64 {
+fn last(b: &Buf, n: i64) -> i64 {
@@ -15 +15 @@
-fn scale(x: i32, k: i32) -> i32 {
+fn scale(x: i64, k: i64) -> i32 {
@@ -21,2 +21,2 @@
-    let a = first(b) + last(b, b.len);
-    scale(a as i32, 2) + scale(scale(1, 2), 3)
+    let a = first(&b) + last(&b, b.len);
+    scale((a as i32) as i64, 2 as i64) + scale(scale(1 as i64, 2 as i64), 3 as i64)
note refactor.nested: 1 argument inside a rewritten one (or rewritten already) left as written; first: main.vl:22:32
## (an argument inside one that is rewritten already is left, and said)
$ refactor signature --batch changes.txt
changed 4 parameters (changes.txt), 8 calls	main.vl	+5 -5 lines
note refactor.nested: 1 argument inside a rewritten one (or rewritten already) left as written; first: main.vl:22:32
$ check
ok: 0 errors in main.vl (1 file, 0 shaders)
$ undo
undid changed 4 parameters (changes.txt), 8 calls	main.vl	+5 -5 lines
## A line that cannot be made ends it, with its place: nothing written.
$ refactor signature --batch bad_param.txt
error refactor.no-param: crate::first has no parameter 'nope': (b)
try: volec query def crate::first
error refactor.batch: bad_param.txt:2: the line's change cannot be made (above); nothing run
[exit 1]
$ refactor signature --batch bad_line.txt
error refactor.batch: bad_line.txt:1: a line is FN PARAM TYPE [DEFAULT], quoted as in sh (`f v '&mut [i64]' '&mut $v'`); nothing run
[exit 2]
$ refactor signature --batch nope.txt
error refactor.batch: cannot read 'nope.txt'
[exit 2]
$ refactor signature first --batch changes.txt
error refactor.usage: --batch FILE takes its changes from FILE's lines, FN PARAM TYPE [DEFAULT]
try: volec refactor signature --batch changes.txt --dry-run
[exit 2]
## On a program with errors, the calls in code the checker did not see
## are not changed: each is listed, FILE:L:C and the function.
$ refactor signature --batch broken/changes.txt --root broken/main.vl --dry-run
broken/main.vl:16:26	crate::first
--- a/broken/main.vl
+++ b/broken/main.vl
@@ -9 +9 @@
-fn first(b: Buf) -> i64 {
+fn first(b: &Buf) -> i64 {
@@ -15 +15 @@
-    let a = first(b);
+    let a = first(&b);
warning refactor.unchecked: 1 call in code the checker did not see (after an error, in a generic function never instantiated) is not changed: listed above, FILE:L:C and the function
