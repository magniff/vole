# Appendix C: coming from another language

If you already know a language well, the quickest way into vole is a
list of differences: what carries over, what looks the same and means
something else, and the first errors you'll meet. This appendix has one
section per background. Each row points to the chapter that explains
it, and each section ends with a small program.

Read the section for the language you know best; the others are short.

## From Rust

Vole looks like Rust on purpose: the same `fn`, `struct`, `enum`,
`match`, `impl`, traits and generics, `Option` and `Result` with `?`,
modules and `use`, `unsafe` and `extern "C"`. Ownership carries over
too: moves, `&T` and `&mut T`, lifetimes, and a borrow checker with the
rules you know (chapter 4). What doesn't carry over is a short list,
and the compiler's errors for Rust habits name vole's form on their
`help:` or `try:` lines.

| Rust | vole | chapter |
|---|---|---|
| `println!`, `vec!`, `assert!`, macros | functions: `println("{x}")`, `assert(c)`, `assert_eq(a, b)`; there are no macros | 1, 13 |
| `Vec::new()`, `String::new()`, `collect()`, `format!` | `Vec::new_in(gpa)`, `String::new_in(gpa)`, `collect_in(gpa)`, `format_in("{x}", gpa)`: allocation is explicit, the allocator goes last | 8 |
| `Vec<T>`, `String`, `HashMap<K, V>` | `Vec<T, Gpa>`, `String<Gpa>`, `HashMap<K, V, Gpa, FixedState>`: the allocator is part of the type, and there is no default; a map's hasher too (`use std::hash::FixedState;`) | 8 |
| a struct holding a `Vec` | names the allocator: `struct Log<A: Allocator> { lines: Vec<String<A>, A> }` | 8, 9 |
| `fn main()` | `fn main(gpa: Gpa)`, for a program that allocates | 2, 8 |
| `x as i64` to widen an `i32` | nothing: an `i32` goes where an `i64` is wanted; narrowing still takes `as` | 3 |
| `use std::io::*;` | no wildcard imports: every name is imported by name | 2, 11 |
| `dyn Trait` | none: generics, `fn f<T: Trait>(x: &T)`, or an enum | 9 |
| `Rc<T>` | not there: a `Vec` and indices, or an arena | 8 |
| `Arc<T>`, `Mutex<T>`, `thread::spawn` | `Arc<T, Gpa>` from `Arc::new_in(x, gpa)`, `Mutex<T>`, `thread::spawn_in(f, gpa)`; no poisoning, a panic stops the program | 14 |
| comments about what a function expects | `requires` and `ensures`, checked in every build | 13 |
| Cargo, crates | none yet: a program is its files, and C libraries through headers | 11 |
| bindgen | `import "header.h" as c;` | 15 |
| `#[test]`, proptest, cargo-fuzz | `#[test]`, `#[property]`, `#[fuzz]`, run by `volec test` | 13 |

The biggest difference is allocation. Rust has a global allocator that
`Vec::new()` reaches for; vole has none. A function that allocates is
given an allocator, `main` gets the program's from outside, and a
container's type says which allocator it grows from. In return, a
signature tells you whether a function allocates, and a part of a
program can run on an arena or a fixed buffer (chapter 8).

Here's a small program as a Rust programmer would type it on day one:

```vole
fn main() {
    let mut v = Vec::new();
    v.push(1);
    v.push(2);
    let total: i32 = v.iter().sum();
    println!("{} {total}", v.len());
}
```

```err
error[parser error]: 'println!' is a macro call: vole has no macros
 --> main.vl: line 6, column 5
  = help: write `println("{} {total}", v.len())`
```

The `help:` line has the call without its `!`. With that fixed, the
next error is the allocation:

```vole
fn main() {
    let mut v = Vec::new();
    v.push(1);
    v.push(2);
    let total: i32 = v.iter().sum();
    println("{} {total}", v.len());
}
```

```err
error[alloc.no_in]: 'Vec::new' allocates from nothing: pass the allocator, last, to 'Vec::new_in'
 --> main.vl: line 2, column 17
  = help: main takes the allocator: `fn main(gpa: Gpa)`, passed down as a parameter
```

And with an allocator from `main`, it runs:

```vole
fn main(gpa: Gpa) {
    let mut v = Vec::new_in(gpa);
    v.push(1);
    v.push(2);
    let total: i32 = v.iter().sum();
    println("{} {total}", v.len());
}
```

```out
2 3
```

`volec guide` is the language in a couple of pages, written for a
reader who knows Rust.

## From C and C++

Vole is a systems language, compiled to machine code, with no garbage
collector and no runtime to speak of, so a C programmer will find the
performance model familiar. What changes is the safety: the language
is designed so that ordinary code can't have undefined behaviour.

| C or C++ | vole | chapter |
|---|---|---|
| undefined behaviour: signed overflow, a bad index, an uninitialized variable | none in safe code: overflow stops a debug build and wraps in an optimized one, every index is checked, every variable is set before it's read | 3, 15 |
| `malloc` and `free`, `new` and `delete` | allocators passed as parameters; values are freed when they go out of scope | 8 |
| destructors (C++) | `impl Drop`, run at the end of the scope | 4, 15 |
| a pointer and a length, passed separately | a slice, `&[T]`, which carries its length | 7 |
| `char *` strings | `&str`, UTF-8 with a length; `c"..."` for C | 7, 15 |
| `int`, `long`, `size_t` | `i32`, `i64`, `usize`; lengths and indices are `usize` | 3 |
| `#include` and the preprocessor | `mod` and `use`; no macros | 11 |
| exceptions (C++), error codes | `Result` and `?` | 6 |
| templates (C++) | generics, compiled once per type as templates are; bounds are checked at each call | 9 |
| calling C | direct: `import "stdio.h" as c;`, or `extern "C"` | 15 |
| struct layout | unspecified, unless `#[repr(C)]` | 15 |
| `-ffast-math`, optimizations based on UB | none; contracts tell the optimizer facts, and they're checked | 16 |
| `assert`, `NDEBUG` | `assert`, and `requires`/`ensures` contracts, checked in every build | 13 |

Two of these surprise C programmers most. First, indexing is checked:
`v[i]` past the end stops the program with a message and exit status
101, rather than reading some other memory. The compiler removes the
check wherever it can prove `i` is in range, as it can in a simple
counted loop, and `volec query checks` shows the ones left (chapter
16). Second, division by zero isn't undefined: `x / 0` stops the
program with a message, at every level, and signed overflow stops a
debug build and wraps in an optimized one. All of it is defined, so the
optimizer has nothing to assume.

The C-like parts of vole are still there: raw pointers, `malloc`,
unions, calling any C function. They're allowed inside `unsafe`, which
marks the few lines where C's rules apply (chapter 15).

```vole c.vl
// The sum of a slice: the slice knows its length.
fn sum(xs: &[i32]) -> i32 {
    let mut total: i32 = 0;
    for x in xs {
        total = total.wrapping_add(*x); // wraps: defined, unlike C's int
    }
    total
}

fn main(gpa: Gpa) {
    let mut v: Vec<i32, Gpa> = Vec::new_in(gpa); // freed when main ends: no free()
    v.push(2147483647);
    v.push(1);
    println("{} {}", sum(&v), v.len());
    let two = v.len();
    println("{} {}", 7 / two, 7 % two);
    println("{}", v[2]);
}
```

```out exit=101
-2147483648 2
3 1
c.vl:17:19: index out of bounds: index 2, length 2
```

> **If you know C++:** there are no constructors, no inheritance, no
> overloading and no implicit conversions that lose information.
> Methods live in `impl` blocks, interfaces are traits, and a struct is
> built with all its fields named: `Point { x: 1, y: 2 }`.

## From Go

Go and vole share a taste for simple, explicit code and a compiler that
cares about its own speed (chapter 16), but they make the opposite
choice about memory.

| Go | vole | chapter |
|---|---|---|
| a garbage collector | no collector: values are freed at the end of their scope; allocators are explicit parameters | 8 |
| `if err != nil { return err }` | `Result<T, E>` and `?` | 6 |
| `panic`, `recover` | `panic`, with no recover: a panic ends the program, with exit status 101 | 6 |
| goroutines and channels | OS threads (`std::thread`) and channels (`std::sync::mpsc`) | 14 |
| data races found by `-race`, at run time | data races rejected by the compiler | 14 |
| interfaces, satisfied implicitly | traits, implemented explicitly, resolved at compile time; enums for "one of several types" | 5, 9 |
| generics | generics, specialized for each type (no boxing) | 9 |
| slices that share an array | `&[T]` slices, which borrow: they can't outlive what they borrow from, and it can't change while they're in use | 4 |
| `defer` | a guard, a struct whose `Drop` cleans up, made where the defer was (`volec guide memory`); there is no `defer` | 4, 15 |
| `go fmt`, `go vet` | `volec fmt`, and the compiler's own checks | 17 |
| modules and packages | modules (`mod`, `use`, `pub`); no packages yet | 11 |
| zero values | none: a variable has no value until the program gives it one, and reading it before that is an error | 3 |

The trade is this: Go makes memory easy by collecting it for you, at the
cost of a collector running alongside your program. Vole makes you pass
an allocator to code that allocates, which is more typing, and in return
memory is freed at predictable points, you can see in a signature
whether a function allocates, and a part of a program can use an arena
instead (chapter 8).

Here is Go's most common pattern, returning an error up the call
chain, with a few threads sending results down a channel:

```vole go.vl
use std::sync::mpsc;
use std::thread;

// Like Go's strconv.Atoi: the number, or an error to return.
fn parse(s: &str) -> Result<i64, &'static str> {
    match s.parse::<i64>() {
        Ok(n) => Ok(n),
        Err(_) => Err("not a number"),
    }
}

fn sum_of_squares(words: &[&str], gpa: Gpa) -> Result<i64, &'static str> {
    let mut nums: Vec<i64, Gpa> = Vec::new_in(gpa);
    for w in words {
        nums.push(parse(w)?); // Go: if err != nil { return 0, err }
    }
    let total = thread::scope(|s| {
        let (tx, rx) = mpsc::channel_in(gpa);
        for &n in &nums {
            let tx = tx.clone();
            s.spawn(move || {
                tx.send(n * n).unwrap();
            });
        }
        drop(tx);
        let mut sum = 0;
        for x in rx.iter() {
            sum += x;
        }
        sum
    });
    Ok(total)
}

fn main(gpa: Gpa) {
    let good = ["1", "2", "3"];
    let bad = ["1", "two"];
    println("{:?}", sum_of_squares(&good, gpa));
    println("{:?}", sum_of_squares(&bad, gpa));
}
```

```out
Ok(14)
Err("not a number")
```

`thread::scope` waits for every thread started in it before it returns,
like a `sync.WaitGroup` built into the call. Each thread gets its own
`Sender`, and `drop(tx)` drops the original, so that `rx.iter()` ends
when the last thread is done.

## From Python, JavaScript or Java

Coming from a dynamic or garbage-collected language, three things will
feel different at first: types are checked before the program runs,
values are copied or moved rather than shared, and memory is managed
without a collector.

| Python, JavaScript, Java | vole | chapter |
|---|---|---|
| types checked at run time (Python, JavaScript) | types checked by the compiler; most are inferred, so you write few | 3 |
| `b = a` shares one list | `let b = a;` moves a `Vec` into `b`; `a.clone()` copies it | 4 |
| a function can change any object you pass it | only through a `&mut` parameter, and the call says so: `f(&mut x)` | 4 |
| exceptions, `try`/`except` | `Result` and `?`; a `panic` for bugs | 6 |
| `None`, `null`, `undefined` | `Option<T>`: `Some(x)` or `None`, and the compiler makes you handle both | 6 |
| a garbage collector | values are freed when they go out of scope | 8 |
| classes and inheritance | structs with methods, traits for shared behaviour, enums for alternatives | 5, 9 |
| list comprehensions, `map`/`filter` | iterator chains: `v.iter().filter(..).map(..)` | 10 |
| `import` runs the module's code | `use` only names things; modules are compiled together | 11 |
| run by an interpreter or a VM | compiled to a native executable | 1 |

The second row is the one to watch. In Python, after `b = a`, both
names refer to the same list, and a change through one shows through
the other. In vole, a `Vec` has one owner. `let mut b = a;` moves it, and
using `a` afterwards is an error:

```vole
fn main(gpa: Gpa) {
    let mut a: Vec<i64, Gpa> = Vec::new_in(gpa);
    a.push(1);
    let mut b = a;
    b.push(2);
    println("{} {}", a.len(), b.len());
}
```

```err
error[borrowck.use_moved]: 'a' is used here after it moved (moved at main.vl: line 4, column 17)
 --> main.vl: line 6, column 22
  = help: use it before the move, pass a clone where it moves, or take it by reference
  = try: volec edit patch main.vl:4 --old 'let mut b = a;' --new 'let mut b = a.clone();'
```

Following the `try:` line, `let mut b = a.clone();` makes `b` a copy, and
the two lists are independent:

```vole
fn main(gpa: Gpa) {
    let mut a: Vec<i64, Gpa> = Vec::new_in(gpa);
    a.push(1);
    let mut b = a.clone();
    b.push(2);
    println("{} {}", a.len(), b.len());
}
```

```out
1 2
```

Nothing is shared by accident, so a function that reads a value can't
change it behind your back, and two threads can't race on it. When you
do want a function to change a value, `&mut` says so in both the
signature and the call. Chapter 4 explains the whole idea; it's the one
chapter worth reading slowly.
