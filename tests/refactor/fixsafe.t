## (0.25.2.1) fix --suggested makes only the fixes that keep what the
## program means (tests/refactor/fixsafe/; each case is a wrong fix from
## the 0.25.2 eval, evals/tasks/0.25.2/*/ANALYSIS.md). Refused, each
## with a `note fix.refused` saying why: a fix with which the edited
## program has a new error (deferred's `use` of a function where a bool
## goes), std's function for a method that takes another type (ocean's
## kind: `std::is_digit(d)` of an i32), a cast of a cast
## (cloth: the annotation is the fix), a conversion that loses the value
## (`t as u8`), a did-you-mean naming the function the call is in (it
## would recurse). Not added: a second import of a name a use line's fix
## already imports (sdftext).
$ check
main.vl:13:5: error[type error] no method 'is_ascii_digit' on type 'i32' | help: 'is_ascii_digit' is no method: std's function `is_digit` takes the value as its first argument | try: std::is_digit(d) | try: volec fix --suggested main.vl
main.vl:23:8: error[type error] undefined variable 'check' | help: add `use std::gpu::wgsl::uniformity::check;` | try: volec fix --suggested main.vl
main.vl:34:5: error[type error] undefined variable 'readback' | help: did you mean 'read_back'? | try: volec fix --suggested main.vl
glyphs.vl:3:12: error[type error] unresolved import 'mathx::sqr' | help: did you mean 'sqrt'? | try: volec fix --suggested main.vl
glyphs.vl:6:5: error[type error] undefined variable 'sqrt' | help: add `use crate::mathx::sqrt;` | try: volec fix --suggested main.vl
casts.vl:7:16: error[type error] expected 'f64', got 'f32' | help: only widening is implicit: convert explicitly | try: (m[k] as f32) as f64 | try: volec fix --suggested main.vl
casts.vl:9:5: error[type error] expected '[f32; 4]', got '[f64; 4]' | help: 'r' has its literals' type: annotate it where it is made (the note) | note: casts.vl:5:5: 'r' is '[f64; 4]' from its literals (a float literal is f64, an integer one i64, where nothing gives their type): annotate it, `var r: [f32; 4] = ...` | try: volec edit patch casts.vl:5 --old 'var r =' --new 'var r: [f32; 4] =' main.vl | try: volec fix --suggested main.vl
casts.vl:13:17: error[type error] expected 'u8', got 'i64' | help: only widening is implicit: convert explicitly | try: t as u8 | try: volec fix --suggested main.vl
marks.vl:10:9: error[conv.marker] 'ui' is lent inout here (the callee may change it): mark it '&ui' | help: an inout parameter takes '&place'; when the callee never changes it, take it let: 'volec refactor signature F --convention x let' | try: volec edit patch marks.vl:10 --old '(ui' --new '(&ui' | try: volec fix --suggested main.vl
marks.vl:11:10: error[conv.rust] '&mut ui' is Rust's spelling; an inout argument (the callee may change it) is marked '&x' | try: volec edit patch marks.vl:11 --old '&mut ui' --new '&ui' | try: volec fix --suggested main.vl
marks.vl:15:5: error[conv.rust] 'let mut' is Rust's spelling; a mutable binding is 'var x' | try: volec edit patch marks.vl:15 --old 'let mut' --new 'var' | try: volec fix --suggested main.vl
[exit 1]
$ fix --suggested --dry-run
--- a/glyphs.vl
+++ b/glyphs.vl
@@ -3 +3 @@
-use mathx::sqr;
+use mathx::sqrt;
--- a/casts.vl
+++ b/casts.vl
@@ -5 +5 @@
-    var r = [0.0; 4];
+    var r: [f32; 4] = [0.0; 4];
--- a/marks.vl
+++ b/marks.vl
@@ -10,2 +10,2 @@
-    bump(ui);
-    bump(&mut ui);
+    bump(&ui);
+    bump(&ui);
@@ -15 +15 @@
-    let mut u = Ui { n: 0 };
+    var u = Ui { n: 0 };
note fix.refused: main.vl:13:5: not applied: `std::is_digit(d)`: std's `is_digit` takes u8 and the value is i32: what it gives has another type
note fix.refused: main.vl:34:5: not applied: `read_back`: the name it puts there is the function the call is in: the call would call itself
note fix.refused: casts.vl:7:16: not applied: `(m[k] as f32) as f64`: it converts what a cast gives: the cast's type, or the type of the place it goes to, is what to change
note fix.refused: casts.vl:13:17: not applied: `t as u8`: the integer type it goes to does not hold every value: it wraps
note fix.refused: main.vl:23:8: not applied: `use std::gpu::wgsl::uniformity::check;`: the edited program has a new error with it: main.vl:25:8: error[type error] expected 'bool', got 'fn(let Front) -> ()'
## --codes: only the errors with these codes, the classes the check hook
## makes itself; --diff: the diff of what was written.
$ fix --suggested --codes conv.marker,conv.rust --diff
fixed 3 suggested fixes	marks.vl	+3 -3 lines
--- a/marks.vl
+++ b/marks.vl
@@ -10,2 +10,2 @@
-    bump(ui);
-    bump(&mut ui);
+    bump(&ui);
+    bump(&ui);
@@ -15 +15 @@
-    let mut u = Ui { n: 0 };
+    var u = Ui { n: 0 };
main.vl:13:5: error[type error] no method 'is_ascii_digit' on type 'i32' | help: 'is_ascii_digit' is no method: std's function `is_digit` takes the value as its first argument | try: std::is_digit(d) | try: volec fix --suggested main.vl
main.vl:23:8: error[type error] undefined variable 'check' | help: add `use std::gpu::wgsl::uniformity::check;` | try: volec fix --suggested main.vl
main.vl:34:5: error[type error] undefined variable 'readback' | help: did you mean 'read_back'? | try: volec fix --suggested main.vl
glyphs.vl:3:12: error[type error] unresolved import 'mathx::sqr' | help: did you mean 'sqrt'? | try: volec fix --suggested main.vl
glyphs.vl:6:5: error[type error] undefined variable 'sqrt' | help: add `use crate::mathx::sqrt;` | try: volec fix --suggested main.vl
casts.vl:7:16: error[type error] expected 'f64', got 'f32' | help: only widening is implicit: convert explicitly | try: (m[k] as f32) as f64 | try: volec fix --suggested main.vl
casts.vl:9:5: error[type error] expected '[f32; 4]', got '[f64; 4]' | help: 'r' has its literals' type: annotate it where it is made (the note) | note: casts.vl:5:5: 'r' is '[f64; 4]' from its literals (a float literal is f64, an integer one i64, where nothing gives their type): annotate it, `var r: [f32; 4] = ...` | try: volec edit patch casts.vl:5 --old 'var r =' --new 'var r: [f32; 4] =' main.vl | try: volec fix --suggested main.vl
casts.vl:13:17: error[type error] expected 'u8', got 'i64' | help: only widening is implicit: convert explicitly | try: t as u8 | try: volec fix --suggested main.vl
note fix.left: 8 errors left (above)
% cat marks.vl
// The mechanical classes the check hook makes itself (`--codes
// conv.marker,conv.rust`): a call's `&` marker, Rust's spellings.
pub struct Ui { pub n: i64 }

fn bump(ui: inout Ui) {
    ui.n += 1;
}

pub fn twice(ui: inout Ui) {
    bump(&ui);
    bump(&ui);
}

pub fn start() -> i64 {
    var u = Ui { n: 0 };
    twice(&u);
    u.n
}
## The rest: the use line and the annotation are made, the others refused.
$ fix --suggested
fixed 2 suggested fixes	2 files	+2 -2 lines
main.vl:13:5: error[type error] no method 'is_ascii_digit' on type 'i32' | help: 'is_ascii_digit' is no method: std's function `is_digit` takes the value as its first argument | try: std::is_digit(d) | try: volec fix --suggested main.vl
main.vl:23:8: error[type error] undefined variable 'check' | help: add `use std::gpu::wgsl::uniformity::check;` | try: volec fix --suggested main.vl
main.vl:34:5: error[type error] undefined variable 'readback' | help: did you mean 'read_back'? | try: volec fix --suggested main.vl
casts.vl:13:17: error[type error] expected 'u8', got 'i64' | help: only widening is implicit: convert explicitly | try: t as u8 | try: volec fix --suggested main.vl
note fix.refused: main.vl:13:5: not applied: `std::is_digit(d)`: std's `is_digit` takes u8 and the value is i32: what it gives has another type
note fix.refused: main.vl:34:5: not applied: `read_back`: the name it puts there is the function the call is in: the call would call itself
note fix.refused: casts.vl:7:16: not applied: `(m[k] as f32) as f64`: it converts what a cast gives: the cast's type, or the type of the place it goes to, is what to change
note fix.refused: casts.vl:13:17: not applied: `t as u8`: the integer type it goes to does not hold every value: it wraps
note fix.refused: main.vl:23:8: not applied: `use std::gpu::wgsl::uniformity::check;`: the edited program has a new error with it: main.vl:25:8: error[type error] expected 'bool', got 'fn(let Front) -> ()'
note fix.left: 4 errors left (above)
% cat glyphs.vl
// sdftext: the use line's name is misspelled; its fix imports sqrt, so
// the missing `use` of sqrt is not added again.
use mathx::sqrt;

pub fn dist(a: f64, b: f64) -> f64 {
    sqrt(a * a + b * b)
}
