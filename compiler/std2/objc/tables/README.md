# Objective-C binding tables (`.objc`)

A table lists the Objective-C methods a vole module calls, with their C
types. `tools/objcgen` turns it into that module (the typed
`objc_msgSend` declarations, one wrapper per method, the selector cache),
and checks it against the Objective-C runtime and the SDK's headers. No
`objc_msgSend` prototype is written by hand: a wrong one is silent memory
corruption (docs/design/gpu.md, §2.9 and R1).

| table | generated module |
|---|---|
| `foundation.objc` | `compiler/std2/objc/foundation.vl` (`std::objc::foundation`) |
| `metal.objc` | `compiler/std2/gpu/hal/metal/bindings.vl` (`std::gpu::hal::metal::bindings`) |

```sh
volec tools/objcgen/main.vl -o objcgen
./objcgen compiler/std2/objc/tables/foundation.objc > compiler/std2/objc/foundation.vl   # generate
volec fmt compiler/std2/objc/foundation.vl                                     # the standard style
./objcgen --check compiler/std2/objc/tables/foundation.objc                    # against the runtime
./objcgen --c-check compiler/std2/objc/tables/foundation.objc > c.m && clang -fsyntax-only -x objective-c c.m
```

`tests/gpu/run.sh` runs all three for every table and fails when a
checked-in module differs from its table's output.

## Lines

`#` starts a comment. Lines that are not indented:

| line | meaning |
|---|---|
| `objc PATH` | where `Id`, `Ref`, `Object` and `opt_ptr` are (default `crate::objc`: the tables are std's own) |
| `framework NAME` | opened by `--check` (`/System/Library/Frameworks/NAME.framework/NAME`), so that its classes and protocols are registered |
| `header H` | imported by `--c-check`'s file (`#import <H>`) |
| `use PATH::{A, B}` | copied to the module; A and B become object types the table may use |
| `struct NAME { f: T, g: T }` | a `#[repr(C)]` struct; its size and fields are checked against the header's |
| `const NAME: T = VALUE` | a `pub const`; checked against the header's value |
| `class NAME [: PARENT]` | an Objective-C class; its methods follow, indented |
| `protocol NAME [: P, Q]` | a protocol; its methods follow, indented |

A method line:

```
  [+|-]SELECTOR   (name: T, ...) [-> [own] T[?]] [as NAME]
```

- `+` is a class method; `-` (or nothing) an instance method.
- The parameters match the selector's colons.
- Types: `u8 i8 u16 i16 u32 i32 u64 i64 bool f32 f64` (NSUInteger and the
  Metal enums are `u64`, NSInteger `i64`, BOOL `bool`), `*u8` (any pointer,
  `void *`, `NSError **`; `*mut u8` in the module: the wrapper is then an
  `unsafe fn`), `sel`,
  `class`, a struct of the table, `id`, or a class or protocol name.
- Object results: `own T` is a +1 reference (the `alloc`, `new`, `copy`,
  `mutableCopy` families), returned as `Id<T>`; without `own` it is +0,
  returned as `Ref<'a, T>`: of the receiver's lifetime for an instance
  method, `'static` for a class method (the class or the pool keeps it).
  `?` marks nil as possible: `Option<Id<T>>`, `Option<Ref<'a, T>>`; a
  nullable parameter takes `Option<Ref<'_, T>>`.
- `as NAME` names the wrapper; by default it is the selector in snake case
  (`newBufferWithLength:options:` is `new_buffer_with_length_options`).
  Two methods of one type with one name are an error.

## What is generated

- `pub struct NAME {}`: a marker type per class and protocol, so that
  `Ref<MTLBuffer>` and `Ref<MTLTexture>` do not mix.
- `pub trait NAMEMethods<'a>`: the instance methods, implemented for
  `Ref<'a, NAME>` and for `Ref<'a, X>` of every class or protocol X that
  derives from NAME in the table (`protocol MTLBuffer : MTLResource` gives
  `Ref<MTLBuffer>` `set_label`). Callers write `buf.r().contents()`, with
  the trait imported (`use std::objc::foundation::NSStringMethods;`).
- `impl NAME`: the class methods (`MTLTextureDescriptor::new()`) and the
  init family, whose receiver is an `Id<NAME>` that the call consumes
  (`NSString::init_with_bytes_length_encoding(NSString::alloc(), ...)`).
- One `objc_msgSend` declaration per ABI shape (`msg_v_p_u64_u64`), and a
  static per selector and class (an `Atomic<usize>`), filled on first use
  by `objc::cached_selector` and `objc::cached_class`.

## The checks

- `--check` looks every method up in the runtime:
  `protocol_getMethodDescription` for protocols (required, then optional),
  `class_getClassMethod` and `class_getInstanceMethod` for classes. A
  class's property accessors are often only in the private subclass its
  `alloc` returns (`MTLTextureDescriptorInternal`), and an abstract
  class's in its heirs', so those are tried next. The runtime's encoding
  (`@32@0:8Q16Q24`) is compared with the table's types, qualifiers and
  offsets aside: `objcgen.encoding` on a mismatch, `objcgen.missing` when
  the method is not there.
- `--c-check` writes `_Static_assert`s of every constant's value and every
  struct's size and field types, for clang with the SDK's headers.
