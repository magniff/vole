# Modules and imports

A file is a module. The files on the command line make the root module
(`crate`); `mod name;` in a module loads its child `name` from
`name.vl` or `name/mod.vl` next to it (from `a.vl`: `a/name.vl`).
`mod name { items }` declares one inline.

```text
main.vl            mod geometry;  use geometry::shapes::{Shape, area};
geometry.vl        pub mod shapes;  pub struct Rect { w: i64, h: i64 }
geometry/shapes.vl pub enum Shape { ... }  pub fn area(s: Shape) -> i64 { ... }
```

```sh
volec main.vl -o prog      # loads the modules main.vl names
```

## Visibility

Every item is private to its module and the modules inside it unless
`pub`. So is a struct's field (0.26, Rust's rule): outside, reading,
writing or borrowing a field not marked `pub` is `field.private`, and a
literal needs every field visible (`field.literal-private`; a struct
with a private field is made by its module's functions). On your own
field the help is its declaration with `pub`, which `volec fix --only
pub` writes. Methods are visible wherever their type is. A `pub mod` can
be reached from outside its parent. `pub use a::b;` re-exports `b`.
`pub(crate)` (0.26.2) is visible in the crate only, `pub(super)` in the
parent module (and inside it), `pub(in crate::a)` in module `a`, which
must be the item's own or one around it (`vis.path`); `pub(self)` is
private. They go on items, fields, `use` and `mod`. Used outside, the
error (`item.private`, `field.private`) says where it is visible, and
`fix --only pub` widens it to `pub(crate)`. Std's crate is std: a std
item marked `pub(crate)` is not a program's to use.

```vole
mod shop {
    pub mod till {
        pub(super) fn tax(n: i64) -> i64 { n / 10 }
        pub(crate) fn total(n: i64) -> i64 { n + tax(n) }
    }
    pub fn quote(n: i64) -> i64 { till::tax(n) }   // the parent sees it
}

fn main() -> i32 {
    println(shop::till::total(50) + shop::quote(50));   // not shop::till::tax
    0
}
```
```out
60
```

```vole
mod geo {
    pub struct Rect { pub w: i64, h: i64 }
    impl Rect {
        pub fn new(w: i64, h: i64) -> Rect { Rect { w: w, h: h } }
        pub fn area(self) -> i64 { self.w * self.h }
    }
}

fn main() -> i32 {
    let r = geo::Rect::new(3, 4);     // not `geo::Rect { w: 3, h: 4 }`: h is private
    std::print_int(r.w + r.area());   // r.w is pub; r.h would be field.private
    println("");
    0
}
```
```out
15
```

## Paths and use

A path starts with a name in scope, `crate`, `self`, `super` or `std`:
`geometry::area(s)`, `crate::util::Vec2 { x: 1, y: 2 }`,
`shapes::Shape::Rect(r)`, `util::Stack::<u8>::new()`.

A path may also start with a sibling module (0.17): in `parser.vl`,
where `main.vl` has `mod lexer; mod parser;`, `use lexer::{Tok, next};`
is `use crate::lexer::{Tok, next};`, and `lexer::next(..)` or `t:
lexer::Tok` in code is `crate::lexer::...` the same way. The first
segment, when the module has no name of its own for it, is a child of its
parent module, else of the root; when both exist and differ, the error's
`try:` lines are the two `crate::` paths.

```vole
mod util {
    pub fn double(x: i64) -> i64 { x * 2 }
    pub fn half(x: i64) -> i64 { x / 2 }
    pub enum Mode { Fast, Slow }
    pub mod inner {
        use super::double;               // the parent's item
        pub fn quad(x: i64) -> i64 { double(double(x)) }
    }
}

use util::{double, half as halve};       // by name, with `as` to rename
use util::inner::quad;
use util::Mode::{Fast, Slow};            // an enum's variants

fn speed(m: util::Mode) -> i64 {
    match m { Fast => 10, Slow => 1 }
}

fn main() -> i32 {
    std::print_int(double(3) + halve(8) + quad(1) + speed(Fast) + crate::util::double(1));
    println("");
    0
}
```
```out
26
```

- No wildcard imports (`use m::*;` is an error): every name a file uses
  is declared there, imported by name, or written as a path.
- The order of items and `use` lines does not matter.
- Name resolution: a local binding, then the module's own items, then
  its imports, then the prelude. A program's own `Vec` (or `trim`) hides
  the prelude's.
- The prelude, std's names used without a `use`: `Option Some None
  Result Ok Err Vec Buf HashMap print println eprint eprintln format
  format_in Gpa Allocator Arena ScopedArena arena_scope read_line
  read_stdin_in Scanner parse_int trim split_in split_whitespace_in sort
  sort_by cmp_of eq_of Fmt Display Debug Clone From Into Iterator Hash
  Eq Ord` and the operator traits, `panic(msg)` (prints `msg`, exits with
  101) and `unreachable()`. The rest of std is `use std::{...}` (or
  `std::name`); a program that names none of it is built without std.
- A C header: `import "stdio.h" as c;` then `c::printf`; in a pattern,
  import a C constant by name: `use c::EOF;`.

## Symbols

An item of module `a::b` has the symbol `a.b.name`; root items keep
their names, as do `extern "C"` items and `#[link_name]`s.

## Tools

- `volec fix --only imports` adds the `use` lines a program is
  missing (its own items', and std's outside the prelude),
  and `--only unused` removes unused ones. (0.25.2) `check` and a build
  warn about each, `use.unused` (an error with `--deny-warnings`): an
  import nothing in its file names; not a `pub use`.
- `volec query items` lists every module; `query items MODULE` its
  items with signatures.
- `volec refactor move a::f --to crate::b` moves items, fixing
  imports and `pub`; `refactor rename`, `refactor new-module`,
  `refactor split` (see `volec guide tools`).
