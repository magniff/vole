## (0.28.0) A `static var` of the program is read and written through
## accessors at its file's end (tools/translate/statics.vl): `get_x()`,
## `set_x(v)`, a write into a part of it on a copy written back (`{ let
## mut names_copy = get_names(); names_copy.push(7); set_names(names_copy);
## }`), the imports of it the accessors the file uses, and the static
## private. An `atomic` row of statics.tsv (crate::places::BORROWCK_PARTIAL)
## makes it an Atomic<T> read and written Relaxed, its row's comment above
## the accessors; the others' `unsafe` blocks get no UNSAFE:/SAFETY: lines
## without a `justified` row.
$ main.vl -o mvs
ok: built mvs
% ./mvs
4 1 4 1 true
4
$ fix --edition rust main.vl
fixed, 1 receiver, 1 integer annotated, 6 static vars to 'static mut', 16 static uses through their accessors, 1 copy type derived Clone, Copy	3 files	+99 -21 lines
% cat main.vl
// The modules are named as compiler/src's (places, base) so that
// statics.tsv's rows name two of these statics: an `atomic` row's, a
// `justified` row's; the others have none.
mod base;
mod places;

use crate::base::{get_root_lex_abs, set_abs};
use crate::places::{get_count, set_count, get_names, set_names, get_totals, set_totals, bump, partial};

static mut STATE: i64 = 0;

fn main() {
    bump(3);
    set_count(get_count() + (1));
    { let mut names_copy = get_names(); names_copy.push(7); set_names(names_copy); }
    { let mut totals_copy = get_totals(); totals_copy[2] = get_count(); set_totals(totals_copy); }
    set_state(partial(true));
    let n = get_names().count;
    set_abs(true);
    println("{} {} {} {} {}", get_count(), n, get_totals()[2], get_state(), get_root_lex_abs());
    let count_now = get_count(); println("{count_now}");
}

// (0.28.0) STATE's accessors: every use of it is one of them.
fn get_state() -> i64 {
    unsafe { STATE }
}

fn set_state(v: i64) {
    unsafe {
        STATE = v;
    }
}
// EDITION: rust
% cat places/mod.vl
#[derive(Clone, Copy)] pub struct IntVec {
    pub count: i64, pub last: i64,
}

impl IntVec {
    pub fn push(&mut self, v: i64) {
        self.count += 1;
        self.last = v;
    }
}

// (statics.tsv: crate::places::BORROWCK_PARTIAL is `atomic`)
static BORROWCK_PARTIAL: Atomic<bool> = Atomic::new(false);

static mut COUNT: i64 = 0;
static mut NAMES: IntVec = IntVec { count: 0, last: 0 };
static mut TOTALS: [i64; 4] = [0i64; 4];

pub fn bump(by: i64) {
    set_count(get_count() + by);
}

pub fn partial(on: bool) -> i64 {
    set_borrowck_partial(on);
    if get_borrowck_partial() { 1 } else { 0 }
}

use std::sync::atomic::{Atomic, Ordering};

// (0.28.0) BORROWCK_PARTIAL's accessors: every use of it is one of them.
// Atomic, Relaxed: only the main thread reads and writes it (no function a
// worker or the assembler thread runs touches it), so Relaxed orders
// nothing else.
fn get_borrowck_partial() -> bool {
    BORROWCK_PARTIAL.load(Ordering::Relaxed)
}

fn set_borrowck_partial(v: bool) {
    BORROWCK_PARTIAL.store(v, Ordering::Relaxed);
}

// (0.28.0) COUNT's accessors: every use of it is one of them.
pub fn get_count() -> i64 {
    unsafe { COUNT }
}

pub fn set_count(v: i64) {
    unsafe {
        COUNT = v;
    }
}

// (0.28.0) NAMES's accessors: every use of it is one of them.
pub fn get_names() -> IntVec {
    unsafe { NAMES }
}

pub fn set_names(v: IntVec) {
    unsafe {
        NAMES = v;
    }
}

// (0.28.0) TOTALS's accessors: every use of it is one of them.
pub fn get_totals() -> [i64; 4] {
    unsafe { TOTALS }
}

pub fn set_totals(v: [i64; 4]) {
    unsafe {
        TOTALS = v;
    }
}
% cat base/mod.vl
// (statics.tsv: crate::base::ROOT_LEX_ABS is `justified`)
static mut ROOT_LEX_ABS: bool = false;

pub fn set_abs(on: bool) {
    set_root_lex_abs(on);
}

// (0.28.0) ROOT_LEX_ABS's accessors: every use of it is one of them.
pub fn get_root_lex_abs() -> bool {
    // UNSAFE: the lexical root flag of out_path, a process-wide static mut;
    // Rust has no safe access to a static mut
    // SAFETY: written and read only in out_path, reached on a task only via
    // dbg_loc under -g (serial compile); never used by two threads
    unsafe { ROOT_LEX_ABS }
}

pub fn set_root_lex_abs(v: bool) {
    // UNSAFE: the lexical root flag of out_path, a process-wide static mut;
    // Rust has no safe access to a static mut
    // SAFETY: written and read only in out_path, reached on a task only via
    // dbg_loc under -g (serial compile); never used by two threads
    unsafe {
        ROOT_LEX_ABS = v;
    }
}
$ check main.vl
main.vl:26:5: warning[unsafe.unjustified] 8 unsafe sites lack `// UNSAFE:` and `// SAFETY:` comments (the first here) | help: each unsafe site says right above it why it cannot be safe and why it is sound; the try: line lists them | try: volec query unsafe --no-std --unjustified --root main.vl
ok: 0 errors, 1 warning in main.vl
$ main.vl -o prog
ok: built prog
% ./prog
4 1 4 1 true
4
