# Formatting and derive

Format strings, the `Display` and `Debug` traits, the `print` family,
and `#[derive]`.

## Format strings

Rust's `format!` family without the `!` (vole has no macros: `println!`
is an error naming `println`): a literal that is the first argument of
`print`, `println`, `eprint`, `eprintln` (stderr), `format_in(..,
gpa)` (a new `String<A>` on allocator `gpa`, the allocator last),
`format_args`, `write(w, ..)` and `writeln` (into a `fmt::Write`, a
Formatter inside a Display impl), `panic` or `assert`'s message is a
format string, its arguments after it: `println("{} has {n:>4}",
p.name)`. The grammar and the output are Rust's std::fmt.

- `{}` takes the next argument, `{0}` argument 0, `{name}` a named
  argument (`name = expr`) or a local, a parameter, a `const` or a
  `static` in scope; `{{` and `}}` are braces. An expression in a hole,
  `{p.x}`, is `format.expr-hole`: write `{}` and pass `p.x` (its `try:`
  does).
- Each argument is evaluated once, left to right, before anything is
  written; one no hole takes, or a hole with no argument, is
  `format.args`.
- Floats print the shortest text that reads back as the same value
  (`2.5`, `0.1`), byte for byte as Rust prints them (#numbers).
- Passed straight to the printing functions, a format string is written
  in place: no allocation, at every `-O` level.
- `format_args("..", args)` is the formatted text as a value, for a
  function of your own taking `T: Display`.
- MVS's f-strings, `f"{p.x + 1}"`, are `syntax.fstring`.

### The spec

`{name:spec}`, `spec = [[fill]align][+][#][0][width][.precision][type]`:
`<` `^` `>` align (numbers go right by default, text left) with any fill
character (`{s:*^9}`), `+` signs a number, `#` writes `0x`/`0o`/`0b`
(and `0` pads after them), `0` pads a number with zeros after its sign,
the width and the precision are digits (precision also `*`: the next
argument), `.N` gives a float N decimals and cuts text to N; the type is
`?` Debug (`x?`, `X?` with hex numbers; `#?` over several lines),
`x`/`X` hex, `o` octal, `b` binary, `e`/`E` an exponent (`1.5e3`).
A width from an argument (`w$`, `1$`) is not read yet.

```vole
fn next(c: &mut i64) -> i64 {
    *c += 1;
    *c
}

fn main(gpa: Gpa) -> i32 {
    let n = 42;
    let s = "hi";
    println("[{n:^8}] [{n:+}] [{n:#x}] [{n:o}] [{n:#010x}] [{s:*^7}]");
    println("[{:>5}] [{:.*}] [{0:?}] [{:e}]", 9, 2, 1.25, 1500.0);
    let name = "vole";
    let x = 2.5;
    println("{name} has {n} and {x}");
    println("[{n:>6}] [{n:<6}] [{n:06}] [{n:x}] [{n:X}] [{n:b}]");
    println("[{name:>9}] [{x:.3}] [{}] {{braces}} {}", 'A', n * 2 + 1);
    let t = format_in("{n}-{}", n + 1, gpa); // a String, dropped at the end
    eprintln("to stderr: {}", t);
    let mut c = 0;
    println("{} {}", next(&mut c), next(&mut c)); // left to right: 1, then 2
    println("{:#?}", (1, "a"));
    0
}
```
```out
[   42   ] [+42] [0x2a] [52] [0x0000002a] [**hi***]
[    9] [1.25] [9] [1.5e3]
vole has 42 and 2.5
[    42] [42    ] [000042] [2a] [2A] [101010]
[     vole] [2.500] [A] {braces} 85
to stderr: 42-43
1 2
(
    1,
    "a",
)
```

Printing writes through a static 4 KB buffer, one `write` per call, no
heap.

## Numbers

A float's `{}`, `{:?}`, `{:e}` and `{:E}` are Rust's text, byte for
byte: the shortest digits that read back as the value (Schubfach), `{}`
never with an exponent, `{:?}` with one below 1e-4 and from 1e16 on.
`s.parse::<f64>()` reads text back as Rust's does (`-1.5e3`, `.5`,
`inf`, `NaN`; no spaces; correctly rounded), and `to_bits`,
`from_bits` give the IEEE bits. Text without an allocator: `guide
text#numbers-as-text-without-an-allocator`.

```vole
fn main() -> i32 {
    let x = "0.1".parse::<f64>().unwrap() + "2e-1".parse::<f64>().unwrap();
    println("{x} {x:?} {x:e} {:?} {} {}", 1e16, 1e-7, 0.1f32);
    println("{:?} {} {:x}", "-255".parse::<i64>(), "1,5".parse::<f64>().is_err(), 1.5f64.to_bits());
    println("{} {:?} {}", f64::from_bits(0x3ff8000000000000), "inf".parse::<f64>(), b'A' as char);
    0
}
```
```out
0.30000000000000004 0.30000000000000004 3.0000000000000004e-1 1e16 0.0000001 0.1
Ok(-255) true 3ff8000000000000
1.5 Ok(inf) A
```

## Display and Debug

Rust's traits, `std::fmt::Display` and `std::fmt::Debug`:

```text
trait Display { fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result; }
trait Debug { fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result; }
```

Write `impl Display for T` (no derive: the text is yours) with `write(f,
"..", args)`, or `f.write_str(s)`. Display is in std for the numbers,
`char`, `str`, `String` and std's errors; Debug for those (text quoted
and escaped: `"a\n"`), slices, arrays, `Vec<T, A>`, tuples, `Option`,
`Result` and `HashMap` (`[1, 2]`, `Some(5)`, `{1: 2}`).

```vole
use std::fmt;

#[derive(Debug, Clone, Copy)]
struct Point { x: i64, y: i64 }

#[derive(Debug)]
enum Shape { Circle(i64), Rect(Point, Point), Line { from: Point, len: i64 }, Empty }

impl fmt::Display for Point {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write(f, "({}, {})", self.x, self.y)
    }
}

fn main(gpa: Gpa) -> i32 {
    let p = Point { x: 1, y: 2 };
    let mut q = p.clone();
    q.x = 5;
    println("{p} {q:?} [{p:>8}]");
    let shapes = [Shape::Circle(3), Shape::Rect(p, q), Shape::Line { from: p, len: 4 }, Shape::Empty];
    for s in &shapes { println("{s:?}"); }
    let mut v: Vec<i64, Gpa> = Vec::new_in(gpa);
    v.push(1);
    v.push(2);
    println("{v:?} {:?} {:?} {:?}", v.last(), "hi\n", &v[..1]);
    0
}
```
```out
(1, 2) Point { x: 5, y: 2 } [(1, 2)]
Circle(3)
Rect(Point { x: 1, y: 2 }, Point { x: 5, y: 2 })
Line { from: Point { x: 1, y: 2 }, len: 4 }
Empty
[1, 2] Some(2) "hi\n" [1]
```

A `write(f, ..)` in `fmt` ignores the caller's width (`{p:>8}` above),
as in Rust; `f.pad(s)` honours it.

## derive

`#[derive(..)]` before a struct or an enum writes Rust's impls:
`Clone`, `Copy`, `PartialEq`, `Eq`, `PartialOrd`, `Ord` (field by field,
in declaration order; an enum by variant order, then payload), `Hash`,
`Debug` (`P { x: 1, y: 2 }`, `Circle(3)`, `Empty`) and `Default`. On a
generic type each parameter gets the trait as a bound: `#[derive(Ord)]
struct P<T>` is `impl<T: Ord> Ord for P<T>`. Display has no derive. A
derived trait and a hand-written impl of it clash: remove one.

```vole
use std::collections::HashMap;

#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Debug, Default)]
struct Key { group: i64, id: i64 }

fn main(gpa: Gpa) -> i32 {
    let mut keys = [Key { group: 2, id: 1 }, Key { group: 1, id: 9 }, Key { group: 1, id: 3 }];
    keys.sort_unstable();                    // by group, then id
    let mut m: HashMap<Key, i64, Gpa> = HashMap::new_in(gpa);
    for k in keys { m.insert(k, k.id * 10); }
    let wanted = Key { group: 2, id: 1 };
    println("{:?} {:?} {:?} {}", keys[0], m.get(&wanted), Key::default(), keys[1] < keys[2]);
    0
}
```
```out
Key { group: 1, id: 3 } Some(10) Key { group: 0, id: 0 } true
```

`sort` of a slice or an array is stable and allocates its buffer:
`a.sort_in(gpa)` (a Vec's `v.sort()` takes the Vec's allocator);
`sort_unstable` allocates nothing.
