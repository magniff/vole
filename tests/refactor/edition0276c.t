## fix --edition rust (0.27.6): static_returns, the structural
## `'static` result: every value `word` returns is a part of base::SRC or
## a text literal, `first` returns a part of a `let` bound to a call of
## it, and `pick` a range of such a call or a `let` bound to one, so the
## three results are `&'static [u8]` and main may change `w` while it
## holds them (elision would tie them to `w`: a borrowck.conflict).
## Written, then built and run in the rust edition with the MVS
## program's output.
$ main.vl -o mvs
ok: built mvs
% ./mvs
5 1 2 1 1 1
$ fix --edition rust --list-left main.vl
fixed, 3 parameters to &T, 3 views to &[T], 4 borrows written '&x', 1 var to 'let mut', 4 '.len's to '.len()', 1 static var to 'static mut', 1 import, 4 text views to &str, 2 indexes cast to usize	2 files	+15 -14 lines
% cat main.vl
// fix --edition rust (0.27.6): a function whose every returned value is
// static (a part of base::SRC, a text literal, a call of such a function,
// a local bound to one, or a part of one) has a `'static` result, base's region being never moved, unmapped or
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

fn pick(w: &W<Gpa>, k: i64) -> &'static str {
    let t = first(w);
    if k > 0 {
        return &word(w, 0, 5)[1..3];
    }
    t
}

fn main(gpa: Gpa) {
    base::set();
    let mut w: W<Gpa> = W { v: Vec::new_in(gpa), n: 0 };
    let s = word(&w, 6, 11);
    let f = first(&w);
    let p = pick(&w, 1);
    let q = pick(&w, 0);
    w.n += 1;
    w.v.push(w.n);
    println("{} {} {} {} {} {}", s.len(), f.len(), p.len(), q.len(), w.n, w.v.len());
}
// EDITION: rust
$ main.vl -o prog
ok: built prog
% ./prog
5 1 2 1 1 1
