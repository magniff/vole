# Allocators

Allocation is explicit: nothing allocates without being given an
allocator. A program's general-purpose allocator is the `gpa: Gpa` its
`main` takes; a function that allocates takes one as a parameter, or
works on a container it was given (a `Vec` holds its allocator: `push`,
`clone` and its drop use it). There is no global allocator to reach for,
so a function's signature says whether it allocates. This is where vole
is not Rust: Rust's `Vec::new()` allocates from a global one.

## Gpa, from main

```vole
fn squares(n: i64, gpa: Gpa) -> Vec<i64, Gpa> { // allocates: takes the allocator
    let mut v: Vec<i64, Gpa> = Vec::with_capacity_in(n as usize, gpa);
    for i in 0..n { v.push(i * i); }
    v
}

fn total(v: &Vec<i64, Gpa>) -> i64 { // grows nothing: no allocator
    v.iter().sum()
}

fn main(gpa: Gpa) -> i32 {
    let mut v = squares(4, gpa);
    v.push(100);                              // the Vec's own allocator
    let b = total(&v).to_string_in(gpa);      // a String<Gpa>
    let words: Vec<i64, Gpa> = (1..4i64).map(|x| x * 10).collect_in(gpa);
    println("{b} {words:?}");
    0
}                                             // words, b, v dropped: freed
```
```out
114 [10, 20, 30]
```

`Gpa` is a zero-sized `Copy` value: an allocator is passed by value
(`gpa: Gpa`), and every container made from it shares it. Only `main`
gets one (std's types have private fields: no `Gpa {}` outside std).
Each of Rust's forms that allocates has an `_in` form taking the
allocator last, as Rust's allocator API does (`Vec::with_capacity_in(cap,
alloc)`): `Vec::new_in(a)`, `with_capacity_in(n, a)`,
`String::new_in(a)`, `String::from_in(s, a)`, `Box::new_in(x, a)`,
`HashMap::new_in(a)`, `it.collect_in(a)`, `format_in("..", args, a)`,
`x.to_string_in(a)`, `s.to_vec_in(a)`, `s.to_uppercase_in(a)`,
`io::read_to_string_in(r, a)`, `fs::read_in(p, a)`, `v.clone_in(b)`.
There is no form without `_in`: `Vec::new()`, `collect()`,
`to_string()` are errors that name the `_in` form, and `volec fix --only
alloc` passes the one allocator in scope:

```vole
fn main(gpa: Gpa) {
    let v: Vec<i64, Gpa> = Vec::new();
}
```
```err
error[alloc.no_in] 'Vec::new' allocates from nothing: pass the allocator, last, to 'Vec::new_in'
```

## Containers and their allocator

`Vec<T, A: Allocator>`, `String<A>`, `Box<T, A>`, `HashMap<K, V, A>`: the
allocator is a type parameter, always written (no default,
`alloc.default`), so `Vec<i64, Gpa>` says it may grow from `Gpa`, which
takes no bytes. Code generic over the allocator names it (`use
std::alloc::Allocator;`), and changes the container through a `&mut`;
code that only reads takes a slice:

```vole
use std::alloc::Allocator;

fn fill<A: Allocator>(v: &mut Vec<i64, A>, n: i64) {
    for i in 0..n { v.push(i); }
}

fn sum(s: &[i64]) -> i64 {                    // any Vec's slice
    s.iter().sum()
}

fn main(gpa: Gpa) -> i32 {
    let mut v: Vec<i64, Gpa> = Vec::new_in(gpa);
    fill(&mut v, 5);
    println("{}", sum(&v));
    0
}
```
```out
10
```

An impl block writes every type argument: `impl<T, A: Allocator> Tr for
Vec<T, A>`. `&A` is an allocator when `A` is one, so a container can
borrow its allocator (`Vec::new_in(&arena)`, below).

## Allocation is a capability

A function can allocate only through an allocator reachable from its
parameters, so its signature says whether it may:

- **No default allocator type** (`alloc.default`): `Vec<u8>` is an
  error; write `Vec<u8, Gpa>`, or a generic `A`.
- **No static holds an allocator** (`alloc.static`): a static's type
  holds none, looked through fields, payloads and pointers. Keep
  containers in `main` and pass them (or slices of them) down.
- **A type that holds an allocator names it** (`alloc.field`): a field
  `Vec<i64, Gpa>` needs `struct Parser<A: Allocator> { toks: Vec<i64, A>
  }`, used as `Parser<Gpa>`; a literal infers `A` from its fields.
- **An allocator's impl is unsafe** (`alloc.safe_impl`): `Allocator` is
  an `unsafe trait` (Rust's: `allocate(&self, Layout) ->
  Result<NonNull<u8>, AllocError>`, `deallocate`), and `unsafe impl
  Allocator for T` says, under `// SAFETY:`, where its memory comes
  from. An `_in` function takes its allocator last (`alloc.last`).

```vole
use std::alloc::Allocator;

struct Parser<A: Allocator> {
    toks: Vec<i64, A>,
}

fn parse_in<A: Allocator>(s: &str, a: A) -> Parser<A> {
    let mut p = Parser { toks: Vec::new_in(a) };
    for c in s.bytes() { p.toks.push(c as i64); }
    p
}

fn main(gpa: Gpa) {
    let p = parse_in("ab", gpa);
    println("{}", p.toks.len());
}
```
```out
2
```

`volec fix --only alloc` writes what it can: `Gpa` where an allocator is
missing, the `_in` form with the allocator in scope, a type made generic
over what it holds, then its uses; `volec explain alloc.field` (and each
code) tells the rule.

## Arenas

An arena allocates by bumping a pointer and frees everything at once.
`Arena::new_in(gpa)` makes one (its memory from `gpa`), freed whole when
it is dropped: `arena.alloc(x)` puts a value in it and gives a `&mut T`
that lives as long as the arena is borrowed, `alloc_str(s)` and
`alloc_slice_copy(s)` copy text and slices in, and `&arena` is an
allocator for containers. `std::alloc::arena_scope(&gpa, |a| ...)` makes
one for a closure and frees all of it when the closure returns; nothing
allocated from it may leave the closure (`borrowck.outlives`).
`arena.scope(|s| ...)` is a scope inside an arena. `FixedBuf::new(&mut
mem)` allocates from memory you give it, which it borrows mutably:
while it, or a container on it, lives, `mem` is not read or written
another way (`borrowck.assign_borrowed`), and it cannot outlive `mem`.
Two containers alive together need a buffer each.

```vole
use std::alloc::FixedBuf;

fn main() {
    let mut mem = [0u8; 256];
    let mut v: Vec<i64, FixedBuf> = Vec::new_in(FixedBuf::new(&mut mem));
    v.push(7);
    v.push(8);
    println("{}", v[0] + v[1]);
}
```
```out
15
```

```vole
use std::alloc::{Arena, arena_scope};

fn longest(words: &[&str], gpa: Gpa) -> usize {
    arena_scope(&gpa, |a| {
        let mut lens = Vec::new_in(a);        // a Vec<usize, &ArenaScope<..>>
        for w in words { lens.push(w.len()); }
        lens.iter().copied().max().unwrap_or(0) // a usize leaves, the Vec does not
    })
}

fn main(gpa: Gpa) {
    let arena = Arena::new_in(gpa);           // freed whole when it is dropped
    let n = arena.alloc(40);                  // a &mut i32 in the arena
    *n += 2;
    let name = arena.alloc_str("vole");
    let mut v = Vec::new_in(&arena);          // a container on it: &Arena is an allocator
    v.push(*n);
    println("{} {name} {} {}", longest(&["a", "bcd"], gpa), v[0], arena.used() > 0);
}
```
```out
3 vole 42 true
```

## --check-alloc

`volec --check-alloc f.vl -o f` builds the program with a checking
`Gpa` (like `--check-unsafe`, at any `-O`): every block gets pages of
its own, never reused, so a use after free, a double free, a free of a
wrong pointer or size stop the program with where the block was
allocated and freed; leaks are listed at exit (`gpa.check_leaks()` in a
test). Safe code cannot do these (the borrow checker rejects a
reference into memory that was freed or moved: `volec guide
memory#slices`); this mode finds them in `unsafe` code.
