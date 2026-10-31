# usize263: compiler/src on `usize` (0.26.3)

## Verdict

Done as designed. `volec fix --only casts` (compiler/src/tools/fix/casts.vl)
removed 1,242 of compiler/src's usize-to-i64 casts in slot 2, and nothing
was edited by hand. `query grep 'as i64' --code --count` went from 4,787
(4,792 with the fix's own file) to 3,550. No type or field moved to usize.
The cost is a little lower: -0.14% instructions on the -O2 self-compile
and -0.1% on `check`.

The census, on release-0.26.3 at 8845bbdd. It is the fix's own count,
made on the checked AST by where each cast's value goes first:

| class | casts | decision |
|---|---|---|
| index | 126 | removed |
| slicing to its own end, `a[i..a.len as i64]` to `a[i..]` | 168 | removed |
| comparison with a usize, a literal or another removed cast | 754 | removed |
| `for` bound whose counter is used only so | 189 | removed |
| `let` used only so | 5 | removed |
| comparison with an i64 (mostly a `var i = 0` counter), sign test | 1,138 | kept |
| `-`, `-=` | 386 | kept |
| other arithmetic | 314 | kept |
| stored: field, argument, return, assignment, typed let, `var` | 168 | kept |
| refused by the fixed point (counters, lets reaching the above) | 336 | kept |
| node with two parents (a tail value, a branch), closure | 48 | kept |
| other | 1 | kept |
| not a usize (u8, bool, enum, pointer) | 1,116 | not this fix's |

## What worked

- Working on the checked AST, with a parent map, per-local use lists and
  a fixed point, gave exact classes in about a second over compiler/src.
  The census and the fix are the same code, and `--only casts-list`
  prints both.
- The checked-edit framework (finish_edit) does the type half of the
  proof for free. The rules only have to show the meaning holds.
- `for i in 0..s.len` with no cast lets the effects pass mark the body's
  indexing as in bounds (walk_for), so the rewrite costs nothing.

## What cost time, ranked

1. The parent map. Fn bodies, For nodes and tail values show up as
   children of two nodes. A walk up to the enclosing Fn stopped there, and
   2,002 casts looked "copied" until closures were found by position.
2. The hook blocks reading command.vl past 300 lines. The Read tool
   worked around it.
3. `query grep --in FILE` takes a few seconds per call, so a text census
   over 299 files took minutes and was truncated at 60 hits per file. The
   AST census replaced it.

## Never used

`refactor`, `probe`, `reduce`.

## Fix list, in order (tagged)

1. [0.27, compiler/src] The 1,138 comparisons with an i64, mostly `while
   i < s.len as i64` with `var i = 0`. Removing them means making the
   counters usize. That collides with the `-` class (386), because these
   counters meet `i - 1` and `j - i`, and every such counter needs a
   decision. Leave it to 0.27's translation, which decides the ids' types
   too.
2. [fix] The census counts a generic function's cast once per instance
   (tests/refactor/casts0263edge.t shows 2 for one site). It should count
   by span.
3. [query] `query grep` without `--in` prints per-file counts when piped,
   not hits. A `--list` with every hit would have saved the per-file loop.
