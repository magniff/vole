# Feedback: placesir261b, the places IR into both code generators (agent B, 0.26.1)

2026-10-30, release 0.26.1. Committed:

- step 1: shared operator, cast, call-ABI and intrinsic helpers (d51db2df,
  no output change);
- step 2: -O1+ from the places IR behind `VOLE_LOWER=places` (6a937c62,
  middle/lower/places.vl), with the fallback counted by reason and
  VOLE_LOWER in the code cache's key;
- fold's `k ? false : false` fix (f1ceb3c4) and block forwarding back
  (7d80668b);
- cost work (e0cb7243);
- step 3, drops through A's shims (64af433d), contracts (1e177b31);
- step 5, -O0 from the IR in gen0 (74ae5651), and its code size made the
  AST walk's (35ee705c);
- ir: predecessor lists start small (db652f8b); gen0's analyses in one
  pass, a types-only scan, labels only where jumped to.

- step 6, places by default at every level (fb114599), the bar for -O0
  set at 1.15x (the gate's measure: 1.132x); two bugs the Book found on
  the flipped build fixed (7a640e96: a unit argument evaluated twice,
  check-alloc's drop sites).

Left: step 8 (the AST lowerings deleted), in 0.26.2 with A2's step 7.

## Verdict

The places IR lowers to the middle IR in one walk.

- At -O2 every function of compiler/src comes from the IR, 10,840 of
  them.
- A compiler built that way compiles compiler/src to the same bytes as
  the AST-lowered one.
- The remaining failures under VOLE_LOWER=places are the IR's drop
  semantics (temporaries dropped at their last use, part flags never set,
  a sink closure's second move unchecked), sent to A as R5-R9, plus two
  IR-shape cases. Two of them are use-after-frees that `--places-diff`
  does not see, because it compares named locals only.
- -O0 from the IR also builds compiler/src to a compiler that compiles
  it byte-identically, and its code is now the AST walk's size (3,159,628
  instructions against 3,172,169; objects 18,010,224 against 18,040,272
  bytes), from 22% more.
- Cost, compiler/src at -j1 (instructions; the totals vary by about
  ±70M between runs):
  - -O2 total: 66,643M against 66,247M (1.006x). -O1 total: 23,796M
    against 22,131M (1.075x).
  - -O0 total, the gate's measure (/usr/bin/time -l, default -j, on
    df931cf9): 10,892M against 9,587M (1.136x; -j1 1.130x). The bar,
    1.10x, is about 300M away.
  - `--time-passes` costs the places path about 1.2G more than the AST
    walk's (a timer read per function and phase), so its -j1 table says
    1.23x; use it for where, not how much. In it emission (mine) is
    +737M over the AST walk's: the generator's own passes, not the code
    it emits.
  - Where (in-process counters, compiler/src at -j1: 10,982 functions,
    157k blocks, 248k locals, 479k statements): gen_blocks 1,984M
    against the AST walk's whole gen_function 1,867M; the analyses
    before it about 450M (scan_locals ~250M, take_body ~100M,
    forward_blocks ~80M, slots and share_slots ~40M), some 400 to 500
    instructions per statement or block, spread over Vec reads and
    pushes. Cutting the calls (op_kind inlined by hand) or the scans
    (forward_blocks in one scan per block) moved nothing measurable;
    the lever is not walking at all: A's keep records each local's
    mentions (asked of A, with the RPO kept with the body).

## What worked

- Step 1 first: each operation behind one function per back end, with
  byte-identical objects (`cmp` of compiler/src at -O0 and -O2, 390 test
  objects). Step 2 was then a matter of calling them with values.
- `bootstrap/bootstrap.sh --dev --no-suite`: under 20 s, fixpoint each
  time.
- `VOLE_LOWER=places tests/run.sh -O 2 FILTER...`: the runner passes the
  environment, so one variable ran every filter under the new lowering.
- Self-compilation as the shadow: a places-lowered compiler's output
  compared with `cmp`.
- `--print-after-all` and `--emit-ir` on a 30-line reduction, then the
  first dump with the wrong `or`: the "ifconv" miscompile was
  fold::combine_select (`k ? false : false` taken for `!k`). It
  reproduced on the AST path too, once the comparator had early returns.
- `--emit-places`: every R5-R9 request came with the IR lines that show
  it.
- `sample` six times plus a 20-line awk (self and inclusive samples by
  function) told the scans apart from the walk.
- `query unsafe --unjustified FILE` and `fix --only unneeded-unsafe`.

## What cost time, ranked

0. The -O0 code size (step 5): finding the classes took an instruction
   mix diff (each line's opcode with operands normalized, ast against
   places), then the hottest small functions side by side. Four classes
   made almost all of the 22%: values that the AST walk keeps in the
   accumulator across `&&`/`||` and if-arms; compound call results copied
   from their own slot; push/pop around a constant or frame operand; and
   index checks reading their length through a temporary. About 3 hours.

1. Cost. In-process instruction counters cost about 33k instructions a
   read (a syscall), which buried the small sections; sampling did
   better. The three ideas (one scan, PStmt in place, lazy PROMOTE)
   saved about 40M before the drops, and about 100M once no function
   fell back. About 3 hours.
2. The miscompile: 1.5 hours the first time. After the reduction it was
   20 minutes (it was not in ifconv.vl).
3. Drop failures: 43 cases to triage, most of them one cause (R5). About
   1 hour.
4. Sink closures, the result pointer, the return at the goto (layout
   cases): about 1.5 hours together.
5. zsh: `$R` with spaces is one word (`edit patch ... $R` failed four
   times), and `=====` is a command expansion.

## Never used

- `refactor` (rename, move, signature): a new file, no renames.
- `probe`, `reduce`: crashes named their line; reductions by hand were
  faster.
- `tests/affected.sh --linux`: macOS only for this release.

## Fix list, in order

1. [ir] A's R5: temporaries dropped at the end of the statement, not
   after their last use (two use-after-frees: `v == v.clone()`,
   `b + mk(3)`).
2. [ir] A's R6: a part's drop flag set when the whole is initialized,
   and cleared at entry.
3. [ir] A's R7: a sink closure's move of a flagged capture checks the
   flag (exit 101), as the own pass does.
4. [ir] A's R8 and R9: a raw-pointer read of T is not dropped; Vec
   indexing without `as_slice` (entry facts).
5. [test] `--places-diff` compares named locals only. It should compare
   the temporaries' drops too, which would have caught R5.
6. [build] cost: load_body packs and unpacks every body word by word
   (about 8% of the lowering's samples). A body read in place, or copied
   in bulk, is the next saving. Then the per-statement walk: operand and
   bind, about 25%.
7. [build] -O0 cost of the places generator: its per-function passes
   (about 360M for the analyses) are mostly static Vec accesses in tight
   loops. A function-local table, or raw slices for P_STMTS and P_OPS,
   would halve them.
8. [tool:hooks] query-first: let a file the agent created this session
   be read with grep.
9. [tool] `git checkout FILE` to undo temporary instrumentation threw
   away an uncommitted rewrite once. Instrument a copy, or let `volec
   undo` take back a batch of edits made by a script.
