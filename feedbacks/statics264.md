# statics264: the compiler's statics into context structs (0.26.4, item f)

## Verdict

0.26.4's part is done: P1, P2 and P3. 2,151 statics are down to
1,234, and checking compiler/src costs 6.1% more with one compiler
(0.89x 0.26.3's with each its own). P3 moved 244 of front's statics into
six pass contexts. Its groups came from following the dry run's `via`s
(fix list 12), and its by-hand work was named arguments, owned
contexts and `pub` records (10, 11). Earlier: The tool, `volec fix --only statics
--group FILE`, moved the places IR's body and its control-flow graph
(19 statics) into `places::ir::Body`, passed down as `pbody` to 288
functions (105 inout, 183 let) from four owners. Nothing was changed by
hand except the struct. P2 moved 673 of the tools' 760 statics into
`tools::ctx::Tcx`, passed as `tcx` to 1,228 functions (765 inout) from
`main` and `cli::run::run`. By hand: the struct, one format hole, seven
calls passing a field inout beside `tcx`, and two statics the group
missed. The tool's own 32 statics are among those moved. P4 to P6 move
to 0.26.5.

## What worked

- Scratch programs on 0.26.3 before any design: they showed that a
  context passed **last** lets a call nested in another's arguments take
  it too (`two(add(1, &ctx), 2, &ctx)` checks; with the context first it
  is own.conflict). That decided the tool's one convention and removed
  the nested-call class rawptr264 had to leave raw.
- A dry run (`--only statics-list`) with no owners first: the functions
  it refuses (the ones reaching `main`) show where the owners must be,
  and the closure's size before any edit.
- `query refs` over every static (2,134 of them, one batch) for the
  census: uses, writers, the subsystems using each, which task code
  touches.
- The list's `writes at LINE WHAT`: it showed in one run why 276 of 288
  functions came out inout (the checker's implicit `&` on a receiver,
  std's `self` typed as a mutable reference whatever the method does).

## What cost time, ranked

1. Deciding whether a method call writes its receiver. Neither the
   parameter's convention nor its checked type says it for std's methods
   (`Vec::len`'s `self` has the same type as `Vec::push`'s). The tool now
   asks the program's own methods by their checked type, and std's by a
   list of names that only read.
2. The checked call is not the call as written: defaults filled in,
   named arguments in the parameters' order, format literals lowered
   into an Interp's `y`. The arguments to edit are therefore found in the
   source text (the segments between the call's parentheses), and the
   walk follows Interp's and Try's checked forms.
3. Edits inside a statement that is then rewritten whole (an argument
   moved into a `let`): the edit list refuses overlaps. The edits are
   recorded first, the statement is rendered with them, then everything
   is written.
4. P2's view-typed statics (seven `[u8]` slices, such as fmt's text and
   the completion text). As fields, they make `tcx` a holder of views,
   and the own pass then ties `tcx` to the locals of every caller that
   lends it anything (`own.escape` in `edit patch`'s option loop). They
   were taken out of the group and stay statics. The first run had to be
   undone.
5. P3's groups. A pass's statics are mostly reached from outside it:
   the checker calls the own pass's fast path, places and gen0 read its
   summaries, and `query own` walks one function. Strictly per module,
   the checker's, the effects', the patterns' and the modules' statics
   all drop out. What stayed is state that a pass makes and drops
   itself. The own pass needed a split by lifetime, done by hand from
   the module names.
6. `volec check` stops at 50 errors, so `fix --only imports` after the
   rewrite needed seven rounds, one per 50 missing `use` lines.
7. Deleting 671 statics with `edit delete`, one process each, took about
   15 minutes.
8. The sandbox refused shell loops, `$VAR` commands and `xargs git`, so
   each multi-step run went into a script file.

## Never used

`refactor signature` (it adds one parameter to one function; the
closure is the tool's), `probe`, `reduce`.

## Fix list, in order (tagged)

1. [tool] `fix --only statics` should add the `use` lines for its
   parameter's type itself (today `fix --only imports` follows it), and
   delete the moved statics' declarations (today `edit delete`, one at a
   time).
2. [tool] `edit delete` takes one NAME; several would help.
3. [lang] std's `self` receivers: their checked type says inout for a
   method that only reads (`len`, `get`), so a tool or the own pass
   cannot tell a read from a write by the signature.
4. [tool] Done in P2: the tool's own 32 statics are now `tcx` fields.
5. [tool] Refuse a view-typed static (a slice, a `str`) in a group, and
   say why: as a field, it makes the context a holder of views.
   [lang, 0.27] The class itself: a static slice that views memory
   nothing names (an arena's copy, a raw buffer), which no context can
   hold today because the own pass then ties the context to its callers'
   locals. 0.27's references give it a lifetime the context can name.
   P2 left seven: tools::fmt::pieces::FT and BAD_MESSAGE,
   tools::lsp::complete::TX and PREFIX, tools::reduce::program::WANT,
   tools::textual::places::LINES_TEXT, and
   tools::refactor_shape::table::X_TEXT.
6. [tool] A static named in a format literal's hole (`"{DOC_SEQ}"`)
   becomes `{tcx.doc_seq}`, which is `format.expr-hole`. Write `{}` and
   pass the argument instead.
7. [tool] A static passed inout to a function that also takes the
   context (`get_ints(&ALIASES, &tcx)`) conflicts. Take the field into a
   local and put it back when the callee does not touch it through the
   context; refuse otherwise.
8. [tool] Adding statics to a context that is already passed down:
   today a function with a parameter of that name is refused (F_CLASH),
   so the two statics the group missed were moved by hand.
9. [tool] `fix --only imports` is bounded by check's 50 errors. It could
   collect every missing `use` in one run.
10. [tool] A call with named arguments (`ctok_new(.., bol: false)`) got
    the context before them, positionally, where it fills the named
    parameter's slot. When the context is the last parameter, it should
    go after them, named (`ccx: &ccx`). P3 moved 25 by hand.
11. [tool] A plain context (no owned field) is copied into each let
    parameter (a memcpy per call: 1.5 KB for OwnCx). The tool should
    say so. P3 gave each plain context an empty Drop, which makes it
    owned and therefore lent. [lang] A way to say "lend, don't copy"
    for a plain struct, without a Drop that does nothing.
12. [tool] Finding a pass's group is a loop: dry-run the list, follow
    each member outside the pass down its `via`s to the field it uses,
    drop that field, and repeat (up to 80 rounds of about 3 s; one field
    per round at the end). A `--only statics-list --prune PREFIX` that
    did the loop itself would save that.
13. [tool] A group with two owners (`check_program` and `own_state_at`)
    is only right when neither needs what the other's run left. The
    tool cannot tell, so P3 kept the own pass's walk state (reset by each
    walk) and left the rest.
