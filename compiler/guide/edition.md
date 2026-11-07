# The rust edition (0.27.0; its std, std2, since 0.27.2)

A file whose first line is `// EDITION: rust` (or a program compiled
with `--edition rust`) is read with Rust's meanings. It is the same
compiler; since 0.27.2 its std is the edition's own, std2
(compiler/std2): Rust's std, its names, modules and signatures, with
the allocator written (`Vec<T, A>`, `Vec::new_in(gpa)`, `String<A>`,
`HashMap<K, V, A>`). Its prelude is Rust's plus `Gpa`; `Allocator` is
`use std::alloc::Allocator`. The print functions are functions, not
macros: `println("{} {x}", a)`. MVS files, and MVS's std, are read
exactly as before; the edition is per program, from its root file.

## What 0.27.0 reads

- references: `&T` and `&mut T` as values, `&x`, `&mut x`, `*r`, a field
  or a method through a reference, reborrows (`f(r)` twice with `r: &mut T`);
- receivers `&self`, `&mut self`, `self`, `mut self`; `let mut`, `mut x: T`;
- lifetimes: `'a` in generics, types, bounds and `where`, `&'a T`,
  `impl<'a>`, elision (kept, not checked yet: 0.27.1 checks regions);
- `for` over `&v`, `&mut v`, a slice or `v.iter()` gives `&T` (`&mut T`),
  over a Vec or an array by value the values;
- patterns: match ergonomics through a reference, `ref x`, `ref mut x`,
  `&x`, `&(a, b)`, `&Some(k)`;
- std's `Deref`, `DerefMut`, `Index`, `IndexMut` on your types (`use
  std::ops::{Deref, Index}`): `*w`, `w.f`, `w.m()`, `g[i]`;
- `&impl Trait` and `impl Trait` arguments, `#[derive(Clone, Copy,
  PartialEq, ...)]` (Copy is what a plain type is already);
- `where Self: Sized` and `?Sized` (they say nothing); `*const T` and
  `*mut T`; quoted labels `'outer:`; a trait's defaulted parameter
  (`trait PartialEq<Rhs = Self>`, `impl PartialEq for P`); MVS's `var`,
  `inout`, `sink` and `defer` are names, and so is `union` but before a
  name;
- `&f(x)` of a value: a temporary of its statement, dropped at its end
  (of the block for `let r = &f(x);`).

```vole
// EDITION: rust
use std::ops::Index;

struct Grid {
    cells: [i64; 4],
}

impl Index<usize> for Grid {
    type Output = i64;
    fn index(&self, i: usize) -> &i64 {
        &self.cells[i]
    }
}

fn bump(v: &mut Vec<i64, Gpa>) {
    for x in v {
        *x += 1;
    }
}

fn main(gpa: Gpa) -> i32 {
    let mut v: Vec<i64, Gpa> = Vec::new_in(gpa);
    v.push(1);
    bump(&mut v);
    let g = Grid { cells: [5, 6, 7, 8] };
    let mut s = 0;
    for &x in &g.cells {
        s += x;
    }
    println("{} {} {}", v[0], g[2], s);
    0
}
```

```out
2 7 26
```

## Translating an MVS program: fix --edition rust (0.27.3)

`volec fix --edition rust FILE|DIR` rewrites an MVS program, in place,
into the rust edition (`--dry-run`: the diff only). It reads the program
as MVS checks it, so each rewrite follows the types:

- parameters: a let parameter MVS borrows is `&T` (a copy stays `T`),
  `inout T` is `&mut T`, `sink T` is `T`, a view `[T]` is `&[T]` (`[u8]`
  is `&str` when the program uses its bytes as text only); receivers
  `&self`, `&mut self`, `self`;
- calls: the inout marker `&x` is `&mut x`, a value a let parameter
  borrows is given as `&x`, a reference read as a copy or assigned is
  `*r`; std's calls by compiler/std2/rewrite.tsv's rows, chosen by type
  (`v.get(i)` is `v[i]` for a Copy element);
- locals: `var` is `let mut`, `inout r = &e` is `let r = &mut e`, an
  integer literal MVS types as i64 by default gets `: i64`;
- items: a copy type derives Clone and Copy, std's paths are std2's,
  `println(x)` is `println("{}", x)`.

No line moves (the `// EDITION: rust` line ends the root file), so a
position the program prints stays. What it cannot decide is left as
written and counted (`note fix.edition_left`; `--list-left` names each
place); the rust check's errors follow. The MVS program:

```vole
struct Point { x: i64, y: i64 }

fn total(v: Vec<i64, Gpa>) -> i64 {
    var t = 0;
    for i in 0..v.len() {
        t += v.get(i);
    }
    t
}

fn shift(p: inout Point, d: i64) {
    p.x += d;
    p.y += d;
}

fn keep(v: sink Vec<i64, Gpa>) -> usize { v.len() }

fn main(gpa: Gpa) {
    var v: Vec<i64, Gpa> = Vec::new_in(gpa);
    v.push(3);
    v.push(4);
    var p = Point { x: 1, y: 2 };
    shift(&p, 10);
    let q = p;
    println(total(v));
    println("{} {} {}", q.x, q.y, keep(v));
}
```

```out
7
11 12 2
```

and what `fix --edition rust` makes of it, which prints the same:

```vole
#[derive(Clone, Copy)] struct Point { x: i64, y: i64 }

fn total(v: &Vec<i64, Gpa>) -> i64 {
    let mut t: i64 = 0;
    for i in 0..v.len() {
        t += v[i];
    }
    t
}

fn shift(p: &mut Point, d: i64) {
    p.x += d;
    p.y += d;
}

fn keep(v: Vec<i64, Gpa>) -> usize { v.len() }

fn main(gpa: Gpa) {
    let mut v: Vec<i64, Gpa> = Vec::new_in(gpa);
    v.push(3);
    v.push(4);
    let mut p = Point { x: 1, y: 2 };
    shift(&mut p, 10);
    let q = p;
    println("{}", total(&v));
    println("{} {} {}", q.x, q.y, keep(v));
}
// EDITION: rust
```

```out
7
11 12 2
```

## The seams of 0.27.0 and 0.27.1 (MVS std), gone

Until 0.27.2 the edition ran on MVS's std, and two places differed from
Rust's std, each with its own code: `edition.std_copy` (`*x` of what a
std getter gave, `v.last()`, a copy where Rust's gives `&T`) and
`edition.std_by_value` (`&x` given to a std function taking the value,
`v.contains(&t)`). With std2 both are gone, and so is `edition.lenient`'s
std half: `*v.last().unwrap()` and `v.contains(&t)` are right, as in
Rust. `edition.lenient` stays for a rust-edition function's own
parameters and a `let`'s written type: a `&T` given where its value
goes, or a place where `&T` goes, is an error whose `try:` is Rust's
spelling (`*r`, `&x`).

## NLL, the regions solved (0.27.1)

Every rust-edition function's regions are solved on the places IR, as
rustc's NLL does (docs/design/borrowck.md is the rule book; each
message's code names its rule): a reference lives as long as its region
is used; a place is not written, moved, dropped or lent exclusively
while a loan of it is live, nor read while an exclusive loan is; a
receiver's `&mut` is two-phase (`v.push(v.len())` is fine); a
reference to a local does not leave its function; a signature's
lifetimes are what the body must respect (`'a: 'b`, elision as Rust's);
a moved value is not used again (a field moved, the whole is partly
moved; in a loop, "in a previous iteration"); a value cannot be moved
out of a reference, an index or a `static`; a value with `impl Drop`
keeps what it references alive until its drop, the std containers
(`Vec`, `String`, `HashMap`, ...) only their elements'. The seventeen
codes are `volec explain --list`'s `borrowck.*` entries (`mut_twice`,
`conflict`, `return_local`, `outlives`, `use_moved`, `move_out`, ...),
each with its rustc code; `volec check --emit-places=regions` prints
each body's liveness, constraints, region values and loans.

What is not checked (each a named divergence in the rule book): MVS
std's types holding hidden views (0.27.0 to 0.27.1: std2's types carry
their lifetimes, `Iter<'a, T>`); a `&raw` pointer's uses (unsafe's);
rvalue promotion (`&5` is a temporary, not `'static`). Since 0.27.2 a
closure body is checked like any other (its environment is `&Env`,
`&mut Env` or `Env` by its kind, and what it stores or returns from
its captures is checked where the closure is made), so 0.27.1's
`warning borrowck.unchecked` is gone.

## What comes later: edition.later

What the edition reads but does not have yet is one soft error,
`edition.later`, naming the feature and its release; the rest of the
program is checked, and an impl or a function the feature is in is left
out (`#[array_builtin(N)]`, a blanket impl, an impl on an instance).
`volec explain edition.later`. Deferred initialization, `let x: T;` and
`let x;` (typed by its first assignment), is the edition's from 0.27.1.

| feature | release |
|---|---|
| `const_ptr_write` (a write through `*const T`) | 0.27.1 |
| `where_bound` (a bound on a type that is not a parameter), `array_builtin`, `qualified_path` (a longer path than `<T as Tr>::X`), `auto_trait` (`Send`, `Sync`) | 0.27.2 |
| `impl_trait_return` (`-> impl Tr` at the top of a function's result) | 0.27.2.1 |
| `impl_trait_nested` (`-> Option<impl Tr>`, a trait method's `-> impl Tr`, `let x: impl Tr`) | 0.29 |

```vole
// EDITION: rust
fn adder(k: i64) -> Option<impl Fn(i64) -> i64> {
    None
}

fn main() -> i32 {
    0
}
```

```err
error[edition.later] 'impl Fn(i64) -> i64' (impl_trait_nested) comes with the rust edition in 0.29
```

## Options

- `--edition rust` (`--edition=rust`): the edition without the line.
- `--allow=CODE` (repeatable; a family: `--allow=borrowck`): a warning
  not reported, as rustc's `-A`.
- `--max-errors=N`: stop after N errors, not 50 (0: every error).
