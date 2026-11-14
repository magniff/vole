# The compiler's own speed

Where the time of a self-build goes, what 0.30 took out of it, and what
stands between it and the goal: a cold self-build under one second, a
warm one instant (the owner, 2026-11-12). Measured at the start of 0.30
(the 0.29.0 tree) and after the changes of this document, on an Apple
M-series machine with 10 cores (4 performance, 6 efficiency).

## How it is measured

Instructions retired, not time: the machine is shared, and a time taken
under load says nothing. Every figure below is the fewest of two or
three runs; a time is given only with the 1-minute load beside it.

- `tools/perf-diff.sh A B FILE.vl` (`-O0`, `--check`): two compilers on
  one input, each phase and each optimizer pass, on one thread
  (`--no-cache -j1 --time-passes=json`). "before" below is the tree at
  the start of 0.30 built by itself, "after" the tree with these
  changes built by itself; both compile the same source, the tree at the
  start (484 files).
- `tools/perf-experiment.sh -b BASELINE`: the three workloads and the
  compile-cost programs against a released compiler.
- `bench/run.sh --instructions -p BASELINE`: what the generated code
  costs, so that a change to the pipeline is not paid by the programs.
- Per function: `/usr/bin/sample PID 30 1` (a sample a millisecond) of
  a `-j1` build, and the call graph summed per function (self and
  inclusive). A 3 to 9 s run gives 1000 to 6000 samples: a function with
  N samples is known to about the square root of N, so a row under 20
  samples is a hint. Samples are time, not instructions: a walk of the
  128-byte instructions that misses the cache has many samples and few
  instructions.
- The same object: the -O2 object of the compiler written by the
  compiler before and after a change is compared byte for byte. All but
  one of the changes below leave it the same.

## Where a self-build goes

Instructions retired on one thread, in millions, the compiler compiling
its own source:

| phase | -O2 before | -O2 after | -O0 after | check after |
|---|---:|---:|---:|---:|
| read, lex and modules | 2395 | 2442 | 2411 | 1483 |
| parse | 708 | 708 | 711 | 782 |
| check | 9290 | 7563 | 7569 | 8680 |
| effects | 770 | 766 | 765 | 768 |
| places (build, elaborate) | 3317 | 2951 | 2955 | 2700 |
| borrowck | 8879 | 7750 | 7748 | 7801 |
| lower to SSA | 2758 | 2827 | | |
| scalar pipeline (-O1 part) | 12560 | 11395 | | |
| interprocedural constants | 618 | 533 | | |
| inlining (and simplification) | 25548 | 20678 | | |
| loop passes | 36757 | 26824 | | |
| licm | 5051 | 4249 | | |
| scalar promotion, heap to stack, attributes, dead functions, SLP | 2540 | 2256 | | |
| instruction selection | 1997 | 1694 | | |
| register allocation and emission | 10937 | 10913 | 4752 | |
| data and output | 2714 | 2712 | 4324 | |
| total | 126971 | 106262 | 31235 | 22213 |

(-O0 before: 34467; check before: 25459. `check` checks the tests'
code too, which a build leaves out: its check row is larger.)

By optimizer pass at -O2 (each pass wherever it runs), before and
after: gvn 27445 and 22139; loops: folding by ranges 13827 and 7681;
register allocation 8055 and 8037; sccp 6981 and 6850; sroa 5325 and
4125; dead code elimination 3265 and 2224; simplify_cfg 2967 and 2389;
instcombine 2932 and 2585; constant slots 2718 and 2361; inlining (the
calls) 2574 and 2578; the loop transforms 2236 and 2237; tail recursion
2174 and 2100; instruction selection 1986 and 1684; copy elision 1932
and 1815; rotation 1853 and 1662; frame and layout 1857 and 1854;
strength reduction 1613 and 1613; vectorization 1527 and 1401; licm
1499 and 1531; aggressive dead code 1434 and 1318; resolve between
passes 248 and 27; the rest under 1000 each.

**Threads and wall time.** A build uses 8 threads (the main thread and
7 of the pool). The main thread's samples in a threaded -O2 self-build
(2460 at a load of 3.4; the after tree before its last three changes)
say where the wall time is:

| the main thread is in | samples | what runs |
|---|---:|---|
| read, lex, modules | 64 | one thread |
| parse | 28 | one thread |
| check, effects, places, borrowck | 876 | one thread |
| lower to SSA | 152 | one thread |
| the scalar pipeline and the cleanup | 103 | the pool |
| whole-program walks between the tasks' phases: the call sites counted (86), interprocedural constants (45), the taken functions (31), the functions' sizes (23), unreachable std (15), the components (12) | 212 | one thread |
| inlining and the loop passes, bottom up by component | 759 | the pool |
| instruction selection, register allocation, emission | 171 | the pool; the main thread joins the tasks' text and assembles it (83 + 28 of the 119 it spends joining at -j1) |
| data, the object, the link | 48 | one thread |

So 58% of the wall time of a -O2 self-build is one thread: the front
end 40%, the lowering 6%, the walks between the phases 9%, the output
3%. `check` is one thread throughout. A -O0 build is one thread but for
the assembler, which overlaps the generator a little (1.63 s of CPU in
1.53 s).

Times, the same binaries, 1-minute load 1.9 to 2.8, whole process
(`/usr/bin/time -l`; "after" here is three small changes short of the
table above, 0.6% more instructions):

| workload | before | after |
|---|---|---|
| -O2 self-build | 3.43 to 3.57 s, 130.7 G | 3.01 to 3.11 s, 111.2 G |
| -O0 self-build | 1.71 to 1.74 s, 34.5 G | 1.53 to 1.68 s, 31.2 G |
| check | 1.50 to 1.58 s, 25.5 G | 1.27 to 1.28 s, 22.2 G |

## Per function (before)

The functions with the most samples of their own in a `-j1` -O2
self-build (6194 samples) were walks of the IR, not work on it:
`ir_resolve_operands` 347, `find_escaping_slots` 158, `build_users`
(sccp's users) 148, `run_gvn` itself 145, `bits_of_value` 141,
`layout_order` 135, `eliminate_dead_code` 114, `memmove` 100,
`narrow_by_facts` 94, `compute_dominators` 92, `resolve_all` 88,
`sccp_eval` 86, `count_call_sites` 84, `is_memcpy` 77, `bzero` 74.
Inclusive: `simplify_function` (the scalar pipeline, wherever it runs)
36% of the build, `run_gvn` 17%, `fold_by_ranges` 7%, `resolve_all` 6%.

In `check` (1158 samples): borrowck 30% (`solve` 9%, the move checks
7%, `zero_fill` 7%, the access check 4%), the type check of bodies 32%,
`report_unused_imports` 4%, the layouts asked by `size_of` 4%,
`infer::sweep` 5%.

## The bounds checks

0.29 made the compiler's tables `Vec`s, indexed with checks. What they
cost, measured: a compiler built from the 0.29.0 tree by a scratch
compiler whose lowering leaves the index check out (the slice range
checks stay; nothing of it is in the tree) builds the tree in 105.9 G
where the checked one takes 127.0 G: **21.0 G, 16.6% of the self-build**,
spread evenly (10% to 25% of every phase: sccp 26%, the ranges 22%,
register allocation 19%, gvn 16%, check 14%, borrowck 15%). Its text is
13% smaller. With no check the 0.29 tree would be at 0.28.0's figure
(103.6 G); the checks are the whole regression.

What is left of them at -O2 (`--print-checks`): 33694 index checks, and
12791 that the ranges removed. By what the index is (from the optimized
IR of the whole compiler):

| the index | checks | |
|---|---:|---:|
| read from memory (an operand of an instruction, a node's child) | 12399 | 36.8% |
| a phi (a loop's or a merge's variable) | 11070 | 32.9% |
| a parameter | 7000 | 20.8% |
| a call's result | 2520 | 7.5% |
| a constant | 573 | 1.7% |

and 80% are against the length of a `Vec` behind a reference parameter
(the context). Two thirds have an index that is data: nothing the
function knows bounds it.

Which the optimizer could prove away, each fact looked at:

- **A dominating check of the same index against the same length** is
  already one check (value numbering). What is left is the same index
  against the same header *read again*: 7083 of the 33694 (21%), after
  a store or a call between the two. Weighted by where the time is (the
  share of each function's checks that are such, by its samples), they
  are 13% of the checks run; a check being a sixth of the cost where it
  is, **removing every one of them would give about 2% of the build**.
- **A store to another Vec's element** (the third Vec fact of 0.29's
  notes: a Vec's buffer does not hold the object that holds the Vec; 10
  lines in `vecfacts::vec_apart`, sound by the argument of the second)
  was tried again now that the contexts hold many Vecs: the compiler's
  own code gains nothing that shows (the front end's phases, which do
  no more work for it, move by -0.1% to +1.5%), and value numbering
  pays for the entries that survive: gvn +12.1%, the build +3.0%. Left
  out, for the second time.
- **A call between** (the header summaries of 0.29): 4018 of the 6261
  functions with attributes have no summary. Followed to the first
  unknown callee, the roots are few: writing formatted text to a
  `String` (`write_erased`, 27% of the unknown ones), the buffer and
  symbol tables' atomics (`buf_new`, `buf_str`, `intern`,
  `buf_reserve`: 33%), `Vec::resize`'s block fill (4%), the type
  checker's recursion. An atomic must stay unknown as the rule stands
  (a lock is atomics: a callee that unlocks and locks lets another
  thread write); a header behind a `&mut` could be kept across it, and
  the formatting could be followed. Not done: the bound above (2% for
  all of it) does not pay for it, and the experiment with the stores
  found less than the bound.
- **A table's length never shrinks** (a monotone length): the same
  bound; the proof needs each callee's stores to a length to be
  increments that do not wrap, which is the Vec's invariant and no fact
  the optimizer has.
- **An index read from a table whose entries are checked on write**: a
  fact about every value of a field (an instruction's operand is an
  instruction of this function), which no local analysis has. It would
  take a type that carries it (an index type made only by the table
  that hands it out) and the table not shrinking: a design change.
- **A loop over 0..len**: done by the ranges where the length does not
  change (12791 removed); where a call in the body may change it, it is
  the call case above.
- **A store through a `&mut [T; N]` parameter making the callee's
  summary unknown**: not found at this tree. A callee that stores
  through an array parameter is `known: writes none`, one that stores
  through a slice `writes through operand 0`, and the caller keeps its
  Vec header and has one check in both.

So the checks stay at about a sixth of the build, and the way back to
0.28.0's figure was the other costs.

## What 0.30 took out

Each with the instructions of the -O2 self-build (or of `check`) before
and after it, and the same object written unless said:

| change | where | effect |
|---|---|---|
| `resolve_all` returns when no value was replaced since it last ran (`FnCtx.resolved_len`, kept with the function) | middle/opt.vl, ir/mod.vl | 126.9 to 123.4 G |
| value numbering restores a dominator's available loads with one block copy; `param_written` looks only at the instructions made since, inside `run_gvn` | middle/gvn.vl | 123.4 to 121.8 G |
| a fact's two operands are found once, with the marks (`FnCtx.fact_ab`) | middle/range/mod.vl | 121.8 to 115.8 G: the ranges 13.8 to 7.7 G |
| sroa's map of definitions is not zeroed whole for every function; no slot walks in a function with no slot | middle/lower/ssa.vl, gvn.vl | 115.8 to 114.9 G |
| borrowck's sets are zeroed as one block | places/borrowck/mod.vl | check 25.5 to 25.0 G |
| a field's size and alignment come from one layout (`size_align`) | front/types.vl | check 24.9 to 23.0 G |
| the liveness is transposed only for the locals a region reads | places/borrowck/solve.vl | check 23.1 to 22.4 G |
| the scalar pipeline's second round runs a pass only on a function changed since that pass ran | middle/opt.vl | 111.4 to 107.8 G; the code is not the same (below) |
| `sweep` passes primitives; `layout_order`'s stack; one walk less in dead code elimination | front/check/infer.vl, back/regalloc/prepare.vl, middle/opt.vl | 107.9 to 107.0 G |
| `reached_through` walks the use nodes and path tokens, listed once | tools/reexports.vl | check 22.4 to 22.2 G |
| the dead functions are found with one walk of the program | middle/opt.vl | dead functions 255 to 107 M; a walk on the main thread less |
| a function with no loop skips the passes over loops | middle/opt.vl | 106.8 to 106.2 G |

The second round is the one change that alters the code: the passes
are not exactly idempotent, so 1720 of the compiler's 6260 functions
differ in their IR (0.3% more IR lines in all, the text 0.04% smaller).
What it costs the programs: `bench/run.sh --instructions` geomean
+0.03% over 24 programs (json +0.33%, iterchain +0.20%, 17 within
0.02%); the compiler's own source built by both pipelines runs the
self-build in 111.81 G and 111.54 G.

Against the released 0.29.0 (`tools/perf-experiment.sh`, each compiler
on the tree's source, a load of 7):

| workload | 0.29.0 | this tree | |
|---|---:|---:|---:|
| self-build -O2 | 124.74 G | 104.50 G | -16.2% |
| self-build -O0 | 34.31 G | 31.21 G | -9.0% |
| check | 25.28 G | 22.21 G | -12.1% |
| hello | 153.0 M | 149.0 M | -2.6% |
| std_heavy | 1231.0 M | 1119.0 M | -9.1% |
| regions | 1125.5 M | 1126.6 M | +0.1% |

0.28.0's
figures, each release on its own source, were 103.6 G, 29.9 G and
21.3 G: the -O2 build is within 1% of it with every check kept, the -O0
build and the check 4% above.

## What is left, with its size

Seen and not done; the size is of the workload named.

- **`infer::sweep` at every unification** (5% of `check`, 1.1 G): each
  successful `unify` retypes every node and local of the function, also
  when it solved no variable. Sweeping only after a variable was solved
  is not the same program text for text (a node typed since the last
  sweep keeps a solved variable until the next), and the type checker's
  cases are most of the suite: not changed without it.
- **Borrowck's sets are dense** (points by locals, regions by points):
  the cost grows with the square of a function (a function of 8000
  calls: 2.2 G, a third of it block fills). In the compiler it is small
  (the 22 generated text functions of 200 to 2300 calls: about 0.4 G of
  the 7.8 G), and the rest of borrowck is spread: `solve` 14%, the move
  checks 26%, the access check 24%, the constraints 15%, liveness 9%.
- **The dominators and the loops are found again by every pass** that
  wants them (`analyze_loops` 3.6% of the -O2 samples, `layout_order`
  2.6% of its own): there is no count of the CFG's changes that a pass
  could trust, since blocks' terminators are written in place.
- **`find_escaping_slots`** (2.7% of the samples), **sccp's users**
  (2.8%), **`ir_resolve_operands`** inside value numbering and
  instcombine (1.2%): walks of every instruction, bound by memory (an
  instruction is 128 bytes).
- **The whole-program walks between the tasks' phases** (the call sites
  once, the constants, the sizes: about 6% of the wall time of a -O2
  build after two of the dead functions' three walks went): they could
  run in the tasks.
- **The assembler reads text**: the code generator writes assembly and
  the assembler parses it: 12% of the samples of a -O0 build (about
  4 G of its 31 G) and 2% of a -O2 one, there on the main thread while
  it joins the tasks (4.5% of the wall time).
- **Reallocation** of the passes' local stacks and lists (`realloc`
  1.8% of the -O2 samples before `layout_order`'s stack, a quarter of
  it, was given its room).
- **The tools' cache**: a `check` that writes it costs 29.6 G where
  22.2 G checks (below).

## The goal: one second cold

Where a cold -O2 self-build stands: about 3.0 s at a load of 2 to 3,
106 G on 8 threads. From the main thread's table, of that wall time
about 1.2 s is the front end on one thread, 0.2 s the lowering, 0.25 s
the walks between phases (0.2 s now), 1.05 s the optimizer's two
parallel phases, 0.2 s the back end, 0.06 s the output. What would have to change, each
with what the profile says it gives:

| change | gives | from |
|---|---|---|
| the front end in parallel: bodies checked, lowered to the places IR and borrow-checked by the pool, after one thread has collected the items | 0.7 s of the 1.2 s (84% of `check_program`'s samples are per body; the 8 threads of mixed cores give about 4.5 times on the optimizer's components) | the main thread's table; `check` and the -O0 build gain the same |
| the lowering to SSA in the tasks | 0.15 s | the same |
| less than -O2 for the compiler's own build | a -O0 build is 31 G against 106 G and 1.55 s: about 0.85 s with the first row, where -O2 stays near 2.2 s | the phase table: the optimizer is 67 G of the 106 G |
| code generated as bytes, not text for the assembler | about 4 G of 31 G at -O0 (0.15 s, part of it on the assembler's thread already), 2 G at -O2 | the samples of the assembler |
| -O0's generator in the pool | 0.15 s (its 4.8 G are one thread: 13% of the samples) | the -O0 table |
| the walks between phases in the tasks | 0.15 s at -O2 | the main thread's table |
| std read lazily further | under 0.05 s: read, lex and modules are 2.4 G in all | the phase table |
| the bounds checks | 17 G of 106 G, if the tables' indices were types that carry their bound | the scratch build; a design change, not an optimizer's |

A cold second is within reach for the -O0 build (the front end in
parallel 0.85 s; with the generator in the pool and no text about 0.55
to 0.65 s on this machine), not for the -O2 build: with every row but
the last it is near 1.8 s, and what is left is the optimizer's 67 G on
8 threads, which 0.30 brought from 84 G. These are estimates from the
samples of one machine at a load of 2 to 3, not measurements of the
changes.

## The warm case

As it is (the tree's compiler, a load of 4 to 5, the tools' and the
code cache on, in a directory of their own):

| step | time | instructions |
|---|---:|---:|
| `check`, cold, writing the cache | 1.93 s | 29.6 G |
| `check` again, nothing changed | 2.11 s | 29.3 G |
| `check` a third time | 0.04 s | 0.7 G |
| -O2 build, cold cache | 4.71 s | 119.2 G |
| -O2 build, nothing changed | 2.65 s | 40.1 G |
| -O0 build, nothing changed | 1.55 s | 31.3 G |
| after an edit of one function: `check` | 1.61 s | 29.3 G |
| after it: -O2 build | 2.26 s | 40.1 G |
| after it: -O0 build | 1.61 s | 31.2 G |

What bounds it: nothing of the front end is kept between runs. A
`check` after an edit of one function reads, checks and borrow-checks
every function again (and pays 7 G more than an uncached check for the
cache it writes; the second run of an unchanged tree does too, only the
third is answered from it). The code cache saves the optimizer and the
back end (119 G to 40 G), and what is left is the front end (22 G) and
18 G more: every function lowered again and compared with what the
cache has, the data and the link (not split further here). A -O0 build has no cache at all. So the warm case is the
cold front end: "instant" needs the checked bodies kept by function
(their types, places IR and borrowck verdict, keyed by the function's
text and the signatures it reads), which is the same split the parallel
front end needs: one thread collects, each body is a task with its own
inputs.
