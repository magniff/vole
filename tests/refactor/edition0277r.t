## fix --edition rust (0.27.7): an address given where a raw pointer goes
## (edit_amp, place_mut). A mutable place's is `&mut x` (a `var`'s, a
## `var` array's element, an inout parameter's field), which Rust
## coerces to `*mut T`; a `let`'s is `&raw const x as *mut _` (rustc
## coerces a `&T` only to a `*const T`, E0308, as the rust edition does
## since D3.6a). Written, then built and run in the rust edition with
## the MVS program's output; the rustc twin agrees (rust_t_raw_address).
$ main.vl -o mvs
ok: built mvs
% ./mvs
2 6 1 1 41 8
$ fix --edition rust --list-left main.vl
fixed, 1 parameter to &mut T, 5 '&x's to '&mut x', 3 vars to 'let mut', 5 integers annotated, 2 types, 1 copy type derived Clone, Copy	main.vl	+17 -16 lines
$ fmt main.vl
note fmt.none: 1 file formatted already
% cat main.vl
// fix --edition rust (0.27.7): an address given where a raw pointer goes.
// A mutable place's is `&mut x`, which Rust coerces to `*mut T` (rustc
// coerces a `&T` only to a `*const T`, E0308): a `var`'s, an element of
// a `var` array, a field of an inout parameter's. A `let`'s is `&raw
// const x as *mut _`, there being no `mut` binding to lend.
#[derive(Clone, Copy)] struct C {
    n: i64,
    v: [i64; 2],
}

fn bump(p: *mut i64) {
    // UNSAFE: a raw pointer's write, the program's own out parameter.
    // SAFETY: every caller gives a live i64 it lends for the call.
    unsafe {
        *p += 1;
    }
}

fn peek(p: *mut i64) -> i64 {
    // UNSAFE: a raw pointer's read.
    // SAFETY: every caller gives a live i64.
    unsafe { *p }
}

fn through(c: &mut C) {
    bump(&mut c.n);
    bump(&mut c.v[1]);
}

fn main() {
    let mut x: i64 = 1;
    bump(&mut x);
    let mut a: [i64; 2] = [5i64, 6];
    bump(&mut a[0]);
    let mut c = C { n: 0, v: [0i64, 0] };
    through(&mut c);
    let k: i64 = 41;
    let r = peek(&raw const k as *mut _);
    let arr: [i64; 2] = [7i64, 8];
    let q = peek(&raw const arr[1] as *mut _);
    println("{} {} {} {} {} {}", x, a[0], c.n, c.v[1], r, q);
}
// EDITION: rust
$ main.vl -o prog
ok: built prog
% ./prog
2 6 1 1 41 8
