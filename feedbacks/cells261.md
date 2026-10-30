# Feedback: cells261, UnsafeCell, Cell and Freeze (0.26.1)

2026-10-30, release 0.26.1. Every step of the brief is committed:
- the step-1 probes;
- std::cell and Freeze;
- the no-copy rules (for, byref, the iterator adapters);
- Sync and statics;
- the interior effect;
- the optimizer's facts;
- Atomic and Mutex on UnsafeCell;
- std::fmt's print state behind one immutable static;
- the docs.

## Verdict

Cells fit vole's model with few changes, because a `let` parameter of
an owned type is already a reference. Cell needed no new convention.
The work was finding every place that silently makes a bit copy of a
value:
- `for` over an array;
- byref's copies;
- the iterator adapters;
- GVN's shared-param facts.

The step-1 probes found these. Four of the nine probes lost the write.
The cost was mostly outside the compiler:
- the transcripts, book chapters and walkthroughs that quote effects and
  explain codes;
- std's core size budget, which the print-state change pressed against.

Compile cost (`tests/compile_cost.sh -r 5`): check 0.99x against the
base tools build and 1.00x against 0.25.5; hello 1.05x (std's core
+1133 bytes for fmt, and the cell sections).

## What worked

- Step-1 probes first. `cell_copy_*` and `opt_cell_alias_let_params`
  were written before any code, as XFAIL. Each fix turned one green, and
  the list of what was left was always visible.
- `volec query context` on byref, iterate and gvn: one call per
  unfamiliar pass.
- `edit patch --old/--new`, with several pairs and `--in OTHER` in one
  checked call. A step that needed a new helper first was refused
  (edit.breaks) without writing anything, and said so.
- `edit insert --before`: it added a std helper and regenerated stdsrc.vl
  in the same call (note edit.std).
- `tests/query/run.sh -u NAME` and `tests/lsp/run.sh -u`. Regenerating
  them and reading the diff was fast.
- An `inout` local made from a raw pointer
  (`inout st = unsafe { &*ps() };`). It made fmt's state access one line
  per function, with no reindented bodies: +1133 core bytes, where the
  first version, which took the pointer and put each body in an unsafe
  block, cost +2210.

## What cost time, ranked

1. The suites a front-end change reaches that tests/affected.map did not
   name: the book (contract.effect's text, the explain lists), the
   self_explain prefix list, guide-std-index's byte limit, calls016's
   callee count, and the walkthrough READMEs. Each failed only in the
   integrator's full suite. The map now has rules for them. About 1.5
   hours over two rounds.
2. std's core budget. The print state's first form was +2210 bytes.
   Finding what counts (comments and indentation do) and rewriting it
   lean took about 1 hour.
3. A stale `target/volec` after `git merge`: query failures that were
   the old build's (budget's duplicate suggestions). Rebuild after every
   merge, before testing.
4. The check hook runs `target/tools/volec` against the worktree's std,
   so a std change that needs a compiler change (the PrintCell vouch)
   prints a false `sync.static` on every program until the tools build
   is updated.
5. own.escape on a view returned from an `inout` local made from a raw
   pointer: std-own caught it and the fix was clear (fmt_take), but no
   per-case test showed it.

## Never used

- `refactor rename|move|signature`: no renames.
- `probe`, `reduce`: every failure named its line.
- `tests/affected.sh --linux`: macOS only for this release.

## Fix list, in order

1. [tests] tests/affected.map: a rule for every pass that owns
   diagnostic codes (own, threads, contracts, effects, explain) should
   name =book and =refactor (self_explain). Done here for these; others
   (conv, syntax, use) likely have the same gap.
2. [hooks] check-after-edit.py: when compiler/std differs from what
   target/tools/volec embeds, check with target/volec (or say the
   findings come from an older compiler).
3. [query] `query def` no-match listed std::gpu::wgsl::dump twice
   (recorded with agent-feedback; fixed by A in dcd5f4d3).
4. [std] What waits for 0.27's regions and auto traits: Arena,
   ScopedArena and FixedBuf on UnsafeCell; Chan handles and MutexGuard;
   std's other 224 `static var` (`query grep 'static var' --in std --code --count`; stdin's 3 first); variance; `Cell<&'a T>`;
   iter_item_copy on adapters like collect still copies cells silently.
