# `*const T` and `*mut T` as two types (for 0.29)

*Done in 0.29: the rules are front-rust.md's F30.5 (the pointers) and
F30.4 (a slice has no fields). What follows is the plan as it was
written at 0.28.0; the type's word is the `count` of the pointer's type
record, and the fat raw pointers are left one type.*

At 0.28.0 the checker has one raw pointer type: `*const T` and `*mut T`
are the same type, messages and `--emit-imports` print `*T`, and `let
q: *mut u8 = p` of a `p: *const u8` is accepted (rustc E0308). It is a
known divergence of 0.28. This note is the plan for closing it.

## Why not in 0.28

compiler/src writes `*mut` 6714 times and `*const` 234 times; std2
writes 256 and 162. Telling them apart surfaces a few hundred
mismatches in compiler/src that have to be fixed by hand, and 0.29
removes most raw pointers from compiler/src anyway. The same holds for
the `.ptr` and `.len` fields of a slice (about 850 `.ptr` uses in
compiler/src), which rustc does not have.

## The design

- **The type.** A raw pointer is `TyKind::Ptr` with `b == 0`, and that
  test, "b == 0 is raw", is everywhere in the front, the places IR and
  the back ends. Keep it. Constness goes in another word of the type
  record, so that `*const T` and `*mut T` are two type ids and every
  existing raw test still holds for both.
- **Coercion.** `*mut T` where `*const T` is expected coerces (rustc's);
  the other way is an error (E0308). The site is the checker's
  `coerce_ref` (front/check/check_mode.vl). `&mut T` to `*mut T` and
  `&T` to `*const T` stay as they are; `&T` to `*mut T` is already
  refused (D3.6a).
- **Casts.** `as` goes both ways between the two, as in rustc.
- **Methods.** std2's `impl<T> *const T` and `impl<T> *mut T` are
  pattern impls already; each then matches its own type only.
- **Printing.** `*const T` and `*mut T` in messages, `query type`, the
  LSP's hover and `--emit-imports` (front/types.vl buf_type prints `*T`
  today).
- **Mangling and ABI.** One letter for both: no symbol changes, no
  layout change, an old object links with a new one.
- **C.** A header's `const T *` imports as `*const T`, `T *` and `void
  *` as `*mut T`. A `c"..."` literal is `*const u8`, as its bytes are
  read-only; the calls that take it must then say `*const u8`, which is
  most of the hand work in compiler/src.
- **The places IR.** D2.7 already says a write through a `*const T` is
  not allowed where rustc refuses it; with one type that rule could not
  be applied. It applies once the two are apart.

## The order of work

1. The type word, the printer, the coercion and the casts, behind the
   rust edition only; compiler/src still builds because 0.28.0, which
   builds it, reads both spellings as one type.
2. compiler/src and std2 made const-correct with the new compiler
   reporting each mismatch; the chain rule holds at every step, since
   the older compiler accepts either spelling.
3. The C import and `--emit-imports`.
4. `.ptr` and `.len` of a slice refused in the rust edition, once
   compiler/src writes `as_ptr()` and `len()`.
