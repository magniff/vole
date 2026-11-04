# statics265: the rest of the compiler's statics into contexts (0.26.5, item f)

## Verdict

In progress. The tool first: `fix --only statics` now does the by-hand
steps of 0.26.4 (fix list 1, 6, 7, 8, 10, 12 of feedbacks/statics264.md),
each with a case in tests/refactor/statics0265.t.

## What worked

- `--prune crate` on a group of every static of base, front, places and
  the tools (860): 63 rounds in 2.3 s, 790 kept; the 70 dropped are
  exactly what code generation's tasks reach (worker_main,
  asm_thread_main), which is P5's.

## What cost time, ranked

1. Format holes: the hole's name node is reached through the literal's
   checked form, not under the call it is given to, so the call is found
   in the text (the `(` before the literal).

## Never used

## Fix list, in order (tagged)
