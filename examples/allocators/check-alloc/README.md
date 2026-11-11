# What `--check-alloc` still catches

Safe code cannot use memory after it is freed, free it twice, or keep a
reference into a `Vec` across a `push` that moves its memory: the borrow
checker refuses each at compile time (the first section). Two kinds of
memory bug are left, and `volec --check-alloc` finds both at run time:

- **leaks**, which are safe: a block nobody frees (here a `String` given
  to `std::mem::forget`, which does not drop it);
- bugs in **`unsafe` code**, whose raw pointers the compiler does not
  check: a pointer kept after its block moved, a block freed twice.

`main.vl` has one bug per argument, `leak`, `dangling` and `twice`; with
no argument it runs the correct version of each. Every command below is
run by `tests/walkthrough/run.sh` in a copy of this directory, and its
output is checked against this file;
`tests/examples/allocators-check-alloc*.test` run the program, correct
and with each bug.

## The bugs that are compile errors

The same bugs in safe code: a `Vec` moved into a struct and used through
its old name, a value dropped twice, a slice kept across a `push`, a
`Vec` on an arena's scope leaving the scope.

```console
$ cat > old.vl <<'EOF'
> // EDITION: rust
> use std::alloc::{Allocator, arena_scope};
>
> struct Shelf<'a, A: Allocator> { name: &'a str, counts: Vec<i64, A> }
>
> fn moved_then_used(gpa: Gpa) {
>     let mut counts: Vec<i64, Gpa> = Vec::new_in(gpa);
>     counts.push(3);
>     let shelf = Shelf { name: "fruit", counts };
>     drop(counts);
>     println("{} {}", shelf.name, shelf.counts[0]);
> }
>
> fn dropped_twice(gpa: Gpa) {
>     let counts: Vec<i64, Gpa> = Vec::new_in(gpa);
>     let shelf = Shelf { name: "tools", counts };
>     drop(shelf);
>     drop(shelf);
> }
>
> fn slice_after_push(gpa: Gpa) {
>     let mut v: Vec<i64, Gpa> = Vec::new_in(gpa);
>     v.push(0);
>     let first = &v[..];
>     v.push(40);
>     println("{}", first[0]);
> }
>
> fn slice_out_of_scope(gpa: Gpa) {
>     let s = arena_scope(&gpa, |a| {
>         let mut v = Vec::new_in(a);
>         v.push(7i64);
>         v
>     });
>     println("{}", s[0]);
> }
>
> fn main(gpa: Gpa) -> i32 {
>     moved_then_used(gpa);
>     dropped_twice(gpa);
>     slice_after_push(gpa);
>     slice_out_of_scope(gpa);
>     0
> }
> EOF
$ volec check old.vl
old.vl:10:10: error[borrowck.use_moved] 'counts' is used here after it moved (moved at old.vl:9:17) | help: use it before the move, pass a clone where it moves, or take it by reference | try: volec edit patch old.vl:9 --old 'let shelf = Shelf { name: "fruit", counts };' --new 'let shelf = Shelf { name: "fruit", counts }.clone();'
old.vl:18:10: error[borrowck.use_moved] 'shelf' is used here after it moved (moved at old.vl:17:10) | help: use it before the move, pass a clone where it moves, or take it by reference | try: volec edit patch old.vl:17 --old 'drop(shelf);' --new 'drop(shelf.clone());'
old.vl:25:5: error[borrowck.conflict] cannot borrow 'v' as mutable because it is also borrowed as immutable (borrowed at old.vl:24:18) | help: use the shared borrow before the mutable one, or take it again after
old.vl:31:21: error[borrowck.outlives] lifetime may not live long enough: the lifetime of the closure's parameter 'a' is only the call's, but it flows where a lifetime of the closure's signature, from outside it is required, which lasts longer | help: keep a copy of the value instead of the reference (`*p`, `.clone()`); a closure's result borrows from its parameter only when the bound it is passed for says so (`Fn(&T) -> &T`)
[exit 1]
```

- **Values move.** `Shelf { name: "fruit", counts }` moves `counts`
  into the struct, and `drop(shelf)` moves `shelf` into `drop`; using
  either afterwards, to drop it again or anything else, is
  `borrowck.use_moved`. A value has one owner, dropped once at the end
  of its scope (no `free` to write), and `.clone()` is the explicit way
  to a second, independent copy.
- **References cannot outlive their owner, or be invalidated under
  it.** A slice of the Vec is live until its last use, and a `push`
  while it is live is `borrowck.conflict`; a Vec that allocates from the
  arena's scope and leaves it is `borrowck.outlives`.

`volec guide memory` has the rules.

## The program, correct

```console
$ volec main.vl -o shop && ./shop
a report nobody frees
first 1
shelf: 7
blocks still allocated: 0
ok: built shop
```

## The bugs, built as usual

Built without the flag, each bug does whatever the freed memory happens
to hold. On macOS, one run printed this (another run, or another
machine, prints something else, or crashes):

```text
$ ./shop leak
a report nobody frees
$ ./shop dangling
first 3
$ ./shop twice
shelf: 7
[exit 133]
```

Nothing at all, a wrong number, and a crash in `free` with no message.
(The correct version's last line says 0 here whatever the program
does: only the checking allocator counts its blocks.)

## The bugs, built with `--check-alloc`

```console
$ volec --check-alloc main.vl -o shop-checked
ok: built shop-checked
```

**A leak.** `std::mem::forget` takes a value and does not drop it. It
is safe: nothing can be read or freed wrongly through a value nobody
has. The `String`'s buffer is never freed:

```tach
let mut b = String::new_in(gpa);
b.push_str("a report nobody frees");
println("{b}");
if !fixed {
    std::mem::forget(b);
}
```

A leak is not undefined behaviour, and the program's exit status is
unchanged; the blocks still allocated at exit are listed, with where
they were allocated:

```console
$ ./shop-checked leak
a report nobody frees
check-alloc: 1 block of Gpa not freed (21 bytes):
  block #10 (21 bytes), allocated at main.vl:20:5
```

**A raw pointer kept across a push.** A reference into the Vec kept
across the `push` would be `borrowck.conflict`, as above; the raw
pointer `v.as_ptr()` is not checked. The `push` grows the Vec, which moves its memory
(`realloc`), and the pointer points at the old place:

```tach
let first = v.as_ptr();
v.push(41);
println("first {}", unsafe { *first });
```

The checking allocator gives every block pages of its own and never
reuses an address; freeing a block takes its pages' access away, so the
next read faults, and the fault handler finds the block. Under
`--check-alloc` every resize moves the block, so the bug shows every
time, not only when the allocator happened to move it:

```console
$ ./shop-checked dangling
use after free: block #10 (32 bytes), allocated at main.vl:33:9, freed at main.vl:36:5
[exit 101]
```

The block is the Vec's buffer, allocated by its first `push` (line 33)
and freed by the `push` that moved it (line 36); the blocks before it
are the command line's, which `std::cli` parsed and dropped.

**Freed twice.** `Pair` manages its memory by hand, through a raw
pointer; it is `Copy` and has no `Drop`, so `let shelf = counts;`
copies the pointer, not the memory. Each copy is freed:

```tach
let counts = pair_new(gpa, 3, 4);
let shelf = counts;
println("shelf: {}", unsafe { *shelf.p + *shelf.p.add(1) });
unsafe { gpa.deallocate(counts.block(), pair_layout()) };
unsafe { gpa.deallocate(shelf.block(), pair_layout()) };
```

```console
$ ./shop-checked twice
shelf: 7
double free: block #10 (16 bytes), allocated at main.vl:56:13, freed at main.vl:80:14, freed again at main.vl:84:18
[exit 101]
```

The fix that keeps it from coming back is the one `volec guide unsafe`
gives: a type whose safe methods manage memory through raw pointers
implements `Drop`, and is not `Copy`. Then `let shelf = counts;` moves
it, and its drop frees it once.

**None of them.** A test can ask instead: `gpa.live_blocks()` is the
number of blocks not yet freed, and `gpa.check_leaks()` lists them and
returns false when there are some (both are known only under
`--check-alloc`: `live_blocks()` is 0 and `check_leaks()` true
otherwise). The correct version
prints it:

```console
$ ./shop-checked | tail -1
blocks still allocated: 0
```

What the flag costs: a page or more per block (16 KB on Apple silicon),
a system call per allocation and per free, and on Linux a memory map per
live block (`vm.max_map_count`: the program stops with the command that
raises it). It is for tests and debugging, at any `-O`, not for
production builds. With `--check-unsafe` as well, raw-pointer accesses
are checked against the blocks too, out of bounds included (`volec guide
unsafe`, "Tools").

## Read more

- `volec guide allocators`, section "--check-alloc".
- `volec guide memory`: moves, drops, references and their lifetime.
- `volec guide unsafe`: raw pointers, and what unsafe code must keep.
- [gpa-from-main](../gpa-from-main/) and
  [scoped-arena](../scoped-arena/): `--check-alloc` finding nothing.
