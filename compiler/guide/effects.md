# Effects (0.16)

Every function has an inferred effect set: what calling it may do. It
is inferred from the body and everything the body calls, closures and
generic instances included, and never depends on `-O`. A signature
says two things: its parameter types what a call may change of its
arguments (`&mut`) and keep (by value), its effects what it may do
beyond them:

| effect | comes from |
|---|---|
| `alloc(Gpa)`, `alloc(Arena<Gpa>)`, `alloc(extern)` | allocating from that allocator type (`ArenaScope<&Gpa>`: `arena_scope`'s; `extern`: C's malloc); several as one, `alloc(Gpa, Arena<Gpa>)` |
| `io` | a C function that reads or writes: `write`, `read`, stdio |
| `static` | reading or writing a `static mut`, taking its address (not shown in a set: `--why static`; `global` its old name, an alias) |
| `panic` | a checked index or slice, `unwrap`, `as E`, std's panic, an `assert` (but `assert(true)`), a requires (in the caller), an ensures |
| `diverge` | `loop`, a `while` the compiler cannot count, recursion: it may not return (a `for` over a range or a slice returns, and so do std's iterators that end; a panic is `panic`, not `diverge`) |
| `unsafe` | unsafe operations in its own body (not its callers') |

A set is written in that order, `none` for the empty one. Allocation is
explicit (`guide allocators`), so `alloc(Gpa)` without `static` means
"from a Gpa it was given". Running out of memory is `alloc`, not `panic`.

## Asking

```sh
volec query effects total            # crate::total  alloc(Gpa) panic
volec query effects crate::parser    # every function of a module
volec query effects total --why 'alloc(Gpa)'   # the chain of calls down to where it allocates
volec query effects crate --has io        # the functions that do io
volec --print-effects main.vl           # every function's set, then the build
```

`query def`, `show` and `context` print a function's set on its first
line (`effects: alloc(Gpa) panic`); a generic function's sets are its
instances' (`query effects` lists each).

## Declaring

A declaration is an upper bound the compiler checks against the
inferred set; callers still see the inferred one, which may be smaller.

```vole
#[pure]                                   // no alloc, io or static
fn mid(a: i64, b: i64) -> i64 { a + (b - a) / 2 }

#[no_alloc]
fn sum(s: &[i64]) -> i64 { s.iter().sum() }

#[effects(alloc(Gpa), panic)]             // at most these
fn grow(v: &mut Vec<i64, Gpa>) { v.push(1); }

fn apply<F: Fn(i64) -> i64 + effects(panic)>(f: F, x: i64) -> i64 { f(x) }

fn main() -> i32 {
    let a = [1i64, 2];
    println("{}", apply(|x| mid(x, 10), 2) + sum(&a));
    0
}
```
```out
9
```

- `#[pure]`: no `alloc`, `io`, `static` (it may panic, loop and write
  through its `&mut` parameters: they are in the signature, the call
  marks them `&mut x`); `#[no_alloc]`, `#[no_io]`,
  `#[no_panic]` forbid one; `#[effects(...)]` lists what is allowed,
  `#[effects()]` nothing. Several attributes intersect.
- On a trait's function (`#[pure] fn eq(&self, other: &Self) -> bool;`)
  the declaration binds every impl; std's `PartialEq` and `Ord` are
  pure.
- On a C function in an `extern` block it is trusted, as its signature
  is. Undeclared, std's table applies (libm and `mem*`: none, `malloc`:
  `alloc(extern)`, stdio: `io`), else everything.
- A bound `F: Fn(..) -> R + effects(panic)` is checked where `F` is
  given: the error is at the call, naming the closure's effect.
- A call through a `fn` value may call every function of that type
  whose address the program takes.

A broken declaration is one error with where the effect comes from:

```text
sum.vl:3:1: error[effect] 'total' is #[no_alloc], but it allocates from Gpa: 'v.push(x)' at sum.vl:7:9 grows a Vec<i64, Gpa>
help: allocate in the caller and pass the memory in, or remove #[no_alloc]
try: volec query effects total --why alloc(Gpa)
```
