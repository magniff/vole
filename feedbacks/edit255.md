# Feedback: edit255, dependent edits in one checked call and the edit tools' gaps

2026-10-29, release 0.25.5. Worked on compiler/src/tools/patch/mod.vl,
tools/edit/{apply,breaks,cli,mod,stdedit}.vl, tools/textual/{mod,rewrite}.vl,
tools/sameout.vl, tools/query/{mod,unsafe_audit}.vl, base/diag.vl,
tools/explain/tools_table.vl, tools/help.vl; a new transcript
(tests/refactor/edit255.t), a std case in stdedit.t, a same-output check in
tests/refactor/run.sh, 15 transcripts' `edit.breaks` lines; about 600 lines.

## Verdict

Most of item 1 already existed (`--in NAME` takes a const, `@@ NAME`
blocks); what was missing was small: the `--pairs` + `--old` refusal, std
files and inline modules as `@@` targets, insertion above a line, and
overlap messages. The real finds were elsewhere: the imports round hid
the edit's own error behind an import it invented (`use std::size`), and
parallel edits in one tree really did take ten minutes and report each
other's errors.

## What worked

- `volec edit patch TOOLS_TABLE --pairs explain.pairs --in TOOLS_COUNT --old '108' --new '109'`:
  the new mixed form, dogfooded on the explain table and its count: one
  checked call.
- `edit patch --pairs FILE` with `@@ NAME` blocks for several hunks in
  several items at once (sameout, unsafe_audit, rewrite.vl: each one call,
  the imports round adding every `use` the new code needed:
  `note edit.imports`).
- `edit replace NAME < file.vl` with two items in the file (imports_round
  became imports_round + imports_child in one call).
- The check hook's `suggested, not applied` lines, then `volec fix
  --suggested` for the missing imports (`FORCE`, `BUFS`).
- `volec query unsafe compiler/src/FILE` against the base tree's counts
  found the 7 unjustified blocks I had added; all made safe or justified
  (4365, the baseline, again).
- `tests/refactor/run.sh -u NAMES` rewrote the 15 transcripts whose
  `edit.breaks` line changed.

## What cost time, ranked

### 1. Two shell loops waiting on `pgrep -f` matched themselves (about 15 minutes)

`while pgrep -f "after/volec refactor" ...` matched the shell running the
loop, and never ended; the 300 s timeout moved it to the background and I
stopped it. A script with `wait` worked (`par.sh`). My mistake, but the
parallel-runs check is a natural thing to want: a `tests/refactor` case
that runs two dry runs at once would have saved writing it.

### 2. The old binary's parallel dry runs ran over ten minutes (about 10 minutes)

To show the collision before the fix, three FNS and three TYPES dry runs
at once with the 0.25.4 binary were still running after ten minutes (each
child `fix --round --only imports --in FILE` at 6 to 11 s of CPU, one per
file and round) and printed other runs' errors (`unresolved import
'crate::front::types::FN_COUNT'`, 34 copies left behind). I killed them.
The new binary: the same six runs in 4.1 s, each output the sequential one.

### 3. `-u` rewrote std's line numbers in json.t

`tests/refactor/run.sh -u json` wrote `<std>:5096:20` for `<std>:4788:20`
(the comparison normalizes them, the update does not), as stdunsafe254 #14
says. I put the old numbers back by hand with sed.

### 4. The hook blocked reads and a Python splice of my own new code (5 calls)

`grep -n` over compiler/src files and a Python replacement of three
adjacent functions I had just written were blocked; `# no-tool:` with a
reason ran them. `edit apply` with a block per item would have worked for
the three functions, but not for adding a fourth between them.

### 5. `help: add use std::size;` for an undefined `size`

The checker suggests `use std::size;` (only `std::window::script::size`
exists), and the imports fix applied it, so a refused edit reported
`unresolved import 'std::size'` instead of `undefined variable 'size'`
(that is what opt254 #3 saw). The edit engine now takes such a round back;
the suggestion itself is still wrong (recorded with tools/agent-feedback).

## Never used

`probe`, `reduce`, `refactor rename/signature`, `query impact`: the work
was in the tools' own plumbing, read with `query show`/`items` and the
Read tool.

## Fix list, in order

1. [diag] The missing-use help names a path that resolves (`use
   std::window::script::size`, or nothing), not `std::size`.
2. [test] tests/refactor/run.sh -u keeps std's numbers normalized
   (stdunsafe254 #14, seen again on json.t).
3. [tool:edit] `edit replace FILE:A-B < text` (a range of lines, checked),
   for several adjacent items rewritten at once.
4. [tool:rewrite] In a script step, `rewrite --text` prints the program's
   paths without `./` (`./shapes.vl	6 matches`).
5. [test] A transcript case with two edits running at once in one tree
   (the copies' tag), not only the hand check of this branch.
