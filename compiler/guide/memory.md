# Memory

Rust's ownership. Each value has one owner: `let w = v;`, an argument
passed by value and `return v` move it (a `Copy` value is copied), and
the owner drops it at the end of its scope. References borrow it: `&T`
shared, `&mut T` exclusive, checked by the borrow checker, with
lifetimes (`'a`) where a signature needs them. There is no garbage
collector and no reference counting; memory comes from an allocator,
written in the type (`Vec<i64, Gpa>`, `guide allocators`).

## Copy and move

- `Copy` types are copied bit for bit: integers, floats, `bool`,
  `char`, `&T`, raw pointers, `fn` pointers, tuples and arrays of `Copy`
  types, and a struct or enum that derives `Clone, Copy` (its fields all
  `Copy`). A struct without the derive moves, as in Rust.
- Everything else moves: `Vec`, `String`, `HashMap`, `Box`, a type with
  `Drop`, a struct holding one. A use after the move is
  `borrowck.use_moved` (rustc E0382), whose help says where it moved:
  use it before, pass a `.clone()`, or lend it (`&v`).

## Borrowing

A parameter's type says what the function does with the argument:

| written | the callee | the caller writes |
|---|---|---|
| `v: &Vec<i64, Gpa>` | reads it | `total(&v)` |
| `v: &mut Vec<i64, Gpa>` | may change it; the change reaches the caller | `fill(&mut v)` |
| `v: Vec<i64, Gpa>` | owns it (keeps it or drops it) | `keep(v)`: v moves |

```vole
fn total(v: &Vec<i64, Gpa>) -> i64 { // reads, no copy
    let mut s = 0;
    for x in v { s += *x; }
    s
}

fn fill(v: &mut Vec<i64, Gpa>, n: i64) { // changes the caller's Vec
    for i in 0..n { v.push(i * i); }
}

fn keep(all: &mut Vec<Vec<i64, Gpa>, Gpa>, v: Vec<i64, Gpa>) { // takes v
    all.push(v);
}

fn make(n: i64, gpa: Gpa) -> Vec<i64, Gpa> { // the caller owns the result
    let mut v: Vec<i64, Gpa> = Vec::new_in(gpa);
    fill(&mut v, n);
    v                                    // moved out: not dropped here
}

fn main(gpa: Gpa) {
    let v = make(4, gpa);
    let w = v.clone();                   // a copy; `let w = v;` moves v
    println("{} {} {}", total(&v), total(&w), w.len());
    let mut all: Vec<Vec<i64, Gpa>, Gpa> = Vec::new_in(gpa);
    keep(&mut all, w);                   // w is dead from here
    println("{}", all.len());
}                                        // all (and w in it), then v, dropped (freed)
```
```out
14 14 4
1
```

- At each point a place has any number of shared borrows or one
  mutable one, never both. A borrow lasts until its last use, not to
  the end of its block. `v.push(v.len())` is fine (the argument is read
  before the receiver's mutable borrow starts).
- The errors, with rustc's codes: `borrowck.conflict` (E0502),
  `borrowck.mut_twice` (E0499), `borrowck.assign_borrowed` (E0506),
  `borrowck.move_out` (E0507, E0508), `borrowck.dropped_borrowed`
  (E0597, E0716), `borrowck.borrow_immutable` (E0596),
  `borrowck.elision` (E0106), `borrowck.outlives` (a lifetime too
  short). Each one's help names the fix.
- A binding changes only if declared `let mut x`; `&mut x` or a `&mut
  self` method (`x.push(1)`) of a `let x` is an error (E0596).
- Receivers: `fn len(&self)`, `fn push(&mut self, x: T)`, `fn
  finish(self)`. A method call borrows its receiver itself: `v.push(1)`
  is `Vec::push(&mut v, 1)`.
- Lifetimes, Rust's: a result that borrows from the one reference
  parameter (or from `&self`) needs none written; otherwise name it,
  `fn longest<'a>(a: &'a str, b: &'a str) -> &'a str`
  (`borrowck.elision` says so). A struct that holds a reference takes
  one: `struct Parser<'a> { text: &'a str }`. A reference to a function's
  own local cannot leave it.

## Moves and drops

- At the end of a scope its owned locals are dropped, last declared
  first, on every exit (`return`, `break`, `?`), not on an `exit` or a
  panic. A moved value is not dropped where it was.
- A temporary (a call's result that is lent, read or matched and not
  bound: `total(&make())`, `make().len()`) is dropped at the end of its
  statement, the last made first; a block's tail expression's before
  the block's locals; `let r = &make();` keeps it to the end of the
  block. An `if let`'s scrutinee's are dropped before its `else` block
  runs, and at the end of the matching block (Rust 2024's rule): in
  `if let Some(n) = lock(c).peek() { .. } else { c.n += 1; }` the guard
  is gone in the else block. So are a `let .. else`'s before its else
  block, and a `while let`'s at each iteration's end. A `match` keeps
  its scrutinee's to the end of its statement.
- `impl Drop for T { fn drop(&mut self) { ... } }` runs code at the
  drop; a type without one drops its fields. `drop(x)` drops early,
  `std::mem::forget(x)` never (a leak, safe); calling `x.drop()` is an
  error (rustc E0040).
- A guard is a struct whose `Drop` releases what it holds (closes a
  descriptor, restores the terminal), made where the resource is taken:
  `let _closer = Closer { fd };` runs its drop on every exit of the
  scope, after the locals made later (`let _ = ..` drops at once).
- A `match`, `if let` or `let Two { a, .. } = t` by value moves only the
  parts it binds; the rest stays in `t` and is dropped with it.
  `v[i] = x` drops the element it replaces.
- `let x = v[i];` of an element that is not `Copy` would move it out of
  the Vec: `borrowck.move_out`. Borrow it (`&v[i]`), clone it, or take
  it with `std::mem::replace(&mut v[i], new)` or `Option::take`
  (`std::mem::take` for a type with `Default`).

## Slices

A slice `&[T]` borrows its owner's elements: `v.as_slice()`, `&v[a..b]`,
`s.as_bytes()`. While it is used, its owner does not grow, shrink or
drop (`borrowck.conflict`), so a slice never points at freed memory. Use
the slice before the change, then borrow again, or keep an index:

```vole
fn main(gpa: Gpa) {
    let mut v: Vec<i64, Gpa> = Vec::new_in(gpa);
    v.push(1);
    let s = v.as_slice();
    print("{} ", s[0]);                  // s's last use: before the pushes
    for i in 0..100 { v.push(i); }       // may move the elements
    let s2 = v.as_slice();               // a fresh borrow
    println("{}", s2.len());
}
```
```out
1 101
```

`volec --check-alloc` (0.16) also checks at run time: every Gpa block
on pages of its own, so a use after free (through `unsafe` code) faults
and is reported with where the block was allocated and freed; bad frees
and leaks are reported too.

## Cells

`std::cell::Cell<T>` is a value that changes through a shared
reference, Rust's Cell: `get` (a copy, `T: Copy`), `set`, `replace`,
`take`, `swap`, `update`.

```vole
use std::cell::Cell;

struct Counter { hits: Cell<i64> }

fn hit(c: &Counter) { c.hits.set(c.hits.get() + 1); }

fn main() {
    let c = Counter { hits: Cell::new(0) };
    hit(&c);
    hit(&c);
    let arr = [Cell::new(1i64), Cell::new(2)];
    for x in &arr { x.set(x.get() * 10); }
    println("{} {}", c.hits.get(), arr[1].get());
}
```
```out
2 20
```

- `UnsafeCell<T>` is the primitive under Cell, the atomics and Mutex:
  `get` gives a `*mut T` to write through in `unsafe`.

## Raw memory

`malloc` and `free` from C, raw `*const T` and `*mut T` pointers, in
`unsafe` (`volec guide unsafe`). `volec --check-unsafe -O1` checks heap
accesses through raw pointers at run time. Memory nobody wrote (from
`malloc`) has an unspecified value: write it before reading it.
