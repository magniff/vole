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
| `build.vl` | the builder: a checked body to the IR, in evaluation order, reading the own pass's nodes; a construct it does not build yet makes the body a fallback (`--verify-places` names it) |
| `front.vl` | what the IR reads of the checker's raw tables, one justified accessor each |
| `mod.vl` | the driver (check_program calls `run_places`) and the options: `--places`, `--no-places`, `--emit-places[=all]`, `--verify-places`, `--places-diff` |

In 0.26.0 the IR is built only under `--places` (or `--emit-places`,
`--verify-places`, `--places-diff`): after step 2a its builder costs about
433M instructions at `check` of compiler/src, over §6's 340M for all of
step 2, so §6's fallback rule applies (the IR off by default).

One body is held at a time (`ir.vl`'s `P_*` tables), cleared and reused
for the next.

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
