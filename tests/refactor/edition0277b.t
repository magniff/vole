## fix --edition rust (0.27.7): base's buf_done, a frozen buffer's
## slice, is a row of static_result's list (docs/design/src-buffer.md,
## "Views of other storage"): its body is a range of a static that is not
## SRC, which static_returns does not read as `'static`, and the row says
## it is. `signature` returns it, so its result is `&'static [u8]` by
## static_returns and main may change `w` while it holds it (elision
## would tie it to `w`: borrowck.assign_borrowed, borrowck.conflict).
## Written, then built and run in the rust edition with the MVS program's
## output.
$ main.vl -o mvs
ok: built mvs
% ./mvs
frozen 1 1
$ fix --edition rust --list-left main.vl
fixed, 1 parameter to &T, 1 view to &[T], 1 borrow written '&x', 1 var to 'let mut', 1 static var to 'static mut', 1 import, 3 text views to &str, 1 index cast to usize	2 files	+8 -7 lines
% cat main.vl
// fix --edition rust (0.27.7): base's buf_done is a row of
// static_result's list (a frozen buffer's slice), so a function that
// returns it, as lsp/complete's signature does, has a `'static` result
// too: its caller may change what it read the view through while it
// holds the view.
mod base;

use std::alloc::Allocator;

struct W<A: Allocator> {
    v: Vec<i64, A>,
    n: i64,
}

fn signature(w: &W<Gpa>, n: i64) -> &'static str {
    if w.n < 0 {
        return "";
    }
    let s = base::buf_done(n);
    s
}

fn main(gpa: Gpa) {
    base::fill();
    let mut w: W<Gpa> = W { v: Vec::new_in(gpa), n: 0 };
    let s = signature(&w, 6);
    w.n += 1;
    w.v.push(w.n);
    println("{} {} {}", s, w.n, w.v.len());
}
// EDITION: rust
$ main.vl -o prog
ok: built prog
% ./prog
frozen 1 1
