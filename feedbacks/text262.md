# Feedback: text262, `where`, `impl Trait`, visibility and format literals

2026-10-30, release 0.26.2. Steps 1 to 5 of brief-text262 and the docs of
step 6: `where` and argument-position `impl Trait`; `pub(crate)`,
`pub(super)`, `pub(self)`, `pub(in path)` with item.private and
vis.path; format literals (Rust's std::fmt at std's format positions,
rustc's output byte for byte), with the tools seeing their holes; `fix
--only fstring`, with the guide migrated. `{:#?}` is format.spec "not in
this release".

## Verdict

The compiler's tools carried the language work: `query context` before
each unfamiliar item, `edit patch`/`edit insert` with the check after
each, and `bootstrap.sh --dev --no-suite` at 20 to 60 s. Two things cost
more than the code: splitting one working tree into a commit per step
(the steps touch the same files), and std's core budget, which a format
spec in every program's Fmt path breaks by itself.

## What worked

- Comparing with rustc 1.98.0 directly: the spec case's lines are
  rustc's output, and three of my guesses (`{:#X}` is `0x2A`, `^` puts
  the odd pad byte on the right, `-0` is `+0` for an integer) were wrong
  before rustc said so.
- tests/refactor, tests/query and tests/lsp transcripts recorded with
  `-u`: a new transcript is one file and one run.
- Making the format literal the f-string's Interp node, its names Ident
  nodes at their own positions: rename, refs of an item, the effects,
  the own pass and both IRs saw them unchanged; only `query refs` of a
  local and item rename needed a "name inside a string token" check.
- `fix --only fstring` over scratch copies: compiler/src 430 rewritten
  (the brief's 417 and this stream's own), std 382 (368 rooted at std.vl,
  14 in the flat test and fuzz sections, which only a program naming
  them reads), examples 516, every copy checking as before.

## What cost time, ranked

1. One commit per step from one working tree: steps 2 and 3 share
   lookup.vl, the explain tables, stdsrc.vl and the docs; the split was a
   backup, a hand-made step-2 tree, a build and its tests, then a
   restore. An agent doing several steps should commit each before
   starting the next.
2. std's core budget (tests/std/core_sections.sh): 587 bytes of room
   on the base; Rust's specs in fmt_pad, fmt_radix and the sign took
   1.4 KB after trimming comments, so the bound went up to 164 KiB (its
   own commit), and format_args/__panic_fmt went to a lazy section.
3. The hook's `target/tools/volec` was older than the base (no
   `format_args`, usize impl errors): every edit's check showed 8 to 50
   bogus errors, and each had to be checked against `target/volec check`.
4. `fix` writes a file reached through a symlink as a plain file
   (examples/voltty/app/pty.vl -> ../core/pty.vl became a copy): the
   tree trial had to skip symlinked paths.
5. Rule 4 of the migration (double a plain literal's braces) cannot
   tell a 0.26.1 literal from a migrated one, so a second run (or two
   programs sharing a file) doubles braces again. The trial runs each
   file once (`--in` its program's files not yet fixed).
6. Positions inside a string token: `token_at(p)` is the first token at
   or after p, so a hole inside a literal is the token before it.
7. The disk filled up halfway through (other worktrees).

## The chain

0.25.5, stage 1, cannot build a format literal: `println("{} {x}", x)` is
type error "'println<[u8]>' expects 1 arguments, got 2", and
`println("plain {x}")` prints `{x}` with a warning. compiler/src keeps its
f-strings until the release after 0.26.2 builds it.

## Never used

`refactor extract-function`, `inline`, `split`; `probe` and `reduce`
(no bug needed them); `batch`.

## Fix list, in order

1. [tool] done (tools/proc's rename_file): `fix` and `edit` write through a
   symlink, not over it; tests/refactor/symlink0262.
2. [tool] `fix --only fstring` rule 4: record which literals 0.26.1
   would have printed as they are (e.g. only in files that still hold an
   f-string, or behind `--plain-braces`), so that a second run is a no-op.
3. [compiler] done: macro_error's help for `println!(..)` is the call
   without its `!` (`println("{}", 1)`), `format!` `format_in(.., gpa)`,
   `write!(f, ..)` `f.write(..)`.
4. [lsp] done: hover on a name in a literal's hole answers the name's
   range (tests/lsp/fmtlit).
5. [compiler] an `unsafe { .. }` inside an f-string hole is not an unsafe
   site for unsafe.unjustified (examples/allocators/check-alloc: 3 more
   once migrated).
6. [std] `{:#?}`: Fmt's alternate flag and an indenting writer, derive
   (Debug) following it.
7. [tool] `query stats --all` is the only way to list a program's files;
   a `query files ROOT` would do it directly.
