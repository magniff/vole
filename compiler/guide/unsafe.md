# unsafe

Safe code has no undefined behaviour: indexing is checked, every
variable is initialized, references are checked by the borrow checker,
and arithmetic that overflows or divides by zero panics (at -O0;
overflow wraps at -O1 and above, as Rust's release builds). What can
have undefined behaviour is an *unsafe operation*, allowed only inside
`unsafe { ... }` (an expression: `let x = unsafe { *p };`) or in the body
of an `unsafe fn`, as in Rust:

- calling a C function (an `extern "C"` declaration, an `extern "C" fn`
  pointer) or an `unsafe fn`, `p.add(i)` and `std::slice::from_raw_parts`
  among them;
- dereferencing a raw pointer: `*p`, `(*p).f`, a method called through
  `*p`;
- reading or writing a `static mut` (error `unsafe`, rustc's E0133); a plain `static`
  is safe to read;
- reading a union's field.

`*const T` and `*mut T` are raw pointers: nothing checks what they point
to. Making, passing, comparing and casting one is safe, an integer cast
to a pointer too (`4096 as *const u8`); dereferencing it is not.

## References and raw pointers

`&T` and `&mut T` are checked by the compiler (`guide memory`, the
borrow checker's rules), so using them is safe. A raw pointer is the
escape hatch:

- `&x as *const T` and `&mut x as *mut T` make one, and a `&mut x`
  passed where a `*mut T` is wanted (a C function's parameter) converts
  to it; `c"..."` is a `*const u8` to read-only memory, NUL-terminated.
- In `unsafe` code `&*p` and `&mut *p` make a reference of the pointee:
  the code vouches for it. A raw pointer never becomes a reference by
  itself.
- To read or change a caller's value, take a reference, not a pointer:
  `fn read(x: &i64)`, `fn set(x: &mut i64) { *x = 4; }`. `fix --only
  unsafe` wraps what stays raw in `unsafe { }`.
- `v[i]` on a Vec or a slice is that element, checked; `*p.add(i)` on a
  raw pointer is pointer arithmetic, unchecked and unsafe.

```vole
extern "C" {
    fn malloc(n: usize) -> *mut u8;
    fn free(p: *mut u8);
}

struct Stats { count: i64, sum: i64 }

fn add(s: &mut Stats, x: i64) {     // a reference: checked, safe to use
    s.count += 1;
    s.sum += x;
}

// The caller promises that p points to n valid i64s.
unsafe fn total(p: *const i64, n: usize) -> i64 {
    let mut t = 0;
    for i in 0..n { t += *p.add(i); } // allowed: the body is unsafe code
    t
}

fn main() -> i32 {
    let mut st = Stats { count: 0, sum: 0 };
    add(&mut st, 5);
    add(&mut st, 7);
    let p = unsafe { malloc(3 * 8) as *mut i64 };
    unsafe {
        *p = 1;
        *p.add(1) = 2;
        *p.add(2) = 3;
    }
    let raw = unsafe { std::slice::from_raw_parts(p, 3) }; // valid while p is
    println("{}", st.sum + unsafe { total(p, 3) } + raw[2]);
    unsafe { free(p as *mut u8); }  // raw is not used after
    0
}
```
```out
21
```

Write the contract of an `unsafe fn` in its comment: its callers take it
on. What unsafe code must keep so that the safe code around it stays
defined:

- every reference it hands to safe code (`&*p`, `&mut *p`) points to
  live memory of its type, and every slice it makes is valid for its
  length while it is used;
- it makes no second live alias of a place a `&mut` reference holds
  (the optimizer relies on a `&mut` being the only way to its memory);
  overlapping slices made with `std::slice::from_raw_parts` and
  `from_raw_parts_mut` and passed to a function as its `&[T]` and
  `&mut [T]` are undefined behaviour (the optimizer knows such
  parameters apart): overlapping memory goes through raw pointers
  (`*const T`, `*mut T`), never through two references;
- it changes nothing behind a live `&` reference, through a raw pointer
  either (a `Cell` aside): the optimizer keeps a `&Vec`'s header (its
  pointer, length and capacity) from before a loop, so a push to the
  caller's Vec through a pointer kept in a static may go unseen;
- it makes no pointer into a Vec's header from the Vec's own buffer
  pointer, nor puts a Vec inside its own buffer (the optimizer takes a
  store to an element as never reaching that Vec's header);
- a type whose safe methods manage memory through raw pointers (a
  growable buffer of its own) implements `Drop`: that keeps it from
  being `Copy`, so a copy cannot outlive a reallocation.

## Tools

- `volec fix --only unsafe` puts each unsafe operation outside unsafe
  code into an `unsafe { }` block (the statement around it).
- Each unsafe site says why, in the comments right above it (the
  statement's or item's, no blank line between): `// UNSAFE:` why it
  cannot be safe, `// SAFETY:` why it is sound. `volec check` warns
  about a site without both (`unsafe.unjustified`). (0.25.3)
- `volec query unsafe [FILE...|std]` (0.25.3) lists every unsafe block,
  `unsafe fn` and extern block: `FILE:LINE`, kind, item, class (`ffi`,
  `alloc`, `intrinsic`, `transmute/cast`, `raw-pointer`, `static-mut`:
  through a pointer held in a static, `other`), its comments, and the
  operations inside that need unsafe; `none (unneeded)`: a block with
  nothing unsafe inside, to remove. `--unjustified`, `--summary`
  (counts by class, module, file), `--json`, `--no-std`.
- `volec fix --only unneeded-unsafe` (0.25.4) takes the `none
  (unneeded)` blocks away and keeps their code in its scope; a block it
  cannot open so (one that declares and is not last) is left and
  counted. `--only unneeded-justified` (0.25.5) takes the justified ones
  too, with their `// UNSAFE:` and `// SAFETY:` comments.
- `volec --check-unsafe -O1 prog.vl -o prog` checks raw-pointer
  accesses against the heap blocks at run time (`malloc`/`free`):
  out-of-bounds and use-after-free stop the program with `unsafe access
  ...` and exit 101. Programs run tens of times slower.
- `volec --check-alloc` (0.16) puts every block of Gpa on pages of
  its own: a use after free through raw pointers faults and is reported
  with where the block was allocated and freed;
  bad frees and leaks are reported too (`volec guide memory`). With
  `--check-unsafe`, raw accesses are checked against those blocks.
