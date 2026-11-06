# clos272: closures in full, auto traits, the std side of the IR (0.27.2)

## Verdict

M0-M2 done as specified (borrowck.md §19, §20, §24's AT1-AT3, D10.4 and
D10.5 superseded); M3's IR side mostly: Z7's std2-check row, Z8 (the own
pass off), Z9's IR (unsized places behind a pointer, a fat raw pointer
without a region of its own, R12 deleted), AT2's std2 vouches and AT6
(`thread::scope` by bounds and the borrow checker), and Z7's on-disk
verdict cache. The last round: borrowck's messages in rustc's place
names, println's `&mut` and value arguments (I7, a leak), calls through
`&F`/`&mut F`, a projection in a closure's bound (D20.3). Left: std2's
remaining borrowck errors, most from `T = str` instances (front272's
Z9.1); the twin's subset at 150 with `--std2`.

## What to fix, with a tag

- [tool] The check-after-edit hook checks a rust-edition test case as
  MVS (or with the hook's 0.27.1 binary): every new `rust_b_` case gets
  "50 errors" in std2 positions, which is noise to read past each time.
  Read the case's `// EDITION: rust` line and use the worktree's build.
- [tool] `volec edit patch` with several pairs applies none when one
  fails, but a run of several independent `edit patch` calls in one
  script re-applies the ones that did succeed on a second run (a
  duplicated block in slot_variances_in). Report "already applied" when
  NEW is present and OLD is not.
- [tool] The query-first hook blocks a whole compound line for one
  `grep` of compiler/src, including the edits before it: the edits did
  not run, which is easy to miss. Say first that nothing ran (it does)
  and keep that line short.
- [borrowck] A std2 borrowck error names no instance (§14.2 says it
  adds `in f<..>` and the call): finding which instance of
  `Clone::clone_from` fails took a debug print in check_body. Name the
  instance, even in the region-free run.
- [spec] D2.5 (2) read only the first projection past the access for a
  shallow access; rustc's Shallow(None) stops at any deref. Found by
  AT6 (a by-value env's exit), fixed in the spec first.
- [spec] D4.5's declared `T: 'a` had no implementation: the parser
  dropped type parameters' lifetime bounds. Now kept (outlives_of); a
  case per bound form would have shown it earlier.
- [front] The rust derive writes `impl Clone for Chars` with no
  lifetime, so a derived method's `Self` has an elided slot that E3 ties
  to `&self`: four of std2's borrowck errors (`Chars::clone_from`).
  Write the item's lifetimes in the impl header.
- [front] std2's `[T]` instances with `T = str` (a view where `&str`
  is meant) give two outlives errors (`[T]::iter`, `Iter::next`): Z9.1.
- [borrowck] A closure whose bound names a projection (`F: FnMut(B,
  Self::Item) -> B`) reads the projection's regions as bound regions of
  the closure (D20.3): `Iterator::last`'s `|_, x| Some(x)` on
  Graphemes is outlives. Treating them as external is not enough: the
  instance must tie the X_C position to the projection's resolved slot,
  as subst_requirements does for a type parameter's.
- [tool] tests/run.sh sampled `--verify-places` by the case's whole path,
  so each worktree verified a different half: an I7 failure showed in
  one tree and not in the integrator's. Now by the file name.
- [tool] `git stash` is shared by every worktree and session; a check of
  "does the base fail too" is a WIP commit, not a stash.
- [front] `v.iter().map(|x| x + 1).last()` on std2 is type.infer: "cannot
  infer type parameter 'B' of 'Map<I, F>::fold'" (<std>:11080, the default
  `last` through Map's own `fold`).
- [borrowck] D20.3's tie was made only in the template whose bound the
  closure was checked against; a closure passed on (`reduce`'s to `fold`)
  must be read with each template's bound of the parameter it fills.
