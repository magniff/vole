# Allocators (0.16)

Allocation is explicit: nothing allocates without being given an
allocator. A program's general-purpose allocator is the `gpa: Gpa` its
`main` takes; a function that allocates takes one as a parameter, or
works on a container it was given (a `Vec` holds its allocator: `push`,
`clone` and its drop use it). There is no global allocator to reach for,
so a function's signature says whether it allocates.

## Gpa, from main

```vole
fn squares(n: i64, gpa: Gpa) -> Vec<i64, Gpa> { // allocates: takes the allocator
    var v: Vec<i64, Gpa> = Vec::with_capacity_in(n as usize, gpa);
    for i in 0..n { v.push(i * i); }
    v
}

fn total(v: Vec<i64, Gpa>) -> i64 { // grows nothing: no allocator
    v.iter().sum()
}

fn main(gpa: Gpa) -> i32 {                    // or main(argc, argv, gpa)
    var v = squares(4, gpa);
    v.push(100);                              // the Vec's own allocator
    var b = Buf::new_in(gpa);
    b.push_int(total(v));
    let words: Vec<i64, Gpa> = (1..4).map(|x| x * 10).collect_in(gpa);
    println("{} {words:?}", b.as_slice());
    0
}                                             // words, b, v dropped: freed
```
```out
114 [10, 20, 30]
```

`Gpa` is a zero-sized value, copied freely: an allocator is passed as a
let parameter (`gpa: Gpa`, no convention to write), and every container
made from it shares it. Only `main` gets one (std's
types have private fields: no `Gpa {}` outside std). Each 0.15 form that
allocated has an `_in` form taking the allocator last: `Vec::new_in(a)`,
`with_capacity_in(n, a)`, `filled_in(n, x, a)`, `Buf::new_in(a)`,
`HashMap::new_in(a)`, `it.collect_in(a)`, `format_in(x, a)`,
`read_stdin_in(a)`, `split_in(s, sep, a)`, `split_whitespace_in(s, a)`,
`sort_stable_in(s, a)`, `sort_stable_by_in(s, f, a)`, `v.clone_in(b)`,
`BinaryHeap::new_in(a)`. The allocator is always the last argument, as
in Rust's allocator API (`Vec::with_capacity_in(cap, alloc)`), except
before a closure that is given it: `arena_scope(gpa, |a| ..)`.
There is no form without `_in` (0.26.3): `Vec::new()`, `collect()`,
`format(x)` are errors that name the `_in` form, and `volec fix --only
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

`Vec<T, A: Allocator>`, `Buf<A>`, `HashMap<K, V, A>`: the allocator is a
type parameter, always written (0.26.3: no default, `alloc.default`), so
`Vec<i64, Gpa>` says it may grow from `Gpa`, which takes no bytes. Code
generic over the allocator names it, and changes the container through
an `inout` parameter (called with `&v`); code that only reads takes a
slice:

```vole
fn fill<A: Allocator>(v: inout Vec<i64, A>, n: i64) {
    for i in 0..n { v.push(i); }
}

fn sum(s: [i64]) -> i64 {                     // any Vec's as_slice()
    s.iter().sum()
}

fn main(gpa: Gpa) -> i32 {
    var v: Vec<i64, Gpa> = Vec::new_in(gpa);
    fill(&v, 5);
    println(sum(v.as_slice()));
    0
}
```
```out
10
```

An impl block writes every type argument: `impl<T, A: Allocator> Tr for
Vec<T, A>`.

## Allocation is a capability (0.26.3)

A function can allocate only through an allocator reachable from its
parameters, so its signature says whether it may:

- **No default allocator type** (`alloc.default`): `Vec<u8>` is an
  error; write `Vec<u8, Gpa>`, or a generic `A`.
- **No static holds an allocator** (`alloc.static`): a static's type is
  `AllocFree`, looked through fields, payloads and pointers. Keep
  containers in `main` and pass them (or views of them) down. A bound
  `T: AllocFree` (`use std::AllocFree;`) keeps a generic function from
  allocating through what it is given.
- **A type that holds an allocator names it** (`alloc.field`): a field
  `Vec<i64, Gpa>` needs `struct Parser<A: Allocator> { toks: Vec<i64, A>
  }`, used as `Parser<Gpa>`; a literal infers `A` from its fields.
- **An allocator's impl is unsafe** (`alloc.safe_impl`): `Allocator` is
  an `unsafe trait`, and `unsafe impl Allocator for T` says, under
  `// SAFETY:`, where its memory comes from. An `_in` function takes its
  allocator last (`alloc.last`).

```vole
struct Parser<A: Allocator> {
    toks: Vec<i64, A>,
}

fn parse_in<A: Allocator>(s: [u8], a: A) -> Parser<A> {
    var p = Parser { toks: Vec::new_in(a) };
    for c in s { p.toks.push(c as i64); }
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
`arena_scope(gpa, |a| ...)` makes one (its memory from `gpa`), runs the
closure with it, and frees all of it when the closure returns; nothing allocated from it may leave
the closure (the compiler rejects a result or a capture that holds the
`ScopedArena`). `Arena::new_in(gpa)` is a handle kept longer (it does
not drop yet: `unsafe { a.free_all(); }` returns its memory, 0.17),
`a.scope(|s| ...)` a scope of it; `FixedBuf::new(&mem[..])` allocates
from memory you give it, which it holds inout (0.25): while it, or a
container on it, lives, `mem` is not read, written or dropped another
way (`own.conflict`), and it cannot outlive `mem`. Two containers alive
together need a buffer each.

```vole
use std::FixedBuf;

fn main() {
    var mem = [0u8; 256];
    var v: Vec<i64, FixedBuf> = Vec::new_in(FixedBuf::new(&mem[..]));
    v.push(7);
    v.push(8);
    println("{}", v[0] + v[1]);
}
```
```out
15
```

```vole
fn longest(words: [[u8]], gpa: Gpa) -> usize {
    arena_scope(gpa, |a| {
        var lens: Vec<usize, ScopedArena> = Vec::new_in(a);
        for w in words { lens.push(w.len()); }
        lens.iter().max().unwrap_or(0)        // a usize leaves, the Vec does not
    })
}
```

## --check-alloc

`volec --check-alloc f.vl -o f` builds the program with a checking
`Gpa` (like `--check-unsafe`, at any `-O`): every block gets pages of
its own, never reused, so a use after free, a double free, a free of a
wrong pointer or size stop the program with where the block was
allocated and freed; leaks are listed at exit (`gpa.check_leaks()` in a
test). Arenas and `FixedBuf` are checked the same way: a block
used after their `reset`, after its scope ended, or after it moved is
reported. Views (`as_slice()`, a `[T]`) into memory that was freed or
moved are rejected in safe code since 0.17 (`volec guide views`);
this mode still finds them in `unsafe` code and under `--values=off`.
