## The refactorings on calls with named arguments (0.15,
## tests/refactor/args015/; 0.28.0: no parameter has a default value):
## `--add 'x: T = V'` adds the parameter and writes V into every call, by
## label after a named argument (--fill-calls asks for the same);
## --rename-param renames the labels; --remove takes the argument by
## label or position; --reorder writes a call with labels in the new
## order; inline puts in labelled arguments by parameter.
$ check
ok: 0 errors in main.vl (1 file, 0 shaders)
$ refactor signature area --add 'scale: i64 = 2' --dry-run
--- a/main.vl
+++ b/main.vl
@@ -3 +3 @@
-fn area(w: i64, h: i64, depth: i64) -> i64 {
+fn area(w: i64, h: i64, depth: i64, scale: i64) -> i64 {
@@ -24,4 +24,4 @@
-    let a = area(2, 1, 1);
-    let b = area(2, h: 3, depth: 1);
-    let c = area(2, 3, depth: 4);
-    let d = area(2, h: 1, depth: 5);
+    let a = area(2, 1, 1, 2);
+    let b = area(2, h: 3, depth: 1, scale: 2);
+    let c = area(2, 3, depth: 4, scale: 2);
+    let d = area(2, h: 1, depth: 5, scale: 2);
$ refactor signature area --add 'scale: i64 = 2' --fill-calls --dry-run
--- a/main.vl
+++ b/main.vl
@@ -3 +3 @@
-fn area(w: i64, h: i64, depth: i64) -> i64 {
+fn area(w: i64, h: i64, depth: i64, scale: i64) -> i64 {
@@ -24,4 +24,4 @@
-    let a = area(2, 1, 1);
-    let b = area(2, h: 3, depth: 1);
-    let c = area(2, 3, depth: 4);
-    let d = area(2, h: 1, depth: 5);
+    let a = area(2, 1, 1, 2);
+    let b = area(2, h: 3, depth: 1, scale: 2);
+    let c = area(2, 3, depth: 4, scale: 2);
+    let d = area(2, h: 1, depth: 5, scale: 2);
$ refactor signature area --add 'first: i64 = 0' --at 0 --dry-run
--- a/main.vl
+++ b/main.vl
@@ -3 +3 @@
-fn area(w: i64, h: i64, depth: i64) -> i64 {
+fn area(first: i64, w: i64, h: i64, depth: i64) -> i64 {
@@ -24,4 +24,4 @@
-    let a = area(2, 1, 1);
-    let b = area(2, h: 3, depth: 1);
-    let c = area(2, 3, depth: 4);
-    let d = area(2, h: 1, depth: 5);
+    let a = area(0, 2, 1, 1);
+    let b = area(0, 2, h: 3, depth: 1);
+    let c = area(0, 2, 3, depth: 4);
+    let d = area(0, 2, h: 1, depth: 5);
$ refactor signature area --rename-param h height --dry-run
--- a/main.vl
+++ b/main.vl
@@ -3,2 +3,2 @@
-fn area(w: i64, h: i64, depth: i64) -> i64 {
-    w * h * depth
+fn area(w: i64, height: i64, depth: i64) -> i64 {
+    w * height * depth
@@ -25 +25 @@
-    let b = area(2, h: 3, depth: 1);
+    let b = area(2, height: 3, depth: 1);
@@ -27 +27 @@
-    let d = area(2, h: 1, depth: 5);
+    let d = area(2, height: 1, depth: 5);
$ refactor signature label --remove unused --dry-run
--- a/main.vl
+++ b/main.vl
@@ -7 +7 @@
-fn label(n: i64, unused: i64, wide: bool) -> i64 {
+fn label(n: i64, wide: bool) -> i64 {
@@ -29 +29 @@
-    let f = label(1, unused: 0, wide: true) + label(2, 0, false) + label(3, 0, wide: false);
+    let f = label(1, wide: true) + label(2, false) + label(3, wide: false);
$ refactor signature area --reorder w,depth,h --dry-run
--- a/main.vl
+++ b/main.vl
@@ -3 +3 @@
-fn area(w: i64, h: i64, depth: i64) -> i64 {
+fn area(w: i64, depth: i64, h: i64) -> i64 {
@@ -25,3 +25,3 @@
-    let b = area(2, h: 3, depth: 1);
-    let c = area(2, 3, depth: 4);
-    let d = area(2, h: 1, depth: 5);
+    let b = area(2, depth: 1, h: 3);
+    let c = area(2, depth: 4, h: 3);
+    let d = area(2, depth: 5, h: 1);
$ refactor signature Box::grow --rename-param times n --dry-run
--- a/main.vl
+++ b/main.vl
@@ -18,2 +18,2 @@
-    fn grow(&mut self, by: i64, times: i64) {
-        self.w += by * times;
+    fn grow(&mut self, by: i64, n: i64) {
+        self.w += by * n;
@@ -31 +31 @@
-    x.grow(2, times: 3);
+    x.grow(2, n: 3);
$ refactor inline twice --dry-run
--- a/main.vl
+++ b/main.vl
@@ -11,4 +10,0 @@
-fn twice(x: i64, k: i64) -> i64 {
-    x * k
-}
-
@@ -28 +24 @@
-    let e = twice(3, 2) + twice(4, k: 5);
+    let e = 3 * 2 + 4 * 5;
## Written: the program still runs.
$ refactor signature area --reorder w,depth,h
reordered the parameters of crate::area, 4 calls	main.vl	+4 -4 lines
% "$COMPILER" main.vl -o prog && ./prog && echo ran
ran
ok: built prog
