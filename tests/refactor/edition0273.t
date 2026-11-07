## fix --edition rust (0.27.3, guide fix#edition): an MVS program
## translated into the rust edition, by types: parameters (`x: T` a copy,
## `&T` a borrow, `inout` `&mut`, a view `&[T]`), receivers, locals (`var`
## `let mut`, an inout local `&mut`), the borrows and accesses written
## (`&k` `&mut k`, `r` `*r`), `.len()`, prints given their format, a
## `static var` `static mut` and its uses in `unsafe { }`, a raw pointer
## `*mut T`, an i64 index `as usize`, a struct holding a view `Word<'a>`
## (used as `Word<'_>`), the derives Rust names, Display's
## `fmt` result, an operator's `Output`, std's paths; written, then built
## and run in the rust edition with the MVS program's output.
$ fix --edition rust --list-left main.vl
fixed, 1 parameter to &T, 2 parameters to &mut T, 3 receivers, 6 views to &[T], 2 '&x's to '&mut x', 2 borrows written '&x', 2 accesses written '*r', 5 vars to 'let mut', 1 inout local, 1 print given its format, 6 integers annotated, 1 static var to 'static mut', 2 imports, 5 types, 4 std calls by rewrite.tsv, 2 text views to &str, 4 static mut uses put in unsafe, 1 index cast to usize, 2 copy types derived Clone, Copy	main.vl	+34 -33 lines
% cat main.vl
// fix --edition rust (0.27.3): an MVS program of each rewrite kind.
use std::fmt::Debug; use std::ops::Add; use std::fmt::Display; use std::fmt::Formatter as Fmt; use std::alloc::Allocator; use std::collections::HashMap;

static mut CALLS: i64 = 0;

#[derive(PartialEq, Eq, Debug)]
struct Money { cents: i64 }

impl Add for Money { type Output = Money;
    fn add(self, o: Money) -> Money { Money { cents: self.cents + o.cents } }
}

impl Display for Money {
    fn fmt(&self, f: &mut Fmt) -> std::fmt::Result { write(f, "${}.{}", self.cents / 100, self.cents % 100)?;  Ok(()) }
}

struct Ledger<A: Allocator> { names: Vec<i64, A>, total: i64 }

impl Ledger<Gpa> {
    fn count(&self) -> usize { self.names.len() }
    fn add(&mut self, n: i64) { self.names.push(n); self.total += n; }
}

fn label(n: i64) -> &'static str { if n > 10 { "big" } else { "small" } }

fn sum(v: &[i64]) -> i64 {
    let mut t: i64 = 0;
    for &x in v {
        t += x;
    }
    t
}

fn bump(n: &mut i64) {
    *n += 1;
    unsafe { CALLS += 1; }
}

fn total(l: &Ledger<Gpa>) -> i64 { l.total }

fn none() -> *mut u8 { 0 as *mut u8 }

#[derive(Clone, Copy)] struct Word<'a> { text: &'a str, at: i64 }

fn first_word(s: &str) -> Word<'_> { Word { text: &s[0..2], at: 0 } }

fn main(gpa: Gpa) {
    let mut l = Ledger { names: Vec::new_in(gpa), total: 0 };
    l.add(5);
    l.add(20);
    let mut k: i64 = 1;
    bump(&mut k);
    let r = &mut k;
    *r += 10;
    let mut v: Vec<i64, Gpa> = Vec::new_in(gpa);
    for x in [4i64, 1, 3] {
        v.push(x);
    }
    v.sort_unstable();
    let mut seen: HashMap<i64, i64, Gpa> = HashMap::new_in(gpa);
    seen.insert(1, 2);
    let a = Money { cents: 150 };
    let b = Money { cents: 275 };
    println("{}", label(total(&l)));
    println("{} {} {} {}", l.count(), k, v[0usize], sum(&v[1..]));
    println("{} {} {}", a + b, seen.contains_key(&1), unsafe { CALLS });
    let arr = [7i64, 8, 9];
    let i: i64 = 1;
    let calls_now = unsafe { CALLS }; println("{} {calls_now} {}", arr[(i + 1) as usize], none() == 0 as *mut u8);
    let w = first_word("hello");
    println("{} {}", w.text, w.at);
}
// EDITION: rust
$ main.vl -o prog
ok: built prog
% ./prog
big
2 12 1 7
$4.25 true 1
9 1 true
he 0
