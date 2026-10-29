# Feedback: table254, `volec refactor table` and its first five tables

2026-10-29, release 0.25.4. Built `volec refactor table X` in
compiler/src/tools/refactor_shape/table.vl (1,454 lines, new) with
its help, explain codes, docs and tests/refactor/table254.t (one program
of 8 modules); converted five cold tables with it (HS, CFILES,
CENUMERATORS, CVARS, CFUNCS: 1 to 4 files each); ran its `--dry-run` over
the 243 pointer statics of compiler/src, NODES included.

## Verdict

The query, refs and edit engine carried a whole-program refactoring
without new infrastructure: the edit's check, its imports round and
emit_use_edits did the hard parts, and 29 tables (NODES among them)
convert cleanly. What cost time was the tooling around the tool: a
dry-run that takes minutes on a big table, dry-runs that cannot run in
parallel in one tree, and the same-output proof that needs a hand-written
recheck for the compiler's own path.

## What worked

- `volec query context NAME` and `query show` for reading the refactor
  modules (field.vl as the model, refs.vl, refactor_move/imports.vl):
  `remove_use_names` + `emit_use_edits` removed the count's imports, and
  `ADD_IMPORTS = true` before `apply_edit` added the table's import
  where a file read only the count, with no code of mine.
- `edit patch NAME --old A --new B --in OTHER --old C --new D`: a
  signature change and its caller in one checked edit, after the
  refused single edit printed exactly that (`note edit.together`).
- The check hook's `suggested, not applied` lines (`use
  crate::tools::query::refs::R_DEF;`) and `fix --suggested`.
- `bootstrap/bootstrap.sh --dev --no-suite`: 10 to 20 s with the
  fixpoint, a dozen times.
- `volec same-output OLD -j 4`: 32,844 compilations in 6 minutes, the
  differing ones kept in target/same-output/N/ with old.out, new.out,
  status, easy to recheck by script.
- `tests/refactor/run.sh -u table254`: the transcript written from the
  real output; and the suite's self_explain check, which caught two
  notes I had printed with buf_str instead of diag() (no explain entry
  found for them).

## What cost time, ranked

### 1. A dry-run of a big table took minutes, and parallel dry-runs broke each other

`refactor table FNS --dry-run` ran over 10 minutes: the edit's imports
round runs one child `volec fix --round --only imports --in FILE
--overlay ...` per file and per round (seen in `ps`), each a whole check
(8 s of CPU). NODES (38 files) took 55 s. To survey 241 tables I ran
four dry-runs at once in the worktree: 8 of them failed with errors
that were not theirs (`error[module error] cannot find the file of
module 'emit'`, `unresolved import 'crate::front::cimport::CFUNC_CAP'`),
because each run writes and removes `FILE.vole-edit~` copies next to the
sources. Cost: one survey thrown away (about 15 minutes) and copying
compiler/ four times into scratch to run them apart. What would have
saved it: one imports round over all files at once, and copies with a
per-process suffix (or the edit taking a lock).

### 2. same-output needs a hand recheck for the compiler's own path

Every proof printed `error same-output.differs: 7425 of 32844
compilations differ`, all of them the compiler's own path in `try:`
lines (`try: /…/old-HS/volec edit patch …` against `try: target/volec
edit patch …`). I wrote a script comparing old.out with OLD's path
replaced by the new one (0 differ, five times). What would save it: an
option of same-output that normalizes the two compilers' paths (or runs
both under the same name), so the proof is one line.

### 3. `query items --kind static` was cut silently for a script

My first table list came from `query items --kind static | awk`: 109 of
243 pointer statics, because the output stops at the 8,000-token budget
(`note query.budget: cut at about 8000 tokens: 560 of 2085 lines`, on
stderr, which my pipe dropped). The first survey missed MEMOS, FIXUPS
and the other back-end tables. `--budget 40000` gave all of them. A
`--names` or `--all` for scripts, or the budget note on stdout when it
is piped, would have saved a survey round.

### 4. Internal APIs of refs: accumulating state

`refs_of(targets)` appends to `R_POS`/`R_FLAGS` and its targets to a
static list, so calling it once per definition gave each later call the
earlier ones' references too: my first run of the tool refused MEMOS's
21 uses as "X_CAP read" at positions of MEMOS itself. One call with all
targets and R_DEF to split them was the fix (one build round). A
`refs_clear()` or a doc comment on refs_of would have said it.

### 5. A qualified path is a Path node whose segments have no parent in rewrite's expr_slots

`crate::front::types::ENUMS[i]` and `crate::base::SYMS[...]` were
refused as "the table itself used": the ref's Ident is a segment of a
Path node, and `expr_slots` gives no children for Path. I added the
segments to my parent map. Cost: one survey round. A parent map in
rewrite/parsed.vl (every tool that walks up rebuilds one) would help.

### 6. Justified unneeded blocks stay

After CFILES, `query unsafe --summary` said `unneeded: 1`, and `fix
--only unneeded-unsafe` left it: cfile_path's block had `// UNSAFE:` and
`// SAFETY:` comments (now false, they named CFILE_COUNT). Taken away by
`edit patch`. The fix could take a justified unneeded block with its
comments, or list it with a `try:`.

### 7. The hooks around a shell edit of help.vl

`sed -i '' -e '12s/41/42/' … help.vl && sed -n 12,14p …` printed the old
line and changed nothing, with no block message I could see; `edit
patch` did it. Also: a Python write to my own new file needed `#
no-tool:` (fine), and a `grep -n` of it was blocked as compiler source
over 300 lines, with a good `try:`.

## Never used

- `refactor --script`, `rewrite`: the tool's edits are computed from the
  parsed nodes and the references, not patterns.
- `probe`, `reduce`, `guide debug`: no crash or wrong output to chase;
  same-output found no difference.
- `tests/affected.sh --linux`: the plan did not say platform-relevant.

## Fix list, in order

1. [tool:edit] The imports round of a checked edit: one `fix --round
   --only imports` over all edited files, not one child per file; a
   dry-run of 40 files in seconds, not minutes.
2. [tool:edit] `.vole-edit~` copies per process (a pid suffix) or a lock,
   so two dry-runs in one tree do not report each other's errors.
3. [tool:same-output] An option (or the default) that compares with the
   two compilers' own paths in `try:` lines made equal; print the
   remaining count only.
4. [tool:query] `query items` for scripts: `--all` (no budget), or the
   budget note on stdout when the output is piped.
5. [tool:fix] `--only unneeded-unsafe` takes a justified unneeded block
   too (with its comments), or lists it with an `edit patch` `try:`.
6. [tool:refactor] `refactor table`: also rewrite the comments that name
   X_COUNT (doc_mentions, as rename does), and take the forms the 17
   refused tables need where they are mechanical: `X = grow_x()`
   wrappers (DEFS), a `TOK_COUNT = mark` rollback as `truncate(mark)`
   when mark is a length read before.
7. [tool:rewrite] A parent map of the parsed nodes in
   tools/rewrite/parsed.vl (with a Path's segments), for the tools that
   walk up from a reference.
8. [docs] refs.vl: say that refs_of accumulates (targets and R_POS), or
   give it a reset.
