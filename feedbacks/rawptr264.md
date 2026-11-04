# rawptr264: the raw-pointer parameters decided (0.26.4, plan item e)

## Verdict

Done, with less unsafe removed than the plan expected. `volec fix --only
rawptr` (compiler/src/tools/fix/rawptr.vl) decided compiler/src's raw
pointer parameters in slot 2. Only four lines were edited by hand: two
`let` to `var` in link_macho, and the comments on two unsafe sites in
m_load.

The census, on release-0.26.4 at 136f9061, counted 2,583 parameters (the
plan's 3,903 was too high). `fix --only rawptr-list` prints each one:

| class | parameters | decision |
|---|---|---|
| only read | 580 (572 FnCtx) | inout (every one is a plain value over 16 bytes) |
| written through | 731 (722 FnCtx) | inout |
| caller gives a raw pointer | 105 (all FnCtx: thread and task roots) | inout, the call `&*q` |
| escape: C strings (`*u8`) | 813 | raw |
| escape: nested call | 141 | raw, to hoist later (below) |
| escape: indexed, offset | 211 (of all reasons) | raw |
| escape: passed on to a raw parameter used as an address | 713 (of all reasons) | raw |
| escape: given null, a C string, `&TABLE[i]` | 31 | raw |
| escape: stored, captured, compared, cast, assigned | 9 | raw |
| fixed: unsafe fn 7, exported 2, `**T`/`*[T]` 14, `self: *T` 5 | 28 | as written |

After the rewrite the census reads 0 read, 0 write, 0 caller: the
parameters left are all raw. std has 2 read, 21 escape and 193 fixed;
std was left alone (the chain rule, and too few to be worth it).

Unjustified unsafe sites in compiler/src went from 3,329 to 3,224
(docs/unsafe-baseline.md lowered). The tool removed 104 blocks
(unneeded-unsafe) and added 49 boundary blocks with their comments. The
removal is small because most `cx.` blocks also index the raw static
tables (IRFUNCS, FNS, TLISTS). Those go with item f, not with this item.

Cost: the rewrite made `check` of compiler/src 6% more expensive (the
own pass +32%). The cause was kinds::holds_inout walking every field of
an inout FnCtx at every call. Memoizing it per function's walk (commit
8b367409) brought `check` back to 1.01x of the source before the
rewrite, and to 0.95x of 0.26.3 (tests/compile_cost.sh).

## The read-only inout parameters, for 0.27

0.27's references should make the 580 read-only parameters `&T`, not
`&mut T`. To list them again:

1. Check out 4b47dc46 (the tool, before the rewrite).
2. Run `target/volec fix --only rawptr-list`.
3. The lines of class `read` are those parameters, by FILE:LINE,
   function and parameter.

The function names are stable, so the list maps onto the rewritten
tree. 0.27's fix could also derive it directly: an `inout` parameter of
a plain type that its function never writes through and never passes
on to a written parameter. That is the same fixed point as the tool's
F_WRITE (`walk_all(PH_MARK)`), applied to inout parameters instead of
`*T` ones.

## The nested-call class (141), and the hoisting rule

A parameter stays raw when its function is called inside the arguments
of another call that takes the same context: `f(&cx, g(&cx))`, `f(&cx,
&cx.cap)`. Two inout accesses there are own.conflict, and a raw one is
no loan. A first version without this rule left 537 own.conflict errors
(ir_arg 86, ir_val 42, ir_const 37, konst 24, ...).

The rule for later, after the statics work:
- Hoist each inner call that takes the context into a `let` before the
  statement, in argument order: `let t = g(&cx); f(&cx, t)`.
- Do it only where the statement is a plain expression statement, a
  `let` or a `return`. Never inside a `while` condition, an `&&` or `||`
  operand, or a match guard, where hoisting changes what runs.
- Do it only when no argument before the inner call has an effect the
  inner call could observe.
- Then rerun `fix --only rawptr`, which decides those parameters. The
  nested-call rule matches by local, not by raw parameter, so a rerun on
  the hoisted program sees the same calls.

## What worked

- Starting from 0.17's `fix --values` analysis: its fixed point over
  callers and callees, and its "raw when indexed, cast, compared or
  stored". On top of it, a split between a raw callee that uses its
  parameter as an address (escape) and one that keeps it as one object
  (the caller passes `&p`, safe). Before that split, a single captured
  `cx` in `is_hfa` kept about 90 others raw, and 376 more raw because
  their callers' contexts were. With the split, read and write went from
  1,119 to 1,522, before the nested-call rule took 141 back.
- Trial rewrites in the working tree, measured, then reverted with a
  saved patch. A compiler built with MAX_ERRORS raised counted every
  error, not just the first 50.
- `--time-passes=instructions` on a build, and a generated benchmark (a
  context of N fields, 4,000 inout calls). Together they showed in a few
  minutes that the own pass's cost grew with the context's field count.

## What cost time, ranked

1. The own pass's errors come after the type errors and are capped at
   50, so the first dry runs showed 7 errors where there were 537.
2. Shell guards on worktree commands: any loop or `$VAR` in a command
   line is refused. Each measurement became a script file in the
   scratchpad.
3. The check hook of a file outside the tree uses an older tools binary:
   it reports `Allocator is not a trait` and `unknown attribute
   deprecated` for every scratch program, which is noise.
4. `sample` cannot attach to a 0.5 s run, and there is no xctrace, so
   there was no profiler. The generated benchmark took its place.
5. The commit hook flags lines with an existing unsafe that a rewrite
   only touched, as if the unsafe were new. The tool now writes comments
   for the blocks it adds; three touched lines needed hand comments.

## Never used

`refactor signature` (the tool edits the signatures and calls in one
fixed point), `query views`, `--places-diff`.

## Fix list, in order (tagged)

1. [own] `fix` dry runs should report every error class, not stop at
   the first 50 (base/diag.vl MAX_ERRORS). The 537 conflicts were
   invisible until a compiler without the cap was built.
2. [own] An own.conflict `f(&cx, g(&cx))` with g only reading cx could
   be accepted as a two-phase access, as Rust does for receivers. That
   would decide the 141 nested-call parameters without hoisting.
3. [fix] `fix --only rawptr` could make a `let` local `var` when it is
   given `&x` to a new inout parameter: own.readonly's `try: var x`, done
   by hand twice here.
4. [hooks] The check hook of a scratch file should use the tree's
   target/tools/volec, not an older one.
5. [tools] An `inout`-parameter census (`rawptr-list --inout`: read-only
   or written) for 0.27, instead of rerunning the list at 4b47dc46.
