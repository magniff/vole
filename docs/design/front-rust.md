# The rust front (0.27.2): the semantics

This is the committed semantics of the rust edition's front end beyond
what 0.27.0 and 0.27.1 gave it (references, lifetimes, elision, `Deref`,
`Index`, reborrows, match ergonomics, `impl Trait` arguments; the borrow
checker of [borrowck.md](borrowck.md)): the typing rules the std2 bodies
and their tests need, the std switch's front side, and the bound-only
rule for generic bodies. It is the contract of three streams: the front
(front272, `compiler/src/front`), std2 (std272, `compiler/std2`) and the
closures and IR work (clos272). Code cites a rule as `// RULE: F4.2`, a
corpus case as `// RULE: F4.2` and, where it diverges from rustc,
`// RUSTC: accepts|rejects CLASS` with a class from §9.

**Status.** Every rule here is gated on the edition: it reads only in a
rust-edition position (`rust_at`, Z1), and an MVS program compiles
exactly as before (the full MVS suite is the witness). A rule whose
front support does not exist at v0.27.1 names the item it changes
(*Anchor*); until it lands, the position reports `edition.later` with
the feature name of `compiler/std2/features.tsv`, as 0.27.0 made it.
F1–F21 follow the plan's §25 numbering; F22–F32 are the rules the std2
gap lists (M1, M2, M3a) needed beyond it (§10 maps every gap to its
rule).

**Reading.** `Fn.m` a definition or rule; `Zn` a std-switch rule (the
plan's §23, its front side here); `D22.3` the bound-only rule (kept
under its borrowck.md id, user decision U1); `FLn` a named strictness
and `FRn` a named permissiveness against rustc (§9). `Γ` is the typing
environment of the item being checked: its type parameters with their
bounds, its `where` clauses, and the impls and traits of the program.
`τ`, `σ` range over types, `T`, `U` over type parameters, `Tr` over
traits, `θ` over substitutions of a header's parameters. A *position* is
a byte offset of a source; `rust_at(p)` says whether it is read in the
rust edition. "Rust's reference §X" means vole does exactly what the
Rust Reference's section says.

## 0. Definitions

**F0.1 (types of the rust edition).** In a rust-edition position the
type grammar is

```
τ ::= i8 | i16 | i32 | i64 | isize | u8 | u16 | u32 | u64 | usize
    | f32 | f64 | bool | char | () | !
    | &'r τ | &'r mut τ | *const τ | *mut τ
    | [τ; n] | [τ] | str | (τ₁, .., τₙ)
    | S<a₁, .., aₙ> | E<a₁, .., aₙ>            a struct or enum instance
    | fn(τ₁, .., τₙ) -> τ | unsafe fn(..) -> τ | extern "C" fn(..) -> τ
    | T                                         a type parameter
    | <τ as Tr<a..>>::A | T::A                  a projection (F8, F11)
    | Ω                                         an opaque instance (D22.1)
```

`char` is new (F1). `[τ]` and `str` are *unsized* (Z9, F21); so is a
parameter declared `T: ?Sized`. Every other type is sized. The
representation is `front/types.vl`'s `TyKind` plus one primitive id
(`TY_CHAR`) and, in a rust file, `Slice` and the `str` form denote the
unsized type rather than MVS's fat view (Z9.1). The lifetime arguments
of a reference or an instance are the places IR's business (borrowck.md
§3–§4): the front binds them (`bind_lifetimes`) and unifies them
positionally with `slots` (F5.2) but draws no conclusion from them.

**F0.2 (traits and impls).** A trait declaration is
`trait Tr<P₁ = d₁, .., Pₖ = dₖ>: S₁ + .. + Sₘ where W { items }` with
items: methods (with or without a default body), associated types
`type A: B₁ + ..;`, associated consts `const N: τ [= v];`. Its
*supertrait closure* `super*(Tr)` is the least set containing every
`Sᵢ` (and every `Self: S` of `W`), closed under the same for each
member (F2). An impl is `impl<Q₁, .., Qₘ> Tr<a₁, .., aₖ> for σ where W
{ items }`; its *header* is `H = (Tr, a₁..aₖ, σ)`; an inherent impl
`impl<Q..> σ where W { items }` has header `σ`. A *goal* is
`G = (Tr, b₁..bₖ, τ)` ("`τ: Tr<b..>`").

**F0.3 (impl application).** Impl `I` with header `H` and parameters
`Q` *applies to* goal `G` iff there is a substitution `θ` of `Q` with
`θ(H) = G` (syntactic unification, projections normalized first, F11.3)
and every bound of `W` and of `Q`'s declarations holds under `θ`
(F0.4), each recursively to depth `MAX_INST_DEPTH` (beyond it: the goal
fails with the depth's error, as instantiation does today). The impl's
*key* is `H` up to renaming of `Q` (so `(Tr, args, σ)`, F13.1, not
`(Tr, σ)`).

**F0.4 (entailment).** `Γ ⊢ τ: Tr<b..>` holds iff one of
- (a) `τ` is a parameter `T` (or `Self` in a trait) and `Γ` declares
  `T: Tr'<b'..>` with `Tr ∈ super*(Tr')` and the arguments of `Tr` in
  `Tr'`'s declaration, under `Self := T`, equal `b..` (F2.2);
- (b) `Γ` has the `where` clause `τ: Tr<b..>` literally, or `τ` is a
  projection `T::A` whose declaration gives `Tr` (F11.2);
- (c) exactly one impl of `Tr` applies to `(Tr, b.., τ)` (F0.3; two
  applying is excluded by F4.2);
- (d) `τ` is a primitive listed in `Tr`'s `#[builtin_impls]` (F15.1),
  or an array type covered by an `#[array_builtin]` template (F15.3);
- (e) `Tr` is a compiler-known marker (`Sized`, F21; `Copy` by
  structure, D8.3; `Send`/`Sync`, borrowck.md §24) and its rule holds.
An unbounded parameter entails nothing (D22.3): in a rust-edition body
F0.4 is the *only* way a trait item reaches a value.

**F0.5 (the method probe).** For `recv.m(args)` with `recv: τ₀`, the
*candidate receiver types* are the autoderef chain `τ₀, τ₁, .., τₙ`
where `τᵢ₊₁ = *τᵢ` through the builtin deref of `&`, `&mut`, `Box` or
through `Deref::deref` (F6.2), stopped when no deref applies, plus, if
`τₙ = [τ; n]`, the unsized `[τ]` (the one unsize step). For each `τᵢ`
in order, the *probe steps* are `τᵢ` by value, then `&τᵢ`, then
`&mut τᵢ`. At a step with receiver type `ρ`, the *candidates* are the
methods named `m` whose declared receiver type (the `self` parameter's,
with `Self` the impl's self type `σ`: `σ` for `self`, `&σ` for `&self`,
`&mut σ` for `&mut self`) is `ρ`, whatever `σ` is: an impl for `S`
offers its `&self` methods at the step `ρ = &S`, an impl for `&S` its
`self` methods there and its `&self` methods at `ρ = &&S`. They are
taken from (i) the inherent impls whose header applies to `σ` (F5),
then, only if (i) is empty, (ii) the traits *in scope* (F9.2) with an
impl applying to `σ` or a bound of `Γ` entailing them. The first step
with a non-empty candidate set decides; its size must be one (F9.3,
`error method.ambiguous`, rustc E0034). The methods "of type `τᵢ`" are
not the rule: a receiver `r: &S` finds `S::m(&self)` at its first step,
`&S` by value, before `impl Tr for &S`'s `m(&self)` (receiver `&&S`, the
`&` step). Rust's reference "Method call expressions".
*Anchor:* `front/check/calls/mod.vl: method_of`, `front/check/rust.vl:
deref_receiver` (today: inherent and impl methods of `τ₀`'s template,
then one `Deref`).

**F0.6 (text is not its bytes, 0.27.5).** In a rust-edition position a
`&str` where a `&[u8]` goes is a mismatch, as rustc's E0308: a string
literal, a `&str` value, or a `&String` (which derefs to `str` only).
MVS's view model (0.20, `coerce_text`) made a `str` its bytes for free.
In the rust edition the bytes are `s.as_bytes()`, and a literal's are
`b".."`. The error's `try:` gives that conversion. A string literal
where a `&str` goes is that `&str` as it is: it is not checked as its
bytes. Two places take a literal's bytes as before, the compiler's own
reads: its writes of a format literal's text in a direct `print`/`write`
(F16.3), and an intrinsic's feature name (`std::arch::has("neon")`). A generic
`&[T]` does not bind `T = u8` from a `&str`. *Anchor:*
`front/check/check_mode.vl: coerce_text`, `check/distinct.vl:
distinct_literal, distinct_mismatch`, `check/interp.vl: direct_call`,
`check/calls/paths.vl: check_direct_call`.
Cases `rust_f_f0_str_not_bytes_err`, `rust_f_f0_string_not_bytes_err`,
`rust_f_f0_str_bytes_ok`.

## 1. Types

### F1 `char`

**F1.1 (the type).** `char` is a primitive (`TY_CHAR`): 4 bytes, align
4, whose values are the Unicode scalar values (`0..=0xD7FF`,
`0xE000..=0x10FFFF`). It is `Copy`, has no slots, and is a distinct
type from every integer. *Anchor:* `front/types.vl` (the primitive ids
`TY_I8 .. TY_NEVER`), `front/traits.vl: builtin_type_symbol`.

**F1.2 (literals).** In a rust-edition position a character literal
`'x'` (one scalar, or an escape `\n \t \r \\ \' \0 \u{..}`) has type
`char`; `b'x'` has type `u8` (F23.2). In an MVS position `'x'` stays
`u8` (`front/check/synth_mode.vl: synth_expr_inner`, `Char => TY_U8`)
and `b'x'` is a parse error. A literal with more than one scalar is a
lexer error in both. *Anchor:* `front/lexer/mod.vl` (`Tok::Char`), the
`Char` arm of `synth_expr_inner`.

**F1.3 (casts).** `c as u32`, `c as u64`, `c as usize` give the scalar
value; `c as u8` truncates (Rust's); `u8 as char` is the only integer-
to-`char` cast (`u32 as char` is `error type.cast`, rustc E0604; the
conversion is std2's `char::from_u32`). No other cast touches `char`.
Rust's reference "Type cast expressions". *Anchor:* `front/check/
synth_mode.vl: synth_cast` (F29).

**F1.4 (patterns and comparisons).** A `char` literal is a pattern
(`match c { 'a'..='z' => .. }`, ranges inclusive), compares by scalar
value (`PartialEq`, `PartialOrd`, `Ord` through `#[builtin_impls]`
listing `char`, F15.1), hashes as its `u32`. *Anchor:*
`front/patterns/mod.vl: check_literal_type`, `front/check/equality.vl`.

**F1.5 (`impl char`).** std2's `impl char { .. }` is an inherent impl on
a primitive (F5.3); its methods probe as any (F0.5). `char` in a
`#[builtin_impls]` list is allowed (F15.1).

### F7 Tuple structs and unit structs

**F7.1 (tuple structs).** `struct S<P..>(v₁ τ₁, .., vₙ τₙ);` (`vᵢ` a
visibility or nothing) declares a struct whose fields are named `0..n-1`
and read as `x.0`, `x.1` (the existing tuple-field syntax,
`synth_tuple_field`); a field without `pub` is private to its module as
a named field is (F24). *Anchor:* `front/parser/items/mod.vl:
parse_struct` (today: `edition.later: tuple_struct`), `front/check/
synth_mode.vl: synth_tuple_field`, `front/check/sealed.vl:
field_hidden`.

**F7.2 (the constructor).** The name `S` (and `Self` in its impls,
F5.4) is, in expression position, a function value of type
`fn(τ₁, .., τₙ) -> S<P..>` with `P..` inferred as a generic function's
(F18); `S(e₁, .., eₙ)` is its call. It is also a pattern
`S(p₁, .., pₙ)` (irrefutable when its sub-patterns are). The
constructor is as visible as the least visible field (Rust's reference
"Tuple structs"). *Anchor:* `front/check/names.vl: synth_name` (today
"is a type, not a value"), `front/patterns/mod.vl: check_pat`.

**F7.3 (unit structs).** `struct U;` declares a struct with no fields.
`U` in expression position is a value of type `U` (the literal `U {}`);
`U` is a pattern matching that value. Generic unit structs
(`PhantomData<T>`) take their arguments from the expected type or a
turbofish (`PhantomData::<T>`, F19.1); with neither and no use that
fixes them, `error type.infer` (F18.2). `PhantomData<T>` has
`slots = slots(T)` (borrowck.md D5.3) and size 0. *Anchor:* `synth_name`
(`is a type, not a value`), `front/check/names.vl`.

### F21 `Sized`, and the unsized types (with Z9)

**F21.1 (the predicate).** `sized(τ)` is false for `[τ]`, `str`, a
parameter declared `T: ?Sized` (anywhere a bound list is read:
generics, impl headers, `where`), and a projection whose declaration
says `?Sized`; true otherwise. Every type parameter is `Sized` unless
`?Sized`; `Sized` as a written bound is accepted and says nothing;
`?Sized` on anything but a type parameter is `error type.unsized`.
*Anchor:* `front/parser/rust.vl: skip_maybe_bound, drop_sized`
(today: both are skipped), `front/parser/items/params.vl: parse_where`.

**F21.2 (where an unsized value may not be).** A value of unsized type
may not be: a local (`let s: str`), a by-value parameter or result, a
field other than the last of a struct (and a struct with an unsized
last field is itself `?Sized`-only, 0.29: `edition.later: dst`), an
array or tuple element, an argument for a `Sized` parameter (`Vec<str>`,
`Option<[T]>`), a cast's result. Each is `error type.unsized` (rustc
E0277 "the size for values of type .. cannot be known"). Allowed:
behind `&`, `&mut`, `*const`, `*mut`, `Box<_, A>`; as a `?Sized`
argument; as the self type of an impl (`impl<T> [T]`, `impl str`,
`impl<T: ?Sized> Borrow<T> for T`). *Anchor:* `front/check/resolve.vl`
(type resolution at a `let`, a param, a field), `front/traits.vl:
check_bounds` (the `Sized` bound), `front/generics/instantiate.vl:
require_bound`.

**F21.3 (`where Self: Sized` on a trait method).** A trait method with
`where Self: Sized` is left out of the items of `Tr` for an unsized
`Self` (F0.5 never offers it; an impl for an unsized type need not
define it; `assert_eq<T: ?Sized>`-style callers cannot call it).
*Anchor:* `parse_where` (today: dropped as saying nothing).

**F21.4 (the fat-pointer intrinsics).** The length and the address of a
place of unsized type are the reference's two words (Z9's `RV_LEN`
and the pointer). std2 spells them as compiler-known functions (Z3's
table, keys `slice_len`, `slice_as_ptr`, `slice_as_mut_ptr`,
`slice_from_raw_parts`, `slice_from_raw_parts_mut`, `str_as_bytes`,
`str_as_bytes_mut`, `str_from_utf8_unchecked`, `size_of_val`,
`ptr_drop_in_place`): whatever body std2 writes for a known item (today
`self.len`, a view's field read, with a "built in" comment) is not
checked and not compiled: the intrinsic stands for it. They are
`<[T]>::len(&self) -> usize`, `<[T]>::as_ptr(&self) -> *const T`,
`as_mut_ptr`, `slice::from_raw_parts(p: *const T, n: usize) -> &'a [T]`
(unsafe), `from_raw_parts_mut`, `str::as_bytes(&self) -> &[u8]`,
`as_bytes_mut` (unsafe), `str::from_utf8_unchecked(&[u8]) -> &str`
(unsafe), `mem::size_of_val<T: ?Sized>(x: &T) -> usize` (`len *
size_of::<elem>()` for a slice, `len` for `str`, `size_of::<T>()`
else), `ptr::drop_in_place<T: ?Sized>(p: *mut T)` (the drop glue of a
sized `T`; each element's for `[T]`; nothing for `str`). No other
function reads the words; a user-defined DST is 0.29 (`edition.later:
dst`). *Anchor:* `front/check/calls/paths.vl: call_function` (the
known-function dispatch, as `format_call`'s), Z3.

### Z9 (type side) `[T]` and `str` are unsized in the rust edition

**Z9.1 (construction).** In a rust-edition position `parse_type`'s
`[T]` and `str` denote the unsized types; `&'a [T]`, `&'a mut [T]`,
`&'a str` are references to them (`Ptr(ref, Slice(T))`-shaped, one
slot `'a` plus `slots(T)`); `*const [T]`, `*mut str`, `Box<[T], A>`
likewise. MVS's `TyKind::Slice` view is untouched: the edition gates the
construction, so one `TyKind` serves both, and a type's *meaning*
(sized view or unsized place) is the edition's of the position that
wrote it. A rust program never meets an MVS view (Z4). *Anchor:*
`front/parser/types.vl: parse_type`, `front/parser/rust.vl: ref_type`.

**Z9.2 (what the type change gives the front).** `impl<T> [T] { .. }`
and `impl str { .. }` are inherent impls on an unsized self type
(F5.3); `impl<'a, T> IntoIterator for &'a [T]`, `PartialOrd for [T]`
apply by F0.3; `&self[..mid]` on a `&str` is F20.3; `&&'a str` is a
reference to a reference; a `&mut [T]` argument reborrows (borrowck.md
Z9); `if c { &s[a..b] } else { s }` has one type `&str` (closing M1's
gap 17). `str_slice_self`, `impl_for_ref`-on-`str` and `unsized_cast`
of `features.tsv` are this rule's.

**Z9.3 (fat casts).** `&[T] as *const [T]`, `&mut [T] as *mut [T]`,
`*mut [u8] as *mut str`, `*const str as *const [u8]`, `&str as *const
str`: a cast between pointer types of unsized pointees keeps both
words; one from an unsized to a sized pointee (`*const [T] as *const
T`) keeps the address and drops the length; sized to unsized is
`error type.cast` (rustc E0606; use `from_raw_parts`). F29.2.


**Z9.1a (a reference impl over an unsized self, 0.27.2.1).** While `&[T]`
is represented as `[T]`, a pattern impl for `&A` (`impl<A: PartialEq<B>,
B> PartialEq<&B> for &A`) matches a slice too; when it and the slice's
own impl both take a call, the slice's own is chosen (rustc reaches it
through the reference impl). *Anchor:* `front/convert/mod.vl:
by_unsized_self`. Case `rust_f_z91_ref_impl_ok`.

**Z9.1b (a reference to a view's place, 0.27.3, FL10's first stage).**
While `&[T]` is represented as `[T]`, `&mut X` in a rust-edition position
is a reference to the view (a thin pointer to its two words, the place
`*self = &self[n..]` writes), not the exclusive view `&mut [T]`, when X
stands for a view (`&[T]`, `&str`) and:
(a) X is written as a reference: `&mut &[u8]`, `&mut &'a str`;
(b) X is `Self` of an impl whose self type is written as one, `impl Read
for &[u8]`, `impl Pattern for &'b str`: its `&mut self`;
(c) X is a type parameter without `?Sized` (F21.1: the parser records
`?Sized` on the parameter, in its list or a `where`), as `R` of `fn
fill<R: Read>(r: &mut R)` with R = `&[u8]`: a Sized parameter is never
`[T]`, so a view it stands for is a reference.
A `?Sized` parameter bound to a view keeps the exclusive view (it may be
`[T]`; telling `R = &[u8]` from `R = [u8]` is Z9.1c's, the second stage). *Anchor:*
`front/check/resolve.vl: view_ref_node, sized_param_node`, `front/parser/types.vl:
parse_ref_rest` (`&mut &[u8]` a TyPtr around the view), `synth_mode.vl:
synth_index` (`self[n..]` through a `&mut &str`). Cases
`rust_f_z91b_mut_ref_view`, `rust_f_z91b_sized_param`.

**Z9.1c (the unsized place type, FL10's second stage; 0.27.3, after
front273's FL6).** Z9.1's meaning gets a type of its own.
- *The type.* `TyKind::Unsized` (a = the view: `Slice(T)` with b = 0,
  or std's str) is the unsized place `[T]`/`str`. It is made only in a
  rust-edition position: `[T]` or `str` written anywhere but directly
  under `&`, `&mut`, `*const`, `*mut` (an impl's self type, a type
  argument `Box<[T], A>`, `NonNull<[u8]>`, `PhantomData<[T]>`, a
  turbofish `size_of_val::<[T]>`), and `Self` of an impl for one.
- *References.* `&U`, `&mut U`, `*const U`/`*mut U` of `U = Unsized(v)`
  are today's view forms (`v`, the exclusive view, the fat raw pointer):
  what codegen sees is unchanged. `&V`/`&mut V` of a view `V` is
  `Ptr(V, kind)`, a thin pointer to the two words, in every position
  (Z9.1b's three cases become one rule).
- *Expressions.* `*r` of a view `r` is a place of type `Unsized(v)`;
  `&*r`, `&r[a..b]`, `&mut *r` give the view forms back (the IR never
  holds an Unsized value: a `let`, a parameter, a result, a field, an
  element of type Unsized is F21.2's `type.unsized`); `&x` of a local
  `x: &[T]` is `Ptr(view)` (`&&[T]`).
- *Inference.* Unifying `&T` with a view binds `T := Unsized(v)`;
  `&mut T` with an exclusive view, `T := Unsized(v)`; `&T`/`&mut T` with
  `Ptr(view, k)`, `T := view`; a by-value `T` with a view, `T := view`.
  A Sized parameter (no `?Sized`, F21.1) bound to `Unsized` is
  `type.unsized` (rustc E0277), so `Vec<[i64]>` is rejected.
- *Impl keys and lookup.* An impl for `[T]`/`str` is keyed by
  `Unsized(v)`, one for `&[T]`/`&str` by the view: both may be written
  (`impl Tr for [T]` and `impl Tr for &[T]`). Method lookup's autoderef
  steps from a view (shared or exclusive) to `Unsized(v)`, whose `&self`
  (`&mut self`) methods take the receiver as it is (the autoref of `*r`
  is `r`). A bound `T: Tr` with `T = Unsized(v)` is met by the impl for
  `[T]`; with `T = view`, by the one for `&[T]` (or a reference pattern
  impl `impl<A: ..> Tr for &A`). Z9.1a's `by_unsized_self` retires: the
  reference impl matches `&&[T]`, not the slice.
- *Layout.* `Unsized` has no size (`size_of::<[T]>()` is
  `type.unsized`, as now); a struct field `*const T`/`*mut T`/`&T` with
  `T = Unsized(v)` is the two-word fat form, so `NonNull<[u8]>` and
  `Box<[u8], A>` are 16 bytes, as rustc's (FL10's last gap).
- *Slots.* `slots(Unsized(v)) = slots(elem)` (no region of its own;
  the reference to it supplies one); `slots(Ptr(view, k))` is the
  general `&'a τ` rule: its own slot, then the view's two.
- *MVS.* Nothing above is made in an MVS position; an MVS program has
  the same type ids, IR and code (the fixpoint proves it).
Closes: `io::copy` with `R = &[u8]` (a `?Sized` parameter), `&T` with
`T = &str` (`Iter<&str>::copied`, `Option<&str>::clone`, `Cell<&str>`),
`impl Tr for [T]` beside `impl Tr for &[T]`, the fat `NonNull`/`Box`.
*Anchor:* `front/types.vl` (the kind, its printing), `check/resolve.vl:
resolve_type`, `generics/instantiate.vl: unify`, `check/calls/mod.vl:
synth_method` (the autoderef step), `traits.vl` (impl keys), `types.vl:
layout_of`, `places/regions.vl: slots_in`.
*Staging (0.27.3, 0.27.4).* Step A (0.27.3): the kind, `unsized_of`,
its printing (its view's spelling) and mangling (`Z<v>`); nothing makes
one. Step B (0.27.4) is one commit: while the view stands for both `[T]`
and `&[T]`, no part of the rule above closes a gap alone. Its scope:
`resolve_type`'s `&X` (the view when X is written `[T]`/`str` or is
`Unsized(v)`, else `Ptr(view)`); `match_type`'s `&T` against a view
(`T := Unsized(v)`); `str`/`[T]` as an impl's self type or a type
argument (`Unsized`), so the impl keys; implements/has_impl over
`Unsized(v)`; synth_method's step from a view to `Unsized(v)`; Z9.1a
retired. Each iteration runs the std2 and rust categories. Failure modes
of a partial step, seen in 0.27.3 (making the str view Copy alone):
`need::<&str>` with `T: Copy` passes, but `words.iter().copied()
.collect_in(..)` on `[&str; 2]` is `'Vec<str, Gpa>::extend' is ambiguous
(Extend<str>, Extend<str>)`, Vec's `Extend<T>` and `Extend<&'a T>`
collapsing to one, and `Copied<Iter<str>>::next` reads `Option<&&str>`
as `Option<str>` (`no method 'copied' on type 'Option<str>'`): both are
`&T` with `T = &str` collapsed to the view.
*As landed (0.27.4, step B).* The rules above hold in every
rust-edition position, with these readings:
- *The probe on a view* (F6.2). The place's `&self` method, inherent or
  of a trait, is at the by-value step on the view; the view's own impls'
  `&self` methods (`impl<T: ?Sized + Ord> Ord for &T`) are at the `&` step.
  So `a.cmp(b)` of two `&str`s is `<str as Ord>::cmp`, `b.as_ref()` of a
  `&str` is `<str as AsRef<[u8]>>`, and `rr.tag()` of a `&&S` is still the
  `&S` impl's (the step is read from the receiver's written type). In
  `Tr::m(x)` (F8.2), x is the `&self` itself, with no autoref, so a view x
  takes the place's. In an instance, a receiver of a parameter's type
  (`k: K`, or a field of type `K`) takes the bound's method, the one the
  generic body named: `<&str as Borrow<&str>>` for `K = &str`. A receiver
  `x: &P` takes P's.
- *Associated functions* of the place are its view's path too
  (`str::from_utf8(b)`).
- *A default body's trait argument.* `PartialEq<[U]>`'s `[U]`,
  substituted for `Rhs` in `ne`'s default, stays the place: its written
  text is kept (`traits.vl: subst_trait_args`).
- *Sized* (F21.1). A parameter without `?Sized` bound to `Unsized(v)` is
  `type.unsized` (E0277), checked with the bounds of every struct, enum
  and function instance (`traits.vl: check_bounds`).
- *A receiver written `*v` of a view* (0.27.5). `*v` is read as the view
  (Z4.1's reading), but as a receiver it is the place `Unsized(v)`, as
  rustc's probe starts from `str`: only the place's methods take it
  (their `&self` the view), never an impl for `&T`. So `(**self).as_ref()`
  in `impl<T: ?Sized + AsRef<U>, U: ?Sized> AsRef<U> for &T` with `T =
  str` is `<str as AsRef<[u8]>>`, in an instance too, with or without an
  expected type (before, with `let b: &[u8] = ..` the reference impl took
  it, called itself, and the program overflowed its stack).
- *An instance's call through a type parameter* (0.27.5). rustc resolves
  a method call once, on the generic body: `(**self).tag()` in `impl<T:
  ?Sized + Tag> Tag for &T` is `<T as Tag>::tag` for every T. Vole checks
  the instance's body, and a receiver whose type as written in the body
  is a bare type parameter T bounded by a trait Tr that declares the
  method takes `<X as Tr>::m`, X the type T stands for: X's own impl of
  Tr or a pattern impl (`impl<T> Tr for &T`), its `&self` borrowing the
  receiver, and never a method found again through X's references or a
  view's place. So with `C = &&str`, `via(r)` of `fn via<C: Tag>(c: C) {
  c.tag() }` is the reference impl twice (21, as rustc; 0.27.4 took
  str's for `(**self)`, 11). The type as written is a local's declared
  type (a parameter's, a `let`'s annotation), `Self` read as the impl's
  self type as written, and `*e` as e's pointee; any other receiver is
  resolved in the instance as before. Case `rust_f_z91c_template_choice`.
  (0.27.6) The same holds for the path forms: `Clone::clone(&a)`, and
  `A::clone(&a)` of a bounded parameter A whose bound declares the method
  with a receiver, which is read as `Clone::clone(&a)`. With `A = &Gpa`
  all three are `<&Gpa as Clone>::clone` (0.27.5 took Gpa's, "expected
  &Gpa, got Gpa", or found no `clone` in `&Gpa`). Cases
  `rust_f_z91c_template_choice_clone` and `_alloc`.
- *`&'a T` of an unsized argument in a signature* (0.27.5, D4.6). With
  `T = Unsized(v)`, `&'a T` is the view `v` whose region is the
  reference's (`'a`, or the elided one, E2/E3's), with T's slots (the
  elements') under it, not a region of T's: the result `&U` of `fn
  as_ref(&self) -> &U` with `U = [u8]` is `&self`'s region, so
  `AsRef::as_ref(*self)` in the impl for `&T` is no
  `borrowck.outlives` (rustc accepts it).
- *`&e` of a view value.* `&e`/`&mut e` of a call's view
  (`&mut "ab".as_bytes()`) is a reference to a temporary view,
  `&mut &[u8]`; `&v[..]` stays the place's view.
- *Slots.* `slots_in` and `slot_variances_in` read `Unsized(v)` as its
  element.
- *std2* gains rustc's forwarding impls that the distinct `&&str` now
  needs: `Borrow<T>` for `&T`/`&mut T`, `AsRef<U>` for `&T`/`&mut T`,
  `AsMut<U>` for `&mut T`, `Eq`/`Ord` for `&A`.
Not closed (0.27.5): an iterator whose Item is a view, in std2's
generic instances (`[&str; 2].into_iter().collect_in(a)`, `Extend::extend`'s
`I: IntoIterator<Item = T>`), is a `borrowck.outlives` between the
parameters' regions (D4.6's ties do not reach a view's slot). It also
fails without step B. Case `rust_b_view_item_collect`.
Not closed either: `Box<[T], A>` and `Box<str, A>`. std2's `Box<T, A>` has
a Sized T, so they are `type.unsized`; an unsized Box needs `T: ?Sized` on
the Box and its impls (0.27.5). A `NonNull<[u8]>` is two words.
*Cases:* `rust_f_z91c_ref_of_view`, `rust_f_z91c_impl_place_and_ref`,
`rust_f_z91c_unsized_param`, `rust_f_z91c_vec_unsized_err`,
`rust_f_z91c_fat_nonnull`.
### F23 Literals

**F23.1 (string literals).** `"…"` has type `&'static str` in a
rust-edition position (MVS: the `str` view). It unifies with an expected
`&'r str` for any `'r` (`'static ⊒ 'r`), with a parameter `P` bounded
`P: Pattern` or `T: Display` (F0.4 on `&str`), and with `&[u8]` never
(`.as_bytes()`). An unannotated `let s = "";` is `&'static str`. *Anchor:*
`synth_expr_inner` (`Str`), `front/check/mod.vl: mismatch_help`.

**F23.2 (byte literals).** `b'x'` is `u8` (its escapes `\n \t \r \\ \'
\0 \xHH`; `\u{..}` is an error); `b"…"` is `&'static [u8; n]` (and
unsizes to `&[u8]` at a `&[u8]` expected type, F0.5's one unsize step
applied to coercion sites: a `let` with an annotation, an argument, a
return). (0.27.3: `b"…"` parses, typed `&[u8]`, FL12.) `volec fmt` keeps
`b'x'` and `b"…"` as one token. *Anchor:*
`front/lexer/mod.vl: lex_number` (the `b` prefix), `front/lexer/
strings.vl`, `tools/fmt`.

**F23.3 (the empty array literal).** `[]` takes its type from the
expected type when there is one (`&mut []` against `&mut [T]`:
`[T; 0]`, then the unsize step); without one, `error type.infer` as
today. *Anchor:* `synth_mode.vl: synth_array` ("cannot infer the type
of an empty array").

**F23.4 (character literals).** F1.2.

**F23.5 (octal literals).** (0.27.6) In a rust-edition file an integer
literal may be written `0o` then octal digits and `_` (`0o644`,
`0o7_55`, `0o17u8`): its value in base 8, typed like any integer
literal (F18.3) and suffixed like one. A digit `8` or `9` among its
digits is rustc's error, "invalid digit for a base 8 literal" (`0o8`,
`0o78`); `0o` with no digit after it, "expected octal digit after
'0o'" (rustc E0768). Only the lower-case `o` (rustc refuses `0O`). `{:o}` formats an integer in base
8 (`{:#o}`: `0o` first). MVS files keep refusing `0o` (an invalid
suffix on `0`). *Anchor:* `front/lexer/mod.vl: lex_number`,
`lex_radix_digits`. *Cases:* `rust_f_f23_octal`.

### F29 Casts

**F29.1 (what `as` does, by kinds).** In a rust-edition position
`e as τ` is allowed exactly for Rust's reference "Type cast
expressions" table: numeric ↔ numeric (integers truncate or extend,
floats round toward zero and saturate), `bool`/fieldless enum →
integer, `u8` → `char`, `char` → integer (F1.3), `*const T` ↔ `*mut T`,
pointer ↔ pointer of sized pointees (any `T`, `U`), `&T` → `*const T`,
`&mut T` → `*mut T` (or `*const T`), `fn` item or pointer → `fn`
pointer or `usize`, **integer ↔ raw pointer (`usize as *mut T`, `p as
usize`): safe**, as Rust's (the deref is what is unsafe; closes M2's
gap 13, where MVS makes the cast itself unsafe). Everything else is
`error type.cast` (E0605/E0606). *Anchor:* `synth_cast` ("cannot cast
..", today requiring `unsafe` for int→ptr), `front/check/unsafety.vl`. (0.27.3:
`&T as *const U` with `U` not `T` is an error, rustc E0606; it read a
`T` as a `U`.) (0.27.4: `e as *const _` and `e as *mut _` take the
pointee from the operand, `T` of a `&T`, `&mut T`, `*const T` or `*mut
T`; of any other operand, an integer, the pointee is not known: `error
type.cast`, rustc E0641 "cannot cast to a pointer of an unknown kind".)

**F29.2 (fat pointers).** Z9.3.

**F29.3 (no implicit numeric conversion).** As today: no `as` is
inserted; an integer literal takes its type from its context (F18.3).
There is no `u128`/`i128` in 0.27.2: the names are `edition.later:
u128 (0.29)`.

### F30 Places through raw pointers

**F30.1 (`*p` is a place).** For `p: *const T` or `*mut T`, `*p` is a
place of type `T` (readable, and writable through `*mut`), legal only
in an `unsafe` block or fn (today's rule); its projections `(*p).f`,
`(*p)[i]`, `(*p).0` are places of the field's type. `&(*p).f` is a
**reference** `&'r T_f` (`&mut (*p).f` a `&'r mut T_f` for `p: *mut`),
`'r` a fresh region unrelated to any loan (borrowck.md D3.8's raw-deref
rule: the reference is as trusted as the `unsafe` that made it), not a
raw pointer (today: `&(*p).f` of a raw pointee is a raw pointer, M3a's
gap 1). *Anchor:* `front/check/synth_mode.vl: synth_unary` (the `&` of
a raw deref), `front/check/rust.vl: note_const_ptr, const_write`.

**F30.2 (`&raw`).** In the rust edition `&raw const P` and `&raw mut P`
(P a place) are the raw-pointer forms, `*const T` and `*mut T` for P of
type T: the address, with no reference made and no loan (borrowck.md
R1, `BK_RAW`); `raw` is a contextual word, an identifier elsewhere. `&raw
mut P` needs P mutable as `&mut P` does (a `let` without `mut`: rustc
E0596). A value that is not a place is an error (rustc: "cannot take
address of a temporary", E0745). No `unsafe` is needed beyond P's own:
the deref in `&raw const (*p).field`, a `static mut` S's use in `&raw
const S.n` (F19.6, E0133); the bare `&raw mut S` of a `static mut` is
safe, as rustc's. It is how a `static mut` is reached (borrowck.md
D6.2.5): `let p: *mut T = &raw mut S;`. *Anchor:*
`front/parser/exprs.vl: parse_prefix` (NODE_RAW_BORROW on the `&`),
`front/check/rust.vl: raw_borrow` (from `synth_unary`),
`places/build.vl: ref_kind, emit_ref`.

**F30.3 (no indexing of a raw pointer).** In a rust-edition position
`p[i]` and `p[a..b]` with `p: *const T` or `*mut T` are `error type`
("cannot index into a value of type `*mut T`", rustc E0608), as Rust's:
an element is `*p.add(i)` (`<*const T>::add`, unsafe, and `offset`,
`read`, `write`), a run of them `slice::from_raw_parts(p, n)` (F21.4).
A reference to an indexable type (`&[T]`, `&Vec<T, A>`, `&[T; N]`) is
indexed through, as before. MVS keeps its raw-pointer indexing.
*Anchor:* `front/check/synth_mode.vl: synth_index`.

**F30.4 (a slice has no fields, 0.29).** `s.len` and `s.ptr` of a
slice (`[T]`, through any reference) are `error type` ("a slice has no
field 'len'", rustc E0609/E0615), as is any other field name: the
length is `s.len()`, the pointer `s.as_ptr()` (a `*const T`) or
`s.as_mut_ptr()` (a `*mut T`, of a `&mut [T]`). Each error carries its
exact fix (`len()`, `as_ptr()`), which `volec fix --suggested` writes.
The two words of the reference are read as fields only where the
methods are made: `len`, `as_ptr` and `as_mut_ptr` of std::slice, and
the nodes the checker makes itself (a `for` over a slice, `==` of two).
*Anchor:* `front/check/synth_mode.vl: synth_field, in_std_slice`.

### F32 Unsize coercion

**F32.1 (the one coercion).** At a *coercion site* — a `let` with an
annotation, a call's or method call's argument (after F6.2's receiver
adjustment), a `return` or tail against the return type, a struct
literal's field, an array literal's element against an expected
element type, a cast's operand — a value of type `&[T; N]` is coerced
to an expected `&[T]`, `&mut [T; N]` to `&mut [T]`, `*const [T; N]` to
`*const [T]`, `Box<[T; N], A>` to `Box<[T], A>` (the fat pointer gains
the length `N`). So `self.write(&[i])` against `write(&mut self, bytes:
&[u8])` typechecks (M3a's gap 14), and `b"…"` reaches a `&[u8]`
(F23.2). No other unsize coercion (`&S` to `&dyn Tr`: no `dyn`; a
struct's last field: 0.29). Coercion never applies to a generic
parameter's inference (`f(&[1, 2])` with `f<T>(x: T)` gives `T = &[i64;
2]`, as rustc). *Anchor:* `front/generics/mod.vl: check_arg,
check_call_arg`, `front/check/mod.vl: mismatch_error`, `front/check/
widen.vl`.

**F32.2 (deref coercion through Deref, 0.27.2.1).** At a coercion site a
shared reference `&S` where `&U` (or the view `&[T]`, `&str`) is
expected, with `U` reached from `S` by `<_ as Deref>::Target` steps (at
most 4), is `n.deref()` that many times: `f(&b)` with `b: Box<i64, A>`
and `f(x: &i64)`. At a generic call, a parameter `&P` whose own
parameters the argument `&S` does not bind is unified with the first
`&D` of the chain that binds them (`sum(rest)` with `rest: &Box<List<A>,
A>` and `sum<A>(l: &List<A>)`), as rustc's coercion of an argument
against `&List<?A>`. *Anchor:* `front/check/rust.vl: deref_coerce,
deref_projection`, `front/generics/instantiate.vl: deref_unify`. Case
`rust_f_f32_deref_coerce_ok`.

### F33 Raw pointers hold no allocator

**F33.1 (alloc.field through a raw pointer).** In a rust-edition
position the allocator rules (grammar.md "Allocators": `alloc.field`)
do not look through a raw pointer: a field `*mut Out<T, CHeap>` or
`*const Node<Gpa>` holds no allocator, so its struct need not name one
(std2's `thread::ScopedJoinHandle { out: *mut Out<T, CHeap> }`). A raw
pointer carries no ownership: what it points to is freed by whoever
made it, through the allocator that code names. References (`&'a
Arena<P>`), `Box<T, A>`, arrays, tuples and the other parts are looked
through as before; MVS is unchanged. *Anchor:* `front/check/
alloc_rules.vl: field_allocator`.

### F34 `const fn`

**F34.1 (the qualifier).** (0.27.6) In a rust-edition file `const fn`,
`const unsafe fn` and `const extern "C" fn` declare a function as
`fn`, `unsafe fn` and `extern "C" fn` do: at the top level and in an
inherent impl or a trait impl, after any visibility (`pub const fn`); a
block holds no item in vole, `const fn` or other. The qualifier changes nothing in the function, which is called
at run time like any other. A call of it is constant where a call of a
function whose body is one expression already is: a static's
initializer (consteval.vl's constant constructors). rustc's checks of a
`const fn` body (E0015: a non-`const` call in it) are not made. A
`const` before anything else is a constant, as before (`const N: τ =
v;`), and `*const fn()` is a raw pointer type. *Anchor:*
`front/parser/rust.vl: skip_const_fn`, `front/parser/items/mod.vl:
parse_item, parse_impl`. *Cases:* `rust_f_f34_const_fn`.

**F34.2 (constants of other types).** (0.27.6) In a rust-edition file
a `const C: τ = v;` whose type is not a number, a `bool`, a fieldless
enum or a string, or whose value calls a function (`const N: u64 =
double(21);`, `const SECOND: D = D::new(1, 0);`), is made at each use:
`C` stands for a copy of `v`, checked against `τ` in the constant's
module, as an inherent impl's constant already is (F3.1:
`assoc.vl: inherent_const_value`). So each use is a fresh value, as in
Rust: two uses of a constant with a Drop field are two values, each
dropped once, and a change to one does not reach the other. Rust
evaluates `v` at compile time and copies the result; vole evaluates it
at each use, which gives the same values because a `const fn`'s body is
deterministic. Such a constant is not a compile-time value yet: as an
array length or in a pattern it is an error that says so (rustc accepts
both). A constant defined through itself is an error at its use.
The copy is read as at the constant: no local and no type parameter of
the use is seen, so `let double = |x| x;` at a use of `const N: u64 =
double(21);` does not take the place of the function `double`. The
same holds for an inherent impl's constant (`impl D { const T: u64 =
double(22); }`), whose copy 0.27.5 resolved in the use's scope: a
local `double` was called there, which was wrong code. (`lookup_local`
reads the env from `env_floor` up, and the copy is checked with no
type parameter bound beyond the impl's.)
0.27.5 refused such a constant ("constants must be integers, floats,
bool or string literals"). MVS is unchanged. *Anchor:*
`front/check/collect.vl: collect_const_types` (state 3),
`front/check/names.vl: inline_const`, `front/consteval.vl:
const_value, eval_array_len`, `front/assoc.vl: inherent_const_value`,
`front/check/mod.vl: lookup_local`. *Cases:* `rust_f_f34_const_values`,
`rust_f_f34_const_len_err`, `rust_f_f34_const_hygiene`.

## 2. Traits

### F2 Supertraits

**F2.1 (declaration).** `trait A: B₁ + .. + Bₘ` and `trait A where
Self: Bᵢ` declare `Bᵢ ∈ super(A)`; `super*(A)` is the closure (F0.2). A
cycle (`A: B`, `B: A`) is `error trait.cycle` (E0391). A supertrait may
be generic (`BorrowMut<B>: Borrow<B>`): its arguments are substituted as
written. *Anchor:* `front/parser/items/mod.vl: parse_trait` (today
`skip_item_bounds("supertrait")`, `edition.later`), `front/traits.vl:
TraitInfo` (gains the supertrait list), `front/convert/mod.vl:
collect_trait_params`.

**F2.2 (what a bound implies).** `T: A` in `Γ` entails `T: B` for every
`B ∈ super*(A)` (F0.4a): `B`'s methods, associated types and consts are
available on `T` in the body and in lookup (`T::Item` with
`T: DoubleEndedIterator`), and a parameter bounded `T: A` satisfies a
parameter bounded `U: B`. *Anchor:* `front/traits.vl: satisfies,
require_in_bounds, bounded_param_of_type`, `front/assoc.vl: projection`.

**F2.3 (what an impl must prove).** `impl<Q..> A for σ where W` is
accepted only if `Γ_impl ⊢ σ: B` (F0.4 under `Q`, `W`) for every
`B ∈ super(A)`, checked at the impl's position: `error trait.unmet`
(E0277, "the trait bound `σ: B` is not satisfied"), with `try:` naming
the missing impl. The check runs after every impl of the program is
collected (so order is free) and before bodies. *Anchor:*
`front/traits.vl: collect_impl, check_impl_signatures`.

**F2.4 (upcasting to a supertrait's items).** `A::m` for `m` an item of
`B ∈ super*(A)` resolves as `B::m` (Rust's: a supertrait's items are
not re-exported by the subtrait's name, so `A::m` with `m` only in `B`
is `error name.unknown`; F8.2 says `<τ as B>::m`). Vole follows Rust.

### F3 Associated consts

**F3.1 (declaration and definition).** `const N: τ;` or `const N: τ =
v;` in a trait; `const N: τ = v;` in an impl (its type must equal the
trait's, with `Self` substituted; a trait default stands where the impl
omits it; an impl may not add a const the trait lacks, E0438, nor
omit one without a default, E0046). `v` is a constant expression
(`consteval.vl`'s language) which may name `Self::M` and other consts
(no cycle, E0391). An inherent `impl σ { pub const N: τ = v; }` is
allowed likewise. *Anchor:* `front/parser/rust.vl: skip_assoc_const`
(today `edition.later`), `front/assoc.vl: collect_trait_assoc,
collect_impl_assoc` (the assoc-type table, extended with a const kind),
`front/consteval.vl`.

**F3.2 (use).** `τ::N`, `Self::N`, `T::N` (with `T: Tr` declaring `N`,
F0.4a), `<τ as Tr>::N` (F8.1) are expressions of type `τ_N[Self := τ]`,
constant per instance: folded when `τ` is concrete, a parameter of the
instance otherwise (so usable in a pattern, an array length only with
const generics: `[T; Self::N]` is `edition.later: const_generics`
(0.29)). Resolution: inherent consts first, then the traits in scope
(F9.2); ambiguity is `error method.ambiguous` with `try: <τ as Tr>::N`.
*Anchor:* `front/check/calls/paths.vl: synth_path, path_target`,
`front/assoc.vl: assoc_value`.

### F4 Blanket impls and coherence

**F4.1 (application).** An impl applies to a goal by F0.3, with the
header's self type any type pattern (`T`, `&'a T`, `Vec<T, A>`,
`[T]`, `(A, B)`, `fn(A) -> R`, `*const T`), not only a struct or enum
template: `impl<T: ?Sized> Borrow<T> for T`, `impl<I: Iterator>
IntoIterator for I`, `impl<T, U: From<T>> Into<U> for T`. *Anchor:*
`front/traits.vl: ImplInfo` (gains a header type node and the bound
list), `has_impl`, `front/assoc.vl: impl_covers`, `front/parser/
rust.vl: later_impl` (today drops these).

**F4.2 (the overlap check).** After collection, for every pair of impls
`I₁`, `I₂` of one trait `Tr` whose headers *unify* (there is `θ` over
`Q₁ ∪ Q₂`, disjointly renamed, with `θ(H₁) = θ(H₂)`), the pair
*overlaps* iff the bounds of both can hold for some assignment of the
unified parameters: `W₁ ∧ W₂` under `θ` is *satisfiable*. Satisfiability
is decided by: a bound on a concrete type by F0.4 (closed world: the
program's impls); a bound `T: Tr` on a still-free parameter by the
existence of *any* impl of `Tr` whose header unifies with `T` under the
current `θ` (recursively, depth-bounded); two bounds `T: A`, `T: B` on
one free parameter are jointly satisfiable iff some type pattern unifies
with an impl of each (checked pairwise). Where the procedure cannot
decide (the depth bound, a projection it cannot normalize), the pair
**overlaps** (strict). An overlapping pair is `error trait.overlap`
(E0119) at the second impl, naming the first and the witness `θ`. There
is no specialization and no orphan rule (one program, FR1). Examples:
`impl<T: ?Sized> Borrow<T> for T` and `impl<A> Borrow<str> for
String<A>` do not unify (`T = str` forces the self type `str ≠
String<A>`); `impl<I: Iterator> IntoIterator for I` and `impl<'a, T>
IntoIterator for &'a [T]` unify at `I = &'a [T]` and the bound `&'a [T]:
Iterator` has no impl: no overlap; `AsRef<str>` and `AsRef<[u8]>` for
`str` have different trait arguments: no overlap (F13). *Anchor:*
`front/traits.vl: collect_impls` (a new pass `check_overlap` after it).

**F4.3 (selection at a goal).** With F4.2 holding, at most one impl
applies to any ground goal; selection is F0.3 over all impls of `Tr`
(by trait, then header unification). A goal with a free parameter (in a
template body, D22.3) is answered by `Γ` alone (F0.4a–b), never by
searching impls. *Anchor:* `has_impl, implements` (today: keyed by
`(tr, ty)` or `(tr, tpl)`).

### F5 Inherent impls on an instance and on primitives; `Self`

**F5.1 (headers).** `impl<Q..> σ where W { .. }` with `σ` any sized or
unsized type pattern: a template's instance (`impl<'a, T> Option<&'a
T>`, `impl<K, V, A: Allocator> HashMap<K, V, A, FixedState>`), a
primitive (`impl char`, `impl<T> *const T`, `impl<T: ?Sized> *mut T`,
`impl<T> [T]`, `impl str`), a reference (`impl<'a, T> &'a T`: allowed,
rarely useful). The methods belong to the type `σ` and are found by
F0.5(i) when the header applies to the candidate type (F0.3 with
`W`). *Anchor:* `later_impl` (today `edition.later: impl_on_instance`),
`method_of`, `front/check/calls/paths.vl: bind_impl_params`.

**F5.2 (lifetime arguments in a header).** `'a` in `impl<'a, T>
Option<&'a T>` is bound by `bind_lifetimes` and unifies positionally
with the receiver's slots (`slots(Option<&'a T>) = ['a] ++ slots(T)`);
the front reads them only to carry them into the method's signature
(borrowck.md D4.1 reads the result).

**F5.3 (several inherent impls of one type).** Allowed (std2's
`impl<T> [T]` in several files, `impl<T, A> Vec<T, A>` blocks) if the
method names are pairwise disjoint over impls whose headers can both
apply to one type (unify, F4.2's test without bounds): a clash is
`error impl.duplicate` (E0592) at the second. Inherent methods of one
type may share a name with a trait method (F9.1 orders them).

**F5.4 (`Self`).** In an impl body `Self` is the header's self type
with its arguments as written (`Self = HashMap<K, V, A, FixedState>`):
`Self { f: .. }` (a struct literal), `Self(..)` (a tuple-struct
constructor, F7.2), `Self::new(..)`, `Self::N`, `Self::Item`, and the
patterns `Self { .. }`, `Self(..)`, are those of `σ`. In a trait body
`Self` is the parameter `Self: Tr` (F0.4a). *Anchor:*
`front/generics/instantiate.vl: is_self_name`, `front/check/names.vl:
synth_name` (today `Self` resolves only to a non-generic self type at
some sites: M2's gap 12).

### F6 `impl .. for &'a T`, and the probe order

**F6.1 (reference self types).** `impl<'a, T: Tr> Tr for &'a T`,
`impl<'a, A: Allocator + ?Sized> Allocator for &'a A`, `impl<'a, T>
IntoIterator for &'a mut [T]`: the header's self type is a reference;
it applies (F0.3) to a reference type by unifying pointee and
mutability (`&'a T` never applies to `&'b mut U`; `'a` is positional,
F5.2). *Anchor:* `later_impl` (today `edition.later: impl_for_ref`),
`ImplInfo.ty`.

**F6.2 (the probe).** F0.5's order, in full, which is rustc's: for
receiver type `τ₀`, each candidate `τᵢ` of the autoderef chain, each of
the receiver types `τᵢ`, `&τᵢ`, `&mut τᵢ` in that order, and at each the
methods whose *receiver type* is that type (not the methods of the
type `τᵢ`), inherent then in-scope trait methods; two trait methods at
one step are `error method.ambiguous` (rustc E0034). A result that
differs from rustc's silently is a bug: where the front cannot tell the
step it keeps its order and the corpus names it. Consequences that are
corpus cases (each checked with rustc): with `impl S { fn tag(&self) }`
and `impl Tag for &S { fn tag(&self) }`, `r.tag()` on `r: &S` is S's
(receiver `&S` = `τ₀` by value) and `rr.tag()` on `rr: &&S` the impl's
(receiver `&&S` = `τ₀` by value, S's only at `τ₁`); `s.c()` on `s: S`
with `fn c(&mut self)` on S and `impl C for &S { fn c(self) }` is the
impl's (`&S`, the `&` step, before `&mut S`); `m.e()` on `m: &mut S`
with `fn e(&self)` on S and `impl E for &mut S { fn e(self) }` is the
impl's (`τ₀` by value); `v.iter()` on `v: Vec<T, A>` finds
`<[T]>::iter` at `τ₁ = [T]` through `Deref` (by `&`); `s.len()` on `s:
&&str` finds `str::len` (receiver `&str`) at `τ₁` by value; `x.clone()`
on `x: &T` with `T: Clone` finds `<T as Clone>::clone` (receiver `&T`)
at `τ₀` by value, before `<&T as Clone>::clone` (receiver `&&T`, the `&`
step); `r.into_iter()` on `r: &Vec<T>` finds the `&'a Vec<T>` impl at
`τ₀` by value before `Vec`'s at `τ₁`; `it.next()` on a `&mut I` with
`I: Iterator` finds `I::next` (receiver `&mut I`) at `τ₀` by value;
`a.into_iter()` on `a: [T; N]` finds `[T; N]`'s by-value `IntoIterator`
(std::array's `IntoIter`, yielding `T`, FL13) at `τ₀` by value, before
the `&[T; N]` impl (the `&` step) and the slice's at `τ₁ = [T]`
(rustc's 2021 edition; 0.27.3). A
receiver of unsized type (`τᵢ = [T]`) is probed by `&` and `&mut` only
(F21.2). *Anchor:* `method_of`, `front/check/rust.vl: probe_step,
probe_first, autoref_first` (the steps through references; a `Deref`
target or a view is ordered as before), `deref_receiver`.

**F6.3 (autoref writes the receiver).** The probe's result rewrites the
receiver expression to the adjusted form (`(&*recv).m(..)`,
`(&mut **recv).m(..)`) before borrowck sees it, so the places IR gets
an ordinary reborrow (borrowck.md D3.8); a `&mut` autoref of an
immutable place is `error borrowck.mut_borrow_immutable` as a written
`&mut` is. The adjustments are recorded on the call node (`a` = the
deref count, `b` = the autoref kind) for `query type` and the LSP.

### F10 `where` bounds on projections and other types

**F10.1 (forms).** A `where` clause's subject may be any type: a
parameter (`T: Clone`), a projection (`I::Item: Debug`, `<I as
Iterator>::Item: Display`), an instance (`Vec<T, A>: Clone`), a
reference (`&'a T: IntoIterator`), a closure bound (`F: FnMut(I::Item)
-> B`, D20.1). *Anchor:* `front/parser/items/params.vl: parse_where`
(today `edition.later: where_bound` for a non-parameter subject),
`front/parser/rust.vl: where_key`.
A clause is its own item's: a function's is checked for that function
(F10.2), a struct's, an enum's, a trait's and an impl's are none
function's (0.27.3: a struct's predicate was the function's parsed
before it, `struct Flatten<I> where I::Item: IntoIterator` read as a
bound of Cloned's `next_back` when the whole std2 was loaded; which
impls a program loads does not change which predicates a function has).
Case `std2_iter_adapters_cloned_impl_doubleendediterator`.

**F10.2 (at instantiation).** For an instance with substitution `θ`,
every clause `σ: Tr<b..>` is checked as `θ(σ): Tr<θ(b)..>` by F0.4 at
the instantiation's position: `error trait.unmet` (E0277), naming the
clause and the instance. *Anchor:* `front/traits.vl: check_bounds,
check_later_bounds`, `front/generics/instantiate.vl: require_bound`.

**F10.3 (in the body).** Within the item (and its opaque instance,
D22.1) the clause is in `Γ`: F0.4b answers `σ: Tr` for lookup on a
value of type `σ` (`x.fmt(f)` for `x: I::Item` with `where I::Item:
Debug`). *Anchor:* `require_in_bounds, bounded_param_of_type` (today:
only a parameter's declared bounds).

### F11 Bounds on an associated type's declaration

**F11.1 (declaration).** `type A: B₁ + .. + Bₘ;` in `Tr` (and `type A:
?Sized`, `type A = default` is 0.29). Every impl's definition `type A =
σ;` must satisfy `Γ_impl ⊢ σ: Bᵢ` (F0.4): `error trait.unmet` at the
impl's definition. *Anchor:* `front/assoc.vl: collect_trait_assoc,
collect_impl_assoc` (today `edition.later: assoc_bounds`).

**F11.2 (in bodies).** `T: Tr` in `Γ` entails `T::A: Bᵢ` for every
declared bound (F0.4b): `x.clone()` for `x: I::Item` under `I: Iterator`
and `type Item: Clone` needs no `where`. In the opaque instance `Ω::A`
is a fresh `Ω'` carrying exactly these bounds plus any `Item = X` of
the bound (D22.1).

**F11.3 (normalization).** A projection `<τ as Tr>::A` with `τ`
concrete and one applying impl is replaced by that impl's definition
before unification (`assoc.vl: projection`); one with `τ` a parameter is
kept as a projection type, equal only to itself (and to its `= X`
constraint when `Γ` has `T: Tr<A = X>`). *Anchor:* `front/assoc.vl:
projection, trait_projection, constraint_type`.


**F11.5 (a bound's equality through a supertrait, 0.27.2.1).** A bound
`I: Tr<Name = τ>` whose `Name` a supertrait of `Tr` declares
(`DoubleEndedIterator<Item = &'a T>`, Item Iterator's) is read through
that supertrait's impl for the bound's type, so it binds the parameters
τ names as `Iterator<Item = &'a T>` would (`Copied<I>`'s
`DoubleEndedIterator` impl). *Anchor:* `front/assoc.vl:
super_projection, infer_from_assoc`. Case `rust_f_f11_super_projection_ok`.
### F12 Default bodies in generic traits

**F12.1.** A method of a generic trait `Tr<P..>` may have a default
body (`fn ne(&self, o: &Rhs) -> bool { !self.eq(o) }`); an impl `impl
Tr<a..> for σ` that omits it gets a copy with `Self := σ`, `P := a`
substituted, checked as the impl's own method (as a non-generic trait's
default is today: `FN_DEFAULT_COPY`). The default body is checked
against `Γ_Tr = {Self: Tr<P..>} ∪ super*` (D22.3 applies: it may use
only `Tr`'s and the supertraits' items on `self`, and `P`'s declared
bounds on values of type `P`). *Anchor:* `collect_trait_params` (today:
"a function of a generic trait has no default body"),
`front/traits.vl: collect_impl` (the default copy).

**F12.2 (a default's own parameters).** The copy's own generic
parameters are the default's, whatever the impl's are named: one named
as an impl's parameter (`collect_in<B, A>` in `impl<B, I, F> Iterator
for Map<I, F>`) is renamed in the copy, in its signature, its `where`
predicates and its body, a path's head included (`B::from_iter_in(..)`,
0.27.2.1). *Anchor:* `front/traits.vl: rename_own_params,
subst_trait_args`. Case `rust_f_f12_own_param_path_ok`.

**F12.3 (a default in a pattern impl, 0.27.3).** A default copied into
a pattern impl (F5.1, `count` in `impl<T> Iterator for W<T, Option<T>>`)
is found by the impl's header, as the impl's own methods are; the copy
is checked in the trait's module, but the header's names (`W`, a
struct of the impl's module) are resolved in the impl's. *Anchor:*
`front/traits.vl: fn_pattern_bindings`. Case
`rust_f_f12_pattern_impl_default`.

**F12.4 (`where Self: Sized`, 0.27.6).** A trait function whose `where`
says `Self: Sized` is not part of an impl whose `Self` is unsized (`[T]`,
`str`), as in rustc. Its default is not checked for that impl: no opaque
instance of the copy is made (D22.2). `impl<T: Hash> Hash for [T]` does
not check `hash_slice(data: &[[T]], ..)`. 0.27.5 checked it and
reported "the size of '[T]' cannot be known" in the default's body.
The bound itself still says nothing elsewhere (it is dropped when it is
parsed, F21). *Anchor:* `front/parser/items/params.vl: parse_where`
(FN_SELF_SIZED), `front/opaque.vl: build_opaque_instances`. *Case:*
`rust_f_f82_assoc_self_from_arg`.

### F13 Several impls of one generic trait for one type

**F13.1 (the key).** An impl's key is its whole header `(Tr, a..,
σ)` (F0.3): `impl AsRef<str> for str` and `impl AsRef<[u8]> for str`,
`impl<T> SliceIndex<[T]> for Range<usize>` and `impl SliceIndex<str>
for Range<usize>`, `From<u8>` and `From<char>` for `String<A>` coexist;
two impls with unifiable headers are F4.2's. Each impl's signatures are
checked against the trait's with its own `a..` (today: the second is
checked against the first's). *Anchor:* `ImplInfo` (`targs` becomes
part of the key), `has_impl`, `check_impl_signatures`,
`front/assoc.vl: find_assoc`.

**F13.2 (selection by the expected type).** For `x.m(args)` or
`Tr::m(x, args)` where more than one impl of `Tr` applies to `x`'s
type with different trait arguments, the trait arguments are inferred
as a generic call's parameters (F18.1): from the argument types, then
from the expected type of the result (an `AsRef<U>::as_ref(&self) ->
&U` against an expected `&str` picks `U = str`). If one candidate's
header unifies, it is chosen; none is `error trait.unmet`; several is
`error type.ambiguous` (E0283) with `try: AsRef::<str>::as_ref(&x)` (or
`<str as AsRef<[u8]>>::as_ref`, F8.1) per candidate. *Anchor:*
`front/check/calls/paths.vl: synth_path_call, sole_instance_with`,
`front/generics/instantiate.vl: infer_from`.

**F13.3 (selection by an own parameter's bound).** When the parameter a
candidate's function takes an argument at is one of the function's own
type parameters (`fn extend<I: IntoIterator<Item = T>>(&mut self, iter:
I)`), the argument's type is checked against that parameter's bounds'
associated-type equalities, with the impl's trait arguments for the
trait's: `v.extend(s.iter().copied())` on a `Vec<i64>` gives `Item =
i64`, which `Extend<i64>` takes and `Extend<&i64>` does not. A
projection the checker cannot compute (no impl defines it) rejects no
candidate. *Anchor:* `front/convert/mod.vl: own_bound_misses, takes`.

**F13.4 (selection by the generic body's bound).** In an instance of a
generic function (checked per instance, D22.3), a method call whose
receiver is a parameter of a bounded type parameter `S: Tr<a..>` and
which more than one impl of `Tr` takes picks the impl whose trait
arguments are the bound's: `s.as_ref()` with `S: AsRef<str>`, S =
`String`, is `AsRef<str>`'s, as the generic body read it. F13.2's
expected type is tried first. *Anchor:* `front/convert/mod.vl:
by_expected, by_param_bound, dispatch`.

### F14 Impl parameters fixed by the trait's arguments

**F14.1.** An impl parameter `Q` must be *constrained*: it occurs in the
self type `σ`, or in a trait argument `aᵢ`, or is determined by a
projection of a constrained parameter through a bound in `W` (`impl<B,
I: Iterator, F: FnMut(I::Item) -> B> Iterator for Map<I, F>`: `B` is
fixed by `F`'s bound's result position, `I` by `σ`; the result may be
a type with arguments, `P: FnMut(I::Item) -> Option<B>` for MapWhile and
Scan, 0.27.2.1). Unification at a
goal runs over the whole header and, for a parameter constrained only
through a bound, over the bound's projection after the rest is bound
(so `impl<T> SliceIndex<[T]> for usize` binds `T` from the goal's
trait argument). A parameter constrained by nothing is `error
trait.unconstrained` (E0207) at the impl. *Anchor:* `collect_impl`
(today: parameters must be the self type's arguments in order:
`later_impl`), `front/check/calls/paths.vl: impl_param_count,
bind_impl_params`.
In an instance, a parameter of a pattern impl that the receiver's type
and the arguments leave free is taken from the bound of the receiver's
type parameter that names the impl's trait: `r.start_bound()` with `R:
RangeBounds<K>`, `R = RangeFull`, is `impl<T> RangeBounds<T> for
RangeFull` with `T = K` (0.28.0: `m.range(..)`, `v.drain(..)`).
In an instance a receiver `*a` of `a: &T` is a `T`: when no impl of
what `T` points to takes the call, `T`'s own does, as the generic body
resolved it by `T`'s bound (`<&u8 as PartialEq<&u8>>::eq` in
`Option<&u8>::eq`); and a receiver that is a reference to a view, `k:
&K` with `K = &str`, is the view's own impl, not its place's (`K:
Borrow<K>` is the reflexive impl; 0.28.0, gap 59). *Anchor:*
`front/convert: unify_recv_bound, dispatch`. Cases
`rust_t_bound_blanket_impl`, `rust_t_borrow_reflexive`.

**F14.2 (positional binding).** An instance's arguments bind a template
impl's parameters by position only when the header names them in order
(`impl<T> Tr for W<T>`); `impl<T> SliceIndex<[T]> for Range<usize>` is
matched (F0.3), does not cover `Range<i64>`, and its `T` is fixed by
the trait arguments a projection is read with (`trait_args_agree`).
*Anchor:* `front/traits.vl: header_in_order, impl_bindings,
trait_args_agree`.

### F15 Builtin impls

**F15.1 (`#[builtin_impls(P₁, .., Pₙ)]`).** On a trait declaration in a
std2 file: for each listed primitive `Pᵢ` (any of F0.1's primitives
including `char`, `bool`, `()`), the compiler synthesizes `impl Tr for
Pᵢ` whose methods are the intrinsic bodies MVS's intrinsic impls have
today (`front/derive/intrinsic.vl`, `front/traits.vl: intrinsic`): the
arithmetic, comparison, bitwise and shift operators by the machine
operation (with MVS's overflow rules, `arith.overflow`), `Clone`/`Copy`
by copy, `Default` by zero/`false`/`'\0'`, `Display`/`Debug`/`LowerHex`/
`UpperHex`/`Octal`/`Binary` by the existing number formatting into the
`Formatter` (F16.3), `Hash` by hashing the bytes, `Ord`/`PartialOrd` by
the machine comparison (floats: `PartialOrd` only, `partial_cmp` giving
`None` on NaN), `Step` by `+1`/`-1` on integers, `Sum`/`Product` by the
operator (each as `Sum for P` and, as Rust's core has, `Sum<&'a P> for
P`, 0.27.2.1). A listed trait that has no intrinsic (a method the compiler
does not know) is a compiler-build error reported by `known_items_check`
(Z3). The attribute on a non-std2 trait is `error attr.builtin`. The
synthesized impls are keyed like written ones (F13.1) and take part in
F4.2 (a written `impl Tr for i64` beside the list is an overlap). An
impl so synthesized has no position: its errors are reported at the
attribute. *Anchor:* `front/parser/rust.vl: take_builtin_impls` (today
`edition.later: primitive_builtin`), `intrinsic`.
(0.27.4) *Which primitives a build makes them for.* A lazy build
(std2lazy) makes the impls, and the integers' inherent methods (F15.4),
only for the primitives a program brings in. A program brings in a
primitive when one of these holds:
- one of its files names it as a word;
- a literal's suffix names it (`5u16`);
- an unsuffixed float (f64) or a char literal (u32) appears;
- a float is brought in (f32 or f64): then u64, i64 and u32 are too, the
  types its formatting and bit methods work in;
- a word in std2lazy's PRIM_WORDS table brings it through std2's types.
  For example `chars` and `to_digit` bring u32, `Hash`, `HashMap`, `copy`
  and `to_bits` bring u64, `PartialOrd` and `Ord` bring a derived
  order's isize, `floor`, `pop` and `drain` bring u32, and `AtomicU16`
  brings u16.
The impls for i32, usize, u8 and bool are always made. They come without
a name: the literal default, a length, a str's bytes, a condition.
A dropped impl counts as dropped std2 text, so a build whose check then
fails is made again with std2 whole (rerun_eager). Its diagnostics are
then the eager build's, and a missing impl is an error before it is
anything else: no impl is ever chosen in its place. An open literal
closed by a bound keeps its default (FL6: i32 and f64, whose impls are
always there when the literal is), and a type variable solved through an
impl (FL1) is solved among the impls of the named types, which are all
made. Queries,
`--std2-check`, `fix` and an on-disk std2 make every impl. Cases
`rust_f_f15_prim_impl_literal_ok`, `rust_f_f15_prim_impl_unnamed_ok`,
`rust_f_f15_prim_impl_bound_ok`, `rust_f_f15_prim_impl_solved_ok`.

**F15.2 (what counts as a primitive here).** The listed names are the
primitives; `&T`, `[T]`, `str`, tuples are not (their impls are written,
F4.1, F6.1).

**F15.4 (the integers' inherent methods).** The integer primitives'
inherent methods are the compiler's, made from its list (decided: supplied by
the compiler, not written in std2): `#[builtin_methods(P₁, .., Pₙ)]`
on an item of a std2 module (std2 writes it once, in `num::wrapping`)
makes, for each listed integer `Pᵢ`, `impl Pᵢ { .. }` with Rust's
signatures and bodies in rust-edition text (F15.1's way: parsed as
`<builtin>`, given the attribute's span, the module's items, flagged
made), as MVS's `std::num::wrapping` (tools/intops) has them:
`wrapping_{add,sub,mul,neg,shl,shr,div,rem,pow}`,
`checked_{add,sub,mul,neg,shl,shr,div,rem,pow}`,
`overflowing_{add,sub,mul,neg,shl,shr,div,rem,pow}`,
`saturating_{add,sub,mul,div,pow}`, for the signed ones also
`wrapping_abs`, `checked_abs`, `overflowing_abs`, `saturating_abs`,
`saturating_neg`, `signum`, `is_negative`, `is_positive`,
`unsigned_abs`, for the unsigned `is_power_of_two`; and `count_ones`,
`count_zeros`, `leading_zeros`, `trailing_zeros`, `rotate_left`,
`rotate_right`. The module's arithmetic never checks overflow (MVS's
`std_wraps` rule, which reads `num::wrapping` under std's root in either
std), so a body's `self + rhs` is the wrapping add. `min`, `max` and
`clamp` are `Ord`'s (F15.1); the consts `MIN`, `MAX`, `BITS` are the
compiler's as in MVS. A listed name that is not an integer is `error
attr.builtin` ("no builtin methods for .."); the attribute outside std2
is `error attr.builtin` (F15.1). Not in 0.27.2: `pow`, `abs` (they panic
on overflow in Rust's debug builds), `swap_bytes`, `to_be`/`to_le`/
`from_be`/`from_le`, `next_power_of_two`, the float methods (`sqrt`,
`floor`, .., `to_bits`) come in 0.27.3.
*Anchor:* `front/parser/rust.vl: take_builtin_impls`,
`front/builtin_impls.vl: write_int_methods`, `front/modules: std_wraps`.

**F15.5 (written impls with a primitive self type).** `impl TryFrom<i64>
for u8`, `impl From<u8> for u32`, `impl From<char> for u32`, `impl
Step for char`: ordinary impls (F0.3, FR3) written in std2 with `as`
and range checks; nothing is synthesized for them, and F4.2 checks them
against F15.1's lists (so a trait with a `#[builtin_impls]` list may not
also be written for a listed primitive).

**F15.6 (the floats' digits).** F15.1's `Display`, `Debug`, `LowerExp`
and `UpperExp` for `f32` and `f64`, `LowerExp`/`UpperExp` for the
integers, and `FromStr` for `f32`, `f64` and `bool` are bodies that call
std2's private module `flt` (`fmt_float`, `fmt_int_exp`, `parse_float`,
`parse_bool`), with Rust's output: the shortest digits that read back as
the same float (`{}`; `{:?}` with `.0`, exponent form below 1e-4 and
from 1e16), the exact value rounded half to even at a precision, and a
parse rounded to the nearest float. *Anchor:* `front/builtin_impls.vl:
write_fmt, write_from_str`, `compiler/std2/flt.vl`.

**F15.3 (`#[array_builtin(N)]`).** On an impl or free function whose
header mentions `[T; N]` with `N` a declared name: a template over the
length, instantiated for each `N` the program uses (`impl<T: Clone, N>
Clone for [T; N]`, `Vec::from_in([..], a)`); within it `N` is a `usize`
constant. It is the stopgap for const generics (0.29), std2-only.
An impl over a type that holds `[T; N]` as an argument (`impl<T> Drop
for IntoIter<T, [T; N]>`, std2's by-value iterator, FL13) is a pattern
impl (F5.1): its methods, its trait's defaults (F12.3) and its `drop`
are found by its header. *Anchor:* `front/parser/rust.vl:
take_array_builtin`; `places/shim.vl: drop_fn` (a pattern impl's drop).

## 3. Names, calls and inference

### F8 Qualified paths

**F8.1 (`<τ as Tr<a..>>::name`).** Resolves `name` among `Tr`'s items
(methods, associated types, consts) with `Self := τ`; `τ: Tr<a..>` must
hold (F0.4, else `trait.unmet`). For a method the result is the
function value of the impl's (or builtin's, or default's) method; its
call passes the receiver explicitly. In type position
`<τ as Tr>::A` is F11.3's projection. (0.27.4) In type position the
trait's arguments pick the impl: `<I as SliceIndex<[i64]>>::Output`
with I = `RangeFrom<usize>` is the impl for `[T]` (T := i64 from the
arguments, F14.1), not the one for `str`; without arguments, or when
none matches, it is t's impl of Tr, as before. Case
`std2_slice_sliceindex_output`. *Anchor:* `front/parser/rust.vl:
qualified_path` (today `edition.later`), `split_shl`, `synth_path`,
`check/resolve.vl: qualified_projection`.

**F8.2 (`Tr::name`).** A trait name used as a path head (`Debug::fmt(v,
f)`, `Iterator::next(&mut it)`, `Default::default()`) is `<_ as
Tr>::name` with `Self` inferred from the first argument's type (a
method; through F6.2's adjustments of that argument: `Debug::fmt(v, f)`
with `v: &T` finds `T: Debug`) or from the expected type (an
associated function, F18.1). Neither: `error type.infer` with `try: <T
as Tr>::name`. *Anchor:* `front/check/resolve.vl: resolve_key` (today
"is a trait, not a type"), `path_target`.
(0.27.6) An associated function without a receiver also takes `Self`
from an argument whose parameter's written type holds `Self` (`Self`,
`&Self`, `&mut Self`, `&[Self]`, `[Self]`), as rustc infers it.
`Hash::hash_slice(self, state)` in `impl<T: Hash> Hash for [T]`, with
`data: &[Self]` and `self: &[T]`, is `<T as Hash>::hash_slice`. 0.27.5
read every `Tr::f(x, ..)` as the method call `x.f(..)`, which gave Self
`= [T]` and "an associated function, not a method". The argument's
type is the one it has without being checked: a local, `&e` or `&mut
e` of one, or `e[a..b]` of an array or a slice. Another argument (a
literal array sliced in place) gives no `Self` yet. *Anchor:*
`front/check/calls/paths.vl: synth_path_call, self_from_args`. *Case:*
`rust_f_f82_assoc_self_from_arg`.

**F8.3 (`<τ>::name`, `τ::name`).** The inherent namespace of `τ` first;
then, with `τ` concrete, the traits in scope (F9.2) that `τ` implements
and that declare `name`; with `τ` a parameter, its bounds (F0.4a).
Ambiguity is F9.3's. `<τ>::name` with an explicit type is what
disambiguates a primitive (`<i64>::MAX`, `<[T]>::len`).

**F8.4 (`<τ as Tr>::name` in an expression).** With `τ` a name
(`<i32 as FromStr>::from_str("-7")`, `<W as Make>::make()`), the path
`τ::name` (F8.3). In 0.27.2.1 the trait is parsed and not kept, so two
traits in scope that both declare `name` for `τ` are F9.3's ambiguity,
where rustc takes `Tr`'s; a `τ` that is not a name (`<Vec<T> as
Tr>::f`) is a parser error. *Anchor:* `front/parser/exprs.vl:
parse_primary`. Case `rust_f_f8_qualified_call_ok`.

### F9 Method name clash

**F9.1 (order).** F0.5: at each probe step inherent candidates first;
only when there are none, trait candidates. So a type with its own `fmt`
and `Display::fmt` calls its own on `x.fmt(f)`; `Iterator::eq` and
`PartialEq::eq` on one type conflict only when both traits are in scope
and neither is inherent.

**F9.2 (traits in scope).** A trait is in scope at a position iff it is
declared in the position's module, imported by a `use` there (by name
or `use path::Tr as _`), or in the edition's prelude (Z2). A method of
a trait not in scope is not a candidate: `error method.unknown` with
`try: use path::Tr;` (rustc E0599's "items from traits can only be used
if the trait is in scope"). *Anchor:* `method_of` (today: every impl of
the program), `front/modules/lookup.vl`; of several trait candidates the
one of a trait in scope is taken (0.27.2.1, `self.v.fmt(f)` with only
`Binary` imported: `front/check/calls: trait_method_choice,
trait_in_scope`). Case `rust_f_f9_trait_in_scope_ok`.

**F9.3 (ambiguity).** More than one candidate at the deciding step is
`error method.ambiguous` (E0034), listing each as `try: Tr::m(&x, ..)`
(F8.2 forms; `<τ as Tr>::m` when `Self` would not infer). In a bounded
body, two bounds declaring `m` (`T: Display + Debug`, `x.fmt(f)`) are
the same error.

### F18 Return-type and literal inference

**F18.1 (the inference order of a call).** For a call of a generic
function or method `g<P..>` the parameters are bound, in order: (1)
from the turbofish (F19.1); (2) by unifying each argument's synthesized
type with its parameter's type, untyped literals last (`infer_from`);
(3) **from the expected type**: a parameter that occurs in the result
type and is still free is bound by unifying the result type with the
expected type when there is one — a `let`'s annotation, a parameter's
type at an argument position, the enclosing function's return type at a
`return` or the tail, an assignment's target type, a struct literal's
field type, a cast's target (`as`), the `Self` of a method's receiver
(`x.collect_in::<..>()` aside); (4) by the parameter's default (`Rhs =
Self`); (5) from a bound with an equality (`I: Iterator<Item = T>` binds
`T` from `I`, `infer_from_assoc`). A parameter still free is `error
type.infer` (E0282) with `try: g::<τ>(..)` naming the free parameter.
A closure argument is typed after steps (1)–(3) with the parameter's
bound as its expected signature (D20.3; `s.retain(|c| ..)` gets `c:
char`). *Anchor:* `infer_from` (today: arguments and one hint),
`front/generics/mod.vl: hint_for`, `front/closures/mod.vl:
infer_param_error`.

**F18.2 (no expected type).** In MVS a parameter the steps of F18.1
leave free is `type.infer` at the call, with the `try:` of the turbofish
(`try: Vec::<T>::new_in(...)`). In the rust edition it is an inference
variable (F18.6, 0.27.4: FL1's deferred inference): `let x =
Vec::new_in(a);` with `T` fixed by a later `x.push(1)` is inferred; a
variable still free at the end of its function is the same `type.infer`,
at the call that made it.

**F18.3 (integer and float literals).** An unsuffixed integer literal
has no type of its own: it takes the type of the context it unifies
with (an expected type, the other operand of a binary operator, a
parameter's type, a bound's requirement when the parameter is otherwise
fixed: `self.get(0)` with `I: SliceIndex<[T]>` and the impls for `usize`
and the ranges picks `usize`, the only integer type with an applying
impl, F13.2), compared against `.len()`'s `usize` takes `usize`; an
`0..1` at `R: RangeBounds<usize>` is `Range<usize>`. With no context it
is `i64` in MVS and `i32` in the rust edition (Rust's default; a literal
that does not fit is `arith.overflow`). An unsuffixed float literal is
`f64`. A suffix (`1u8`, `2.0f32`) fixes the type. *Anchor:*
`front/generics/mod.vl: is_untyped_literal_expr`, `front/check/
literals.vl: defaulted_apart`, `synth_mode.vl: is_untyped_literal`
(the default kind).
(0.27.2.1: a range of unsuffixed integer literals at a bare bounded
parameter, `s.get(1..3)`, is checked as the one `Range<N>` the bounds
admit before the call's arguments are inferred:
`generics/instantiate.vl: range_literal_by_bounds`.)
(0.27.7: a literal whose context is a value an error left untyped, `value >
9223372036854775807` after a reported mismatch in `let value = ..`, takes
the error type, not the fallback. Its fit is not checked, as rustc
reports only the first error. 0.27.6 checked it against `i32` and
reported a second error. *Anchor:* `check_mode.vl: check_expr_inner`.
*Case:* `rust_f_f183_literal_after_error_err`.)

**F18.4 (a hoisted literal takes the let's annotation).** `let r: &U = &e;`
with `e` a literal (an array, an integer, a float, a tuple) makes its
temporary (lifetime extension) with the annotation's type: `let d: &[u8]
= &[1, 2, 3];` is `let t: [u8; 3] = [1, 2, 3]; let d: &[u8] = &t;`, so
the literals are `u8`, not the default. *Anchor:* `front/check/temps.vl:
annotate_temp`. Integer inference variables (a literal typed by a later
statement, `let a = [1, 2]; f(&a)` with `f(&[u8])`) are F18.5's.
(0.27.5) Where no `let` hoists it (a block's tail, an `if`'s or a
`match`'s branch, an argument, a field), a shared `&e` checked where
`&U` goes, with `e` an array, a repeat or a tuple, checks `e` against
`U` when `U` is of its kind (an array type for an array or a repeat, a
tuple type of as many elements for a tuple): `let b: &[i64; 2] = if c {
&[1, 2] } else { &[3, 4] };` and `if c { &(7, true) } else { &(8, false)
}` where `&(i64, bool)` goes type their literals from `U`, as rustc's
expectation does. So does a sliced array literal where `&[U]` goes,
`if c { &[1, 2, 3][1..] } else { &[0][..] }`: the array is a `[U; N]`.
Where `&mut [U]` goes (0.27.6), the slice is checked as `[U]` and the
reference is the exclusive one, so `&mut [1, 2, 3][..]` passed to a `&mut
[i64]` is accepted, as rustc accepts it (0.27.5 checked the slice against
`&mut [U]` and refused it).

*A shared `&e` where `&mut` goes* (0.27.6) is refused in the rust
edition, as rustc refuses it (E0308, the types differ in mutability):
`bump(&n)` with `bump(x: &mut i64)`, `first(&[1, 2, 3][..])` and
`first(&a[..])` with `first(v: &mut [i64])`. Each is a `type error`
(not MVS's `own.readonly`) whose help says so and whose `try:` and fix
borrow exclusively (`&mut n`, `&mut [1, 2, 3][..]`, `&mut a[..]`). The
`&` of a rust node is shared as written: MVS's inout marker, which makes
`&x` exclusive where an exclusive reference is expected (check_mode:
check_expr and coerce_ref), is MVS's alone. 0.27.5 accepted all three.
Cases: rust_f_f18_shared_for_mut_err, and tests/borrowck-try's mut_ref_arg,
mut_slice_literal and mut_slice_place, whose try: lines are run.
(0.27.6) The same slicing as a `let`'s whole initializer with a slice
annotation, `let s: &[i64] = &[1, 2, 3][1..];`, hoists the array, not
the slice: `let t: [i64; 3] = [1, 2, 3]; let s: &[i64] = &t[1..];`, so
its literals take the annotation's element type (0.27.5 hoisted the
slice, typed by the fallback `i32`: a type error). *Anchor:*
`check_mode.vl: check_expr_inner`, `temps.vl: annotate_temp`. *Cases:*
`rust_f_f18_let_sliced_literal`.

**F18.5 (integer inference variables: an open local).** In the rust
edition an unannotated `let x = e;` binding one name, with `e` a literal
tree (an unsuffixed integer literal, its negation, an array, a repeat or
a tuple of literal trees, where a tuple's other elements are any
value, an arithmetic operator of two literal trees; 0.27.7: a shift
whose left operand is a literal tree, its right operand any integer
value, which does not type it, `1 << (l % 64)` and `(0 - 1) << (bits -
1)`, and `!` of a literal tree, `!0`; 0.27.4: an `if`
with an `else`, or a `match`, whose every branch's value, its block's
tail, is a literal tree, `let e0 = if c { 1 } else { 0 };`, and a block
whose tail is one), makes `x` **open**:
its integer positions are inference variables. So does `let r = &x;` (or
`&mut x`) of an open `x`: `r` is a **link**, its type `&` of `x`'s;
solving one solves the other, closing one closes both. Until it is
solved the local reads as its provisional type, the tree with `i32` at
each variable. It is solved by its first use, in the order the function
is checked, that gives its positions a type:
(a) a check against an expected type (an argument, an annotation, the
return or tail, a struct field, an assignment's target type, `&x` where
`&τ`, `*const τ` or `&[τ]` goes, `a[i]` and `&a[..]` of an open array
where `τ` or `&[τ]` goes), matched with the provisional type where the
variables are; (b) an operand of a binary operator whose other operand
has a definite integer type (`i < v.len()`: `usize`), so a `for`
range's start whose end has one (`for i in e0..np`, 0.27.4); (c) the
target of `x = e` or `x op= e` with `e` of a definite type (`s += m.v`,
`kv = e.remove_entry()`; `s += x` of an `x: &i64` reads through it); (d) a
generic call's argument, placed with the untyped literals (F18.1 step
(2)), so that it takes the type the other arguments or the expected type
bind. These uses keep it open and are retyped when it is solved: `x op=
lit`, `x = lit` and a comparison with a literal (`x < 10`). A closure
that captures an open local closes it when the closure is checked (its
environment holds the type). Any other use closes it at its provisional
type (the `i32` fallback, F18.3): a method receiver, a pattern's
scrutinee, a `format_args` hole (FL6 names each). (0.27.7) A
cast's operand, `x as τ`, keeps it open: the cast gives `x` no type, as
in rustc. A local still
open at the function's end has the fallback. Solving retypes the local
and the nodes typed through it in place, and a literal that does not fit
its type is an error (rustc: literal out of range); after the function
is checked nothing is open. *Anchor:* `front/check/literals.vl: open_let,
open_solve, open_expected`, `check_mode.vl: check_expr_inner`,
`assign.vl: check_assign`. MVS is unchanged: no local is open, its
fallback is `i64`.
(0.27.7, the shift) A shift's type is its left operand's, so only that
operand makes it a literal tree, and solving it types that operand: `let
bit = 1 << (l % 64);` then `v[w] | bit` with `v: Vec<i64>` is an `i64`
shift, as rustc infers it. 0.27.6 did not count a shift as a literal
tree, so its literal took `i32` at the `let` and the later `i64` use
widened the wrong value: `1 << 40` was `256`, and `(0 - 1) << 63`
passed as an `i64` was `i32`'s minimum. That was a silent wrong value,
found by the 0.28 flip rehearsal (19 such `let`s in compiler/src's
translation). A `!` of a literal tree (an integer `!`, checked as `~`)
is one too. *Cases:* `rust_f_f185_shift_open`,
`rust_f_f185_shift_open_err`.
(0.27.7, a method on a literal tree) An integer type's own method (F15.4's
`impl i32 { .. }`: `wrapping_sub`, `pow`, `count_ones`, `abs`) called on a
literal tree, `(1 << s).wrapping_sub(1)`, `2.pow(2)`, is error
`type.infer`, rustc's E0689, where 0.27.6 took `i32`'s method (so `1 << 40`
was `1 << 8`: a silent wrong value, the flip rehearsal's). A trait's method
there, `5.max(3)`, `3.clone()`, `1.cmp(&2)`, is `i32`'s, as rustc's
fallback gives it. So is a method on a local still open: `let m = (1 <<
b) - 1;` then `m.count_ones()` is `type.infer`, rustc's E0689 (0.27.6 took
`i32`'s). *Anchor:* `check/calls: synth_method,
literal_method_error`. *Cases:* `rust_f_f185_literal_method_err`,
`rust_f_f185_literal_method_ok`, `rust_f_f185_local_method_err`.
(0.27.7, a cast) The operand of `x as τ` keeps an open `x` open; its use
is retyped when `x` is solved. `let max = (1 << bits) - 1;` then `if v >=
max as f64 { return max; }` in a function returning `i64` is an `i64`
`max`, as rustc infers it; 0.27.6 closed it at the cast, and `max` was
`i32`'s 255 for `bits` 40 (a silent wrong value, the flip rehearsal's,
through consteval's `float_to_int`). *Anchor:* `check/synth_mode:
synth_cast`. *Case:* `rust_f_f185_cast_open`.
(0.28.0, open locals as leaves) An open local of an integer type is a
leaf of a literal tree where the tree's own type goes (not as an array's
or a tuple's element): `let c = a;`, `let b = a + 1;` and `let p = a *
k;` make `c`, `b` and `p` open, and their uses in the tree keep `a` and
`k` open. So do a comparison of two such trees (`a > b`, `i + 1 == n`),
the assignment of one to an open local (`s += x`, `t = x + 1`), and a
`for` loop over a range of two (`for i in 0..64`, `for q in 0..r` of an
open `r`): the loop's local is open, its init the range. The locals a tree
links are one variable, a **group** (rustc's unified `{integer}`): solving
one solves them all at its type, and closing one closes them all. On std2
a format hole of a direct call (`println`, `print`, `eprintln`,
`format_in`, `write`, `panic`) keeps its open local open too: when the
local is solved, the hole's value takes its type and its write is made
again, with that type's impl. 0.27.7 closed the local at each of these
at `i32`, and a later `i64` use widened the `i32` value (FR5): `let c =
a;` of `1 << 40` gave 256, a loop's `i * i` wrapped past 2^31 (silent
wrong values: the FR5 census found 146 widenings in compiler/src's
translation, 132 of them a `for` loop's local over a literal range).
*Anchor:* `front/check/literals.vl: open_group, open_shape, open_bounds`,
`synth_mode.vl: synth_operands`, `body.vl: check_for`, `assign.vl:
check_assign`, `interp.vl: hole_retype`. *Cases:*
`rust_f_f185_open_leaves`, `rust_f_f185_open_compare`,
`rust_f_f185_open_loops`, `rust_f_f185_open_format`.
(0.27.3, the literals around it, F18.3: `&1` where `&τ` of a number
goes is a `τ` (`m.get(&1)`, `x.total_cmp(&0.0)`); a literal bound only
by a parameter's bound picks the one integer type an impl gives, also
behind `&` or negated, and through another parameter's bound that names
it (`K: Borrow<Q>`); an array of literals at a generic call takes its
element type from the expected type or the written `[i64; N]`; a
closure argument whose parameter types are known is typed before the
literal arguments, so that its result binds their parameter
(`map_or(0, |x| x + 1)`), and one whose value is itself a literal
after; a negated literal where an unsigned type goes is an error, rustc
E0600.)
(0.27.6, the branches of an `if` or a `match` where no type is expected:
an element of a tuple that every earlier branch gives by a literal tree
is an inference variable (F18.6) where a later branch is checked. A
branch of a definite type there solves it, and the earlier branches'
literals take that type. `match k { 0 => (gap, 0), _ => (0, gap) }`
with `gap: usize` is `(usize, usize)`, as in rustc; 0.27.5 typed the
first arm `(usize, i32)` and refused the second. A variable that the
later branches leave free, all of them literals there, is the `i32`
fallback. *Anchor:* `literals.vl: branch_expected, branch_settle`,
`patterns/mod.vl: check_match`, `body.vl: synth_if`.)

**F18.6 (type variables: deferred inference; 0.27.4).** In the rust
edition a type parameter of a generic call (a function, a method, a path
`Vec::new_in(..)`), of an enum's variant (`Ok(x)`) or of a struct
literal that F18.1's steps (1)-(5) leave free is not an error: it
becomes an **inference variable** `?ᵢ`, and the call's type mentions it
(`Vec<?T, Gpa>`). A variable is solved by the first check, in the order
the function is checked, that unifies a type mentioning it with a
definite type:
(a) a value checked against an expected type, either side mentioning
the variable: an argument and its parameter's type, a `let`'s
annotation, the return or the tail, a struct field, a later arm of an
`if` or `match` against the first's type (`if c { Ok(1) } else
{ Err("neg") }` fixes `E`), so a value passed where its type goes
(`mem::replace(&mut x, fresh)`);
(b) a method call's receiver against the instance's `Self`, after the
arguments bound the parameters (`v.push(2)`: `T` from `2`);
(c) the target of `x = e` with `e` of a definite type.
These uses keep it free: a method call whose instance names the
variable only through `Self` (`v.len()`, `v.is_empty()`,
`v.capacity()`): the instance waits for the variable, and is made again
with its solution. Any other use is `type.infer` (rustc E0282) at the
call that made the variable: a method call on a bare variable, `x as
τ`, a capture by a closure, a format hole (`println("{:?}", v)` before
the push). Solving retypes in
place the function's locals, nodes and closure signatures that mention
the variable, and makes again each instance made with it; a variable
free at the function's end is F18.2's `type.infer`. After the function
is checked no variable is left: none reaches code generation, effects,
the caches or another function. An untyped literal or an open local
(F18.5) checked where a variable goes gives it its provisional type at
once (`v.push(1)`: `Vec<i32>`), and closes the local (FL6). MVS has no
variables.
Stage 2 (0.27.4) adds three sources and one use. (d) A `_` written in a
type in a function's body (`let f: FromFn<_> = from_fn(..)`, `let v:
Vec<_, Gpa> = Vec::new_in(gpa)`, `let t: (i64, _) = (1, 2u8)`) is a
fresh variable, solved as the others; one still free at the end is
`type.infer` at the `_` ("cannot infer the type written `_` here", rustc
E0282). (e) A projection of a variable, `<?ᵢ as Tr>::A` (the `Err` of
`"4".parse()`'s `Result<F, F::Err>`), is a variable that depends on
`?ᵢ`: when `?ᵢ` is solved it is the projection of the solution, so
`let a: u32 = "4".parse().unwrap()` is inferred (`F` from the `let`, its
`Err` then `ParseIntError`); it is free while `?ᵢ` is. (f) A closure
argument whose parameter's bound mentions a free variable (`from_fn(||
..)` where the hint is `FromFn<?ᵢ>`) is not bound by the hint: the
closure's own inference fixes the parameter. And `e?` checked against
an expected type checks the value it gives (the `Ok`'s or `Some`'s
payload) against it first, by (a), before its error's conversion
(`let n: u8 = s.parse()?`). A variant pattern checked against a
variable's enum names its variant of the solution's when the function's
check ends. (g) (0.27.6) A variable for a bounded parameter
(`Vec::<u8, _>::new_in(gpa)`, `let v: Vec<u8, _> = ..`: `A: Allocator`)
is not checked against its bound while free: the instance made with it
is made again with the solution, and the bound is checked then, at the
call and at the `_` that made it (rustc E0277 for `Vec::<u8,
_>::new_in(5i64)`). A value synthesized before it is checked (a struct
literal's field, synthesized to infer the struct's parameters) is
unified with the type it is checked against when either mentions a free
variable, as by (a): `gpa` where the `_` goes, and `Vec::new_in(g)`
(`Vec<?T, &Gpa>`) where the field's `Vec<i64, &Gpa>` goes. Before, the
bound was checked on the variable ("the trait 'Allocator' is not
implemented for '_'"), and the field's value did not solve it
("expected 'Vec<i64, &Gpa>', got 'Vec<_, &Gpa>'"). *Anchor:*
`front/check/infer.vl`, `generics/instantiate.vl: require_bound,
infer_from`, `check_mode.vl: check_expr_inner`, `assoc.vl: projection`,
`resolve.vl: resolve_type` (the `_`), `try_op.vl: check_try`,
`traits.vl: check_bounds` and `generics/mod.vl: check_arg` (g). Cases
`rust_f_f18_hole_alloc_ok`, `rust_f_f18_hole_alloc_err`.

**F18.7 (a field typed by its parameter takes the value's type;
0.27.6).** A generic struct literal or enum variant whose one free
parameter `A` is an allocator parameter binds it from an `_in` call's
allocator argument (0.26.3: `Tokens { kinds: Vec::new_in(a) }` is
`Tokens<typeof a>`, as the field is `Vec<u8, A>`). That rule is for a
field that holds something *made in* the allocator. A field typed by
the parameter itself (`struct Cx<W: Allocator> { arena: W }`) holds the
value, so `W` is the value's own type, as rustc infers it: `Cx { arena:
Arena::new_in(gpa) }` is `Cx<Arena<Gpa>>`, not `Cx<Gpa>`, which was an
error in 0.27.5 ("expected 'Gpa', got 'Arena<Gpa>'"). The same holds
for a variant's payload (`E::A(Arena::new_in(gpa))` with `A(W)`). The
rule is in shared code, so MVS gets it too; what MVS compiled before is
unchanged. *Anchor:* `generics/instantiate.vl: bind_allocator_arg`
(its `p`, the place's type node). Case `rust_f_f18_alloc_field_ok`.

### F19 Small syntax

**F19.1 (turbofish).** `f::<τ..>(..)`, `x.m::<τ..>(..)`, `S::<τ..>`,
`S::<τ..>::new(..)`, `size_of::<τ>()`: the arguments bind the item's
parameters in order (`_` leaves one to inference). On a non-generic
item, `error generic.count`. *Anchor:* `front/check/calls/paths.vl:
call_function` (the `written` Generics node: exists for paths), the
parser for `x.m::<T>(..)` and `S::<T>::f`.

**F19.2 (`use a::{self, B}`).** `self` in a use list imports the
module `a` itself under its last name. *Anchor:* `front/modules/
lookup.vl` (the `use` list reader; `features.tsv: use_self`).

**F19.3 (`unsafe fn` types).** `unsafe fn(τ..) -> ρ` and `unsafe
extern "C" fn(..)` are function-pointer types distinct from the safe
ones: a safe `fn` value coerces to the unsafe type, not the reverse; a
call through an unsafe pointer needs `unsafe`. A field, a parameter and
a `let` may have the type. A closure that captures nothing coerces to
either, `fn(..)` or `unsafe fn(..)` (not to an `extern "C"` one), as in
rustc. *Anchor:* `front/parser/types.vl` (the `fn` type reader;
`features.tsv: unsafe_fn_ptr`), `front/check/unsafety.vl`,
`front/closures/mod.vl: closure_fn_target`.

**F19.4 (`size_of`, `align_of` by name).** In a rust-edition position
`size_of::<T>()`, `align_of::<T>()`, `mem::size_of::<T>()`,
`size_of_val(&x)` are std2's `mem` functions (prelude-free: imported or
qualified), compiler-known (Z3, keys `size_of`, `align_of`,
`size_of_val`): their calls fold to the constant MVS's builtin
`size_of(T)` gives, per instance. MVS's builtin spelling `size_of(T)` is
not read in a rust file (it is a call with a type where a value goes:
`error type.expected_value`). *Anchor:* `synth_mode.vl:
fold_layout_query`, `front/check/collect.vl: collect_name` (the
reserved names: not reserved in the rust edition).

**F19.5 (`mem::transmute`).** `unsafe fn transmute<T, U>(x: T) -> U`
is std2's, compiler-known (Z3 key `transmute`): `size_of::<T>() ==
size_of::<U>()` is checked per instance (`error type.transmute`,
rustc E0512) and the bits are reinterpreted (a move, no drop of `x`).
`char::from_u32_unchecked` is written with it (M3a's gap 11; the
`*const u32 as *const char` spelling is Z9.3-legal too).

**F19.6 (`static mut`).** In a rust-edition position a read or a write of
a `static mut` item is an unsafe operation (`error unsafe`, rustc E0133):
inside `unsafe { }` or an `unsafe fn`'s body only. A reference to one is
D6.2.5's error either way. An MVS `static var` is unchanged (safe).
(0.27.4) Since every such use is unsafe, the program vouches for it, and a
thread may reach it, as in rustc: a rust-edition `static mut` (or an
`extern` static) used by a spawned closure, or by what it calls, is not
`sync.global`, and neither is a C function declared in the rust edition
(its call is unsafe too; `--check-alloc`'s allocator, std2's, calls
`mmap` and `sigaction` from any thread). Each keeps the `global` effect,
the memory the optimizer keeps other threads' view of
(contracts-effects.md E1). An MVS `static var` stays for the main thread
only. *Anchor:* `front/check/names.vl: synth_name` (`U_STATIC_MUT`),
`front/effects/infer.vl: walk_ident`, `effects/check.vl:
extern_effects` (no `raw_global`). Cases `rust_f_f19_static_mut_err`,
`rust_f_f19_static_mut_thread`.

**F19.7 (unions drop nothing).** A union declared in a rust-edition
position has no drop glue of its own fields (an `impl Drop for U` of its
own runs): which field holds a value is the program's to know, as in
Rust. A field read out by value (in `unsafe`) moves the union: a union's
field has the union's own move path (borrowck.md D8.3). Not yet: rustc's
E0740 for a field that is neither `Copy` nor `ManuallyDrop` (FL12).
*Anchor:* `front/own/glue.vl: glue_of`, `places/elab.vl: path_of,
rust_union`. Case `rust_f_f19_union_no_drop`.

### F22 `for` loops

**F22.1 (desugaring).** In a rust-edition position
```
for PAT in EXPR { BODY }
```
is
```
{ let mut __it = IntoIterator::into_iter(EXPR);
  loop { match Iterator::next(&mut __it) { Some(PAT) => BODY, None => break } } }
```
with `IntoIterator` and `Iterator` std2's (Z3 keys `into_iter`,
`next`), `PAT` any irrefutable pattern (F27), and `break`/`continue`
with labels as today. The MVS forms (a range, a view, an array, an
`iter` method) are not read: a range iterates because `impl<A: Step>
Iterator for Range<A>` (F15.1's `Step`), a `&Vec<T>` because
`impl<'a, T, A> IntoIterator for &'a Vec<T, A>`, a `[T; N]` by
`#[array_builtin]`'s `IntoIterator`. The error for a non-iterable is
`trait.unmet` ("`τ: IntoIterator` is not satisfied"). *Anchor:*
`front/check/iterate.vl` (today `not_iterable`'s list), `interp.vl:
direct_body`.

### F24 Visibility

**F24.1 (one crate).** A program and its std are each one crate:
`pub(crate)` on an item or field makes it visible everywhere in that
crate (so std2's `iter` reads `ops`'s `pub(crate)` fields); `pub(super)`
and `pub(in path)` as 0.26.2 has them; no visibility: the declaring
module and its descendants (Rust's reference "Visibility and privacy").
A tuple struct's fields and constructor follow F7.2. *Anchor:*
`front/check/sealed.vl: field_hidden`, `front/modules/vis.vl:
restricted_at, crate_root` (today: `pub(crate)` on a field of std is
read as the program's crate).

### F26 Operators

**F26.1 (lowering).** In a rust-edition position an operator expression
is the call of the std2 trait method (Z3's `ops` keys), per Rust's
reference "Operator expressions":
`a + b` → `Add::add(a, b)` (likewise `- * / %`, `& | ^ << >>`),
`-a` → `Neg::neg(a)`, `!a` → `Not::not(a)` (bitwise on integers,
logical on `bool`: closes M2's gap 14; MVS's `~x` is not read),
`a += b` → `AddAssign::add_assign(&mut a, b)` (every `op=`),
`a == b` → `PartialEq::eq(&a, &b)`, `!=` → `ne`,
`a < b` → `PartialOrd::lt(&a, &b)` (`le`, `gt`, `ge`),
`*a` → `*Deref::deref(&a)` (`deref_mut` in a written place),
`a[i]` → F20. The operand types are the trait's parameters (`Rhs`
inferred as F18.1's step (2), default `Self`); `&&`, `||` and `as` are
not traits. On primitives the lowering meets F15.1's builtin impl and
is folded to the machine operation (so MVS's codegen path is kept).
*Anchor:* `front/traits.vl: operator_call, binary_op_trait,
negation_call` (today: `a.cmp(&b) < 0` for `<`, `a.eq(&b)` for `==`),
`front/check/equality.vl`.

**F26.2 (on a parameter).** `a < b` with `a, b: T` needs `T:
PartialOrd` in `Γ` (F0.4a; D22.3): the call is `<T as
PartialOrd>::lt(&a, &b)`, resolved per instance; without the bound,
`error generic.unbounded_use` (E0369, "binary operation `<` cannot be
applied to type `T`") with `try: T: PartialOrd`. `==` needs
`PartialEq`; `+` needs `Add<Output = ..>`.

**F26.3 (an operator's right operand of another type).** On std2, a
binary operator (`a == b`, `a < b`, `a + b`, ..) with `a` of a struct or
enum type and `b` of another (not a literal that takes its type from
context; an array literal does, for a comparison) checks `b` alone: the
impl of the operator's trait for `b`'s type decides (`s == "x"` with
`impl PartialEq<str> for String`, `v == [1, 2]`, `s + "bar"` with `impl
Add<&str> for String`).
When the operand is a view (`[T]`, `str`, Z9.1, where `&str` is the view
too), an impl whose argument is written `&..` yields to one that is not:
`PartialEq<str>` and `PartialEq<&'a str>` compare alike (0.27.2.1).
A comparison whose left type has exactly one impl of the operator's
trait (a derive's `PartialEq for Option<T>`) gives the right operand
that type as its expected type, as rustc's inference does: `a ==
Some(0)` of an `Option<i64>`, `v.last() == Some(&0)`; and a left operand
that is a call holding a literal without a suffix (`Some(0) == a`) is
read after the right one, with its type expected (0.28.0, gap 103).
A comparison of two references with no impl of their own is of what
they refer to, level by level (Rust's `impl PartialEq<&B> for &A`):
`&a == &b` of two `&u8`, `a == b` of `a: &T` with `T = &u8`; never of
the addresses (0.28.0; a raw pointer compares its address).
*Anchor:* `front/check/synth_mode.vl: synth_operands, binary_result`,
`front/convert: by_view_rhs, one_generic_trait_fn`. Cases
`rust_f_f26_cmp_rhs_ok`, `rust_t_ref_eq_instance`.

### F27 Patterns in `let` and parameters

**F27.1 (irrefutable patterns).** `let PAT = e;`, `let PAT: τ = e;`,
a parameter `PAT: τ`, and `for PAT in ..` take any *irrefutable*
pattern: a binding (`x`, `mut x`, `ref x`, `ref mut x`), `_`, a tuple
`(p₁, .., pₙ)`, a struct `S { f: p, g, .. }` (with `..`), a tuple struct
`S(p..)`, a unit struct `U`, a reference `&p`, `&mut p`, a single-
variant enum's variant, and match ergonomics as in `match` (0.27.0). A
refutable pattern (a literal, a range, a variant of a many-variant enum)
in `let` is `error pattern.refutable` (E0005) with `try: let .. else`
is not offered (`let else` is 0.29) and `if let` is. *Anchor:*
`front/parser/stmts.vl` (the `let` reader: today a name or a tuple),
`front/patterns/mod.vl: check_pattern, check_pat`.

**F27.2 (bindings and moves).** A `let` pattern binds as `match`'s
arms do (by value, moving out of `e` the parts it binds by value,
borrowck.md M3; `ref`/`&` by reference): a struct pattern on a place
moves only the bound fields (partial move, M2).
(0.27.6) A `let` whose whole pattern is `ref x` or `ref mut x` is
`let x = &e;` or `let x = &mut e;` (`let ref x: τ = e;` is `let x: &τ =
&e;`): of a place it borrows the place and moves nothing, as rustc
does. `let ref z = a; a.x` reads `a`, and `let ref mut w = v[0]; *w +=
1` changes `v[0]` (through IndexMut, F20.6). Of a value, its temporary
lives as long as `x` (lifetime extension, as F18.4's `let r = &e;`).
0.27.5 moved `e` into the binding's temporary: `a` was moved, and `v[0]`
was copied. *Anchor:*
`front/parser/stmts.vl: parse_let`. *Cases:* `rust_f_f27_let_ref`,
`rust_f_f27_let_ref_err`.

### F31 `#[track_caller]`

**F31.1 (the attribute).** `#[track_caller]` on a function or method
`f` gives `f` a hidden last parameter `__caller: &'static Location`
(std2's `panic::Location { file: &'static str, line: u32, col: u32 }`).
A call of `f` passes the call's position (`file:line:col`, the
program's path as `volec` prints it; std2's paths as `<std>`); a call
of `f` from inside another `#[track_caller]` function `g` passes `g`'s
own `__caller` (the location propagates to the first non-tracked
caller, Rust's rule). `Location::caller()` is compiler-known (Z3 key
`caller_location`) and, inside a tracked function, reads `__caller`;
outside one it is the call's own position. A `fn` pointer or closure
value taken from a tracked function passes the pointer-taking site. std2
marks `panic`, `unreachable`, `todo`, `unimplemented`, `assert*`,
`Option::unwrap`/`expect`, `Result::unwrap`/`expect`/`unwrap_err`,
`Index::index` of `[T]`/`str`/`Vec`/`HashMap`, and the `Formatter`-free
`panic_str`; the program may mark its own. The positions are what
MVS's `panic_str` receives today (`format.vl: panic_call`); `EXIT: 101`
output names them. The attribute is read in the rust edition only.
**ABI note:** a tracked function's calling convention differs from its
signature's by the hidden argument; none is `extern "C"` or exported to
C (`#[track_caller]` on an `extern` function or a `#[no_mangle]` item is
`error attr.builtin`), and a `fn` pointer to a tracked function is the
pointer to a shim that passes the pointer-taking site. *Anchor:*
`front/parser/items/attrs.vl`, `front/check/format.vl: panic_call`,
`front/check/calls/paths.vl: call_function` (the hidden argument).

## 4. Format and derives

### F16 Format functions

**F16.1 (the compiler-known functions).** In a rust-edition program
these std2 items are compiler-known (Z3 keys): `fmt::print`, `println`,
`eprint`, `eprintln`, `format_in`, `fmt::write`, `fmt::writeln`,
`panic::panic`, `assert`, `assert_eq`, `assert_ne`, `debug_assert`,
`unreachable`, `todo`, `unimplemented`. They are known by *item*, not by
bare name: a call resolves the name as any (own items, imports, prelude,
Z2) and the format rule applies iff the resolved item is one of the
keys. So a module's own or `extern` `write` shadows `fmt::write`
(closes M2's gap 16: `extern "C" fn write(..)` is just an extern).
*Anchor:* `front/check/format.vl: format_call, std_fn, format_kind`
(today by name, MVS std's).

**F16.2 (the format literal).** When the format argument (the first;
for `write`/`writeln`, the second; for `assert*`, the first after the
condition or the two values) is a string literal, it is a *format
literal*: 0.26.2's grammar (`{}`, `{x}`, `{0}`, `{:?}`, `{x:>8.3}`,
`{:#?}`, `{:x}`, `{{`, `}}`), checked at the call: the holes are
counted against the arguments after it (positional) and the names
resolved in the call's scope (inline `{x}`); each hole's spec fixes the
trait its argument must satisfy — `{}` `Display`, `{:?}` `Debug`,
`{:x}` `LowerHex`, `{:X}` `UpperHex`, `{:o}` `Octal`, `{:b}` `Binary`,
`{:e}` `LowerExp`, `{:p}` `Pointer` — checked by F0.4 (`trait.unmet`
names the hole). Errors: `format.syntax`, `format.spec`, `format.args`
as today. A non-literal format argument is a plain `T: Display` value
(`println(s)`); `panic(s)` likewise. *Anchor:* `format_call,
format_message`, `front/check/interp.vl`.

**F16.3 (lowering).** The call becomes a block that builds std2's
`Formatter` over the destination and calls, per piece, `Formatter::
write_str` for the text and `<τ as Tr>::fmt(&arg, &mut f)` for a hole
(with the spec's width, fill, precision, flags set on `f` by the
`Formatter` setters first; `{:#?}` sets `alternate`): the destination
is stdout/stderr (locked once per call: `__print_begin`'s role, Z3 key
`fmt_begin`/`fmt_end`), an allocated `String<A>` for `format_in`, the
writer `w` for `write(w, ..)`/`writeln` (calling `w.write_fmt`-free:
the pieces go to `w.write_str` through `fmt::Write` or `io::Write`,
whichever `w` implements, F13.2), a 256-byte stack buffer for
`panic`/`assert*` (0.26.2's decision 5). `write`/`writeln` return
`fmt::Result` (or `io::Result<()>` for an `io::Write` writer: 0.27.3,
through the tail's `std::__rt::io_fmt`, the first io error kept, its
`finish` the value; a writer whose referent is no `fmt::Write`); the
print functions return `()`. The lowering is rust-edition generated
code (Z1): the trait calls are F0.5's and go through F15.1's intrinsic
impls for primitives (the number formatting MVS has). *Anchor:*
`front/check/interp.vl: direct_body` (today: MVS's `__print_begin`,
`Fmt::display`), `format.vl: panic_call`.

**F16.4 (format_args's value).** `format_args(lit, ..)` outside a
compiler-known call (F16.1) is a value: its holes' arguments are
evaluated once, where it stands, into the hole lets, and it is
`std::__rt::Interp { f: move |__out: &mut std::fmt::Formatter| WRITES }`,
WRITES F16.3's for the literal through `__out`. `Interp<F>` is std2's
(the compiler's tail, Z5.1) with `impl<F: Fn(&mut Formatter<'_>)>
Display`, so the value goes wherever a `T: Display` goes (a parameter,
`to_string_in`, `write(f, "{}", v)`), as Rust's `fmt::Arguments` does.
Divergences, named: the value's type is its own per literal, not one
`Arguments<'a>`; a write's error inside the closure is not carried out of
`fmt` (0.27.4: it returns `Ok(())`; the sinks keep an io error for their
own `finish`). *Anchor:* `front/check/interp.vl: expand,
push_writes_std2`, `front/stdalloc.vl: std2_tail`.

**F16.5 (the spec's traits and flags).** A hole's trait is the spec's: `x`
LowerHex, `X` UpperHex, `o` Octal, `b` Binary, `e` LowerExp, `E`
UpperExp, `p` Pointer (0.27.2.1; a pointer's `{:p}` stays its address),
`?` Debug, else Display. A struct's or an enum's impl of the spec's trait
writes the hole (`impl Binary for W`, `{:b}`), not only a number's
(0.27.2.1). `+` sets the Formatter's
`sign_plus` (bit 0), `-` its `sign_minus` (bit 1), `#` `alternate`, `0`
`sign_aware_zero_pad`. *Anchor:* `front/check/interp.vl:
direct_body_std2, spec_call`, `format.vl: parse_spec`.

### F17 Derives

**F17.1 (Rust's shapes).** `#[derive(Tr, ..)]` on a struct or enum in a
rust-edition position (a program's file or std2's, Z1) generates, as
rust-edition code, impls with std2's signatures:
- `PartialEq`: `fn eq(&self, other: &Self) -> bool` (fieldwise `==`,
  F26.1; enums: same variant and fieldwise); `Eq`: the marker impl;
- `PartialOrd`: `fn partial_cmp(&self, other: &Self) ->
  Option<Ordering>` (lexicographic by field order; enums by variant
  index then fields); `Ord`: `fn cmp(&self, other: &Self) -> Ordering`;
- `Hash`: `fn hash<H: Hasher>(&self, state: &mut H)` (each field;
  enums: the discriminant as `isize`, then the fields);
- `Debug`: `fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result` using
  `f.debug_struct(name).field("x", &self.x).finish()`, `debug_tuple`,
  and the variant's name for an enum, as Rust prints them (`{:#?}`
  pretty through the builders);
- `Clone`: `fn clone(&self) -> Self` fieldwise; for a struct with an
  allocator field `a: A` where `A: Allocator`, `fn clone_in<B:
  Allocator>(&self, b: B)`-style reuse is **not** derived (std2 writes
  `CloneIn` by hand); `Copy`: the marker impl (the fields must be
  `Copy`: `trait.unmet`);
- `Default`: `fn default() -> Self` fieldwise (an enum: the
  `#[default]` variant, else `error derive.default`); `DefaultIn` is
  written by hand.
Each derived impl is `impl<P.. : Tr> Tr for S<P..>` (every type
parameter bounded by the derived trait, Rust's rule; `PhantomData<T>`
fields do not lift the bound: FR2 is *not* claimed — vole bounds as
rustc does). A derived impl is keyed and overlap-checked like a written
one (F4.2). *Anchor:* `front/derive/mod.vl: expand_derives,
rust_derive_skip` (today: Rust's names mapped to MVS's `Eq`/`Ord`;
`Copy` skipped), `struct_eq, struct_cmp, struct_hash, struct_debug,
struct_clone, enum_*`, `write_impl, w_impl_head`.

**F17.2 (MVS untouched).** In an MVS position derives keep MVS's shapes
and rules (`derive/intrinsic.vl`). The generated source of a rust
program is `rust_at` (Z1.2), so F0.4 and D22.3 apply inside it.

**F17.4 (empty enums, and a program's derives).** A derive on an enum
with no variants (`Infallible`) generates the body `match *self {}`
(each method; `Clone` and `Copy` likewise), so a struct holding one
derives `Debug` (M3a's gap 8). A program's `#[derive(Clone,
PartialEq, Debug, ..)]` generates impls of std2's traits (the prelude's
and `fmt`'s, by Z3's keys, not by the names in scope), so a user struct
satisfies std2's bounds (`HashMap<K: Hash + Eq, ..>`, `assert_eq`).

**F17.3 (`Clone` for `Gpa`).** std2's `#[derive(Clone, Copy)] pub
struct Gpa;` is F17.1 in a std2 file: `Gpa: Clone` holds, and
`clone_in(gpa)` on a `Vec<T, Gpa>` typechecks (closes M1's gap 18 and
M2's gap 5, which were Z1's: std2's derives were expanded as MVS's).

## 5. Indexing

### F20 `SliceIndex` and `Index`

**F20.1 (the rewrite).** In a rust-edition position `c[i]` on a type
`τ` that is not an array (`[T; N]` indexes by `usize` directly, as
today) is `*Index::index(&c, i)` in a read, `*IndexMut::index_mut(&mut
c, i)` in a written or `&mut`-borrowed place (0.27.0's
`index_through_trait`, kept); the result type is `<τ as
Index<I>>::Output` with `I` inferred from `i` (F18.1; an untyped literal
picks the one integer impl, F18.3). `Output` may be unsized (`[T]`,
`str`): the place `*index(..)` is then an unsized place behind the
returned reference (Z9), so `&c[a..b]` is `&*index(&c, a..b)`, a
reborrow, and `c[a..b]` by value is `type.unsized`. *Anchor:*
`front/check/rust.vl: index_through_trait`, `synth_mode.vl:
synth_index` (today: a view's index is MVS's).
(0.27.4) Through references: `h[i]` of an `h: &[T; N]`, `&mut [T; N]`
or `&&[T; N]` is `(*h)[i]` (each reference dereferenced, as rustc's
autoderef of the indexed expression), read, written through `&mut` and
sliced (`&h[a..b]`). A write through `&` is borrowck.assign_immutable
(E0594). 0.27.3 read it as a raw pointer's arithmetic (unsafe). Cases
`rust_f_f20_index_array_ref_ok`, `rust_f_f20_index_array_ref_err`.

**F20.2 (std2's impls).** `impl<T, I: SliceIndex<[T]>> Index<I> for [T]
{ type Output = I::Output; fn index(&self, i: I) -> &I::Output {
i.index(self) } }`, the same for `IndexMut`, `Vec<T, A>` (through
`Deref` to `[T]`: F6.2 finds `<[T] as Index<I>>` at `τ₁`) and `str`
(`SliceIndex<str>` for the range types, F13.1): `impl<T> SliceIndex<[T]>
for usize { type Output = T; .. }`, `for Range<usize> { type Output =
[T]; .. }` (F14.1 binds `T` from the trait argument). `v.get(i)`,
`get_mut`, `get_unchecked` are the same traits' `get`/`get_mut`/
`get_unchecked` through `I::Output` (`Option<&I::Output>`).

**F20.3 (`&self[..mid]` on `str`).** `self: &str`, `self[..mid]` is
`*<str as Index<RangeTo<usize>>>::index(&*self, ..mid)`: an unsized
`str` place; `&self[..mid]` reborrows it with the receiver's region
(E3's `self` rule for the method's result, borrowck.md D4.3). Closes
`str_slice_self`.

**F20.4 (`IndexMut` and assignment).** `c[i] = e`, `c[i] += e`,
`&mut c[i]`, `c[i].m()` with `m` taking `&mut self` (F6.2's `&mut`
autoref) use `index_mut`; a `τ` with `Index` but no `IndexMut` keeps
`index`, and the write through its `&` is borrowck.assign_immutable or
borrow_immutable (rustc E0594, E0596). The same holds of `Deref` and
`DerefMut` on the path (`w.x.push(..)` of a `w: W`, `W: DerefMut`), and
of a Vec's `as_slice` and `as_mut_slice` (`v[i]`, 0.17).

**F20.6 (where a place is used mutably, 0.27.5).** A place is used
mutably when it is:
- an assignment's target, `+=`'s included;
- the operand of `&mut` or `&raw mut`;
- the receiver of a method whose `self` is `&mut Self`, autoref'd
  (F6.2), the method found either way (`v[0].push(x)`, `v[0].iter_mut()`,
  in a closure's body too);
- the scrutinee of a match, `if let` or `let else` with a `ref mut`
  binding.

On such a place every index and deref of its path, through fields and
tuple fields, is IndexMut's, DerefMut's or `as_mut_slice`, each level
(`m[i][j].push(x)`, `ps[0].x.push(x)`). The first two contexts are known
before the place is checked (`Ctx.mut_place`, check::rust::on_mut_path).
The last two are known only after it is, once the method is found or the
pattern checked. The place is then made mutable after the fact, as
rustc's `convert_place_derefs_to_mutable` does. Each index or deref read
through Index or Deref keeps the IndexMut or DerefMut call it would be
(`Ctx.mut_alt`, with its receiver's type as checked, keep_alt).
place_to_mut puts that call in place and checks it as any other: its
instance is the one made and called, and the superseded `index` is no
longer called (its effects are not the caller's). The kept call takes its receiver by
`&mut`, so the places under it are made mutable in turn. A container
whose type still holds an unsolved type variable (FL1) is made mutable
the same way. F26.3's `s[1..].make_ascii_uppercase()` on str is decided
before the place is checked, as before. *Anchor:* `front/check/rust.vl:
place_to_mut, keep_alt`, `synth_mode.vl: keep_mut_slice`,
`calls/mod.vl: synth_method`, `convert/mod.vl: method_call`,
`patterns/mod.vl: check_match`. Cases `rust_f_f20_index_mut_method_ok`,
`rust_f_f20_deref_mut_method_ok`, `rust_f_f20_index_mut_ref_mut_pat_ok`,
`rust_f_f20_index_mut_infer_ok`, `rust_f_f20_index_mut_method_err`,
`rust_f_f20_index_mut_readonly_err`.

**F20.5 (a tuple index of literals).** `g[(0, 1)]` with `G:
Index<(usize, usize)>`: a tuple of unsuffixed literals takes its
elements' types from the impl's index type, as one literal does
(`(i64, i64)` only when no impl takes an integer tuple; 0.27.2.1).
*Anchor:* `front/convert: literal_kind, literal_tuple_fits`. Case
`rust_f_f20_tuple_index_ok`.

**F20.7 (an index through Deref, 0.28.0).** `g[i]` of a type that has
Deref and no Index (a `MutexGuard<Vec<T>>`, an `Arc<Vec<T>>`, a `Box<[T;
N]>`, a struct with its own Deref), or of a reference to one, is
`(*g)[i]`: rustc's autoderef of an index's base. The `*g` is checked as
one written, so a place written goes through `deref_mut` (a guard not
declared `mut` is E0596). *Anchor:* `check/synth_mode.vl: synth_index`.
Cases `rust_t_index_deref`, `rust_b_err_index_deref_mut`.

**F20.8 (an index is a `usize`, 0.28.0).** The index of `a[i]` and the
ends of `a[i..j]`, of an array, a slice, a `str` or a Vec, are `usize`
and nothing else, as rustc's `SliceIndex` impls (E0277, `the type [T]
cannot be indexed by i64`): no other integer type, and no widening to
it (FR5 stops here: a `u8` index is converted as an `i64` one is). An
untyped literal and an open local take `usize` from the index (F18.5).
The error is `an index is a 'usize', got 'i64'`; its fix (`volec fix
--suggested`) writes `i as usize`, `(i + 1) as usize`, or, of an index
that is a cast of an integer, the cast's type (`(b >> 4) as i64` becomes
`(b >> 4) as usize`). `fix` makes it although an `i64` holds values a
`usize` does not: such an index is out of bounds before the conversion
and after it. Until 0.28.0 any integer type indexed (the divergence FR6,
removed). A reference to a `usize` is still read through (`keys[a]` of
an `a: &usize`). *Anchor:* `check/synth_mode.vl: check_index_type`,
`tools/fix/verify.vl: index_operand`. Cases `err_index_usize`,
`rust_t_index_usize`; the transcript `tests/refactor/indexusize.t`.

**F33.1 (no default values; named arguments stay, 0.28.0).** A parameter
has no default value: `fn f(a: i64, b: i64 = 2)` is a parse error at the
`=` (`syntax.default-arg`: "a parameter has no default value; pass it at
each call"), with the
fix that removes ` = value` (`volec fix --suggested`). Named arguments
are kept, a documented divergence from Rust: `f(1, b: 3)`, after the
positional ones and in parameter order. One exception, by name and not
by syntax: std's macro-like panic functions, Rust's macros of the same
names, take their message `msg` (and the position `at` the compiler
fills) as an empty string when a call leaves it out: `assert`,
`assert_eq`, `assert_ne`, `debug_assert`, `unreachable`, `todo`,
`unimplemented`, and `__assert_fmt` (what an `assert` with a format
message becomes). The set is fixed in the checker; their declarations
in std's panic.vl carry no default, and no other function, in std or in a
program, can ask for it. `contract_check` gets its three values from the
compiler (0 for those a message does not show). *Anchor:*
`parser/items/params.vl: parse_param`, `check/args.vl: macro_message,
normalize_args`, `contracts/expand.vl: check_call`. Cases
`err_args_defaults`, `args_defaults`, `err_args_named`.

## 6. The bound-only rule (D22.3's front side; U1)

**D22.3 (restated for the front).** In a rust-edition generic body
(a function, method, impl or trait default with type parameters, and
the closures in it) a value whose type is a parameter `T` (or `&T`,
`&mut T`, `Box<T, A>`, `Option<T>`'s content through a pattern — any
place of type `T`) admits exactly: a move or copy (copy iff `Γ ⊢ T:
Copy`, D8.3), a borrow, passing where `T` (or a type unifying with it)
is expected, a method or associated item that F0.4 entails on `T`
through `Γ` (its bounds, their supertraits F2.2, the `where` clauses
F10.3, the assoc-type declarations F11.2), an operator whose trait F0.4
entails (F26.2), formatting through a hole whose trait is entailed
(F16.2), a cast never (`T as u8` is `type.cast`), a field access never,
a literal of its type never. Anything else is `error
generic.unbounded_use` (E0599 for a method, E0369 for an operator,
E0609 for a field) at the use, with `try:` adding the bound `T: Tr`
that the use needs when `Tr` is the unique trait in scope declaring the
item, else listing the candidates. The rule is checked **per instance
today** (0.5's per-instance check, with the instance's concrete types
hidden behind `T`'s bounds: `require_in_bounds` extended from "a
bounded parameter's method must be a bound's" to "every parameter's
every use is a bound's"), and by the opaque instance from 0.27.2.1
(D22.1–D22.2) — the two agree by D22.4. MVS bodies keep duck typing
(0.5) in full. *Anchor:* `front/traits.vl: require_in_bounds,
bounded_param, bounded_param_of_type`, `method_of`, `synth_field`.

**D22.3a (what counts as a bound in `Γ`).** The declared bounds of the
item and of every enclosing impl or trait, `where` clauses (F10),
supertrait closure (F2.2), assoc-type declarations (F11.2), the
compiler's markers (`Sized` by default; `Copy`, `Send`, `Sync` only when
written), and for a closure the enclosing item's `Γ` (a closure adds
no bounds; D19.1).

**D22.3b (`Self` in a trait).** In a trait's default body `Self` has
exactly `Γ_Tr` (F12.1); in an impl body `Self` is concrete (F5.4) and
the rule does not apply to it.

## 7. The std switch (Z1–Z6, the front side)

**Z1.1 (one std per edition).** `load_std_if_named` and `stdtree.vl`
read the std of `pcx.edition`: MVS `compiler/std` (`stdsrc.vl`:
`std_source`, `std_index`, `std_files`, `std_line_marks`), rust
`compiler/std2` (`stdsrc_rust.vl`: `std2_source`, `std2_index`,
`std2_files`, `std2_line_marks`), through one accessor
`std_edition(pcx) -> (source, index, files, marks)`. A rust program
never loads MVS std, in any part (the sections of `stdsections.vl`,
`PRELUDE_LATE`'s lazy sections, `STD_ALWAYS`'s query loads). `volec
edit`/`refactor` on a std item of a rust program edits `compiler/std2`.
*Anchor:* `front/modules/mod.vl: load_std_if_named`, `front/stdtree.vl`,
`front/stdsrc.vl`, `compiler/std/embed.sh --edition rust`.

**Z1.2 (positions).** `rust_at(p) = edition == RUST ∧ (user_at(p) ∨
std2_at(p) ∨ generated_at(p))`: std2's files and the compiler's
generated sources of a rust program (derives F17, format lowering
F16.3, closures' env structs, `for` F22.1) are rust-edition positions.
Every rule of this document reads `rust_at`. *Anchor:*
`front/rust/mod.vl: rust_at` (today `user_at` only), `front/conv.vl:
user_at, generated_at`.

**Z2.1 (the prelude).** The rust prelude is the `pub use` list of
std2's `prelude.vl`, read at std load into a per-edition table
(`prelude_name(e, i)`, `PRELUDE_COUNT(e)`; MVS's fixed list is
unchanged); `PRELUDE_LATE`'s lazy loading applies to both. The
compiler's own names (`Send`, `Sync`, `Sized`, `AllocFree`, `Fn`,
`FnMut`, `FnOnce`) need no `use` in any edition. Resolution order is
unchanged: the module's own items, its imports, the prelude; so a
module's `fn print` shadows the prelude's. *Anchor:* `front/modules/
lookup.vl: prelude_name, PRELUDE_COUNT, PRELUDE_LATE, PRELUDE_STR`.

**Z3.1 (compiler-known items).** Every std item the checker, the
builder, the effects pass or a lowering names by path or by name is
looked up through one table `known(e, key) -> path` (`front/stdalloc.vl`'s
style), with a row per edition. The keys, each with MVS's item today
and std2's: `gpa` (`alloc::Gpa`), `allocator` (`alloc::Allocator`),
`alloc_free`, `scoped_arena`, `any_alloc`, `box` (`boxed::Box`),
`option`/`some`/`none`, `result`/`ok`/`err` (`?`, `if let`, F22.1,
`try_op.vl: check_try`: closes M1's gap 1), `into_iter`/`next`
(F22.1), `range`/`range_inclusive`/`range_from`/`range_to`/
`range_full`/`range_to_inclusive` (the `..` forms), `deref`/
`deref_mut`, `index`/`index_mut` (F20), the `ops` operator traits
(F26.1), `drop` (`ops::Drop`), `clone`, `copy`, `partial_eq`/`eq`,
`partial_ord`/`ord`, `hash`/`hasher`, `default`, `display`/`debug`/
`lower_hex`/`upper_hex`/`octal`/`binary`/`lower_exp`/`pointer`,
`formatter`/`fmt_write`/`fmt_result`/`fmt_begin`/`fmt_end` (F16),
`format_fns` (F16.1's list), `panic_str`/`panic_fmt`/`assert_fmt`,
`contract_check`, `unsafe_cell_get`, `vec_as_slice`/`vec_as_mut_slice`
(D1.4), `string`, `str_pattern`, `size_of`/`align_of`/`size_of_val`
(F19.4), F21.4's ten fat-pointer keys, `ptr_read`/`ptr_write`
(§10), `transmute` (F19.5), `prim_intrinsics` (F15.4),
`caller_location` (F31.1), `non_null`, `phantom_data`, the thread
items (`thread_spawn`, `scope`, `scoped_join`), the atomics
(`atomic_load`, `atomic_store`, `atomic_add`, `atomic_sub`,
`atomic_cas`, `fence`: std2's private `thread` functions lowered by
key as MVS's `std::sync::atomic` is by name; a `sync` module is
0.27.3's), `step`, `sum`, `iterator`, `into_iterator`,
`double_ended`, `exact_size`. A
key with no entry for an edition whose std needs it is a compiler build
error (`known_items_check`, run under `--verify-places`' flag and by
the gate, which prints `known items: N/N`). The front272 M3 commit that
lands the table enumerates the keys from the `intern_c` sites of
`front/check`, `front/effects` and `places/build.vl` and this list is
updated to match it. *Anchor:* `front/stdalloc.vl`, `front/effects/
infer.vl: std_struct_type`, `front/traits.vl: std_trait`,
`front/check/format.vl: std_fn`.

**Z4.1 (no mixing: what retires).** `edition.std_copy`,
`edition.std_by_value` and `edition.lenient`'s std half are not
raised in 0.27.2 (`check/rust.vl: std_copy_error, std_by_value_error,
lenient_error` become unreachable for a rust program and are deleted;
their `explain` rows say "0.27.0–0.27.1 only"); `std2_root` of
`features.tsv` is closed; borrowck.md D12.1–D12.3 and
`callee_regions`'s bridge are deleted by clos272 (`Σ_f` of a std2
function is D4.1's reading of its signature). *Anchor:*
`front/check/rust.vl`, `front/check/mod.vl: mismatch_error`,
`tools/explain/edition_table.vl`.

**Z5.1 (the tail, the missing modules).** `embed.sh --edition rust`
embeds std2's `alloc::Gpa` implementation with its `--check-alloc`
variant (`CHECK_ALLOC_MODE` selects the file as `stdalloc.vl` does),
the `sys` layer and `panic`'s exit-101 path. `std::gpu`, `std::window`,
`std::objc`, `std::arch`, `std::cli` do not exist for a rust program: a
`use` or path naming them is `edition.later: std_gpu (0.27.4)` (one
feature name, `std_gpu`, for the five; U4). *Anchor:* `compiler/std/
embed.sh`, `front/modules/lookup.vl: private_error` (the "no such
module" site).

**Z5.2 (std2 lexed by its units; 0.27.5).** A build reads std2 by the
units std2lazy splits it into (an item; an inherent impl's header, each
member and its closing brace; a trait's header with its required items,
each default method and its brace; a `use` line; a module's lines), and
keeps only the units it reaches (0.27.3's rule, unchanged). In 0.27.5
the split is made once, when std2 is embedded, not at each build:
`embed.sh --edition rust` writes `std2_units`, the index of the built-in
text's units: each unit's kind, its bytes, its name, trait, type head and
parent, the identifiers it holds (as positions in one table of std2's
words), and the asks of its `use` leaves and its trait's item names. It
is made by the compiler (`volec --edition rust __std2-index TEXT`, the
same split the token path runs), so the two cannot differ. A build on the built-in text
reads the index, interns its words, runs the reach over its units, and
lexes only the units it keeps, in their order; the tail (Z5.1, made per
build) is lexed and split as tokens, as before. The tokens kept are
those the token path keeps, the same and in the same order (each run of
kept units lexed at once, its last token's `joint` as in the whole
text), and std2's inline modules are made after they are lexed, in the
text's order and the tail's last, as when the text is lexed whole. A
symbol's or a string literal's number may differ from the token path's
(what is interned, and in which order, is not the same); no meaning
does.
- The index is used only when it was made for this text: its format and
  the text's length match, the text is the built-in one, and the
  index's first line, `std2-text SUM`, names the cksum of this text
  (`std2_text_sum`, which embed.sh writes from the text alone, with no
  compiler). Otherwise (std2 read from a tree, `VOLE_STD_TREE`; an index
  made by an older format, or for another text; none), and when std2 is read whole (queries, `--std2-check`,
  `VOLE_STD2_EAGER=1`, the eager rerun), the text is lexed whole as in
  0.27.4. `VOLE_STD2_INDEX=0` forces the token path.
- (0.27.6) A gated module's units wait for its name. The reach matches
  names without their modules, so a module of many common names
  (std::gpu::wgsl: `Type`, `Module`, `Entry`, `Block`, `check`) would be
  reached, a little at a time, from any program. A unit inside a top
  module of std2 listed in std2lazy's GATED (`gpu`) is loaded only once
  the word `gpu` is asked (by the program, or by a unit it reaches);
  until then it waits, and the units waiting are loaded when it is. The
  module's own `mod` lines and braces are kept, as every module's are.
  The gate is set from the units' text after they are made (index or
  tokens alike, so the two reads keep the same tokens). A rust hello
  world reads none of std::gpu: 1.86x MVS's with it in std2 (1.80x
  before it, the rest the index's larger tables), not 2.42x.
- Kept up to date with no manual step: the commit hook and the
  stdsrc_rust.vl merge driver run embed.sh, which makes the index with
  the tree's compiler (`target/tools/volec`, else `target/volec`;
  `VOLE_EMBED_VOLEC` names another). Two branches that change std2
  merge without a conflict on it: the driver makes it again from the
  merged std2. The compiler chosen is the first that writes the index's
  format (embed.sh's `STD2_UNITS_FORMAT`, std2lazy's `INDEX_FORMAT`);
  the hooks name the tree's `target/volec` by its absolute path, and the
  main checkout's compilers are tried last. With none (a tree whose
  compilers predate 0.27.5) the index the file has is kept as it is,
  never replaced by an empty one, and embed.sh and the hook say so: made
  for another text, it is not read, and a build reads std2 whole until a
  compiler that can makes it again. `-c` then compares the rest of the
  file; with a compiler that can, an empty index or one for another text
  is stale. (0.27.5's first merges wrote an empty index where the hooks
  ran with 0.27.4's compilers; tools/git-hooks/test-stdsrc.py's std2
  cases are that commit.)
- Checked: `embed.sh --edition rust -c` with the current compiler says
  whether the index is stale, and a test compares the tokens a build
  keeps with the index and without it (`VOLE_STD2_INDEX=0`), on a set of
  programs; both run for every change to std2 or the front's std2 files
  (tests/affected.map). The test (tests/std2/units.sh) reads what
  `VOLE_STD2_DUMP=FILE` writes, the kept tokens with the way they were
  read (by-index, by-tokens), and builds with `VOLE_STD2_NORERUN=1`: a
  lazy build with errors would be made again whole and hide a wrong
  index.
- The cost: the hello-rust row of tests/compile_cost.sh is enforced at
  2.0x the MVS hello world from 0.27.5 (1.78x with the index, 2.08x
  without, which the row would refuse); the index adds about 150 KB to
  stdsrc_rust.vl and 0.5% to the compiler's own compile.
*Anchor:* `front/modules/std2lazy.vl`, `front/modules/mod.vl:
load_std2`, `compiler/std/embed.sh`.

**Z6.1 (two stds, one binary).** Both texts are embedded; the on-disk
cache is keyed by `(edition, std hash)`; `ls -l target/volec` is
printed by the release's gate.

## 8. The codes

All errors unless marked; each new code has an `Explain` row in
`tools/explain/edition_table.vl`'s shape (a new `front_table.vl`), and
where a `try:` is named, a case in `tests/borrowck-try`'s shape under
`tests/front-try/NAME/main.vl`. Existing codes are kept.

| code | fires (rule) | rustc | `try:` |
|---|---|---|---|
| `trait.overlap` | F4.2 | E0119 | none; the message gives the witness types |
| `trait.unconstrained` | F14.1 | E0207 | none; names the parameter |
| `trait.unmet` | F2.3, F10.2, F11.1, F13.2 (none applies), F16.2, F20.4, F22.1 | E0277 | the missing impl's header, or `use` of the trait when an impl exists in a module not in scope |
| `trait.cycle` | F2.1, F3.1 | E0391 | none |
| `trait.missing_item` | F3.1 (a const without default omitted), an impl missing a method (today's message, now coded) | E0046 | inserts the item's signature with `todo()` |
| `trait.extra_item` | F3.1, an impl item the trait lacks | E0407, E0438 | none |
| `impl.duplicate` | F5.3 | E0592 | none; names both impls |
| `method.unknown` | F9.2 (the trait exists but is not in scope) | E0599 | `use path::Tr;` |
| `method.ambiguous` | F9.3, F3.2, F8.3 | E0034 | `Tr::m(&x, ..)` per candidate |
| `type.ambiguous` | F13.2 | E0283 | `AsRef::<U>::as_ref(&x)` per candidate |
| `type.infer` | F18.1, F18.2, F7.3, F8.2, F18.5 (an integer's own method on a literal or an open local, 0.27.7) | E0282, E0689 | `g::<τ>(..)`, `let x: τ` |
| `type.unsized` | F21.1, F21.2, F20.1 | E0277 | `&` the type, `?Sized` on the parameter, `Box<_>` |
| `type.cast` | F1.3, F29.1, Z9.3, D22.3 | E0604, E0605, E0606 | `char::from_u32(x)` for `u32 as char`; none else |
| `type.transmute` | F19.5 | E0512 | none; names both sizes |
| `generic.unbounded_use` | D22.3, F26.2 | E0599, E0369, E0609 | adds `T: Tr` when unique |
| `generic.count` | F19.1 | E0107 | removes or completes the turbofish |
| `pattern.refutable` | F27.1 | E0005 | `if let` |
| `attr.builtin` | F15.1 (outside std2) | — | none |
| `derive.default` | F17.1 (`Default` on an enum without `#[default]`) | E0665 | `#[default]` on the first unit variant |
| `edition.later` (kept) | every feature of `features.tsv` not yet landed; `std_gpu` (Z5.1), `const_generics`, `dst`, `let_else` | — | as today |

Twenty rows (nineteen new codes). The rustc column is the twin's
map (`tools/borrowck-twin.sh`, extended to the `rust_f_*` cases): a
rejecting case's first `error[E0xxx]` must map to the case's expected
code, or the case carries `// RUSTC:`.

## 9. Divergences from rustc

Each is a class a case may name in `// RUSTC: accepts|rejects CLASS`.
Rustc is the oracle elsewhere: a disagreement not listed here is a bug.

**Permissive (vole accepts what rustc rejects).**
- **FR1 (no orphan rule).** One program is one crate: an impl of any
  trait for any type is accepted where rustc would say E0117/E0210.
- **FR3 (any `?Sized` self types for inherent impls).** `impl<T> *const
  T`, `impl str` in a program, which rustc reserves to core (E0390).
- **FR4 (`*const T` and `*mut T` are one type).** vole has one raw
  pointer type: a `*const T` converts to a `*mut T` with no cast, is
  passed where a `*mut T` is wanted, and has `*mut T`'s methods
  (`p.write(x)`, F30.3); rustc keeps the two apart (E0308, and no
  `write` on `*const T`). Only a write through a local declared `*const`
  is refused (F30.1's const_write). Whether to split the types is a
  later decision. Case `rust_f_f30_const_mut_ok`.

- **FR5 (integer widening).** F29.3: MVS's lossless widening is kept
  in the rust edition: an `i32` where an `i64` goes, a `u8` where a
  `u32` goes, and two integer operands of different widths join to the
  wider (`x + n` with `x: i64`, `n: i32`); rustc says E0308. The
  translator's output never needs it; a hand-written program may lean on
  it.

**Strict (vole rejects what rustc accepts).**
- **FL1 (deferred inference by the first constraining use; 0.27.4).**
  F18.6's variables are solved in the order the function is checked, by
  the first use that meets a definite type; rustc unifies over the whole
  function. So a use F18.6 does not let wait, before the one that fixes
  the variable, rejects where rustc accepts (`println("{:?}", v)`, then
  `v.push(1)`; a closure capturing `v`, then the push; a deref through
  a type that holds a variable, `Box::new_in(Vec::new_in(a), a)` then
  `b.push(1)`), and a variable fixed by an untyped literal takes `i32`
  at once where rustc keeps an `{integer}` that a later use may fix:
  `v.push(1); let b: u8 = v[0];` is rustc's `Vec<u8>` and vole's error
  (`Vec<i32>`, FL6). A projection of a variable is solved with it
  (F18.6 (e)), but a method of a generic trait called on a variable's
  value is a use that needs its type (`let r = x.try_into(); match r {
  Ok(v) => .., }` with the target from the arms, rustc's; vole's
  `type.infer`), and so is a `?` whose value is not checked against a
  type (`let n = s.parse()?; Ok(n * 2)`: rustc's E0282 too, at the `*`).
  Cases `rust_f_f18_deferred_ok`, `rust_f_f18_deferred_err`,
  `rust_f_f18_stage2_ok`, `rust_f_f18_stage2_err`,
  `rust_f_fl1_literal_i32` (`// RUSTC-DIFFERS: FL1`).
- **FL2 (overlap by satisfiability, strict when undecidable).** F4.2
  errs on the side of `trait.overlap` where rustc's coherence (with
  negative reasoning on fundamental types and the orphan rule) would
  accept.
- **FL3 (no specialization, no `impl !Trait`'s negative reasoning in
  coherence).** As F4.2; auto-trait vouches (borrowck.md §24) do not
  feed F4.2.
- **FL4 (the probe's `Deref` chain is bounded and static).** F0.5: the
  chain stops at `MAX_ASSOC_DEPTH` derefs; no `Deref` on a parameter
  through an unbounded `Deref` (D22.3).
- **FL5 (no HR regions in bounds beyond D20.1's implicit binder).**
  `for<'a>` is 0.29.
- **FL6 (integer inference variables, F18.5; 0.27.3).** F18.3's context
  rule and the `i32` fallback are rustc's, but vole's variables are
  F18.5's open locals, solved by their first constraining use; rustc
  unifies every `{integer}` of the function and falls back after. Each
  early close rejects where rustc accepts, or picks `i32` where rustc
  infers from a later use: a method receiver (`a.iter_mut()` then
  `zero(it)` with `IterMut<i64>`; `Some(4).and_then(half)` with `half:
  fn(i64)`), an open local in a tree other than F18.5's leaves (a branch
  of an `if` or a `match`, `let b = if c { a } else { 0 };`, an array's
  element), a capture by a closure (closed when the closure is checked),
  a pattern's scrutinee (`match x {..}`), a
  destructuring `let` (`let (a, b) = (0, 1);`), a hole of a
  `format_args` value (`format_args("{n}")` then `f(n)` with `f(usize)`:
  its closure holds the hole's value, whose `Display` impl is picked
  where it is checked; a later `i64` use still widens, F29.3; a direct
  call's hole keeps it open since 0.28.0), a closure whose body is a literal (`|| 1`, then `twice(c)`
  with `FnMut() -> i64`), a literal that fixes a closure's parameter type
  (`fold(0, |a, x| a + x)` with `x: &i64`, `scan(0, ..)`), a range of
  literals as a receiver or behind `&` (`(1..4).sum()` into an `i64`), a
  literal at a `where` predicate on a projection (`next_if_eq(&0)`), and
  an array literal behind `&` at a generic parameter (`same_len(&[7, 8])`).
  A literal reaching no context through a chain of generic calls is `i32`
  at once. No float-literal variables (an unsuffixed float literal is
  `f64`, but `&0.0` and a context take theirs, F18.3). A generic
  constructor's parameter fixed by a later statement (`let v =
  Vec::from_in([1, 2], gpa);` then `v` as a `Vec<i64>`, `W { x: 7 }`
  then `&W<i64>`) is not F18.6's either: the literals bind `T` at the
  call, to `i32` (a variable is made only for a parameter left free;
  FL1). The corpus writes the suffix
  (`1i64`) where it meets one. (Since 0.27.7 a cast keeps the local
  open, and an integer type's own method on an open local, `x.pow(2)`, is
  E0689, F18.5, as on a literal tree; since 0.28.0 `let y = x;`, `x + 1`
  into another `let`, a comparison of two open locals, `s += x` and a
  `for` loop's local over a literal range are one variable, F18.5.)
- **FL7 (const evaluation).** F3.2's consts fold with `consteval.vl`'s
  language, smaller than rustc's const eval (no loops, no `if` over
  consts until 0.29).
- **FL8 (derive bounds).** F17.1 bounds every parameter by the derived
  trait, as rustc; no divergence — listed so a case that expects
  rustc's bound on a `PhantomData<T>` field names the rule.
- **FL9 (a C function pointer's call is unsafe).** F19.3: a call through
  a safe `extern "C" fn(..)` pointer needs `unsafe`, as in MVS (the
  pointer may come from C; the fn type's ABI bit keeps its meaning);
  rustc calls one safely. Case `rust_f_f19_c_ptr_err`.
- **FL10 (Z9.1's representation; later, 0.27.3).** In the rust edition
  `[T]` and `&[T]` (`str` and `&str`) are still one type, MVS's view:
  `resolve_type` makes `&` of a view the view. So `&mut &[u8]` is `&mut
  [u8]` (`*self = &self[n..]` cannot be written in `impl Read for
  &[u8]`), `&mut self` of an impl for a view type is `inout [u8]`, `impl
  Tr for [T]` and `impl Tr for &[T]` cannot both be written, a `T: ?Sized`
  parameter is not told from a sized one (`?Sized` is not recorded), and
  `NonNull<[u8]>`/`Box<[u8], A>` are 8 bytes (the field `*const T` with T
  a view is thin; rustc: 16). The change is a type form of its own for
  the unsized place behind a reference, read by `resolve_type`, method
  lookup on slices and `str`, indexing, `len`, the coercions, the places
  IR, layout and the borrow checker's slots: about a week of wide front
  work, near MVS's shared type code. It blocks 6 std2 cases: the five
  `std2_io_` cases of `impl Read for &[u8]` and `std2_str_pattern`
  (`impl Pattern for &str`). 0.27.2.1 has the parts that do not need it:
  `size_of_val` of a view (its length times the element's size) and
  `size_of::<[T]>()`/`size_of::<str>()` as `type.unsized`.
  (0.27.3) Stage 1 is Z9.1b; stage 2, the change above, is Z9.1c. Until stage 2, a view written as an
  element or argument, `Vec<[i64]>`, is the view (`Vec<&[i64]>`) and is
  accepted; rustc rejects it (E0277), F21.2's `type.unsized` under stage
  2 (rust_capture_view_copy writes `Vec<&[i64]>`).
- **FL11 (the opaque instance's type errors; 0.27.3).** borrowck.md
  D22.2: an opaque instance reports its type errors as rustc does
  (`x + x` of `T: Add<Output = T>` returned as an i64 is E0308), unless
  it is *unsure*: it meets a gap of the model, and its errors are
  forgotten. The model now covers operators on an Ω through its bounds,
  a bound's type arguments and a trait parameter's default, `T::f()` and
  `T::CONST` of a bound's trait, `*x` with `Deref`, `g[i]` with `Index`.
  The gaps left, each an unsure instance, so reporting nothing where
  rustc may: a generic method of a generic trait (`contains<U>` of
  `RangeBounds<T>`), a `where` predicate in the template, a bound an Ω
  does not resolve while the instance is made (an impl parameter fixed
  only by another's bound, F14.1). An `#[array_builtin(N)]` template has
  no opaque instance. Cases `rust_b_opaque_err_type_mismatch`,
  `rust_b_opaque_err_bound_args`, `rust_b_opaque_ok_model`.

- **FL12 (a union's field that needs a drop; 0.27.3).** rustc rejects a
  union field that is neither `Copy` nor `ManuallyDrop<_>` (E0740, a
  generic `T` too); vole accepts it and drops no field (F19.7), so std2
  can write `ManuallyDrop<T>` as a union over a `T`. Case
  `rust_f_f19_union_no_drop` (`// RUSTC: none FL12`).
- **FL13 (an array's by-value iterator; 0.27.3, until const generics,
  0.29).** Rust's `std::array::IntoIter<T, const N: usize>` is std2's
  `IntoIter<T, Arr>` with `Arr = [T; N]` (`IntoIter<i64, [i64; 3]>`),
  its impls `#[array_builtin(N)]` (F15.3): a type parameter stands for
  the length a const parameter would carry. A program that names the
  type writes `IntoIter<T, [T; N]>` where Rust writes `IntoIter<T, N>`;
  one that only calls `into_iter()`, or loops over `[T; N]` by value,
  is Rust's. Const generics retire it: std2's type becomes Rust's.
  Cases `rust_f_fl13_array_iter_partial_drop`,
  `rust_f_fl13_array_iter_break`, `rust_f_fl13_array_iter_by_value`.

- **FL12 (a byte string is `&[u8]`; 0.27.3).** F23.2: `b"…"` is typed
  `&[u8]`, not `&'static [u8; n]`: `let a: &[u8; 2] = b"ab";` and
  `*b"ab"` are rejected where rustc accepts them; where `&[u8]` goes (the
  usual use) the two agree. Case `rust_f_f23_byte_string_ok`.

## 10. The gap map

Every gap of the std272 M1 and M2 lists, and the rule that closes it
(the number is the list's).

| M1 gap | rule | M2 gap | rule |
|---|---|---|---|
| 1 `?` on std2's Result | Z3.1 (`option`/`result` keys) | 1 `pub(crate)` fields | F24.1 |
| 2 `for` over std2 iterators | F22.1 | 2 Step/Ord/Sum for primitives | F15.1 |
| 3 string-literal typing | F23.1 | 3 blanket `IntoIterator for I` | F4.1, F4.2 |
| 4 char literals are `u8` | F1.2 | 4 `<` on `T: PartialOrd` | F26.2 |
| 5 byte literals | F23.2 | 5 `Clone` for `Gpa` | F17.3, Z1.2 |
| 6 integer-literal inference | F18.3 | 6 byte literals | F23.2 |
| 7 empty array literal | F23.3 | 7 `impl_on_instance` | F5.1, F14.1 |
| 8 fat-pointer casts | Z9.3 | 8 blanket `Borrow<T> for T` | F4.1, F4.2 |
| 9 unit-struct value | F7.3 | 9 unit struct as a value | F7.3 |
| 10 `Debug::fmt(v, f)` | F8.2 | 10 `size_of::<T>()` | F19.4 |
| 11 `primitive_builtin` | F15.1 | 11 struct pattern in `let` | F27.1 |
| 12 multi-impl `SliceIndex` | F13.1, F14.1, F20.2 | 12 `Self { .. }` in generic impls | F5.4 |
| 13 `partial_cmp` on `[i64]` | F5.1, F6.2, Z9.2 | 13 int→ptr cast is unsafe | F29.1 |
| 14 `panic("..{}..", x)` | F16.2 | 14 `!` on integers | F26.1 |
| 15 `mem::size_of` | F19.4 | 15 Display/Debug for `i32`, `u8` | F15.1 |
| 16 closure-parameter inference | F18.1 (D20.3) | 16 `extern fn write` | F16.1 |
| 17 `&s[a..b]` vs `s` in `if` | Z9.2 | 17 `unsafe fn` pointer fields | F19.3 |
| 18 `Clone` for `Gpa` | F17.3, Z1.2 | | |
| 19 `p.add(1)` on `*T` | F5.1 (`impl<T> *const T` in std2's `ptr`) | | |

The M3a list (thread, char, hash helpers):

| M3a gap | rule |
|---|---|
| 1 `&(*p).field` is a raw pointer | F30.1 (a reference), F30.2 (`&raw` for the address) |
| 2 `drop_in_place`, `size_of_val` on `?Sized` | F21.4 (`[T]`, `str`); other DSTs `edition.later: dst` (0.29) |
| 3 atomics by name in std | Z3.1 (the atomic keys); `std::sync` is std's, 0.27.3 |
| 4 `unsafe fn` pointer types | F19.3 |
| 5 `==`, `<` on non-primitive types | F26.1 (every type, through the trait), F26.2 (on `T`) |
| 6 `TryFrom` for primitives | F15.5 (written in std2) |
| 7 panic's caller location | F31.1 |
| 8 derive with an empty enum; program derives vs std2's traits | F17.4 |
| 9 unit-struct values | F7.3 |
| 10 `char` | F1 |
| 11 no `transmute` | F19.5 |
| 12 Unicode tables | not the front's: std2's approximations stand in 0.27.2; a `unicode` module is std's, 0.27.3 |
| 13 byte literals; `u32` wrapping/saturating | F23.2; F15.4 |
| 14 array-to-slice coercion at a call | F32.1 |
| 15 `v = &v[96..]` rejected | borrowck's, not the front's: under Z9 the loan is of `*v` and the assignment to `v` kills nothing it holds (borrowck.md D2.3, D2.4); reported to clos272 as a Z9 IR-side case |
| 16 no `u128` | `edition.later: u128` (0.29), F29.3 |

M1's "to decide": `[T]::len`, `as_ptr`, `str::as_bytes` are F21.4's
intrinsics (their written bodies are placeholders); `ptr::read`/
`write` are F21.4's siblings in `ptr` (keys `ptr_read`, `ptr_write`:
a bitwise move that drops nothing, as MVS's raw store does). The
`features.tsv` names map: `char` F1; `fn_once` D19 (clos272);
`impl_for_ref` F6; `slice_index` F20; `assoc_bounds` F11;
`qualified_path` F8; `return_inference` F18; `assoc_const` F3;
`blanket_impl` F4; `auto_trait` borrowck.md §24 (clos272);
`rust_derives` F17; `format_fns` F16; `impl_on_instance` F5;
`array_builtin` F15.3; `primitive_builtin` F15.1; `where_bound` F10;
`supertrait` F2; `tuple_struct` F7; `impl_param_in_trait` F14;
`generic_trait_multi_impl` F13; `generic_trait_default` F12;
`method_name_clash` F9; `std2_root` Z4; `size_of_name` F19.4;
`str_slice_self` F20.3; `unit_struct` F7.3; `use_self` F19.2;
`unsafe_fn_ptr` F19.3; `try_std2` Z3.1; `unsized_cast` Z9.3.

## 11. Implementation notes (non-normative)

- **Order of the passes.** Collect traits and impls (F2.1, F3.1, F4.1,
  F13.1, F15.1's synthesis), then F14.1 and F2.3 per impl, then F4.2
  over the pairs (by trait: the pairs of one trait only), then
  signatures (F11.1, F12.1's copies), then bodies. The overlap check
  is `O(Σ_Tr n_Tr²)` unifications; std2 has about 1,400 items and the
  largest trait family (`Iterator`'s impls) is under 60: measured by the
  `std-rust` cost row.
- **The impl table.** `ImplInfo` gains the header's self-type node, the
  trait argument nodes and the `where` list; `has_impl(tr, t)` becomes
  `impls_applying(goal) -> list` with the F0.3 unifier, memoized per
  goal in the instantiation cache (`InstIndex`), since F0.4 is called at
  every method probe step.
- **Per-instance checking and D22.3.** 0.27.2 keeps 0.5's per-instance
  body check; D22.3 is enforced by `require_in_bounds` on every use of
  a parameter-typed value, with the concrete type at hand only for the
  `try:`. The opaque instance (0.27.2.1) replaces nothing here: it adds
  the check of uninstantiated templates.
- **Gating.** Each rule's site tests `rust_at(pos)` once, at the entry
  of the changed function, and falls into the MVS code otherwise; no
  MVS code path is moved. The MVS suite and the compile-cost rows
  (hello, std, check ≤ 1.03x) are the witness.
- **The corpus.** `tests/run/rust_f_<rule>_<ok|err>_*.vl`, one positive
  and one negative case per rule (≥ 60), each `// RULE: F..` and, where
  rustc disagrees, `// RUSTC: .. FLn|FRn`.
