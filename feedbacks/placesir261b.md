# Feedback: placesir261b, the places IR into both code generators (agent B, 0.26.1)

2026-10-30, release 0.26.1. Steps 1 and 2 of the brief committed: the
shared operator, cast, call-ABI and intrinsic helpers (d51db2df, no
output change), and -O1+ lowered from the places IR behind
`VOLE_LOWER=places` (6a937c62, middle/lower/places.vl, 1,220 lines),
with the fallback counted by reason and VOLE_LOWER in the code cache's
key. Steps 3 to 6 (drops and shims, the -O0 walk in gen0, places by
default, the fixpoint with it) are not started: left for a second round
once the shim question below is decided.

## Verdict

The places IR lowers to the middle IR in one walk without trouble for
drop-free bodies: 10,682 of compiler/src's functions at -O2 go through
it and the drop/temp/own/opt filters pass but for three IR-shape cases.
What does not fit is cost: IR to SSA is 2,061M instructions on
compiler/src at -O1 against the AST walk's 1,452M (the bar is 1,343M),
with no single hotspot. The time went to semantics the IR leaves to the
lowering (the result pointer, sink-closure capture flags, union
literals) and to telling an optimizer bug from mine.

## What worked

- Step 1 first: moving each operation behind one function per back end
  with byte-identical objects (`cmp` of compiler/src at -O0 and -O2, 390
  test objects) made step 2 a matter of calling them with values.
- `bootstrap/bootstrap.sh --dev --no-suite`: under 20 s, fixpoint each
  time.
- `VOLE_LOWER=places tests/run.sh -O 2 FILTER...`: the runner passes the
  environment, so one variable ran every filter under the new lowering.
- `--time-passes=instructions` with the fallback line in the same run:
  cost and coverage from one command.
- `--no-ifconv` and `--emit-ir` on a 30-line reduction: they separated
  the if-conversion miscompile (below) from the lowering in minutes.
- `volec fix --only unneeded-unsafe`, then `query unsafe --unjustified
  FILE`: the new file's 11 unjustified sites listed, each justified or
  narrowed; 3414 before and after.
- `sh tests/embed/run.sh -c target/tools/volec`: the cache-key check
  fails on 0.25.5's compiler (101 hits), so it tests what it claims.

## What cost time, ranked

1. Cost: three profiles of IR to SSA were flat (load_body about 5%, the
   per-function map clears, the block and local scans); no change I
   tried moved it more than a few percent. About 2 hours.
2. If-conversion: forwarding empty blocks (a goto-only block jumps to
   its target) made `sort_by` with an inlined `i64::cmp` compute
   `lt || ne`; `--no-ifconv` fixed it. middle/ifconv.vl mishandles an
   innermost-loop branch that joins at a three-predecessor phi. I
   removed the forwarding rather than fix another stream's pass. About
   1.5 hours.
3. Sink closures: the own pass clears `(*env).__live_x` when a closure
   body moves a flagged capture; the IR does not, so the env's drop shim
   would drop it twice. Found by a crash in a closure case; those bodies
   fall back (10 in the suite). About 1 hour.
4. The return: a goto to the return block first went through a phi of
   _0, which changed the layout of `opt_cold_layout` and `opt_isel`;
   returning at the goto, as the AST walk lowers `return`, fixed both.
5. The query-first hook blocked `grep` of a file I had written myself
   (places.vl) and of a 429-line file for one comment; `query grep
   --in FILE` worked, after a retry each time.

## Never used

- `refactor` (rename, move, signature): a new file, no renames.
- `probe`, `reduce`: crashes named their line.
- `tests/affected.sh --linux`: macOS only for this release (memory).

## Fix list, in order

1. [build] middle/ifconv.vl: the innermost-loop branch with a
   three-predecessor join miscompiles (reproduce: forward goto-only
   blocks in the places lowering, std `sort_by` on i64s).
2. [ir] places builder: write `(*_1).__live_x = false` when a sink
   closure body moves a flagged capture, as the own pass does (request
   R3 to A).
3. [ir] places builder: keep a union literal's value (lower_aggregate's
   `i < n` drops a field whose index is past the written count; request
   to A).
4. [ir] places builder: one multi-target TK_SWITCH for a switchable
   match (matching.vl's switch_cases rule), so `opt_switch` and the
   jump tables hold (request R4 to A).
5. [build] the places lowering's cost: one scan of the body instead of
   three (blocks, locals, borrows), PStmt read in place instead of
   copied, and the AST PROMOTE scan skipped for an IR body.
6. [design] the drop shims need a callable function: either a synthetic
   FNS entry and Fn node per shim made before init_ir (the shim set
   known at keep time), or the back end taking an IR function with
   f = -1 and the shim's symbol. Decide before step 3.
7. [tool:hooks] query-first: let a file the agent created this session
   be read with grep.
