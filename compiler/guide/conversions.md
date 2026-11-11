# Conversions and errors

Integer conversions, `From`/`Into`, the `?` operator, and std's
convention for failure: Option means absent, Result means failed.

## Integers

`x as T` converts between any number types (truncating, wrapping or
saturating as Rust's `as` does); `i64::from(x)` widens losslessly
(`From` holds for every widening: `i8 -> i16 -> i32 -> i64`, `u8 -> u16
-> u32 -> u64`, unsigned to a strictly wider signed type).
`u8::try_from(x)` and `x.try_into()` narrow with a check: a
`Result<u8, TryFromIntError>` (`std::num`), `Err` when the value does
not fit.

vole also widens by itself, where rustc says E0308: an `i32` where an
`i64` goes, and two integer operands of different widths join to the
wider (`a_i32 + b_i64` is an `i64`). Code meant to build with rustc too
writes the `from` or the `as`, as the block below does. An index may be
any integer type (rustc's: `usize` only).

## From and Into

`trait From<T> { fn from(x: T) -> Self; }` is std's (Rust's). A type can
implement it for several `T`s, one impl per trait, arguments and type;
`T::from(x)` picks the impl by the type of `x`. Implement `From`, never
`Into`: `x.into()` is `U::from(x)` with `U` the type expected there
(`let y: U = x.into();`). Bounds take arguments: `fn f<T: From<i64>>(n:
i64) -> T { T::from(n) }`.

## The ? operator

`e?` on an `Option<T>` gives the `T`, or returns `None` from the
function. On a `Result<T, E>` it gives the `T`, or returns
`Err(F::from(err))`, `F` the function's error type (`From<E> for E`
holds, so the same type passes). Inside a closure it returns from the
closure. The drops run, as for `return`. `?` on an Option in a function
returning a Result needs the error named: `x.ok_or(AppError::Missing)?`.
Option and Result have Rust's methods (`map`, `and_then`, `ok_or`,
`unwrap_or`, `unwrap_or_else`, `map_err`, `ok`, `err`, `is_some`...).

```vole
use std::num::ParseIntError;

fn total(xs: &[i32]) -> i64 {
    let mut t: i64 = 0;
    for x in xs { t += i64::from(*x); }  // each i32 widened by From
    t
}

#[derive(Debug)]
enum AppError { Parse(ParseIntError), Negative(i64) }

impl From<ParseIntError> for AppError {
    fn from(e: ParseIntError) -> AppError { AppError::Parse(e) }
}

fn checked(s: &str) -> Result<i64, AppError> {
    let n: i64 = s.parse()?;            // an Err returns Err(AppError::from(e))
    if n < 0 { return Err(AppError::Negative(n)); }
    Ok(n)
}

fn half(x: Option<i64>) -> Option<i64> {
    let v = x?;                          // None returns None
    Some(v / 2)
}

fn main() -> Result<(), AppError> {
    let a: i32 = 2000000000;
    let b: i32 = 2000000000;
    let wide = a as i64 + b as i64;
    let c: u32 = 1200;
    let xs = [1i32, 2, 3];
    println("{wide} {}", total(&xs) + i64::from(c));
    println("{:?} {:?} {:?} {}", checked("42"), checked("4x"), checked("-3"), half(Some(8)).unwrap_or(-1) + half(None).unwrap_or(-1));
    match checked("4x") { Err(AppError::Parse(e)) => println("{e}"), _ => {} }
    println("{:?} {:?}", u8::try_from(300i64).is_err(), u8::try_from(checked("7")?));
    Ok(())
}
```
```out
4000000000 1206
Ok(42) Err(Parse(ParseIntError { kind: InvalidDigit })) Err(Negative(-3)) 3
invalid digit found in string
true Ok(7)
```

- `s.parse::<T>()` (or `let n: T = s.parse()?`) gives a `Result<T,
  T::Err>`: `ParseIntError` (its `kind()`: `IntErrorKind::Empty`,
  `InvalidDigit`, `PosOverflow`, `NegOverflow`), `ParseFloatError`,
  `ParseBoolError`.
- `main` returns nothing, an `i32` (its exit code) or a `Result<(), E>`
  with `E: Debug`: an `Err(e)` prints `Error: ` and `{e:?}` on stderr,
  and the program exits with 1.

## Reading input

`std::io::stdin()` reads standard input: `read_line(&mut s)` appends a
line to a String (`Ok(0)` at the end), `lines_in(gpa)` iterates over
them, and `io::read_to_string_in(io::stdin(), gpa)` reads it all
(`guide io`).

```vole
use std::io;

fn main(gpa: Gpa) -> i32 {
    let input = io::read_to_string_in(io::stdin(), gpa).unwrap();
    let mut sum = 0i64;
    for tok in input.split_whitespace() {
        match tok.parse::<i64>() {
            Ok(n) => sum += n,
            Err(e) => println("skipped {tok:?}: {:?}", e.kind()),
        }
    }
    let mut line = String::new_in(gpa);
    let n = io::stdin().read_line(&mut line).unwrap();
    println("{sum} {n}");
    0
}
```
```in
1 2 x 3
```
```out
skipped "x": InvalidDigit
6 0
```
