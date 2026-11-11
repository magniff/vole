# 8. Allocation: where memory comes from

Since chapter 2, every program that needed memory has started with `fn
main(gpa: Gpa)` and handed `gpa` to whatever made a `Vec` or a
`String`. This chapter explains why, and what else you can hand over
instead.

By the end you'll be able to read a signature and tell whether the
function allocates, pass an allocator down through a program, give a
part of the program an *arena* that frees everything at once, run code
with no heap at all, write functions that work with any allocator, and
find memory bugs in unsafe code with `--check-alloc`.

## Why allocation is explicit

An *allocator* is where memory comes from: the program asks it for a
block of bytes, and gives the block back when it's done. In most
languages there is one allocator for the whole program, and any
function can use it without saying so. Vole has no such global
allocator. A function that allocates gets an allocator as a parameter,
like any other input.

Here are two functions side by side. Save them as `lengths.vl`:

```vole lengths.vl mvs
// Reads the words it's given: allocates nothing.
fn longest(words: [str]) -> usize {
    var best: usize = 0;
    for w in words {
        if w.len() > best {
            best = w.len();
        }
    }
    best
}

// Builds a new Vec: needs an allocator.
fn lengths(words: [str], gpa: Gpa) -> Vec<usize, Gpa> {
    var out: Vec<usize, Gpa> = Vec::new_in(gpa);
    for w in words {
        out.push(w.len());
    }
    out
}

fn main(gpa: Gpa) {
    let words: [str; 3] = ["vole", "mouse", "shrew"];
    println("{} {:?}", longest(words), lengths(words, gpa));
}
```

```out
5 [4, 5, 5]
```

`longest` has no allocator, so it cannot allocate: there is nothing
for it to allocate from. `lengths` takes one, and you can see that from
its first line, without reading its body. The compiler sees it too:

```console mvs
$ volec query effects crate lengths.vl
crate::longest	none
crate::lengths	alloc(Gpa) panic
crate::main	alloc(Gpa) io panic
```

This line of output for each function is its *effects*, the things
calling it may do. `longest` does none of them; `lengths` allocates
from a `Gpa` (and may panic: `push` stops the program if memory runs
out). Chapter 12 is about effects.

Making allocation a parameter buys three things:

- **You can see which functions allocate**, by reading signatures. A
  function deep in a library can't quietly start allocating: it would
  need a new parameter, and every caller would have to pass it.
- **You can choose the allocator** for a part of the program: an arena
  for one request, a fixed buffer for code that must not touch the heap.
  The same function works with any of them, as you'll see below.
- **Code that must not allocate can say so**, and the compiler checks
  it, through every function it calls (chapter 12).

The cost is one more parameter on the functions that allocate, and
`_in` on the names of the calls that do.

> **If you know Zig:** this is very close to Zig's explicit allocators.

> **If you know Rust:** it's like Rust's allocator API (`Vec::new_in`)
> made mandatory, without a global default.

## Gpa, from main

The program's *general-purpose allocator*, the `Gpa`, comes from the
outside: `main` is the only function that gets one, by asking for it
as a parameter. Everything else gets it from `main`, passed down.

Let's write the program this chapter is built around: a tiny request
handler. Each line of input is a request like `GET /users/ada`; the
handler splits the path into its parts and answers. Start
`requests.vl`:

```vole requests.vl
use std::io;

fn split_path(path: &str, gpa: Gpa) -> Vec<&str, Gpa> {
    let mut parts: Vec<&str, Gpa> = Vec::new_in(gpa);
    for p in path.split('/') {
        if !p.is_empty() {
            parts.push(p);
        }
    }
    parts
}

fn handle(line: &str, gpa: Gpa) -> String<Gpa> {
    let mut out = String::new_in(gpa);
    let (method, path) = match line.split_once(' ') {
        Some(pair) => pair,
        None => {
            out.push_str("400 bad request");
            return out;
        }
    };
    let parts = split_path(path, gpa);
    if method == "GET" && parts.len() == 2 && parts[0] == "users" {
        write(&mut out, "200 user {}", parts[1]).unwrap();
    } else {
        write(&mut out, "404 no page {path}").unwrap();
    }
    out
}

fn main(gpa: Gpa) {
    let text = io::read_to_string_in(io::stdin(), gpa).unwrap();
    for line in text.lines() {
        let reply = handle(line, gpa);
        println("{line:<24} -> {reply}");
    }
}
```

```in
GET /users/ada
GET /users/ada/posts
POST /users/alan
hello
```

```out
GET /users/ada           -> 200 user ada
GET /users/ada/posts     -> 404 no page /users/ada/posts
POST /users/alan         -> 404 no page /users/alan
hello                    -> 400 bad request
```

`main` passes `gpa` to `io::read_to_string_in`, which reads the whole
input into a `String`, and to `handle`, which passes it to `split_path`
and to `String::new_in`. Each function that allocates, or calls
something that does, has a `gpa: Gpa` parameter. `Gpa` takes no memory itself (it
is *zero-sized*), so passing it around costs nothing at run time.

Notice what doesn't take the allocator: `parts.push(p)`,
`out.push_str(...)` and the `write`s into `out`. A container remembers the allocator it was made
with, and uses it whenever it grows. Only the functions that make a
new container, the constructors and the `_in` functions, need to be
told. The allocator is always their last argument.

### Forgetting the allocator

If a function uses `gpa` without having one, the compiler can't find
it:

```vole
fn split_path(path: &str) -> Vec<&str, Gpa> {
    let mut parts: Vec<&str, Gpa> = Vec::new_in(gpa);
    for p in path.split('/') {
        parts.push(p);
    }
    parts
}

fn main(gpa: Gpa) {
    let parts = split_path("/users/ada");
    println("{parts:?}");
}
```

```err
error[type error]: undefined variable 'gpa'
 --> main.vl: line 2, column 49
  = help: a 'gpa: Gpa' comes from 'fn main(gpa: Gpa)': add the parameter `gpa: Gpa` to 'split_path' and pass it down
```

`gpa` is just a parameter name, and `split_path` has no parameter by
that name. The fix is to add one, `gpa: Gpa`, at the end of
`split_path`'s parameters, and pass `gpa` at the call.

If you forget it the other way, writing `Vec::new()` the way other
languages do, you get the error from chapter 2, `alloc.no_in`, which
names the `_in` form.

## Drops free memory

Where does the memory go back? Look at the loop in `main` again:

```vole skip
    for line in text.lines() {
        let reply = handle(line, gpa);
        println("{line:<24} -> {reply}");
    }
```

Each round, `handle` makes a `String` and gives it to `main` as
`reply`. At the end of the round, `reply` goes out of scope and is
*dropped*: its memory goes back to the allocator it came from. Inside
`handle`, the same happens to `parts` when `handle` returns. As
[chapter 4](04-value-semantics.md) showed, every owned value is dropped
exactly once, at the end of the scope that owns it, unless it was moved
somewhere else first.

So there is no `free` to call, none to forget, and no way to free a
block twice. The allocator is passed explicitly; giving memory back is
automatic.

> **If you know C:** there's no `malloc` or `free` in safe vole. Drops
> do the freeing, in the right place, every time.

## Arenas: free everything at once

Our handler allocates a little for every request, a Vec of parts and a
reply, and gives it all back at the end of the request. Each of those
blocks is asked for and given back one at a time. When a piece of work
makes many small allocations that all die together, there is a cheaper
way.

An *arena* is an allocator that hands out memory by moving a pointer
forward through a big block, and frees nothing until the end, when it
frees everything at once. Asking an arena for memory costs a few
instructions, and giving it all back costs one.

`arena_scope(&gpa, |a| ...)`, from `std::alloc`, makes an arena (its
block comes from `gpa`), runs the closure with it as `a`, and frees the
arena when the closure returns. Let's try it on a small program first:

```vole
use std::alloc::arena_scope;

fn shout(s: &str, gpa: Gpa) -> String<Gpa> {
    s.to_uppercase_in(gpa)
}

fn main(gpa: Gpa) {
    arena_scope(&gpa, |a| {
        println("{}", shout("hello", a));
    });
}
```

```err
error[type error]: expected 'Gpa', got '&ArenaScope<&Gpa>'
 --> main.vl: line 9, column 38
```

The arena isn't a `Gpa`: `a` is a reference to an `ArenaScope`, a type
of its own. `shout` asked for a `Gpa` specifically, so it can't be
given anything else. We could change it to take the arena's type, but
then it couldn't take a `Gpa`. What we want is a `shout` that takes any
allocator.

## Generic over the allocator

Every allocator type implements a *trait* called `Allocator`, which
lives in `std::alloc`. A trait
names what a type can do, and a function can take "any type with this
trait" with a *type parameter*. Chapter 9 explains both properly; here
is all we need:

```vole
use std::alloc::{Allocator, arena_scope};

fn shout<A: Allocator>(s: &str, a: A) -> String<A> {
    s.to_uppercase_in(a)
}

fn main(gpa: Gpa) {
    println("{}", shout("from the gpa", gpa));
    arena_scope(&gpa, |a| {
        println("{}", shout("from an arena", a));
    });
}
```

```out
FROM THE GPA
FROM AN ARENA
```

`<A: Allocator>` says that `shout` works for any type `A` that is an
allocator, and `a: A` is the allocator it's given. The result is a
`String<A>`, a `String` whose memory comes from an `A`.

That type explains something you've been writing all along. A
container's allocator is part of its type: `Vec<i64, Gpa>` is a Vec on
`Gpa`, and a Vec made inside an `arena_scope` has the arena's type in
that place (`Vec<i64, &ArenaScope<&Gpa>>`: a mouthful, so the examples
below let the compiler work it out). The allocator is always written:
a bare `Vec<i64>` is the error `alloc.default`, and a struct that holds
a Vec names the allocator in its own parameters, `struct Log<A:
Allocator> { lines: Vec<String<A>, A> }`, used as `Log<Gpa>` (the
error is `alloc.field`).

The compiler makes a separate copy of `shout` for each allocator type
it's used with, so the generic version costs nothing extra at run time.

### Functions that only read don't care

A function that only reads a container takes a slice or a `&str`, as in
chapter 7. A slice doesn't say where its elements live, so the function
works on a Vec from any allocator without being generic:

```vole
use std::alloc::{Allocator, arena_scope};

fn total(xs: &[i64]) -> i64 {
    let mut t = 0;
    for x in xs {
        t += x;
    }
    t
}

fn fill<A: Allocator>(v: &mut Vec<i64, A>, n: i64) {
    for i in 1..n + 1 {
        v.push(i);
    }
}

fn main(gpa: Gpa) {
    let mut on_heap: Vec<i64, Gpa> = Vec::new_in(gpa);
    fill(&mut on_heap, 3);
    let from_arena = arena_scope(&gpa, |a| {
        let mut scratch = Vec::new_in(a);
        fill(&mut scratch, 4);
        total(&scratch)
    });
    println("{} {from_arena}", total(&on_heap));
}
```

```out
6 10
```

`fill` changes a Vec, so it names the allocator in the Vec's type and
is generic over it. `total` only reads, so it takes `&[i64]`.

## The request handler on an arena

Now we can give each request an arena of its own. `split_path` and
`handle` become generic over the allocator, and `main` runs each request
inside an `arena_scope`:

```vole requests.vl
use std::alloc::{Allocator, arena_scope};
use std::io;

fn split_path<A: Allocator>(path: &str, a: A) -> Vec<&str, A> {
    let mut parts: Vec<&str, A> = Vec::new_in(a);
    for p in path.split('/') {
        if !p.is_empty() {
            parts.push(p);
        }
    }
    parts
}

fn handle<A: Allocator + Copy>(line: &str, a: A) -> String<A> {
    let mut out = String::new_in(a);
    let (method, path) = match line.split_once(' ') {
        Some(pair) => pair,
        None => {
            out.push_str("400 bad request");
            return out;
        }
    };
    let parts = split_path(path, a);
    if method == "GET" && parts.len() == 2 && parts[0] == "users" {
        write(&mut out, "200 user {}", parts[1]).unwrap();
    } else {
        write(&mut out, "404 no page {path}").unwrap();
    }
    out
}

fn main(gpa: Gpa) {
    let text = io::read_to_string_in(io::stdin(), gpa).unwrap();
    let mut most = 0;
    for line in text.lines() {
        let used = arena_scope(&gpa, |a| {
            let reply = handle(line, a);
            println("{line:<24} -> {reply}");
            a.used()
        });
        if used > most {
            most = used;
        }
    }
    println("at most {most} bytes per request");
}
```

```in
GET /users/ada
GET /users/ada/posts
POST /users/alan
hello
```

```out
GET /users/ada           -> 200 user ada
GET /users/ada/posts     -> 404 no page /users/ada/posts
POST /users/alan         -> 404 no page /users/alan
hello                    -> 400 bad request
at most 104 bytes per request
```

The bodies of `split_path` and `handle` didn't change; only their
signatures did. `handle` uses its allocator twice, for the `String` and
for `split_path`, so it asks for one that can be copied: `A: Allocator
+ Copy`. A `Gpa` can, and so can a reference to an arena. Each
request's parts and reply now come from its
arena, and all of it is freed in one go when the closure returns.
`a.used()` says how many bytes the arena handed out, and the closure
returns that number as the scope's value.

Arenas pay off wherever work comes in units whose memory dies together:
a request, a frame of a game, a file being parsed. Allocation becomes
nearly free, and there's no chance of one forgotten value keeping the
rest alive.

### What can't leave the scope

Everything allocated from the arena is gone when the scope ends. So the
compiler doesn't let anything that still uses the arena out of it:

```vole
use std::alloc::arena_scope;

fn main(gpa: Gpa) {
    let squares = arena_scope(&gpa, |a| {
        let mut v = Vec::new_in(a);
        v.push(1);
        v.push(4);
        v
    });
    println("{}", squares.len());
}
```

```err
error[borrowck.outlives]: lifetime may not live long enough: the lifetime of the closure's parameter 'a' is only the call's, but it flows where a lifetime of the closure's signature, from outside it is required, which lasts longer
 --> main.vl: line 5, column 21
  = help: keep a copy of the value instead of the reference (`*p`, `.clone()`); a closure's result borrows from its parameter only when the bound it is passed for says so (`Fn(&T) -> &T`)
```

The error is long, but its first
line has the point. `a` is a reference to the arena, good only for the
length of the call, and the Vec holds it, so the Vec can't be the closure's result: that is
chapter 4's rule about a reference outliving what it points to. There
are two ways out. Return what you computed from the Vec (`v.len()`, a
total, a plain number) instead of the Vec itself, or copy it to a
longer-lived allocator with `v.clone_in(gpa)` and return the copy. In
the request handler, the reply is printed inside the scope and only a
number leaves it.

For memory that must live longer than one call but still be freed all
at once, `Arena::new_in(gpa)` makes an arena you keep in a variable:
`&arena` is the allocator to hand to containers, and all of its memory
is freed when the arena is dropped. `volec guide allocators` has the
details.

## No heap at all: FixedBuf

Some code must not use the heap: code on a small device, a signal
handler, a request with a hard memory budget. For those, `FixedBuf`
allocates from memory you give it, such as an array on the stack.

Because `handle` is generic, it runs on a `FixedBuf` unchanged. This
version of `main` takes no `Gpa` at all, so nothing in the program can
use the heap. The requests are in the program, since reading stdin
would need an allocator too:

```vole requests.vl mvs
use std::FixedBuf;

fn split_path<A: Allocator>(path: str, a: A) -> Vec<str, A> {
    var parts: Vec<str, A> = Vec::new_in(a);
    for p in path.split('/') {
        if !p.is_empty() {
            parts.push(p);
        }
    }
    parts
}

fn handle<A: Allocator>(line: str, a: A) -> String<A> {
    var out = String::new_in(a);
    let (method, path) = match line.split_once(' ') {
        Some(pair) => pair,
        None => {
            out.push_str("400 bad request");
            return out;
        }
    };
    let parts = split_path(path, a);
    if method == "GET" && parts.len() == 2 && parts[0] == "users" {
        out.push_fmt("200 user {}", parts[1]);
    } else {
        out.push_fmt("404 no page {path}");
    }
    out
}

fn main() {
    let requests: [str; 4] = [
        "GET /users/ada",
        "hello",
        "GET /users/ada/posts",
        "GET /a/b/c/d/e/f/g/h/i",
    ];
    var mem = [0u8; 256];
    for line in requests {
        let fb = FixedBuf::new(&mem[..]);
        let reply = handle(line, fb);
        println("{line:<24} -> {reply} ({} bytes)", fb.used());
    }
}
```

```out exit=101
GET /users/ada           -> 200 user ada (76 bytes)
hello                    -> 400 bad request (15 bytes)
GET /users/ada/posts     -> 404 no page /users/ada/posts (92 bytes)
out of memory
```

`var mem = [0u8; 256];` is 256 bytes on `main`'s stack, and
`FixedBuf::new(&mem[..])` makes an allocator that hands them out. The
`&` is chapter 4's: the `FixedBuf` writes what it allocates into `mem`,
so it holds an inout access to it, and while the `FixedBuf` and what it
allocated are in use, nothing else can read or change `mem`. Each
request gets a fresh `FixedBuf` over the same bytes, because the last
request's reply and parts were dropped at the end of its round.

The fourth request has nine parts, and the Vec holding them needs more
room than the 256 bytes have. A heap would just give it more; a
`FixedBuf` can't, and `push` stops the program with "out of memory" and
exit status 101, like any other panic.

The compiler confirms that no `Gpa` is involved:

```console mvs
$ volec query effects crate requests.vl
split_path<FixedBuf>	alloc(FixedBuf) panic diverge
handle<FixedBuf>	alloc(FixedBuf) io panic diverge
crate::main	alloc(FixedBuf) io panic diverge
```

### Handling running out

When running out is a possibility rather than a bug, ask for the room
first, with `try_reserve`. `parts.try_reserve(1)` returns a `Result`:
`Ok(())` when there is room for one more item, growing the Vec if it
has to, and an `Err(TryReserveError)` when there isn't and the
allocator has no more to give. Here `split_path` uses it, and passes
the error up with `?` (chapter 6):

```vole requests.vl
use std::alloc::{Allocator, FixedBuf, TryReserveError};

fn split_path<A: Allocator>(path: &str, a: A) -> Result<Vec<&str, A>, TryReserveError> {
    let mut parts: Vec<&str, A> = Vec::new_in(a);
    for p in path.split('/') {
        if !p.is_empty() {
            parts.try_reserve(1)?;
            parts.push(p);
        }
    }
    Ok(parts)
}

fn handle<A: Allocator + Copy>(line: &str, a: A) -> String<A> {
    let mut out = String::new_in(a);
    let (method, path) = match line.split_once(' ') {
        Some(pair) => pair,
        None => {
            out.push_str("400 bad request");
            return out;
        }
    };
    let parts = match split_path(path, a) {
        Ok(parts) => parts,
        Err(_) => {
            out.push_str("414 path too long");
            return out;
        }
    };
    if method == "GET" && parts.len() == 2 && parts[0] == "users" {
        write(&mut out, "200 user {}", parts[1]).unwrap();
    } else {
        write(&mut out, "404 no page {path}").unwrap();
    }
    out
}

fn main() {
    let requests = [
        "GET /users/ada",
        "hello",
        "GET /users/ada/posts",
        "GET /a/b/c/d/e/f/g/h/i",
    ];
    let mut mem = [0u8; 256];
    for line in requests {
        let fb = FixedBuf::new(&mut mem);
        let reply = handle(line, &fb);
        println("{line:<24} -> {reply} ({} bytes)", fb.used());
    }
}
```

```out
GET /users/ada           -> 200 user ada (91 bytes)
hello                    -> 400 bad request (15 bytes)
GET /users/ada/posts     -> 404 no page /users/ada/posts (104 bytes)
GET /a/b/c/d/e/f/g/h/i   -> 414 path too long (209 bytes)
```

The long request is now an answer instead of a crash. `main` hands
`handle` a `&fb`: a reference to an allocator is an allocator too, and
one that can be copied.

`String` and `HashMap` have `try_reserve` as well. A plain `push`,
`push_str` or `insert` that runs out of room stops the program.

## Checking memory

Safe vole can't free memory twice, use it after it's freed, or keep a
reference to memory that moved: the compiler rejects those programs, as
you've seen. Two things are still possible. Code in an `unsafe` block
(chapter 15) works with raw pointers, which the compiler can't follow.
And a program can *leak*, keeping memory it never gives back.

`volec --check-alloc` builds a program with a checking allocator that
watches for all of these at run time. Here is a leak: `std::mem::forget`
throws a value away without dropping it, so its memory is never freed.
That's allowed in safe code, but it's rarely what you want:

```vole leak.vl
fn main(gpa: Gpa) {
    let mut log = String::new_in(gpa);
    log.push_str("a reply nobody frees");
    println("{log}");
    std::mem::forget(log);
}
```

```console
$ volec --check-alloc leak.vl -o leak
ok: built leak
$ ./leak
a reply nobody frees
check-alloc: 1 block of Gpa not freed (20 bytes):
  block #1 (20 bytes), allocated at leak.vl:3:5
```

At exit, the checking allocator lists every block that was never
freed, with the line that allocated it: the `push_str` on line 3, where
the `String` first needed memory. A leak doesn't change the exit status.

A use after free in unsafe code is stopped where it happens:

```vole uaf.vl
fn main(gpa: Gpa) {
    let mut v: Vec<i64, Gpa> = Vec::new_in(gpa);
    v.push(7);
    let p = v.as_ptr();
    drop(v);
    let x = unsafe { *p };
    println("{x}");
}
```

```console
$ volec --check-alloc uaf.vl -o uaf
ok: built uaf
$ ./uaf
use after free: block #1 (32 bytes), allocated at uaf.vl:3:5, freed at uaf.vl:5:5
$ echo $?
101
```

`p` is a raw pointer to the Vec's elements, and `drop(v)` frees them.
Reading through `p` afterwards is a bug that, built normally, would
print whatever happens to be in that memory. With `--check-alloc`, the
program stops and tells you which block it was, where it was allocated
and where it was freed.

The checking allocator is slow and uses a lot of memory (every block
gets whole pages of its own), so it's for tests and debugging, not for
the program you ship. `volec test` (chapter 13) runs a program's tests
with it on, so a test that leaks fails.

> **If you know Rust:** `Box::new_in(x, gpa)` is there; `Rc` and `Arc`
> are not. For shared or linked data, use a `Vec` and indexes into it,
> or an arena.

## Summary

- Vole has no global allocator. A function that allocates takes one,
  so its signature says so, and `volec query effects` shows it.
- `main` gets the `Gpa`; pass it down. Constructors and `_in` functions
  take the allocator last; containers remember theirs, so `push` and
  `clone` need none.
- Drops give memory back; there is no `free` to call.
- `arena_scope(&gpa, |a| ...)` gives a piece of work an arena, freed all
  at once; nothing that uses the arena can leave the scope.
- `FixedBuf` allocates from memory you provide, with no heap at all;
  `try_reserve` handles running out.
- `<A: Allocator>` makes a function work with any allocator;
  `Vec<T, A>` and `String<A>` carry the allocator in their types.
- `volec --check-alloc` finds leaks, and memory bugs in unsafe code.

That `<A: Allocator>` was a first look at generics. The next chapter
covers them properly, with the traits that make them work.

## Try it yourself

- Add a request `GET /users`, which answers with `200 all users`.
- Give the arena version a `HashMap` on the arena (`HashMap::new_in(a)`) that counts
  how often each part appears in one request, and print the counts
  inside the scope.
- Make the fixed buffer smaller, 128 bytes, and see which requests
  still fit.
