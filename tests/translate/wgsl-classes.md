# Translator classes found by the std::gpu::wgsl port (0.27.6, draft)

`fix --edition rust` on MVS std's gpu/wgsl front (ir, names, lex, front,
expr, builtins, entry, uniformity: 6,862 lines) as a program of its own
left 35 type errors. Each class below gives a minimal MVS program (it
checks clean as MVS, unless said), what the translator writes, and what
it should write. "Port" counts the hand fixes in the wgsl port that the
class's rule would have made; they come out once the rule lands.

## 1. `use std::Option::Some;` is kept

```
use std::Option::Some;

fn half(x: i64) -> Option<i64> {
    if x % 2 == 0 { Some(x / 2) } else { None }
}

fn main() {
    match half(4) {
        Some(h) => println("{}", h),
        None => println("odd"),
    }
}
```

The output keeps line 1: `no 'Option' in module 'std'`, then `unknown
variant 'Some'`. Wanted: delete the import (std2's prelude has `Some`,
`None`, `Ok`, `Err`). Same for `use std::Option::None` and
`std::Result::{Ok, Err}`. Port: 2.

## 2. A `Buf<A>` type becomes `Buf<u8, A>`

```
use std::{Allocator, Buf, Gpa};

pub struct Fr<A: Allocator> {
    pub emsg: Buf<A>,
}

impl<A: Allocator> Fr<A> {
    pub fn err(inout self, what: [u8]) {
        self.emsg.push_fmt("'{what}' is not here");
    }
}

fn main(gpa: Gpa) {
    var f = Fr { emsg: Buf::new_in(gpa) };
    f.err("x");
    println("{}", f.emsg.len);
}
```

Output: `pub emsg: Buf<u8, A>` (the type row `Buf - type Vec<u8, $1>`
fills its arguments but keeps the name): `unknown type 'Buf'`. Wanted
`Vec<u8, A>`. Also in a parameter, `b: inout Buf<A>` -> `&mut Buf<u8,
A>`. Port: 4.

## 3. A `Buf`'s `push_fmt` through a field or a parameter is not rewritten

Same program as 2: `self.emsg.push_fmt("..")` stays `push_fmt` (row 91,
`std::fmt::write(&mut $r, $1).unwrap()`, does not fire), and so does
`out.push_fmt(..)` with `out: inout Buf<Gpa>` (program 5). Wanted:
`write(&mut self.emsg, "..").unwrap()` (std2's `write`, as row 90
writes for `push_int`). Port: 71 (front 24, builtins 16, expr 16, ir 8,
entry 7).

## 4. `x.len` on a Buf becomes `x.len()()`

Same program as 2: `println("{}", f.emsg.len)` -> `f.emsg.len()()`
(`cannot call non-function type 'usize'`). The `.len` -> `.len()` rule
and the `Buf::len` row both apply. Wanted: `f.emsg.len()`.

## 5. An inline capture of bytes becomes a named argument

```
use std::{Buf, Gpa, Vec};

fn note(out: inout Buf<Gpa>, what: [u8]) {
    out.push_fmt("'{what}' is not here");
}

fn main(gpa: Gpa) {
    var b: Vec<u8, Gpa> = Vec::new_in(gpa);
    b.push('x');
    var out = Buf::new_in(gpa);
    note(&out, b.as_slice());
    println("{}", out.len);
}
```

Output: `out.push_fmt("'{what}' is not here", what =
str::from_utf8(what).unwrap())`. std2's format functions take no named
argument: `named argument 'what': only the calls of functions and
methods name their arguments`. Wanted (with 3): `{ let what =
str::from_utf8(what).unwrap(); write(&mut *out, "'{what}' is not
here").unwrap(); }`, or a positional `{}` with the argument. Port: 13.

## 6. `std::num::parse_f64(s[a..b])` becomes `&s[a..b].parse::<f64>()`

```
use std::{Gpa, Vec};

fn num(s: [u8]) -> f64 {
    std::num::parse_f64(s[0..3]).unwrap_or(0.0)
}

fn main(gpa: Gpa) {
    var b: Vec<u8, Gpa> = Vec::new_in(gpa);
    b.push('1');
    b.push('.');
    b.push('5');
    b.push('x');
    println("{}", num(b.as_slice()));
}
```

Output: `&s[0..3].parse::<f64>().unwrap_or(0.0)`. Two mistakes: the
`&` the view gets is put in front of the whole chain (`&(s[..].parse()
..)`), and `parse` is called on bytes (`no method 'parse' on type
'[u8]'`). Wanted: `str::from_utf8(&s[0..3]).ok().and_then(|t|
t.parse::<f64>().ok()).unwrap_or(0.0)` (or `.map_or`), and `&s[..]`
itself when the operand is not text. Port: 1.

## 7. A non-Copy struct read out of a Vec is a move

```
use std::{Allocator, Gpa, Vec};

struct F<A: Allocator> {
    params: Vec<i64, A>,
}

fn count(fs: Vec<F<Gpa>, Gpa>) -> i64 {
    let f = fs[0];
    f.params.len as i64
}

fn main(gpa: Gpa) {
    var fs: Vec<F<Gpa>, Gpa> = Vec::new_in(gpa);
    var p: Vec<i64, Gpa> = Vec::new_in(gpa);
    p.push(1);
    fs.push(F { params: p });
    println("{}", count(fs));
}
```

Output: `let f = fs[0];` (borrowck.move_out); in the wgsl port, with a
generic struct, `m.functions[h as usize].clone()` on a type with no
Clone. Wanted: `let f = &fs[0];` (MVS's copy of a view; nothing writes
`f`). Port: 1.

## 8. A row's text literal where bytes go

MVS `self.emsg.push_str("ref to ")` (a Buf field) -> `self.emsg.
extend_from_slice("ref to ")` (row 89): a `&str` where `&[u8]` goes
(F0.6, rustc E0308). Wanted: `extend_from_slice(b"ref to ")`: the
translator's text-to-bytes rule, applied to the row's output. Port: 57
(53 `extend_from_slice`, 4 other calls taking bytes).

## Also seen (not errors)

- The `use` lines it adds are joined on one line (`use std::mem; use
  std::alloc::Allocator; use std::alloc::ArenaScope as ScopedArena;`).
- `ScopedArena` becomes `use std::alloc::ArenaScope as ScopedArena` and
  `&ScopedArena<'_, Gpa>` in signatures, and `impl Front<'_,
  &ScopedArena<'_, Gpa>>`: an impl whose methods return the struct's
  borrowed text (`fn name_of(&self, ..) -> &[u8]`) then ties it to
  `&self`, so every `write(&mut self.emsg, .., self.name_of(s))` is a
  borrowck.conflict. The port makes them generic (`impl<'a, A: Allocator
  + Copy> Front<'a, A>`, `-> &'a [u8]`); a rule may be out of reach,
  but `pub type V<T> = Vec<T, &ScopedArena<'_, Gpa>>;` (an elided
  lifetime in a type alias) is never valid Rust.
- `Module::new` gets the result `Module<'static, ..>`.
