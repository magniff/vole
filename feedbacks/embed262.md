# Feedback: embed262, shader parts, `.wgsl` files, shared structs, check-time GPU lints

2026-10-30, release 0.26.2; steps 1-5, 8 and 9 done; the optional steps 6 (the host-side three)
and 7 (`refs` over WGSL names) left.

## Verdict

The design held: `with` parts as text concatenation with a piece table for positions, a `.wgsl`
file as a FILES entry of its own kind, `#[repr(wgsl)]` as one layout rule in `compute_layout`, and
the lint as one pass over each function's checked tree. Cost: `tests/compile_cost.sh -r 5`, check
1.00x against 0.25.5 and 1.00x against the base (5567.7M/5566.2M, 5566.7M/5565.7M). compiler/src's
own growth (the base's source and the branch's, checked by the same compiler, uncached, best of 3):
5528.9M to 5604.2M, +1.4%. The fluid2d-shaped probe (12 blocks): about 39M head and 38M base, best
of 5 uncached, under the 69.5M of 0.26.0; single runs ranged 35M to 91M under the machine's load.

## What worked

- `volec query context` / `query show` and `edit patch`/`replace`/`insert`/`delete` on every
  compiler/src change; `bootstrap.sh --dev --no-suite` in about 9 s, so a debug print was cheap.
- `tests/run.sh FILTER` with directory cases for multi-file errors (`err_embed_with_apart/`,
  `embed_wgsl_parts_file/`) and the `--deny-warnings` default, which made "the six must say
  nothing" one case.
- lldb `-k "thread backtrace"` found the lint's unbounded recursion in one run.
- `explain` entries as data (gpu_table.vl): five check-time forms added without code.

## What cost time, ranked

1. The lint reads the checked tree, whose synthetic shapes are documented nowhere: a contract's
   `$pre` calls, blocks of `?aN` temporaries around a call with a contract, the own pass's
   `__own_tv`, and a use of each `let` the compiler adds at the binding's own position (its drop).
   Each was found by printing nodes. A nested contract's temporary reads one of its own name, which
   recursed without end; only `example_build` (voxel) showed it.
2. The FILES audit for a second kind of file: 46 loops and every `lex_range` caller, read one by one.
3. Test directives: each WARNING line matches a different warning (two lines for one warning fail);
   positions move when the header grows; the runner prints absolute paths, so expectations are
   written as `FILE: line L, column C`.
4. `git stash` is shared by all worktrees: a failed `stash push` (an untracked file) and the `pop`
   after it applied another branch's old stash (lsp25) here, with conflicts in three files.
5. `edit patch` with several pairs, one not matching: it prints only a `try: ... --pairs` line, not
   which pair missed.

## Never used

`refactor` (rename, move, signature), `probe`, `reduce`, `rewrite`, `batch`, `undo`.

## Fix list, in order (tagged)

1. [compiler] A documented helper for the checked tree's synthetic nodes (is it a temporary, a
   contract's check, the compiler's drop use), for passes like gpu_lint.vl that read it.
2. [std] A safe bytes view of a `#[repr(wgsl)]` struct without padding (a compiler-known bound);
   until then fluid2d's `set_params` and tests/gpu/cases/embed_wgsl_repr.vl use a justified
   `unsafe` slice.
3. [compiler] Shared `const`s evaluated, not only literals (WGSL is written before consts are
   evaluated); `with` paths through `use` (now from the block's module only).
4. [tool] `edit patch --pairs`: name the pair whose old text is not found.
5. [docs] AGENTS.md: never `git stash` in a worktree (the list is shared).
6. [tests] Directive matching on paths relative to the case.
7. [left] Step 6 (`path.module`, `conv.mode_order` confirmed, `volec test --show-output`) and step 7
   (`refs` over WGSL names).

## The affected plan

`tests/affected.sh`: plan: 2480 of 2885 cases (19 of 27 suites). 11 failures at -O0, -O2 clean:
gpu_lint_silent and warn_gpu_unwritten (no `// LINK:` directive; fixed in 2bab9685, pass alone at
-O0 and -O2); the other nine fail the same on release-0.26.2's tip built alone (9079b37b):
budget (off, cache: `try: query def std::gpu::wgsl::dump` twice), stdpos0253 (off, cache: std.vl's
lines moved by numbers262), self_explain (`cell.view_item` not a code), guide-std-index (22441
bytes, 22000 at most), book 13-contracts-testing:173 and 20-appendix-diagnostics:122, 138 (cells'
new wording and codes).
