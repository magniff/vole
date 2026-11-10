# calc

A calculator: reads lines of integer arithmetic from stdin and prints the
value of each, or what is wrong with it. A tokenizer and a
recursive-descent parser, with enums, `match`, `Result` and `?`.

## Build and run

From this folder (with `volec` on your `PATH`, or `../../target/volec`):

```sh
volec main.vl -o calc
printf '1 + 2 * 3\n(1 + 2) * 3\n100 / (5 - 5)\n2 * (3 + 4\n2 $ 3\n' | ./calc
```

Or run `./calc` and type expressions, one per line (Ctrl-D ends).

## Expected output

```text
7
9
error: division by zero
error: unexpected the end
error: unexpected character '$'
```

`+ - * / %`, unary minus and parentheses are understood, with the usual
precedence; numbers are `i64`. Empty lines are skipped.

## How it works

**Tokens and errors are enums.** A variant may carry data (`Num(i64)`),
and `use Token::{...}` lets the variants be written without `Token::`.
`Token` derives `Clone, Copy` (the parser copies one out of the slice)
and `PartialEq` (it compares one with `Close`):

```tach
#[derive(Clone, Copy, PartialEq)]
enum Token { Num(i64), Plus, Minus, Star, Slash, Percent, Open, Close, End }
enum Error { BadChar(char), Unexpected(Token), DivideByZero }
```

**The tokenizer** walks the line's characters with a `match` on each
one; `'0'..='9'` is a range pattern, and `' ' => continue` skips a blank
from inside the `match`. `chars().peekable()` lets it look at the next
character before taking it, for the digits of a number. A character that
starts no token ends it with an error:

```tach
fn tokenize(text: &str, gpa: Gpa) -> Result<Vec<Token, Gpa>, Error> {
    let mut tokens: Vec<Token, Gpa> = Vec::new_in(gpa);
    let mut chars = text.chars().peekable();
    while let Some(c) = chars.next() {
        ...
            _ => return Err(BadChar(c)),
```

The vector owns its memory and is dropped when it goes out of scope, so
the early `return` frees it; on success it moves out in the `Ok`, and
`evaluate` drops it when it returns. The parser only borrows the tokens:
`struct Parser<'a> { tokens: &'a [Token], at: usize }`.

**The parser** has one method per grammar rule, each returning
`Result<i64, Error>`. `?` returns the first error from every level at
once, so the grammar reads as it would without errors:

```tach
// term: unary (('*' | '/' | '%') unary)*
fn term(&mut self) -> Result<i64, Error> {
    let mut value = self.unary()?;
    loop {
        let op = self.peek();
        match op {
            Star | Slash | Percent => {
                self.at += 1;
                let rhs = self.unary()?;
                value = match op {
                    Star => value * rhs,
                    _ if rhs == 0 => return Err(DivideByZero),
                    Slash => value / rhs,
                    _ => value % rhs,
                };
            }
            _ => return Ok(value),
        }
    }
}
```

`Star | Slash | Percent` is an or-pattern and `_ if rhs == 0` a guard.
(`x / 0` panics, so the check turns a crash into a message.)

**Messages come from `Display` impls.** `impl fmt::Display for Error`
writes the text with `write(f, "..")`, the format function for a
formatter; `{t}` uses `Token`'s own `Display`:

```tach
impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            BadChar(c) => write(f, "unexpected character '{c}'"),
            Unexpected(t) => write(f, "unexpected {t}"),
            DivideByZero => f.write_str("division by zero"),
        }
    }
}
```

**The main loop** reads stdin a line at a time: `read_line` appends the
next line to the String, its `'\n'` included, and returns how many bytes
it read, 0 at the end of the input:

```tach
while io::stdin().read_line(&mut line).unwrap_or(0) > 0 {
    let text = line.trim();
    ...
    line.clear();
}
```

## Language features

- enums with data, `match`, or-patterns, ranges and guards: `volec guide syntax`
- `Result` and `?`: `volec guide conversions`
- `impl Display`, format strings: `volec guide formatting`
- `&mut self` methods, a `Vec` and its drop, a struct holding a borrow: `volec guide memory`
- reading stdin (`read_line`): `volec guide conversions#reading-input`
