# Feedback: privfields260, struct fields private to their module unless `pub`

2026-10-30, release 0.26.0. Seven commits: the `pub` migration in four
trees (std::gpu::wgsl 165, the rest of std 47, compiler/src 286,
examples 63, tests 6), then the rule (front/check/sealed.vl), the codes
field.private and field.literal-private, `#[sealed]` retired
(attr.obsolete, `fix --only obsolete-attr`), Gpa's `_private: ()`, the
tools and the docs.

## Verdict

The brief's plan held: the checker was 0.16's sealed check made the
default, and `fix --only pub` driven by a local env switch wrote every
`pub`. The probe's numbers came back within a few percent. The time
went to what the probe could not see: std's statics made by literal
across std modules (Atomic, RawLock, Once, in fmt, arch, thread and
alloc_check.vl), the compiler's own f-string literal, and transcripts
whose text named `#[sealed]`.

## What worked

- `VOLE_PRIVATE_FIELDS=1 target/volec fix --only pub ROOT`: compiler/src
  in 1 s (286 pubs, 21 files, formatted); with `--std-tree compiler/std
  --in std::gpu::wgsl` it wrote std's files directly (164 pubs).
- `fix --only obsolete-attr --std-tree compiler/std` on one program
  naming std's modules deleted std's 29 `#[sealed]` lines.
- `bootstrap.sh --dev --no-suite` in 7 to 15 s, and `git stash -u`
  around it to check each migration commit alone.
- The commit hook's unsafe check: it refused 8 new unjustified sites;
  moving the raw-table reads into five commented accessors left none.
- Constant constructors in statics (`AtomicI64::new(0)`,
  `RawLock::new()`) work: no literal of a private field is needed.

## What cost time, ranked

1. A probe over every tests/run case with `--std-tree` took about 25
   minutes (each check loads all of std); without it, 3 minutes.
2. `target/tools/volec` (0.25.5) checks with the tree's std, so after
   Gpa's private field the check hook reports `missing field '_private'`
   at compiler/src/main.vl on every edit, until tools are rebuilt.
3. `edit patch` on std files that depend on each other (Gpa's field and
   its literals in three files) fails per file; `--no-check` was needed.
   alloc_check.vl is outside query's std, so it was edited with the Edit
   tool.
4. The test runner prints errors in the long form (`error[X]: msg`,
   ` --> file: line L`), `check` in the short one; ERROR lines had to be
   rewritten once.
5. `fix --only obsolete-attr --dry-run` on a program with errors reports
   `edit.breaks: 1 new error`: an old error whose help names a position
   in the edited file reads as new.

## Never used

`refactor move` (sealed.vl keeps its name), `query impact`, `batch`.

## Fix list, in order

- [tool:edit] An error whose text holds a FILE:L:C of the edited file
  should not count as new after an edit that moves that line (verify
  maps positions in messages).
- [tool:query grep] A std-wide search: `--in` takes one file
  (agent-feedback filed).
- [tool:edit] `edit patch` on compiler/std/alloc_check.vl and the other
  std parts query does not load.
- [test] The runner's ERROR lines could accept the short form too.
- [hook] The check hook could use target/volec when the tree's std no
  longer checks under target/tools/volec.
- [lang] 0.26.2: `pub(crate)` to narrow std::gpu::wgsl's 165 and
  compiler/src's 286 `pub`s; 0.27: struct patterns, then
  field.pattern-private.
- [diag] A literal of a generic std struct names `T::new` only; an
  instance's own associated functions are not listed.
