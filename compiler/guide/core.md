# vole, the core (vole 0.28)

Vole is a compiled systems language with Rust's surface: its syntax,
ownership (a value has one owner, moves or is copied, and is dropped at
the end of its scope), references (`&T`, `&mut T`) checked by a borrow
checker, traits, generics and std's names. It differs in a few places:
no macros (`println("{x}")` is a function), and nothing allocates
without an allocator, which is written in the type (`Vec<i64, Gpa>`) and
passed to what allocates (`Vec::new_in(gpa)`). Indexing is checked, and
safe code has no undefined behaviour. This page is the core; the rest is
on demand (the end). Every difference from Rust: `volec guide rust`.

## Build and run

```sh
volec run < in.txt                         # ./main.vl built (when changed), run
volec main.vl -o prog                      # the executable; `mod x;` loads x.vl
volec check main.vl                        # every error, one line each
volec try '"42".parse::<i64>()'            # a snippet: its TYPE = VALUE
```

## The language in one program

```vole
import "stdio.h" as c;                 // a C header; its names under c::
use std::fmt::Write;
use std::collections::HashMap;         // std items by name (never *)
use std::hash::FixedState;

struct P { x: i64 }

impl P {
    fn bump(&mut self) { self.x += 1; }    // &mut self: changes the caller's P
    fn get(&self) -> i64 { self.x }        // &self: reads it
}

fn total(v: &Vec<i64, Gpa>) -> i64 { // &: reads, no copy
    v.iter().sum()
}

fn grow(v: &mut Vec<i64, Gpa>, x: i64) { // &mut: the caller writes grow(&mut v, x)
    v.push(x);
}

fn keep(all: &mut Vec<Vec<i64, Gpa>, Gpa>, v: Vec<i64, Gpa>) { // by value: keep takes v
    all.push(v);
}

fn first(s: &str) -> char { s.chars().next().unwrap() } // text is &str, UTF-8; 'a' is a char, b'a' a u8

fn odds(n: i64, gpa: Gpa) -> Vec<i64, Gpa> { // allocating takes an allocator
    (0..n).filter(|i| i % 2 == 1).collect_in(gpa)
}

fn main(gpa: Gpa) -> i32 { // gpa: the program's allocator; 0 = exit status
    let mut v: Vec<i64, Gpa> = Vec::new_in(gpa); // let mut: mutable; let: not
    v.push(5);
    grow(&mut v, 2);
    v[0] += 10;                        // checked (&v[1..2] a slice)
    v.sort();
    let mut p = P { x: 1 };
    p.bump();                          // a receiver needs no &mut; p must be let mut
    println("{} {v:?} {}", p.get(), total(&v)); // formatted; total(&v) only reads
    let mut all: Vec<Vec<i64, Gpa>, Gpa> = Vec::new_in(gpa);
    keep(&mut all, v);                 // v moved into keep: dead from here
    let s = "hi";
    println("{}", s.len());            // a usize (slices, Vec, String, HashMap)
    let mut b = String::new_in(gpa);   // a text builder
    let o = odds(7, gpa);
    b.push_str("n=");
    write(&mut b, "{}", o.len()).unwrap();
    println("{b}");
    if s == "hi" && !first(s).is_ascii_digit() { println("{}", first(s)); }
    let mut m: HashMap<&str, i64, Gpa, FixedState> = HashMap::new_in(gpa);
    *m.entry("k").or_insert(0) += 1;
    let z = 0;
    println("{} {} {}", !0u8, 250u8.wrapping_add(7), m["k"]); // x / 0 panics
    unsafe { c::puts(c"from C"); }     // C calls need unsafe; c"..": a NUL-terminated *const u8
    if z != 0 { panic("z"); }          // exit 101; unreachable()
    0
}                                      // all, o, b, m: dropped (freed) here
```
```out
2 [2, 15] 17
2
n=3
h
255 1 1
from C
```

Also: lengths and indices are `usize` (`v[i as usize]` of an `i64`);
overflow panics at -O0, wraps at -O2 (`wrapping_add`: always);
`a as i32` narrows, widening is implicit (`i64::from(a)` is Rust's
form); `x?`, closures (`|x| x + k`, `move ||` to take what it captures),
`impl Trait for T`, `T: Trait`, `#[derive(Clone, PartialEq, Debug)]`,
`where T: Ord`, `x: impl Display`, lifetimes (`'a`) where a signature
needs them, `Box<T, A>`; no `dyn`. A struct is moved unless it derives
`Clone, Copy`. A reference is used as in Rust: `*x` reads or writes
through it, a field or method needs no `*` (`p.x`, `v.len()`), and
`match e` on an `e: &E` binds references (`E::A(n) => *n + 1`). The
prelude (no `use`) is Rust's plus `Gpa`: `Option`, `Result`, `Vec`,
`String`, `Box`, the common traits, and as functions Rust's macros:
`print`, `println`, `eprintln`, `format_in`, `write`, `writeln`,
`panic`, `assert`, `assert_eq`, `unreachable`, `todo`. The rest of std
is `use std::...` (`std::collections::HashMap`); `use crate::lexer::Tok;`
reaches the program's module `lexer`.

## std: what programs use most

```vole
use std::collections::HashMap;
use std::hash::FixedState;
use std::io;

struct Item<'a> { name: &'a str, qty: i64 }    // 'a: the name borrows the input

fn main(gpa: Gpa) -> i32 {
    let input = io::read_to_string_in(io::stdin(), gpa).unwrap(); // all of stdin, a String<Gpa>
    let mut lines = input.lines();
    let mut toks = lines.next().unwrap().split_whitespace();
    let n: i64 = toks.next().unwrap().parse().unwrap(); // parse: a Result<i64, ParseIntError>
    let mut items: Vec<Item, Gpa> = Vec::new_in(gpa);
    let mut seen: HashMap<&str, i64, Gpa, FixedState> = HashMap::new_in(gpa);
    for _ in 0..n {
        let name = toks.next().unwrap();       // Option<&str>: a slice of input
        let qty = toks.next().unwrap_or("").parse().unwrap_or(0);
        items.push(Item { name, qty });
        seen.insert(name, qty);                // also contains_key(k), remove(k)
    }
    items.sort_by(|a, b| b.qty.cmp(&a.qty));   // a, b: &Item; an Ordering
    for (i, it) in items.iter().enumerate() { print("{i}:{} ", it.name); }
    let line = lines.next().unwrap_or("").trim();
    let total: i64 = line.split(',').map(|w| w.trim().parse::<i64>().unwrap_or(0)).sum();
    match seen.get("pen") {                    // Option<&i64>
        Some(q) => println("pen={q} total={total}"),
        None => println("no pen"),
    }
    let text = format_in("{} {}", items.len(), seen.len(), gpa); // a String<Gpa>
    println("{text}");                         // text, seen, items, input: dropped at the end
    0
}
```
```in
3 pen 2 ink 5 cap 1
1,2, 3
```
```out
0:ink 1:pen 2:cap pen=2 total=6
3 3
```

Lines one at a time: `let mut b = String::new_in(gpa); while
io::stdin().read_line(&mut b).unwrap() > 0 { ... }` (appends, with the
`'\n'`; `b.clear()` between). An owned value (`Vec`, `String`,
`HashMap`, a struct holding one) moves into a by-value parameter, a
`let w = v;`, a struct field or a `return`: `v` is dead after it
(`borrowck.use_moved`); pass `&v` to lend it, or `v.clone()`. A `Copy`
value (numbers, `&T`, a struct deriving it) is copied. A temporary is
dropped at the end of its statement. A slice of `v` (`&v[a..b]`) borrows
it: `v` does not grow while the slice is used. What allocates has Rust's
name with `_in` and takes the allocator last: `collect_in(gpa)`,
`to_string_in(gpa)`, `format_in(.., gpa)`. std's most used items:
`volec guide std`; all, a line each: `volec guide std#the-api`; one name
with its comment: `volec guide --find split_once`.

## The first errors and their fixes

| error (short form) | fix |
|---|---|
| `'println!' is a macro call: vole has no macros` | `println("{a}")`, the help's form |
| `'Vec::new' allocates from nothing` (`alloc.no_in`) | `Vec::new_in(gpa)`: main's `gpa`, passed down; `volec fix --only alloc` |
| `'Vec' names no allocator` (`alloc.default`) | `Vec<i64, Gpa>`; a struct holding one: `struct P<A: Allocator> { v: Vec<i64, A> }`, used as `P<Gpa>` (`volec fix --only alloc` writes both) |
| `expected 'String<Gpa>', got '&str'` | `String::from_in("..", gpa)`: a String owns its text; a parameter `s: &str` takes literals and a String's `&s` |
| `cannot assign to immutable variable 'a'` | `let mut a` |
| `borrowck.borrow_immutable: cannot borrow 'w' as mutable, as it is not declared as mutable` | `let mut w`: `w.push(1)` and `&mut w` change it |
| `expected '&mut Vec<i64, Gpa>', got 'Vec<i64, Gpa>'` | `f(&mut v)`: the callee may change `v` |
| `borrowck.use_moved: 'v' is used here after it moved` | lend it (`&v`), or `keep(v.clone())` |
| `borrowck.conflict: cannot borrow 'u' as mutable because it is also borrowed as immutable` | use the shared borrow before the change, or take it again after (`guide memory#borrowing`) |
| `non-exhaustive match: 'E::B' is not covered` | an arm for it, or `_ =>` |
| `calling a C function is unsafe` | `unsafe { ... }`; `volec fix --only unsafe` adds them |
| `expected 'i32', got 'i64'` | `x as i32`: only widening is implicit |
| `an index is a 'usize', got 'i64'` | `v[i as usize]`, or declare `i: usize` |

Every error has a `help:`; `volec guide errors` has more.

Tests and checks: `#[test] fn` and `#[property] fn p(x: i64)` (inputs
generated, shrunk) sit next to the code and `volec test` runs them at
-O0 and -O2; `requires`/`ensures` clauses and `assert_eq(a, b)` are
checked at run time (`guide testing`, `guide contracts`).

Float math: Rust's methods on f32 and f64 (`x.sqrt()`, `y.atan2(x)`,
`x.powi(2)`) and constants (`std::f64::consts::PI`): `volec guide math`.
SIMD and CPU intrinsics: `std::arch`, the vendors' names (`vaddq_u8`)
checked against the CPU: `volec guide arch`; `query arch WORDS`.
GPU compute and rendering: `std::gpu`, wgpu's objects on Metal: `volec guide gpu`.

## The loop

Write the program, then `volec check` (a check hook, where there is
one, runs it after each edit); fix the first error first. A clean check
ends with `ok: 0 errors in main.vl (1 file, 0 shaders)` (the program checked), a build with `ok: built prog`. Before writing a construct
you are unsure of, `volec guide --find WORDS` (`--find read a line`)
or `volec guide TOPIC#SECTION` prints the lines on it; `volec
try 'CODE'` runs a snippet. For an unfamiliar item, ask
`volec query context NAME` first: its source, what it calls and its
callers in one call (`query context parse_args`). Edits, refactorings
and other queries: `volec guide tools`.

Topics (`volec guide TOPIC`, `TOPIC#` lists its sections):
@TOPIC-NAMES@
