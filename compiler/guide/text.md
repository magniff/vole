# text

## str and String

`str` is UTF-8 text, a view (`&str` is `str`, as `&[T]` is `[T]`); a
string literal is one where a `str` goes, and a `str` goes where a `[u8]`
does, for free. `String` owns its text, on an allocator:
`String::new_in(gpa)`, `String::from_in("x", gpa)`, `s.push_str("..")`,
`s.push(c)` (a code point, a `u32`: vole has no `char` yet),
`s.push_fmt(f"{x}")`, `to_string_in(f"..", gpa)`. A String has its
`str`'s methods (`s.trim()`), and `&s` goes where a `str` or `[u8]` does.
The methods are Rust's, and what they return views the text: `len`,
`chars()` (code points; `.rev()`), `char_indices()`, `bytes()`,
`lines()`, `split(p)`, `splitn(n, p)`, `split_once(p)`, `rsplit_once`,
`split_whitespace()`, `trim()` (and `_start`, `_end`, `_matches`),
`strip_prefix(p)`, `starts_with(p)`, `ends_with`, `contains`, `find(p)`
(an `Option<i64>`, a byte index), `rfind`, `matches(p)`, `parse::<T>()`
(numbers, `bool`), `width()` (terminal columns), `graphemes(true)`. A
pattern `p` is a `str` (`", "`), a byte (`','`) or a code point (`0x4e16
as u32`). What allocates takes an allocator, Rust's name with `_in`:
`to_uppercase_in(gpa)`, `to_lowercase_in`, `replace_in(a, b, gpa)`,
`repeat_in(n, gpa)`, `to_string_in(gpa)`, `.collect_in(gpa)`; the Rust
forms are errors naming them. Bytes become a `str` checked:
`str::from_utf8(b)?`, `String::from_utf8(v)?` (a `Vec<u8>`),
`String::from_buf(b)?`, `String::from_utf8_lossy_in(b, gpa)`; back:
`s.as_bytes()`, `s.into_bytes()`, `s.into_buf()`.

```vole
fn initials(name: str, gpa: Gpa) -> String {
    var out = String::new_in(gpa);
    for w in name.split_whitespace() {
        out.push(w.chars().next().unwrap());
    }
    out
}

fn main(gpa: Gpa) -> i32 {
    let line: str = "  ada lovelace, 1815 ";
    let (name, year) = line.trim().split_once(", ").unwrap();
    let born = year.parse::<i64>().unwrap();
    let up = name.to_uppercase_in(gpa);
    let short = initials(name, gpa);
    println(f"{up} {short} {2026 - born} {name.contains('l')}");
    let parts: Vec<str> = "a,b,,c".split(',').collect_in(gpa);
    println(f"{parts:?} {parts.len()}");
    0
}
```
```out
ADA LOVELACE al 211 true
["a", "b", "", "c"] 4
```

## String constants

String constants come in four forms:

| form | what it is |
|---|---|
| `const X: str = "...";` | text, a value: each use is the literal (0.25.4); a text block too |
| `const X: [u8] = "...";` | bytes; a text block (`"""`, `guide syntax#lexical`), `include_str("f.wgsl")` and `include_bytes("f.bin")` too |
| `static X: str = "...";` | text in a place, one address for every use, as any static |
| `static X: [str; N] = ["a", "b"];` | an array of them (`const` too): `X[i]` is one, `X[..]` the slice; `[str]`, without the length, is refused |

What turns one form into another:

| you have | you want | write |
|---|---|---|
| a `str` (a literal, a static) | `[u8]` | nothing: a `str` goes where a `[u8]` does; `s.as_bytes()` says so |
| `[u8]` | `str` | `str::from_utf8(b)?`: checked, a `Result` |
| `Vec<T>`, `Buf` | `[T]`, `[u8]` | `v.as_slice()`, a view, no copy; a `String`: `s.as_str()` |
| an f-string | its text | `format_in(f"..", gpa)`, a `Buf` (`.as_slice()` views it); `to_string_in(f"..", gpa)`, a `String` |
| a slice | appended | `v.extend_from_slice(s)` to a `Vec`; `push_str(s)` to a `Buf` or `String` |

`print`, `println` and `eprintln` take any `T: Display`: an f-string,
a number, a `str`, a `[u8]`, with no allocator. `panic(msg)` and
`assert`'s message take a `[u8]` (a `str` too), not an f-string:
`panic(format_in(f"bad {x}", gpa).as_slice())`; with no `gpa` at hand,
`eprintln(f"bad {x}")` and `std::process::exit(1)`.

```vole
const SHADER: [u8] = """
    @compute @workgroup_size(1)
    fn main() {}
    """;
const NAME: str = "vole";
static DAYS: [str; 3] = ["mon", "tue", "wed"];

fn main(gpa: Gpa) {
    let bytes: [u8] = NAME; // a str goes where [u8] does
    let text: str = str::from_utf8(SHADER).unwrap(); // bytes to str: checked
    var v: Vec<u8> = Vec::new_in(gpa);
    v.extend_from_slice(NAME.as_bytes());
    v.extend_from_slice(DAYS[1]);
    let msg = format_in(f"{NAME}: {DAYS.len()} days, {v.len()} bytes", gpa); // a Buf
    println(msg.as_slice());
    println(f"{bytes.len} {text.lines().count()} {DAYS[..].len()}");
    if v.len() != 7 {
        panic(msg.as_slice()); // [u8], not an f-string
    }
}
```
```out
vole: 3 days, 7 bytes
4 2 3
```

## Numbers as text without an allocator

`format_in(f"{v:.2}", gpa)` allocates a `Buf`; a loop that writes a
number every frame (a UI's label) writes it into a stack array instead.
`std::num::fmt_f64(v, decimals, &out)` (0.25.4) writes `{v:.N}`'s text
byte for byte at the end of a `[u8; 32]` and returns where it starts:
the exact value rounded to the nearest, a tie to the even digit (`2.5`
to 0 decimals is `2`, as C's `%.0f` and Rust's `{:.0}`), `-0.00`,
`NaN`, `inf`; `decimals` from 0 to `FIXED_DECIMALS_MAX` (20); a text
longer than 32 bytes is `{v:e}`'s. An `f32` is `fmt_f64(x as f64, ..)`.
`fmt_i64(v, &out)` and `fmt_u64` do the same for integers into a
`[u8; 20]` (`guide formatting#numbers`).

```vole
use std::num::{fmt_f64, fmt_i64};

fn main() {
    var out: [u8; 32] = [0; 32];
    let at = fmt_f64(3.14159, 2, &out);
    println(out[at..32]);
    let at2 = fmt_f64(-0.5, 0, &out);
    println(out[at2..32]);
    var digits: [u8; 20] = [0; 20];
    let i = fmt_i64(-42, &digits);
    println(digits[i..20]);
}
```
```out
3.14
-0
-42
```
