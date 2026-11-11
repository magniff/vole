## The refactorings on 0.15's syntax that need no 0.15 checking
## (tests/refactor/shorthand015/): a field shorthand `S { x }` is both
## the field and the value, so a renamed field writes `S { y: x }` and a
## renamed local, parameter or const `S { x: y }`; inline puts `x: ARG`;
## --add writes the value into the calls (0.28.0: always; no parameter
## has a default value); extract-function and
## inline refuse `?`, which may return from the function (the program has
## the `?` stub's error).
$ refactor field P --rename x px --dry-run
--- a/main.vl
+++ b/main.vl
@@ -4 +4 @@
-#[derive(Clone, Copy)] struct P { x: i64, y: i64 }
+#[derive(Clone, Copy)] struct P { px: i64, y: i64 }
@@ -10 +10 @@
-    P { x, y }
+    P { px: x, y }
@@ -18 +18 @@
-    P { x, y: p.y }
+    P { px: x, y: p.y }
@@ -25 +25 @@
-    (q.x + q.y + c.LIMIT - 17) as i32
+    (q.px + q.y + c.LIMIT - 17) as i32
$ refactor rename main.vl:9:9 yy --dry-run
--- a/main.vl
+++ b/main.vl
@@ -9,2 +9,2 @@
-    let y = k * 2;
-    P { x, y }
+    let yy = k * 2;
+    P { x, y: yy }
$ refactor signature make --rename-param x xx --dry-run
--- a/main.vl
+++ b/main.vl
@@ -8 +8 @@
-fn make(x: i64, k: i64) -> P {
+fn make(xx: i64, k: i64) -> P {
@@ -10 +10 @@
-    P { x, y }
+    P { x: xx, y }
$ refactor rename LIMIT MAXV --dry-run
--- a/main.vl
+++ b/main.vl
@@ -2 +2 @@
-const LIMIT: i64 = 10;
+const MAXV: i64 = 10;
@@ -14 +14 @@
-    Cap { LIMIT }
+    Cap { LIMIT: MAXV }
$ refactor inline shift --dry-run
--- a/main.vl
+++ b/main.vl
@@ -17,4 +16,0 @@
-fn shift(p: P, x: i64) -> P {
-    P { x, y: p.y }
-}
-
@@ -23 +19 @@
-    let q = shift(p, 3);
+    let q = P { x: 3, y: p.y };
$ refactor signature make --add 'z: i64 = 5' --fill-calls --dry-run
--- a/main.vl
+++ b/main.vl
@@ -8 +8 @@
-fn make(x: i64, k: i64) -> P {
+fn make(x: i64, k: i64, z: i64) -> P {
@@ -22 +22 @@
-    let p = make(1, 2);
+    let p = make(1, 2, 5);
$ refactor signature make --add 'z: i64 = 5' --at 0 --dry-run
--- a/main.vl
+++ b/main.vl
@@ -8 +8 @@
-fn make(x: i64, k: i64) -> P {
+fn make(z: i64, x: i64, k: i64) -> P {
@@ -22 +22 @@
-    let p = make(1, 2);
+    let p = make(5, 1, 2);
$ refactor extract-function half --lines 30-31 --to part --dry-run
error refactor.escapes: line 30 may return (`?`) from crate::half: out of lines 30-31, which NEW cannot do for its caller
try: volec query show main.vl:30
[exit 1]
$ refactor inline half --dry-run
error refactor.escapes: crate::half may return early (`?`), on line 30: inline takes a function that ends with its value
try: volec query show main.vl:30
[exit 1]
$ explain refactor.fill-calls
refactor.fill-calls: note, exit 0
`refactor signature FN --add 'x: T = V'` adds the parameter `x: T` and writes V into every call: by position, or `x: V` after a named argument. The `= V` is the tool's syntax for the value the calls get; no parameter has a default value (0.28.0; 0.15 to 0.27 declared V as x's default where the language allowed one, and this note said when the calls got it instead).
fix: Nothing to fix: every call passes the new argument (--fill-calls is taken and changes nothing).
example:
    note refactor.fill-calls: the calls get the value (a trait's function has no defaults)
## (0.16) A tool's name with its `-` lists its codes; a subcommand's own
## help.
$ explain same-output
same-output.differs	error, exit 1
same-output.no-compiler	error, exit 2
same-output.no-corpus	error, exit 2
same-output.not-run	warning
same-output.target	note
same-output.usage	error, exit 2
same-output.work	error, exit 2
$ edit apply --help
volec edit apply [FILE]   several items' new text in one checked edit (stdin without FILE)
blocks: @@ NAME (its new text), @@ new after|before NAME, @@ new in MODULE, @@ delete NAME,
@@ MODULE::use, @@ MODULE::header; or query show's output, changed
--show: the diff after; --dry-run: the diff only; --no-check: write despite new errors
