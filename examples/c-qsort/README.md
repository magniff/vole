# c-qsort

Sorting vole data with the C library's `qsort`, and searching it with
`bsearch`. The records are `#[repr(C)]` structs, so C sees exactly the
layout vole wrote, and the comparison functions are vole functions
with C's calling convention (`extern "C" fn`) that `qsort` calls back. A
small generic wrapper, `c_sort<T>`, sorts a slice of any element type
through C, and the same wrapper sorts plain `i32`s at the end.

## Build and run

From this folder (with `volec` on your `PATH`, or as
`../../target/volec` from a built tree):

```sh
volec main.vl -o c-qsort && ./c-qsort
```

`qsort`, `bsearch`, `strlen` and `strcmp` are in the C library every
program links with, so no extra flags are needed on macOS or Linux.

## Expected output

```
32 bytes per City, 7 cities

by population:
   1. Reykjavik    Iceland       139875    512.4/km2
   2. Oslo         Norway        709037   1561.8/km2
   3. Montevideo   Uruguay      1319108   6562.7/km2
   4. Lima         Peru        10092000   3776.5/km2
   5. Dhaka        Bangladesh  10278882  33547.3/km2
   6. Tokyo        Japan       13960000   6362.5/km2
   7. Lagos        Nigeria     15388000  13137.5/km2
by density, densest first:
   1. Dhaka        Bangladesh  10278882  33547.3/km2
   2. Lagos        Nigeria     15388000  13137.5/km2
   3. Montevideo   Uruguay      1319108   6562.7/km2
   4. Tokyo        Japan       13960000   6362.5/km2
   5. Lima         Peru        10092000   3776.5/km2
   6. Oslo         Norway        709037   1561.8/km2
   7. Reykjavik    Iceland       139875    512.4/km2
by name:
   1. Dhaka        Bangladesh  10278882  33547.3/km2
   2. Lagos        Nigeria     15388000  13137.5/km2
   3. Lima         Peru        10092000   3776.5/km2
   4. Montevideo   Uruguay      1319108   6562.7/km2
   5. Oslo         Norway        709037   1561.8/km2
   6. Reykjavik    Iceland       139875    512.4/km2
   7. Tokyo        Japan       13960000   6362.5/km2

found Oslo: 709037 people
found Lima: 10092000 people
no Atlantis
primes 2..19, sum 77
```

(The city figures are round illustrative numbers, not a census.)

## How it works

### The C side, imported

```tach
import "stdlib.h" as c;
import "string.h" as c;
```

`import "header.h" as c;` runs the system's C preprocessor on the header
and turns its declarations into vole ones under the name `c`: here
`c::qsort`, `c::bsearch`, `c::strlen`, `c::strcmp`. Every header of a
program shares one C module, so both imports use the same `c`. To see
what a header declares: `volec --emit-imports main.vl -o decls.vl`.
`qsort`'s parameters are C's: `void *` is a pointer to `u8`, `size_t`
is `u64`, and the comparator is an `extern "C" fn(*const u8, *const u8)
-> i32` pointer.

### A struct C can read

```tach
#[repr(C)]
#[derive(Clone, Copy)]
struct City { name: *const u8, country: *const u8, population: i64, area: f64 }
```

Vole's own structs have no promised layout. `#[repr(C)]` asks for
C's: fields in declaration order, C's padding and alignment, so an array
of `City` is exactly what a C `struct City[]` would be.
`size_of::<City>()` (32 here) is the element size `qsort` needs. The
names are C strings, `c"Lagos"`: NUL-terminated `*const u8`s in
read-only memory. `Clone, Copy` lets a callback copy a City out through
a pointer.

### Callbacks: `extern "C" fn`

```tach
extern "C" fn by_population(a: *const u8, b: *const u8) -> i32 {
    // UNSAFE: city reads through the pointers.
    // SAFETY: qsort passes two elements of the City array it sorts.
    let (x, y) = unsafe { (city(a).population, city(b).population) };
    // not `x - y`: the difference of two i64 does not fit an i32
    sign(x.cmp(&y))
}
```

Only an `extern "C" fn` can be a C callback: it has C's calling
convention and an unmangled symbol. A plain `fn` is a different type, and
a closure cannot be one at all (it has nowhere to keep what it
captures; C APIs that need state take a `void *` context, see
[c-mixed-build](../c-mixed-build/)). `qsort` passes pointers to two
elements as `const void *`; `city(p)` casts one back to `*const City`
and reads through it, which is unsafe: nothing checks that the pointer
really points at a `City`. Each `unsafe` block says, in the two comments
above it, why it cannot be safe and why it is sound.

### A generic wrapper

```tach
unsafe fn c_sort<T>(items: &mut [T], cmp: extern "C" fn(*const u8, *const u8) -> i32) {
    c::qsort(items.as_mut_ptr() as *mut u8, items.len() as u64, size_of::<T>() as u64, cmp);
}
```

A slice is a pointer and a length (`items.as_mut_ptr()`,
`items.len()`): with `size_of::<T>()` that is all `qsort` needs, for any
`T`. The wrapper is an `unsafe fn` because its contract cannot be
checked: `cmp` must read its pointers as `T`s. Its callers say so with
`unsafe { c_sort(&mut cities, by_population); }`. Passing
`by_population` as a value is safe in itself; what is unsafe is the
reads through the pointers inside it.

### bsearch with a key of another type

```tach
extern "C" fn name_key(key: *const u8, element: *const u8) -> i32 {
    let (wanted, name) = unsafe { (*(key as *const &str), text(city(element).name)) };
    sign(wanted.cmp(name))
}
```

`bsearch(key, base, n, size, cmp)` passes the key as the first argument
and an element as the second. The key does not have to be a `City`: here
it is the address of a `&str` (`&name as *const &str as *const u8`). C
never looks inside it, it only hands it back to the callback, so any
vole value works, `#[repr(C)]` or not. The comparison is byte order
(`str`'s `cmp`), the same order `strcmp` gave `qsort`: `bsearch` needs
the array sorted by the order it searches with. `sign` turns the
`Ordering` into C's negative, zero or positive.

`find` turns C's "a pointer or NULL" into an `Option<City>`:

```tach
if hit.is_null() { None } else { Some(city(hit)) }
```

### C strings to vole text

```tach
unsafe fn text(p: *const u8) -> &'static str {
    let bytes = std::slice::from_raw_parts(p, c::strlen(p) as usize);
    std::str::from_utf8(bytes).unwrap_or("?")
}
```

`from_raw_parts` makes a slice of the C string's bytes (without its
NUL), and `from_utf8` checks that they are text. The slice is unchecked,
hence `unsafe fn`, and its comment states the contract the caller takes
on.

### Printing

```tach
println("  {:>2}. {name:<12} {country:<10} {:>9} {d:>8.1}/km2", i + 1, city.population);
```

Format strings with widths (`>` right, `<` left) and a precision for
floats (`.1`); `cities.iter().enumerate()` numbers the rows.

## C interop rules in brief

- **Declaring C**: `import "header.h" as c;` (the system's own
  declarations) or an `extern "C" { fn name(...) -> T; }` block written by
  hand. Every call to C is `unsafe`.
- **Layout**: only `#[repr(C)]` structs, unions and enums have C's layout;
  give them to C by pointer or by value. Slices, tuples and plain structs
  are not FFI-safe in signatures (the compiler says so).
- **Callbacks**: `extern "C" fn` (not a plain `fn`, not a closure).
- **Pointers**: `void *` is a pointer to `u8`; cast to the real type to
  read. Reading through a raw pointer is `unsafe`; wrap it in a small
  function whose comment states the contract.
- **Strings**: `c"..."` is a NUL-terminated `*const u8`; a `&str` has no
  NUL (pass `.as_ptr()` and `.len()`, or copy it with a 0 after).
- **Linking**: `volec main.vl -o prog` links with `cc` and the C
  library; other libraries and C files go through an object (see
  [c-mixed-build](../c-mixed-build/) and [c-math](../c-math/)).

## Language features

- `import "stdlib.h" as c`, `extern "C" fn`, `#[repr(C)]`, `size_of::<T>()`:
  `volec guide c-interop`
- `unsafe fn` with a stated contract, raw pointer casts and dereferences,
  `// UNSAFE:` and `// SAFETY:` comments: `volec guide unsafe`
- generic functions over `&mut [T]`: `volec guide generics`
- format strings with width, alignment and precision: `volec guide formatting`
- `iter().enumerate()`, `map` and `sum`: `volec guide iterators`
- `Option` for "found or not", `Ordering`: `volec guide conversions`

## Going further

- `slice.sort()` and `slice.sort_by(|a, b| ...)` sort in vole, with a
  closure and no `unsafe`; the C route is for code that already speaks
  `qsort`.
- `qsort_r` would let the comparator take a context pointer, but its
  argument order differs between macOS (BSD) and glibc, which is why this
  example does not use it.
