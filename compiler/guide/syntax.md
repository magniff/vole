# Syntax

The whole grammar is docs/grammar.md; this is what a program uses. It
is Rust's, with the differences named here.

## Lexical

- Comments: `// line`, `/* block, nesting */`. No doc-comment syntax:
  `//` above an item is its comment.
- Identifiers: ASCII letters, digits, `_`; `_` alone is the wildcard.
  `r#type` is the identifier `type` (C names that are keywords).
- Keywords are Rust's (`let mut`, `move`, `ref`, `match`, `impl`,
  `where`, ...) plus `import` (a C header) and `union`. Reserved
  (errors): `dyn`, `defer` (a guard with `Drop` does it), `@`. `var`,
  `inout` and `sink` are plain names (not keywords).
- Integers: `42`, `1_000`, `0xff`, `0b1010`, with a type suffix `255u8`,
  `7i32`. Floats: `1.5`, `2e10`, `1.5f32`. `'a'`, `'\n'`, `'\u{e9}'` are
  `char`s; `b'A'` is a `u8`. Strings: `"a\tb\n\"q\"\\"`, `"\x41"`,
  `"\u{e9}"`, a `&'static str`; `b"a\x41"` a `&[u8]`; `c"..."` a
  NUL-terminated `*const u8`. A backslash at the end of a line inside a
  string continues it, leaving out the line break and the next line's
  indentation. Not there yet: a line break inside `"..."`, raw strings
  `r"..."` and `r#"..."#` (a raw text block, below, is one).
- An f-string, `f"x = {x:>4}"`, is not vole (`syntax.fstring`): a
  format string, `println("x = {x:>4}")`, writes it (`guide formatting`).
- Text blocks, vole's, for text of several lines (WGSL, SQL, a usage
  message): `"""` ending its line opens one, a line holding only blanks
  and `"""` closes it, and the closing line's indentation is removed
  from every line (a line indented less is `lex.text-block-indent`).
  The line breaks after the opening `"""` and before the closing line
  are not in the value; escapes work as in `"..."`. `r"""` is a raw
  block: no escapes, a `\` is a backslash. A text block at a format
  position, `println("""` .. `""", args)`, is a format string. A text
  block is a `&'static str`, in a `const` too. `volec fmt` leaves its
  lines as they are.
- `include_str!("shader.wgsl")` (or `include_str(..)`) is the file's
  text as a string literal, read when the program is compiled (the path
  relative to the file holding the call; UTF-8, else `embed.utf8`).

```vole
const USAGE: &str = """
    usage: tool [-v] FILE
      -v  verbose
    """;
const PATTERN: &str = r"""
    ^\d+\.\d+$
    """;

fn main() -> i32 {
    println("{USAGE}");
    println("{PATTERN} {}", PATTERN.len());
    let n = 2;
    println("""
        "{n}" lines
          {:>3}
        """, n * 2);
    let c = '\u{e9}';
    println("{} {} {:?}", c as u32, b'A', b"a\x41");
    0
}
```
```out
usage: tool [-v] FILE
  -v  verbose
^\d+\.\d+$ 10
"2" lines
    4
233 65 [97, 65]
```

## Items

```vole
use std::collections::HashMap;      // imports first, by convention
use std::hash::FixedState;
import "stdio.h" as c;              // a C header

const LIMIT: i64 = 100;             // a constant expression
const NAMES: [i64; 3] = [1, 2, 3];  // array constants too
static mut COUNTER: i64 = 0;        // a global: unsafe to use
static GREETING: &str = "hi";       // immutable: safe to read
type Grid = [[u8; 8]; 8];           // an alias; `type P<T> = (T, T);`

pub struct Point { x: i64, y: i64 }
struct Wrapper<T> { inner: T }      // generic
struct Meters(f64);                 // a tuple struct
#[derive(Clone, Copy, PartialEq)]
enum Dir { North, South }           // fieldless: casts with `as`
enum Tok { Num(i64), Op(u8), End }  // tuple variants
enum Ev { Key { code: u8, shift: bool }, Quit }   // struct-like variants
#[repr(C)] union Bits { i: u32, f: f32 }

pub fn add(a: i64, b: i64) -> i64 { a + b }
fn first<T: Copy>(s: &[T]) -> T { s[0] }
fn ignore(_: i64) {}                 // `_` ignores an argument
fn bump(mut n: i64) -> i64 { n += 1; n }  // a mutable copy of the argument
fn twice(v: &mut Vec<i64, Gpa>) { v.push(v.len() as i64); } // called as twice(&mut v)
unsafe fn raw(p: *const i64) -> i64 { *p }  // callers need unsafe
fn hi(m: &mut HashMap<i64, i64, Gpa, FixedState>) { m.insert(1, 2); } // the `use`s above

impl Point {
    fn len2(&self) -> i64 { self.x * self.x + self.y * self.y }
    fn move_by(&mut self, d: i64) { self.x += d; }               // p.move_by(1)
}

trait Named { fn name(&self) -> &str; }
impl Named for Point { fn name(&self) -> &str { "point" } }

mod util { pub fn twice(x: i64) -> i64 { x * 2 } }

extern "C" { fn abs(x: i32) -> i32; }
extern "C" fn callback(x: i32) -> i32 { x + 1 }
```

Items may come in any order and refer to each other; they are a
module's (an item inside a function body is not there yet). Parameters
and receivers are Rust's: `x: T` (by value: moved, or copied for a
`Copy` type), `x: &T`, `x: &mut T` (the caller passes `&mut place`),
`mut x: T` (a mutable copy); `&self`, `&mut self`, `self`. Attributes:
`#[derive(..)]`, `#[repr(C)]`, `#[repr(C, packed)]`, `#[repr(C,
align(16))]`, `#[repr(u8)]` (an enum's tag), `#[inline]`,
`#[inline(never)]`, `#[cold]`, `#[deprecated(note = "use g")]` (each use
is `warning item.deprecated` with the note), `#[thread_local]`.

## Statements and blocks

```vole
let x = 1;                          // immutable
let mut y: i64 = 2;                 // mutable, with a type
let (a, mut b) = (3, 4);            // patterns that always match; `mut` per name
b += 0;
let r = &mut y;                     // a mutable borrow of y
*r += x + a * b;                    // = += -= *= /= %= &= |= ^= <<= >>=
{
    let inner = y;                  // a block is an expression
    println("{inner}");
}
```
```out
15
```

`let x;` declares a binding that each path assigns once before it is
read. A statement that starts with `if`, `match`, `loop`, `while`,
`for`, `unsafe` or a block ends at its `}`: no `;` is needed, and it is
never continued by an operator. The last expression of a block, without
`;`, is the block's value. There is no `++`/`--`.

## Expressions and precedence

From loosest to tightest (all left-associative except where noted):

| operators | |
|---|---|
| `=` `+=` `-=` ... | right; an assignment is `()` |
| `\|\|` | |
| `&&` | |
| `==` `!=` `<` `>` `<=` `>=` | not chained: `a < b < c` is an error |
| `\|` then `^` then `&` | bits; `a \| b == c` is `(a \| b) == c` |
| `<<` `>>` | arithmetic `>>` on signed, logical on unsigned |
| `+` `-` | |
| `*` `/` `%` | |
| `as` | `-x as i64` is `(-x) as i64`; `a * b as f64` is `a * (b as f64)` |
| prefix `-` `!` `*` `&` `&mut` | `!` is bool's not and an integer's bitwise not (`~x` is an error); `*r` reads through a reference or a raw pointer |
| `f()` `a[i]` `a[i..j]` `x.f` `x.0` `x.m()` `e?` | `*p.x` is `*(p.x)` |

No `**` (power: `x.pow(n)`), no ternary (`if c { a } else { b }` is an
expression). `e?` is postfix, as tight as a call: `parse(s)?.len()`
(`volec guide conversions`). `return`, `break`, `continue` have type `!`
and fit anywhere: `let v = if ok { x } else { return 1 };`.

In an `if`, `while`, `match` or `for` head, `Name {` starts the body: put
a struct literal there in parentheses, `if p == (P { x: 1 }) { ... }`.

## Control flow

```vole
enum Shape { Line(i64), Dot }
enum Ev { Key { code: u8, shift: bool }, Quit }
fn main(gpa: Gpa) -> i32 {
    let n = 7;
    let parity = if n % 2 == 0 { "even" } else { "odd" };
    println("{parity}");
    let mut i = 0;
    while i < 3 { i += 1; }
    for k in 0..=2 { i += k; }
    for ch in "ab".bytes() { i += ch as i64; }
    let v = loop { i += 1; if i % 10 == 0 { break i; } };
    'rows: for r in 0..3 {
        for c in 0..3 {
            if c == 1 { continue 'rows; }
            if r == 2 { break 'rows; }
        }
    }
    let o: Option<i64> = Some(3);
    if let Some(x) = o { i += x; } else if n > 0 { i -= 1; }
    let mut stack: Vec<i64, Gpa> = Vec::new_in(gpa);
    stack.push(1);
    while let Some(top) = stack.pop() { i += top; }
    let Some(t) = o else { return 1; };
    let mut s = Shape::Line(1);
    match &mut s { Shape::Line(n) => *n += 1, Shape::Dot => {} }
    let e = Ev::Key { code: 3, shift: true };
    let k = match e { Ev::Key { code, shift: true } => code as i64, Ev::Key { .. } => 0, Ev::Quit => -1 };
    let m = match n { 0 => 0, 1..=5 | 9 => 1, x if x > 6 => 2, _ => 3 };
    if let Shape::Line(ref q) = s { i += *q; }
    let (a, mut bb) = (3, 4);
    bb += a;
    println("{v} {i} {t} {k} {m} {bb}");
    0
}
```
```out
odd
210 216 3 3 2 7
```

`match`: arms are tried in order; a pattern may be a literal, a range
`'a'..='z'`, alternatives `A | B`, a variant `E::V(x, _)` or `E::K {
code, shift: true }` (`E::K { .. }` leaves the fields out), a tuple `(a,
0)`, a binding (`n`, `ref n`, `mut n`), `_`, with a guard `x if x > 0`.
The arms must cover every value; a match is an expression. Matching a
reference binds references into it (Rust's default binding modes):
`match &mut s { Shape::Line(n) => *n += 1, _ => {} }` changes the
field. `let PAT = e else { return ..; };` binds or leaves. Matching an
owned local by value moves its parts out.
