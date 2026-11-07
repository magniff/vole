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
return). `volec fmt` keeps `b'x'` and `b"…"` as one token. *Anchor:*
`front/lexer/mod.vl: lex_number` (the `b` prefix), `front/lexer/
strings.vl`, `tools/fmt`.

**F23.3 (the empty array literal).** `[]` takes its type from the
expected type when there is one (`&mut []` against `&mut [T]`:
`[T; 0]`, then the unsize step); without one, `error type.infer` as
today. *Anchor:* `synth_mode.vl: synth_array` ("cannot infer the type
of an empty array").

**F23.4 (character literals).** F1.2.

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
..", today requiring `unsafe` for int→ptr), `front/check/unsafety.vl`.

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

**F30.2 (`&raw`).** `&raw const place` and `&raw mut place` are the
raw-pointer forms (`*const T`, `*mut T`), with no reference made and no
`unsafe` needed for a place through `*p` beyond the deref's; they are
what std2 writes where it wants the address (`&raw const (*p).field`).
Rust's reference "Borrow expressions" (raw borrows). *Anchor:* the
parser's unary `&` (`front/parser/exprs.vl`), `synth_unary`.

**F30.3 (no indexing of a raw pointer).** In a rust-edition position
`p[i]` and `p[a..b]` with `p: *const T` or `*mut T` are `error type`
("cannot index into a value of type `*mut T`", rustc E0608), as Rust's:
an element is `*p.add(i)` (`<*const T>::add`, unsafe, and `offset`,
`read`, `write`), a run of them `slice::from_raw_parts(p, n)` (F21.4).
A reference to an indexable type (`&[T]`, `&Vec<T, A>`, `&[T; N]`) is
indexed through, as before. MVS keeps its raw-pointer indexing.
*Anchor:* `front/check/synth_mode.vl: synth_index`.

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
`I: Iterator` finds `I::next` (receiver `&mut I`) at `τ₀` by value. A
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
*Anchor:* `front/parser/rust.vl: take_array_builtin`.

## 3. Names, calls and inference

### F8 Qualified paths

**F8.1 (`<τ as Tr<a..>>::name`).** Resolves `name` among `Tr`'s items
(methods, associated types, consts) with `Self := τ`; `τ: Tr<a..>` must
hold (F0.4, else `trait.unmet`). For a method the result is the
function value of the impl's (or builtin's, or default's) method; its
call passes the receiver explicitly. In type position
`<τ as Tr>::A` is F11.3's projection. *Anchor:* `front/parser/rust.vl:
qualified_path` (today `edition.later`), `split_shl`, `synth_path`.

**F8.2 (`Tr::name`).** A trait name used as a path head (`Debug::fmt(v,
f)`, `Iterator::next(&mut it)`, `Default::default()`) is `<_ as
Tr>::name` with `Self` inferred from the first argument's type (a
method; through F6.2's adjustments of that argument: `Debug::fmt(v, f)`
with `v: &T` finds `T: Debug`) or from the expected type (an
associated function, F18.1). Neither: `error type.infer` with `try: <T
as Tr>::name`. *Anchor:* `front/check/resolve.vl: resolve_key` (today
"is a trait, not a type"), `path_target`.

**F8.3 (`<τ>::name`, `τ::name`).** The inherent namespace of `τ` first;
then, with `τ` concrete, the traits in scope (F9.2) that `τ` implements
and that declare `name`; with `τ` a parameter, its bounds (F0.4a).
Ambiguity is F9.3's. `<τ>::name` with an explicit type is what
disambiguates a primitive (`<i64>::MAX`, `<[T]>::len`).

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

**F18.2 (no expected type).** `let x = Vec::new_in(a);` with `T` fixed
by a later `x.push(1)` is **not** inferred in 0.27.2 (vole has no
deferred unification variables; FL1, `edition.later: deferred_infer
(0.27.4)`, with the compiler's own move to the edition, where it will
matter; the translator of 0.27.3 writes the annotation from MVS's known
types). The error is `type.infer` at the `let`; its `try:` gives the
annotation the first later use determines when the checker can see one
(`try: let x: Vec<i64, Gpa> = Vec::new_in(a)`: the first method call,
assignment or argument of `x` in the body whose parameter type binds
`T`), else the turbofish. std2 and the corpus annotate.

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

**F18.4 (a hoisted literal takes the let's annotation).** `let r: &U = &e;`
with `e` a literal (an array, an integer, a float, a tuple) makes its
temporary (lifetime extension) with the annotation's type: `let d: &[u8]
= &[1, 2, 3];` is `let t: [u8; 3] = [1, 2, 3]; let d: &[u8] = &t;`, so
the literals are `u8`, not the default. *Anchor:* `front/check/temps.vl:
annotate_temp`. Integer inference variables (a literal typed by a later
statement, `let a = [1, 2]; f(&a)` with `f(&[u8])`) stay FL6's, 0.27.3.

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

**F26.3 (a comparison's right operand of another type).** On std2, `a
== b`, `a < b` and the others with `a` of a struct or enum type and `b`
of another (not a literal that takes its type from context; an array
literal does not) check `b` alone: the impl of `PartialEq<Rhs>` or
`PartialOrd<Rhs>` its type picks decides (`s == "x"` with `impl
PartialEq<str> for String`, `v == [1, 2]`, `v == other_vec_in_arena`).
When the operand is a view (`[T]`, `str`, Z9.1, where `&str` is the view
too), an impl whose argument is written `&..` yields to one that is not:
`PartialEq<str>` and `PartialEq<&'a str>` compare alike (0.27.2.1). An
arithmetic operator's right operand stays checked against `a`'s type in
0.27.2.1: the operator call frees a by-value operand that drops twice.
*Anchor:* `front/check/synth_mode.vl: synth_operands`,
`front/convert: by_view_rhs`. Case `rust_f_f26_cmp_rhs_ok`.

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
`fmt::Result` (or `io::Result<()>` for an `io::Write` writer); the
print functions return `()`. The lowering is rust-edition generated
code (Z1): the trait calls are F0.5's and go through F15.1's intrinsic
impls for primitives (the number formatting MVS has). *Anchor:*
`front/check/interp.vl: direct_body` (today: MVS's `__print_begin`,
`Fmt::display`), `format.vl: panic_call`.

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
autoref) use `index_mut`; a `τ` with `Index` but no `IndexMut` is
`error trait.unmet` naming `IndexMut` (E0594's shape).

**F20.5 (a tuple index of literals).** `g[(0, 1)]` with `G:
Index<(usize, usize)>`: a tuple of unsuffixed literals takes its
elements' types from the impl's index type, as one literal does
(`(i64, i64)` only when no impl takes an integer tuple; 0.27.2.1).
*Anchor:* `front/convert: literal_kind, literal_tuple_fits`. Case
`rust_f_f20_tuple_index_ok`.

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
| `type.infer` | F18.1, F18.2, F7.3, F8.2 | E0282 | `g::<τ>(..)`, `let x: τ` |
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

**Strict (vole rejects what rustc accepts).**
- **FL1 (no deferred inference; later, 0.27.4).** F18.2: a parameter
  fixed only by a later statement is `type.infer` (its `try:` the
  annotation the first use determines); rustc's unification variables
  infer it. Deferred inference comes with 0.27.4, when the compiler's
  own source moves to the edition.
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
- **FL6 (integer literal default).** F18.3's context rule is rustc's;
  the fallback `i32` is too, but vole does not run rustc's full
  fallback after unification (a literal reaching no context through a
  chain of generic calls is `i32` at once). Also, no float-literal
  fallback interplay. (0.27.2: the fallback is still `i64`. Switching
  it alone fails 206 of the 1,962 rust_/std2_/error cases, because a
  literal is typed where it is met: `let a = [1, 2, 3]` is `[i32; 3]`
  before `f(&a)` with `&[i64]`. It waits for integer inference
  variables, resolved at the first constraining use, with the `i32`
  fallback at the end of the function: 0.27.3.)
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
