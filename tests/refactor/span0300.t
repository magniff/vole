## 0.30: spans that are no single definition (the 0.29 tool diaries,
## theme B.4). A run of adjacent items, `NAME --to LAST`, is replaced or
## deleted in one checked step: with it one step per item, each alone
## broke the program.
$ edit replace one --to two --show < $T/inputs/span-items.vl
replaced crate::one through crate::two	main.vl	+2 -4 lines
// main.vl:13
13	// One and two, as one.
// main.vl:17: 1 line removed after line 17
// main.vl:19
19	    one() + 1
% git checkout -q .
$ edit delete two --to three --dry-run
--- a/main.vl
+++ b/main.vl
@@ -19,11 +18,0 @@
-// Two.
-fn two() -> i64 {
-    2
-}
-
-#[inline]
-// Three.
-fn three() -> i64 {
-    3
-}
-
main.vl:21:26: error[type error] undefined variable 'two' | help: std's names: `volec guide std`  [in crate::main]
warning edit.breaks: 1 new error (1 in crate::main, which the edit does not change) (dry run); the error: main.vl:21:26: undefined variable 'two'
[exit 1]
$ edit delete two --to one
error edit.layout: crate::two and crate::one: the second is not after the first; --to names the last of a run of adjacent items
[exit 1]
$ edit delete one --to P::twice
error edit.layout: crate::one and crate::P::twice: the second is not after the first; --to names the last of a run of adjacent items
[exit 1]
## An impl block has no name: the FILE:LINE of its header is the block
## (the line once resolved to the type it is for, and `edit delete`
## took the struct). Its comment lines stay unless the new text has its own.
$ edit replace main.vl:6 --show < $T/inputs/span-impl.vl
replaced the impl block at main.vl:6	main.vl	+1 -2 lines
// main.vl:6: 1 line removed after line 6
// main.vl:8
8	        self.x + self.x
% git checkout -q .
$ edit delete main.vl:6 --dry-run
--- a/main.vl
+++ b/main.vl
@@ -5,8 +4,0 @@
-// The methods of P.
-impl P {
-    // x, doubled.
-    fn twice(&self) -> i64 {
-        self.x * 2
-    }
-}
-
main.vl:24:6: error[type error] no method 'twice' on type 'P' | try: volec query items P main.vl  [in crate::main]
warning edit.breaks: 1 new error (1 in crate::main, which the edit does not change) (dry run); the error: main.vl:24:6: no method 'twice' on type 'P'
[exit 1]
## delete takes an item's leading comment lines and attributes with it.
$ edit delete one --dry-run
--- a/main.vl
+++ b/main.vl
@@ -13,6 +12,0 @@
-// One.
-// (a second line)
-fn one() -> i64 {
-    1
-}
-
main.vl:26:18: error[type error] undefined variable 'one' | help: std's names: `volec guide std`  [in crate::main]
warning edit.breaks: 1 new error (1 in crate::main, which the edit does not change) (dry run); the error: main.vl:26:18: undefined variable 'one'
[exit 1]
$ edit delete three --dry-run
--- a/main.vl
+++ b/main.vl
@@ -24,6 +23,0 @@
-#[inline]
-// Three.
-fn three() -> i64 {
-    3
-}
-
main.vl:26:34: error[type error] undefined variable 'three' | help: std's names: `volec guide std`  [in crate::main]
warning edit.breaks: 1 new error (1 in crate::main, which the edit does not change) (dry run); the error: main.vl:26:34: undefined variable 'three'
[exit 1]
