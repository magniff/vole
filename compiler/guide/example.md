# A whole program

One complete program, written the way vole code is written: modules
and `use`, enums with data and `match`, `Result` and `?`, `Vec`,
`HashMap`, `String`, text as `&str`, a sort closure, format strings, the
allocator passed down from `main`, and a test case. A program of this
kind needs only what it shows: copy its patterns.

`stock` reads commands from stdin, one a line, and prints a line for
each command it rejects and the report it is asked for. It has three
files next to each other: `volec main.vl -o prog` builds them all.

```vole main.vl
// stock: a ledger of items. Reads commands from stdin, one a line; prints
// the report it is asked for, and a line for each command it rejects.
mod command;
mod store;

use command::{Error, parse};
use std::io;
use store::Store;

fn main(gpa: Gpa) -> i32 {
    let input = io::read_to_string_in(io::stdin(), gpa).unwrap(); // all of stdin, a String<Gpa>
    let mut store = Store::new(gpa);            // it allocates: give it gpa
    for (i, raw) in input.lines().enumerate() { // a line, without its '\n'
        let line = cut_comment(raw).trim();     // slices of input: no copies
        if line.is_empty() {
            continue;
        }
        if let Err(e) = run(&mut store, line, gpa) { // &mut: run may change store
            println("line {}: {e}", i + 1);     // Error has Display
        }
    }
    0
}                                               // store, then input, dropped (freed)

// One line: parsed, then applied; `?` passes the first Err up.
fn run<'a>(store: &mut Store<'a, Gpa>, line: &'a str, gpa: Gpa) -> Result<(), Error<'a>> {
    let cmd = parse(line, gpa)?;
    store.apply(cmd)
}

// s up to its first '#'.
fn cut_comment(s: &str) -> &str {
    match s.find('#') {                         // an Option<usize>, a byte index
        Some(i) => &s[..i],                     // a slice of s: &s[a..b], &s[a..]
        None => s,
    }
}
```

```vole command.vl
// A line of input as a Command, or the Error that rejects it.

use std::fmt;

// A field is private to its module unless `pub`: store.vl reads these.
// 'a: an Item's name borrows the input. Clone: Vec::clone needs it.
#[derive(Clone)]
pub struct Item<'a> { pub name: &'a str, pub count: i64, pub price: i64 }

// Variants carry data, tuple-like or struct-like.
pub enum Command<'a> {
    Add(Item<'a>),
    Sell { name: &'a str, count: i64 },
    Report,
}

pub enum Error<'a> {
    Unknown(&'a str),
    Arity(&'a str, usize),
    BadNumber(&'a str),
    NoItem(&'a str),
    Short(&'a str, i64),
}

// What `{e}` in a format string prints.
impl fmt::Display for Error<'_> {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            Error::Unknown(w) => write(f, "unknown command {w}"),
            Error::Arity(w, n) => write(f, "{w} takes {} arguments", n - 1),
            Error::BadNumber(w) => write(f, "not a number: {w}"),
            Error::NoItem(name) => write(f, "no item {name}"),
            Error::Short(name, have) => write(f, "only {have} {name} left"),
        }
    }
}

// `add NAME COUNT PRICE`, `sell NAME COUNT` or `report`.
pub fn parse<'a>(line: &'a str, gpa: Gpa) -> Result<Command<'a>, Error<'a>> {
    let w: Vec<&str, Gpa> = line.split_whitespace().collect_in(gpa); // slices of line
    let verb = w[0];
    if verb == "add" {                          // a string literal is not a pattern yet
        arity(&w, 4)?;
        let item = Item { name: w[1], count: number(w[2])?, price: number(w[3])? };
        Ok(Command::Add(item))
    } else if verb == "sell" {
        arity(&w, 3)?;
        Ok(Command::Sell { name: w[1], count: number(w[2])? })
    } else if verb == "report" {
        Ok(Command::Report)
    } else {
        Err(Error::Unknown(verb))
    }
}

fn arity<'a>(w: &[&'a str], n: usize) -> Result<(), Error<'a>> {
    if w.len() != n {
        return Err(Error::Arity(w[0], n));
    }
    Ok(())
}

// A count or a price: a number, not negative.
fn number(w: &str) -> Result<i64, Error> {
    match w.parse::<i64>() {
        Ok(n) if n >= 0 => Ok(n),
        _ => Err(Error::BadNumber(w)),
    }
}
```

```vole store.vl
// The items in stock, in the order they were first added.

use command::{Command, Error, Item};
use std::alloc::Allocator;
use std::collections::HashMap;
use std::fmt::Write;

// A type that holds an allocator is generic over it.
pub struct Store<'a, A: Allocator> {
    items: Vec<Item<'a>, A>,
    index: HashMap<&'a str, usize, A>,          // name -> its position in items
}

impl<'a> Store<'a, Gpa> {
    pub fn new(gpa: Gpa) -> Store<'a, Gpa> {
        Store { items: Vec::new_in(gpa), index: HashMap::new_in(gpa) }
    }

    // No free: a Store drops its fields (items, then index) when it is dropped.

    pub fn apply(&mut self, cmd: Command<'a>) -> Result<(), Error<'a>> {
        match cmd {
            Command::Add(item) => match self.index.get(item.name) {
                Some(&i) => {
                    self.items[i].count += item.count;
                    self.items[i].price = item.price;
                }
                None => {
                    self.index.insert(item.name, self.items.len());
                    self.items.push(item);
                }
            },
            Command::Sell { name, count } => {
                let i = *self.index.get(name).ok_or(Error::NoItem(name))?;
                let have = self.items[i].count;
                if have < count {
                    return Err(Error::Short(name, have));
                }
                self.items[i].count = have - count;
            }
            Command::Report => self.report(),
        }
        Ok(())
    }

    // The items by value, highest first, ties by name; then the total.
    fn report(&self) {
        let gpa = *self.items.allocator();      // a Vec's allocator, to allocate with
        let mut order = self.items.clone();     // a copy (in that allocator)
        order.sort_by(|a, b| value(b).cmp(&value(a)).then(a.name.cmp(b.name)));
        let mut out = String::new_in(gpa);
        let mut total = 0;
        for it in &order {
            writeln(&mut out, "{:<5}{:>3} x {:>2} = {}", it.name, it.count, it.price, value(it)).unwrap();
            total += value(it);
        }
        println("{out}total {total}");
    }
}

fn value(it: &Item) -> i64 {
    it.count * it.price
}
```

A test case is two files: the input in `tests/basic.in`, the expected
output in `tests/basic.out`. `volec test` builds the program and runs
every case (`test main.vl: 1 passed (1 case; -O0 and -O2 agree)`, or
the first lines that differ):

```in
# a day at the shop
add pen 10 3
add ink 4 12
add cap 6 8   # caps arrived
sell pen 3
sell hat 1
add pen x 2
sell ink 9
add ink 1 12
refund pen 1
sell cap
report
```
```out
line 6: no item hat
line 7: not a number: x
line 8: only 4 ink left
line 10: unknown command refund
line 11: sell takes 2 arguments
ink    5 x 12 = 60
cap    6 x  8 = 48
pen    7 x  3 = 21
total 129
```

## What differs from Rust here

- No macros: `println("line {}: {e}", i + 1)`, `write(f, "..")` and
  `writeln(&mut out, "..", args)` are functions with Rust's format
  strings.
- Nothing allocates without an allocator. `main` gets `gpa` and passes
  it down. A function that allocates takes `gpa: Gpa`
  (`collect_in(gpa)`, `String::new_in(gpa)`); one holding a `Vec` can
  use `*v.allocator()`. The allocator is in the type: `Vec<&str, Gpa>`,
  `String<Gpa>`, and a struct that holds one is generic over it
  (`Store<'a, A: Allocator>`, used as `Store<'a, Gpa>`).
- `match` has no string patterns yet: `if verb == "add"`.
- `mod command;` in main.vl makes `command` a name every module of the
  program imports from: `use command::{Command, Error, Item};` in
  store.vl (Rust: `use crate::command::..`, which works here too).

The rest is Rust's: text is `&str`, slices of `input` that borrow it
(`'a` on `Item`, `Command`, `Error` and `Store` says so), `&mut store`
for the function that changes it, `Display` by hand, `sort_by` with an
`Ordering` (`a.cmp(&b).then(..)`), and values dropped at the end of
their scope (`volec guide memory`).
