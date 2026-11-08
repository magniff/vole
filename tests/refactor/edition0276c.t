## fix --edition rust (0.27.6): static_src, the structural `'static`
## result: every value `word` returns is a part of base::SRC or a text
## literal, and `first` returns a part of a `let` bound to a call of it,
## so both results are `&'static [u8]` and main may change `w` while it
## holds them (elision would tie them to `w`: a borrowck.conflict).
## Written, then built and run in the rust edition with the MVS
## program's output.
$ main.vl -o mvs
ok: built mvs
% ./mvs
5 1 1 1
$ fix --edition rust --list-left main.vl
fixed, 2 parameters to &T, 2 views to &[T], 2 borrows written '&x', 1 var to 'let mut', 2 '.len's to '.len()', 1 static var to 'static mut', 1 import, 3 text views to &str, 2 indexes cast to usize	2 files	+11 -10 lines
% cat main.vl
// fix --edition rust (0.27.6): a function whose every returned value is
// a part of base::SRC (or a text literal, or a call of such a function)
// has a `'static` result, base's region being never moved, unmapped or
// written again (docs/design/src-buffer.md): its caller may change what
// it read the view through while it holds the view.
mod base;

use std::alloc::Allocator;

use crate::base::SRC;

struct W<A: Allocator> {
    v: Vec<i64, A>,
    n: i64,
}

fn word(w: &W<Gpa>, a: i64, b: i64) -> &'static str {
    if a >= b || w.n < 0 {
        return "";
    }
    // UNSAFE: a static var's read.
    // SAFETY: one thread; SRC views static data.
    unsafe { &SRC[a as usize..b as usize] }
}

fn first(w: &W<Gpa>) -> &'static str {
    let s = word(w, 0, 5);
    &s[0..1]
}

fn main(gpa: Gpa) {
    base::set();
    let mut w: W<Gpa> = W { v: Vec::new_in(gpa), n: 0 };
    let s = word(&w, 6, 11);
    let f = first(&w);
    w.n += 1;
    w.v.push(w.n);
    println("{} {} {} {}", s.len(), f.len(), w.n, w.v.len());
}
// EDITION: rust
$ main.vl -o prog
ok: built prog
% ./prog
5 1 1 1
