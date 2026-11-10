# formatting

Formatted text in vole: format strings and every part of a spec
(width, alignment, zero padding, precision, hex, binary, characters,
Debug), `Display` and `Debug` written by hand and derived, and the ways
to send formatted text somewhere (`println`, `eprintln`, `format_in`,
`write`). The program prints a spec cheat sheet, an aligned inventory
table, some Debug views and a hex dump.

## Build and run

From this folder (with `volec` on your `PATH`, or `../../target/volec`):

```sh
volec main.vl -o formatting && ./formatting
./formatting 2>/dev/null     # the report alone, without the warnings on stderr
```

## Expected output

On stdout:

```text
== format specs
{n}           [42]         Display
{n:>8}        [      42]   right-aligned: the default for numbers
{n:<8}        [42      ]   left-aligned
{n:08}        [00000042]   zero-padded
{n:x} {n:X}   [2a 2A]      hex
{n:08b}       [00101010]   binary, zero-padded
{x}           [3.14159]    the shortest text that reads back
{x:.2}        [3.14]       two decimals
{x:>9.3}      [    3.142]  width and precision
{name:>9}     [     vole]  text goes left by default
{name:?}      ["vole"]     Debug: quoted and escaped
{}, 'A'       [A]          a char
{}, n * 2 + 1 [85]         the next argument
{{ and }} in a format string are literal braces: {n}
== inventory
sku    item               qty      price        value
-----------------------------------------------------
#7     hammer              12     $15.99      $191.88
#42    socket set           3     $89.50      $268.50
#108   coffee beans        40     $12.75      $510.00
#9     rubber duck        250      $1.99      $497.50
#1500  workbench            2    $649.00    $1,298.00
-----------------------------------------------------
total                                       $2,765.88
== debug
Item { sku: SKU-0007, name: "hammer", category: Tools, qty: 12, price: Money(1599) }
Food(180) SKU-0108 Money(1275)
[12, 3, 40, 250, 2] Some(2) "tab\there"
== hex dump
0000  76 6f 6c 65 20 66 6f 72  |vole for|
0008  6d 61 74 73 09 62 79 74  |mats.byt|
0010  65 73 0a                 |es.|
```

On stderr:

```text
warning: socket set (SKU-0042) is low: 3 left
warning: workbench (SKU-1500) is low: 2 left
```

## How it works

**Format strings.** The first argument of `println` and the other
printing calls is a format string, Rust's `format!` without the `!`:
`{}` takes the next argument, `{name}` a local or a constant, `{0}` the
first argument; each argument's type has `Display` (with `:?`, `Debug`).
`{{` and `}}` are literal braces. The spec after `:` is Rust's,
`[[fill]align][+][#][0][width][.precision][type]`:

| spec | meaning |
|---|---|
| `{n:>8}` `{n:<8}` | width 8, right or left aligned (numbers go right, text left, by default) |
| `{n:08}` | zero-padded to 8 |
| `{n:x}` `{n:X}` `{n:b}` | hex, upper-case hex, binary (`{n:08b}`: padded) |
| `{x:.2}` `{x:>9.3}` | a float with 2 decimals; width 9 with 3 decimals |
| `{v:?}` | Debug |
| `{s:*^9}` `{n:+}` `{n:#x}` | a fill character and centring, a sign, `0x` |

A float without a precision prints the shortest text that reads back as
the same value (`3.14159`, `0.1`). A `u8` prints as a number; `b as
char` prints its character.

**Where a format string goes.** `println`, `eprintln` (stderr),
`format_in` (returns a new `String`, dropped when its owner's scope
ends; the allocator comes last), `write(&mut s, ..)` (appends to a
`String`, or to anything with `std::fmt::Write`) and `write(f, ..)`
inside a Display impl. The cheat sheet passes `format_in("...", args,
gpa)` results to a helper that takes them; the hex dump builds each line
in a `String`:

```tach
let mut line = format_in("{:04x}  ", n * 8, gpa); // format_in: a new String to keep
for i in 0..8 {
    if i < chunk.len() { write(&mut line, "{:02x} ", chunk[i]).unwrap(); }
    else { line.push_str("   "); }
}
```

**Display by hand.** `Display` has one method, Rust's `fmt(&self, f:
&mut Formatter) -> fmt::Result`, which writes through the formatter
with `write(f, "..", args)`, `f.write_str` and `f.write_char`. `Money`
prints cents as dollars with thousands separators, using a zero-padded
spec for each group:

```tach
impl Display for Money {
    fn fmt(&self, f: &mut Formatter) -> fmt::Result {
        let mut text = Text { buf: [0; 32], len: 0 };
        ...
        write(&mut text, "{}", dollars / group)?;
        while group > 1 {
            group /= 1000;
            write(&mut text, ",{:03}", dollars / group % 1000)?;
        }
        write(&mut text, ".{:02}", c % 100)?;
        f.pad(text.as_str())
    }
}
```

As in Rust, a width in the caller's spec (`{value:>12}`) is the impl's
to apply: `f.pad(text)` writes a text with the spec's width and
alignment. So `Money` builds its text first, in `Text`, a 32-byte buffer
on the stack that implements `std::fmt::Write` (one method,
`write_str`): no allocator is needed to format.

**Debug by hand and derived.** `Debug` is the same method in another
trait. `Sku` prints `#42` for people and `SKU-0042` for programmers.
`#[derive(Debug)]` writes Rust's text for a struct or enum, calling the
fields' own Debug impls, which is how `Item`'s Debug shows
`sku: SKU-0007` and `price: Money(1599)`:

```tach
#[derive(Debug)]
enum Category { Tools, Food(i64), Toys }

#[derive(Debug)]
struct Item { sku: Sku, name: &'static str, category: Category, qty: i64, price: Money }
```

std has Debug for the numbers, `&str` (quoted and escaped:
`"tab\there"`), `Vec` (`[12, 3, 40, 250, 2]`), `Option`, `Result` and
`HashMap`.

**A table.** Headers and cells share the same widths, and text columns
are left-aligned while numbers and money are right-aligned:

```tach
println("{:<6} {:<16} {:>5} {:>10} {:>12}", "sku", "item", "qty", "price", "value");
...
println("{:<6} {:<16} {:>5} {:>10} {value:>12}", it.sku, it.name, it.qty, it.price);
```

**stdout and stderr.** The low-stock warnings go through `eprintln`, so
`./formatting 2>/dev/null` leaves the report alone.

## Language features

- format strings, specs, `Display`, `Debug`, `format_in`, `write`, `eprintln`, `#[derive(Debug)]`: `volec guide formatting`
- `String`, `Vec`, drops: `volec guide std`, `volec guide memory`
- struct field shorthand (`Item { sku: Sku { id }, name, ... }`): `volec guide syntax`
- formatting without an allocator (`std::fmt::Write`): `volec guide text`

## Going further

- `{x:e}` and `{x:E}` print a float in exponent notation (`volec guide
  formatting`).
- Display has no derive; write the text you want.
