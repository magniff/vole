## The edition from the environment or the flag (0.28.0;
## tests/refactor/envedition/): a rust program whose root has no
## `// EDITION: rust` line, read as rust because VOLE_EDITION=rust or
## `--edition rust` says so. The writing tools take it as they take the
## line: a fix is that fix (not the translation of an MVS program, which
## wrote `**n += 1` and an `// EDITION: rust` last line), and an edit's
## check reports the edit's errors alone.
% VOLE_EDITION=rust volec check main.vl
main.vl:15:10: error[type error] expected '&mut i64', got '&i64' | help: the types differ in mutability (rustc E0308): the parameter takes an exclusive reference, `&mut x` | try: &mut x | try: volec fix --suggested main.vl
main.vl:17:13: error[unsafe] calling a C function is unsafe | help: put it in an `unsafe { ... }` block, or the function's body in an `unsafe fn` (the try: line wraps every such place) | try: volec fix --only unsafe main.vl
[exit 1]
## The errors' exact fixes, under the variable; the diff first.
% VOLE_EDITION=rust volec fix --suggested --dry-run main.vl
--- a/main.vl
+++ b/main.vl
@@ -15 +15 @@
-    bump(&x);
+    bump(&mut x);
% VOLE_EDITION=rust volec fix --suggested main.vl
fixed 1 suggested fix	main.vl	+1 -1 lines
main.vl:17:13: error[unsafe] calling a C function is unsafe | help: put it in an `unsafe { ... }` block, or the function's body in an `unsafe fn` (the try: line wraps every such place) | try: volec fix --only unsafe main.vl
note fix.left: 1 error left (above)
## The flag with a kind of fix is the same.
$ --edition rust fix --only unsafe
fixed 1 unsafe block	main.vl	+1 -1 lines
% cat main.vl
extern "C" {
    fn sqrt(x: f64) -> f64;
}

fn bump(n: &mut i64) {
    *n += 1;
}

fn show(xs: &[i64]) {
    println("{}", xs.len());
}

fn main() {
    let mut x = 1;
    bump(&mut x);
    show(&[x]);
    let r = unsafe { sqrt(x as f64) };
    println("{r:.4}");
}
% VOLE_EDITION=rust volec main.vl -o prog && ./prog
1
1.4142
ok: built prog
## An edit that breaks the program: its error, nothing else.
% VOLE_EDITION=rust volec edit patch show --old 'xs.len()' --new 'xs.len() + nope' main.vl
main.vl:10:30: error[type error] undefined variable 'nope'  [edited: crate::show]
error edit.breaks: 1 new error; nothing written; the error: main.vl:10:30: undefined variable 'nope'
note edit.together: several steps are one call, checked at its end: `edit patch NAME --old A --new B --old C --new D` (`--in OTHER` before another item's pairs), `edit apply FILE`; or this step alone with --no-check
try: volec edit patch show --old 'xs.len()' --new 'xs.len() + nope' main.vl --no-check
[exit 1]
## Nothing to fix says so, whatever kind.
% VOLE_EDITION=rust volec fix main.vl
note fix.none: nothing to fix
% VOLE_EDITION=rust volec fix --only alloc main.vl
note fix.none: nothing to fix
% git status --short
 M main.vl
?? prog
