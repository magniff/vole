## fix --edition rust (0.27.6): hoist_arg_edits. An argument of a call
## that takes cx `&mut`, which itself calls with cx, is computed first in
## a block (nested, in a condition, after a plain argument). Written,
## formatted, then built and run in the rust edition with the MVS
## program's output; the rustc twin agrees (rust_t_hoist_arg).
$ main.vl -o mvs
ok: built mvs
% ./mvs
804 7
$ fix --edition rust --list-left main.vl
fixed, 3 parameters to &mut T, 1 sink parameter to T, 10 '&x's to '&mut x', 1 var to 'let mut', 1 integer annotated, 1 type, 1 copy type derived Clone, Copy	main.vl	+12 -11 lines
$ fmt main.vl
formatted	main.vl	+2 -1 lines
% cat main.vl
// fix --edition rust (0.27.6): an argument that calls with the root a
// call takes `&mut` is computed first, `{ let at_arg1 = inner(cx, v);
// outer(cx, at_arg1) }`: Rust's reborrow of cx for the first argument
// lives through the arguments, so the inner call's cx is a second mutable
// borrow (rustc E0499, also for a raw-pointer parameter, D3.6). Only when
// every argument before it is plain: MVS's order is kept.
#[derive(Clone, Copy)] struct C {
    x: i64,
}

fn outer(cx: &mut C, v: i64) -> i64 {
    cx.x += 1;
    cx.x + v
}

fn inner(cx: *mut C, v: i64) -> i64 {
    // UNSAFE: the test's raw pointer, as middle/ir's ir_val takes it.
    // SAFETY: cx points to the live C main made; nothing else uses it here.
    unsafe { (*cx).x * 10 + v }
}

fn both(cx: &mut C, a: i64, b: i64) -> i64 {
    cx.x += a;
    cx.x * 100 + b
}

fn go(cx: &mut C, v: i64) -> i64 {
    let a = { let at_arg1 = inner(cx, v); outer(cx, at_arg1) };
    let b = { let at_arg1 = inner(cx, inner(cx, v)); outer(cx, at_arg1) };
    let c: i64 = if v > 0 && { let at_arg1 = inner(cx, 1); outer(cx, at_arg1) } > 0 { 1 }
        else { 0 };
    let d = { let at_arg2 = inner(cx, 2); both(cx, v, at_arg2) };
    a + b + c + d
}

fn main() {
    let mut c = C { x: 1 };
    println("{} {}", go(&mut c, 3), c.x);
}
// EDITION: rust
$ main.vl -o prog
ok: built prog
% ./prog
804 7
