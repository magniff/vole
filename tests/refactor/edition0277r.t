## fix --edition rust (0.27.7): an address given where a raw pointer goes
## (edit_amp). A mutable place's is `&mut x` (a `var`'s, a `var` array's
## element, an inout parameter's field), which Rust coerces to `*mut T`
## (rustc coerces a `&T` only to a `*const T`, E0308, as the rust
## edition does since D3.6a). A `let`'s or a by-value parameter's is
## `&mut x` with its binding made `mut` (`let mut k`, `fn twice(mut n:
## i64)`): the callee may write through the pointer, as `bump` does to
## `k` before main reads it, and a write through `&raw const k` would be
## undefined. Written, then built and run in the rust edition with the
## MVS program's output; the rustc twin agrees, at -O too
## (rust_t_raw_address).
$ main.vl -o mvs
ok: built mvs
% ./mvs
2 6 1 1 42 42 8 10
$ fix --edition rust --list-left main.vl
fixed, 1 parameter to &mut T, 1 '&x' to '&mut x', 6 vars to 'let mut', 5 integers annotated, 2 types, 1 copy type derived Clone, Copy	main.vl	+20 -19 lines
$ fmt main.vl
note fmt.none: 1 file formatted already
% cat main.vl
// fix --edition rust (0.27.7): an address given where a raw pointer goes.
// A mutable place's is `&mut x`, which Rust coerces to `*mut T` (rustc
// coerces a `&T` only to a `*const T`, E0308): a `var`'s, an element of
// a `var` array, a field of an inout parameter's. A `let`'s, or a
// by-value parameter's, is `&mut x` with its binding made `mut`: the
// callee may write through the pointer (`bump` of `k`, read after).
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

fn twice(mut n: i64) -> i64 {
    bump(&mut n);
    n * 2
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
    let mut k: i64 = 41;
    bump(&mut k);
    let r = peek(&mut k);
    let mut arr: [i64; 2] = [7i64, 8];
    let q = peek(&mut arr[1]);
    println("{} {} {} {} {} {} {} {}", x, a[0], c.n, c.v[1], r, k, q, twice(4));
}
// EDITION: rust
$ main.vl -o prog
ok: built prog
% ./prog
2 6 1 1 42 42 8 10
