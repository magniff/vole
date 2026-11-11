# Errors and their fixes

`volec check`, and a build whose output is not a terminal (an
agent's shell, a pipe; `--diagnostics=short` anywhere): one line per
error, `FILE:LINE:COL: error[KIND] MESSAGE | help: HELP | note: NOTE |
try: TRY`, every error of every file at once (up to 50), sorted by
position. A `try:` (0.17) is text to use as it is: code to paste where
the error is (`a as i32`, `&v`, the missing match arms), a
`use` line, or a `volec` command to run (`volec fix --only unsafe
main.vl`, `volec edit new-file util.vl main.vl`); VALUE in it
is yours to fill in.
An error whose fix the compiler knows exactly (0.18: a did-you-mean with
one name that near, a conversion, a path from `crate::`, a missing
`use` or `pub`, a missing `gpa` argument)
also has `try: volec fix --suggested main.vl`: one command makes
all of them, as one checked edit (`--dry-run` shows the diff, `volec
undo` takes it back, `--at FILE:LINE` fixes one line's), then prints the
errors left. Run it instead of editing those lines by hand or with sed.
KIND is `tokenizer error`, `parser error`, `module error`, `type error`,
`unsafe`, or a code (`alloc.no_in`, `borrowck.conflict`: `volec explain
CODE`). Fix the first errors first: a parser error can hide
type errors in the same function. `volec query show FILE:LINE` prints
the item at an error's position. Below: what a newcomer writes, the
error (short form, without the position), and the fix.

## Where vole is not Rust

```vole
let s: String<Gpa> = String::new();
```
```err
error[alloc.no_in] 'String::new' allocates from nothing: pass the allocator, last, to 'String::new_in' | help: this function's `gpa` is the allocator to pass
```
Nothing allocates without an allocator: `String::new_in(gpa)`,
`s.to_uppercase_in(gpa)`, `x.to_string_in(gpa)`, `it.collect_in(gpa)`,
with `gpa` from `fn main(gpa: Gpa)`, passed down (`guide allocators`).
`volec fix --only alloc` writes the `_in` form where one allocator is in
scope.

```vole
let v: Vec<i64> = Vec::new_in(gpa);
```
```err
error[alloc.default] 'Vec' names no allocator: its 'A' is written
```
The allocator is part of the type: `Vec<i64, Gpa>`, `String<Gpa>`,
`HashMap<K, V, Gpa>`, `Box<T, Gpa>`.

```vole
struct Parser { toks: Vec<u8, Gpa> }
fn main() -> i32 { 0 }
```
```err
error[alloc.field] the struct 'Parser' holds an allocator its parameters do not name: 'Gpa', in field 'toks'
```
`struct Parser<A: Allocator> { toks: Vec<u8, A> }` (`use
std::alloc::Allocator;`), used as `Parser<Gpa>`.

```vole
fn name(s: String<Gpa>) -> usize { s.len() }
fn main() -> i32 { name("x") as i32 }
```
```err
error[type error] expected 'String<Gpa>', got '&str'
```
A String owns its text, on an allocator: `String::from_in("x", gpa)`. A
function that only reads text takes `s: &str`, which a literal and a
String's `&s` both go to.

```vole
println!("{}", 1);
```
```err
error[parser error] 'println!' is a macro call: vole has no macros | help: write `println("{}", 1)`
```
The call without its `!` takes the same format string (`volec guide
formatting`). The help names what replaces `vec!`,
`format!`, `assert!` and the others.

```vole
let o: Option<i64> = Some(1);
let Some(x) = o;
```
```err
error[type error] refutable pattern in 'let'
```
`let Some(x) = o else { return 1; };` (0.18.1, the else block must
leave), or `let x = match o { Some(x) => x, None => 0 };`.

```vole
let big = i64::MAX();
```
```err
error[type error] no associated function 'MAX' in 'i64' | help: a constant, without (): 'i64::MAX'
```
`i64::MAX`, `u8::MIN`, ... are constants, as `f64::EPSILON`, `f64::MAX`,
`f64::NAN` and `std::f64::consts::PI` (`guide math`).

```vole
let s = "add";
match s { "add" => println("a"), _ => println("b") }
```
```err
error[parser error] expected a pattern, got 'string literal'
```
`if s == "add" { ... }`: a string literal is not a pattern yet (integers,
chars, bools, variants, tuples are).

```vole
fn main() -> i32 {
    fn helper() -> i64 { 3 }
    helper() as i32
}
```
```err
items cannot be nested in blocks
```
Move `helper` to the module level.

## Types

```vole
let x = 1;
x = 2;
```
```err
error[type error] cannot assign to immutable variable 'x' | help: make it mutable: `let mut x`
```
`let mut x = 1;`: a `let` binding does not change.

```vole
let a: i64 = 1;
let b: i32 = a;
```
```err
error[type error] expected 'i32', got 'i64'
```
Only widening is implicit (`i32` to `i64`, `u8` to `u32`, ...; Rust
writes those too, `i64::from(a)`): narrowing is `a as i32`. The same for `1 + 1.0`, `u32` to `i32`, and
for `main` returning an `i64` (`n as i32`).

```vole
let b: u8 = 300;
```
```err
error[type error] integer literal 300 does not fit in type 'u8'
```
An unsuffixed literal takes the type the code around it gives: `if ok {
line[i] } else { 0 }` is a `u8`, from the other branch; so are match arms
and array elements beside a `u8`, and an array of literals beside an
array (`if down { ACCENT } else { [0.2, 0.5, 0.7, 1.0] }` is a `[f32;
4]` when `ACCENT` is). Alone, a literal is `i32` (`f64`), and a `let` of
literals keeps that type: `let base = [0.2, 0.5, 0.7, 1.0];`
beside a `[f32; 4]` is an error whose note names the `let` and its
annotation, `let base: [f32; 4] = ...`.

```vole
let x = 1;
if x { }
```
```err
error[type error] expected 'bool', got 'i32'
```
`if x != 0`.

```vole
let a = 1;
if 0 < a < 2 { }
```
```err
error[parser error] comparison operators cannot be chained; use parentheses
```
`if 0 < a && a < 2`.

```vole
fn f() -> i64 { 1; }
```
```err
error[type error] function 'f' body has type '()', expected 'i64'
```
The value is the last expression without `;`: `fn f() -> i64 { 1 }`.

```vole
struct P { x: i64, y: i64 }
fn make() -> P { P { x: 1 } }
```
```err
error[type error] missing field 'y' in struct 'P' constructor
```

```vole
fn f(a: i64, b: i64) -> i64 { a + b }
fn g() -> i64 { f(1) }
```
```err
error[type error] function 'f' expects 2 arguments, got 1
```

```vole
enum E { A, B, C }
fn f(e: E) -> i64 { match e { E::A => 1, E::B => 2 } }
```
```err
error[type error] non-exhaustive match: 'E::C' is not covered | help: add an arm for it (try:), or a wildcard arm '_ =>' | try: E::C => VALUE,
```
The `try:` lists every missing pattern as an arm to paste (integers as
ranges: `201..=255 => VALUE,`). An unreachable arm's help gives the line
of the arm above that already matches all it matches.

```vole
fn f() -> i64 { 1 }
fn main() -> i32 { 0 }
fn f() -> i64 { 2 }
```
```err
duplicate function 'f'
```
The help says where the other one is, and the two `try:` lines delete
either (`volec edit delete main.vl:3 main.vl`); to change an item
in place, `volec edit replace f < new.vl` instead of adding a second.

```vole
enum E { A(i64), B }
fn f(e: E) -> i64 { match e { A(x) => x, B => 0 } }
```
```err
error[type error] unknown variant 'A'
```
`E::A(x)`, or `use E::{A, B};` once.

```vole
enum Ev { Key { code: i64, shift: bool }, Quit }
fn main() -> i32 {
    let e = Ev::Key(1, false);
    match e { Ev::Key(c, _) => c as i32, Ev::Quit => 0 }
}
```
```err
error[type error] variant 'Ev::Key' has named fields; give them by name | try: Ev::Key { code: 1, shift: false }
```
A struct-like variant is built and matched by name, as in Rust:
`Ev::Key { code: 1, shift: false }`, `Ev::Key { code, .. } => code`.

```vole
enum Ev { Key { code: i64, shift: bool }, Quit }
fn code(e: Ev) -> i64 {
    match e { Ev::Key { code } => code, Ev::Quit => 0 }
}
```
```err
error[type error] the pattern of 'Ev::Key' does not mention field 'shift' | help: match it too, or end the pattern with '..' to leave the rest out | try: Ev::Key { code, .. }
```

```vole
enum Ev { Key { code: i64, shift: bool }, Quit }
fn code(e: Ev) -> i64 { e.code }
```
```err
error[type error] cannot access field 'code' on type 'Ev' | help: a variant's fields are read through a pattern (no '.field' on an enum) | try: if let Ev::Key { code, .. } = e { ... }
```

## Slices, Vec, std

```vole
let n = 3;
for x in n { }
```
```err
error[type error] no method 'into_iter' on type 'i32'
```
`for x in 0..n`. A `for` takes an `IntoIterator`: a range, `&v`,
`v.iter()`, a `HashMap`; a type of yours with `impl Iterator for T`
(`volec guide iterators`).

A misspelt method, field or item gets the nearest name of its kind:

```vole
fn main(gpa: Gpa) -> i32 { let mut b = String::new_in(gpa); b.push_string("x"); 0 }
```
```err
error[type error] no method 'push_string' on type 'String<Gpa>' | help: did you mean 'push_str'?
```

```vole
fn main(gpa: Gpa) -> i32 { let m: HashMap<i64, i64, Gpa> = HashMap::new_in(gpa); 0 }
```
```err
error[type error] unknown type 'HashMap' | help: add `use std::collections::hash_map::HashMap;`
```
`use std::collections::HashMap;` (the prelude's names need no import:
`volec guide modules`); `volec fix --suggested` adds the line.

```vole
use std::collections::HashMap;
struct K { a: i64 }
fn main(gpa: Gpa) -> i32 {
    let mut m: HashMap<K, i64, Gpa> = HashMap::new_in(gpa);
    m.insert(K { a: 1 }, 2);
    0
}
```
```err
error[type error] the trait 'Hash' is not implemented for 'K' | help: required by the bound 'K: Hash' of 'HashMap::insert'
```
`#[derive(PartialEq, Eq, Hash)] struct K { a: i64 }`.

```vole
let c: char = 65u8;
```
```err
error[distinct.mix] '65u8' is 'u8' where 'char' goes
```
`65u8 as char`; a byte literal is `b'A'`, a `char` `'A'`.

## Closures and iterators

```vole
let f = |x| x + 1;
```
```err
error[type error] cannot infer the type of closure parameter 'x'
```
`|x: i64| x + 1`: in a `let`, nothing says what `x` is; as an argument
for `F: Fn(i64) -> i64` or `fn(i64) -> i64` the type comes from there.

```vole
fn run(f: fn(i64) -> i64) -> i64 { f(1) }
fn main() -> i32 {
    let k = 2;
    run(|x| x + k) as i32
}
```
```err
make the parameter generic
```
A closure that captures is no plain `fn`: `fn run<F: Fn(i64) -> i64>(f:
F) -> i64`. One that captures nothing converts.

```vole
fn apply<F: Fn(i64)>(f: F) { f(1); }
fn main() -> i32 {
    let mut total = 0;
    apply(|x| { total += x; });
    total as i32
}
```
```err
FnMut
```
`Fn` takes closures that assign no captured variable: bound `F:
FnMut(i64)` (and take it `mut f: F`).

```vole
fn apply<F: Fn(i64) -> i64>(f: F) -> i64 { f(1) }
fn main() -> i32 {
    let f = {
        let j = 1;
        |x: i64| x + j
    };
    apply(f) as i32
}
```
```err
error[borrowck.dropped_borrowed] 'j' does not live long enough
```
The closure borrows `j`, and `j` ends with the block: `move |x: i64| x +
j` takes a copy, or declare `j` before the block.

## ?, conversions, arguments, formatting, derive

```vole
fn first(v: Option<i64>) -> i64 { let x = v?; x }
```
```err
'?' needs 'first' to return Option or Result; it returns 'i64'
```
Return `Option<i64>` (or `Result<i64, E>`), or `match` on the value.
`?` on an Option inside a function returning a Result needs the error:
`v.ok_or(MyError::Missing)?`.

```vole
enum AppError { Bad }
fn read(s: &str) -> Result<i64, AppError> { let n: i64 = s.parse()?; Ok(n) }
```
```err
'?' cannot convert the error 'ParseIntError' into 'AppError'
```
The help is the impl to add: `impl From<ParseIntError> for
AppError { fn from(e: ParseIntError) -> AppError { ... } }`.

```vole
struct M { m: i64 }
impl Into<M> for i64 { fn into(self) -> M { M { m: self } } }
```
```err
conflicting impls of trait 'Into'
```
Implement `From<i64> for M`; `Into` comes with it (std's blanket impl). `x.into()` needs the
type it converts to: `let y: M = x.into();`.

```vole
fn f(a: i64, b: i64) -> i64 { a + b }
fn main() -> i32 { f(b: 1, 2) as i32 }
```
```err
a positional argument after a named one: the named arguments come last
```
Named arguments follow the positional ones, in the parameters' order
(`f(1, c: 3, b: 2)` is an error whose `try:` is `f(1, b: 2, c: 3)`); a
missing one gets `try: f(1, b: VALUE)`, a misspelt name the nearest.

```vole
fn f(a: i64, b: i64 = 2) -> i64 { a + b }
```
```err
a parameter has no default value; pass it at each call
```
No parameter has a default value (`syntax.default-arg`; the `try:`
removes it): every call passes every argument, by position or by name.

```vole
struct P { x: i64, y: i64 }
fn main() -> i32 { let x = 1; let p = P { x, y }; p.x as i32 }
```
```err
undefined variable 'y'
```
The shorthand `P { x, y }` takes locals of the fields' names: write
`y: VALUE`.

```vole
#[derive(Debg)]
struct P { x: i64 }
```
```err
cannot derive 'Debg' (derivable: PartialEq, Eq, PartialOrd, Ord, Hash, Debug, Clone, Copy, Default)
```
Display is written by hand. Deriving a trait and implementing it too is a coherence error
whose help is `remove Ord from #[derive]`; deriving `PartialEq` needs
`==` on every field.

```vole
struct P { x: i64 }
fn main() -> i32 { let p = P { x: 1 }; println("{p}"); 0 }
```
```err
'P' does not implement Display
```
Implement it (`impl fmt::Display for P { fn fmt(&self, f: &mut
fmt::Formatter) -> fmt::Result { write(f, "P({})", self.x) } }`, with
`use std::fmt;`), or print with `{p:?}` and `#[derive(Debug)]`.

```vole
fn main() -> i32 { let x = 1; println(f"x = {x + 1}"); 0 }
```
```err
f-strings are removed (0.26.3)
```
Write the format literal: a name
stays in its hole, an expression becomes `{}` and an argument,
`println("x = {}", x + 1)`.

## Generics and traits

```vole
fn biggest<T>(a: T, b: T) -> T { if a > b { a } else { b } }
struct P { x: i64 }
fn main() -> i32 { let p = biggest(P { x: 1 }, P { x: 2 }); 0 }
```
```err
error[type error] comparison requires numeric type, got 'P' | note: in instantiation of 'biggest<P>'
```
A generic body is checked per use; the note names the instance.
Derive or implement `PartialOrd` for `P`, and bound `T: PartialOrd` to
say what it needs.

```vole
trait A { fn a(self) -> i64; fn b(self) -> i64; }
struct S { }
impl A for S { fn a(self) -> i64 { 1 } }
```
```err
error[type error] the impl of trait 'A' is missing 'b' | help: it has no default: write it in the impl
```

```vole
trait A { fn a(self) -> i64; }
fn f(x: &dyn A) -> i64 { 0 }
```
```err
error[parser error] 'dyn' is a reserved keyword
```
No trait objects: `fn f<T: A>(x: T)`, or an enum of the cases.

## Modules and imports

```vole
use std::*;
```
```err
error[module error] wildcard imports are not allowed
```
`use std::collections::{HashMap, HashSet};`; `volec fix --only imports`
writes them.

```vole
mod m { pub fn helper() -> i64 { 1 } }
fn main() -> i32 { helper() as i32 }
```
```err
error[type error] undefined variable 'helper' | help: add `use crate::m::helper;`
```
Add the `use` line the help names, or run the `try:` line, `volec fix
--suggested main.vl`, which adds every missing one (and makes the
other errors' exact fixes; `fix --only imports`: the imports alone).

In a module other than the root, a path starts in that module, or with
a sibling module, or one of the root: `use table::Table;` and
`table::f(x)` in check.vl are `crate::table::...` when `mod table;` is
in main.vl. A module elsewhere (`crate::a::table`) is `unknown module
'table'`, whose help says `crate::a::table::...` and whose `try:` is the
`use` line so written (in code: `use crate::a::table;`). `mod util;` with no util.vl is
`cannot find the file of module 'util'`, whose `try:` makes it:
`volec edit new-file util.vl main.vl < util.vl` (the text on
stdin; the `mod` line that is there stays). A `mod` line for a file that
is next to a submodule's file belongs in the root.

```vole
fn main() -> i32 { let total = 1; println("{}", totl); 0 }
```
```err
error[type error] undefined variable 'totl' | help: did you mean 'total'?
```
A module and an item of the same name both work, as in Rust: after `mod
eval; use eval::eval;`, `eval(x)` calls the function and `eval::NAME`
goes through the module.

```vole
mod m { fn hidden() -> i64 { 1 } }
fn main() -> i32 { m::hidden() as i32 }
```
```err
error[item.private] 'hidden' is private | help: make it public: `pub fn hidden` at
```
The help gives the declaration with `pub` and where it is (`volec fix
--only pub` writes them all). Child modules see their parent's private items, not
the reverse. A struct's fields too:

```vole
mod m {
    pub struct P { pub x: i64, y: i64 }
    pub fn p() -> P { P { x: 1, y: 2 } }
}
fn main() -> i32 { m::p().y as i32 }
```
```err
error[field.private] field 'y' of 'P' is private to module 'm' | help: make it public: 'pub y: i64' at
```

## unsafe

```vole
extern "C" { fn abs(x: i32) -> i32; }
fn main() -> i32 { abs(-3) }
```
```err
error[unsafe] calling a C function is unsafe
```
`unsafe { abs(-3) }`. The error's `try:`, `volec fix --only unsafe
main.vl`, wraps every such place; the check hook prints it once at the
head of its report, with how many errors it answers.

```vole
fn helper() -> i64 { let v: Vec<i64, Gpa> = Vec::new(); v.len() as i64 }
fn main() -> i32 { helper() as i32 }
```
```err
add the parameter `gpa: Gpa` to 'helper' and pass it down
```
Allocation is explicit (`alloc.no_in`): the help
says where the allocator comes from here (this function's `gpa`, main's
parameter, or one to add). `volec fix --only alloc` writes the call
when one allocator is in scope; here there is none, and the parameter
is yours to add (`volec refactor signature`).

```vole
struct P { x: i64 }
fn main() -> i32 {
    let mut p = P { x: 1 };
    let q: *mut P = &mut p;
    q.x = 9;
    0
}
```
```err
error[unsafe] access to a field through a raw pointer is unsafe
```
`q` is a raw pointer. Use `p.x = 9;`, a reference (`let q = &mut p; q.x =
9;`, safe), or pass `&mut p` to a function taking `p: &mut P`.

```vole
fn factorial(n: i64) -> i64 { if n < 2 { 1 } else { n * factorial(n - 1) } }
fn main() -> i32 { let f = &factorial; f(5) as i32 }
```
```err
error[type error] cannot take the address of 'factorial': a function's name is already a pointer to it
```
A function's name is a `fn(i64) -> i64` value: `let f = factorial;`,
then `f(5)`. `fix --suggested` drops the `&`.

```vole
fn first(p: *const i64) -> i64 { p[1] }
```
```err
error[type error] cannot index into a value of type '*i64' | help: a raw pointer is not indexed: offset it and read, `unsafe { *p.add(i) }`
```
A pointer is one value; for many, take a slice `&[i64]`: a slice or a
Vec indexes its elements, checked and safe.

```vole
fn read(x: *const i64) -> i64 { *x }
```
```err
error[unsafe] dereference of a raw pointer is unsafe
```
Take a reference, `x: &i64` (`x: &mut i64` when written through, called
with `&mut n`), or vouch for the pointer in `unsafe { *x }` (`fix --only
unsafe`). The same for a field access and a method call through it.

```vole
unsafe fn danger() -> i64 { 1 }
fn main() -> i32 { danger() as i32 }
```
```err
error[unsafe] calling an `unsafe fn` is unsafe
```
Call it in `unsafe { }`, under a `// SAFETY:` comment that says why its
contract holds here.

## Borrowing and moves

The borrow checker's errors (`borrowck.*`) are Rust's, one line each,
with both positions and a `help:` with the fix; the message names
rustc's code where it has one, and `volec explain borrowck.CODE` has
each in full (`guide memory#borrowing`).

```vole
fn bump(n: &mut i64) { *n += 1; }
fn main() -> i32 { let mut q = 1i64; bump(q); q as i32 }
```
```err
error[type error] expected '&mut i64', got 'i64'
```
`bump(&mut q)`: the call shows what may change. Where a `&T` goes, a
value is `edition.lenient: 'q' is a value where a reference goes`: pass
`&q`.

```vole
fn keep(v: Vec<i64, Gpa>) -> usize { v.len() }
fn main(gpa: Gpa) -> i32 { let v: Vec<i64, Gpa> = Vec::new_in(gpa); keep(v); v.len() as i32 }
```
```err
error[borrowck.use_moved] 'v' is used here after it moved
```
A parameter by value takes the argument; the caller's `v` is dead after
the call (rustc E0382). When `keep` only reads, make it `v: &Vec<i64,
Gpa>` and pass `&v`; else pass `keep(v.clone())` or use `v` before. An
owned value also moves with `let w = v;`, `return v`, into a struct
literal and into a `for x in v`.

```vole
fn main(gpa: Gpa) -> i32 { let w: Vec<i64, Gpa> = Vec::new_in(gpa); w.push(1); w.len() as i32 }
```
```err
error[borrowck.borrow_immutable] cannot borrow 'w' as mutable, as it is not declared as mutable
```
A `&mut self` method and `&mut w` change `w`, so it is a `let mut w`
(E0596), as for an assignment; the same for a closure that changes what
it captures and is called (`let mut bump = || n += 1;`).

```vole
fn main(gpa: Gpa) -> i32 {
    let mut v: Vec<i64, Gpa> = Vec::new_in(gpa);
    v.push(1);
    let first = &v[0];
    v.push(4);
    *first as i32
}
```
```err
error[borrowck.conflict] cannot borrow 'v' as mutable because it is also borrowed as immutable
```
`v.push(4)` may move the elements `first` points into (E0502). Use the
borrow before the change, or take it again after; keep an index (`for i
in 0..v.len() { let x = v[i]; ... }`); copy a `Copy` value out first
(`let x = v[0];`). The same for a push inside `for x in &v`.

```vole
fn swap(a: &mut i64, b: &mut i64) { let t = *a; *a = *b; *b = t; }
fn main() -> i32 { let mut a = 1; swap(&mut a, &mut a); a as i32 }
```
```err
error[borrowck.mut_twice] cannot borrow 'a' as mutable more than once at a time
```
A `&mut` is the only way to its place while it is used (E0499): two
elements of one Vec swap with `v.swap(i, j)`, two halves borrow with
`split_at_mut`.

```vole
fn main() -> i32 { let mut n = 1; let r = &n; n = 2; *r }
```
```err
error[borrowck.assign_borrowed] cannot assign to 'n' because it is borrowed
```
Assign after the borrow's last use (E0506).

```vole
use std::alloc::Allocator;
struct T<A: Allocator> { keys: Vec<i64, A> }
impl T<Gpa> { fn rehash(&mut self) { let mut old = self.keys; old.push(1); } }
fn main() -> i32 { 0 }
```
```err
error[borrowck.move_out] cannot move out of 'self.keys', which is reached through a reference or an index
```
A value behind a reference stays there (E0507): borrow it (`&self.keys`),
clone it, or take it and leave another in its place
(`std::mem::replace(&mut self.keys, Vec::new_in(gpa))`, `Option::take`).
`let s = v[i];` of an element that is not `Copy` is the same error.

```vole
fn greet<'a>(gpa: Gpa) -> &'a str { let b = String::from_in("hi", gpa); b.as_str() }
fn main() -> i32 { 0 }
```
```err
error[borrowck.return_local] a reference to 'b', a local of this function, escapes it
```
Return the `String` (`-> String<Gpa>`, `b`), not a borrow of it (E0515);
the caller borrows.

```vole
fn longest(a: &str, b: &str) -> &str { if a.len() > b.len() { a } else { b } }
fn main() -> i32 { 0 }
```
```err
error[borrowck.elision] the result of 'longest' borrows, but from which parameter is not said
```
`fn longest<'a>(a: &'a str, b: &'a str) -> &'a str` (E0106): with one
reference parameter, or `&self`, nothing is written.

## At run time

A failed check prints its message on stderr and exits with code 101:
`index out of bounds: index I, length N`, `slice range out of bounds:
...`, `called unwrap on None`, `called unwrap on Err`, `invalid value V
for enum E`, `attempt to divide by zero`. A program built with `--trace`
prints, instead, the failing line and the calls that led to it
(`volec test` builds so; `guide debug`). Integer overflow panics at -O0
and wraps at -O1 and above. Runaway recursion is stopped by the operating system
(a signal, no message).

```vole
enum Level { Low, High }

fn main() -> i32 {
    let v: Option<i64> = None;
    println("{}", v.unwrap_or(5));
    let e = 3 as Level;
    println("{}", e as i64);
    0
}
```
```out (exit 101)
5
main.vl:6:13: invalid value 3 for enum Level
```
