# places: the places IR

A MIR-like form of every checked function body (0.26.0; the design is
[docs/design/places-ir.md](../../../docs/design/places-ir.md)): typed
locals, places with interned projections, explicit temporaries, borrows as
rvalues, storage markers, and drops decided per place with drop flags. In
0.26.0 it is built and elaborated beside the own pass's drops, which are
still the ones the code generators run; `--places-diff` compares the two.
From 0.26.1 both code generators read it.

| file | |
|---|---|
| `ir.vl` | the contract: the body's tables (locals, projections, statements, blocks, operands, switch targets), their kinds and fields, and the functions that make and read them |
| `cfg.vl` | predecessors, reverse postorder, immediate dominators of the body held |
| `print.vl` | `--emit-places`: a body as text, what `// PLACES:` lines match |
| `verify.vl` | `--verify-places`: the form, the places, the copy rule, `as V` dominance, storage |
| `build.vl` | the builder: a checked body to the IR, in evaluation order, reading the own pass's nodes; a construct it does not build makes the body a fallback (`--verify-places` names it; none left in 0.26.0) |
| `elab.vl` | drop elaboration: move paths, maybe-initialized and maybe-uninitialized (and the variants an enum may hold) over the reverse postorder, each drop kept, removed, under a flag or opened; the flags' writes |
| `diff.vl` | what is left for after the own pass: the move-out backstop (`own.move_out`) and `--places-diff` |
| `keep.vl` | kept bodies (0.26.1, R1): at a build whose code generators read the IR, each elaborated body packed in one allocation (`keep_body`), put back into the `P_*` tables (`load_body(f) -> bool`) and freed once generated (`free_body(f)`) |
| `shim.vl` | drop shims (0.26.1, R2, places-ir.md §3.9): `shim_of(t) -> id` made on demand, `shim_count()`, `build_shim(id)` (a body, `_1: &mut T`, B_FN -1 and B_SHIM id), `shim_fn_symbol(id)` (`$drop.G` and the type mangled) |
| `front.vl` | what the IR reads of the checker's raw tables, one justified accessor each |
| `mod.vl` | the driver (check_program calls `run_places`, then `after_own` after the own pass) and the options: `--places`, `--no-places`, `--emit-places[=all]`, `--verify-places`, `--places-diff`; `--keep-places` (keep the bodies, print them loaded back) and `--emit-shims` (with `--emit-places`: the shims the printed bodies' drops call, and theirs) |

In 0.26.0 the IR is built only under `--places` (or `--emit-places`,
`--verify-places`, `--places-diff`; the tools' cache is not used with
them): its builder costs about 430M instructions at `check` of
compiler/src, over §6's 340M for all of step 2, so §6's fallback rule
applies. `// PLACES:` lines in tests/run cases (`places_*`) match
`check --emit-places --places-diff`'s output.

One body is held at a time (`ir.vl`'s `P_*` tables), cleared and reused
for the next. At a build whose code generators read the IR
(`keep::KEEP_BODIES`, which B's `VOLE_LOWER=places` sets; `--keep-places`
at check) each is kept after elaboration (keep.vl) and loaded back when
its function is generated. A kept body is as elaboration left it: its
types are the checker's, distinct ones not erased (`undistinct`).

A drop that runs (DS_KEPT, DS_FLAG, and an open drop's parts, each
decided) of a place of type T is a call of T's shim (`shim_of(T)`) with
`&mut P`. A shim's own drops are DS_KEPT (through `*_1`: no move path),
so lowering a shim asks for more shims: loop `while id < shim_count()`.
A shim's `Drop::drop` call is the instance the checker made for the own
pass's glue (until step 7 deletes it; a shim that finds none stops the
compiler with `places: a drop shim found no Drop::drop instance`).

`--check-unsafe` stays on the AST path in 0.26.1: under it
`middle/lower/places.vl` lowers no body from the IR and no shim (its
checks name the AST's raw accesses; `places lowering: ... check-unsafe N`
counts them, 586 functions over tests/run at -O2). Its move to the IR is
step 8's, in 0.26.2, with the AST walk's removal.

## The contract

`ir.vl`'s header comment is the reference: what each projection, operand,
statement, terminator and rvalue kind means and which fields it uses. In
short:

- a place is a local and a projection list (`PJ_FIELD`, `PJ_DEREF`,
  `PJ_INDEX` by a local, `PJ_CONST`, `PJ_VARIANT`, `PJ_UNION`), interned
  per body: two words;
- an operand is three words in `P_OPS`: `copy`, `move`, a place not read
  (a borrow's, a discriminant's), or a constant;
- a statement is a `PStmt`; a block is a range of `P_STMTS` whose
  terminator is the slot after it; a location is an index of `P_STMTS`,
  a point `2 × location` or `2 × location + 1`;
- calls and drops are statements: a panic exits with 101 and nothing
  unwinds (§3.10). Unwinding, when it comes, makes them terminators with
  a cleanup edge.

## Change log

Changes to `ir.vl` after its first commit, one line each, so that the
code generators' agent (0.26.1) sees what moved.

- 0.26.0: first version.
- 0.26.0 (step 2): RV_BINARY and RV_UNARY carry the operator (BO_*,
  UO_*) in d and the AST node in e; an AK_BOUNDS assert has two operands
  (index, length); RV_SLICE checks its bounds; struct_closure.
- 0.26.0 (step 2): the copy rule also allows a copy whose root is a
  BORROWED local (a borrowed copy passed on).
- 0.26.0 (step 3): a DS_FLAG drop stays one statement, `drop(P) [flag
  _f]` (d the flag, a LF_FLAG bool local): the code generators branch on
  it. A DS_OPEN drop is followed by its parts' drops, each decided (an
  enum's behind a switch on its discriminant, new blocks). A drop whose
  place has no move path (through `*` or an index) is DS_KEPT as written.
  A drop's e is the AST local it drops (-1 for an open drop's parts).
  PJ_CONST of an owned array is a move path (`f()[1]` moved out).
- 0.26.1 (R1): kept bodies, keep.vl (`keep_body`, `load_body`,
  `free_body`, `has_kept`); `load_body` restores B_FN, B_NODE, B_PARAMS
  and every `P_*` table, no block open.
- 0.26.1 (R2): drop shims, shim.vl (`shim_of`, `shim_count`,
  `shim_type`, `build_shim`, `shim_fn_symbol`); ir.vl's `B_SHIM` (the
  shim held, -1 for a function's body; B_FN is -1 for a shim).
- 0.26.1 (step 6, front half): `drop_edge_count(f)`, `drop_edge(f, i)`
  (mod.vl): the `Drop::drop` functions f's kept and flagged drops call
  through their shims (shim.vl: `drop_fn_count(t)`, `drop_fn_at(t, i)`),
  edges of the effect graph (front/effects/infer.vl: node_locals).
- 0.26.1 (step 9): a drop's `node` is where it runs: the scope's node (a
  block, a statement, a loop, an arm, the body) or the exit's (`return`,
  `break`, `continue`); print.vl's `drop_pos` gives its position (a
  block's `}`). `query drops FILE:LINE` (tools/query/drops.vl) lists them.
- 0.26.1 (step 2, the builder's cost): an open block's `len` is set when
  it is terminated (`close_block`), not by each `emit`; read a block's
  range only once it has its terminator. Outside `--emit-places` and
  `--verify-places`, StorageLive and StorageDead are made only for the
  locals whose type has glue (the ones elaboration reads them for; about
  half of all statements were the scalars' markers): a code generator
  must not rely on a scalar local having them (`--places-lean` makes the
  printed IR so too). Operands are written straight to `P_OPS` (no
  staging), so `P_OPS` may hold words no statement points to; read
  operands only through a statement's `ops` and `nops`.
- 0.26.1 (shims as functions): with kept bodies and drops on, each shim
  is a function of the `FNS` table after the program's (`shim_fn(id)`,
  `drop_shim_fn(t)`, `is_shim_fn(f)`; `self: &mut T`, unit): not a
  program item, so a code generator lowers them in a loop over
  `shim_count()`, `lower_places_function(cx, fn_node(shim_fn(id)),
  shim_fn(id))`. A generic `Drop::drop` a shim calls is instantiated at
  check time when no instance exists yet (`make_drop_instance`, then
  front/check's `check_queued_instances`), so every shim has its callee.
- 0.26.1 (R3): a sink closure's body that moves a flagged capture out of
  its env writes `(*_1).k_flag = const false` after the move
  (build.vl `live_writes`), as the own pass does.
- 0.26.1: a union literal's aggregate has a part per field of the union,
  `const ()` for each field not written.
- 0.26.1 (R4): a match whose arms are values (no guard; an integer, or
  an enum without the null niche whose variants' fields only bind; a
  wildcard or binding only last; 6 values, or 4 for an enum with
  fields) is one `switch` with a target per value (build.vl
  `switch_cases`, `lower_match_switch`, as middle/lower/matching.vl's).
  An enum's arm with several values is reached through a block per
  value, a goto to the arm's: a code generator may see a switch with
  many targets wherever a match was.
- 0.26.1 (R5): a statement temporary (`__own_tv`) drops at the end of
  the scope of its prelude defer (TEMP_SCOPES, temp_scope, schedule_in),
  not at the end of the hidden `let` that holds an operator's operand or
  an f-string's hole; it has no storage markers (the own pass's lives in
  the body's frame).
- 0.26.1 (R6): an open drop's part flags are made when the drop is
  decided (elab.vl open_flags), so the rewrite clears them at entry and
  writes them at each init and move.
- 0.26.1 (R7): a sink closure's move of a flagged capture first reads
  the flag; moved already, `intrinsic panic` with the own pass's message.
- 0.26.1 (R8): a call temporary is borrowed (not dropped) for a
  parametric copy (`second<T>(p: *T) -> T { p[1] }`), as the own pass's
  fresh (build.vl copied_call).
- 0.26.1: `--places-diff` also checks where each drop runs and its flag
  (diff.vl check_drops): a kept or flagged drop followed, on a path that
  does not make the place again, by a read of it or of a borrowed copy or
  a reference made from it (`'x' used after its drop`), and a flagged drop
  reached with its flag unwritten or a flag never set true (`'x' under a
  flag never set`). Before R5 and R6 it found 6,707 and 652 such lines
  over tests/run (196 sources); after, one (an XFAIL case's `v = v`
  through an inout).

## `--places-diff`: the differences left

Over compiler/src (142 locals compared) and every tests/run source
(30,699 locals), after step 3a: none in compiler/src; 5 in tests/run,
each where the IR is the more precise of the two (the own pass flags a
drop the IR proves never runs):

| case | local | own | IR | why |
|---|---|---|---|---|
| sem_own_match_arm_return `f` | `e` | under a flag | removed | `match e { E::A(d) => return .., E::N => {} }`: past the match `e` is `E::N`, which has nothing to drop |
| sem_own_pat_arms_matrix `m_A_whole`, `m_B_whole`, `m_C_whole`, `m_N_whole` | `e` | under a flag | removed | every arm moves `e` or its owned payload: nothing is left at the end |

Differences of form, not listed by `--places-diff` (diff.vl):

- a flag beside parts apart: the own pass flags a whole enum whose
  payload moved on some arms; the IR opens it and flags the payload;
- a local the IR owns with no drop at all: no exit reaches it (every
  path ends in a `!` call, `worker_exit`, `exit`); the own pass's
  placeholder never runs either;
- a statement temporary (`__own_tv`): the own pass drops it under its
  run-time flag (`__own_tf`), with no placeholder to compare;
- a requires call's argument `?aN`: the own pass drops the statement
  temporary it holds, the IR the `?aN` it was moved into;
- the IR's kept-at-some-exits, removed-at-others is the own pass's flag.

The move-out backstop reports nothing over the same sources. As the own
pass's move_out, it does not look at std's modules that move by bits
(`std_moves_bits`), nor at a raw pointer's `p[i]`.
