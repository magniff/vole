# Feedback: placesir260, the places IR (steps 1 to 3a of places-ir.md §8)

2026-10-30, release 0.26.0. compiler/src/places/ (ir, cfg, print, verify,
build, front, mod and a README: about 3,700 lines), front/own/byref.vl
(the borrowed-copy predicates moved out of drops.vl and moves.vl), a
block flag in front/ast.vl set by check_try and requires_call, two
counters in base/timer.vl. Stopped after 2a at the brief's stop (the
builder over its budget); the fallback was agreed and 2b, 2c and 3a
(match, closures, elaboration, the backstop, `--places-diff`, `//
PLACES:`) followed behind `--places`.

## Verdict

The contract and the builder went in without a crash over compiler/src
and the 2,714 tests/run sources, and `--verify-places` is clean on both.
The cost was in two places: reading the own pass's desugarings (its
temporaries, `__own_new` and `=o` reassignments, transparent blocks) to
lower them back into places, and finding out late what the builder
costs. The instruction count needs the whole `tests/compile_cost.sh`; a
per-pass instruction count would have shown the 433M after the first
hundred lines.

## What cost time, ranked

1. **[perf] No per-pass instruction count.** `--time-passes` gives
   milliseconds; the budget is instructions. I measured by building
   variants (one skipping the body's lowering) and diffing
   `/usr/bin/time -l`, about 20 s each, and `sample` at 1 ms gave ~17
   samples per run, too few for a flat profile.
2. **[hook] One blocked command blocks the whole line,** including a
   `grep -c` of my own new files under compiler/src/places; the line it
   gives back is right, but a shell `cat >` waiting on stdin in the same
   line went to the background and hung for 120 s.
3. **[doc] The own pass's desugarings are documented only in code.**
   `lower_own_assign` had to recognize `{ let __own_new = rhs; { let =o =
   p; p = __own_new; } }` from the printed AST; a paragraph in
   front/own/README listing each shape would have saved an hour.
4. **[conv] `env::var` is refused as Rust's name** with a clear `try:`;
   cheap, but the error came from the bootstrap build, not the hook,
   because the edit was a Python script.

5. **[tool:diff] The own pass's decisions have no reader.** `--places-diff`
   needed three accessors added to drops.vl (own_row_*); its first run
   listed 11,321 differences, nearly all of form (`?try` opened where the
   own pass knew the arm moved it), which took four rounds of sweeps
   (each 2,700 sources, about 3 minutes) to bring to 5.
6. **[doc] The own pass's hidden bindings' rules live in let_drops.**
   `=`-named lets borrow, a let of a static borrows, a `$pre` call reads
   in place, a by-access closure's env copies: each found from a diff
   line, then in drops.vl's code.

## What worked

- `query context NAME` on finish_drops, borrowed_call and own_rewrite:
  the callers and callees in one call, enough to mirror their rules.
- `refactor move` for step 1 (ten items to byref.vl, every path fixed).
- The sweep: `check --verify-places --places-diff` over every tests/run
  source with xargs -P 6, one result file per case: 0 crashes from the
  first run, and the diff's classes counted with sort | uniq -c.
- The verifier: its `as V` dominance and storage checks caught the
  builder's and elaboration's block mistakes before any diff did.

## Never used

`probe`, `reduce`, `batch`, `undo`, `rewrite`.

## Fix list, in order

1. [perf] `--time-passes --instructions` (or a pass's instructions read
   from the cycle counter): the budget's unit, per pass.
2. [doc] front/own/README: each desugaring's shape, the names it makes
   (`__own_tp`, `__own_tf`, `__own_tv`, `__own_new`, `=o`, `__for_seq`).
3. [hook] query-first: allow `grep`/`wc` of files the session created
   under compiler/src.
4. [doc] front/own: a list of the own pass's borrowed-copy rules (the
   bindings let_drops leaves undropped), for the IR's builder to mirror.
