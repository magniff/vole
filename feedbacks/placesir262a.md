# Feedback: placesir262a, the places IR's drops and the own pass's drop half

2026-10-31, release 0.26.2. Agent A2's stream: the builder's own statement
temporaries and assignment drops (step 1), the old value dropped at every
owned assignment, contract and assert conditions in the IR (one branch per
conjunct), R11 (drop shims found by the erased type, `--verify-places`
checking every kept drop's shim), and step 7: the own pass's drop half
deleted.

## Verdict

The deletion was mostly mechanical once the dependencies were mapped, and
the tools made the mapping cheap: `query refs` per name, `query items`,
`edit apply` with dozens of `@@ delete` blocks in one checked step. What
the brief's list did not say, and cost the time, were the side effects
the deleted code had: the glue's `place.drop()` calls were what made the
checker check std's lazy `drop` methods (a link error at the fixpoint's
second build), the walk's defers were where the views checker saw a
local "dropped" (its messages, and the break and continue paths), and the
placeholders were the drops' calls the effects and `query refs`/`callees`
saw at a check, where the IR was not built (a `#[effects]` violation by a
drop passed `check`; found by a probe, not by a test: none checked it at
`check`).

## What worked

- `edit apply FILE` with `@@ delete` and `@@ NAME` blocks: drops.vl lost
  1,600 lines in one edit, then the callers file by file with `edit patch
  --no-check` and one `check` at the end.
- `query refs NAME --count` over every name the deletion touches, before
  and after: which pub items had readers outside drops.vl, which flags
  were only ever set (ARM_FOR_NEXT, GLUE_MATCH), which glue.vl builder was
  dead.
- The bootstrap's two builds: build 1 (by 0.25.5) found a missing body,
  build 2 (by the new compiler) the missing `drop` symbols, each with the
  function named by `--time-passes`' counts.
- The experiment build from step 1 (the own pass's temporaries off):
  it had already said which hidden `let`s the walk needs.

## What cost time, ranked

1. `edit apply` refuses a deletion of a file's last item when another
   block also touches the item before it ("changed twice in one edit"):
   three retries, each by removing the last item from the file and
   deleting it alone.
2. A first `edit apply` whose output I filtered away, so it looked as if
   nothing happened, and my rerun with `--no-check` inserted every new item
   a second time (my mistake; the check would have refused the duplicates).
3. The hook's `volec` (target/tools) is older than the tree: its `try:`
   lines and std "refused" suggestions are noise until the tools are
   refreshed.
4. zsh does not split `$V` into words: a command in a variable runs as
   one word.

## Never used

`refactor rename` (the names that changed meaning kept them: param_drops,
let_drops, arm_drops), `rewrite`, `batch`, `undo`.

## Fix list, in order (tagged)

1. [tool] `edit apply`: deleting the last item of a file next to another
   block for the item before it should not be an overlap.
2. [tool] `edit insert`/`apply --no-check`: refuse an item whose name the
   module already has, even unchecked.
3. [test] The ERROR directive runs a build only: a case's errors at
   `check` (the path the tools and the LSP take) are not tested; a
   `// CHECK-ERROR:` (or ERROR at both) would have caught the effects gap.
4. [process] A brief that deletes code should name what the code did as
   a side effect (checking lazy std functions; the walk's events), not
   only what it was for.
