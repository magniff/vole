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
- `*const T` and `*mut T`, quoted labels `'outer:`.

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

The edition is lenient where MVS's 0.19 meanings are: a `&T` of a plain
value (a number, a struct of numbers) is read where the value goes, and
a place is lent where `&T` goes. A program Rust accepts means the same;
some that Rust rejects compile.

## What comes later: edition.later

What the edition reads but 0.27.0 does not have is one soft error,
`edition.later`, naming the feature and its release; the rest of the
program is checked. `volec explain edition.later`.

| feature | release |
|---|---|
| `const_ptr_write` (a write through `*const T`), `deferred_init` (`let x;`) | 0.27.1 |
| `char`, `fn_once`, `impl_trait_return`, `where_bound`, `tuple_struct`, `supertrait`, `assoc_bounds`, `impl_for_ref`, `array_builtin` | 0.27.2 |

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
