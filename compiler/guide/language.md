# The language, the long form (vole 0.28)

Vole is a compiled systems language with Rust's surface: structs, enums
with exhaustive `match`, traits and generics (monomorphized), closures,
iterators, modules, checked slices, `unsafe` raw pointers, exact C
interop. Ownership is Rust's: a value has one owner and is dropped at
the end of its scope; `&T` and `&mut T` borrow it, checked by the borrow
checker, with lifetimes where a signature needs them. It is not Rust in
a few places (the table below): there are no macros, and nothing
allocates without an allocator. Every function's effects are known.
Safe code has no undefined behaviour. This text matches this compiler;
`volec guide` is the short core of this text, `volec guide TOPIC` the
detail (topics at the end); `volec guide --full` prints this topic with
std's API in its place.

## Build and run

```sh
volec run [DIR] [-- ARGS]            # DIR/main.vl built (when changed), then run
volec hello.vl -o hello && ./hello   # executable (cc links it)
volec hello.vl -o hello.o            # object; `-o x.s`: assembly
volec check hello.vl                 # errors only, one per line
```

```vole
fn main() -> i32 {
    println("hello");
    0
}
```
```out
hello
```

`main` returns the exit status (`fn main()` with no result is 0).
`fn main(gpa: Gpa)` takes the program's allocator (below); the
arguments are `std::env::args()`. Several files on the command line
make one program; `mod name;` loads `name.vl`.

## Where it is not Rust

| Rust | vole |
|---|---|
| `println!("{}", x)`, `format!`, `vec!`, `assert!` | no macros: functions, `println("x = {x:>4} {:?}", v)`, `format_in("..", args, gpa)` (a `String`), `assert(c)`, `panic("..")` (`guide formatting`) |
| `Vec::new()`, a global allocator | `Vec::new_in(gpa)`: nothing allocates without an allocator; `gpa` comes from `fn main(gpa: Gpa)`, passed down as a parameter (`guide allocators`) |
| `Vec<T>`, `String`, `HashMap<K, V>`, `Box<T>` | the allocator is in the type: `Vec<T, Gpa>`, `String<Gpa>`, `HashMap<K, V, Gpa>`, `Box<T, Gpa>`; a struct that holds one is generic over it (`struct S<A: Allocator> { v: Vec<u8, A> }`) |
| `s.to_string()`, `it.collect()`, `s.to_uppercase()` | what allocates has the name with `_in` and takes the allocator last: `to_string_in(gpa)`, `collect_in(gpa)` (`alloc.no_in` names it; `volec fix --only alloc`) |
| `use m::*;` | not allowed: `use m::{a, b};`, or the path `m::a` |
| `a as i64` to widen | written or not: an `i32` goes where an `i64` does, losslessly; `a as i32` narrows (`guide conversions`) |
| `v[i as usize]` | an index may be any integer type |
| `dyn Trait`, `i128`, `async`, macros by example, a function inside a function, a string literal as a pattern | not there: dispatch is static (`impl Trait`, generics); `if s == "add"` |
| contracts, effects | `requires`/`ensures` clauses, `#[no_alloc]`, `volec query effects f` (`guide contracts`, `guide effects`) |

`volec guide rust` has every difference. The prelude, in every module
without `use`, is Rust's (`Option`, `Some`, `None`, `Result`, `Ok`,
`Err`, `Vec`, `String`, `Box`, `Clone`, `Copy`, `Default`, `Drop`,
`PartialEq`, `Eq`, `PartialOrd`, `Ord`, `From`, `Into`, `Iterator`...)
plus `Gpa` and, as functions, Rust's macros: `print`, `println`,
`eprint`, `eprintln`, `format_in`, `write`, `writeln`, `panic`,
`assert`, `assert_eq`, `assert_ne`, `debug_assert`, `todo`,
`unimplemented`, `unreachable`. The rest of std is used by path
(`std::mem::swap(&mut a, &mut b)`) or imported (`use
std::collections::HashMap;`). Calling C or an `unsafe fn`,
dereferencing a raw pointer and using a `static mut` are allowed only
in `unsafe { }` (`volec guide unsafe`: the full list).

## Values and types

```vole
let a = 42;               // i32: an integer literal is i32 unless the context says
let b: u8 = 255;          // i8 i16 i32 i64 u8 u16 u32 u64 isize usize
let c = 3u32;             // suffixes; 1_000, 0xff, 0b1010
let d = 2.5;              // f64; 2.5f32 is f32
let e = 'A';              // char: a Unicode scalar value; b'A' is a u8
let f = true;             // bool
let s = "text";           // &str: s.len() (bytes), &s[1..3], s.chars()
let bs = b"bytes";        // &[u8; 5]: bs[0]
let p = c"for C";         // *const u8, NUL-terminated
let t = (1, "two");       // a tuple: t.0, t.1
let arr = [0; 8];         // [i32; 8]; also [1, 2, 3]; arr[i] is checked
let mut n = a as u8;      // `as` converts numbers; only widening is implicit
n += c as u8 + b / 5 + e as u8;
```

`let` bindings are immutable, `let mut` ones mutable. Shadowing (`let x
= x + 1;`) is allowed. `const N: i64 = 10;` and `static LIMIT: i64 = 3;`
are items; a `static mut` is read and written in `unsafe` (`guide
threads`). Overflow panics at -O0 and wraps at -O1 and above, `x / 0`
panics; indexing, slicing, `unwrap` and casts to enums are checked (a
message, exit 101): `guide types`.

## Functions and control flow

```vole
fn classify(n: i64) -> &'static str {
    if n < 0 { "negative" } else if n == 0 { "zero" } else { "positive" }
}

fn greet(name: &str, times: i64, sep: &str) {
    for _ in 0..times { print("hi {name}{sep}"); }
}

fn main() -> i32 {
    let mut total = 0;
    for i in 0..10 {              // 0..10 and 0..=9; (0..10).rev(), .step_by(2)
        if i % 2 == 0 { continue; }
        total += i;
    }
    let mut k = 0;
    while k < 3 { k += 1; }
    let found = loop {            // loop's value comes from `break value`
        k += 1;
        if k * k > 50 { break k; }
    };
    'outer: for i in 0..5 {       // a label: `'name:`, then `break 'name`
        for j in 0..5 {
            if i * j == 6 { break 'outer; }
        }
    }
    greet("ann", 1, " ");
    greet("bob", 2, "! ");
    println("{}", classify(total - found));
    0
}
```
```out
hi ann hi bob! hi bob! positive
```

The last expression of a block, without `;`, is its value; `if`, `match`,
`loop` and blocks are expressions. A range is a value (`let r = 0..3;`,
`(0..10).rev()`, `.step_by(2)`). There are no nested functions.

## References: &T, &mut T, by value

```vole
use std::alloc::Allocator;

struct Account<A: Allocator> { balance: i64, log: Vec<i64, A> } // the allocator: a parameter

fn transfer(from: &mut Account<Gpa>, to: &mut Account<Gpa>, amount: i64) -> bool {
    if from.balance < amount { return false; }
    from.balance -= amount;
    to.balance += amount;
    from.log.push(-amount);
    to.log.push(amount);
    true
}

fn report(a: &Account<Gpa>, out: &mut i64) { *out += a.balance; } // *out: the caller's i64

fn keep(all: &mut Vec<Account<Gpa>, Gpa>, a: Account<Gpa>) { all.push(a); }

fn main(gpa: Gpa) {
    let mut a = Account { balance: 100, log: Vec::new_in(gpa) };
    let mut b = Account { balance: 5, log: Vec::new_in(gpa) };
    transfer(&mut a, &mut b, 30);         // the call shows what changes
    let mut sum = 0;
    report(&a, &mut sum);
    report(&b, &mut sum);
    let mut all: Vec<Account<Gpa>, Gpa> = Vec::new_in(gpa);
    keep(&mut all, a);                    // a moves: dead from here
    println("{sum} {} {}", all[0].log.len(), b.balance);
}
```
```out
105 1 35
```

- `&T` reads: any number of them at once. `&mut T` changes the caller's
  place, exclusively: `transfer(&mut a, &mut a, 1)` is
  `borrowck.mut_twice`. A parameter by value takes the argument: a
  `Copy` value (`i64`, a struct deriving `Clone, Copy`) is copied, any
  other moves, and the callee owns it and drops it.
- Through a reference, a field or a method needs no `*`
  (`from.balance`, `from.log.push(x)`); the value itself does (`*out +=
  1`).
- `let r = &mut a;` keeps a borrow, passed on as `f(r)`; it ends at its
  last use (`guide memory`).

## Structs, enums, match, methods

```vole
#[derive(Clone, Copy, PartialEq, Debug)]
struct Point { x: i64, y: i64 }

enum Shape { Circle(Point, i64), Rect { min: Point, max: Point }, Empty }

impl Point {
    fn new(x: i64, y: i64) -> Point { Point { x, y } }          // Point::new(1, 2)
    fn shift(&mut self, dx: i64) { self.x += dx; }              // writes through self
    fn sum(&self) -> i64 { self.x + self.y }
}

fn area(s: &Shape) -> i64 {
    match s {
        Shape::Circle(_, r) => 3 * r * r,
        Shape::Rect { min, max } => (max.x - min.x) * (max.y - min.y),
        Shape::Empty => 0,
    }
}

fn main() -> i32 {
    let mut p = Point::new(1, 2);
    p.shift(10);                          // borrows p mutably: p is a let mut
    let shapes = [Shape::Rect { min: Point::new(0, 0), max: p }, Shape::Circle(p, 2),
        Shape::Empty];                    // p is Copy: used twice
    for s in &shapes {
        print("{} ", area(s));
    }
    println("{} {:?}", p.sum(), p);
    let o: Option<i64> = Some(7);
    if let Some(v) = o { print("{v}"); }
    match 15 {
        0 => println(" zero"),
        1..=9 => println(" digit"),
        n if n % 5 == 0 => println(" fives"),
        _ => println(" other"),
    }
    0
}
```
```out
22 12 0 13 Point { x: 11, y: 2 }
7 fives
```

A variant's fields are by position (`Circle(Point, i64)`) or by name
(`Rect { min: Point, max: Point }`: made as `Shape::Rect { min: a, max
}` in any order, matched as `Shape::Rect { min, .. }`; a variant's
fields are read only through patterns). A match must cover every value;
arms can have `|`, ranges `a..=b` and guards `if`. Matching a `&Shape`
binds references (`r` above is a `&i64`). `use Shape::{Circle, Empty};`
lets variants be written without `Shape::`. `==` is `PartialEq`:
`#[derive(PartialEq)]` compares a struct or enum field by field; `&str`
compares by bytes, a `Vec` or `HashMap` by contents.

## Generics and traits

```vole
trait Area {
    fn area(&self) -> i64;
    fn twice(&self) -> i64 { 2 * self.area() }         // a default method
}

struct Square { side: i64 }

impl Area for Square {
    fn area(&self) -> i64 { self.side * self.side }
}

fn total<T: Area>(items: &[T]) -> i64 {   // bounds: T: A + B
    items.iter().map(|it| it.area()).sum()
}

struct Pair<T> { a: T, b: T }

impl<T: PartialOrd> Pair<T> {
    fn max(self) -> T { if self.a > self.b { self.a } else { self.b } }
}

fn main() -> i32 {
    let squares = [Square { side: 2 }, Square { side: 3 }];
    let p = Pair::<i64> { a: 3, b: 9 };   // the turbofish: Pair::<i64>
    println("{} {} {}", total(&squares), squares[0].twice(), p.max()); // &array: a slice
    0
}
```
```out
13 8 9
```

Generics are templates, checked per instantiation (`max::<i64>(a, b)`
is the turbofish). Operators go through std's traits: `impl
std::ops::Add for V` makes `a + b` work; `PartialOrd` gives `<`. There
are no trait objects: dispatch is static (`guide traits`, `guide
generics`).

## Modules and imports

`mod geometry;` loads geometry.vl (or `mod geometry { ... }` inline);
`use geometry::{Rect, area};` imports by name, never `*`. Paths start
with a name in scope, `crate`, `self`, `super` or `std`. Items are
private (to their module and its children) unless `pub`, and so are a
struct's fields (`pub w: i64` to show one); `pub use` re-exports. A
missing import's error says which `use` line to add, and `volec fix`
adds it.

## Slices, arrays, text

```vole
fn sum(xs: &[i64]) -> i64 {
    let mut t = 0;
    for i in 0..xs.len() { t += xs[i]; }    // indices are usize; checked
    t
}

fn main() -> i32 {
    let mut a = [5i64, 1, 4];
    a[1] = 2;
    println("{}", sum(&a) + sum(&a[1..]));  // &a[lo..hi], &a[..hi], &a[lo..]
    let s = "hello world";
    println("{}", &s[6..]);
    if s.starts_with("hello") { println("starts with hello"); }
    let words = [0; 4];
    let i = s.len() - 7;
    println("{}", words[i]);              // out of bounds: a message, exit 101
    0
}
```
```out (exit 101)
17
world
starts with hello
main.vl:16:19: index out of bounds: index 4, length 4
```

An array `[T; N]` is a value (`a.len()` is N); a slice `&[T]` is a
pointer and a length (`.len()`; `.as_ptr()` for C) borrowing an array, a
`Vec` or memory. A `&[T]` is read-only; `&mut [T]` (`&mut a[..]`,
`v.as_mut_slice()`) writes its elements. Text is `&str`, UTF-8: `&s[a..b]`
slices by bytes, `s.chars()` gives its `char`s, `s.as_bytes()` its
`&[u8]` (`guide text`).

## std: Vec, HashMap, String; allocation

```vole
use std::collections::HashMap;
use std::fmt::Write;

fn evens(n: i64, gpa: Gpa) -> Vec<i64, Gpa> { // it allocates: it takes an allocator
    (0..n).map(|i| i * 2).collect_in(gpa)
}

fn main(gpa: Gpa) -> i32 {                 // the program's allocator
    let mut v: Vec<i64, Gpa> = Vec::new_in(gpa); // dropped (freed) when main returns
    v.push(30);
    v.push(10);
    v.push(20);
    v.sort();                              // in place
    v[0] += 1;                             // checked; v.get(0) is an Option<&i64>
    for x in &v { print("{x} "); }         // also v.iter(); `for x in v` moves v
    println("");
    let last = v.pop();                    // Option<i64>
    println("{}", last.unwrap_or(-1));

    let mut m: HashMap<&str, i64, Gpa> = HashMap::new_in(gpa);
    m.insert("a", 1);
    m.insert("b", 2);
    match m.get("a") { Some(x) => println("{x}"), None => println("none") }
    for (k, _) in &m { print("{k}"); }     // (&K, &V) pairs, in slot order
    println("");

    let mut b = String::new_in(gpa);       // text builder
    let e = evens(4, gpa);
    b.push_str("n=");
    write(&mut b, "{}", m.len() + e.len()).unwrap();
    b.push('!');
    println("{b}");
    0
}
```
```out
11 20 30
30
1
ba
n=6!
```

Allocation is explicit: nothing allocates without an allocator. A
function that allocates takes one, `gpa: Gpa` or `a: A` with `A:
Allocator`, or a container it was given (`push` uses the Vec's own);
main's `gpa` is where they come from. `std::alloc::arena_scope(&gpa, |a|
...)` hands out an arena whose memory is all freed when the closure
returns. `--check-alloc` builds the program with a checking allocator: a
use after free, a double free, a leak are reported where they happen.
Every function's effects are inferred (`alloc(Gpa) io panic diverge
unsafe`): `volec query effects f --why io` shows where; `#[no_alloc]` on
a function is checked (`guide effects`, `guide allocators`).

`Vec`, `String` and `HashMap` own their contents: `let w = v;` or
passing one by value moves it (`.clone()` copies). Pass `&v` to a `v:
&Vec<T, A>` (or `&[T]`) parameter to read it, `&mut v` to a `v: &mut
Vec<T, A>` one to let a function push. A slice from `as_slice` borrows
the vector: the vector does not grow or drop while the slice is used
(`guide memory#slices`). std's API, made from its source in this
compiler, a line per item: `volec guide std#the-api`; each item with its
comment: `volec guide std#every-item`; one name: `volec guide --find
NAME`.
@STD-API-FULL@

## Input, output, arguments

std prints and reads stdin, Rust's way: `io::read_to_string_in(
io::stdin(), gpa)` (all of it, an `io::Result<String<Gpa>>`),
`io::stdin().read_line(&mut s)` (appends the next line with its
`'\n'`; `Ok(0)` at the end), then `str`'s methods (`lines`,
`split_whitespace`, `split`, `trim`, `parse::<i64>()`, a `Result`:
`guide conversions`, where Option means absent and Result failed).
Files, the environment and processes are `std::fs`, `std::env` and
`std::process` (`guide io`):

```vole
use std::{env, io};

fn main(gpa: Gpa) -> i32 {
    let input = io::read_to_string_in(io::stdin(), gpa).unwrap(); // all of stdin, a String<Gpa>
    let mut total = 0i64;
    for tok in input.split_whitespace() {
        match tok.parse::<i64>() {        // a Result<i64, ParseIntError>
            Ok(n) => total += n,
            Err(_) => eprintln("not a number: {tok}"),
        }
    }
    println("{total}");
    for a in env::args().skip(1) {        // the first is the program
        println("{a}");
    }
    0
}
```
```in
12
30
```
```out
42
```

## unsafe and C

```vole
import "stdio.h" as c;                   // a C header, its names under c::

extern "C" {                              // or declare C functions yourself
    fn abs(x: i32) -> i32;
}

fn main() -> i32 {
    unsafe { c::printf(c"%.1f %d\n", 2.5 * 2.0, abs(-3)); }
    0
}
```
```out
5.0 3
```

Unsafe operations: calling C or an `unsafe fn`, dereferencing a raw
pointer (`*p`, `(*p).f`), using a `static mut`, reading a union field. A
reference (`&T`, `&mut T`) is safe to read and write through wherever it
is kept; `*const T` and `*mut T` are raw. `volec fix --only unsafe`
wraps what needs it; `#[repr(C)]`, callbacks and linking: `guide
c-interop`.

## Errors you will meet first

| error (short form) | fix |
|---|---|
| `'println!' is a macro call: vole has no macros` | `println("{}", x)`, the help's form |
| `'Vec::new' allocates from nothing` (`alloc.no_in`; `to_string`, `collect`) | `Vec::new_in(gpa)`, `to_string_in(gpa)`: `fn main(gpa: Gpa)`, `gpa` passed down; `volec fix --only alloc` |
| `'Vec' names no allocator` (`alloc.default`) | `Vec<i64, Gpa>` |
| `alloc.field: the struct 'S' holds an allocator its parameters do not name` | `struct S<A: Allocator> { v: Vec<u8, A> }`, used as `S<Gpa>` |
| `expected 'String<Gpa>', got '&str'` | `String::from_in("..", gpa)`; a parameter `s: &str` takes both |
| `wildcard imports are not allowed` | `use m::{a, b};` |
| `borrowck.use_moved: 'v' is used here after it moved` | lend it (`&v`), or pass `v.clone()` |
| `borrowck.conflict: cannot borrow 'u' as mutable because it is also borrowed as immutable` | use the shared borrow before the change, or take it again after |
| `edition.lenient: 'n' is a value where a reference goes` | `f(&n)` |
| `expected '&mut Vec<i64, Gpa>', got 'Vec<i64, Gpa>'` | `f(&mut v)` |
| `cannot assign to immutable variable 'x'` | `let mut x` |
| `cannot infer the type of closure parameter 'x'` | `\|x: i64\| ...`, or pass it where an `Fn` bound or `fn` type gives it |
| `'?' needs 'f' to return Option or Result` | `fn f(..) -> Option<T>` or `-> Result<T, E>` |
| `expected '&[i64]', got '&[i32; 3]'` | `[5i64, 1, 4]`: an unsuffixed literal is an `i32` unless the context says at once |
| `expected 'i32', got 'i64'` | `x as i32`: only widening is implicit |
| `distinct.mix: '5u8' is 'u8' where 'char' goes` | `5u8 as char` |
| `non-exhaustive match: 'E::C' is not covered` | an arm, or `_ =>` |
| `error[unsafe] calling a C function is unsafe` | `unsafe { ... }` |
| `unknown type 'HashMap' \| help: add 'use ...'` | add the `use` line the help names (`volec fix`) |

`volec guide errors` has more, each with its fix.

## Tools: read and change code through the compiler

```sh
volec check [ROOT]                   # all errors, one line each: FILE:L:C: error[KIND] MSG | help: ...
volec f.vl -o f                    # the same lines when compiling, off a terminal
volec query show NAME                # an item's source: fn, Type::method, Enum::Variant, FILE:LINE
volec query def NAME                 # where it is defined, its signature
volec query refs NAME                # every resolved use (--count, --in FILE)
volec query items [MODULE]           # a module's items with signatures (std: its API)
volec query context NAME             # source, what it calls, its types and callers, at once
volec query effects NAME             # what it may do: alloc(Gpa) io panic diverge unsafe
volec try '7 / 2'                    # run a snippet with std: its output, TYPE = VALUE
volec edit patch NAME --old 'a < b' --new 'a <= b'   # change text inside one item
volec edit replace NAME < new.vl   # replace an item; edit insert --after NAME; edit delete NAME
volec fix                            # missing imports, unused, pub, unsafe blocks
volec undo                           # take the last edit back
volec refactor rename main::x total  # a local (or FILE:LINE:COL), an item, a field, with every use
```

They pay off on renames, moves, signature changes, errors across files
and large code; a small file is cheaper read whole (`query show
FILE.vl`). ROOT is `--root FILE`, a last argument ending in `.vl`,
or `./main.vl`. Every edit is checked first: one that adds an error
writes nothing. A problem is one line, `error CODE: message`, then
`try:` lines to run as they are (`guide tools`).

## Topics

`volec guide TOPIC` prints one; `volec guide --list` gives their
sizes; `volec guide --all` prints everything.

@TOPICS@
