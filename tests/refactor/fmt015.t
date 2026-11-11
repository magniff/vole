## volec fmt on the syntax of 0.15 (tests/refactor/fmt015/): `?` after
## its operand, `name: value` arguments (0.28.0: no `= default`), field
## shorthand and `#[derive(A, B)]` spaced as Rust does; an f-string's text
## as written, its holes laid out as expressions (no space inside the
## braces, none before a spec), and no line broken inside one; `>>>`
## closing type arguments as written. fmt needs no checking: the program
## has 0.15's stub errors.
$ fmt --dry-run main.vl
--- a/main.vl
+++ b/main.vl
@@ -2 +2 @@
-#[derive(PartialEq, Eq,PartialOrd, Ord ,Debug, Clone, Copy)]
+#[derive(PartialEq, Eq, PartialOrd, Ord, Debug, Clone, Copy)]
@@ -5 +5 @@
-#[derive( Clone, Copy )]
+#[derive(Clone, Copy)]
@@ -11 +11 @@
-fn scale(a: i64, b:i64, c : i64 ) -> i64 { a*b+c }
+fn scale(a: i64, b: i64, c: i64) -> i64 { a * b + c }
@@ -14,2 +14,2 @@
-    let v = o ?;
-    Some(v/2)
+    let v = o?;
+    Some(v / 2)
@@ -23,2 +23,2 @@
-    let p = P{x,y};
-    let n = scale(1, b:5, c : 6) + scale(1,2,c: 4);
+    let p = P { x, y };
+    let n = scale(1, b: 5, c: 6) + scale(1, 2, c: 4);
$ fmt
formatted	main.vl	+7 -7 lines
% cat main.vl
// The syntax of 0.15 laid out by hand, for `volec fmt`.
#[derive(PartialEq, Eq, PartialOrd, Ord, Debug, Clone, Copy)]
struct P { x: i64, y: i64 }

#[derive(Clone, Copy)]
#[repr(C)]
enum E { A, B(i64) }

trait Conv<T> { fn conv(x: &T) -> Self; }

fn scale(a: i64, b: i64, c: i64) -> i64 { a * b + c }

fn half(o: Option<i64>) -> Option<i64> {
    let v = o?;
    Some(v / 2)
}

fn nested<T: Conv<Vec<i64>>>(x: T) -> i64 { 0 }

fn main() {
    let x: i64 = 1;
    let y: i64 = 2;
    let p = P { x, y };
    let n = scale(1, b: 5, c: 6) + scale(1, 2, c: 4);
    println("x = {x}, y = {y} {:>5} {{text}} {p:?} {:08.3}", p.x, n + 1);
    println("the first value is {x} and the second is {} at last",
        scale(x, b: y, c: x * y + 1000000));
}
// EDITION: rust
$ fmt --check
