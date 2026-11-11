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
## already imports (sdftext). (0.25.4) An error whose fix is refused
## before it is made (all but the new-error one) has no `try: volec fix
## --suggested` line: the error's own try: shows the text to judge.
## (0.28.0, the rust edition) ocean's i32 has no `is_ascii_digit` and no std
## function is offered (std2 has Rust's methods); cloth's `r` gets no
## annotation (rustc would infer [f32; 4]; a gap of the rust edition's
## literals), so only the use line is made. MVS's marks.vl (the conv.marker
## and conv.rust classes, `--codes`) is gone with MVS.
$ check
main.vl:13:5: error[type error] no method 'is_ascii_digit' on type 'i32' | help: no method of that name; the nearest: 'is_positive', 'is_negative'
main.vl:23:8: error[type error] undefined variable 'check' | help: add `use std::gpu::wgsl::uniformity::check;` | try: volec fix --suggested main.vl
main.vl:34:5: error[type error] undefined variable 'readback' | help: did you mean 'read_back'?
glyphs.vl:3:12: error[type error] unresolved import 'mathx::sqr' | help: did you mean 'sqrt'? | try: volec fix --suggested main.vl
glyphs.vl:6:5: error[type error] undefined variable 'sqrt' | help: add `use crate::mathx::sqrt;` | try: volec fix --suggested main.vl
casts.vl:7:25: error[type error] expected 'f64', got 'f32' | help: only widening is implicit: convert explicitly | try: (m[k as usize] as f32) as f64
casts.vl:9:5: error[type error] expected '[f32; 4]', got '[f64; 4]'
casts.vl:13:17: error[type error] expected 'u8', got 'i64' | help: only widening is implicit: convert explicitly | try: t as u8
[exit 1]
$ fix --suggested --dry-run
--- a/glyphs.vl
+++ b/glyphs.vl
@@ -3 +3 @@
-use mathx::sqr;
+use mathx::sqrt;
note fix.refused: main.vl:34:5: not applied: `read_back`: the name it puts there is the function the call is in: the call would call itself
note fix.refused: casts.vl:7:25: not applied: `(m[k as usize] as f32) as f64`: it converts what a cast gives: the cast's type, or the type of the place it goes to, is what to change
note fix.refused: casts.vl:13:17: not applied: `t as u8`: the integer type it goes to does not hold every value: it wraps
note fix.refused: main.vl:23:8: not applied: `use std::gpu::wgsl::uniformity::check;`: the edited program has a new error with it: main.vl:25:8: error[type error] generic function 'check' needs its type arguments to be used as a value ('f::<T>')
## The rest: the use line and the annotation are made, the others refused.
$ fix --suggested
fixed 1 suggested fix	glyphs.vl	+1 -1 lines
main.vl:13:5: error[type error] no method 'is_ascii_digit' on type 'i32' | help: no method of that name; the nearest: 'is_positive', 'is_negative'
main.vl:23:8: error[type error] undefined variable 'check' | help: add `use std::gpu::wgsl::uniformity::check;` | try: volec fix --suggested main.vl
main.vl:34:5: error[type error] undefined variable 'readback' | help: did you mean 'read_back'?
casts.vl:7:25: error[type error] expected 'f64', got 'f32' | help: only widening is implicit: convert explicitly | try: (m[k as usize] as f32) as f64
casts.vl:9:5: error[type error] expected '[f32; 4]', got '[f64; 4]'
casts.vl:13:17: error[type error] expected 'u8', got 'i64' | help: only widening is implicit: convert explicitly | try: t as u8
note fix.refused: main.vl:34:5: not applied: `read_back`: the name it puts there is the function the call is in: the call would call itself
note fix.refused: casts.vl:7:25: not applied: `(m[k as usize] as f32) as f64`: it converts what a cast gives: the cast's type, or the type of the place it goes to, is what to change
note fix.refused: casts.vl:13:17: not applied: `t as u8`: the integer type it goes to does not hold every value: it wraps
note fix.refused: main.vl:23:8: not applied: `use std::gpu::wgsl::uniformity::check;`: the edited program has a new error with it: main.vl:25:8: error[type error] generic function 'check' needs its type arguments to be used as a value ('f::<T>')
note fix.left: 6 errors left (above)
% cat glyphs.vl
// sdftext: the use line's name is misspelled; its fix imports sqrt, so
// the missing `use` of sqrt is not added again.
use mathx::sqrt;

pub fn dist(a: f64, b: f64) -> f64 {
    sqrt(a * a + b * b)
}
