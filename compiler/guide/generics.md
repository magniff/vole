# Generics

Functions, structs, enums, traits, impl blocks and type aliases take
type parameters. A generic item is a template: each use with new type
arguments makes a separate copy (monomorphization), checked and
optimized as if written by hand. No boxing, no dynamic dispatch.

```vole
use std::alloc::Allocator;

struct Stack<T, A: Allocator> {
    items: Vec<T, A>,
}

impl<T, A: Allocator> Stack<T, A> {
    fn new(a: A) -> Stack<T, A> { Stack { items: Vec::new_in(a) } }
    fn push(&mut self, x: T) { self.items.push(x); }
    fn pop(&mut self) -> Option<T> { self.items.pop() }
}                                          // no free: a Stack drops its Vec

impl Stack<i64, Gpa> {                     // methods of one instance only
    fn sum(&self) -> i64 { self.items.iter().sum() }
}

fn largest<T: Ord + Copy>(s: &[T]) -> T {  // bounds: T has Ord and Copy
    let mut best = s[0];
    for &x in s {
        if x > best { best = x; }
    }
    best
}

fn swap<T, U>(p: (T, U)) -> (U, T) { (p.1, p.0) }

type Pair<T> = (T, T);

fn sum_pair(p: Pair<i64>) -> i64 { p.0 + p.1 }

fn main(gpa: Gpa) -> i32 {
    let mut s: Stack<i64, Gpa> = Stack::new(gpa);
    s.push(4);
    s.push(9);
    let a = [3i64, 8, 1];
    print("{} {} ", s.sum(), largest(&a));
    print("{} ", largest::<u8>(b"vole"));  // the turbofish
    let t = swap((1, "one"));
    println("{} {}", t.0, sum_pair((2, 3)) + s.pop().unwrap());
    0
}
```
```out
13 8 118 one 14
```

- Type arguments: after a type's name (`Vec<i64, Gpa>`, `Option<&str>`), and in
  expressions after `::` (`Vec::<u8, Gpa>::new_in(gpa)`, `max::<i64>(a, b)`,
  a method's own: `x.m::<u8>()`). They are inferred from arguments and
  from the expected type (`let v: Vec<i64, Gpa> = Vec::new_in(gpa);`);
  unsuffixed literals are looked at last. A `&[T]` parameter infers T
  from what is borrowed: `&v` of a `Vec<i64, Gpa>`, `&v[a..b]`, `&a` of
  an array, `s.as_bytes()`.
- A generic function used as a value needs its arguments:
  `let f = largest::<i64>;`.
- A body uses a type parameter only as its bounds allow, as in Rust:
  `a > b` needs `T: PartialOrd`, and `let best = s[0]` (a copy out of a
  slice) needs `T: Copy`. An error inside an instance is reported with
  `note: in instantiation of 'f<P>' at ...`.
- `size_of::<T>()` and `align_of::<T>()` (std::mem's) work on type
  parameters.
- `where` writes the bounds after the signature: `fn f<T>(x: T) where
  T: Display + Copy`, on a struct, an enum, a trait and an impl too
  (`impl<T, A: Allocator> Stack<T, A> where T: Ord {`), and on an
  associated type (`where I::Item: Display`).
- `x: impl Display` is a type parameter without a name: `fn show(x:
  impl Display)` is `fn show<T: Display>(x: T)`; also `f: impl Fn(i64)
  -> i64` and `f: &mut impl FnMut(i64)`. A result may be `impl Trait`
  too (`fn twice() -> impl Fn(i64) -> i64`). A turbofish gives only the
  named parameters.
- Traits take type parameters (`trait Conv<T> { fn conv(&self) -> T; }`,
  `impl Conv<i64> for i32`), and have associated types: `I::Item` for
  `I: Iterator`, bounds `I: Iterator<Item = i64>`, `F: Fn(i64) -> bool`
  (`volec guide iterators`, `guide closures`).

```vole
use std::fmt::Display;

fn show<T>(label: T, x: impl Display) where T: Display {
    println("{label}={x}");
}

fn apply(f: impl Fn(i64) -> i64, x: i64) -> i64 { f(x) }

fn main() -> i32 {
    show("n", 4);
    show::<&str>("pi", 3.5);
    println("{}", apply(|x| x * 2, 21));
    0
}
```
```out
n=4
pi=3.5
42
```

- Not there: const generics (`[T; N]` with `N` a parameter), variadic
  generics.
