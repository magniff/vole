## volec fix --only usize (0.26.2) on a program written against 0.26.1's
## std, where lengths and indices were i64 (tests/refactor/usize/): a usize
## length that meets an i64 becomes `as i64` (a comparison's operand, a
## typed let), an i64 passed as a length or an index `as usize`
## (`truncate`, `swap`); the migrated program prints what it printed under
## 0.26.1, and a second run finds nothing to do.
$ fix --only usize --dry-run
--- a/main.vl
+++ b/main.vl
@@ -9 +9 @@
-    while i < v.len() {
+    while i < v.len() as i64 {
@@ -17 +17 @@
-    let n: i64 = b.len;
+    let n: i64 = b.len as i64;
@@ -27 +27 @@
-    v.truncate(keep);
+    v.truncate(keep as usize);
@@ -29 +29 @@
-    v.swap(a, 3);
+    v.swap(a as usize, 3);
$ fix --only usize
fixed 4 suggested fixes	main.vl	+4 -4 lines
% "$COMPILER" main.vl -o prog && ./prog
14 9 3
ok: built prog
$ fix --only usize
note fix.none: nothing to fix
