# Closures

A closure is a function written as an expression, that uses the locals
around it: `|x| x + k`. Each closure has its own type, which has no
name: give a closure to a generic parameter bounded by `Fn`, `FnMut` or
`FnOnce` (or an `impl Fn(..)` parameter), or keep it in a `let`. Calls
are direct (no allocation, no pointer to a function), and a closure
passed to a generic function is usually inlined.

```vole
fn apply<F: Fn(i64) -> i64>(f: F, x: i64) -> i64 {
    f(x)
}

fn repeat<F: FnMut(i64)>(n: i64, mut f: F) {
    for i in 0..n { f(i); }
}

fn main() -> i32 {
    let k = 10;
    let add_k = |x: i64| x + k;             // a `let` needs the parameter's type
    print("{} ", apply(add_k, 1));
    print("{} ", apply(|x| x * 2, 21));     // here F's bound gives x: i64
    let mut total = 0;
    repeat(4, |i| total += i);              // borrows `total` mutably
    println("{total}");
    0
}
```
```out
11 42 6
```

## Syntax

- `|a, b| a + b`; `|| 42` takes nothing; `|x: i64| -> i64 { x + 1 }`:
  with a result type, the body is a block. The body takes everything
  after the bars, as `return`'s value does: `|x| x + 1` is
  `|x| (x + 1)`.
- Parameters are patterns: `|(a, b): (i64, i64)| a * b`, `|mut x|`,
  `|_|`, `|s: &mut Sum, x: i64| s.total += x`; not `|a | b|` (no
  or-pattern at the top).
- A parameter's type is the annotation, else the one the context
  expects (an `F: Fn(i64) -> bool` bound, an `fn(i64) -> bool`
  parameter). Without either it is an error: `cannot infer the type of
  closure parameter 'x'`, fixed by writing `|x: i64|` (a closure kept in
  a `let` needs it, where rustc would infer it from the later call).
- `return` in the body returns from the closure; `break` and `continue`
  cannot leave it. An `unsafe { }` around a closure covers its body.
- Messages and `volec query type FILE:LINE:COL` show a closure's type
  as `closure(i64) -> i64 at main.vl:4:15`.

## What a closure captures

Rust's rules. A closure borrows what it uses: a shared borrow of a
variable it only reads, a mutable borrow of one it changes (an
assignment, `x.push(..)`, `&mut x`). The borrow lasts from the closure's
creation to its last call: until then, a variable it borrows mutably is
not used another way, and one it reads is not changed
(`borrowck.conflict`). Use the variable after the closure's last call,
pass the value as a parameter instead, or move it in with `move`.

```vole
fn main(gpa: Gpa) {
    let mut v: Vec<i64, Gpa> = Vec::new_in(gpa);
    let mut add = |x: i64| v.push(x);
    add(1);
    add(2);
    println("{}", v.len()); // add's last call is above
}
```
```out
2
```

## move closures

`move || body` takes what it captures: a `Copy` value is copied, any
other moves into the closure and is dead after it
(`borrowck.use_moved`), and the closure changes its own copies. It is
the way to keep a closure that outlives the block of what it uses:
without `move`, a closure that borrows a variable cannot leave that
variable's block (a block's value, a `break` value, an arm's value:
`borrowck.dropped_borrowed`). A closure whose body moves a captured
value out (`drop(v)`, `let w = v;`) can be called once: it is `FnOnce`
only.

```vole
fn call<F: FnMut() -> usize>(mut f: F) -> usize { f() }

fn main(gpa: Gpa) -> i32 {
    let mut v: Vec<i64, Gpa> = Vec::new_in(gpa);
    v.push(4);
    let w = v.clone();
    let count = || w.len();            // borrows w
    let keep = move || v.len();        // v moves into the closure: dead here
    println("{} {} {}", count(), call(keep), w.len());
    0
}
```
```out
1 1 1
```

```vole
fn call<F: FnMut() -> i64>(mut f: F) -> i64 {
    f()
}

fn main() -> i32 {
    let mut n: i64 = 1;
    let snap = move || n;              // a copy of n, now
    let bump = || { n += 10; n };      // borrows n mutably
    let b = call(bump);                // 11
    n += 100;                          // bump is done with n
    println("{b} {} {n}", call(snap));
    0
}
```
```out
11 1 111
```

## Fn, FnMut, FnOnce, fn

- `F: Fn(A, B) -> R` takes a closure with that signature that changes
  nothing it captures, or a plain function `fn(A, B) -> R`.
- `F: FnMut(A, B) -> R` takes one that may change what it captures;
  call it through `mut f: F` or `f: &mut F`.
- `F: FnOnce(A, B) -> R` takes any closure, called once.
- `-> R` may be left out: `FnMut(i64)` returns `()`.
- A closure that captures nothing is a plain function: it converts to
  `fn(i64) -> i64` where one is expected. A capturing one is an error
  there; make the parameter generic: `fn run<F: Fn(i64) -> i64>(f: F)`.
- A function may return one: `fn adder(k: i64) -> impl Fn(i64) -> i64 {
  move |x| x + k }`.
- In a struct, a closure is a generic field: `struct Button<F> { on: F }`,
  called as `(b.on)(3)`.

```vole
struct Counter<F> { step: F, n: i64 }

fn run(f: fn(i64) -> i64) -> i64 {
    f(4)
}

fn main() -> i32 {
    print("{} ", run(|x| x * x));      // captures nothing: a plain fn
    let k = 3;
    let mut c = Counter { step: |x: i64| x + k, n: 0 };
    c.n = (c.step)(c.n);
    c.n = (c.step)(c.n);
    println("{}", c.n);
    0
}
```
```out
16 6
```

Not there: `dyn Fn` (`dyn` is reserved: use generics), closures in
statics, a closure calling itself. `volec guide iterators`: closures
with `map`, `filter`, `fold`.
