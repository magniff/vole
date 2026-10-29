# Feedback: bugs254, the open bugs carried into 0.25.4 (seven items)

2026-10-29, release 0.25.4. Worked on compiler/src/front (check/names.vl,
check/collect.vl, closures/mod.vl, closures/fn_bounds.vl, conv.vl,
generics/mod.vl, lexer/blocks.vl, lexer/strings.vl, lexer/mod.vl,
contracts/expand.vl, contracts/diag.vl, check/mod.vl), base/diag.vl,
tools/lsp/complete.vl, tools/explain/v018_table.vl, bootstrap/gate.sh,
tools/agent-hooks (check-after-edit.py, turn-end.py, test-turn-end.py),
the guide (text, syntax, contracts), five new tests/run cases, three
XFAILs turned to passes. About 700 lines over nine commits and a merge.

## Verdict

Finding causes in the compiler was quick: `query context`/`query show`
led from a symptom to the line in a few calls each time (the `const X:
str` crash was three hops: synth_name, Res::Const, lower_ident's
`ir_const`). Most lost time was in the shell around the tools (zsh
expansion, my own `| tail` hiding output), in edit ordering (a patch
that calls a helper not yet inserted is refused), and in the gate item,
where the logs had to be read to see that the brief's premise (a lost
slot) was not what happened.

## What worked

- `target/tools/volec query context closure_call`: the function, the
  14 calls with signatures, and its one caller, in one answer; showed
  that closures check arguments with `check_arg`, not
  `check_call_arg`.
- `target/tools/volec query refs LET_ARG`: the three places the let
  temporary is decided; that was the whole mechanism.
- `target/tools/volec query grep "this value has no place"` and
  `query grep "a string literal constant is a"`: from a message to its
  emitter, `compiler/src/front/check/mod.vl:321`.
- `edit patch NAME --pairs FILE` with `<<<<<<< OLD / ======= / >>>>>>>
  NEW` blocks: multi-line patches without shell quoting trouble (my
  `--old '...\t...'` attempt failed to match; the pairs file did).
- `edit insert NAME --before|--after < file`, with `note edit.imports:
  added the imports the new text needs`.
- The check hook's fix after a commit: `changed
  compiler/src/front/closures/mod.vl:50: - use
  crate::front::generics::check_arg;` (the import my change left unused).
- `fix --suggested` on copies of the three sem_poly cases made the fix my
  new diagnostic proposed, and each fixed program ran (`drop 1`).
- The commit hook's `unsafe-diff-check: 1 unjustified site` caught a new
  `unsafe` without its comments before it landed.
- `bootstrap/bootstrap.sh --dev --no-suite`: 12-20 s per build, every
  time.
- `docker run --rm -i debian:bookworm-slim sh -s < script`: the
  container's dash, to test the jobserver's FIFO in seconds (dash reads
  one byte per `read`; traps fire in `( ... ) &` subshells: both checked
  that way, both fine).

## What cost time, ranked

### 1. The gate stall's premise
The brief said a slot was lost. The container logs
(.claude/worktrees/integ-0.25.3/target/gate/20261029-080848/linux-aarch64.log)
showed `fuzz-vector FAIL 20:43 stalled ... 0 of 8 slots free (slots
lost with killed jobs?)` while the other 18 rows ran on the same 8 slots
to 53-58 min and passed; 0.25.2.2's log is the same with fuzz-loops at
16:02. So nothing was lost: "0 free" is the pool at full load, and the
check took it for loss. Before reading the logs I spent about 8 turns
on loss theories (dash trap semantics, dash `read` buffering, FIFO
fairness under 17 and 19 readers), each tested in the container and
each fine. What would have saved them: the gate writing what a stopped
row's processes were waiting on (it does now: state and wchan into the
row's log), and the stall message not guessing the cause.

### 2. Shell traps around the tools (zsh)
- `tests/run.sh =closure_let_temp` printed `(eval):1: closure_let_temp
  not found` and ran nothing: zsh's `=word` expansion. AGENTS.md
  writes `=NAME` unquoted. 1 turn.
- `grep -rn X --include=*.sh .`: `no matches found: --include=*.sh`.
- My `| tail -3` after `edit patch` hid the error line that `edit.breaks`
  prints first (`main.vl:2:5: error[type error] undefined variable ...`,
  then `error edit.breaks: 1 new error; nothing written`). The tool was
  right; the order (error above the summary) makes a tail lose it.

### 3. Edit ordering
`edit patch error_text` calling `fix_refused()` before `edit insert`
of `fix_refused` is refused (`edit.breaks: 1 new error`); twice, two
turns. `edit apply FILE` would have done both in one checked step; the
note `edit.together` says so, after the fact. Also: `--pairs FILE`
cannot be mixed with `--old/--new` (`the pairs come from --old/--new or
from --pairs FILE, not both`), so the explain table's length and its
`V018_COUNT` took two calls and a `--no-check`.

### 4. Closure parameters' conventions live elsewhere
For item 2 I first used `fn_param_conv(f, i)` on the closure's
function: it returns LEGACY, because the closure's FNS entry is a
synthesized Fn node with no Param children, and a closure parameter's
`let`/`sink`/`inout` is a flag on its *type* node (`NODES[p].b`), not on
the Param node as a function's is. Two builds to find out (the first
fix compiled and changed nothing). A `query` that says where a
construct's flags are kept, or one accessor for "the convention of
parameter i" of any callable, would have saved them.

### 5. Keywords as names give a parser error elsewhere
`let inout = ...;` in an inserted function: `error[parser error]
expected '|', got '{'` at 215:17, a later column, not "`inout` is a
keyword". 1 turn.

### 6. The hook checked with the older binary
After a scratch build that allowed `const X: str`, the check hook (with
target/tools/volec) still reported the old refusal on my repro while
target/volec built and ran it. Expected (tools is the tested build), and
item 6 of this brief is the same problem in another form; the hook's
note now names it when the versions differ, not when only the source
does.

### 7. Language surprises met on the way (not fixed here)
- `let n = "w";` then `scale(1.0, n)` with a `str` parameter:
  `error[distinct.mix] 'n' is '[u8]' where 'str' goes | help: a str is
  UTF-8: bytes become one through str::from_utf8(b) ...` — a literal
  bound by `let` is bytes, so passing it on is an error with a long help
  about UTF-8. `let s: str = "w";` works.
- `let y: f32 = 0.25; x == 2.0 * y` with x f64: `expected 'f64', got
  'f32' | help: only widening is implicit: convert explicitly`; f32 to
  f64 is a widening, so the help contradicts the refusal.
- A `\"` inside an f-string hole: `error[tokenizer error] unexpected
  character`, no help, no try (twice, in test files).
- `volec fmt` rewrote `fn total(v: let Vec<i64>)` to `fn total(v:
  Vec<i64>)` in a test about `let` parameters (let is the default):
  correct, surprising.

## Never used

`refactor` (nothing was renamed or moved), `probe` and `reduce` (every
bug reproduced in a few lines and the cause was readable from the
source), `query impact`/`effects`, `batch`, `undo`, the language server.

## Fix list, in order

1. [docs] AGENTS.md: write `tests/run.sh '=NAME'` quoted (zsh, the
   agents' shell, expands `=NAME`).
2. [diag] `let x = "lit"` given to a `str` parameter: suggest `let x:
   str = "lit"` (the binding's type), not str::from_utf8.
3. [diag] f32 to f64 refused with "only widening is implicit": say why
   this widening is not implicit, or allow it.
4. [diag] a keyword used as a name (`let inout = ..`): say so at the
   name, with the rename.
5. [diag] a `\"` inside an f-string hole: say that a hole cannot hold a
   string literal and to bind it with `let` first.
6. [tool:edit] `edit patch` with `--pairs FILE` and `--old/--new`
   together (or several `--in` items in one pairs file), so dependent
   edits are one checked call.
7. [tool:edit] on `edit.breaks`, repeat the first new error in the
   summary line, so a view of the last lines keeps the cause.
8. [tool:query] one accessor or query for a parameter's convention of any
   callable (functions keep it on the Param node, closures on the type
   node).
9. [lang] contract messages' holes: floats and text (a failure helper
   that formats them; today `contract.message` refuses them).
10. [lang] `assert`'s float operands in millionths (`1500000e-6`): the
    same helper would print them as decimals.
11. [tool:fix] values017 (the 0.19 `fix --values` migration): open since
    0.25 with no release; decide to fix or drop the transcript.
12. [build] the gate's stalled-row log now has the processes' wchan: read
    it at the next stall before theorizing.
