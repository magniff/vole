# text

## str and String

`str` is UTF-8 text, Rust's: `&str` borrows it (a string literal is a
`&'static str`), and `String<A>` owns its text, on an allocator:
`String::new_in(gpa)`, `String::from_in("x", gpa)`, `s.push_str("..")`,
`s.push(c)` (a `char`), `format_in("..", args, gpa)`, `x.to_string_in(gpa)`.
`&s` of a String goes where a `&str` does (Deref), and a String has its
`str`'s methods. The methods are Rust's, and what they return borrows
the text: `len` (bytes), `chars()` (`.rev()`), `char_indices()`,
`bytes()`, `lines()`, `split(p)`, `splitn(n, p)`, `split_once(p)`,
`rsplit_once`, `split_whitespace()`, `trim()` (and `_start`, `_end`,
`_matches`), `strip_prefix(p)`, `starts_with(p)`, `ends_with`,
`contains`, `find(p)` (an `Option<usize>`, a byte index), `rfind`,
`matches(p)`, `parse::<T>()` (numbers, `bool`), `width()` (terminal
columns), `graphemes(true)`. A pattern `p` is a `&str`, a `char` or a
closure `|c: char| ..`. What allocates takes an allocator, Rust's name
with `_in`: `to_uppercase_in(gpa)`, `to_lowercase_in`,
`to_ascii_uppercase_in`, `replace_in(a, b, gpa)`, `repeat_in(n, gpa)`,
`to_string_in(gpa)`, `to_owned_in(gpa)`, `.collect_in(gpa)`; the Rust
form is `alloc.no_in`, which names the `_in` one (`volec fix --only
alloc` writes it). Bytes become text checked: `std::str::from_utf8(b)`
(a `Result<&str, _>`), `String::from_utf8(v)` (a `Vec<u8, A>`),
`String::from_utf8_lossy_in(b, gpa)`; back: `s.as_bytes()`,
`s.into_bytes()`. A byte slice has `starts_with` and `ends_with` too:
`b"name.vl".ends_with(b".vl")`.

```vole
fn initials(name: &str, gpa: Gpa) -> String<Gpa> {
    let mut out = String::new_in(gpa);
    for w in name.split_whitespace() {
        out.push(w.chars().next().unwrap());
    }
    out
}

fn main(gpa: Gpa) -> i32 {
    let line = "  ada lovelace, 1815 ";
    let (name, year) = line.trim().split_once(", ").unwrap();
    let born = year.parse::<i64>().unwrap();
    let up = name.to_uppercase_in(gpa);
    let short = initials(name, gpa);
    println("{up} {short} {} {}", 2026 - born, name.contains('l'));
    let parts: Vec<&str, Gpa> = "a,b,,c".split(',').collect_in(gpa);
    println("{parts:?} {}", parts.len());
    0
}
```
```out
ADA LOVELACE al 211 true
["a", "b", "", "c"] 4
```

## String constants

| form | what it is |
|---|---|
| `const X: &str = "...";` | text: each use is the literal |
| `const X: &[u8] = b"...";` | bytes; `include_str("f.wgsl")` is a file's text, a `&'static str` |
| `static X: &str = "...";` | text in a place, one address for every use, as any static |
| `static X: [&str; N] = ["a", "b"];` | an array of them (`const` too): `X[i]` is one, `&X[..]` the slice |

What turns one form into another:

| you have | you want | write |
|---|---|---|
| a `&str` | `&[u8]` | `s.as_bytes()` |
| `&[u8]` | `&str` | `std::str::from_utf8(b)?`: checked, a `Result` |
| `Vec<T, A>` | `&[T]` | `&v`, `v.as_slice()`, a borrow, no copy; a `String`: `s.as_str()` |
| a format string | its text | `format_in("..", args, gpa)`, a `String<A>`; `x.to_string_in(gpa)` for one value |
| a slice | appended | `v.extend_from_slice(s)` to a `Vec`; `push_str(s)` to a `String` |

`print`, `println` and `eprintln` take a format literal and its
arguments, any `T: Display`, with no allocator; `panic("bad {x}")`
formats its message the same way (`assert(c, "msg")` and `assert_eq(a,
b, "msg")` take a plain message, no arguments yet).

```vole
const SHADER: &str = "@compute @workgroup_size(1)\nfn main() {}\n";
const NAME: &str = "vole";
static DAYS: [&str; 3] = ["mon", "tue", "wed"];

fn main(gpa: Gpa) {
    let bytes: &[u8] = NAME.as_bytes();
    let text = std::str::from_utf8(SHADER.as_bytes()).unwrap(); // checked
    let mut v: Vec<u8, Gpa> = Vec::new_in(gpa);
    v.extend_from_slice(NAME.as_bytes());
    v.extend_from_slice(DAYS[1].as_bytes());
    let msg = format_in("{NAME}: {} days, {} bytes", DAYS.len(), v.len(), gpa); // a String
    println("{}", msg);
    println("{} {} {}", bytes.len(), text.lines().count(), DAYS[..].len());
    let s = String::from_utf8(v).unwrap();
    if s.len() != 7 {
        panic("{}", msg);
    }
}
```
```out
vole: 3 days, 7 bytes
4 2 3
```

## Numbers as text without an allocator

`format_in("{v:.2}", gpa)` allocates a `String`; a loop that writes a
number every frame (a UI's label) writes it into a stack buffer instead,
through `std::fmt::Write`, Rust's: a type with `write_str` takes
`write(&mut w, "..", args)`, and the formatting itself allocates
nothing. `{:.0}` rounds a tie to the even digit (`2.5` is `2`), as
Rust's.

```vole
use std::fmt::{self, Write};

// A label's text in a stack buffer: no allocator.
struct Label { buf: [u8; 32], len: usize }

impl Write for Label {
    fn write_str(&mut self, s: &str) -> fmt::Result {
        let b = s.as_bytes();
        if self.len + b.len() > 32 { return Err(fmt::Error); }
        self.buf[self.len..self.len + b.len()].copy_from_slice(b);
        self.len += b.len();
        Ok(())
    }
}

impl Label {
    fn as_str(&self) -> &str { std::str::from_utf8(&self.buf[..self.len]).unwrap() }
}

fn main() {
    let mut l = Label { buf: [0; 32], len: 0 };
    write(&mut l, "{:.2} {:.0} {}", 3.14159, 2.5, -42).unwrap();
    println("{}", l.as_str());
}
```
```out
3.14 2 -42
```
