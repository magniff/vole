# statics264: the compiler's statics into context structs (0.26.4, item f)

## Verdict

In progress: P1 (the pilot) is done. The tool, `volec fix --only
statics --group FILE`, moved the places IR's body and its control-flow
graph (19 statics) into `places::ir::Body`, passed down as `pbody` to 288
functions (105 inout, 183 let) from four owners. Nothing was changed by
hand except the struct and its constructor. P2 (tools' statics) and P3
(front's pass state) follow in 0.26.4; P4 to P6 move to 0.26.5.

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
4. The sandbox refused shell loops, `$VAR` commands and `xargs git`, so
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
4. [tool] The tool adds about 30 statics of its own (tools/fix/statics.vl);
   P2 moves them with the rest of tools'.
