# Feedback: placesir261a, the places IR, agent A's half of 0.26.1

2026-10-30, release 0.26.1, branch placesir260. R1 (kept bodies,
places/keep.vl) and R2 (drop shims, places/shim.vl) for agent B; step
2, the builder's cost (544M to 421M of `check`); step 6's front half,
the drop edges into effects; step 9's `query drops`. The switch (step
6's default) and step 7 wait for B's steps 4 and 5.

## Verdict

Everything that did not wait on B went in, each with a sweep over
compiler/src and the 2,718 tests/run sources: the kept bodies print the
same IR as fresh ones, the shims verify, the lean storage markers leave
every drop decision as it was, the backstop adds no error, and the
effects with the IR's edges instead of the placeholders' differ in 3
functions of 20,275, each more precise. The IR on by default already
fits its share (`check` 1.08x of 0.25.5 with the placeholders still in).

## What worked

- Byte-identical `--emit-places` output of a fixed copy of compiler/src
  (1.6M lines) as the check of every representation change: a `cmp`
  after each build, no test needed.
- A build that runs the builder 200 times over, for both a usable
  `sample` profile (3,000 samples instead of 17) and a per-pass
  instruction count ((I - I0) / 200) without a per-pass counter.
- An uncommitted experiment build (the effect walk skipping the
  placeholders) to see step 7's effects before step 7.
- `edit patch NAME --old --new --in OTHER ...`: several functions'
  edits in one checked call.

## What cost time, ranked

1. [perf] The 0.26.0 measurement of `hello`'s +23M was the shell
   wrapper that added `--places`: `/usr/bin/time` counts the shell. Any
   flag added this way inflates every row by 22.7M. An env variable for
   compiler options (`VOLE_FLAGS`) in tests/compile_cost.sh would avoid
   it.
2. [hook] query-first blocks a `grep` of my own new files under
   compiler/src/places (the 0.26.0 fix list's #3, still open), and a
   pipe into `head` on a long `tests/query/run.sh` broke the run (the
   run's printf on a closed pipe).
3. [tool] `edit patch` cannot add a parameter at a dozen call sites by
   line; `refactor signature` would have, but its form for "add a
   parameter whose value differs per call" was unclear, so a script did
   it.
4. [conv] `KEPT[f] = w` on a static `Vec<Vec<i64>>` reports "undefined
   variable 'places.keep.KEPT'"; `KEPT.set(f, w)` works. The message
   names the wrong thing.

## Never used

`reduce`, `rewrite`, `refactor extract-function`, `undo`.

## Second round (shims as functions, R3, R4)

- `probe` on the compiler itself (`probe compiler/src/places/build.vl:L
  t integer is_enum -- prog.vl --emit-places`) found in three runs why
  an enum match stayed a chain (its arms match through the reference,
  PAT_DEREF): the fastest tool of the round. An enum prints as
  `<NodeKind>`; `kind as i64` works.
- `edit patch` of two items in one shell line: the second patch's check
  failed on the first's not yet existing static and printed the whole
  command back with `--no-check`, with no error line saying why.
- `tests/affected.sh` after the integrator merged the branch: the plan
  is empty (`0 of 2867`), since the default base contains HEAD; against
  the previous base a one-function change in front/check/mod.vl is
  `@broad` (2,461 cases).

## Fix list, in order

1. [perf] tests/compile_cost.sh: compiler options from an env variable
   (no wrapper), and a note that a wrapper script counts its shell.
2. [conv] the checker's message for an element assignment into a static
   `Vec<Vec<T>>`: say what is unsupported, `try:` `.set(i, v)`.
3. [hook] query-first: allow `grep`/`wc` of files the session created.
4. [doc] places/README: the shim's Drop::drop instance must be made by
   the shim once the placeholders go (step 7). (Done in the second
   round: made at check time.)
5. [tool] edit patch: a failed check says which error, before the
   `--no-check` retry line.
