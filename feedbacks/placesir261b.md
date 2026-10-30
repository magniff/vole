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
- step 3, drops through A's shims (64af433d).

Left: step 5 (the -O0 walk in gen0) and step 6 (places by default, the
fixpoint with it).

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
- Cost is still over the bar: IR to SSA 1,838M against the AST walk's
  1,428M (the bar is 1,343M), with no single hotspot.

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
7. [build] -O0 `--emit-ir`: a flagged drop's split block prints after
   the rest (fmt_direct_ir's CHECK order).
8. [tool:hooks] query-first: let a file the agent created this session
   be read with grep.
