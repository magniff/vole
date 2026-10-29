# Feedback: stdunsafe254, justify or remove every unsafe site in std

2026-10-29, release 0.25.4. Worked on: every `unsafe` block, `unsafe fn`
and extern block in compiler/std (objc and its generated bindings, gpu,
the core module, collections, window, sys and its tails, sync, slice,
fmt, thread, io, hash, iter, str, env, random, string, num), the
soundness bugs found on the way, and std's core size budget. 893 sites
left, 0 unjustified (from 1204 and 1194).

## Verdict

`volec query unsafe std --summary` made the job measurable and
`--unjustified` made it a worklist: every module was "run the query,
fix the list, run it again". The comments' rule found real bugs when
writing a SAFETY line was impossible (a use after free in `RecvIter`,
leaked handles in `SysDir` and `SysSpawnActions`, `strerror`/`ptsname`
races, a released `NSWindow` used after `close`). What cost time was
the distance between the source and what the tools look at: the query
and the check hook read the std embedded in a binary, not the tree;
the sys tails are not audited at all; and the comment rule's notion of
"right above" misses blocks inside tail expressions.

## What worked

- `volec query unsafe std --summary` / `--unjustified`: per class and
  per module counts, the item of each site and the operations inside;
  the before/after numbers in this branch's report come straight from it.
- `tests/unsafe_audit.sh -u`: one command to lower the baseline.
- The checker on generic code once instantiated: `note: in
  instantiation of 'set_len<i64>'` showed a raw write was checked, which
  settled that the 3 "unneeded" blocks are needed.
- `guide --find sealed` found `#[sealed]` (memory, modules#visibility)
  on the first try.
- `volec fix --suggested` for the missing import after a rename.
- The checker caught `let fds` written by `sys_poll` as soon as its
  signature became `inout`, in every caller (process.vl, openhtop,
  voltty, tests/run/sys_pty.vl).
- The commit hook regenerating and checking `stdsrc.vl`: never committed
  a stale embedded std.
- `std.core`'s budget error named the biggest sections and who pulls each
  in ("needed by 100 [Printing] for the name RawLock"): the split of
  Mutex/Once/Condvar into a lazy section came from that line.

## What cost time, ranked

### 1. The tools read the embedded std, not the tree

`volec query unsafe std` after editing a std file printed the old
counts; the check hook (target/tools/volec, a suite-passing build)
reported `unresolved import std::sys_c_strerror_r` for an item that
existed in the tree's tail. About 6 turns over the branch (rebuilding,
then rebuilding again with `bootstrap.sh --dev --no-suite`, then
explaining the hook's false error to myself). Would save: `query unsafe
std` and `check` read compiler/std from the tree when run inside the
compiler's tree (or say "std from the binary, built at X; the tree's
std differs").

### 2. The comment rule misses blocks in tail expressions

A `// UNSAFE:`/`// SAFETY:` pair above `Pool { p: unsafe { .. } }`, above
`if c { 0 } else { unsafe { .. } }` on one line, or above a tuple whose
second element is the second unsafe block of the statement, does not
count. 7 sites rewritten as `let` + tail or early return, about 5 turns
of re-running the query to see which sites still showed. Would save: the
rule covers every unsafe block of the statement or tail expression the
comment is above, or the warning says "this block is inside a tail
expression: comment the expression's first line" with the line.

### 3. The core-sections budget counts comments

The SAFETY comments raised std's core from 151819 to 176809 bytes
(`error std.core: ... more than 163840`). About 8 turns: compressing
comments in core sections, then moving Mutex/Once/Condvar to a lazy
section (compiler/std/index.awk LAZY). Would save: the budget measures
the sections without comments (it is a compile-time budget; comments
are lexed and dropped), or the error says how many of the bytes are
comments.

### 4. The sys tails are not audited and `edit patch` cannot reach them

compiler/std/sys/macos.vl and sys/linux.vl are not in `query unsafe
std`'s list at all, and `volec edit patch` there said `query.no-match:
no file ... in the program`. Edited them with Python under `# no-tool:`;
about 4 turns. Would save: the tails as files of the std program for
query and edit (the host's tail at least).

### 5. Uninstantiated generic code: no unsafe check, "unneeded" blocks

A generic fn never instantiated is not unsafe-checked (`fn peek<T>(p:
*T, i: i64) -> T { p[i] }` passes `check`), so `query unsafe` calls its
blocks "none (unneeded)": RawTable::probe_stats, RawTable::check,
BTreeRaw::node_alloc. Removing them is accepted by `check`, a trap.
About 3 turns to prove they are needed (probe with an instantiation).
Recorded with tools/agent-feedback. Would save: the unsafe check on
generic bodies before instantiation (a raw deref of `*T` is unsafe for
every T), or "unneeded" left out for generic items.

### 6. The hook on grep and Python over compiler/std

`grep -rn ... compiler/std/objc/tables/*.objc` (not vole source) and a
Python bulk insertion of comments were blocked; each needed a rerun
with `# no-query:`/`# no-tool:`. About 10 reruns over the branch; the
bulk edits (hundreds of comment insertions per module) had no tool:
`edit patch --pairs` refuses overlapping OLDs (`patch.overlap: OLD 2
(line 24) overlaps an OLD before it`) and one mismatched OLD fails the
whole batch. Would save: the hook passes non-.vl files under
compiler/std; `edit insert-above FILE:LINE TEXT...` for many lines in
one checked edit.

### 7. A zeroed static array is data in every object

`static var STDIN_BUF: [u8; 65536] = [0; 65536]` (to drop a malloc) is
emitted as `.space 65536` in `__DATA,__data` of every program, hello
world included (its object 9840 -> 75384 bytes), and made compile-cost's
hello row 1.46x (116.9 M instructions against 80.3 M). Found by the
orchestrator from the gate line, then `--time-passes` ("data and output"
0.2 -> 0.9 ms, check 0.7 -> 1.3 ms) and `-S`; the buffer is a checked
malloc again. About 4 turns. Would save: zero-initialized statics in
`__bss`/zerofill, statics no program reaches left out, and compile-cost
printed by `tests/affected.sh` when std changes.

### 8. Smaller

- `query context` "used by" repeated one line about 50 times (recorded).
- `tests/query/run.sh -u` rewrote std line numbers wholesale (a 354-line
  diff for two real changes), though the comparison normalizes them.
- zsh: `grep --include=*.vl` needs quoting (my mistake, 1 turn).
- The optimizer keeps a bounds check after an explicit `(i as u64) <
  len` test, so `[T]::get`'s safe form is 1.9x slower and stays unsafe.

## Never used

`refactor` (no renames needed), `query impact`, `probe`, `reduce`,
`volec undo`, `batch`, `tests/affected.sh --list` beyond its plan line.

## Fix list, in order

1. [tool:query unsafe] read compiler/std from the tree inside the
   compiler's tree (or say the binary's std differs from the tree's).
2. [hook] the check hook's std: the tree's, so new std items do not
   give false `unresolved import` until a suite-passing build.
3. [diag] `unsafe.unjustified`: a comment above a statement or tail
   expression covers every unsafe block in it (struct literal fields,
   if/else branches, tuples).
4. [lang] unsafe-check generic bodies before instantiation; until then,
   [tool:query unsafe] no "unneeded" for generic items.
5. [build] std.core's budget without comments (or report the comment
   share in the error).
6. [tool:query unsafe] audit compiler/std/sys/macos.vl and linux.vl;
   [tool:edit patch] reach them.
7. [tool:edit] insert comment lines above many FILE:LINEs in one checked
   edit; `--pairs` that tolerates adjacent OLDs.
8. [hook] do not block grep/sed over non-.vl files under compiler/std.
9. [lang] private fields (or #[sealed] by default for types with raw
   pointer fields): Window.ns, std::objc Ref/Id `pub ptr`,
   RawSurface::MetalLayer, HashMapIter, Atomic/RawLock/Once are
   forgeable in safe code.
10. [lang] Atomic<T> limited to integer, bool and pointer T: Atomic of a
    struct crashes at -O2, Atomic<f64>::fetch_add adds the bits.
11. [lang] statics are safe to mutate while threads exist: data races in
    safe code (FMT_OUT, Linux sys_args, STDIN statics).
12. [lang] `__fmt_in_end` and `std::test_args` are safe pub fns over raw
    pointers (compiler-generated callers): make them unsafe with the
    compiler's calls in unsafe blocks.
13. [tool:query context] collapse repeated "used by" lines.
14. [test] tests/query/run.sh -u: keep std line numbers normalized in the
    expected files.
15. [build] the optimizer: drop a bounds check dominated by an explicit
    `< len` test.
16. [build] zero-initialized statics as zerofill (bss), and statics no
    program reaches not emitted: a `[u8; 65536]` static cost every
    program 64 KiB of object and 46% of a hello world's build.
17. [test] tests/affected.sh runs the compile-cost row when compiler/std
    changes (std reaches every program).
