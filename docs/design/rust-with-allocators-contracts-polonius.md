# Vole as Rust with explicit allocation, enforced contracts and a Polonius checker

A design report, 2026-10-30. Numbers come from the tree at release 0.25.5
(`volec --time-passes` on the compiler's own source, and counts over
`compiler/src` and `compiler/std`).

## The thesis

Four static systems, each a per-function analysis, each fed only by
signatures, and each producing facts the optimizer consumes:

| system | what the signature carries | what the check is | what the optimizer gets |
|---|---|---|---|
| types and regions | `&'a T`, `&'a mut T`, elided where Rust elides | Polonius, per function | `noalias` on `&mut`, `readonly` on `&` without `UnsafeCell` |
| effects | inferred, pinnable (`#[pure]`, `#[no_alloc]`, `#[effects(..)]`) | per function over the call graph, as today | calls that may be removed, reordered or hoisted |
| contracts | `requires`, `ensures`, declared | a run-time check at the call, as today | the checked condition as a fact after the check |
| allocation | the allocator as a type parameter, `Vec<T, A>` | the type checker, plus `alloc(A)` as an effect | `needs_drop`, arena lifetimes, no hidden calls |

The rule that makes them compose is one sentence: **every fact that
crosses a function boundary is written in, or inferred into, the
signature, so every check is local to one function and the optimizer
reads the same facts the checker proved.** Today's view summaries break
that rule: they are computed from bodies, callees first, which is why the
own pass is interprocedural, why a body change can break a caller, and
why it is the one pass that has not converged.

## 1. What changes, what stays

Stays, unchanged:

- no undefined behaviour in safe code: wrapping integers, checked
  indexing, `unsafe` only around raw pointers and C. One rule is
  reversed: division by zero panics, like an index out of bounds. The
  `x / 0 == 0` rule was a mistake; it hid bugs to avoid a check that
  `requires d != 0` hoists and the optimizer removes like any other;
- the effect system, its inference and its bounds;
- contracts checked in every build, with no release switch;
- allocators as explicit values: `fn main(gpa: Gpa)`, `Vec::new_in(gpa)`,
  arenas, fixed buffers, no global allocator;
- monomorphization only: no `dyn`, no macros, no wildcard imports;
- the toolchain (`query`, `edit`, `refactor`, `fix`, the guide, the LSP),
  the backends, the bootstrap chain.

Changes:

- `&T` and `&mut T` are types. They go in fields, containers, results,
  closures and statics, with a region that is elided or written.
- The MVS surface goes entirely: the `let` / `inout` / `sink` parameter
  conventions, `var`, the `&x` call marker, `inout` locals and
  second-class views. Parameters are `T`, `&T` and `&mut T`; bindings
  are `let` and `let mut`; a call writes `&x` and `&mut x`. The own pass (13.8k lines in `front/own`), the
  view summaries, two-level origins, the type-directed loan filter, the
  iterator stopgap and the 174 `#[views]` pins go with them.
- Moves and drops are elaborated per place on the lowered CFG, with drop
  flags, before SSA. This is where the ownership audit's 19 double-free
  and leak findings are fixed as a class, not one at a time.
- `UnsafeCell`, `Cell`, `RefCell`, `Rc` and `Arc` become expressible, each
  with an allocator parameter where it allocates.
- Send and Sync are inferred structural kinds, as today's "inferred from
  the types", with one attribute for unsafe authors.

### Syntax: a subset of Rust, plus clauses

The rule: **a Rust program that uses only what vole has is a vole
program with the same meaning.** Vole is a subset of Rust (no `dyn`, no
macros at all, no global allocator) plus additions that Rust has no
syntax for (contract clauses, effect attributes, allocator parameters,
`defer`). Rust's own macros are the one place the subset cannot be
literal: `println!` and its family become functions of the same name
without the bang, with the format literal checked by the compiler, which
is what vole does for `println` and `assert` today. A Rust token never means something else. Today's README says
vole "looks like Rust on purpose, but means different things", and the
0.16 evals measured what that costs: 221 pointer-as-reference errors in
16 runs, a `conv.rust` error family whose only job is to rewrite Rust
into vole, and the conversion errors from `i64` lengths. A model's
habits should be right, not nearly right.

What that changes beyond references, with the compiler's own counts:

| today | becomes | count in compiler and std |
|---|---|---|
| `let` / `inout` / `sink` parameters, `&x` at the call, `var`, `inout` locals | `T`, `&T`, `&mut T`, `&x`, `&mut x`, `let mut` | 1,409 + 498 + 1,363 + 3,765 |
| `sink \|x\|` | `move \|x\|` | 35 |
| `println(f"{x}")`, f-strings | `println("{x} {y:?}")`: plain functions, no bang, no `f` prefix; the format string is Rust's grammar, a literal the compiler checks at compile time. Likewise `print`, `eprintln`, `format_in(a, ..)`, `panic`, `assert`, `assert_eq`, `unreachable`, `todo`, `write`. `vec![..]` is `Vec::from_in(a, [..])`. No macros of any kind, bang or otherwise | 1,248 f-strings, 258 println calls |
| `Buf`, `[u8]` as text | `String<A>`, `&str`, `Vec<u8, A>`, `&[u8]` | 703 Buf, 344 String |
| lengths and indices `i64` | `usize`, as every agent writes it | 1,849 `as i64`, 23 `usize` |
| `distinct T` | a newtype struct, `struct Port(u16);` | 0 in the compiler |
| `x / 0 == 0` | a panic | |
| `where` rejected | accepted, as sugar for inline bounds | |
| `impl Trait` rejected | accepted in argument and return position: an inferred concrete type under monomorphization, which is also how a closure is returned | |

Kept because Rust has no syntax for them, in forms Rust's parser would
not misread: `requires` and `ensures` clauses between signature and
body (Rust's nightly contracts use attributes; either is fine, the
clause reads better), `#[pure]`, `#[no_alloc]`, `#[effects(..)]`,
`defer` (59 uses), `fn main(gpa: Gpa)`, `new_in(a)` and the other `_in`
constructors, which are Rust's own `allocator_api` names.

The closeness is testable. Add a `rustc-twin` row to the gate: every
guide example and every bench program, with the clauses and attributes
stripped, the format functions given their bang, and a twenty-line shim
for `Gpa` and `_in`, compiles with `rustc` and prints the same output. The bench already keeps C twins;
this is the same discipline for the syntax, and it is the number that
says whether a model's Rust habits are right in vole.

## 2. The borrow checker: Polonius

**What it computes.** A region is a set of loans. For each point of the
control-flow graph, Polonius computes which loans are live, which regions
flow into which (`subset`), and reports an error where a live loan's path
is written, moved or dropped. It is location-sensitive, which is the
difference from NLL: NLL's known rejection, a borrow returned from one
branch and the place mutated in the other (`get_or_insert`, problem
case 3), is accepted. That pattern is all over vole's HashMap API, so the
difference is not academic.

**Where it runs.** On the lowered CFG with explicit places, before SSA
construction, together with move and drop elaboration. Rust runs it on
MIR for the same reason: the checker needs places, not virtual
registers. Vole's `middle/lower` is the natural home.

**How it is implemented.** About a dozen Datalog relations over a
semi-naive fixpoint on sorted vectors; the rules are public and small.
The one trick worth copying from rustc: run the location-insensitive
variant first as a filter, and the full location-sensitive one only on
functions where the filter finds a potential error. Most functions never
pay for the full analysis.

**Cost.** Per function and close to linear in it, parallel over functions
(the middle end already runs passes in parallel). The budget is
generous: today's own pass is 37 ms of a 457 ms self-build at -O0, and
it is interprocedural. The type checker is 124 ms. A per-function
Polonius with the filter fits inside the own pass's slot. Compile speed
is not what lifetimes cost; what makes rustc slow is LLVM, trait
solving, macros and the query machinery, none of which vole has.

**Signatures.** Rust's elision rules: one reference input gives its
region to the output, `&self` wins when present, anything else is
written. Struct fields are always written (`Parser<'s>`). The compiler
and std have 115 struct fields holding a slice today; those become 115
region parameters, and the 174 pins become zero annotations. Closure
bounds use Rust's `Fn(&T) -> &U` sugar, which means a late-bound region
for the call; support late-bound regions in fn and closure signatures,
with no explicit `for<'a>` syntax at first. There is no `dyn`, and
`where` is only sugar for inline bounds, so no higher-ranked trait
solving is needed.

**Variance** is computed once per type definition: `&mut T` and
`UnsafeCell<T>` are invariant, everything else follows its fields.

**Drop check.** A value whose type has a `Drop` impl needs all its
regions live at the drop. Std's containers get `#[unsafe(may_dangle)]`
on `T` with a SAFETY comment, so `Vec<&'a T>` may outlive what it
borrows as long as it is only dropped. The commit hook already refuses
unjustified `unsafe`, so the attribute is audited like any other.

**Two-phase borrows** stay. The prototype counted 422 call sites of the
form `v.push(v.len())`.

**What becomes impossible by construction.** The views audit's twenty
soundness findings are all "an origin was lost through X", and the
exclusivity audit's twelve are all "two accesses of one place were not
seen". With regions in types there is no origin to lose: the type of
`keep: Vec<&'v String>` says what it depends on, and `v.remove(0)` while
`keep` lives is a Polonius error, not a wrong answer at run time.

## 3. Explicit allocation under regions

The two fit together better than either fits alone.

- **Every container carries its allocator** as a type parameter, with no
  default: `Vec<T, A>`, `Box<T, A>`, `String<A>`, `HashMap<K, V, A>`.
  `Gpa` is zero-sized, so `Vec<T, Gpa>` is today's Vec. `clone()` reuses
  the source's allocator; `clone_in(a)` moves to another.
- **Arenas become references.** `Vec<T, &'a Arena>` is eight bytes, the
  same representation as the handle today. The container is bounded by
  the arena's region, so `arena.reset(&mut self)` is safe: an exclusive
  borrow proves nothing allocated in it is still reachable. This is the
  design document's U3, which the hybrid could never make safe.
- **Reference graphs in arenas.** `arena.alloc(x) -> &'a mut T` gives
  `&'a Node` graphs, the third thing lifetimes buy that the MVS design
  listed as lost. `alloc` requires `needs_drop::<T>()` to be false, a
  compile-time constant; a `TypedArena<T>` runs drops for the rest. Leaks
  stay safe, not UB, and `--check-alloc` lists them.
- **Recursive and self-managed types lose their raw pointers.** Today
  `Node { left: *Node }` is a plain struct and the compiler and std have
  3,903 raw-pointer parameters, most of them the legacy "`*T` means
  `&mut T`" form. They become `&`, `&mut` and `Box<T, A>`, and the 5,835
  mentions of `unsafe` should fall by most of that. Measure it after the
  migration; it is the single best number for "did this make the
  language safer".
- **Effects keep naming allocators.** `alloc(A)` is inferred as today,
  `#[no_alloc]` is checked as today. With loans in hand, the value-level
  form `alloc(a)` that 0.16 planned becomes cheap: the loan on the
  parameter identifies the allocator.
- **Shared ownership is explicit.** `Rc::new_in(gpa, x)` and
  `Arc::new_in(gpa, x)` name their allocator like everything else. The
  ethos "a program says in its text what it allocates" holds unchanged.

## 4. Contracts: enforced, and used by the optimizer

What exists already is most of it. `requires` is checked at the call
after the arguments, `ensures` at every return, `old(e)` at entry;
conditions must be pure, checked through the effect system; nothing is
ever assumed, a fact comes only from a check that ran; `query checks FN`
lists what the optimizer removed; the bench pair shows what the facts
are worth (prefix sum -83% time, dot -59%). The compiler and std use 133
`requires` and one `ensures`.

Under the new model, four things tighten it.

**Conditions are closures over shared borrows.** A condition takes `&`
of every argument and `result`. The borrow checker then guarantees for
free what the effect check guarantees today, that a condition mutates
nothing, and the two checks agree by construction. `old(e)` requires a
plain `e` (`old(v.len())`, never `old(v)`), because an `old` of an owned
value would be an allocation inside a contract; a `debug` clause may
clone with an explicit allocator.

**Three outcomes at every check site, decided by the optimizer.** Proven:
the check is removed and the fact kept. Unknown: the check stays and the
fact holds after it. Refuted, which is new: a check the optimizer folds
to false (a constant argument, a range that excludes it) is a compile
error, `contract.refuted`, not a run-time panic waiting to happen. This
is Rust's deny-by-default `unconditional_panic` lint, promoted to the
rule. "Compiler enforced" means exactly this: a contract that can be
decided at compile time is decided there.

**Facts flow both ways across a call.** After a call returns, the
caller knows the callee's `ensures`, as today, and also that the
callee's `requires` held at entry, because the call would not have
returned otherwise. Nothing is assumed: both facts come from checks that
ran. This stays the principled line against C++'s `[[assume]]`; there is
no attribute that asserts without checking, and if one is ever wanted it
is `unsafe`.

**Contracts and regions solve the index problem twice.** The MVS
discussion ended on stale indices. A reference carries identity, so
`keep: Vec<&'v String>` cannot go stale. A contract carries bounds, so
`fn get(&self, i: usize) -> &T requires i < self.len()` hoists the bounds
check to the caller, where a loop bound or the caller's own `requires`
discharges it, and the range pass removes it. Trait contracts bind every
impl, as effect declarations do; generic contracts are checked per
instance, as everything is.

## 5. Threads and interior mutability

With Rust's semantics the answers are Rust's, and there is nothing to
invent:

- `UnsafeCell<T>` is the one source of a writable pointer from `&T`, and
  the one thing that turns off `readonly` for the optimizer. `Cell`,
  `RefCell`, `Mutex`, atomics and channels are built on it in std.
- A `Mutex` lock returns a guard with `Drop` and `Deref`, which the
  hybrid could not express (a Drop type may not hold a view today). The
  `with(|data| ..)` form stays as sugar.
- Send and Sync are inferred structural kinds with two leaves that need
  a vouch: a raw pointer and an `UnsafeCell`. Unsafe authors write one
  attribute with a SAFETY comment on perhaps ten std types; users never
  write it. This is today's "inferred from the types", made exact.
- Scoped threads take `'scope` and `'env` regions as Rust 1.63 does, and
  `thread::scope` already has the right shape. Two threads writing
  disjoint halves of a slice is `split_at_mut`, which exists.
- A `static` requires Sync. `static mut` keeps today's effect rule, and is safe:
  legal in single-threaded code, `sync.global` when reachable from a
  thread. That is more permissive than Rust's `static mut` and still
  race-free.

## 6. A worked example: all four together

```rust
struct Tok<'s> { text: &'s str, kind: Kind }          // Copy: two words

struct Parser<'s, 'a> {
    toks: Vec<Tok<'s>, &'a Arena>,                     // owned by the arena
    pos: usize,
}

impl<'s, 'a> Parser<'s, 'a> {
    #[no_alloc]
    fn peek(&self) -> &Tok<'s>
        requires self.pos < self.toks.len()            // the bounds check, hoisted
    { &self.toks[self.pos] }                           // no check here: the fact holds

    fn next(&mut self) -> Tok<'s>
        ensures self.pos == old(self.pos) + 1
    { let t = self.toks[self.pos]; self.pos += 1; t }
}

fn parse<'s, 'a>(src: &'s str, arena: &'a Arena) -> Parser<'s, 'a> { .. }  // alloc(Arena)

fn main(gpa: Gpa) {
    let src = read_in(gpa, "x.vl");
    let arena = Arena::new_in(gpa);
    {
        let mut p = parse(&src, &arena);
        while p.pos < p.toks.len() { let t = p.next(); .. }
    }
    arena.reset();                                     // safe: nothing borrows it now
}
```

Zero copies: every token is a view of `src`. `parse` is `alloc(Arena)`
and `peek` is proven allocation-free. The optimizer removes `peek`'s
bounds check from its `requires` and proves the `while` loop's call to
`next` in bounds from the loop condition. `arena.reset()` is safe because
Polonius sees no live loan on the arena after the block. The 3.4% of
agent-written functions the MVS prototype rejected are this shape, and
they check clean with one region each.

## 7. Migration and the bootstrap

The chain rule holds: each release is built by the previous one, so the
change is three releases.

- **N: both checkers.** Reference types, elision and Polonius land next
  to the own pass. The MVS spellings still parse in this release only,
  as a migration aid, and are lowered to references (`let` → `&T`,
  `inout` → `&mut T`, `sink` → by value, `&x` → `&mut x`, `var` → `let
  mut`). Polonius errors are reported as warnings where the own pass
  accepts; the self-build must be clean under both. Division by zero
  starts panicking here, with `requires d != 0` added where the
  compiler's own source relied on the old rule.
- **N+1: the compiler's source migrates**, with `fix --only references`,
  the reverse of 0.18's `fix --only conventions`. Its workload is
  countable today: 1,409 `inout` parameters, 498 `sink`, 1,363
  `inout`/`sink` receivers, 3,765 `&`-marked arguments, 115 slice fields
  that need a region, and the hard part, 3,903 raw-pointer parameters
  that each need a decision between `&`, `&mut` and raw. The own pass is
  deleted in this release.
- **N+2: the MVS spellings are removed.** `let x: T` as a parameter,
  `inout`, `sink`, `var` and the bare `&x` marker become parse errors
  with a `try: volec fix --only references`, and the guide's "why this
  is not Rust" table shrinks to the rows that remain true: allocation,
  effects, contracts, no macros, no `dyn`.

## 8. What is given up, and what is not

Against the MVS plan: lifetime syntax on struct fields and on the rare
signature elision cannot cover, which is where agents' Rust habits
already are; and a checker that is a known algorithm rather than a new
one. Against Rust: `dyn`, macros and a global allocator, all deliberately. Against today's vole: the second-class views story, the
summaries, and the hybrid's inferential checker, which is the thing that
would not converge.

## 9. Decisions to take

1. Rust's syntax and meaning throughout, the table in section 1: every
   MVS spelling gone after N+2, no macros (`println` and its family are
   functions with a checked format literal), `usize` lengths, `String` and `&str`, `where` and `impl Trait` accepted,
   division by zero panics. The `rustc-twin` gate row measures it.
2. Polonius on the lowered CFG before SSA, with the location-insensitive
   prefilter; move and drop elaboration per place in the same pass.
3. `Rc` and `Arc` in std, with allocator parameters.
4. `old(e)` plain-only outside `debug` clauses.
5. A refuted contract is a compile error.
6. `#[unsafe(may_dangle)]` on std containers, audited by the commit hook.
7. `static mut` keeps the effect rule rather than Rust's `unsafe`.
8. The migration's success number: `unsafe` mentions in the compiler and
   std, before and after.

## 10. Should the type system go further? On dependent types

The question is whether the patterns above, index validity, non-empty
containers, dimension agreement, state machines, are better captured by
a richer type system than by contracts. The answer is: take four cheap
type-level features, make contracts gradually static with a fixed
decision procedure, and keep anything that needs a solver out of the
compiler.

**Why not full dependent types.** Three reasons, each sufficient.

- *Compile speed and predictability.* Dependent type checking evaluates
  terms at compile time, and refinement systems (Liquid Haskell, F*,
  Dafny) call an SMT solver whose time is unbounded and whose answers
  change between versions. Every release of vole measures compile speed
  and refuses a regression; a solver in the build path makes that
  promise impossible to keep.
- *Agents write the proofs.* In a dependently typed language the hard
  cases need hand-written proof terms or lemma calls. The 0.16 evals
  show the cost of agent work is dominated by turns and prompt size.
  Every annotation an agent must write that is not a Rust habit is a
  tax; a proof obligation is a large one, and a wrong proof attempt
  loops.
- *Mutation.* Dependent types and mutable state do not mix without
  separation logic or ownership underneath. The ownership is the
  expensive part, and section 2 already buys it. What is left for a
  type system to add is small.

**What ownership already gives, nearly free.** Regions are a lightweight
dependent mechanism: they quantify over scopes. Two patterns fall out of
Polonius with no new theory:

- *Branded indices.* An invariant region ties an index type to one
  container value (`Idx<'v>` from `v.indices()`), so an index into one
  Vec cannot be used on another and cannot survive a reallocation. This
  is the `indexing` crate and GhostCell, and it answers the stale-index
  problem of the MVS discussion statically for the cases where a
  reference is too strong.
- *Typestate.* Affine types plus generics give state machines in types
  (`Socket<Closed>` to `Socket<Open>`, a builder that cannot be finished
  twice). Rust programs already do this; nothing to add.

**Two features worth adding to the type system.**

- *Const generics.* `[T; N]` with `N` a parameter, `Matrix<R, C>`,
  `Simd<T, LANES>`. Under monomorphization they cost nothing and they
  capture every dimension-agreement pattern. `std::arch` and `std::gpu`
  want them today.
- *Invariants on newtype structs.* Give a struct a clause:
  `struct Port(u16) requires self.0 < 1024;`. The invariant is checked
  once, where the value is made, and is a fact of the type everywhere
  after, which is sound because it was checked.
  This is Ada's subtype predicate, and it is the honest form of a
  refinement type: a `Port` is an `i64` with a proven range, a
  `NonEmpty<T>` is a `Vec<T>` with `len() > 0`, an `Idx<N>` is an index
  under `N`. The optimizer reads the invariant as it reads a `requires`.

**Contracts, gradually static.** The contract system is the right
primitive; the upgrade is to let more of it be decided at compile time,
in steps, with the decision procedure fixed and documented:

- *Level 0, today.* Checked at run time, removed where the range pass
  proves it, and (section 4) a compile error where it is refuted.
- *Level 1, `static requires` and `static ensures`.* A clause the
  compiler must discharge at every call, or report an error naming the
  missing fact (`cannot prove i < v.len() at main.vl:12; known: 0 <= i,
  i < n; try: add requires n <= v.len()`). The procedure is the one the
  optimizer already runs: intervals, congruences and the facts from
  callees' `ensures`, with no solver, so it is fast, deterministic and
  the same at every opt level. This covers bounds, non-emptiness,
  dimension equality and most arithmetic preconditions in real code,
  and it is exactly what a refinement type system would prove, minus
  the cases that need induction.
- *Level 2, outside the compiler.* `volec verify` exports the remaining
  obligations, with ghost code and lemmas in the Verus style, to an SMT
  solver as a tool. Because the borrow checker has removed aliasing, the
  conditions are over values only, which is why Verus and Prusti work on
  Rust and not on C. It never runs in a build, so compile speed never
  depends on a solver, and a program whose obligations are unproven is
  still a program with run-time checks, not a rejected one.

**The principle, restated.** Facts live in signatures; the compiler's
decision procedure is small, fixed and fast; a contract it cannot decide
is checked at run time, and the solver is a tool. That is gradual
verification, and it fits an agent's workflow: the agent writes the
contract, the compiler says what it could not prove and what would
prove it, and the unproven remainder costs a branch, not a build.
