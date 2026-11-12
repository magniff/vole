# Appendix A: keywords, operators and attributes

A page to keep open while you write code: the words, symbols and
attributes of vole, each with a line on what it means and the chapter
that teaches it. It is a reminder, not a grammar. For the exact rules,
see [docs/grammar.md](../docs/grammar.md) and `volec guide syntax`.

## Keywords

These words are reserved: you can't use them as names.

| keyword | meaning | chapter |
|---|---|---|
| `as` | converts a number, `bool` or fieldless enum (`x as i32`), a pointer, or a distinct type | 3, 15 |
| `break` | leaves a loop, optionally with a value or a label: `break n`, `break 'outer` | 3 |
| `const` | a constant item: `const MAX: i64 = 100;` | 3 |
| `continue` | starts the next round of a loop: `continue 'outer` | 3 |
| `else` | the other branch of `if`; also in `let ... else` and a contract's message | 3, 5 |
| `enum` | a type whose value is one of several variants | 5 |
| `extern` | a C function or block of them: `extern "C" { ... }` | 15 |
| `false`, `true` | the two `bool` values | 3 |
| `fn` | a function or method | 3 |
| `for` | loops over a range, a list or an iterator: `for x in v` | 3, 10 |
| `if` | a condition; an expression, so it has a value | 3 |
| `impl` | methods for a type, or a trait for a type: `impl Drop for T` | 5, 9 |
| `import` | a C header: `import "stdio.h" as c;` | 15 |
| `in` | the `in` of a `for` loop | 3 |
| `let` | a variable; `let mut` for one that can change | 3 |
| `loop` | repeats until a `break` | 3 |
| `match` | picks an arm by pattern | 5 |
| `mod` | a module: `mod util;` loads `util.vl` | 11 |
| `move` | a closure that takes what it captures: `move \|\| ...` | 10 |
| `mut` | marks what may change: `let mut x`, `&mut x`, `&mut self` | 3, 4 |
| `pub` | makes an item visible outside its module | 11 |
| `return` | leaves the function, with a value | 3 |
| `static` | a value that lives as long as the program; a `static mut` can change, and using one is `unsafe` | 3, 14 |
| `struct` | a type with named fields | 5 |
| `trait` | a set of methods types can provide | 9 |
| `type` | an alias, or a distinct type: `type Id = distinct i64;` | `guide types` |
| `union` | a C-style union, read only in `unsafe` code | 15 |
| `unsafe` | a block or function allowed to do what the compiler can't check | 15 |
| `use` | imports a name: `use std::collections::HashMap;` | 2, 11 |
| `where` | bounds written after a signature: `where T: Ord` | 9 |
| `while` | loops while a condition holds; `while let` while a pattern fits | 3, 5 |

`dyn` is reserved too, and is an error: vole has no trait objects.
`ref` (in a pattern, borrow instead of move) is there as in Rust.

### Words that are special in one place

These are ordinary names everywhere else, so you can still have a
variable called `result` or `debug`:

| word | special where | meaning | chapter |
|---|---|---|---|
| `self` | a method's first parameter | the value the method is called on | 4, 5 |
| `Self` | inside an `impl` or a trait | the type being implemented | 5, 9 |
| `crate`, `super` | at the start of a path | this program's root module; the parent module | 11 |
| `requires`, `ensures` | between a function's signature and its body | what the function needs, and what it promises | 6, 13 |
| `result`, `old` | in an `ensures` | the returned value; a value as it was at entry: `old(v.len())` | 13 |
| `debug` | before `requires`, `ensures` or `invariant` | checked only by `volec test` and `--debug-contracts` | 13 |
| `distinct` | after `type X =` | a new type with another type's representation | `guide types` |
| `invariant` | after a type | a condition its values keep | docs/grammar.md |

## Operators

### Arithmetic, bits and comparison

| operator | meaning |
|---|---|
| `+ - * /` | arithmetic; an integer overflow stops a debug build and wraps in an optimized one (chapter 3); an integer divided by zero panics |
| `%` | remainder, with the sign of the left side; `x % 0` panics |
| `-x` | negation |
| `& \| ^` | bitwise and, or, xor (on integers) |
| `<< >>` | shifts; `>>` keeps the sign of a signed integer |
| `== !=` | equal, not equal: numbers, `bool`, text, tuples, arrays; structs and enums with `#[derive(PartialEq)]` |
| `< <= > >=` | ordering; they don't chain (`a < b < c` is an error) |
| `&& \|\|` | `bool` and, or; the right side runs only if needed |
| `!x` | `bool` not; on an integer, bitwise not |

There's no `**` (power), no `++` or `--`, and no `?:` (an `if` is an
expression).

### Assignment

`=` assigns, and `+= -= *= /= %= &= |= ^= <<= >>=` combine an operator
with assignment. An assignment's value is `()`, so `a = b = 1` is not
allowed.

### Everything else

| operator | meaning | chapter |
|---|---|---|
| `a..b`, `a..=b` | a range, excluding or including `b`: `for i in 0..n`; a slice: `v[1..3]` | 3, 7 |
| `a[i]` | an element of an array, a slice or a `Vec`; checked | 3, 7 |
| `x.f`, `t.0` | a field; a tuple's part | 3, 5 |
| `x.m()` | a method call | 5 |
| `T::f` | an associated function or a variant: `Player::new()`, `Option::None` | 5 |
| `f::<T>()` | a function told its type (the *turbofish*): `s.parse::<i64>()` | 2 |
| `e?` | the value in an `Ok` or `Some`; else return the error or `None` | 6 |
| `&x`, `&mut x` | borrows `x`: a reference to read it, or to change it | 4 |
| `*r` | what a reference points to; through a raw pointer, in `unsafe` code only | 4, 15 |
| `\|x\| e` | a closure | 10 |
| `=>` | separates a `match` arm's pattern from its value | 5 |
| `->` | a function's result type | 3 |

### Precedence

From the loosest to the tightest. Operators on one line bind equally
and group left to right, except assignment, which groups right to left.

| operators | note |
|---|---|
| `=` `+=` `-=` ... | assignment |
| `\|\|` | |
| `&&` | |
| `==` `!=` `<` `>` `<=` `>=` | not chained |
| `\|`, then `^`, then `&` | `a \| b == c` is `(a \| b) == c` |
| `<<` `>>` | |
| `+` `-` | |
| `*` `/` `%` | |
| `as` | `-x as f64` is `(-x) as f64`; `a * b as f64` is `a * (b as f64)` |
| prefix `-` `!` `*` `&` `&mut` | |
| `f()` `a[i]` `x.f` `x.0` `x.m()` `e?` | |

Note that `&`, `|` and `^` bind looser than `+` and `<<` but tighter
than `==`. That's the other way round from C, where `a & b == c` means
`a & (b == c)`. When in doubt, add parentheses.

Here's a program that exercises the table:

```vole
fn main() {
    let a = 6;
    let b = 4;
    println("{} {} {} {} {}", a + b * 2, (a + b) * 2, a - b - 1, a / b, a % b);
    println("{} {} {} {} {} {}", a & b, a | b, a ^ b, !a, 1 << 4, -16 >> 2);
    println("{} {} {}", a | b == 6, a + 1 << 1, -a as f64 / 4.0);
    println("{} {} {}", a > b && b > 0 || false, !(a == b), a != b);
    let mut x = 1;
    x += 2;
    x *= 5;
    x -= 1;
    x <<= 1;
    x %= 10;
    println("{x}");
}
```

```out
14 20 1 1 2
4 6 2 -7 16 -4
true 14 -1.5
true true true
8
```

## Literals

| literal | type | example |
|---|---|---|
| integer | `i32`, or what the context needs | `42`, `1_000_000`, `0xff`, `0o17`, `0b1010` |
| integer with a suffix | the suffix's | `255u8`, `7i32`, `1_000_u64` |
| float | `f64`, or what the context needs | `2.5`, `1e10`, `1.5e-3` |
| float with a suffix | `f32` | `2.5f32` |
| `bool` | `bool` | `true`, `false` |
| character | `char` | `'a'`, `'\n'`, `'\u{e9}'`, `'\''` |
| byte | `u8` | `b'a'`, `b'\n'`, `b'\x41'` |
| string | `&str` | `"hello\n"` |
| byte string | `&[u8; N]`, a reference to an array of its bytes | `b"GET "` |
| C string | `*const u8`, NUL-terminated | `c"for C"` |
| format string | a string literal, the first argument of `println`, `format_in`, `write`, `panic` | `"{name} is {age:>3}"` |
| unit | `()` | `()` |

Strings take the escapes `\n`, `\t`, `\r`, `\0`, `\\`, `\"`, `\'`,
`\xNN` (a byte) and `\u{NNNN}` (a Unicode character, as UTF-8). A
backslash at the end of a line continues the string on the next line,
without the line break and the next line's indentation.

A string literal is a `&str`: text that lives as long as the program
(a `&'static str`), with the text methods (`trim`, `split`, `find`,
...). `b"..."` is the same characters as bytes. Chapter 7 explains the
difference.

In a format string, `{name}` is replaced by a variable's text and `{}`
by the next argument's (an expression is an argument after the string,
never inside the braces), and a *spec* after a colon shapes it: `{x:>8}` (right-aligned in 8 columns), `{x:<8}`
(left), `{x:08}` (zero-padded), `{x:.2}` (2 decimals), `{x:x}` (hex),
`{x:b}` (binary), `{v:?}` (the Debug form). `{{` and `}}` are literal braces. Chapter 7 has more.

## Attributes

An attribute is written `#[name]` or `#[name(...)]` on the line before
an item.

| attribute | on | meaning | chapter |
|---|---|---|---|
| `#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Default)]` | struct, enum | generates those traits from the fields | 5, 9 |
| `#[repr(u8)]` (or another integer) | enum | stores the enum as that integer; variants can have `= N` | 5 |
| `#[repr(C)]` | struct, union | C's layout, for passing to C | 15 |
| `#[test]` | function | a test, run by `volec test` | 13 |
| `#[property]` | function | a property test, run with generated inputs | 13 |
| `#[fuzz]` | function | a fuzz target | 13 |
| `#[cfg(test)]` | item | compiled only for `volec test` | 13 |
| `#[pure]` | function | checked: no allocation, I/O or globals (it may still panic) | 12 |
| `#[no_alloc]`, `#[no_io]`, `#[no_panic]` | function | checked: the function never allocates, does I/O, or panics | 12 |
| `#[effects(io, global, ...)]` | function | checked: the function does at most these | 12 |
| `#[inline]`, `#[inline(never)]` | function | asks the optimizer to inline it, or not to | 16 |
| `#[cold]` | function | rarely called: the optimizer keeps it out of the way | `guide syntax` |
| `#[target_feature(...)]`, `#[multiversion(...)]` | function | compiled for particular CPU features | 16 |
| `#[thread_local]` | `static mut` | one copy per thread | 14 |
| `#[deprecated(note = "...")]` | item | each use gets a warning with the note | `guide syntax` |
| `#[link(...)]`, `#[link_name = "..."]` | `extern` block, function | which C library to link, and a function's C name | 15 |

Until 0.26 you could see `#[sealed]` before a struct, which made its
fields private to its module; every struct's fields are now, so the
attribute only gets a warning (`volec fix --only obsolete-attr`
deletes it).

## The prelude

These names are available in every file without a `use`:

- **Option and Result:** `Option`, `Some`, `None`, `Result`, `Ok`, `Err`.
- **Printing and formatting:** `print`, `println`, `eprint`,
  `eprintln`, `format_in`, `write`, `writeln`.
- **Text and containers:** `String`, `Vec`, `Box`, and `ToStringIn`,
  the trait behind `x.to_string_in(gpa)`.
- **Memory:** `Gpa`, `Drop`, `drop`.
- **Traits:** `Clone`, `Copy`, `PartialEq`, `Eq`, `PartialOrd`, `Ord`,
  `Default`, `From`, `Into`, `TryFrom`, `TryInto`, `AsRef`, `AsMut`,
  `Iterator`, `IntoIterator`, `DoubleEndedIterator`,
  `ExactSizeIterator`, `Extend`.
- **Checks:** `panic`, `unreachable`, `todo`, `unimplemented`, `assert`,
  `assert_eq`, `assert_ne`, `debug_assert`.

The built-in types (`i32`, `f64`, `bool`, `char`, `str` and the rest)
need no import either. Everything else in the standard library is
imported by name, `use std::collections::HashMap;`, or written as a
path, `std::io::stdin()`. Your
own items hide prelude names of the same spelling. `volec query items
std` lists the whole library.
