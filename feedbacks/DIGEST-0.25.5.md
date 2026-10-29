# Feedback digest after 0.25.5

Sources: the five agents' files: feedbacks/{tables255, edit255, loop255, codegen255, std255}.md. Items are grouped by theme and ranked by what they cost. A tag gives each item's area.

## The picture

The tools carried the code changes. Two runs show it:
- `refactor table` plus `same-output` converted a table in 10 to 50 seconds of tool time;
- `edit patch --pairs` made a dozen related edits as one call.

The time went to three places, none of them in the compiler's loop:
1. **Measuring.** A 1.03x limit sits inside 1% to 3% noise under load. Finding the 10x linker slowdown took `otool`, `dyld_info` and `sample` by hand.
2. **Checks that had silently stopped checking:**
   - threads_writes.sh, since `static mut` became `static var`;
   - the hooks' std, missing the tree's system file;
   - the SDK field that no test compared with `ld`'s.
3. **Language seams, found by doing real work** (all for 0.26):
   - an index evaluated after its base;
   - no way to seal a trait;
   - no generic impl over `*T`;
   - effects hidden by a list of std function names.

## 1. For 0.26 (language; the core rethink)

1. [lang] `v[f()]` takes `v`'s view before it evaluates `f()`, so `v[grow(&v)]` is a use after free in safe code (tables255 #1; semantics-inventory seam 32). VC0's places with local-only indexes close it.
2. [lang] A sealed trait and generic impls over `*T` (std255 #2). `AtomicValue` is a checker intrinsic, and sealing is done with a private type in a signature (seam 33). VC0 makes `atomic τ` a core type.
3. [lang] Effects that a std function hides (the print lock) belong in an attribute on the function, not a list of names in front/effects/infer.vl (std255 #12).
4. [lang] CHECK_ALLOC_SITE is a plain static written under threads (std255 #8): it should be thread-local or a per-call argument.

## 2. Measuring and the build

1. [build] Lower a Vec's `v[i]` without the `as_slice` call, and share a function's bounds-failure blocks. The -O2 self-compile went from 46G to 61.5G instructions with six tables (tables255 #2). **The biggest cost this release accepted; do it first.**
2. [build] Fold `x - 0` and `x + 0` across signedness of one width, so the range pass drops a Vec index's check after `0 <= i && i < v.len()` (codegen255 #5, tables255 #6).
3. [test] compile-cost: a count stable under load (the fewest of several runs, or user-mode instructions only), with the noise printed beside the ratio (tables255 #3).
4. [test] tests/link: build one program with the internal linker and with `ld`, and diff the load commands and fixup page counts (codegen255 #1). That would have caught the SDK field.
5. [test] Every grep-based check fails when the set it checks is empty (codegen255 #2).
6. [build] link_macho's LIBSYSTEM_COUNT from the array's length (std255 #4).

## 3. Tools

1. [diag] The missing-use help names a path that resolves (`use std::window::script::size`, or nothing), not `std::size` (edit255 #1). It caused a hidden edit error.
2. [tool:query] `--in crate` / `--no-std` for `views`, `def`, `items` and `callees` (loop255 #2, #6), so transcripts about a program don't list std's content.
3. [tool:check] Print `check.std-files` (which std a check read) on stderr and in `--json` (loop255 #1). `check` should also instantiate std's generic bodies as the build does (std255 #3).
4. [tool:help] Show a build's options: `volec --help options`, or `volec FILE.vl --help` (codegen255 #4).
5. [tool:query] `query refs NAME --lines` (tables255 #5); `query grep` over compiler/std, reaching alloc_check.vl and sys/*.vl (std255 #5).
6. [tool:edit] `edit replace FILE:A-B < text` (edit255 #3).
7. [tool:same-output] `--allow KIND` for intended differences (a section's name, a static not emitted), counted apart (codegen255 #8).
8. [tool:refactor] `refactor table` for a table that views a buffer (SRC), and the comments naming X_COUNT (tables255 #4).
9. [diag] An impl of a sealed std trait says "implemented by std only" instead of "'Sealed' is private" (std255 #7).

## 4. Hooks, the harness and docs

1. [docs] **The scratchpad is shared:** each agent works in `$SCRATCH/<branch>/`. Two agents' `t1` collided, and one deleted the other's (loop255 #4, std255 #1). Put this in the common brief.
2. [hook] check-after-edit names the unjustified unsafe sites in the items an edit touched (codegen255 #3).
3. [hook] query-first: Python writes to compiler/src are blocked the same way whatever the path's spelling, and a block says first that the Read tool reads any file (codegen255 #9, loop255 #7).
4. [test] `tests/stdpos/run.sh --real` in the gate's stdpos row (loop255 #5); tests/refactor's `-u` keeps std's numbers normalized (edit255 #2).
5. [docs] grammar.md says `static [ "mut" ]` (codegen255 #7); it goes with 0.26's replacement of grammar.md.

## Proposed placement

- **0.26:** §1, inside the core work.
- **The first release after 0.26's decisions:**
  - §2.1 and §2.2, the indexing cost, measured against 46G;
  - §2.3 and §2.4, which make measuring trustworthy.
- **Any release:** the rest of §2, §3 and §4. §4.1 goes into the next common brief at once.
