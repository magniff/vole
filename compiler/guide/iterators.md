# Iterators

`Iterator` is a prelude trait with one required method and an
associated type, Rust's:

```text
trait Iterator {
    type Item;
    fn next(&mut self) -> Option<Self::Item>;
    // and, written once in std: map filter enumerate zip take rev chain
    // fold for_each count sum min max collect_in ...
}
```

std's sources and adapters are small structs whose methods are
`#[inline]`: a chain of them compiles to the loop written by hand (the
same machine code at -O2, vectorized where the loop would be).

```vole
fn main(gpa: Gpa) -> i32 {
    let mut v: Vec<i64, Gpa> = Vec::new_in(gpa);
    for i in 1..=6 { v.push(i); }
    let evens: i64 = v.iter().filter(|x| *x % 2 == 0).map(|x| x * x).sum();
    let top = v.iter().map(|x| x * 10).max().unwrap();
    println("{} {} {}", evens, top, (0..100).filter(|n| n % 7 == 0).count());
    for (i, x) in v.iter().enumerate().take(2) {
        print("{} ", i as i64 * 100 + x);
    }
    println("{}", v.iter().zip(v.iter()).fold(0i64, |acc, (a, b)| acc + a * b));
    let mut w: Vec<i64, Gpa> = v.iter().map(|x| 7 - x).collect_in(gpa);
    w.sort_by(|a, b| a.cmp(b));
    for x in &w { print("{x}"); }
    println("");
    0
}
```
```out
56 60 15
1 102 91
123456
```

## Sources

| source | items |
|---|---|
| `v.iter()`, `s.iter()` (a Vec, a slice, an array variable) | `&T`, each element borrowed |
| `v.iter_mut()` | `&mut T`: `for x in v.iter_mut() { *x *= 2; }` |
| `v.into_iter()`, `for x in v` | `T`, the Vec's elements moved out |
| `m.iter()`, `m.keys()`, `m.values()` (a `HashMap<K, V, A, S>`) | `(&K, &V)`, `&K`, `&V` |
| `a..b`, `a..=b` as a value: `(0..n).map(...)` | the integers; `0..=255u8` ends without overflow |
| a type with `impl Iterator` | what its `next` returns |

`for x in E` takes what Rust's does: a range, an iterator, `&v` (`&T`
items), `&mut v` (`&mut T`), `v` by value. An array's or a Vec's methods
want a place: `[1, 2].iter()` of a temporary array is an error, bind it
to a variable first.

## Adapters and consumers

- Rust's: `map`, `filter` (its closure takes `&Item`: `|x| **x > 0` over
  `v.iter()`, or `.copied()` first), `enumerate` (items `(usize,
  Item)`), `zip`, `take`, `skip`, `rev`, `step_by`, `chain`, `flat_map`,
  `peekable`, `copied`, `cloned`, and `fold`, `for_each`, `count` (a
  usize), `sum`, `min`, `max` (an `Option`), `any`, `all`, `position`,
  `find`.
- `collect_in(gpa)` collects into the type written where the value
  goes (`let w: Vec<i64, Gpa> = it.collect_in(gpa);`): a Vec, a String,
  a HashMap; `collect_in::<Vec<i64, Gpa>, _>(gpa)` says it in the call.
- `v.sort()`, `v.sort_by(|a, b| a.cmp(b))` (`b.cmp(a)`: descending),
  `v.sort_by_key(..)`, the `_unstable` forms.
- A literal an adapter's result is added to needs its type where nothing
  else gives it: `fold(0i64, ..)`, `(0..10i64).step_by(3).sum()`.

## Your own iterator

```vole
struct Countdown { n: i64 }

impl Iterator for Countdown {
    type Item = i64;
    fn next(&mut self) -> Option<i64> {
        if self.n == 0 { return None; }
        self.n -= 1;
        Some(self.n + 1)
    }
}

fn first<I: Iterator>(mut it: I) -> Option<I::Item> {
    it.next()
}

fn total<I: Iterator<Item = i64>>(it: I) -> i64 {
    it.sum()
}

fn main() -> i32 {
    let c = Countdown { n: 3 };
    for x in c { print("{x}"); }
    println(" {} {}", total(Countdown { n: 4 }), first(Countdown { n: 9 }).unwrap());
    0
}
```
```out
321 10 9
```

- `type Item = T;` in the impl is required; `Self::Item` and `I::Item`
  (for a type parameter `I: Iterator`) name it. `I: Iterator<Item = i64>`
  constrains it.
- The provided methods (`map`, `sum`...) come with the trait.
- A function may return one: `fn evens(n: i64) -> impl Iterator<Item =
  i64> { (0..n).filter(|x| x % 2 == 0) }`.

Not there: `dyn Iterator` (`dyn` is reserved).
