# The places IR (0.26.0 and 0.26.1, Phase 1(a))

A design document, 2026-10-30, for row (a) of
[rust-surface-plan.md](rust-surface-plan.md) §1 (below, "the plan"). It
says what the places IR is, where it runs, what it takes from the own
pass, what it costs, how it is tested and in which commits it lands.
Nothing in it has been implemented. Every number below was measured with
the 0.25.5 compiler, `target/tools/volec`, on aarch64-macos, on
2026-10-30 at a load average of 2 to 3.5.

## 0. The goal and the bar

The places IR is a MIR-like form of every checked function body: typed
places with projections, explicit temporaries, borrows as rvalues,
storage markers, and drops with drop flags. Moves and drops are
elaborated per place on it. It runs at `check`, at -O0 and at -O1+. It
lands in two point releases:

- **0.26.0** (one agent): the IR's definition, its builder and its drop
  elaboration (steps 1–3, §8), on by default at `check` and at every build
  level, with `--no-places` to turn it off for one release. The own pass's
  drops are still the ones that run. The IR is checked against them by
  `--places-diff` (§7.3), and it adds the move-out backstop.
- **0.26.1** (two agents): both code generators read the IR, and the own
  pass's drop code is deleted (steps 4–8).

In 0.26.2 effect inference moves onto it (plan §9.2); in 0.27 the borrow
checker, NLL and then the location-sensitive solve, runs on it (plan §4).

The bar for 0.26.0, with the corrections of §11:

| # | bar | how it is shown |
|---|---|---|
| 1 | the own audit's 19 SOUNDNESS findings are decided the same way by the IR | each finding gets a `places_` case that shows its drops in the IR with `// PLACES:` lines; `--places-diff` lists no difference on its probes (§7.2) |
| 2 | the post-audit drop family (`793e4b8c`, with `51075d9c` and `ea70255c`) is decided the same way by the IR | `--places-diff` over the sweeps `own_arg_temp_sweep_*` (9 files), `own_arg_temp_try_outer`, `own_arg_temp_requires`, `own_assign_temp_drop_order` |
| 3 | the IR is on by default and adds no unaudited error | `--verify-places` clean, and the move-out backstop silent, over compiler/src and every tests/run source, before the default changes (§3.8) |
| 4 | the IR's share of the 0.26.0 budget: `check` of the compiler within 1.10x of 0.25.5's | 5,157M instructions retired, 288 ms, by `tests/compile_cost.sh` after steps 2a and 3 (§6); over it, the IR runs only under `--places` |

The bar for 0.26.1:

| # | bar | how it is shown |
|---|---|---|
| 5 | the findings and the family pass on the IR's drops | each finding's probes (§7.2) and the sweeps pass at -O0 and -O2 with `--check-alloc` |
| 6 | the own pass's drop code is deleted | `front/own/drops.vl` and `glue.vl` gone; `query refs own::drops --count` is 0 outside the kept predicates (§5) |

`e1bbdd94` is not a drop family; §11 says where its tests go.

## 1. What exists today

### 1.1 The pipeline

`gen0/gen/mod.vl: compile_program` (lines 232–381) drives every level.
`check_program` (`front/check/mod.vl:522–616`) is the front end; `volec
check` stops after it.

| phase | code | `check` | -O0 | -O1+ |
|---|---|---|---|---|
| read, lex, modules, C imports | `base`, `front/lexer`, `front/modules`, `front/cpp`, `front/cimport` | yes | yes | yes |
| parse | `front/parser` | yes | yes | yes |
| declarations, then bodies; instances as they are made (`INST_QUEUE`) | `front/check`, `front/generics` | yes | yes | yes |
| drop placeholders, during body checking | `front/own/drops.vl`, called from `check/body.vl`, `check/iterate.vl`, `patterns`, `closures`, `check/try_op.vl`, `check/check_mode.vl` (14 call sites) | yes | yes | yes |
| effects, inferred on the AST | `front/effects/infer.vl: infer_effects` | yes | when wanted (`EFFECTS_WANTED`) | yes |
| threads, features, contracts, distinct kinds; `exit_if_errors` | `front/threads`, `front/features`, `front/contracts` | yes | yes | yes |
| the own pass | `front/own/mod.vl: check_own` | yes | yes | yes |
| distinct types erased | `erase_program_types` | no (tools keep them) | yes | yes |
| AST to SSA IR | `middle/lower/mod.vl: lower_program` | no | no | yes |
| optimizer, isel, regalloc, emission | `middle/opt.vl`, `back/` | no | no | yes |
| code from the checked AST | `gen0/gen/mod.vl: gen_function` | no | yes | no |

The typed AST becomes the middle IR in one place: `lower_program`, called
only `if OPT_LEVEL > 0 || EMIT_IR` (compile_program). At -O0 the 0.1 code
generator walks the checked AST itself (`for item in kids(program) {
gen_function(cx, item) }`). The two levels share only the front end
(`gen0/README.md`: "so it is the oracle they are tested against").

Before code generation the checker has already desugared most of the
language into a small core: `for` into a block with `__for_seq` and a
counted loop or a `next()` match (`check/iterate.vl:6–21`), `?` into `{
let ?try = e; match ?try { .. } }`, a call with a `requires` clause into
`{ let ?a0 = arg; f$pre(..); f(?a0, ..) }`
(`contracts/desugar.vl: requires_call`), closures into env structs,
contracts into functions, derives into impls. This is why
`middle/lower` is 3,131 lines and `gen0/gen` 2,844.

### 1.2 Where drops, moves and temporaries are decided

All of it is decided on the AST, in two halves, and written back into
the AST as ordinary nodes that both code generators already lower:

1. **While bodies are checked** (`drops.vl:1–33`), the checker calls
   drops.vl to place an implicit `defer` (`DEFER_IMPLICIT`) after each
   `let` of a type with glue, one per by-value parameter and one per
   owned binding of a match arm; to bind a discarded owned temporary to a
   hidden local; to rewrite `p = rhs` on an owned place into `{ let
   __own_new = rhs; { let =o = p; p = __own_new; } }`; and to make the
   temporaries of a statement hidden `let`s (`visit_temps`, `temp_make`,
   `hold_args`). Drop glue is untyped AST written per drop site
   (`glue.vl`), then checked where it stands.
2. **In the own pass**, the walk records each implicit defer's state at
   every exit (`moves.vl` → `drops::drop_state`), and `finish_drops`
   (`drops.vl:1463`) empties a defer moved on every exit, puts one moved
   on some exits under a hidden `let mut __df = true;` flag, and keeps the
   rest.

Both back ends then lower `defer` on every exit (`middle/lower/mod.vl:
lower_defers`, gen0 the same), so neither has drop logic of its own.
Temporary lifetime extension is decided by type: a `let` whose
initializer has a view type keeps that statement's temporaries to the end
of the block (`drops::after_stmt`, `is_view_type(NODES[init].ty)`).
Bindings that borrow (a `for` element, a match through a reference, the
items of a borrowing iterator, the copying getters) are marked by
`BYREF`, `MATCH_BYREF`, `borrowed_call`, `fresh` and `parametric_copy`:
they are bit copies of an owned value that must not be dropped. Drops are
placed only under `--values=error` (`drops_on`), the default.

Every SOUNDNESS finding of the audit, and every commit of the post-audit
family, was a hole in this AST bookkeeping: a desugared block
`visit_temps` did not enter (`793e4b8c`: `?`; `51075d9c`: a requires
call), a unit the assignment desugaring split wrongly (`ea70255c`), a
pattern form that skipped a part (S8), a construct with no placeholder
(S9–S19).

### 1.3 The middle IR

`middle/ir/mod.vl:1–55` defines it: per function a CFG of basic blocks;
instructions are SSA values of *scalar* type (the integers, f32, f64,
bool); "pointers, function values and the addresses of compound values
(structs, tuples, arrays) are TY_U64"; memory is explicit (`SLOT`,
`LOAD`, `STORE`, `COPY`); calls carry ABI detail (result pointers,
`ARGTY`, variadic pieces). Instructions form doubly linked lists for
in-place rewriting. Lowering builds SSA on the fly (Braun et al.,
`middle/lower/mod.vl:1–15`). At -O1 on compiler/src the lowered tables
take 219 MB (`--time-passes`).

It has no places, no source types of aggregates, no moves and no scopes:
everything a drop elaborator or a borrow checker needs is erased before
it exists.

### 1.4 The own pass, by part

`front/own/` is 13,783 lines (`wc -l`), in `check_own`
(`own/mod.vl:91`) after the effects, reusing their SCCs:

| part | files | lines | computes |
|---|---|---|---|
| kinds | `kinds.vl` | 433 | plain, owned, view, needs-drop, level 2; `param_mode` |
| state | `state.vl` | 787 | places, bitsets, origins, slots, pending arguments |
| the walk | `walk.vl`, `fast.vl` | 2,395 | the evaluation-order walk and its events; the fast path |
| moves | `moves.vl` | 1,390 | `own.moved`, `own.move_out`, `own.partial`, `own.drop_call`; records drop states |
| drops | `drops.vl`, `glue.vl` | 3,313 | placeholders, temporaries, the assignment desugaring, glue, flags, `finish_drops` |
| views | `views.vl`, `calls.vl` | 2,721 | origins, exclusivity (`own.conflict`), `own.escape`, two-phase receivers, statics |
| summaries | `summary.vl`, `infer.vl` | 2,129 | view summaries, `#[views]`/`#[stores]` (66 pins in std), SCC fixpoints, the type filter, casts (`cast_mask`) |
| tools | `diag.vl`, `observe.vl`, `mod.vl` | 615 | codes, `query own`, `--values`, `--print-views` |

### 1.5 The cost today

`check` of compiler/src as the gate's compile-cost row measures it
(`tests/compile_cost.sh`: a copy of compiler/src without compiler/std,
the fewest instructions of the runs): `VOLE_CACHE=off /usr/bin/time -l
target/tools/volec check src/main.vl` five times, and the same with
`--time-passes` three times.

| measure | 0.25.5 |
|---|---|
| instructions retired, fewest of 5 | **4,688M** (4,688–4,711M) |
| wall | 0.27 s |
| `--time-passes`, 3 runs | read, lex, modules 61 ms; parse 31; check 123–124; effects 8.4; own 38; **total 262 ms** |
| the same with `--values=off` (no own pass, no drops) | 3,654M instructions; check 111 ms; total 211 ms |
| RSS | 513 MB |

`check --time-passes=instructions` is refused (`check.usage`), so the
phase split in instructions comes from a build, whose front end is the
same code: `VOLE_CACHE=off target/tools/volec --no-cache -j1 -O0|-O1
[--values=off] --time-passes=instructions -c src/main.vl -o X.o`.

| phase | -O0 | -O0, `--values=off` | -O1 |
|---|---|---|---|
| check | 1,990.8M | 1,762.6M | 1,990.3M |
| effects | 95.1M | 94.9M | 94.9M |
| own | 807.7M | — | 807.1M |
| lower to SSA | — | — | 1,343.2M (103.5 ms) |
| gen0's code (`register allocation and emission`) | 2,012.1M | 2,015.5M | — |
| total | 8,896M | 7,870M | 19,699M |

So the drop placeholders cost 228M instructions inside `check`
(1,990.8M − 1,762.6M), about 11.5 ms, and the own pass 808M, about 38 ms
(31% of the type checker; plan §0 says 32%). The compiler's own source has
few owned values: its -O0 object is 16,686,952 bytes with drops and
16,649,232 without (0.2%), so on the self-check the elaborator mostly
takes its fast path.

## 2. Decision: a new IR that lowers into the middle IR

The places IR is a new IR, `compiler/src/places/`, that lowers into
`middle/ir` at -O1+ and that gen0 reads at -O0. It is not a first stage
of `middle/ir`:

| | a first stage of `middle/ir` | a new IR (chosen) |
|---|---|---|
| types | scalars only; aggregates are `TY_U64` addresses (`ir/mod.vl:5–10`) | the checker's types, on every local and place |
| places | none: loads and stores through addresses | locals with projections, what move paths and loans are made of |
| form | SSA, built on the fly | not SSA: a place is assigned many times; borrowck needs places, not virtual registers (the proposal, §2) |
| tables | program-wide, 219 MB at -O1, linked lists for rewriting | per function, flat arrays, discardable at `check` |
| when built | only `OPT_LEVEL > 0 \|\| EMIT_IR` | at every level and at `check` |
| ABI detail | result pointers, `ARGTY`, pieces, variadics | none: calls take operands |

Making `middle/ir` carry types and places would slow the optimizer, whose
passes assume scalar SSA, and would bring codegen detail into `check`.
Rust has the same split for the same reasons (MIR, then LLVM IR).

Both code generators read the IR, in place of the AST:
`middle/lower` becomes places-to-SSA (a CFG to SSA is Braun's algorithm
as today, without the structured-control-flow bookkeeping), and gen0's
statement and expression walk becomes a walk over IR statements through
the same target interface (`gen0/target.vl`, unchanged). This is what
lets the own pass's drop code go: the alternative, writing the IR's
decisions back into the AST as defers and hidden lets, keeps the AST
bookkeeping that every finding came from, and is thrown away when the
code generators move anyway (plan §4: "the one IR for moves, drops,
borrows, effects and lowering"). -O0 through `middle/ir` and `back`
without the optimizer was rejected: at -O1 lowering, isel and regalloc
cost 1,343M + 1,222M + 4,744M against gen0's 2,012M (§1.5), 3.6x.

## 3. The IR

### 3.1 Bodies and locals

One `Body` per checked function: items, instances (each instance is a
copy of its template's AST, checked with its parameters bound, so every
type in a body is concrete), closures and contract functions. A body
holds its locals, its interned projections, its statements, its blocks
and a span (an AST node) per statement.

| local | what | notes |
|---|---|---|
| `_0` | the return place | the result is assigned to it; `return` jumps to the return block |
| `_1.._n` | the parameters, in order | the type follows the convention (§3.11) |
| user locals | one per `LOCALS` entry of the body | name and span from the AST |
| temporaries | one per value that is not written straight into a place | their scope is a statement or, by extension, a block (§3.7) |
| drop flags | `bool`, made by elaboration | never user-visible |

A local's flags: `MUT` (a `var`: may be assigned again) and `BORROWED`
(a bit copy of a value owned elsewhere, §3.11: never dropped, never
moved out of).

### 3.2 Places and projections

A place is a local and an interned projection list (0: none). Lists are
interned per body, so a place is two words and equal places are equal
numbers.

| projection | meaning |
|---|---|
| `.f` | field f of a struct; element k of a tuple |
| `*` | through a reference or a raw pointer |
| `[i]` | an element of an array, a slice or a Vec's buffer, indexed by local `i`, after its bounds check |
| `[k]` | the same with a constant index |
| `as V` | the payload of enum variant V, only where a `switch` on `discriminant P` dominates it (the verifier checks the dominance, which 0.27's match lowering relies on) |
| `.f` of a union | a union's field (`union_decl`, grammar.md:102): no drop and no move path; a read is a `copy`, unsafe as today |

A static is a place root of its own (`static S`), never dropped. A Vec
element is `(*buf)[i]` once the indexing builtin has given its buffer.

### 3.3 Operands and rvalues

An operand is `copy P`, `move P` or a constant. A `copy` of a place whose
type needs drop is valid only as the initializer of a `BORROWED` local or
a `BORROWED` temporary: the source is an ordinary owned place, the
destination is the borrowed copy (`x = copy (*_buf)[_i]`, a `for`
element; `x = copy (_s as Some).0`, a match through a reference), or
when its root is itself a `BORROWED` local (a borrowed copy of a borrowed
copy: a closure's borrowed item passed on, `g(acc, e.1)`). A `BORROWED`
local is never the source of a `move`. The verifier checks
both, under `--values=error` (§4): any other copy of a needs-drop place is
the shape of S6, a bit copy of an owned iterator.

A borrow's place may contain `*`: `&(*_1).f` reborrows through the
reference `_1`. NLL's supporting-prefixes rule applies to it in 0.27: a
reborrow through a `&mut` does not end the outer loan's region.

| rvalue | meaning |
|---|---|
| `use op` | the operand |
| `&P`, `&mut P`, `&mut2 P`, `&raw P` | a borrow: shared, exclusive, two-phase exclusive (a reservation activated at its first use), raw address (`&x` to a `*T`). A region word is reserved on each, 0 until 0.27 |
| `op1 ⊕ op2`, `⊖ op` | the checker's arithmetic and comparisons |
| `cast op as T` | the checker's conversions |
| `discriminant P` | an enum's tag |
| `aggregate K (ops)` | a struct, tuple, array, enum variant or closure env, from moved or copied operands |
| `repeat op; n` | `[x; n]` |
| `len P` | an array's or a slice's length |

### 3.4 Statements

| statement | meaning |
|---|---|
| `P = rvalue` | assignment; initializes P |
| `P = call f(ops)` | a call: `f` a function (FNS), a function value, or a C symbol; its operands evaluated, then the call, then P written. A call is a statement because nothing unwinds (§3.10) |
| `P = intrinsic k(ops)` | vectors, atomics, `std::arch` intrinsics, `needs_drop` |
| `drop(P)` | run P's drop glue; P is uninitialized after it |
| `assert(op, kind)` | a run-time check (bounds, `as E`, a `requires` call's result): exit 101 when false |
| `StorageLive(l)`, `StorageDead(l)` | the local's storage begins and ends (§3.7) |
| `mention P` | a place read without a value: `let _ = x`, a scrutinee no arm reads; borrowck's fake read |
| `nop` | removed statements |

### 3.5 Terminators

| terminator | meaning |
|---|---|
| `goto b` | with one bit: a loop's back edge of an uncounted loop (`while`, `loop`), for 0.26.2's `diverge` |
| `switch op [v: b, .., otherwise: b]` | on an integer, a bool or a discriminant |
| `return` | `_0` is the result |
| `unreachable` | after a call that returns `!`, a `panic`, an `exit` |

There is no `drop` or `call` terminator and no cleanup block. 0.27 adds
`false_edge` for match guards (a borrow taken in a guard must conflict
with the arms after it); its number is reserved.

### 3.6 Locations and points

A body's statements live in one array; a block is a range of it and its
terminator is the slot after the range. A location is that index. A
point is `2 × location` (the start) or `2 × location + 1` (the mid),
which is the numbering NLL's liveness and the location-sensitive solve
use: dense, so a set of points is a bitset. Elaboration splits a block
by moving its tail to a new range at the array's end; points are
numbered after it. The verifier checks that every block ends in one terminator and
that predecessor lists match.

### 3.7 Scopes, temporaries, storage

The builder keeps a scope stack, as rustc's MIR builder does. A scope is
a block, a loop body, a match arm, a statement (its temporaries) or a
function body. Each entry of a scope is one of: drop local l, storage of
l ends, run defer d. Leaving a scope by any edge (the end, `break`,
`continue`, `return`, a `?`'s return) emits the entries of every scope
it leaves, innermost first, each in reverse order of registration. So
drops and `defer`s interleave as value-semantics.md §2.2 says ("as if
each owned `let` registered one"), and `defer` bodies are lowered on each
exit as both code generators do today.

The rules for temporaries are vole's 0.25 rules, unchanged
(conventions.md §2.2, "Temporaries"):

- a temporary lives to the end of its full statement and drops there, in
  reverse order of creation, unless moved;
- a `let` whose initializer has a view type keeps its statement's
  temporaries to the end of the enclosing block (today's
  `drops::after_stmt`);
- on an early exit every temporary already initialized drops once;
- the checker's desugared blocks (`?`'s `{ let ?try = e; match .. }`,
  `requires_call`'s `{ let ?a0 = arg; .. }`) are *transparent*: their
  `let`s are temporaries of the enclosing statement. The checker marks
  these blocks with a node flag where it makes them; the builder never
  guesses from names. This is what `793e4b8c` and `51075d9c` fixed by
  hand, one desugaring at a time.

`StorageLive(l)` comes at a `let` (or a temporary's first
initialization), `StorageDead(l)` on every edge out of its scope, after
its drop. The code generators may ignore them in 0.26 (one frame slot per
local, as today); borrowck needs them in 0.27 (a loan of a dead local is
an error, `StorageDead` kills its loans).

### 3.8 Moves, drops and drop flags

The builder emits a `drop(l)` for every needs-drop local and temporary on
every scope exit, without asking whether it moved, and for an owned
assignment `P = v` it emits `tmp = v; drop(P); P = move tmp` (the right
side, then the old value, then the write; the right side's temporaries
after it, at the statement's end: `ea70255c`'s order). Elaboration then
decides each drop, as rustc's drop elaboration does:

1. **Move paths.** A tree per body of the places that are moved, assigned
   or dropped, rooted at locals, with children for fields and variant
   payloads. A move of `P` is a `move P` operand; an initialization is an
   assignment to P (children included).
2. **Dataflow.** Maybe-initialized and maybe-uninitialized, forward,
   gen/kill bitsets per block over the move paths, iterated to a fixed
   point in reverse postorder. With 64 move paths or fewer, a set is one
   word.
3. **Each `drop(P)`** is then one of:

   | state of P's path at the drop | result |
   |---|---|
   | uninitialized on every path | removed |
   | initialized on every path, no child moved | kept |
   | initialized on some paths | kept under a flag: `switch flag [0: skip, otherwise: drop]` |
   | some child moved | *open*: each child dropped by these rules; an enum switches on its discriminant, per variant whose payload has a moved path |

4. **Flags.** A path that needs one gets a `bool` local, set false at
   entry, true after each initialization, false after each move.

A place with a `*` or `[i]` projection has no move path, as in rustc.
Its `drop` is kept as written (the place is assumed initialized), and the
table above does not apply to it: `drop(*_1)` before an inout assignment
and `drop((*_b)[_i])` before a write through an index are always kept
(§3.12).

Moves out of an `[i]` element, through `*` of a reference, out of a
static or out of a `BORROWED` local are errors, which the own pass
reports today (`own.move_out`). The IR checks for them after the own pass
and reports `own.move_out` for any the own pass let through: a backstop,
so that a missing own rule (S1–S5) is an error, not a double free. The
backstop is silent over compiler/src and every tests/run source before
the IR is on by default: each report it makes there is audited first (a
missing own rule, fixed in the own pass, or a bug of the IR), so the
default ships no new unaudited error.

The fast path: a body with no needs-drop local and no needs-drop
temporary skips move paths and elaboration; it gets only storage markers.

### 3.9 Drop glue

`drop(P)` of type T runs T's glue, made once per type as a body of its
own, a drop shim (rustc's `drop_in_place::<T>`), from the type rather
than from AST: T's `Drop::drop(&mut P)` if it has one, then its fields'
drops in declaration order; an enum's a `switch` on its discriminant; an
array's a counted loop; std's containers their `Drop` only; a closure's
the owned values its env holds. `needs_drop::<T>()` and `has_glue(t)`
move with it (`places/glue.vl`). At -O0 a drop is a call of the shim; at
-O2 the inliner takes it, as it takes today's inline glue. Elaboration
opens a drop (§3.8) without a shim when a child has moved. Shims are not
program items, so 0.26.1's step 5 adds the shim list to gen0's -O0 loop
(`compile_program`'s `for item in kids(program)`) and to the code
cache's function set (`back/codecache`).

### 3.10 Panics do not unwind

A panic prints its message and exits with 101 (`grammar.md`:
"`panic(message: [u8]) -> !` prints the message on stderr and exits";
std's `panic`: "exits with 101"); drops do not run on a panic or an
`exit` (value-semantics.md §2.2). So the IR has no unwind edges and no
cleanup blocks: a call is a statement, a check is `assert`, and the drop
tables of rustc's unwind paths do not exist. This is the plan's proposed
decision 18, "a panic exits with 101, with no unwinding" (§10, question
6, has its consequences). If vole ever unwinds, `call` and `drop` become
terminators with a cleanup edge, a mechanical change.

### 3.11 MVS onto the IR, under 0.26

The IR's shape is the one 0.27's rust edition will have, so the
translation `fix --edition rust` makes (plan §6) changes the surface, not
the IR:

| MVS today | IR in 0.26 | the rust edition |
|---|---|---|
| `x: T` (let) parameter, T not compound | `_1: T`, copied in | `x: T`, Copy |
| `x: T` (let) parameter, T compound (`is_compound`, the ABI's pointer) | `_1: &T`; uses are `(*_1).f` | `x: &T` |
| `inout x: T` | `_1: &mut T`; `x = v` is `drop(*_1); (*_1) = move v` | `x: &mut T` |
| `sink x: T` | `_1: T`, owned: dropped at exit unless moved | `x: T` |
| `let self`, `inout self`, `sink self` | as the three rows above | `&self`, `&mut self`, `self` |
| `f(&x)` to an inout parameter | `_t = &mut x`; a receiver's is `&mut2 x`, taken before the other arguments | `f(&mut x)` |
| a place or a value given to a let parameter | `_t = &x` (a temporary first when it is a value) | `f(&x)` |
| `let x`, `var x` | a local, `MUT` for `var` | `let x`, `let mut x` |
| a view: `[T]`, `str`, a view struct | a value with no drop; its origins are the own pass's | `&[T]`, `&str`, `S<'a>` |
| `&mut [T]` | a value with no drop, moved | `&mut [T]` |
| `*T` | a value with no drop; `*p` a projection (unsafe) | `*const T`, `*mut T` |
| a borrowed copy: a `for` element of a slice or Vec, a match through a reference, a borrowing iterator's items, a copying getter's result | a local flagged `BORROWED` (today's `BYREF`, `MATCH_BYREF`, `borrowed_call`, `fresh`, `parametric_copy`) | `&T` |
| a closure's captures | the env is the closure body's `_1`; a by-reference capture is `aggregate closure(&x, ..)` in the creating body and `(*_1).f` in the closure's | `\|..\| ..` with captures |
| `defer` | lowered on every exit of its scope | (kept: vole's) |

Under 0.26 the IR checks nothing about views or exclusivity: the own
pass does, on the AST, until 0.28 (§5). The IR elaborates drops, checks
the move-out backstop, and from 0.26.2 infers effects. 0.27 adds region
variables (the reserved word on `&` rvalues, and in local types),
`false_edge`, liveness over points, constraint generation and two-phase
activation (the first use of a `&mut2` temporary); none of it changes
the statement set.

### 3.12 An example

`two(mk(1, gpa), g()?)`, with `two(a: sink D, b: i64)`: S12, whose first
argument leaked when `?` returned. `--emit-places`, before elaboration:

```
    let _2: D                  // temporary: two's first argument
    let _3: Result<i64, E>     // ?try: a temporary of the statement (transparent block)
    bb0:
        StorageLive(_2); _2 = call mk(const 1, copy _1)       // main.vl:9:9
        StorageLive(_3); _3 = call g()                        // main.vl:9:20
        _4 = discriminant _3; switch _4 [0: bb1, otherwise: bb2]
    bb1:                                                      // Ok(v)
        _5 = call two(move _2, copy (_3 as Ok).0)             // main.vl:9:5
        drop(_3); drop(_2); StorageDead(_3); StorageDead(_2)  // the statement's end
    bb2:                                                      // Err(e) => return
        _0 = aggregate Result::Err(move (_3 as Err).0)
        drop(_3); drop(_2); StorageDead(_3); StorageDead(_2); goto bb_ret
```

Elaboration removes bb1's `drop(_2)` (moved into the call) and bb2's
`drop(_3)` (its one owned part moved), and keeps bb2's `drop(_2)`: the
early exit drops the first argument. No flag is needed.

Two drops elaboration never decides (§3.8), with `inout x: D` as `_1:
&mut D`, and `_b` the buffer that indexing a `Vec<D>` gives (§3.2):

```
    x = mk(2, gpa)          drop(*_1); (*_1) = move _4            // kept as written
    b[i] = mk(3, gpa)       drop((*_b)[_i]); (*_b)[_i] = move _5   // S13: kept as written
```

## 4. Where it runs

**In 0.26.0** the IR runs beside the own pass's drops, which are still the
ones the code generators run:

```
check_program:
  declarations; bodies type-checked    with the drop placeholders, as today
  exit_if_errors                       (QUERY: functions with errors get no body)
  places: build, elaborate             per function, places/ (not under --no-places)
  infer_effects, check_effects         on the AST, as today: they see the placeholders
  threads, features, contracts, distinct kinds; exit_if_errors
  erase_view_distincts; check_own      as today, with finish_drops
  places: the move-out backstop        then --places-diff, when asked (§7.3); exit_if_errors
compile_program:                       unchanged: both code generators read the AST
```

The builder reads the AST with the checker's drop nodes in it. It skips
the `DEFER_IMPLICIT` defers (the own pass decides them later, in
`finish_drops`, and makes its flags then), reads a hidden
temporary `let` (`temp_make`, `hold_args`) as the temporary it stands for,
and reads the assignment desugaring (`{ let __own_new = rhs; { let =o = p;
p = __own_new; } }`) as the one assignment `P = v` of §3.8, so that its
drops are the IR's own and `--places-diff` compares two independent
decisions.

The IR is on by default at `check` and at every build level, so the suite
and the fixpoint run it; `--no-places` turns it off, for 0.26.0 only.
`--time-passes` shows `places (build)` and `places (elaborate)` at every
level, -O0 included: `EFFECTS_WANTED` is false at -O0 without
declarations (check/mod.vl:583), so there the IR, not the effects, is the
first whole-program pass after the bodies, and its cost is inside the -O0
row (§6). If the IR misses its share of the budget (§6), it runs only
under `--places`, and the suite and the fixpoint pass that flag.

**From 0.26.1** the placeholders are gone and the code generators read the
IR:

```
check_program:
  declarations; bodies type-checked (no drop placeholders)
  exit_if_errors                       (QUERY: functions with errors get no body)
  places: build, elaborate             per function, places/
  infer_effects, check_effects         0.26.1: plus the IR's drop edges; 0.26.2: on the IR
  threads, features, contracts, distinct kinds; exit_if_errors
  erase_view_distincts; check_own      views, moves' errors; no drops
  places: the move-out backstop; exit_if_errors
compile_program:
  -O0:  gen0 walks each body's IR      (replaces gen_function's AST walk)
  -O1+: middle/lower: IR to SSA        (replaces lower_program's AST walk)
```

At `check` each body is freed after elaboration (after borrowck in
0.27), keeping its drop edges (and 0.26.2's effect facts); at a build
the bodies are kept until each function is generated. The IR runs
before effect inference so that effects see drops: today the
placeholders exist "before effects are inferred, so effects see them"
(value-semantics.md §4 step 0). In 0.26.1 the AST walk of
`front/effects/infer.vl` gains one edge per `drop` of type T to T's shim,
and the shim's edges to `Drop::drop` and its fields' shims; the call
graph `query calls` and the code cache's hash use the same edges, so the
transcripts that reach Vec's drop (`caf0f513`) keep their counts. In
0.26.2 the inference itself moves onto the IR (plan §9.2). `check_own`
still runs after the effects and reuses their SCCs (own/mod.vl:91, §1.4);
this order keeps that.

Distinct types are erased after the IR is built: the code generators map
a body's types through the erasure as they read them.

**`--values`.** The 0.25 rule stays in 0.26: drops are placed only under
`--values=error` (`drops_on`, the default). Under `error` elaboration
keeps its drops and the verifier applies the `copy` rule (§3.3). Under
`warn`, `report` and `off` the IR is still built, with its storage
markers; every `drop` is removed, and neither the `copy` rule nor the
move-out backstop runs. Ten cases in tests/run run with `--values=off`
because they need 0.16's semantics with no drops (`checkalloc_double_free`
frees a container twice through two copies of its handle); drops there
would make them fail to compile or free twice, and a program the own pass
only warns about would turn from a leak into a double free. The rule is
revisited in 0.28, when `--values` goes.

## 5. What the own pass loses

| part | 0.26.0 | 0.26.1 | 0.26.2 | 0.28 (the flip) |
|---|---|---|---|---|
| placeholders in the checker (14 call sites), the assignment desugaring, the drop half of temporary making | kept; the builder reads through them (§4) | deleted | | |
| `glue.vl` (551 lines) | kept; the IR's shims are built from types beside it | moved to `places/glue.vl` | | |
| `finish_drops`, flags, `drop_state` recording in `moves.vl` and `walk.vl` | kept; `--places-diff` reads their decisions | deleted | | |
| the borrowed-copy predicates (`borrowed_call`, `fresh`, `parametric_copy`, `BYREF`, `MATCH_BYREF`, `method_word`) | moved out of drops.vl to `front/own/byref.vl` by step 1's first commit (a `refactor move`), so that the builder never imports drops.vl; `borrowed_call`'s one `moves.vl` dependency, `copies_owned_items`, moves with it or is cut; the IR reads them | | | deleted (`&T` items) |
| temporaries as hidden `let`s for the view checks (`own.escape` names a temporary) | kept | kept for views only, if the walk still needs them (§8, step 7) | | deleted |
| kinds | kept | kept; `needs_drop` moves to places | | Copy and Drop traits |
| move errors (`own.moved`, `own.move_out`, `own.partial`, `own.drop_call`) | kept, with the IR's backstop | | | borrowck's (0.27 for rust-edition files) |
| views, exclusivity, `own.escape`, statics, summaries, `#[views]`, `#[stores]`, casts, `query own`, `query views` | kept | | | deleted |
| the effects' SCCs it reuses | kept | kept | from the IR's call graph | |
| `noalias` facts for the optimizer | kept | | | from `&mut T` types |

**Step 7's scope, decided 2026-10-30 (0.26.2): the drop half only.** It
deletes the implicit defers (DEFER_IMPLICIT) and their placement at the
checker's call sites, the statement temporaries' drop flags and pointers
(`__own_tf`, `__own_tp`, their defers), the assignment desugaring,
`finish_drops` and the walk's drop recording, and the tools' reads of them
(fixvalues, refactor extract). It keeps `visit_temps` and the hidden `let`s
of the statement temporaries (`__own_tv`) that the own walk's checks read:
own.escape (an argument's local lent past its arm, hold_args), own.partial
(an element moved out of a temporary array by a run-time index),
own.move_out (a part moved out of a temporary, part_move) and own.moved.
An experiment build with them off fails 26 of the 650 places/own/temp
cases, 15 of them those checks' errors. They go with those checks to the
borrow checker (NLL, 0.27). own.drop_view, reported today from the
parameters' implicit defers (finish_drops), moves onto the IR's drops.
The builder makes its own temporaries and assignment drops already
(0.26.2, places/README.md), and drops the old value at every owned
assignment, as Rust does (0.25's own pass leaked it at an arm's value or
inside an expression).

Nothing of the own pass goes in 0.26.0. About 3,300 lines go in 0.26.1
(`drops.vl` but its predicates, `glue.vl` moved, the drop recording in
the walk), and with them the AST lowerings of function bodies in
`middle/lower` and `gen0/gen` once nothing falls back to them (§8, step
8).

What has no body stays on the AST: static initializers (0.16's statics
that call constant constructors, `check_static_calls`), array constants,
`consteval`, `gen_data` and the `--emit-header` path. Bodies exist only
for functions (§3.1), so the part of the AST expression lowering these
need survives step 8, and step 8's line counts expect it.

## 6. Cost plan

**The budget.** 0.26.0 has one compile-cost budget for its three items
(brief-0260-common.md): `check` of compiler/src at most **1.13x** of
0.25.5's 4,688M (§1.5), **5,297M**, with the gate's 1.15x as the hard
stop. The shares add up to it:

| item | share | `check` of compiler/src at most | headroom |
|---|---|---|---|
| the places IR (this document) | 1.10x | 5,157M, 288 ms | **+469M, +26 ms** |
| `embed wgsl` (on its lower-level path) | 1.025x | | +117M |
| private fields | 1.005x (noise) | | +23M |
| 0.26.0 in all | 1.13x | 5,297M | +609M |

Each item measures with `tests/compile_cost.sh -c target/volec -p PREV -r
5` (no gate lock; the `hello`, `std` and `check` rows), once against
0.25.5's compiler and once against the integration branch's at its base,
and reports its delta against the base. 0.26 as a whole is held to 1.25x
of 0.25.5 (5,860M) by its last point release (plan §1).

**What the IR may cost in 0.26.0.** The own pass's placeholders stay
until 0.26.1's step 7, so the 228M they cost inside `check` (§1.5) does
not come back in 0.26.0. The IR (build, elaboration and backstop
together) may cost at most **469M, about 26 ms**: 35% of today's
AST-to-SSA lowering (1,343M). That is the binding constraint of this
item. `--places-diff` is not charged: it runs only when asked.

| 0.26.0 | target (instructions, compiler/src, `tests/compile_cost.sh`'s method) |
|---|---|
| the builder after step 2a (expressions, calls, control flow) | measured, with its fallback count (the bodies it could not build); the first point at which the fallback rule below is applied |
| the builder, all of step 2 | ≤ 340M |
| elaboration, flags and shims (step 3) | ≤ 100M |
| the move-out backstop | ≤ 25M |
| total at `check`, after step 3 | ≤ 4,688M + 469M = 5,157M |
| the `hello` and `std` rows | reported; the gate's limit is 1.5x, and a change over 1.10x is explained (a hello world now builds IR bodies for every std function it reaches) |
| -O0 build | the IR runs there too: ≤ 8,896M + 469M (1.053x) |
| RSS of `check` | ≤ 1.05x of 513 MB |

**The fallback.** The cost is measured after step 2a and after step 3.
If either is over +469M, the IR runs only under `--places`: the suite and
the fixpoint still run with it on (its cost measured, not charged to every
`check`), `--places-diff` and the backstop keep working there, and the
representation work below moves to 0.26.1.

| 0.26.1 | target |
|---|---|
| total at `check`, after step 7 | ≤ 0.26.0's, with the placeholders' 228M given back; the aim 5,000M (leaving 0.26.2's effects on the IR room: today's AST effects are 95M) |
| -O1 build: IR to SSA in place of AST to SSA | the whole -O1 and -O2 build ≤ 1.10x of the AST lowering's on the same source (2026-10-30: 1,343M was the AST walk's cost then, and the walk has since got cheaper, 1,352M against places' 1,749M at db652f8b; lowering is under 1% of an -O2 build) |
| -O0 build: gen0 from the IR | -O0 total ≤ 1.15x of the AST lowering's on the same source, the gate's measure at the default -j (the user, 2026-10-30, twice: 1.05x was out of reach with every body built at a build; then 1.10x, as the remaining cost is per-statement bookkeeping, not a trim: flipped at 1.137x, step 7 expected to bring it to about 1.11x of today's) |
| RSS of `check` | ≤ 1.05x of 513 MB |

**Measured in 0.26.0 (the fallback applied).** `tests/compile_cost.sh -r
5` with `--places` added, against the same compiler without it (both
checking the branch's compiler/src):

| point | check | IR's share | hello | std |
|---|---|---|---|---|
| after 2a (95% of bodies built) | 5,188M vs 4,755M | +433M | 108.8M vs 85.7M | 1,077M vs 1,052M |
| after 2c (every body) | 5,197M vs 4,769M | +428M (the builder) | 109.2M vs 86.6M | 1,077M vs 1,051M |
| after 3a (elaboration, flags, the backstop's record) | 5,439M vs 4,886M | +554M | 109.4M vs 87.0M | 1,090M vs 1,060M |

So the builder alone is about 430M (340M budgeted) and elaboration with
the backstop about 125M (125M budgeted, 100M + 25M): the IR runs only
under `--places` in 0.26.0, and the representation work below moves to
0.26.1, before default-on. `--time-passes` at 3a: places (build) about 50
ms, places (elaborate) about 5 ms. The profile of the builder is flat:
staging operands (OPSTACK, then copied into P_OPS) and Vec pushes are
about 20% of it. Writing operands straight into P_OPS where the order
allows is the first change to make; estimated 15-20% of the builder.

`hello` at 1.27x with `--places`: the bodies of every std function a
hello world checks (fmt, Buf, the allocator), about 23M. 0.26.1 needs
bodies only for the functions emitted or checked for the program (std's
reached ones built on demand, as the code generators ask), not all of
std's checked ones. *Corrected in 0.26.1:* the 23M was the measuring
wrapper's, not the IR's: `--places` was added by a shell script around
the compiler, and `/usr/bin/time` counts the shell's start (22.7M: the
same wrapper without the flag gives 110.2M against 87.5M). The IR's
own share of `hello` is 0.7M (49 bodies), so nothing is to be won there.

**Measured in 0.26.1, step 2 (the builder's cost).** `check` of
compiler/src (a copy, `VOLE_CACHE=off`, fewest of 3 to 5 runs), the same
compiler with and without `--places`; the builder alone by a build that
builds each body 200 times more (its cost: the difference / 200):

| change | the IR's share | the builder |
|---|---|---|
| R1 and R2 (a230cedc) | +544M | 440M |
| a block's length set at its terminator, not by each `emit` | | |
| operands written straight to `P_OPS` (no OPSTACK staging) | +501M | 395M, then 375M |
| `has_glue` memoized per type | | |
| storage markers only for locals with glue (595,544 of 1,120,167 statements were markers) | +421M | 357M |

With the IR on by default (an uncommitted build, the placeholders still
there), `tests/compile_cost.sh -r 5`: `check` 5,982M against 0.25.5's
5,535M (1.08x, inside the IR's 1.10x before the placeholders' 228M come
back), against the base 1.07x; `hello` 1.03x and `std` 1.00x against
0.25.5. RSS of `check`: 531 MB against 529 MB. Kept bodies at a build
(R1, every body kept, none freed yet): -O0 737 MB against 661 MB, -O2
1,323 MB against 1,246 MB (+77 MB; +117 MB before the lean markers).
The profile left is flat (the statement and operand pushes, `operand`,
`expr_into`, the scope stack, `proj`'s interning), each a few percent.

**The builder's cost at check (0.26.1, later).** At a check no code
generator reads the bodies, and a body without a drop that runs gives
nothing the check uses (no drop, flag or drop edge; the backstop is a
second check of the own pass). So a check builds only the bodies that
may drop (front/own/fast.vl `glue_met`: the own pass gave the function
a drop; with its drops off, any type with glue met in it); a build,
`--verify-places`, `--places-diff` and `--emit-places` build all.
`check` of compiler/src, fewest of 5 runs:

| compiler | without `--places` | with | the IR's share |
|---|---|---|---|
| before (every body built) | 5,557.3M | 6,043.4M | 1.087x |
| a body built when it may drop (by the own pass's drops) | 5,555.0M | 5,594.4M | 1.007x |
| (by the types met alone, the rule left after step 7) | 5,598.0M | 5,863.8M | 1.047x |

700 of 10,872 bodies are built. `--places-noglue-check` builds the
others too and names any with a drop that runs: none over compiler/src
and every tests/run source. The objects of a build under
`VOLE_LOWER=places` (every body built) are byte-identical at -O0 and
-O2. Step 7, which deletes the own pass's drops, needs a rule of its own
to keep this (the types rule alone is 1.047x).

**The builder's cost at a build (0.26.1, later).** The flip's bar is
-O0 total within 1.10x of the AST lowering. A build of compiler/src
(`-c -O0`, `VOLE_LOWER=places`, caches off, fewest of 3):

| step | instructions | objects |
|---|---|---|
| before | 11,776.8M | |
| the check's work skipped at a build (record_body unless a move is suspect or `--places-diff` runs; drop edges and shims only when a drop is kept; live_writes with no flag) | 11,663.8M | identical |
| load_body takes the kept tables instead of copying them | 11,638.9M | identical |
| `a && b`, `a \|\| b` made in their destination (no temporary copied at the end) | 11,382.9M (1.186x) | text 17.85M to 17.70M |
| the AST lowering | 9,601.0M | text 15.22M |

With gen0's accumulator across blocks (35ee705c) the code is at parity
(text 15.19M against 15.23M), and the gap is the work. By phase, `-j1
--time-passes=instructions` on 62828865 (millions):

| phase | AST | places |
|---|---|---|
| check | 2,511 | 2,882 |
| places (build) | | 822 (878 with LF_SSA) |
| places (elaborate) | | 379 |
| register allocation and emission | 2,237 | 3,045 |
| data and output | 2,628 | 2,660 |
| total | 10,351 | 12,774 (1.234x) |

LF_SSA (places/README.md) flags 98,251 of 149,332 temporaries for gen0,
which then need not scan the body for them.

**How it stays cheap.**

- One pass per function over the checked AST, in evaluation order, into
  per-function arrays cleared and reused (no allocation per function at
  `check`); places interned in a small per-body table.
- No SSA, no phis, no use lists: the IR is append-only until elaboration,
  which rewrites drops in place and appends blocks for flags.
- The fast path (§3.8) for bodies with nothing to drop, which on
  compiler/src is most of them (§1.5's object sizes); one-word bitsets up
  to 64 move paths.
- Only checked functions get bodies: std's functions stay lazy.
- `--time-passes` gains `places (build)` and `places (elaborate)` lines
  and a fallback count, so every step reports its cost in the same run.

**If the target is missed** after step 3: first the representation
(statement records, the intern table), then building lazily (bodies only
for functions with a needs-drop local, temporary or parameter at
`check`, all at a build), which is safe because nothing else reads the
IR at `check` until 0.26.2's effects. Lazy building is a stopgap: 0.26.1's
code generators need every body at a build, and 0.26.2's effects every
body at `check`.

## 7. Test plan

### 7.1 What exists

`tests/run.sh -l FILTER | wc -l`, of 2,823 cases: `sem_own_` 389 (the
audit's probes; 8 XFAIL left, all OVERSTRICT or DIAG), `own_` 481 (with
`sem_own_` and `err_own_`), `drop` 98, `move` 122, `temp` 81, `flag` 23.
In tests/run, 283 cases print their drops (`// EXPECT: drop N`; 213 of
them `sem_own_`), 326 expect an `own.*` error, 154 run with
`--check-alloc`. tools/sinksweep/argsweep.py makes the
`own_arg_temp_sweep_*` files (4,340 cases of argument forms); the gate's
`fuzz-sem` row runs tools/semfuzz (`--try-args`, `--assign-calls`), and
tests/own-try has 10 agent-style programs.

### 7.2 The findings and families as IR tests

A new runner directive, `// PLACES: text` (and `PLACES-NOT`), matches the
elaborated IR of `--emit-places`, as `// CHECK:` matches `--emit-ir`
(tests/run.sh:103–107). Each finding gets a `places_sNN_*` case: its
probe with `PLACES:` lines on the drops. In 0.26.0 it runs with
`--places-diff`, which must list no difference; from 0.26.1, when the
code generators run the IR's drops, it also runs at -O0 and -O2 with
`--check-alloc`, so it fails if the IR or a code generator drops wrongly.

| finding | probes (tests/run, `sem_own_` left out) | the IR's mechanism | `PLACES:` shows |
|---|---|---|---|
| S1 a part of a Vec element moves out | vec_elem_tuple_part, elem_part_push, elem_field_return, … | move out of `[i]`: own's error, the IR's backstop | (rejected) |
| S2–S5 the stopgap's misses | stop_for_enum_keep, stop_zip_for_keep, stop_keys_for_keep, stop_hashset_iter, stop_btree_first_kv, … | items `BORROWED`: no drop, no move out | no `drop` of the item |
| S6 an owning iterator consumed by bit copy | user_iter_count, generic_user_iterator_collect, … | `copy` of a needs-drop place is a verifier error | one `drop` of the iterator |
| S7 `x.drop()` | drop_call_method | own's `own.drop_call` | (rejected) |
| S8 a pattern skips owned parts | tuple_wild, enum_glue, iflet_partial, enum_named_variant | open drop of the rest | `drop(_t.1)` |
| S9 `for` over an owned Vec temporary | for_temp_vec, for_vec_take | `__for_seq` is a local of the loop's block | `drop(__for_seq)` after the loop |
| S10 `for` over owned items | iter_owned_for, for_owned_break | the arm's binding is owned | a `drop` per iteration, and on `break` |
| S11 `count()`, `filter()` | iter_owned_count, iter_owned_filter | std's bodies, built like any | `drop` in `count`'s loop |
| S12 a later argument's `?` | try_in_arg | temporaries dropped on the early exit | §3.12 |
| S13, S17 assignment through an index | drop_vec_pop_remove, assign_elem_drops_old, assign_array_elem_drops_old, hashmap_get_or_insert | `drop(P)` before the write | `drop((*_b)[_i])` |
| S14 a matched temporary nobody binds | temp_match_scrutinee_unbound | the scrutinee is a statement temporary | `drop` at the statement's end |
| S15 a field moved out of a temporary | temp_return_field_of_call, temp_tuple_index_of_call | open drop of the temporary | `drop(_t.b)` |
| S16 an operator's owned operands | add_owned_temps | temporaries lent to the impl | two `drop`s at the statement's end |
| S18 `let _ = e` | temp_let_underscore | a value is a temporary dropped at once; a place is `mention` | `drop` / `mention` |
| S19 a closure's sink parameter | closure_byvalue_param_map, leak_and_then, iter_owned_fold, … | the closure body's owned parameter | `drop(_2)` at its exit |

| family | tests | mechanism |
|---|---|---|
| `793e4b8c` arguments that may return | own_arg_temp_sweep_{let,sink,inout}, own_arg_temp_try_outer | transparent desugared blocks (§3.7); temporaries per statement |
| `51075d9c` a requires call's arguments, a struct literal's let field | own_arg_temp_requires, own_arg_temp_sweep_{let,sink,inout}_req | the same |
| `ea70255c` an assignment's temporaries after the old value | own_assign_temp_drop_order | `tmp = v; drop(P); P = move tmp`, then the statement's temporaries |
| `1d4215a4` a closure's by-value parameter | own_closure_param_{drop,exits,adapters,generic,nested} | S19's |

Each family also gets one `places_` case with `PLACES:` lines, taken from
its commit's report program.

### 7.3 During the transition

- **`--places-diff`, the oracle at `check` (0.26.0).** The own pass
  decides each `DEFER_IMPLICIT` placeholder (kept, emptied, flagged by
  `finish_drops`), and elaboration decides each `drop(l)` of the same
  locals. `check --places-diff` lists, per function, every local whose
  two decisions differ, every IR drop with no placeholder and every
  placeholder with no IR drop, with their lines. It needs no code
  generator, so it works from step 3. It runs over compiler/src and the
  2,823 suite sources; a difference is a bug in one of the two (the
  audit's `EXPECT` lines and `--check-alloc` say which), or a difference
  of form that is listed with its reason in `places/README.md` (a flag
  one of them does not need). The findings of §7.2 are where the two most
  need to agree.
- **Shadow (0.26.1).** While the old paths exist, `VOLE_LOWER=ast|places`
  selects the code generators' input (the IR-lowered functions ignore the
  own pass's `DEFER_IMPLICIT` nodes and flag `let`s). The 283
  drop-printing cases, the 154 `--check-alloc` cases and the sweeps must
  print the same under both, at -O0 and -O2. A difference is a bug in one
  of them; the audit's EXPECT lines say which.
- **Verifier.** `--verify-places` checks every body's form (§3.6), types
  of operands, the `copy` rule (§3.3), each `as V` dominated by a
  `switch` on its discriminant, no use of a local outside its storage; it
  runs over every case of tests/run with `check` in the step's own test,
  and over compiler/src.
- **Fuzz.** argsweep.py and semfuzz with `-c` the new compiler, at -O0
  and -O2 with `--check-alloc` (tier 1, filtered; the gate's `fuzz-sem`
  is the integrator's).
- **Fixpoint.** `bootstrap.sh --dev --no-suite` builds the compiler with
  the IR on and checks its fixpoint: in 0.26.0 the IR is built and
  elaborated beside the own pass's drops, from 0.26.1 its drops are the
  ones that run.

## 8. The steps

Each step is one commit (steps 2 and 3 may be several) with its own
check, tier 1 only (`tests/run.sh FILTER`, `tests/affected.sh -O 2`);
tier 2 (`tools/premerge.sh`, `tests/affected.sh`) before each report.

**Who owns what.** Agent A owns `places/`, `front/own/` and
`front/effects/`, the `places_` cases and the runner's directive. In
`front/check/` A owns only the 14 drop call sites (0.26.1, step 7),
`check_program`'s order (the places calls in 0.26.0, the reorder of step
6) and the transparent-block flag where the checker makes those blocks
(step 2); everything else in `front/check/` is the private-fields or the
embed agent's. In `front/ast.vl` A adds the node flag beside embed's
`NodeKind::Embed`. The files shared between agents, and the order their
changes merge in, are brief-0260-common.md's table. Agent B (0.26.1)
owns `middle/lower/` and `gen0/gen/`. The IR's definition
(`places/ir.vl`) is A's; B asks A for a change to it, as the 0.17 Phase 0
contract worked.

### 0.26.0: steps 1–3, one agent

| # | step | agent | check |
|---|---|---|---|
| 1 | **The contract.** First commit: the borrowed-copy predicates moved to `front/own/byref.vl` (`refactor move`, §5). Then `places/ir.vl` (bodies, locals, places, projections, operands, rvalues, statements, terminators, points), `print.vl` (`--emit-places`), `verify.vl` (`--verify-places`), `places/README.md`; no caller | A | `check` clean; `bootstrap.sh --dev --no-suite`; nothing else changes |
| 2 | **The builder** for every construct of the checked AST, reading through the own pass's nodes (§4): scopes, temporaries and their transparent blocks (the checker's node flag), borrows, two-phase receivers, storage markers, defers on exits, `BORROWED` locals, un-elaborated drops; `places_ok(f)` false for a construct not yet built; run behind `--places`. 2a expressions, calls, control flow; 2b `match` and patterns; 2c closures, `for`, `defer`, contracts | A | `places_` cases (un-elaborated); `--places --verify-places` clean over compiler/src and every tests/run source; fallback count; after 2a, `tests/compile_cost.sh` and `places (build)`, with the fallback rule (§6); after 2c, `places (build)` ≤ 340M |
| 3 | **Elaboration**: 3a move paths, the two dataflows, drops decided, flags, shims, the backstop, `--places-diff`; the `PLACES:` directive in tests/run.sh; §7.2's cases. 3b the default: the IR on at `check` and at every build level, `--no-places`; `places/README.md`, a releases.md bullet | A | `tests/run.sh places_`; `places (elaborate)` ≤ 100M; `--places-diff` over compiler/src and every tests/run source, each difference fixed or listed; before 3b, the backstop silent over the same sources; after 3b, `tests/compile_cost.sh` (§6), the fallback rule, and the fixpoint |

### 0.26.1: steps 4–9, two agents

The plan of record for 0.26.1, beside the cells (g). B starts on the
day 0.26.1 opens, against the contract, `--emit-places` output and
`--places-diff`.

| # | step | agent | check |
|---|---|---|---|
| 4 | **-O1+ from the IR**: places to SSA in `middle/lower`, drops as shim calls, flags as SSA bools; per-function fallback to the AST path; `VOLE_LOWER` | B | under `VOLE_LOWER=places`, at -O2: `tests/run.sh own_ drop temp flag move opt_`; §7.3's shadow; lowering ≤ 1,343M |
| 5 | **-O0 from the IR**: gen0's walk over IR statements, same target interface; the shim list added to the -O0 loop and to the code cache's function set (§3.9) | B | the same filters at -O0; `tests/affected.sh -O 0`; gen0 ≤ 2,012M |
| 6 | **The switch**: the code generators read the IR by default; the drop edges into effects and the call graph; check_program reordered (§4); the fallback count 0 over compiler/src and the suite's sources | A and B | `bootstrap.sh --dev --no-suite` fixpoint; `tests/affected.sh`; `tests/query` transcripts unchanged |
| 7 | **The own pass's drop code deleted** (§5), the checker's 14 call sites, `tools/fixvalues` and `refactor_shape::extract`'s reads of `DEFER_IMPLICIT`; the walk given its scope-end drop events structurally where views need them (`ev_drop`, `W_DROP`); `--no-places` removed | A | `query refs own::drops --count`; `own_ sem_own_ err_own_` at -O0 and -O2; `check` ≤ 0.26.0's (§6) |
| 8 | **The AST lowerings of function bodies deleted** from `middle/lower` and `gen0/gen`; `VOLE_LOWER` removed; the lowering of statics, array constants, `consteval`, `gen_data` and `--emit-header` kept (§5) | B | the step 4–5 filters; line counts, with the kept lowering counted apart |
| 9 | **Docs and tools**: front, middle and gen0 READMEs, value-semantics.md §4's "Where", optimizer.md's compile time, the budget measured as §1.5; `query drops FILE:LINE` (a function's elaborated drops, with lines) | A | a `tests/query` transcript for `query drops` (`tests/query/run.sh`) |

**Parallelism.** In 0.26.0 the item has one agent, A, beside private
fields and `embed wgsl` (plan §13's three). In 0.26.1 it has two: A
takes step 6's front half and steps 7 and 9; B takes steps 4, 5 and 8.
A's and B's files do not overlap; the one shared function is
`compile_program` (B's), which A's step 6 changes only by its options.

**Order constraints.** Step 4 needs 2a, step 5 needs 2c for the whole
suite: both are in 0.26.0. Step 7 waits for steps 4 and 5: while one code
generator reads the AST, own's drops are still the ones it runs. Step 6
waits for step 3's cases to pass under `VOLE_LOWER=places` at both
levels. Effects move onto the IR in 0.26.2, after steps 6 and 7.

**Step 8 in 0.26.2 (agent B, placesir262b).** Step 6 left most of the
AST lowering live: the IR path drives the calls' and intrinsics'
lowerings (AST-indexed, their operands bound), and lowers constant
operands and contract and assert conditions from the AST, whose
expressions hold blocks, `if`s and `match`es (a desugared method call,
`?`, an f-string). So step 8 is three parts:

- 8.0: `--check-unsafe` from the IR (it lowered every function from the
  AST): a raw pointer's `*` and element checked in `place_addr`.
- 8a: the roots: no function from the AST (`lower_function` deleted,
  gen0's function walk cut to an atomic intrinsic's body), `VOLE_LOWER`
  gone, a build under `--no-places` an error. Everything else of the AST
  walks stays reachable through the conditions.
- 8b, after A2's contract (5391c11d) and assert conditions in the IR,
  each conjunct an IR value checked by an `IK_CONTRACT` with `e > 0`:
  the generators read that form; then the AST walks of statements and
  control flow (1,439 lines: `matching.vl`, both `control.vl`s,
  `lower_block`, `lower_let`, the AST's assignments, the defers,
  `gen_block`, the dispatchers' statement arms; front/ast.vl's DEFERS)
  and the pure expressions' AST lowering (about 520 lines) are deleted,
  with `bind_ast_locals`. Step 7's deletion of the own pass's drops
  waits for 8b's first part: until then a condition's temporaries are
  dropped by the AST lowering's defers.

Left on the AST after 8b, a later release's item (a rewrite, not a
deletion): the calls and intrinsics the IR path drives through bound AST
nodes, 2,539 lines (`middle/lower`: `calls.vl` 586, `vector.vl` 372,
`arch.vl` 347, `atomic.vl` 135; `gen0/gen`: `call.vl` 378, `arch.vl`
336, `vector.vl` 331, `atomic.vl` 54), to become calls of the IR's
operands with no AST node; and the constant operands' lowering
(literals, constants, string ids, RT_SITE values).

**State, agent A (placesir261a).** Done: R1 (kept bodies) and R2 (drop
shims) for B; step 2's builder cost (§6, "Measured in 0.26.1"); step 6's
front half without the switch: the drop edges into effects (each
function's kept and flagged drops give an edge to the `Drop::drop`
functions their shims call; with the placeholders skipped by the effect
walk, `query effects` of compiler/src's 20,275 functions differs in 3,
each more precise); step 9's `query drops`. `check_program`'s order is
§4's already (the IR before the effects). Then, for B: shims as
functions of `FNS` after the program's (`shim_fn(id)`, not program
items: lowered in a loop over `shim_count()`), a generic `Drop::drop`
instance made at check time when the glue made none (so step 7 needs
nothing more for it), R3 (a moved capture's live flag cleared), union
literals' parts, R4 (a match on values is one switch with many targets;
`middle/lower/places.vl`'s `lower_switch` still makes a chain of
compares of it, so `opt_switch` fails under `VOLE_LOWER=places` until it
uses `ir_switch`). From B's step 3: R5 (a statement temporary drops at
the end of its prelude's scope, not of the hidden `let` that holds an
operand), R6 (an open drop's part flags made before the rewrite), R7 (a
sink closure's second move out stops the program), R8 (a parametric
copy's temporary is not owned); R9 (`v[i]` on a Vec) did not reproduce
here: both paths lower the checker's `v.as_slice()[i]` alike. And
`--places-diff` checks where each drop runs and its flag
(places/README.md). Waiting on B's steps 4 and 5: the default (step 6's
switch: `PLACES_ON` true, `--no-places` the escape) and step 7.

## 9. The chain rule

0.26.0's compiler is built by 0.25.5, so compiler/src uses only 0.25.5's
language and std: MVS conventions, `Vec<T, Comp>` tables (0.25.5's
modernization), f-strings as today; no `&T` fields, no `usize`, no
format literals. The IR adds no language feature, so no item here is a
two-step change. In 0.26.0 the IR is built and elaborated in every
build, the fixpoint included, but the own pass's drops are the ones that
run. In 0.26.1 the first compiler (built by 0.26.0) runs the own pass's
drops in its own code; its fixpoint build (0.26.1 by 0.26.1) runs the
IR's, which is the first whole-compiler test of the IR's drops.
std needs no change; a std body the IR shows to drop wrongly is fixed in
std like any bug, and the hook regenerates `front/stdsrc.vl`.

## 10. Open questions

1. **Write the IR's drops back into the AST instead of moving both code
   generators?** It would leave `middle/lower` and gen0 untouched, but it
   keeps the AST bookkeeping every finding came from and is discarded
   when the code generators move. *Recommendation:* move them (§2), in
   0.26.1 (§8), rather than write a bridge that is thrown away.
2. **Move errors on the IR in 0.26?** The IR has exactly the dataflow
   `own.moved` needs. *Recommendation:* not in 0.26: the own pass keeps
   the messages, `query own` and its `try:` lines; the IR adds only the
   move-out backstop. The errors move with borrowck in 0.27.
3. **Shims or inline glue?** *Recommendation:* shims, one per type; open
   drops inline; the inliner takes small shims at -O2. Measure -O0's
   object size and the bench at -O0 in step 5.
4. **Keep every body at a build, or rebuild before codegen?**
   *Recommendation:* keep them at a build (one arena, freed after code
   generation), free each at `check` after elaboration; step 5 measures
   RSS against the 1.05x row.
5. **Temporary rules: vole's 0.25 or Rust 2024's (tail expressions,
   `if let` scrutinees)?** *Recommendation:* vole's, unchanged, in 0.26:
   the shadow comparison needs the same output. The rust edition decides
   in 0.27, where its translation can say what moves.
6. **Calls and drops as statements, given no unwinding?** Yes: this is
   the plan's decision 18 (§12), "a panic exits with 101, with no
   unwinding", taken for now: the user wants unwinding later, so nothing
   here may rule it out. Unwinding makes calls and drops terminators with
   cleanup edges, a change to §3.4–3.5 and both code generators.
   Its consequences:
   - the rustc twin (plan §4) runs with `-C panic=abort` and maps exit
     codes: Rust's abort is SIGABRT (134), vole's panic is 101.
     `#[should_panic]` cannot run under abort, so a vole test that expects
     a panic is compared by its exit code only;
   - a panic in a spawned thread ends the process; there is no
     `catch_unwind`;
   - `Drop` is not cleanup on panic: voltty's terminal restore stays an
     atexit or signal handler;
   - `--check-alloc` reports no leaks on exit 101, pinned by a test;
   - `assert`, a failed `requires` and a panic share one exit-101 path:
     one rule, one `explain` entry;
   - the guide says all of this.
7. **Borrows as rvalues on every argument now, or a compact lend operand
   expanded in 0.27?** *Recommendation:* rvalues now, so that 0.27 changes
   no shape; if step 2 misses its 340M, a lend operand is the first
   saving.
8. **Compound let parameters as `&T`, or as read-only value locals?**
   *Recommendation:* `&T` with `*` projections: the same IR as the
   edition's translation, and moving out of or dropping them is impossible
   by construction.
9. **Where does the IR live?** *Recommendation:* `compiler/src/places/`,
   a top-level module beside `front` and `middle`: `check`, gen0 and
   middle all read it.
10. **A tool for the drops, now that they leave the AST?** Today they are
    AST nodes; afterwards only the IR has them. *Recommendation:* `query
    drops FILE:LINE` in step 9.

## 11. Corrections to the plan

1. **`e1bbdd94` is a view-summary family, not a drop family.** It and its
   follow-up `f9510194` keep a declared cast's loans past the type
   filter (`summary::cast_mask`, `calls::on_call`); their tests are
   `err_own_unmap_live_view` and `err_own_cast_view_grow`. No drop is
   involved, so they cannot pass "on the IR's drops". They stay the own
   pass's in 0.26 and become region tests in 0.27 (`fn f32s(b: &[u8]) ->
   &[f32]` carries the loan in its type). The drop family is `793e4b8c`
   with `51075d9c` and `ea70255c`; `1d4215a4` (S19's fix) belongs with
   them.
2. **The 19 findings already pass.** All 19 SOUNDNESS findings were fixed
   in 0.25.x on the own pass's drops; the 8 XFAIL left in `sem_own_` are
   OVERSTRICT or DIAG. The bar is that they keep passing with the IR's
   drops and show them in the IR.
3. **Effects must see the IR's drops once the placeholders go.** Row (a)
   lists "effects inferred on it", and plan §9.2 says the placeholders
   exist so that inference sees drops. Deleting them without a
   replacement would lose `alloc`, `panic` and `diverge` from user `Drop`
   impls, which the optimizer reads as `willreturn` and `nopanic`. In
   0.26.0 the placeholders stay, so effects see them as today; 0.26.1's
   step 6 feeds the IR's drop edges into the AST inference and the call
   graph before step 7 deletes them, and 0.26.2 moves the inference onto
   the IR.
4. **(f) does not recompute view summaries on the IR.** Its note "after
   a, so the view summaries it disturbs are recomputed on the IR" assumes
   views move onto the IR in 0.26; no item moves them. They stay on the
   AST walk until 0.28, and (f)'s summaries are recomputed by the own pass
   as today.
5. **The 1.10x share is tight, not loose.** It is +469M instructions (+26
   ms) of 0.26.0's single 1.13x budget, and today's AST-to-SSA lowering
   is 1,343M. With the placeholders kept in 0.26.0, their 228M does not
   come back until 0.26.1's step 7, so the IR must cost about a third of
   that lowering (§6).
