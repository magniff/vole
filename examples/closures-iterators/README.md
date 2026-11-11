# closures-iterators

A log-file analyzer: reads a web server's access log on stdin and prints
a report (levels, status codes, latency, the slowest requests, traffic
per service). Nearly every step is a chain of iterator adapters with
closures, the way it would be written in Rust, and the program defines
an iterator of its own.

## Build and run

From this folder (with `volec` on your `PATH`, or `../../target/volec`):

```sh
volec main.vl -o closures-iterators
./closures-iterators < access.log
```

`access.log` is a sample. A line is `TIME LEVEL SERVICE STATUS MILLIS
PATH`; blank lines and `#` comments are skipped, and lines that do not
parse are counted:

```text
09:00:02 WARN api 429 3 /users
09:00:03 ERROR db 500 950 /orders
```

## Expected output

```text
14 requests, 1 malformed line(s) skipped
levels: 2 errors, 2 warnings
status: 10 ok, 4 failed
latency: min 2 ms, max 1200 ms, mean 200 ms
any 5xx: true, all under a second: false
first error: request #6 at 09:00:03, db /orders (500)
slow requests (over 100 ms): 5, the top 3:
  1. 1200 ms  api   /reports
  2.  950 ms  db    /orders
  3.  220 ms  api   /orders
requests per service:
  api      6  ######  mean 277 ms
  auth     3  ###     mean 12 ms
  web      3  ###     mean 4 ms
  db       2  ##      mean 545 ms
back-to-back requests in the same second: 5
```

## How it works

**An iterator of our own.** `Iterator` is a prelude trait with one
required method, `next`, and an associated type, `Item`. `Lines` yields
the lines of a text as slices of it (no copies; `'a` says that they
borrow the text); once it implements `next` it has every adapter
(`filter`, `map`, `for_each`...) for free:

```tach
struct Lines<'a> { text: &'a str, pos: usize }

impl<'a> Iterator for Lines<'a> {
    type Item = &'a str;

    fn next(&mut self) -> Option<&'a str> {
        if self.pos >= self.text.len() { return None; }
        let rest = &self.text[self.pos..];
        let len = rest.find('\n').unwrap_or(rest.len());
        self.pos += len + 1; // past the '\n'
        Some(&rest[..len])
    }
}
```

**Closures that change their surroundings.** Parsing is a `filter` and a
`for_each`. The second closure pushes onto `entries` and counts `bad`
lines: it borrows both mutably (they are `let mut`), so its changes are
seen after the chain. (What a closure only reads it borrows shared;
`move |..|` takes what it captures.)

```tach
let mut entries: Vec<Entry, Gpa> = Vec::new_in(gpa);
let mut bad = 0;
Lines::new(&input)
    .filter(|l| !l.is_empty() && !l.starts_with('#'))
    .for_each(|l| {
        match parse_entry(l) {
            Some(e) => entries.push(e),
            None => bad += 1,
        }
    });
```

`parse_entry` returns an `Option<Entry>` and uses `?` on each field, so
any missing or malformed field makes the whole line `None`
(`.parse().ok()?` turns the `Result` into an `Option` first).

**Consumers** reduce a chain to a value: `count`, `sum`, `min`, `max`
(an `Option`, empty for no items), and `fold`, here with a tuple
accumulator destructured in the closure's parameter list:

```tach
let total_ms: i64 = all.iter().map(|e| e.millis).sum();
let slowest = all.iter().map(|e| e.millis).max().unwrap_or(0);
let (ok, failed) = all.iter().fold((0, 0), |(ok, failed), e| {
    if e.status < 400 { (ok + 1, failed) } else { (ok, failed + 1) }
});
```

`any`, `all` and `position` answer questions, stopping at the first
item that decides them.

**Generic functions take closures** through `Fn`/`FnMut` bounds. Each
closure has its own unnamed type, so `count_where` is instantiated once
per closure and the call is direct, usually inlined:

```tach
fn count_where<F: Fn(&Entry) -> bool>(entries: &[Entry], pred: F) -> usize {
    let mut n = 0;
    for e in entries { if pred(e) { n += 1; } }
    n
}

let errors = count_where(all, |e| e.level == Level::Error);
```

Inside the call the closure's parameter type comes from the bound. A
closure kept in a `let` has no bound to learn from, so its parameter is
annotated: `let is_slow = |e: &Entry| e.millis > limit;`.

**collect, sort_by, enumerate, take.** `collect_in(gpa)` makes a `Vec`
of the items (dropped, so freed, at the end of `main`); `sort_by` sorts
it in place by a comparison of two elements (references to them)
returning an `Ordering`, so `b.cmp(a)` sorts descending:

```tach
let mut slow: Vec<Entry, Gpa> = all.iter().copied().filter(is_slow).collect_in(gpa);
slow.sort_by(|a, b| b.millis.cmp(&a.millis)); // slowest first
for (rank, e) in slow.iter().enumerate().take(3) {
    println("  {}. {:>4} ms  {:<5} {}", rank + 1, e.millis, e.service, e.path);
}
```

**Counting with a HashMap.** `entry(key).or_insert(0)` returns a `&mut`
to the value in place, so `*.. += 1` increments it. The map's `(key,
value)` pairs are then collected and sorted by count, then by name
(`then` takes the second comparison when the first says equal):

```tach
for e in all { *per_service.entry(e.service).or_insert(0) += 1; }
let mut ranked: Vec<(&str, i64), Gpa> = per_service
    .iter()
    .map(|(s, n)| (*s, *n))
    .collect_in(gpa);
ranked.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(b.0)));
```

**zip** walks two iterators in step, ending with the shorter one;
zipping the entries with `all[1..].iter()` pairs each request with the
next.

## Language features

- closures, captures (by reference, `move ||`), `Fn`/`FnMut` bounds: `volec guide closures`
- `Iterator`, `type Item`, adapters and consumers, `sort_by`: `volec guide iterators`
- `Option` and `?`, `.ok()`: `volec guide conversions`
- `HashMap`, `split_whitespace`, `parse`, `io::read_to_string_in`: `volec guide std`
- format specs (`{n:>3}`, `{service:<6}`): `volec guide formatting`
- `#[derive(PartialEq, Debug)]` on an enum: `volec guide formatting`

## Going further

The rest of Rust's iterators is there too: `iter_mut`, `rev`, `step_by`,
`chain`, `flat_map`, `peekable`; `collect_in(gpa)` makes a `HashMap`
from pairs as it makes a `Vec`; a function may return a closure or an
iterator (`-> impl Fn(i64) -> i64`, `-> impl Iterator<Item = &i64>`).
What differs from Rust:

- Collecting allocates, so it names its allocator: `collect_in(gpa)`,
  not `collect()`.
- There is no `dyn`: a closure is passed through a generic parameter or
  `impl Fn`, not as a `Box<dyn Fn>`.
