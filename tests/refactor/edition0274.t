## fix --edition rust (0.27.4, gate 3's first wall, the shapes that
## stopped compiler/src's translation at the parse and import stage): a
## static's `unsafe { }` first in a statement and an operand there is
## `(unsafe { .. })`; a method on a static wraps the call (through the
## receiver's borrow too); a raw-pointer receiver `self: *T` is `self: *mut
## T`, not `&self: ..`; `&c` of an inout parameter given to a `*T` is `c`
## (Rust coerces the `&mut`); a name a file's use binds (`Tok::{Hash}`)
## gets no std import beside it. Written, then built and run in the rust
## edition with the MVS program's output.
$ fix --edition rust --list-left main.vl
fixed, 1 parameter to &mut T, 1 receiver, 2 '&x's to '&mut x', 1 var to 'let mut', 2 static vars to 'static mut', 2 types, 4 static uses through their accessors, 2 indexes cast to usize, 2 copy types derived Clone, Copy	main.vl	+31 -14 lines
% cat main.vl
// fix --edition rust (0.27.4, gate 3's first wall): an `unsafe { }` put
// around a static's use first in a statement, written in parentheses; a
// method on a static, the call wrapped; a raw-pointer receiver, `self:
// *mut T`; an inout parameter's address given to a raw pointer, the
// reference itself; no std import beside a name a use binds (`Hash`).
use crate::Tok::{Hash, Shl};

#[derive(Clone, Copy, PartialEq, Eq)] enum Tok { Hash, Shl, Other }

fn tok_name(t: Tok) -> i64 {
    match t {
        Hash => 1,
        Shl => 2,
        _ => 3,
    }
}

#[derive(Clone, Copy)] struct Cells { n: i64 }

impl Cells {
    fn bump(&mut self) {
        self.n += 1;
    }

    fn read(self: *mut Cells) -> i64 {
        unsafe { self.n * 10 }
    }
}

fn peek(c: *mut Cells) -> i64 {
    unsafe { c.n }
}

fn via(c: &mut Cells) -> i64 {
    c.bump();
    peek(c) + c.read()
}

static mut SRC: [u8; 4] = [1, 2, 3, 4];
static mut N: i64 = 5;

fn twin(p: i64) -> bool {
    get_src()[p as usize] == 2 && get_src()[(p + 1) as usize] == 3
}

fn main() {
    set_n(get_n() + (1));
    let m = get_n().max(3);
    let mut c = Cells { n: 1 };
    println("{} {}", via(&mut c), c.read());
    println("{} {} {} {}", m, twin(1), twin(0), tok_name(Hash) + tok_name(Shl));
}

// (0.28.0) SRC's accessors: every use of it is one of them.
fn get_src() -> [u8; 4] {
    unsafe { SRC }
}

// (0.28.0) N's accessors: every use of it is one of them.
fn get_n() -> i64 {
    unsafe { N }
}

fn set_n(v: i64) {
    unsafe {
        N = v;
    }
}
// EDITION: rust
$ main.vl -o prog
ok: built prog
% ./prog
22 20
6 true false 3
