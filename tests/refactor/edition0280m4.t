## (0.28.0) MVS's `&v[a..b]` where an inout view goes, a function's
## `-> inout [T]` result (the checker's inout borrow of the view), is
## `&mut v[a..b]`. 0.27.8 kept the `&` as written, a `&[i64]` where
## `&mut [i64]` goes (a type error). An argument to an inout parameter
## (`fill(&v[3..5], 7)`) was `&mut` already.
$ main.vl -o mvs
ok: built mvs
% ./mvs
[9, 1, 2, 7, 7]
$ fix --edition rust main.vl
fixed, 2 parameters to &mut T, 1 view to &[T], 2 '&x's to '&mut x', 1 var to 'let mut', 1 '.len' to '.len()', 1 type, 1 index cast to usize	main.vl	+7 -6 lines
% cat main.vl
fn front(v: &mut Vec<i64, Gpa>, n: i64) -> &mut [i64] { &mut v[0..n as usize] }

fn fill(s: &mut [i64], x: i64) {
    for i in 0..s.len() {
        s[i] = x;
    }
}

fn main(gpa: Gpa) {
    let mut v: Vec<i64, Gpa> = Vec::new_in(gpa);
    for i in 0..5 {
        v.push(i);
    }
    let f = front(&mut v, 2);
    f[0] = 9;
    fill(&mut v[3..5], 7);
    println("{v:?}");
}
// EDITION: rust
$ check main.vl
ok: 0 errors in main.vl
$ main.vl -o prog
ok: built prog
% ./prog
[9, 1, 2, 7, 7]
