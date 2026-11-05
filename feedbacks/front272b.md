# front272b: the rust edition's fn-type unsafety, arrays over a length, M2's gaps (0.27.2)

## What landed

| item | rule | commit | cases |
|---|---|---|---|
| unsafety in fn types | F19.3, FL9, FL10 | 69bd9b63, bf67464b (FL) | rust_f_f19_unsafe_fn_ok/_err, rust_f_f19_c_ptr_err, rust_f_f19_closure_err |
| arrays over their length | F15.3 | bf67464b | rust_f_f15_array_ok/_err |
| char is no u32 | F1.2 | fd114bcd | rust_f_f1_char_u32_err |
| one autoref | F6.2 | fd114bcd | rust_f_f6_autoref_self_err |
| generic impls' consts | F3.2 | fd114bcd | rust_f_f3_generic_const_ok/_err |
| attr.builtin outside std2 | F15.1 | left for the switch | — |

Each passed `premerge: ok` and `tests/affected.sh`. std2's root check:
edition.later 2 -> 0 after F15.3.

## Notes for whoever comes next

- A fn type's `b` is now two bits: ABI (FN_TY_C) and unsafe
  (FN_TY_UNSAFE). Read it through `fn_ty_c` / `fn_ty_unsafe`, never as
  `b != 0`. The effects and the own pass key fn values by
  `fn_ty_safe(t)`.
- A length parameter is an ordinary type parameter bound to `[(); n]`
  (`generics::instantiate::length_type`, `length_of`). Every walker over
  type nodes that looks for parameters has to look at `[T; N]`'s length
  node as well (`array_len_name`): unify, match_type, mentions_unbound
  and names_sym do; coherence's overlap test ignores lengths (all
  lengths unify), which is right for a template.
- A char literal is read as its u32 scalar only while CHAR_SCALAR is
  set (a `char` pattern's literals).
- Open: F6.2's probe matches by "methods of τᵢ", not rustc's receiver
  type, so `r.tag()` on `r: &S` picks `<&S as Tag>::tag` (`&self`) over
  `S::tag(&self)`; rustc picks the latter (rust_f_f6_ref_ok encodes
  vole's answer). Reported for the spec.
- Open: attr.builtin outside std2 needs std2 loaded to keep a positive
  case; do it with the switch and move rust_f_f15_builtin_ok into std2.

## The tools

- `edit patch` on an item whose new text calls a function inserted in
  the same step fails the check (the function does not exist yet);
  inserting the helper first, then patching, works.
- The hook's `volec check` after a test program's edit uses
  target/tools/volec (0.27.1), so on a feature the branch adds it
  reports the old errors (edition.later): noise while working on
  rust-edition features.
- tests/borrowck-twin.sh disagrees on 57 of 66 rust_f cases because they
  use `std::print_int` and `main() -> i64`: the twin is not usable as an
  oracle for the corpus as written; I ran rustc by hand on Rust
  translations.
