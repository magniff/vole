# Traits

Rust's traits. A trait declares functions (`Self` is the implementing
type), with or without a default body, associated types and constants.
`impl Trait for Type` defines them for any type (`i64`, `[T]`, `Vec<T,
A>`, a struct); its methods become the type's. Dispatch is static: a
generic function is compiled once per type it is called with.

```vole
use std::collections::HashMap;
use std::hash::FixedState;
use std::ops::Add;

trait Shape {
    fn area(&self) -> i64;
    fn name(&self) -> &str { "shape" }          // a default
}

struct Square { side: i64 }
struct Rect { w: i64, h: i64 }

impl Shape for Square {
    fn area(&self) -> i64 { self.side * self.side }
    fn name(&self) -> &str { "square" }
}

impl Shape for Rect {
    fn area(&self) -> i64 { self.w * self.h }
}

fn report<T: Shape>(s: &T) {
    println("{} {}", s.name(), s.area());
}

// Operators through std::ops (Add, Sub, Mul, Neg, Index...) and std::cmp:
// == through PartialEq, < through PartialOrd, both derivable.
#[derive(Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord, Debug)]
struct V2 { x: i64, y: i64 }

impl Add for V2 {
    type Output = V2;
    fn add(self, o: V2) -> V2 { V2 { x: self.x + o.x, y: self.y + o.y } }
}

trait Double { fn double(self) -> Self; }
impl Double for i64 { fn double(self) -> i64 { self * 2 } }

fn main(gpa: Gpa) -> i32 {
    report(&Square { side: 3 });
    report(&Rect { w: 2, h: 5 });
    let v = V2 { x: 1, y: 2 } + V2 { x: 3, y: 4 };
    if v > (V2 { x: 0, y: 0 }) { print("{}", v.x * 10 + v.y); }
    let mut seen: HashMap<V2, bool, Gpa, FixedState> = HashMap::new_in(gpa); // a key: Hash + Eq
    seen.insert(v, true);
    if seen.contains_key(&V2 { x: 4, y: 6 }) { print(" found "); }
    println("{} {:?}", 21i64.double(), v);
    0
}
```
```out
square 9
shape 10
46 found 42 V2 { x: 4, y: 6 }
```

- Bounds: `fn f<T: A + B>`, `where T: A`, `impl<T: Hash> Hash for
  Pair<T>`, `fn area(s: &impl Shape)`. A call with a type that lacks the
  trait is an error naming the bound: `the trait 'T' is not implemented
  for 'i64' | help: required by the bound 'X: T' of 'g'`.
- One impl per trait and type (a generic impl counts for all its
  instances): `conflicting impls of trait 'T' for 'S'`. An impl without
  a function the trait has no default for: `the impl of trait 'T' is
  missing 'f'`.
- Operators are std::ops' traits (`Add`, `Sub`, `Mul`, `Div`, `Rem`,
  `Neg`, `Not`, the `*Assign` forms, `Index`, `IndexMut`), each with its
  `type Output`; `==` is `PartialEq`, `<` `PartialOrd`. `#[derive(Clone,
  Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Debug, Default)]` writes
  them (`guide formatting#derive`); a HashMap key is `Hash + Eq`.
- Receivers are Rust's: `&self`, `&mut self`, `self`. `x.m()` borrows
  `x` as the receiver says (a `&mut self` method needs a `let mut x`);
  `Type::m(&x)` is the same call, and a function without `self` is called
  `Type::f()` or `T::f()` for a type parameter.
- A method of an integer literal needs its type where only some integer
  types have it: `21i64.double()` (rustc's E0689).
- Supertraits (`trait Loud: Named`), associated constants (`const KIND:
  &'static str;`, used as `Self::KIND`, `<Dog as Named>::KIND`), blanket
  impls (`impl<T: Debug> Describe for T`), generic traits (`trait
  From<T>`, `T: From<i64>`, `guide conversions`) and `impl Trait`
  arguments and results are Rust's.
- Not there: `dyn Trait` (`dyn` is reserved: use generics, or an enum of
  the cases).

## Associated types

A trait declares `type Name;`, each impl defines it, and `T::Name`,
`Self::Name` or `<T as Tr>::Name` is that type. A bound can fix it: `I:
Iterator<Item = i64>`. A trait can be implemented for a slice: `impl<T>
Second for [T]`.

```vole
struct Countdown { n: i64 }

impl Iterator for Countdown {           // std's trait, in the prelude
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
    it.sum()                            // a default of Iterator
}

trait Second<T> { fn second(&self) -> &T; }

impl<T> Second<T> for [T] {
    fn second(&self) -> &T { &self[1] }
}

fn main() -> i32 {
    let b = "xyz".as_bytes();
    println("{} {} {} {}", first(Countdown { n: 3 }).unwrap(), total(Countdown { n: 4 }),
        Countdown { n: 5 }.count(), *b.second() as char);
    0
}
```
```out
3 10 5 y
```

- Every declared name must be defined: `the impl of trait 'Iterator' is
  missing 'type Item'`.
- A constraint that does not hold names both types: `'Small::Item' is
  'u8', but the bound 'I: Iterator<Item = i64>' of 'total' requires
  'i64'`.
- `F::Output` is the result type of a closure or fn type.
