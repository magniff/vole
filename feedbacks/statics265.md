# statics265: the rest of the compiler's statics into contexts (0.26.5, item f)

## Verdict

In progress. P0, the tool: `fix --only statics` now does the by-hand
steps of 0.26.4 (fix list 1, 6, 7, 8, 10, 12 of feedbacks/statics264.md),
each with a case in tests/refactor/statics0265.t. P4: 772 statics into
`base::ctx::Ctx`, one run of the tool, 16 lines by hand; 1,234 statics to
451. The 70 tables tasks read wait for P5's thread bridge.

## What worked

- `--prune crate` on a group of every static of base, front, places and
  the tools (860): 63 rounds in 2.3 s, 790 kept; the 70 dropped are
  exactly what code generation's tasks reach (worker_main,
  asm_thread_main), which is P5's.

- The whole P4 rewrite in a scratch worktree first (`git worktree add`
  in the scratchpad): the errors left (10 own.conflicts, 6 private types,
  a private module) were known before the real run, which was then a
  script: ctx.vl generated from the group, the tool, a fixer for the ten.
- A trial build's fixpoint before touching the branch: 3,441 functions
  changed and the fixpoint held on the first real run.

- P5b's view as a group line (`view middle::threads::take_tasks EXPR`)
  and `--prune crate`: 253 statics the tasks touch pruned to the 105 no
  task's code writes in one run, and the trial's fixpoint held first time;
  tests/threads_writes.sh then needed only its lists renamed
  (`base::ctx::Ctx.FIELD`) to cover the fields.

## What cost time, ranked

1. Imports. `use defs::{X}` (relative to its module), a `pub use` that
   re-exports a static, and two names next to each other in one `use`
   (two overlapping removals) each left an unresolved import; each needed
   a fix in the tool and another trial run.
2. The context's struct: the statics' types and initializers name types
   private to their modules (six made pub, InstIndex's fields too).
3. Format holes: the hole's name node is reached through the literal's
   checked form, not under the call it is given to, so the call is found
   in the text (the `(` before the literal).

## Never used

## Fix list, in order (tagged)

1. [tool] An argument after the context that lends it again
   (`lower_check(.., &pcx, site_of(n, 0, &pcx))`, the context before a
   defaulted parameter): own.conflict; ten taken into lets by hand. The
   tool could hoist it as it does a receiver's argument.
2. [tool] A method's receiver rooted at the context, given an argument
   that lends it, where the callee had the context before (F_HAS): not
   hoisted, because lends_context counts only the calls it edits.
3. [tool] Two deleted declarations with a blank line between them, the
   second at the end of the file: the second deletion overlaps the first
   (delete_lines takes the blank line before it) and is left.
4. [tool] `refactor table` converts only `X` with `X_COUNT`/`X_CAP`; the
   45 symbol- or node-indexed raw tables (`SYM_STRUCT: *i64` grown to a
   capacity, no count) are left raw, so moving them into the context
   removes no unsafe.
5. [tool] tests/refactor/run.sh's self_explain greps the source for
   `ERR_KIND = c"..."`: a static's name in a test's grep breaks when the
   static moves (now `(ERR_KIND|err_kind)`).
6. [tool] P5b: a re-exported static named in a `use` beside others
   (`use crate::front::check::{FNS, lookup_local}`, FNS front::types'
   through check's `pub use`) is left in the `use` when the re-export goes:
   one unresolved import, by hand.
7. [tool] A receiver already a field of the context (`pcx.scratch.push(
   eq_binary(.., &pcx))`) given an argument that now lends the context:
   own.conflict, three hoisted by hand; and an inout field argument beside
   the context let (`conjuncts(c, &pcx.conjs, pcx)`): one, taken out and
   put back by hand.
8. [tool] A view's prune followed one inout callee per round and stopped
   where the write was not an assignment (`note(&HITS)`): fixed in
   0.26.5 (every function below the view, one round).
9. [tool] tests/threads_writes.sh matches by name: a field's line `pcx.f`
   matches a method or `&` of another place's field of the same name on
   that line too (over-reports, never misses).
