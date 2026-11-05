# The rust edition (0.27.0)

A file whose first line is `// EDITION: rust` (or a program compiled
with `--edition rust`) is read with Rust's meanings. It is the same
compiler and the same std: the MVS conventions (`let`, `inout`, `sink`)
are still what a std function's parameters are, and a rust-edition
program calls std as any program does. MVS files are read exactly as
before; the edition is per program, from its root file.

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

## The seams of 0.27.0 (MVS std)

0.27.0's edition runs on MVS's std. Two places differ from Rust's std,
each with its own code; 0.27.2's std removes both:

| code | where | fix |
|---|---|---|
| `edition.std_copy` | `*x` of what a std getter gives (`v.get(i)`, `v.last()`, a map's `get`): a copy, where Rust's give `&T` | the value as it is (`try:`) |
| `edition.std_by_value` | `&x` given to a std function that takes the value (`v.contains(&t)` of Strings, `m.insert(k, v)`) | `x.clone()`, `x`, or `*x` |

A generic `let` parameter of std's is `&T` or `T` per instance (a copy
for a plain T); a `&x` given to one is lent, as Rust's `v.contains(&3)`.

0.27.0 was lenient where MVS's 0.19 meanings are; 0.27.1 closes it
(`edition.lenient`): a `&T` given where its value goes, or a place where
`&T` goes, to a rust-edition function or a `let`'s written type, is an
error whose `try:` is Rust's spelling (`*r`, `&x`). MVS std's
parameters keep 0.19's meanings until 0.27.2's std.

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

What is not checked in 0.27.1 (each a named divergence in the rule
book): the inside of a closure body reaches its captures through a raw
environment (`warning borrowck.unchecked` names the closure;
`--allow=borrowck.unchecked` leaves it out); MVS std's types holding
hidden views; a `&raw` pointer's uses (unsafe's); rvalue promotion
(`&5` is a temporary, not `'static`).

## What comes later: edition.later

What the edition reads but 0.27.0 does not have is one soft error,
`edition.later`, naming the feature and its release; the rest of the
program is checked, and an impl or a function the feature is in is left
out (`#[array_builtin(N)]`, a blanket impl, an impl on an instance).
`volec explain edition.later`. Deferred initialization, `let x: T;` and
`let x;` (typed by its first assignment), is the edition's from 0.27.1.

| feature | release |
|---|---|
| `const_ptr_write` (a write through `*const T`) | 0.27.1 |
| `char`, `fn_once`, `impl_trait_return`, `where_bound`, `tuple_struct`, `supertrait`, `assoc_bounds`, `impl_for_ref`, `assoc_const`, `array_builtin`, `blanket_impl`, `impl_on_instance`, `return_inference`, `qualified_path` (`<T as Tr>::X`), `auto_trait` (`Send`, `Sync`), `primitive_builtin` (`#[builtin_impls(..)]`) | 0.27.2 |

```vole
// EDITION: rust
fn call<F: FnOnce() -> i64>(f: F) -> i64 {
    f()
}

fn main() -> i32 {
    0
}
```

```err
error[edition.later] 'FnOnce' (fn_once) comes with the rust edition in 0.27.2
```

## Options

- `--edition rust` (`--edition=rust`): the edition without the line.
- `--allow=CODE` (repeatable; a family: `--allow=borrowck`): a warning
  not reported, as rustc's `-A`.
- `--max-errors=N`: stop after N errors, not 50 (0: every error).
