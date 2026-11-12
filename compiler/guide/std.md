# std

## The most used

std is Rust's std where it has the item, with allocation as a
capability: what allocates takes an allocator (`gpa`, from `fn
main(gpa: Gpa)`, passed down as a parameter) in a constructor or an
`_in` function, and a container keeps it for its methods (`push`,
`insert`, `clone`, `sort`). `v` is a `Vec`, `s` a `&str` or `String`,
`m` a `HashMap`, `o` an `Option` or `Result`.

```text
Vec::new_in(gpa) -> Vec<T, Gpa>  let mut v: Vec<i64, Gpa> = Vec::new_in(gpa);
v.push(x), v.pop() -> Option<T>  v.len() -> usize, v.is_empty(), v.clear()
v[i], v.get(i) -> Option<&T>     checked; &v[a..b], v.as_slice() -> &[T]
v.iter(), v.iter_mut(), for x in &v   guide iterators
v.sort(), v.sort_by(|a, b| a.cmp(b)), v.sort_unstable()
v.extend_from_slice(&s), v.insert(i, x), v.remove(i), v.retain(f), v.dedup()
s.to_vec_in(gpa), it.collect_in(gpa)   a slice, an iterator into a Vec
String::new_in(gpa), String::from_in("x", gpa), s.push_str(..)   guide text
format_in("{x}", gpa), x.to_string_in(gpa)
println("{x} {:?}", v)           any Display, Debug; eprintln to stderr
HashMap::new_in(gpa)             std::collections::HashMap<K, V, Gpa>
m.insert(k, v) -> Option<V>      m.get(&k) -> Option<&V>, m.get_mut, m.remove
*m.entry(k).or_insert(0) += 1    m.contains_key(&k), m.len(), m.keys(), m.values()
o.unwrap(), o.unwrap_or(x), o.ok_or(e), o?   guide conversions
s.parse::<i64>() -> Result<i64, ParseIntError>
std::io::stdin().read_line(&mut s)   guide conversions#reading-input
std::fs::read_to_string_in(path, gpa)   guide io
```

Not in std yet: `BTreeMap`, `BTreeSet`, `VecDeque`, `Rc`.
`std::collections` has `BinaryHeap` and `MinHeap`, `std::sync` `Arc`,
`Mutex` and the channels (`guide threads`).

@PAGE-END@ More, a section at a time: `volec guide std#the-api` (every item, a line each), `std#overview` (ownership, HashMap and HashSet); one item: `volec guide --find NAME`; all of it: `volec guide std --whole`.

## Overview

The standard library is the module `std`, built into the compiler. The
prelude is Rust's (`guide modules` lists it) plus `Gpa`; anything else
is used by path (`std::mem::swap(&mut a, &mut b)`) or imported by name
(`use std::collections::HashMap;`).

- `Vec<T, A>`, `String<A>` and `HashMap<K, V, A>` own their memory:
  `let w = v;` moves it, `.clone()` copies (with the same allocator),
  and the owner frees it at the end of its scope (`guide memory`).
- A function that reads one takes `&Vec<T, A>` (or `&[T]`, `&str`), one
  that changes it `&mut`, one that keeps it takes it by value.
- Indexing, slicing and `unwrap` are checked: a failure prints a message
  and exits with 101.
- `HashMap` keys need `Hash` and `Eq` (`#[derive(PartialEq, Eq, Hash)]`
  for a struct key). Lookups take a reference to anything the key
  borrows: `m.get("x")` on `&str` or `String` keys. Iteration is in slot
  order, not insertion order.
- A `HashMap` is a Swiss table (hashbrown's design), and its default
  hasher is foldhash with a fixed seed (`std::hash::FixedState`): the
  slot order is the same in every run and on every target. Not proof
  against keys an attacker chooses: `HashMap::with_hasher_in(
  std::hash::SipHashState::new(), gpa)` hashes with SipHash-1-3 and
  random keys, as Rust's default does.
- `std::collections::HashSet<T, A>`: `insert` (false if present),
  `contains`, `remove`, `iter()`.
- `std::mem::take(&mut x)`, `replace(&mut x, v)`, `swap(&mut a, &mut b)`.

```vole
use std::collections::{HashMap, HashSet};

fn main(gpa: Gpa) -> i32 {
    let mut counts: HashMap<&str, i64, Gpa> = HashMap::new_in(gpa);
    let words = ["a", "b", "a", "c", "a"];
    for w in words {
        *counts.entry(w).or_insert(0) += 1;
    }
    if let Some(n) = counts.get_mut("c") {
        *n *= 10;
    }
    let mut keys: Vec<&&str, Gpa> = counts.keys().collect_in(gpa);
    keys.sort();
    for k in &keys { print("{k}={} ", counts[*k]); }
    println("{} {}", counts.len(), counts.contains_key("b"));
    let mut seen: HashSet<i64, Gpa> = HashSet::new_in(gpa);
    println("{} {}", seen.insert(3), seen.insert(3));
    let mut v: Vec<i64, Gpa> = Vec::with_capacity_in(4, gpa);
    v.extend_from_slice(&[3, 1, 2]);
    v.sort();
    v.dedup();
    v.retain(|x| *x > 1);
    let w = vec_in(&[1, 2], gpa);
    println("{:?} {:?} {:?} {}", v, v.binary_search(&3), v.first(), w.len());
    0
}
fn vec_in(s: &[i64], gpa: Gpa) -> Vec<i64, Gpa> { s.to_vec_in(gpa) }
```
```out
a=3 b=1 c=10 3 true
true false
[2, 3] Ok(1) Some(2) 2
```

## The API

Generated from std's source in this compiler: every public item a
program uses most, one line each, in std's source spelling (`&self`
reads; `&mut self` changes, called as `v.push(x)` on a `let mut`; `self`
takes the value). Each item with its
comment: `volec guide std#every-item`; one item's source: `volec
query show Vec::push`.

```text
@STD-API@
```
@STD-API-DOC@
