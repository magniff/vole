# Rust and vole: where they differ

Vole's surface is Rust's: its syntax, ownership and moves, `&T` and
`&mut T` under a borrow checker (NLL, rustc's rules and codes:
`guide memory`), lifetimes, traits and generics, closures, patterns,
`?`, and std's names. A Rust program is not a vole program in the
places below, and only there; each is an error that names the fix, not
another meaning.

## Allocation is a capability

Nothing allocates without an allocator. It is a value passed to what
allocates, and a parameter of the type that owns memory; there is no
global allocator and no default `A`.

| Rust | vole |
|---|---|
| `fn main()` | `fn main(gpa: Gpa)`: the program's allocator, passed down (`fn main()` when nothing allocates) |
| `Vec<T>`, `String`, `HashMap<K, V>`, `Box<T>` | `Vec<T, Gpa>`, `String<Gpa>`, `HashMap<K, V, Gpa, FixedState>` (the hasher is written too, `hash.default`; `FixedState` is in the prelude), `Box<T, Gpa>`; generic code writes `A: Allocator` (`use std::alloc::Allocator`). `Vec<T>` is `alloc.default` |
| `Vec::new()`, `String::new()`, `Box::new(x)`, `Arc::new(x)` | `Vec::new_in(gpa)`, `String::new_in(gpa)`, `Box::new_in(x, gpa)`, `Arc::new_in(x, gpa)`: the allocator last. `Vec::new()` is `alloc.no_in` |
| `x.to_string()`, `format!("{a}-{b}")`, `iter.collect()` | `x.to_string_in(gpa)`, `format_in("{a}-{b}", gpa)`, `iter.collect_in(gpa)`: what returns owned memory ends in `_in` |

```vole
fn squares(n: i64, gpa: Gpa) -> Vec<i64, Gpa> {
    (1..=n).map(|i| i * i).collect_in(gpa)
}

fn main(gpa: Gpa) {
    let v = squares(4, gpa);
    let s = format_in("{v:?} sum {}", v.iter().sum::<i64>(), gpa);
    println("{s}");
}
```
```out
[1, 4, 9, 16] sum 30
```

Arenas and the other allocators: `guide allocators`.

## No macros

Rust's macros are functions of the prelude, called without `!`:
`print`, `println`, `eprintln`, `format_in`, `write`, `writeln`,
`panic`, `assert`, `assert_eq`, `unreachable`, `todo`. The format
string is a literal (`println(x)` is an error: `println("{}", x)`).
`vec![1, 2]` is an array or pushes; `matches!(x, P)` is `if let P = x`
or a `match`; there is no `macro_rules!`. Attributes and
`#[derive(Clone, Copy, PartialEq, Debug, ..)]` are Rust's.

## Effects and contracts

Vole adds two things to a signature, both checked.

- **Effects**: what a function may do, inferred for every function
  and checked where one is declared: `#[pure]`, `#[no_alloc]`,
  `#[no_io]`, `#[no_panic]`, `#[effects(io, static, panic)]`
  (all it may have: `println`'s three). The effects are `alloc(A)`,
  `io`, `static`, `panic`, `diverge` and `unsafe`; a panic is only
  `panic` (`diverge` is a loop or a recursion that may not end).
  `volec query effects NAME --why io` shows the chain (`guide
  effects`).
- **Contracts**: `requires COND else "code: message"` and `ensures
  COND` (with `result`) after the signature. A caller that breaks a
  `requires` stops at its own line with the message, exit 101 (`guide
  contracts`).

```vole
fn half(x: i64) -> i64
    requires x % 2 == 0 else "half.odd: {x} is odd"
    ensures result * 2 == x
{
    x / 2
}

#[pure]
fn square(x: i64) -> i64 {
    x * x
}

fn main() {
    println("{} {}", half(8), square(3));
    println("{}", half(7));
}
```
```out (exit 101)
4 9
main.vl:15:19: half.odd: 7 is odd
```

## Named arguments

An argument may be written with its parameter's name, after the
positional ones and in the parameters' order: `window(800, 600, title:
"demo")`. It is the same call; a wrong name or order is an error.
There are no default arguments: every argument is written.

```vole
fn scale(x: i64, by: i64, shift: i64) -> i64 {
    x * by + shift
}

fn main() {
    println("{}", scale(5, by: 3, shift: 1));
}
```
```out
16
```

## Numbers

- **Lossless integer widening is implicit**: an integer goes where a
  wider one of the same signedness is wanted, and an unsigned one
  where a wider signed one is (`u8` to `u16`, `i32` to `i64`, `u8` to
  `i64`, `u32` to `usize`). Everything else is written: `x as i32`
  narrows, `usize` to `i64` and `i32` to `u64` need `as`, and `f32` to
  `f64` does too. `i64::from(a)` is accepted as in Rust.
  An index is not widened to: it is a `usize`, as in Rust (`v[i as
  usize]` of an `i: u32`).
- **Overflow** panics at `-O0` (`attempt to add with overflow`) and
  wraps at `-O2`, as Rust's debug and release builds do; `wrapping_add`
  and its family always wrap.
- `~x` is an error (`syntax.tilde`): an integer's complement is `!x`;
  `volec fix --suggested` writes it.

```vole
fn main() {
    let small: u8 = 200;
    let wide: i64 = small; // widening: no `as`
    let v = [10, 20, 30];
    let i: i64 = 2;
    println("{} {} {}", wide + 1, v[i as usize], small.wrapping_add(100));
}
```
```out
201 30 44
```

## Pointers and slices

- `*const T` and `*mut T` are one type until 0.29: either goes where
  the other is wanted, with no cast (`let q: *mut i64 = p;` of a
  `*const i64`), and diagnostics print it `*T`. A write through a
  pointer declared `*const T` is still refused.
- A slice has the fields `ptr` and `len` beside Rust's `as_ptr()` and
  `len()` (until 0.29).
- Raw pointers are for `unsafe` code, as in Rust (`guide unsafe`).

## C

- A C header is imported, not bound by hand: `import "stdio.h" as c;`
  then `unsafe { c::puts(c"text"); }` (`c".."` is a NUL-terminated
  `*const u8`). `extern "C" { fn f(..); }` blocks and `#[link(name =
  "m")]`, `#[link(framework = "AppKit")]` are Rust's (`guide
  c-interop`).
- An `extern` function named `write` hides the prelude's `write`
  (the formatting function, Rust's `write!`): declare C's under another
  name, `#[link_name = "write"] fn c_write(fd: i32, buf: *const u8, n:
  usize) -> isize;`.

## std

std has Rust's modules, names and signatures with the allocator
written. Where it differs in shape:

- `std::path::Path<'a>` is a value that borrows its text, not an
  unsized type: `Path::new("a/b.txt")` is a `Path`, a function takes
  `p: Path<'a>`, and `p.file_name()` is an `Option<&str>` (there is no
  `OsStr`: paths and arguments are UTF-8 text).
- What owns memory takes the allocator there too: `Command::new_in(p,
  gpa)`, then Rust's chain, `.arg(a).output()`.

What Rust's std has and vole's does not yet: `std::rc` (`Rc`, `Weak`),
`VecDeque`, a slice's `join` and `concat`, `From<&str>` for a String
(`"x".into()` is `String::from_in("x", gpa)`), `Stdin::lock` (`guide
conversions#reading-input`),
`dyn`-based APIs (`Box<dyn Error>`, `Box<dyn Fn>`), `std::num::Wrapping`,
`u8::is_ascii_whitespace`, a precision taken from an argument (`{:.*}`,
`{:.p$}`), `Vec::try_push`, async and `std::future`. Vole's std adds
`std::gpu`, `std::window` and `std::objc` (`guide gpu`, `guide
window`), the arenas of `std::alloc`, and `embed wgsl` blocks with
`#[repr(wgsl)]` structs.

## Not in the language

| Rust | vole |
|---|---|
| `dyn Trait`, trait objects | none (`dyn` is reserved): generics, `impl Trait`, or an enum of the cases |
| `macro_rules!`, procedural macros | none |
| `async`, `await` | none: threads (`guide threads`) |
| const generics (`struct B<const N: usize>`) | none: the constant is an ordinary argument or field |
| `-> Option<impl Tr>`, a trait method's `-> impl Tr`, `let x: impl Tr` | 0.29 (`edition.later`); `-> impl Tr` at the top of a result works |
| `matches!(x, P)` | `match x { P => true, _ => false }` |
| `let mut v = Vec::new_in(gpa);` typed by a later `v.push(x)` | the type is written: `let mut v: Vec<T, Gpa> = Vec::new_in(gpa);` |
| a closure parameter `\|&&x\|`; `std::cmp::Reverse(k)` by its path | `\|x\| **x > 0`; `use std::cmp::Reverse;` then `Reverse(k)` |
| crates, `Cargo.toml` | a program is its root file and its `mod x;` files (`guide modules`); std is the only library |
