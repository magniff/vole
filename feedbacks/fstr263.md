# fstr263: f-strings out of the tree and the language (0.26.3)

## Verdict

Done as the brief planned, apart from slot 3 (`pub(crate)` in
compiler/src), which was skipped by decision. compiler/src's 444
f-strings went in slot 1, by `fix --only fstring --keep-braces`, with
none refused and the output the same. After that came std's comments,
tools/ (with the vole the generators write), bench/, examples/, tests/,
tests/agent-eval, the Book, docs/' examples and two of the guide's
examples. `f"..."` is now error syntax.fstring, once per file, with the
fix as its `try:` line. The fix still reads the removed form, and its
cases pass. The guide's prose about f-strings waits for capab263's turn
over the guide.

## What worked

- `fix --only fstring --keep-braces` over every program tree: nothing
  refused, and the output stayed the same (numtables byte for byte, the
  Book's 311 units, the walkthroughs).
- The Book went through the same fix: each block was wrapped as
  tests/book/run.sh wraps it, then fixed and written back. Only the
  text quoted around a block had to be written by hand.
- The error copies syntax.defer's shape: the parser still reads the
  form, and the error is soft, so the rest of the file is checked and
  the fix needs no second parser.
- tests/refactor/run.sh -u re-records a transcript, and its diff is
  short enough to review hunk by hunk.

## What cost time, ranked

1. Transcripts quote program lines, so each f-string there appears two
   or three times (the source, a diff, a refs line). A text rewrite with
   the fix's rules, followed by -u, was the only way through.
2. The cases that build their program before the fix
   (fstring0262, fstringkeep0262) cannot do it once the syntax is gone.
   0.26.2's output now lives in their comments.
3. The first version of the error remembered the last file it reported
   in a static. A second read of the same text (the LSP) would have lost
   the error. The token table gives the same answer with no state.
4. In zsh, `tests/run.sh $names` passes one argument. `-f FILE` is the
   way to give a list.

## Never used

`refactor` commands, `rewrite`, `probe`.

## Fix list, in order

1. (runner) `tests/run.sh -f FILE` combined with name filters ran only
   the file's cases. Say so, or take both.
2. (fix) `fix --only fstring` could build and run the program before and
   after when asked (`--same-output`), so a case need not build the
   removed form itself.
3. (guide) After capab263's turn: the guide's prose on f-strings
   (syntax, formatting, contracts, example, core, topics), and the
   errors entry on nested f-strings, which becomes syntax.fstring's.
