# No heap at all: `FixedBuf`

A reverse-Polish calculator (`3 4 * 5 -` is 7) that reads lines from
stdin, with all of its memory in 512 bytes on `main`'s stack. Its `main`
is `fn main()`: it takes no `Gpa`, so nothing in the program can
allocate from the heap, and the compiler can show it. The numbers'
stack and the line being read are `Vec`s on a `FixedBuf`, an allocator
that hands out the bytes of a buffer you give it; when they are used up,
`try_reserve` returns an error the calculator reports, where a heap
allocation would have grown.

This is the shape of code for places without a heap, or where running
out must be handled rather than fatal: embedded targets, a signal
handler, a request with a hard memory budget.

Every command below is run by `tests/walkthrough/run.sh` in a copy of
this directory, and its output is checked against this file;
`tests/examples/allocators-fixed-buffer.test` runs the program.

## Run it

```console
$ volec main.vl -o rpn && ./rpn < input.txt
1 2 + = 3
3 4 * 5 - = 7
10 dup * = 100
1 +: '+' needs two numbers
2 3: 2 numbers left: an operator is missing
1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 ... = 20
1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 ...: out of memory at depth 32 (the stack has no more room)
1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 ...: out of memory: the line is longer than 160 bytes
7 x *: unknown word 'x'
9 lines, 5 failed; 416 of 512 bytes in use, room for 32 numbers
ok: built rpn
```

Five lines fail, two of them for want of memory: 32 numbers fit on the
stack, and 160 bytes in the line.

## The memory

```vole
fn main() -> i32 {
    let mut line_mem = [0u8; 184];
    let mut stack_mem = [0u8; 328];
    let line_fb = FixedBuf::new(&mut line_mem);
    let stack_fb = FixedBuf::new(&mut stack_mem);
    let mut line: Vec<u8, &FixedBuf> = Vec::with_capacity_in(160, &line_fb);
    let mut stack: Stack = Vec::with_capacity_in(32, &stack_fb);
```

`FixedBuf::new(&mut line_mem)` makes an allocator over the array, and
bumps through its bytes. Both `Vec`s ask for their room once, up front:
160 bytes for the line, 32 numbers (256 bytes) for the stack. A `Vec`
that grows asks its allocator for a new, larger block, and neither
buffer has room for a second one.

`&mut` says that the allocator changes the array: a `FixedBuf` borrows
its memory mutably, and a container on it borrows the `FixedBuf`
(`&line_fb` is the allocator the `Vec` holds). While the line lives,
`line_mem` is not read or written another way, and neither the
allocator nor the line can outlive it (the borrow checker's rules): so
the line and the stack, alive together, each have a buffer of their
own.

## Running out, handled

`push` stops the program when the allocator is out of memory (exit
101). `try_reserve(1)` asks for the room first, and returns a `Result`:

```vole
fn push<'a>(stack: &mut Stack, x: i64) -> Result<(), CalcError<'a>> {
    if stack.try_reserve(1).is_err() {
        return Err(CalcError::TooDeep(stack.len()));
    }
    stack.push(x);
    Ok(())
}
```

The line is read the same way, a byte at a time with `try_reserve`: a
line that does not fit is read to its end and reported. (std's readers
of a whole input take an allocator for what they read: this program
reads stdin with C's `read` into 64 bytes of its own.) A `String` or a
`HashMap` on a `FixedBuf` that is full stops the program, unless its
room was reserved the same way.

## What the compiler can show

```console
$ volec query effects crate
<crate::CalcError as Display>::fmt	panic diverge
crate::push	alloc(FixedBuf) panic
crate::skip	panic
crate::pop2	panic
crate::eval	alloc(FixedBuf) panic
crate::Input::byte	io panic unsafe
crate::Input::line	alloc(FixedBuf) io panic diverge
crate::short	panic diverge
crate::main	alloc(FixedBuf) io panic diverge
```

No function has `alloc(Gpa)`, nor `alloc(extern)` (C's `malloc`):
every allocation is from the `FixedBuf`. `eval` makes it a promise:

```vole
#[effects(alloc(FixedBuf), panic)]
fn eval<'a>(line: &'a str, stack: &mut Stack) -> Result<i64, CalcError<'a>> {
```

The compiler checks the declaration against everything `eval` calls.
A helper three calls down that allocated from a `Gpa` (it would have to
be given one: `main` has none to give), printed, or looped with `while`
would be an error at `eval`, naming the helper. Writing the word
scanner with a `while` loop was such an error: `while` may not
terminate (the effect `diverge`), so `skip` is a counted `for` over the
line.

## Read more

- `volec guide allocators`, sections "Arenas" (`FixedBuf::new`) and
  "--check-alloc" (a `FixedBuf`'s blocks are checked too).
- `volec guide effects`, for `#[effects(...)]`.
- [scoped-arena](../scoped-arena/): growing memory, freed per request.
