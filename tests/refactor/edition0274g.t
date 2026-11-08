## fix --edition rust (0.27.4, gate 3): a raw pointer to views `*[u8]` is
## `*mut &[u8]` (its elements are views: `0 as *mut [u8]` would be a
## fat pointer no integer casts to), `&'static` but in a parameter's own
## type; `(&p[i]) as *u8`, a borrow of a raw pointer's element cast to a
## raw pointer, is `(p.add(i)) as *mut u8`. Written, then built and run
## in the rust edition with the MVS program's output.
$ main.vl -o mvs
ok: built mvs
% ./mvs
106 6 true
$ fix --edition rust --list-left main.vl
fixed, 6 views to &[T], 3 '&x's to '&mut x', 1 var to 'let mut', 1 integer annotated, 1 static var to 'static mut', 3 text literals to bytes, 7 types, 1 static use through its accessors, 2 indexes cast to usize	main.vl	+15 -9 lines
% cat main.vl
// fix --edition rust (0.27.4, gate 3): a raw pointer to views, `*[u8]`
// (a table of views, an out parameter), is `*mut &[u8]` (`&'static` but
// in a parameter's own type); a borrow of a raw pointer's element cast
// to a raw pointer, `(&p[i]) as *u8`, is `(p.add(i)) as *mut u8`.
static mut STRS: *mut &'static [u8] = 0 as *mut &'static [u8];

fn set_msg(message: *mut &[u8], long: bool) {
    // UNSAFE: a test. SAFETY: message points to one view.
    unsafe { *message = if long { b"hello" } else { b"hi" }; }
}

fn main() {
    let mut m: &[u8] = b"";
    set_msg(&mut m as *mut &'static [u8], false);
    let a: [i64; 3] = [5i64, 6, 7];
    let p = a.as_ptr() as *mut i64;
    // UNSAFE: a test. SAFETY: p has 3 elements.
    let q = unsafe { (p.add(1)) as *mut u8 };
    // UNSAFE: a test. SAFETY: q is the second element's first byte.
    let b = unsafe { *q };
    // UNSAFE: a test. SAFETY: STRS is only compared.
    println("{} {} {}", m.len() + m[0] as usize, b, unsafe { get_strs() == 0 as *mut &'static [u8] });
}

// (0.28.0) STRS's accessors: every use of it is one of them.
fn get_strs() -> *mut &'static [u8] {
    unsafe { STRS }
}
// EDITION: rust
$ main.vl -o prog
ok: built prog
% ./prog
106 6 true
