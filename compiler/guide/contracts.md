# Contracts and assertions

A function states what it needs and what it promises between its
signature and its body (0.18). The clauses are checked at run time, as
bounds are: a failure is one line on stderr and exit 101. There is no
release switch; `debug` clauses are the ones only test builds check.

## requires and ensures

```vole
use std::alloc::Allocator;

struct Stack<A: Allocator> { items: Vec<i64, A> }

impl Stack<Gpa> {
    fn top(&self, i: i64) -> i64
        requires 0 <= i && i < self.items.len() as i64 else "no item {i}"
        ensures result == self.items[i as usize]
    {
        self.items[i as usize]
    }

    fn pop(&mut self) -> i64
        requires self.items.len() > 0 else "pop on an empty stack"
    {
        self.items.pop().unwrap()
    }
}

fn main(gpa: Gpa) -> i32 {
    let mut s = Stack { items: Vec::new_in(gpa) };
    s.items.push(4);
    println("{} {}", s.top(0), s.pop());
    println("{}", s.pop());
    0
}
```
```out (exit 101)
4 4
main.vl:24:19: pop on an empty stack: self.items.len() = 0
```

- `requires COND` is checked at the call, after the arguments: a failure
  names the caller's line, the one to change. Several clauses are
  checked in order.
- `ensures COND` is checked at every return of the body, before its
  drops: a failure names the function. `result` is the value
  returned; `old(e)` is e evaluated at entry.
- A failure reads `requires failed: 'COND' of 'f' (FILE:L:C): x = 4, ...`
  (the integer operands' values; a float's in millionths, `d = 707106e-6`,
  0.25.2.1). `else "text"` (a format string,
  `else "bad {x}"`, evaluated only on failure) replaces all before the
  values. Its holes are integers, three at most (`contract.message`): a
  float or text shows as an operand of the condition instead.
- `debug requires` / `debug ensures` are checked only by `volec test`
  (and `--debug-contracts`): for conditions that cost more than the
  function (`debug requires is_sorted(v)`).
- std's own: `Vec::get`, `set`, `swap`, `insert`, `remove`,
  `Option::unwrap`, `Result::unwrap` have requires, so their failures
  name your line.

## What a condition may do

A condition reads the parameters, `result`, `old(..)` and constants, and
calls functions; it must be pure: no io, no allocation, no static
(`contract.effect`, with the `query effects --why` that shows the call),
through a fn value too (what every function of its type whose address
is taken may do).
Owned parameters are read in place, never moved or dropped.

An ensures runs after the body, so (`contract.old`):

- a parameter taken by value that is not `Copy` (a `Vec`, a `String`)
  is gone: write `old(v.len())` (or `old(v.clone())`), or take it by `&`;
- `old(e)` must not keep a borrow (`old(v.as_slice())`) of what the body
  may change: take a `Copy` part, `old(v.len())`.

`result` in a requires, or in an ensures of a function that returns
nothing, is `contract.result`.

## Assertions

`assert(c)`, `assert(c, "message")`, `assert_eq(&a, &b)`,
`assert_ne(&a, &b)` and `debug_assert(c)` are in the prelude, as
functions (Rust's macros; `assert!(..)` is accepted too). std2's
`assert_eq` and `assert_ne` take references: `assert_eq(&(k * 2), &6)`.
A failure prints Rust's message and exits with 101: the message given,
or `assertion failed`, or for `assert_eq` `` assertion `left == right`
failed `` with a `left:` and a `right:` line. It names no line; a
`requires` does.

```vole
fn main() -> i32 {
    let k = "3".parse::<i64>().unwrap_or(0);
    assert_eq(&(k * 2), &6);
    assert(k > 5, "k is small");
    0
}
```
```out (exit 101)
k is small
```

## The failure line

Every run-time check of the compiler prints one line, `FILE:LINE:COL:
message`, and exits with 101: bounds, `as E`, contracts, and std's
requires (`unwrap` of a `None`). A `panic` and std2's assertions print
their message alone, as Rust's do.
`--trace` adds the calls that led there (`volec test` builds with
it; guide debug).

## Contracts and the optimizer

A check passes facts on: after `requires i < v.len()`, `v[i]` in the
body needs no bounds check, where the call is inlined and (0.18.1, -O2)
in a function no caller inlines, since every direct call checks first.
Nothing is assumed: a fact comes only from a check that ran, so a
function whose address is taken (an indirect call does not check its
requires) or that C calls keeps its own checks. Integers wrap where
overflow is not checked (-O1 and above): `i + 4 <= v.len()` holds for
an i near `i64::MAX`, so it does not prove `v[i + 1]`; `x % n` with `requires n > 0` is in `0..n`. `volec
query checks FN` lists the checks left after the optimizer and the ones
it removed.

## Contracts as tests

`volec test` tests every function with an `ensures` as a property:
its inputs generated, its requires filtering them (guide testing).
