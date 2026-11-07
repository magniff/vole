## fix --edition rust (0.27.4, gate 3's third wall): `&a as *u8` of an
## array is `a.as_mut_ptr() as *mut u8` (Rust casts no `&[T; N]` to an
## element pointer; `as_ptr` when `a` is a `let`); a static's `.len()`
## inside its `unsafe { }`, not `unsafe { S.len }()`; a `u64` or `u8`
## index cast to usize as an i64 one is. Written, then built and run in
## the rust edition with the MVS program's output.
$ fix --edition rust --list-left main.vl
fixed, 4 '&x's to '&mut x', 1 var to 'let mut', 2 '.len's to '.len()', 2 integers annotated, 1 static var to 'static mut', 4 types, 1 text view to &str, 3 static mut uses put in unsafe, 6 indexes cast to usize	main.vl	+12 -11 lines
% cat main.vl
// fix --edition rust (0.27.4, gate 3's third wall): an array's address
// cast to a raw pointer is its first element's (`a.as_mut_ptr() as *mut
// u8`, `as_ptr` for a `let` one); a static's `.len` is closed after its
// `()`; an index of any integer type is cast to usize.
static mut SRC: &str = "";

fn sys(p: *mut u8, n: i64) -> i64 {
    unsafe { (*p.add(0)) as i64 + n }
}

fn sum3(p: *mut i64) -> i64 {
    unsafe { (*p.add(0)) + (*p.add(1)) + (*p.add(2)) }
}

fn main() {
    let mut attr: [i64; 4] = [7i64, 0, 0, 0];
    let st: [i64; 3] = [1i64, 2, 3];
    unsafe { SRC = "hello"; }
    let n = unsafe { SRC.len() };
    let k: u64 = 2;
    let m: u8 = 1;
    println("{} {} {} {}", sys(attr.as_mut_ptr() as *mut u8, 1), sum3(st.as_ptr() as *mut i64), n, unsafe { SRC.len() } + 1);
    println("{} {}", st[k as usize], attr[m as usize]);
}
// EDITION: rust
$ main.vl -o prog
ok: built prog
% ./prog
8 6 5 6
3 0
