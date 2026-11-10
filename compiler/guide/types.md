# Types

| type | |
|---|---|
| `i8 i16 i32 i64 isize`, `u8 u16 u32 u64 usize` | integers (no `i128`); an unsuffixed literal is `i32` unless the context or a suffix says (Rust's) |
| `f32`, `f64` | IEEE floats; a literal is `f64` unless the context or a suffix says |
| `bool`, `char` | `true`, `false`; a `char` is a Unicode scalar value, `'a'` |
| `()` | the unit type |
| `!` | never: `return`, `break`, `loop` without `break`, `fn f() -> !` |
| `(A, B)` | tuples: `t.0`; `(x,)` has one element |
| `[T; N]` | an array, a value; `N` a constant expression |
| `[T]`, `str` | a slice, text: behind a reference, `&[T]`, `&mut [T]`, `&str`; `.len()` is a `usize` |
| `&T`, `&mut T` | references, checked by the borrow checker (`guide memory`) |
| `*const T`, `*mut T` | raw pointers (`*mut u8` is also C's `void *`) |
| `fn(A, &B) -> R` | a plain function value |
| `extern "C" fn(A) -> R` | a C function pointer, another type |
| `S`, `E`, `S<T>` | structs, enums, unions, their instances |
| `type X = distinct T` | vole's: a type of its own with T's representation |
| `std::ptr::NonNull<T>` | a `*mut T` that is never null |
| `v16u8 v8i16 v4f32 v2f64 ...` | SIMD vectors: 8, 16 or 32 bytes of signed, unsigned or float lanes (`guide arch`) |

## Numbers

`as` converts between numeric types (and `bool` and `char` to an
integer, a fieldless enum to an integer); `T::from(x)` widens (`guide
conversions`, which also has vole's own widening). An unsuffixed literal
takes the type the context needs (`let b: u8 = 7;`, `x + 1` with `x:
u32`), and must fit: `let b: u8 = 300;` is an error.

Every operation is defined. Overflow is Rust's: `max + 1` panics at -O0
(`attempt to add with overflow`, at the expression) and wraps at -O1
and -O2; `--overflow-checks=on|off` chooses for any level. `x / 0` and
`MIN / -1` panic at every level, and so does a shift by the type's bits
or more at -O0 (at -O2 the amount is taken modulo the bits). Where
wrapping (or a check) is what you mean, say so, at every level:
`x.wrapping_add(y)` (`_sub _mul _neg _shl _shr _div _rem _pow _abs`),
`checked_*` (an `Option`), `overflowing_*` (the value and a bool),
`saturating_*`. Hashes and PRNGs write `wrapping_*`.

```vole
fn main() {
    let max: i64 = i64::MAX;
    let b: u8 = 250;
    let s: u32 = 1;
    print("{} ", max.wrapping_add(1));               // wraps at every level
    print("{} ", b.wrapping_add(10));                // u8 wraps: 4
    print("{} ", max.checked_add(1).unwrap_or(-1));  // None: it overflowed
    print("{} ", b.saturating_add(10));              // 255
    print("{} ", -7 % 3);                            // the sign of the dividend
    print("{} ", s.wrapping_shl(33));                // the amount mod the bits
    print("{} ", 1e30 as i64 - max);                 // float to int saturates
    print("{} ", -1.9 as i64);                       // truncates
    println("{}", (0.0f64 / 0.0) as i64);            // NaN becomes 0
    let (v, o) = 250u8.overflowing_add(10);
    println("{v} {o} {}", i32::MIN);
}
```
```out
-9223372036854775808 4 -1 255 -1 2 0 -1 0
4 true -2147483648
```

Floats are IEEE 754 without fast-math; `1.0 / 0.0` is infinity, and
`NaN != NaN`. Floats have Rust's methods and constants: `x.sqrt()`,
`x.sin()`, `x.abs()`, `x.powi(2)`, `a.max(b)`, `f64::EPSILON`,
`f64::MAX`, `std::f64::consts::PI` (`volec guide math`), in vole, with
no C call.

## Arrays and slices

```vole
fn sum(xs: &[u32]) -> u32 { xs.iter().sum() }
fn main() {
    let mut grid = [[0i64; 3]; 2];      // [[i64; 3]; 2]
    grid[1][2] = 5;
    let copy = grid;                  // arrays are Copy: copied whole
    grid[0][0] = 1;
    let row = &grid[1][..];           // &[i64]: a borrow of the array's row
    let part = &row[1..];             // checked: lo <= hi <= len
    println("{} {} {}", copy[0][0] + part.len() as i64 + part[1], grid.len(), sum(&[1, 2]));
    let t = (1, "a");
    let one = (5,);
    println("{} {} {}", t.0, t.1, one.0);
}
```
```out
7 2 3
1 a 5
```

Indexing (`a[i]`) and slicing (`a[lo..hi]`, `a[..hi]`, `a[lo..]`,
`a[..]`) are checked: out of bounds, the program prints `index out of
bounds: index I, length N` and exits with 101. An index may be any
integer type (vole's; rustc's is `usize`). A function taking `&[T]`
takes `&a` of an array or a Vec. An array is `Copy` when its elements
are.

## References and pointers

A reference, `&T` or `&mut T`, is checked (`volec guide memory`) and
safe; a field or method through one needs no `*` (`r.n += 5`), a value
does (`*r += 1`). A raw pointer (`&x as *const T`, `&mut x as *mut T`,
`std::ptr::null()`) is dereferenced only in `unsafe`, `(*p).n`;
`p.add(i)` is pointer arithmetic, unsafe (`guide unsafe`).

`std::ptr::NonNull<T>` is a `*mut T` that is never null:
`NonNull::new(p)` is `Some` unless p is null, `p.as_ptr()` is the raw
pointer, and dereferencing stays `unsafe`. `Option<NonNull<T>>` is the
field type of a nullable link. Any raw pointer has `p.is_null()`.

## Enums as integers

`#[repr(u8)] enum Level { Low = 1, Mid = 5, High = 9 }` gives each
variant its value: `l as u8`. vole also casts back, checked: `9 as
Level` is `High`, `4 as Level` exits 101 (`invalid value 4 for enum
Level`); rustc has no such cast (E0605).

```vole
use std::ptr::NonNull;

struct Counter { n: i64 }

fn bump(c: &mut Counter) { c.n += 1; }   // a reference: checked, safe

struct Node { value: i64, next: Option<NonNull<Node>> }

#[derive(Clone, Copy, PartialEq, PartialOrd, Debug)]
#[repr(u8)]
enum Level { Low = 1, Mid = 5, High = 9 }

fn main() {
    let mut c = Counter { n: 0 };
    bump(&mut c);
    let r = &mut c;
    r.n += 5;                            // auto-deref: (*r).n
    let p = &mut c as *mut Counter;      // a raw pointer: deref in unsafe
    unsafe { (*p).n += 5; }
    let b = Node { value: 2, next: None };
    let a = Node { value: 1, next: NonNull::new(&b as *const Node as *mut Node) };
    let mut total = 0;
    let mut cur = NonNull::new(&a as *const Node as *mut Node);
    while let Some(q) = cur {
        unsafe {
            total += (*q.as_ptr()).value;
            cur = (*q.as_ptr()).next;
        }
    }
    let l = Level::Mid;
    println("{} {total} {} {} {}", c.n, std::mem::size_of::<NonNull<Node>>(), l as u8, Level::Low < l);
    println("{} {}", std::mem::size_of::<(u8, u32)>(), std::mem::align_of::<u64>());
}
```
```out
11 3 8 5 true
8 8
```

## Layout

`std::mem::size_of::<T>()` and `align_of::<T>()` are constants. vole's
own types have no guaranteed layout (field order, enum tags);
`#[repr(C)]` gives C's. See `volec guide c-interop`.

## Distinct types

vole's: `type NodeId = distinct i64;` is a new type, as Go's defined
types are: T's representation and ABI, but not interchangeable with T.
`as` converts both ways for free (`id as i64`, `n as NodeId`); a
literal is the one implicit conversion. T's operators work between two
values of the type, or one and a literal (`a + 1`, `a < b` is a bool);
mixing it with T is `distinct.mix`, whose `try:` is the `as` to write.
It has T's comparisons, Hash, Debug, Display and Clone, but none of T's
methods (`distinct.method`): `impl NodeId { .. }` adds its own. T is
plain: numbers, bool, raw pointers, and structs, tuples and arrays of
them (`distinct.kind`).

## SIMD vectors

`v4f32(a, b, c, d)`, `v4f32::splat(x)`, `v4f32::load(s, i)` (checked,
`s` a slice) make vectors; `+ - *` work lane by lane on all six types,
`/` on float vectors, `& | ^` on integer ones; comparisons give a mask
(`m.select(a, b)`); `v.lane(i)`, `v.with_lane(i, x)`, `v.sum()`,
`v.store(&mut s, i)`. They are not FFI-safe.

| bytes | signed | unsigned | float |
|---|---|---|---|
| 8 | `v8i8 v4i16 v2i32 v1i64` | `v8u8 v4u16 v2u32 v1u64` | `v2f32 v1f64` |
| 16 | `v16i8 v8i16 v4i32 v2i64` | `v16u8 v8u16 v4u32 v2u64` | `v4f32 v2f64` |
| 32 | `v32i8 v16i16 v8i32 v4i64` | `v32u8 v16u16 v8u32 v4u64` | `v8f32 v4f64` |

An unsigned vector compares unsigned, and its mask is itself (a lane all
ones or 0); 32-byte vectors are two registers where the CPU has no wider
ones. `T::from_bits(v)` reinterprets a vector of the same size, with no
instruction. The CPU's own instructions on them (NEON, SSE, AVX2, CRC,
AES, SHA) are `std::arch`'s: `volec guide arch`.

```vole
fn main() {
    let xs: [f32; 4] = [1.0, 2.0, 3.0, 4.0];
    let s: &[f32] = &xs;
    let v = v4f32::load(s, 0) * v4f32::splat(2.0);
    let mut out = [0.0f32; 4];
    v.store(&mut out[..], 0);
    let m = v < v4f32::splat(5.0);       // a mask, lane by lane
    println("{} {} {:?}", v.sum(), m.select(v, v4f32::splat(0.0)).sum(), out);
}
```
```out
20 6 [2.0, 4.0, 6.0, 8.0]
```
