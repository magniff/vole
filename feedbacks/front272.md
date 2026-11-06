# front272: the rust edition's front, std2 switched in (0.27.2)

## Verdict

M0-M2 done by the earlier rounds. This round took gate 1: std2's 1,413
cases under --check-alloc pass 1,032 at -O0 and -O2 (552 when it
started), with 0 failing among rust_, std2_ and error. What got them
passing: range literals as std2's ops types (Z3.1), std2's
write/writeln, a hole's spec, `{:#?}`, char's and arrays' Debug (F16),
deref coercion (F32.1), `&mut F` as FnMut/FnOnce (F33.1), a default's
own parameters apart from the impl's (F12.2), an impl's free parameter
from its bounds (F14.1), a trait path call keeping its trait (F8.2), and
Z4.1 (no edition.std_copy or std_by_value on std2). Left of M3: Z9.1 (the
unsized representation: `&mut &[u8]` collapses to `&mut [u8]`, so
`*self = &self[n..]` in `impl Read for &[u8]` cannot be written, and
`impl Tr for [T]` and `for &[T]` cannot coexist), F18.3's i32 default,
Z5/Z6 checks, arrays' by-value into_iter (it needs const generics).

## What to fix, with a tag

- [front] find_assoc kept its choice in pcx.found_impl while
  impl_covers searched impls again and overwrote it, which paired one
  impl with another's associated type definition. It took a day to see
  through "unknown module 'I'". Fixed: locals. Any global "result of the
  last search" that a nested search can overwrite is this bug again:
  pcx.found_other, pcx.try_result and assoc_trait are the same kind.
- [front] subst_trait_args renames a Generics node's own TyName params
  in place before it walks the parameters that name them. A walk that
  substitutes the names of a node it also visits needs the binder left
  out (rename_own_params does that by hand).
- [front] A for loop over an array value of non-Copy elements reads them
  by reference (F22.1), since the places IR does not follow moves out of
  an index. Vec::from_in works around it with pointer reads. This is a
  soundness gap for a borrowck stream (main's 0.27.2.1 list).
- [tool] `volec probe` was the fastest way into the checker: a value at
  a line in the compiler, on a rust program, in one call. lldb on a -g
  build found the callers but no locals ("no variable information").
  Giving the -g build's frames their variables would remove most of the
  probe round trips.
- [tool] The check-after-edit hook checks a scratch rust program with
  the stale binary and MVS std ("50 errors" from compiler/std): it
  should use the worktree's build and read `// EDITION: rust`.
- [tool] A query-first block of a compound line runs none of it,
  including a probe that is many seconds into a build. Say so before the
  long explanation (it does) and keep the rerun line short.
- [tests] VOLE_TEST_XFAIL_WHY (each XFAIL case's first error in a file)
  was what made "largest group first" workable: group by the message
  with names masked. A `tests/run.sh --why-groups` printing those groups
  would save every front agent the same script.
- [process] Running affected while editing (even std2 files or a scratch
  build in the tree) gives "compiles: changed during the run" and a
  stale checklist. That cost two reruns: edit only in a copy while it
  runs.
