# The borrow checker (0.27.1, 0.27.2): the semantics

This is the committed semantics of the rust edition's borrow checker:
NLL on the places IR ([places-ir.md](places-ir.md) §3), solved per
body. It is the contract of three streams: the IR that carries what the
rules read (ir271), the solver (bc271, `compiler/src/places/borrowck/`)
and the corpus (corpus271, `tests/run/rust_b_*.vl`). It revises
[rust-surface-plan.md](rust-surface-plan.md) §4 into definitions and
rules with stable ids; code cites a rule as `// RULE: D2.5`, a corpus
case as `// RULE: D2.5` and, where it diverges from rustc, `// RUSTC:
accepts|rejects CLASS` with a class from §11.

**Status.** 0.27.0 built the region tables (`places/regions.vl`) and
checked nothing (`warning borrowck.unchecked`). 0.27.1 solves them. A
rule whose IR support does not exist at v0.27.0 says *IR change (ir271
Mn)*; until that lands the rule's stopgap, where one is named, applies.
Nothing here runs for an MVS body (`rust_fn`, regions.vl); every MVS
program compiles exactly as before. 0.27.2 appends §19 (closure kinds
and the environment), §20 (late-bound regions), §23 (std2 as the
edition's std: Z7–Z9) and §24 (auto traits); the 0.27.1 rules they
supersede are marked where they stand.

**Reading.** `Dn.m` a definition or rule; `Mn` a move rule (§8); `In` a
soundness invariant; `Rn` a named permissiveness and `Ln` a named
strictness against rustc (§11); `Qn` a decision (§0.2). IR constants are
`places/ir.vl`'s (`SK_*` statements, `TK_*` terminators, `RV_*` rvalues,
`OK_*` operands, `PJ_*` projections, `BK_*` borrow kinds, `DS_*` drop
decisions, `LF_*` local flags), region origins `places/regions.vl`'s
(`RO_*`). A statement `(a, b) = ...` writes the place `(local a,
projection b)`; `bbK[i]` names location `i` of block `K` as
`--emit-places` prints it. `sub(S ≤ T)` is read "S is a subtype of T".

## 0. Findings and decisions

### 0.1 Day-one findings (recorded as the delta asks)

- **The own pass on a rust body.** `front/own` runs unchanged on
  rust-edition bodies. `front/own/views.vl`'s `on_enter` sets
  `ocx.quiet` for them, which mutes the views/loans half (view
  summaries, `own.conflict`, escapes); only the move half reports:
  `own.moved` fires on `let a = take(v); let b = take(v);` in a
  rust-edition `main` (verified with v0.27.0). So Q2(b)'s "the own pass
  keeps the view findings" does not hold today: MVS std's hidden views
  (`SliceIter`, `Scanner`, ...) are unchecked on rust bodies in 0.27.0.
  See R2 (an explicit, counted hole) and §8.4. (0.27.2: the own pass is
  off for rust programs, Z8.)
- **`&v[i]` on an MVS `Vec`** (R9 of the delta). The rust-edition
  builder lowers it through a view temporary, not through the buffer:
  `_7 = &'r12 _2; _6 = call Vec::as_slice(move _7); ...; _5 = &'r14
  _6[_8]`, with `_6: [i64]` (a view, one slot) and `PJ_INDEX` applied
  to the view-typed local directly, with no `PJ_DEREF`. `&mut v[i]` is
  the same through `&'r mut2 _2` and `as_mut_slice`. Likewise `fn
  first(s: &[i64]) -> &i64 { &s[0] }` is `_0 = &'r3 _1[_2]`. The loan
  is of the view's element, so it ties to `v` through the callee's
  signature (§12) only if indexing a view is read as a deref through
  the view's region: D1.4 says so. **R9 is closed by D1.4, with no
  builder change.**
- **A miscompile in v0.27.0 (the contracts/effects design pass).** The
  optimizer's reference-parameter facts (`gvn::params_disjoint`,
  `gvn::param_frozen`, vecfacts' frozen header) were gated by
  `noalias_active ≡ own_mode == MODE_ERROR && !noalias_off`, true for
  every program (the own mode defaults to the error mode), so they fired
  on rust-edition bodies nothing had checked: `f(&mut x, &mut x)` with
  `*a = 1; *b = 2; *a` and `g(&v, &mut v)` pushing through `w` and
  reading `v.len()` twice printed `f: 2`, `g: 1` at -O0 and `f: 1`, `g:
  0` at -O2 (`-O2 --no-noalias`: `f: 2`, `g: 1`). Fixed in 0.27.1 by
  D17.7's gate (`rust_b_alias_params_O`); the program is
  `rust_b_err_alias_params` (`mut_twice`, `conflict`) once M2 lands.

### 0.2 Decisions

| | decision |
|---|---|
| Q1 | Per-instance checking with the delta's D4.4: every instance is solved, deduped by key; the region-free instance plays the template's role; the opaque instance is 0.27.2's (front272). |
| Q2 | (b): the own pass's move findings (`own.moved`, `own.partial`, `own.move_out`) are suppressed for rust-edition functions, the IR reports them (§8.4); its view findings are kept where they are not muted (today: muted, R2), with the M3 task of §8.4. |
| Q3 | The dropck container table ships (D9.1). |
| Q4 | The builder emits explicit reborrows (ir271 M2); until then D3.6's reading rule is the stopgap. |
| Q5 | Rust's capture modes in the rust edition (D10.2); the closure cases are re-spelled where 0.14's copy semantics were relied on. |
| Q6 | Both positions: an error is reported at the template's position and, when found only in a region-carrying instance, names the instance and the call that made it (§14.2). |
| Q7 | Rvalue static promotion: 0.27.3 (L2). |
| Q8 | A twin divergence is marked in the case (`// RUSTC: accepts|rejects CLASS`). |
| Q9 | `borrowck.unchecked` keeps its code; the message names the closure (D10.4); the runner's auto-`--allow` is removed. *0.27.2:* no body gets it (D19.4); the code and its explain row stay, marked 0.27.0–0.27.1. |

## 1. Places and paths (S1)

**D1.1 (place).** `P ::= L | P.f | *P | P[l] | P[k] | (P as V) | P.u`,
where `L` is a local (`PLocal`), `.f` is `PJ_FIELD k`, `*` is
`PJ_DEREF`, `[l]` is `PJ_INDEX` by local `l`, `[k]` is `PJ_CONST k`,
`as V` is `PJ_VARIANT v`, `.u` is `PJ_UNION k`. A place is the pair
`(local, proj)` with `proj` interned per body (`PProj{parent, kind,
val}`, 0: none), so equal places are equal pairs. `root(P) = L`.
`proj(P)` is the projection list from the root, outermost last.
`type(P)` is the checker's type of the sub-term reached
(`full_place_type`); a view type is `[T]` or `str` (MVS's `[T]` is
`&[T]` with one slot, D3.3).

**D1.2 (deref-like projections).** A projection `e` applied to a place
`B` is *deref-like* iff `e = PJ_DEREF` (then `type(B)` is a reference
or a raw pointer: every `PJ_DEREF` is projected on a pointer-typed
expression, verified at the builder's five sites; D3.8), or `e ∈
{PJ_INDEX, PJ_CONST}` and `type(B)` is a view type (D1.4). Its
*pointee mode* is: `shared` when `type(B)` is `&T`, `[T]` as a shared
view (`let [T]`) or `str`; `mut` when `type(B)` is `&mut T` or `inout
[T]`; `raw` when `type(B)` is a raw pointer.

**D1.3 (prefixes).** `P` is a *prefix* of `Q` iff `Q = P.π` for a
(possibly empty) projection sequence `π`. The *shallow prefixes* of `Q`
are the prefixes reached from `Q` by stripping projections until the
first deref-like projection stripped (inclusive of it: the base of that
projection is the last shallow prefix). The *supporting prefixes* of
`Q` are the prefixes reached by stripping projections, continuing
through a deref-like projection of pointee mode `mut`, and stopping
at one of mode `shared` or `raw` (its base is the last supporting
prefix: the deref of a shared reference, of a shared view, or of a raw
pointer is not supported by its base).

**D1.4 (views).** A `PJ_INDEX`/`PJ_CONST` on a place of view type, and
`RV_SLICE`'s sub-range of a view-typed base, is a deref through the
view's slot `'v` (D3.3: `slots([T]) = ['v] ++ slots(T)`): it is
deref-like (D1.2) with the view's mode; it is a supporting prefix with
`'v : 'ℓ` (D3.6), continuing through a mutable view and stopping at a
shared one; a place with one is not `frame_owned` (D6.2.2); the
place-region walk drops `'v` there (D3.3); it compares as `PJ_DEREF`
does for overlap (D1.5, D2.3). An index on an array `[T; n]` (not a
view) is an ordinary projection. The loan of such an `RV_SLICE` is of
the base's referent, one deref-like projection past the base (`v[..]`
for a view local `v`), not of the base: so `v = &v[a..]` kills it
(D2.3) and does not conflict with it (§23, Z9.5's last paragraph).
(From Z9 a rust program has no view type and this rule does not
apply.)

**D1.5 (relation of two places).** `rel(P, Q)`, for places with the
same root, is computed componentwise from the root over `proj(P)` and
`proj(Q)`; with different roots it is `Disjoint`.
- both lists exhausted: `Equal`;
- `P`'s exhausted first: `PrefixOf` (`P` is a strict prefix of `Q`);
- `Q`'s exhausted first: `Extends` (`Q` is a strict prefix of `P`),
  remembering `e`, the first projection of `P` beyond `Q`, and its
  base's type `type(Q)`;
- `PJ_FIELD k` vs `PJ_FIELD k'` with `k ≠ k'`: `Disjoint`; `PJ_CONST
  k` vs `PJ_CONST k'` with `k ≠ k'`: `Disjoint`; `PJ_VARIANT v` vs
  `PJ_VARIANT v'` with `v ≠ v'`: `Disjoint`; `PJ_INDEX _` vs `PJ_INDEX
  _` or vs `PJ_CONST _`: *may alias*, continue as if equal (R7);
  `PJ_UNION k` vs `PJ_UNION k'`: continue as if equal (a union's fields
  overlap); `PJ_DEREF` vs `PJ_DEREF`: continue; any other pair of
  different kinds does not occur (the type fixes the kind).

`Overlap(P, Q)` iff `rel(P, Q) ≠ Disjoint`. `rel_def(P, Q)` is `rel`
with `PJ_INDEX` vs anything read as `Disjoint` (definite overlap only).

**D1.6 (frame-owned).** `frame_owned(P)` iff `root(P)` is not
`LF_STATIC` and no projection of `P` is deref-like (D1.2, D1.4).

## 2. Loans and accesses (S2)

**D2.1 (loan).** A loan `ℓ = (bk, P, 'ℓ, loc₀)` is created by:
- `SK_ASSIGN (a,b) = RV_REF` with `d ∈ {BK_SHARED, BK_MUT, BK_MUT2,
  BK_FAKE}` (`ops[0]` an `OK_PLACE P`, `e = 'ℓ` the loan's region;
  `BK_FAKE` is D2.6's, *IR change (ir271 M2)*);
- `SK_ASSIGN (a,b) = RV_SLICE` of base `P`: `bk = BK_SHARED`, or
  `BK_MUT` when `type((a,b))` is `inout [T]` (`&mut [T]`).

`loc₀` is the statement's location. `BK_RAW` creates no loan (R1). The
loan table is `P_REGIONS`'s `RO_LOAN` rows, one per such statement; the
checker reads it as is. The *class* of a loan for the conflict table is
`S` (shared: `BK_SHARED`; `BK_MUT2` before its activation, D7.2;
`BK_FAKE`) or `M` (mutable: `BK_MUT`; `BK_MUT2` from its activation,
D7.3); its *kind* for code selection is `shared` (`BK_SHARED`), `mut`
(`BK_MUT`, `BK_MUT2` in either phase) or `fake` (`BK_FAKE`).

**D2.2 (accesses).** An access is `(depth, kind, Q)` with `depth ∈
{Shallow, Deep}` and `kind ∈ {RC, RB, Reserve, Activate ℓ', WB, WA,
WM, WD}` (`RC`: a read by a copy or a use; `RB`: a read by a shared
borrow; `WB`: a write by a mutable borrow; `WA`: by an assignment;
`WM`: by a move; `WD`: by a drop or a storage end). `Read` means `RC` or
`RB`. Each location performs:
- an operand `OK_COPY Q`: `(Deep, RC, Q)`; `OK_MOVE Q`: `(Deep, WM,
  Q)`; a constant operand: none — in every statement kind that has
  operands (`SK_ASSIGN`, `SK_CALL`, `SK_INTRINSIC`, `SK_ASSERT`) and in
  `TK_SWITCH`;
- the rvalue of `SK_ASSIGN (a,b) = rv`: `RV_REF P` with `BK_SHARED`:
  `(Deep, RB, P)`; `BK_MUT`: `(Deep, WB, P)`; `BK_MUT2`: `(Deep,
  Reserve, P)` at its creation and `(Deep, Activate ℓ, P)` at its
  activation location (D7.1); `BK_FAKE`: none (D2.6); `BK_RAW` of a
  `*const T`: `(Deep, Read, P)`, of a `*mut T`: `(Deep, WB, P)` (*IR
  change (ir271 M2)*: `BK_RAW` carries no mutability at v0.27.0; until
  then `Read`); `RV_SLICE` of base `P`: as `RV_REF` of `P` with the
  loan's kind; `RV_LEN P`, `RV_DISCR P`: `(Shallow, Read, P)`; other
  rvalues: their operands only;
- the destination of `SK_ASSIGN`, `SK_CALL`, `SK_INTRINSIC`:
  `(Shallow, WA, (a,b))`, after the operands' and the rvalue's;
- `SK_DROP drop(P)` with decision `DS_KEPT`, `DS_FLAG` or `DS_OPEN`:
  `(Deep, WD, P)`; `DS_REMOVED`: none;
- `SK_DEAD StorageDead(L)`: `(Shallow, WD, L)`; `SK_LIVE`: none;
- `SK_MENTION P`: `(Deep, Read, P)`; `SK_NOP`: none;
- `TK_RETURN`: the *implicit exit accesses*: `(Shallow, WD, L)` for
  every local `L ≠ _0` that has no `StorageDead` on the path reaching
  this return — the parameters `_1.._n` (verified: no parameter gets a
  `StorageDead`; every other local gets one on every exit path, the
  builder's `all_storage` being on for rust-edition bodies) — then
  `(Deep, Read, _0)`;
- `TK_GOTO`, `TK_UNREACHABLE`: none.

**D2.3 (kills).** Loan `ℓ` of place `P` is *killed* at location `loc`
iff `loc` writes a place `Q` — the destination of `SK_ASSIGN`,
`SK_CALL` or `SK_INTRINSIC`, or `StorageDead(Q)` with `Q` a local —
such that `rel_def(Q, P) ∈ {Equal, PrefixOf}` and the projections from
`Q` to `P` pass a deref-like projection (D1.2). A kill removes `ℓ` from
the in-scope set after `loc` (D2.4a step 4). The whole-local write `Q =
(L, 0)` is the common instance: it kills every loan of `*L…` and, for a
view `L`, of `L[…]`. Why the other cases are moot: a write to `Q` with
`P = Q.π` and no deref-like projection in `π` conflicts with `ℓ` (D2.5
step 2, a field extension, or `Equal`/`PrefixOf`), so the body is
rejected and the kill is never observed; a write to a prefix through a
deref overwrites the pointer and makes the loan's referent unreachable
through it, so the loan must end.

**D2.4 (in scope).** `ℓ ∈ scope(p)` iff there is a CFG path from the
mid point `2·loc₀(ℓ)+1` to `p` such that every point `q` on it
(including both ends) satisfies `q ∈ val('ℓ)` (D6.1) and no location
strictly between `loc₀` and `loc(p)` on the path kills `ℓ`. It is a
forward dataflow over points: gen `ℓ` at `2·loc₀+1`; kill `ℓ` at every
point `q ∉ val('ℓ)` and after every location of D2.3. Bitsets of loans,
per block boundary, iterated in RPO to a fixpoint.

**D2.4a (order at one location).** A statement at `loc` (start point
`2·loc`, mid point `2·loc+1`) is checked against `scope(2·loc)` in this
order: (1) the operands' accesses, in operand order; (2) the rvalue's
own access (D2.2), excluding the loan being created; (3) the
destination's `(Shallow, WA, (a,b))`; (4) the kills of D2.3 for the
destination; (5) the gen: a created loan enters `scope(2·loc+1)`. A
terminator's accesses are checked against `scope(2·loc)` in the order
D2.2 lists. A two-phase activation (D7.1) is performed after step (1),
once every operand's own access is done: a call's arguments are read
before the call activates its receiver (`s.add(s.x)` reads `s.x` while
the reservation is still shared; the IR has `copy _1.0` as an operand
of the call, not a statement before it). Consequences: `x = &mut *x`
(`x: &'x mut T`):
(2) borrows `*x` with the supporting-prefix constraint `'x : 'new`; (3)
the shallow write to `x` meets other loans of `*x…` as `Extends` through
a deref at depth `Shallow` → no conflict; (4) kills every in-scope loan
of `*x…` (the old reborrows, now unreachable); (5) the new loan survives
(gen after kill, as rustc's `statement_effect`), and `sub(&'new mut T ≤
&'x mut T)` gives `'new : 'x`, so `val('new) = val('x)`. `r = &a; r =
&b; a = 5; use(r)`: the second assignment writes `r` but does not kill
`ℓ₁` (of `a`, not reached through `r`); `ℓ₁` leaves scope anyway, by
D2.4's path rule: `r` is dead at the point after `r = &a` (its next
access is the write), so that point is not in `val('r)` nor in
`val('ℓ₁)`, and the path from `ℓ₁`'s creation to `a = 5` is cut there.
Accepted, as rustc. `ℓ₁` survives only on a path where the first value
of `r` may still be read: `r = &a; if c { r = &b; } a = 5; use(r)`, or
a loop that reads `r` before reassigning it — then `a = 5` is
`borrowck.assign_borrowed` (one region per local, not per assignment:
as rustc's NLL), and the fix is shadowing (`let r = &b;`), which the
`try:` says when the loan's holder is reassigned.

**D2.5 (conflicts).** For an access `(depth, kind, Q)` at point `p` and
a loan `ℓ = (bk, P, 'ℓ, loc₀) ∈ scope(p)` that is not the access's own
loan (the one step (2) excludes) nor the `ℓ'` of an `Activate ℓ'`:
1. `r = rel(P, Q)` (D1.5); `Disjoint` → no conflict.
2. `r = Extends` (`Q` is a strict prefix of `P`), with `e` the first
   projection of `P` beyond `Q` and `m` its pointee mode when `e` is
   deref-like on `Q`: if `e` is deref-like and `depth = Shallow` → no
   conflict (overwriting `Q` does not touch what it points to; D2.3's
   kill handles the loan); if `e` is deref-like and `m = shared` → no
   conflict (copying or overwriting a shared reference or view while
   its referent is borrowed is fine); if `e` is deref-like, `m ∈ {mut,
   raw}` and `depth = Deep` → *overlap*; if `e` is not deref-like (a
   field, a constant or variable index on an array, a variant, a union
   field) → *overlap* at any depth (a write to `Q` overwrites `P`).
3. `r ∈ {Equal, PrefixOf}` → *overlap*.
4. For a `fake` loan (D2.6) *overlap* is *shallow*: it holds only when
   `kind ∈ {WA, WB, WD}` and `r = Equal`, or `r = Extends` (`Q` a
   strict prefix of `P`) with no deref-like projection between `Q` and
   `P`; a write to a sub-place of `P` (`r = PrefixOf`), a move (`WM`: a
   later arm's test of a moved scrutinee is M1's, §8), a read or a
   borrow never conflicts with it (R10).
5. On *overlap*, by the access kind and the loan's class (D2.1):

| access | `S` | `M` |
|---|---|---|
| `RC`, `RB` | ok | conflict |
| `Reserve` | ok | conflict |
| `Activate ℓ'` | conflict unless `ℓ' = ℓ` | conflict |
| `WB`, `WA`, `WM`, `WD` | conflict | conflict |

6. The code of a conflict, `code(kind, ℓ)`, by the access kind and the
   loan's kind (D2.1; `*` any):

| access | loan kind | code | rustc |
|---|---|---|---|
| `RC` | `mut` | `borrowck.use_borrowed` | E0503 |
| `RB` | `mut` | `borrowck.conflict` | E0502 |
| `Reserve` | `mut` | `borrowck.mut_twice` | E0499 |
| `Activate`, `WB` | `mut` | `borrowck.mut_twice` | E0499 |
| `Activate`, `WB` | `shared` | `borrowck.conflict` | E0502 |
| `WA` | `shared`, `mut` | `borrowck.assign_borrowed` | E0506 |
| `WM` | `shared`, `mut` | `borrowck.move_borrowed` | E0505 |
| `WD` | `shared`, `mut` | `borrowck.dropped_borrowed`, or `borrowck.return_local` when D6.2.2 applies to `ℓ` | E0597/E0713/E0716, E0515 |
| `WA`, `WB`, `WD` | `fake` | `borrowck.guard_write` | E0510 |

`RB` covers an explicit `&x`, a `&self` autoref and a shared capture
(D10.2): rustc's E0502 for a shared borrow of a mutably borrowed place;
`RC` is a copy or a use of its value, E0503.

The loan's kind, not its class, selects the code: an `Activate` or `WB`
meeting a reserved `BK_MUT2` loan (class `S`, kind `mut`) is
`mut_twice`, as rustc's E0499 for `v.push(v.pop().unwrap())`'s inner
activation. (The delta's table named the class; this refinement only
changes which code is printed, never whether a conflict exists.) A
`Read` never meets a `fake` or an `S` loan; `Reserve` against `S` is
`v.push(v.len())`'s shape (D7.2).

**D2.6 (match guards: the fake borrow).** At v0.27.0 a guard's bindings
are bit copies into `LF_BORROWED` locals (`lower_match`:
`bind_pattern(.., true)`, printed `let borrowed _5: D // d`, `_5 = copy
(_2 as A).0`) and nothing borrows the scrutinee, so `match x { Some(y)
if { x = None; true } => .. }` meets no loan. *IR change (ir271 M2,
rust edition only):* in `lower_match`, before the first `test_pattern`,
the builder emits `_t = &'f fake S` (`RV_REF` with `d = BK_FAKE = 5`)
for the scrutinee place `S` and for every place a pattern tests (the
`discriminant P` places and the constant-compared places), and a
`mention _t` at the entry of every arm body; `_t` is `StorageDead`
after the match. A fake loan has class `S`, kind `fake` and the shallow
overlap of D2.5 step 4: it conflicts only with a write to its own place
or to a prefix of it with no deref-like step between, never with a
write to a sub-place, a read or a borrow. So `match x { (a, _) if {
x.1 = 5; true } => .. }` is accepted (only `x` is faked: no pattern
tests `x.1`) and `match x { (1, _) if { x.0 = 2; true } => .. }` is
rejected (`x.0` is tested, so it has a fake of its own), as rustc. The
`mention` keeps `'f` live through every guard (D3.7); the loan leaves
scope after the arm body's entry (`_t` is no longer live; the arm's
bindings are made after it). Guard bindings: a by-value binding stays a
borrowed copy (reads only); a `ref mut y` binding is given to the guard
as `&T` (a shared reborrow), so a write through it in the guard is a
`WB`/`WA` through a shared reference and is `borrowck.guard_write` (L6;
*inferred*: no corpus case has `ref mut` with a guard; ir271 confirms
`bind_pattern(.., true)`'s shape for it).

## 3. Regions (S3)

**D3.1 (denotation).** A region variable `'r` denotes a set `val('r) ⊆
Pts ∪ Ends`, with `Pts = {2·loc, 2·loc+1 | loc a location of the body}`
(places-ir.md §3.6: dense, so a set of points is a bitset) and `Ends =
{end('u) | 'u ∈ U}` (D4.1). `end('u)` stands for every point after the
function returns, as far as `'u` lasts.

**D3.2 (origins; the tables).** `RO_LOAN(s)`: the region of the loan
created at statement `s` (`PStmt.e` of that statement, counted from
1). `RO_LOCAL(L, i)`: the `i`-th region slot of `type(L)` for a
non-parameter local. `RO_UNIVERSAL(u)`: a signature region (D4.1),
one variable per universal, with a *binding* from each parameter slot
`slot(_k, i)` to it (so `fn f<'a>(x: &'a T, y: &'a T)` binds both
slots to one variable). `RO_CALL(s, j)`: the `j`-th region of the
callee's signature instantiated at call `s` (D3.6), `n` rows per call
with a per-call base. *IR change (ir271 M1):* at v0.27.0 `RO_UNIVERSAL`
is one per parameter slot and `RO_CALL` one per call whose destination
holds a reference.

**D3.3 (region slots of a type).** `slots(T)` is the ordered list of
region positions in `T`:
- `slots(&'a T) = slots(&'a mut T) = ['a] ++ slots(T)`;
- `slots([T]) = ['v] ++ slots(T)` (a view's region; MVS's `[T]` is
  `&[T]`); `slots(str) = ['v]`;
- `slots([T; n]) = slots(T)`; `slots((T₁..Tₙ)) = slots(T₁) ++ .. ++
  slots(Tₙ)`;
- `slots(*const T) = slots(*mut T) = slots(T)`;
- `slots(S<'a₁..'aₘ, τ₁..τₙ>) = ['a₁..'aₘ] ++ slots(τ₁) ++ .. ++
  slots(τₙ)` for a struct or enum `S` with `m` declared lifetimes
  (`lifetimes_of(S's node)`) and `n` type arguments, in declaration
  order; a type alias is expanded first;
- `slots(C)` for a closure type `C` with captures `x₁..xₖ` (D10.2) is
  the slots of its environment read as a tuple of capture fields: field
  `k` has type `&'cₖ type(xₖ)` for a by-`&` capture, `&'cₖ mut type(xₖ)`
  for a by-`&mut` capture, `type(xₖ)` for a by-value capture (*IR change
  (ir271 M2)*: at v0.27.0 captures are `&raw` and `references_in` counts
  no closure slot); 0.27.2 appends the external signature regions
  `X_C` (D19.1);
- `slots(fn(..) -> R) = []` (R6); scalars, `bool`, `()`, `Gpa`: `[]`.

*IR change (ir271 M1):* `references_in` → `slots` (today a struct's,
enum's and closure's regions are not counted). A local `L` owns one
variable per slot; `slot(L, i)` names it. The *regions of a place*
`regions(P)`, for `P = L.π`, is the sub-sequence of `L`'s slots that
`type(P)` occupies, by walking `π` from the root: a `PJ_DEREF` through
`&'a T` or `&'a mut T` drops `'a` and keeps `slots(T)`; through a raw
pointer keeps all; a `PJ_INDEX`/`PJ_CONST` on a view drops `'v` and
keeps the element's (D1.4), on an array keeps the element's (all);
`PJ_FIELD k`, `PJ_UNION k` keep the field's sub-sequence: the field's
declared type `F` with `S`'s parameters substituted, each of `slots(F)`
mapped to the parent's position (a declared lifetime `'aᵢ` to index
`i`, a slot of a type parameter `Tⱼ` to its position inside
`slots(τⱼ)`); `PJ_VARIANT v` keeps the slots of `v`'s payload, mapped
the same way. Hence `|regions(P)| = |slots(type(P))|`, positionally.
The verifier (`--verify-places`) checks `|slots(type(L))|` against the
variables bound to `L`.

**D3.4 (outlives).** `'a : 'b` ("`'a` outlives `'b`") means `val('a) ⊇
val('b)`. Constraints are generated location-insensitively; each
records the location of the statement that made it, for messages (the
blame walk, D6.2.1) and for 0.27.4's localized solve. For universals
the relation `⊒` is the declared-and-implied order (D4.5).

**D3.5 (subtyping as constraints).** For two types with the same erased
shape (TYPES erases regions), `sub(T_src ≤ T_dst)` emits, for each slot
position `i` of `slots(T_src)` (and the same `i` of `slots(T_dst)`),
with `v = var(T_src, i)` the variance of that slot in the type (D5.4):
`v = +`: `src_i : dst_i`; `v = −`: `dst_i : src_i`; `v = o`: both; `v
= *`: none. When the arguments are places, their slots are
`regions(P)`.

**D3.6 (constraints per statement and terminator).** One pass over
`P_STMTS` in RPO after elaboration (so `DS_*` decisions and flags
exist). Types are read by `full_place_type` and the slot layout, never
re-inferred.
- `SK_ASSIGN (a,b) = RV_USE op`, `op = copy Q` or `move Q`: `sub(type(Q)
  ≤ type((a,b)))` over the places' regions. A `copy` of a whole `&mut`
  place does not occur: the builder emits the reborrow `_t = &'new mut2
  (*Q)` (or `&(*Q)`) for a `&mut` passed on (ir271 M2, Q4), an ordinary
  `RV_REF` with the supporting-prefix constraint `'q : 'new` below, and
  the verifier (`--verify-places`, I7) rejects such a `copy`. (M1's
  reading of it as that reborrow was the stopgap until then; retired.)
- `SK_ASSIGN (a,b) = RV_REF P` (`e = 'ℓ`, `d ≠ BK_RAW`): loan `ℓ`
  created; `sub(&'ℓ [mut] type(P) ≤ type((a,b)))` (a `BK_FAKE` loan:
  `type((a,b))` is `&type(P)`); **the supporting-prefix rule:** for
  every supporting prefix `R` of `P` (D1.3) that is the base of a
  deref-like projection on `P`'s path, with `'q` the first slot of
  `regions(R)` (the region of the reference or view `R`): `'q : 'ℓ`.
  Through a raw pointer there is no supporting prefix, so no constraint
  (R1). `BK_RAW`: no loan, no constraint (the pointer's type has no
  slot of its own).
- `RV_SLICE` of base `P`: as `RV_REF` of `P` with result type `&'ℓ
  [T]` (slot list `['ℓ] ++ slots(T)`) and, for a view base, D1.4's
  supporting prefix.
- `RV_AGG k (ops)` with result type `A` and result slots `D =
  regions((a,b))`: for each operand `opᵢ` with the field's declared type
  `Fᵢ[D]` (the type's lifetime and type parameters replaced by the
  result's slots, as D3.3 maps them): `sub(type(opᵢ) ≤ Fᵢ[D])`. For a
  closure aggregate (`AK_CLOSURE`) the fields are D3.3's capture fields.
- `RV_CAST op as T`: both reference types (a cast that only changes the
  pointee's spelling): `sub(type(op) ≤ T)`; a reference cast to a raw
  pointer: no constraint (the loan behind `op` ends with its temporary,
  R1); otherwise none.
- `RV_REPEAT op; n`: `sub(type(op) ≤ elem)` for each slot of the
  element (one constraint set, the array's slots are the element's).
- `RV_BINARY`, `RV_UNARY`, `RV_CHECKED`, `RV_LEN`, `RV_DISCR`: none
  (the results are scalars).
- `SK_CALL (a,b) = call f(ops)` (`c = f` a function, or `c = -1` and
  `ops[0]` the callee value): let `Σ_f = (U_f, params, ret, bounds)` be
  the callee's signature regions (D4.1 for `f` as an instance; `U_f`
  includes its `Sub` regions, D4.4). Instantiate `U_f` with fresh
  `RO_CALL(s, j)` variables `'c_j` (`'static` of the callee is
  `'static`); for each argument `i`: `sub(type(opᵢ) ≤ paramᵢ['c])`;
  `sub(ret['c] ≤ type((a,b)))`; for each `'u_j ⊒ 'u_k` of the callee's
  order (D4.5, declared and implied): `'c_j : 'c_k`; for each late-bound
  region of `Σ_f` (D4.3): a fresh `'c` related only through the
  arguments. The one function `callee_regions(f)` yields `Σ_f`: for a
  rust-edition callee from its signature; for an MVS std callee from
  §12's bridge (0.27.1; from 0.27.2 a std2 callee's signature, Z4). A
  callee value of closure type `C`: `Σ` is `C`'s signature (its
  parameter types' and result's regions elided by D4.2 with the inputs
  late-bound, D10.5), and `ops[0]` is the env, read as D10.3 says
  (0.27.2: D19.5 and D20.3 replace this sentence). A callee value of a `fn`
  pointer type: `Σ` by E1-E2 at the call (R6).
- `SK_INTRINSIC`: as a call with the builtin's signature (no regions at
  0.27.1).
- `SK_DROP drop(P)` (decision `≠ DS_REMOVED`): the drop-liveness facts
  of D9.2; the access of D2.2.
- `SK_DEAD StorageDead(L)`: the kills of D2.3 and the end of `L`'s
  liveness (D3.7); `SK_LIVE`: none. `SK_MENTION`: a read. `SK_ASSERT`:
  its operands' reads. `SK_NOP`: none.
- `TK_RETURN`: `sub(type(_0) ≤ ret[U])`, `ret[U]` being the signature's
  return type with its universal regions; then the implicit exit
  accesses of D2.2, then `(Deep, Read, _0)`.
- `TK_SWITCH`: the operand's read; `TK_GOTO`, `TK_UNREACHABLE`: none.
  `TK_FALSE_EDGE`: unused (a guard's failure continues to the next arm
  by a real edge, `lower_match`; D2.6's fake loans do the rest).

**D3.7 (liveness).** For a location `loc`: `use(loc)` is the set of
locals mentioned by an operand (`OK_COPY`/`OK_MOVE`/`OK_PLACE`) or a
place of the statement, including the root of an assigned place *with*
projections and the root of a borrowed, sliced, measured (`RV_LEN`) or
discriminated place, the operand of `TK_SWITCH`, `_0` at `TK_RETURN`,
the place of `SK_MENTION`, and the root of a `drop(P)` whose `P` has a
deref-like projection (the pointer is read); `def(loc)` is the local
written whole (`SK_ASSIGN`/`SK_CALL`/`SK_INTRINSIC` with destination
`(L, 0)`) or the `L` of `StorageDead(L)`; `drop_use(loc)` is `{L}` for
`SK_DROP drop(L.π)` with `π` free of deref-like projections and
decision `≠ DS_REMOVED` (`DS_FLAG` counts: the drop may run), else `∅`.
Backward dataflow over locations in reverse RPO: `live_in(loc) =
use(loc) ∪ (live_out(loc) \ def(loc))`, `live_out(loc) = ∪
live_in(succ)` over the terminator's successors (a terminator is a
location). `L` is *use-live* at point `2·loc` iff `L ∈ live_in(loc)`,
at `2·loc+1` iff `L ∈ live_out(loc)`. The same dataflow with
`drop_use` in place of `use` gives *drop-live*: `drop_in`/`drop_out`.
Region liveness: `'r = slot(L, i)` is *live* at `p` iff `L` is use-live
at `p`, or `L` is drop-live at `p` and `'r ∈ dropck_slots(L)` where
`dropck_slots(L) = ∪ {dropck(L.π) | drop(L.π) ∈ drop_use}` mapped into
`L`'s slots (D9.1). Every universal region is live at every point (its
value, D4.5). A loan region or call region has no liveness of its own.

**D3.8 (owned derefs and containers).** A `PJ_DEREF` applies only to a
place of reference or raw-pointer type (verified: `deref_place`,
`test_pattern`, `bind_pattern`, `lower_match_switch`, `live_writes`;
Deref-trait derefs are rewritten to `*x.deref()` calls in
`front/check/rust.vl`). `Box<T>`'s and the containers' `Deref`/`Index`
go through calls (`*b.deref()`, `v.as_slice()` then D1.4), so their
loans pass through the callee's signature (D3.6's call rule; §12 at
0.27.1, std2's `fn deref(&self) -> &T` with E3's `self` region in
0.27.2). Consequences: R8 (moving out of `*b` for a `Box` is
`borrowck.move_out`, M3: no `DerefMove`); R9 closed (§0.1, D1.4).

## 4. Universal regions (S4)

**D4.1 (the set).** For a body (an item, an instance, a closure body),
`U = {'static} ∪ N ∪ E ∪ Sub`: `N` the function's named lifetimes
(`lifetimes_of(fn node)` plus the impl's, bound to each fn at `-f`);
`E` the elided input regions (D4.2); `Sub` the regions carried by the
instance's type-parameter substitutions (D4.4). `Σ_f = (U_f, params,
ret, bounds)` is the signature read with these: `params` the parameter
types with their slots bound to `U_f`'s variables, `ret` the return
type likewise, `bounds` the declared `'a: 'b` and `T: 'a`.

**D4.2 (elision, exactly).** Walk each parameter's AST type node in
parallel with its checker type (ir271's walk: a reference node's `c` is
its lifetime symbol; `bind_lifetimes`/`lifetimes_of` for generic
lists). (E1) Each elided region in an input position (an unnamed `&T`,
an `S<'_>`, an `S` whose lifetime parameters are omitted, a view `[T]`
or `str` with no name) is a fresh universal. (E2) If there is exactly
one input region position (named or elided, counting every slot of
every parameter), every elided output region is that region. (E3)
Otherwise, if some parameter is `&self`/`&mut self`, every elided
output region is `self`'s reference region. (E4) Otherwise an elided
output region is `error borrowck.elision` (rustc E0106), reported at
the signature by the front (ir271), not by the solve; the body is then
checked with a fresh universal there. `'static` in a type binds the
`'static` universal. The same rules apply to the signature of an `Fn*`
bound (`F: FnMut(&T) -> &U`) with its inputs late-bound (D4.3). When
the walk cannot name a slot (an alias, `Self`, a parameter substituted
by a reference type), the slot gets a fresh universal plus the implied
bounds (E1) and the fallback is counted (a note in the regions dump);
ir271 adds the missing case when the corpus shows one.

**D4.3 (early- vs late-bound).** A named lifetime that appears in a
`where` clause or bound (`'a: 'b`, `T: 'a`) or in a type's bound is
*early-bound*; every other named lifetime, and every elided input
region of a bound's or a closure's signature, is *late-bound*. In
0.27.1 the distinction matters only at calls: a late-bound region is
instantiated fresh per call (D3.6) and relates to nothing but through
the arguments; an early-bound region is the same at every use of the
function. Inside the callee's own body both are universals of `U`.
Explicit `for<'a>` is 0.29's.

**D4.4 (substitution regions, per instance; Q1).** Bodies are checked
per instance ("every type in a body is concrete", places-ir.md §3.1;
templates are never built). For a type parameter `T` substituted by
`τ` with `slots(τ) = ['s₁..'sₖ]`, the instance gets universals
`'s₁..'sₖ`, shared by every occurrence of `T` in the signature and the
body (so `fn f<T>(x: T, y: T) -> T` returning `x` checks for `T = &'x
i64`); `Sub` is their union over the parameters. 0.27.1 ships: (a)
every instance is solved; (b) dedupe by the key `(template,
[|slots(τᵢ)|, dropck(τᵢ) ≠ ∅]ᵢ)`: an instance whose key was seen
reuses the verdict (the same messages, the instance named per §14.2);
(c) an instance whose key has every `slots(τᵢ) = ∅` is the
*region-free instance* and plays the template's role. 0.27.2 adds (d):
an opaque instance (a synthesized argument per parameter with `slots =
[]` and no glue unless bounded by `Drop`) built and solved for every
template, so a template with no instance is checked too, and
region-free instances are deduped against it (front272: no opaque
type kind exists in `front/types.vl` at v0.27.0). The key is stable
across releases (0.27.4 checks compiler/src's many instances).

**D4.5 (implied and declared bounds; the order ⊒).** `⊒` is the least
preorder on `U` containing: `'static ⊒ 'u` for every `'u`; every
declared `'a: 'b` (generics and `where`); for every declared `T: 'a`,
`'s ⊒ 'a` for each `'s ∈ Sub(T)`; and the implied bounds of every
parameter type and of the return type, walked structurally: `&'a τ` and
`&'a mut τ` imply `'b ⊒ 'a` for every `'b ∈ slots(τ)`; a view `[τ]`
with slot `'v` likewise; `S<'a.., τ..>` implies `S`'s own declared
bounds instantiated (`Scope<'scope, 'env: 'scope>` gives `'env ⊒
'scope`) and recurses into `τ`. Values: `val('u) = Pts ∪ {end('v) |
'u ⊒ 'v}`; in particular `val('static) = Pts ∪ Ends`.

## 5. Variance (S5)

**D5.1 (the lattice).** `V = {+, −, o, *}` (co-, contra-, in-,
bivariant). `xform(+, v) = v`; `xform(−, +) = −`, `xform(−, −) = +`,
`xform(−, o) = o`, `xform(−, *) = *`; `xform(o, v) = o` for `v ≠ *`,
`xform(o, *) = *`; `xform(*, v) = *`. Meet `⊓`: `*` is the identity;
`+ ⊓ − = o`; `o ⊓ v = o`; `v ⊓ v = v`.

**D5.2 (constructors).** `&'a T`: `'a: +`, `T: +`. `&'a mut T`: `'a:
+`, `T: o`. A shared view `[T]`, `str`: `'v: +`, `T: +`; a mutable view
`inout [T]`: `'v: +`, `T: o`. MVS std's one `*T` (v0.27.0, and MVS
through 0.27): `T: +`, an owning pointer as `NonNull`/`Unique`, so
`Vec<T>` and `Option<T>` are covariant; in the rust edition, once raw
mutability is distinct (ir271 M2), `*const T`: `T: +` and `*mut T`:
`T: o`. `[T; n]`, tuples: `+`. `fn(A₁..) ->
R`: `Aᵢ: −`, `R: +`. `Cell<T>`, `UnsafeCell<T>`: `T: o`.
`PhantomData<T>`: as `T`. A closure type: each capture field as D3.3
spells it (`&'c T`: `'c: +`, `T: +`; `&'c mut T`: `'c: +`, `T: o`; by
value: `+`). A type alias: expanded first.

**D5.3 (user types).** For every struct and enum of the program
together, each parameter (lifetime or type) starts at `*`; iterate: for
each field (every variant's), walk its type with context `+`, and at
each occurrence of a parameter `X` at context `c`: `var(X) := var(X) ⊓
c`; at a constructor argument with declared variance `w` (D5.2, or the
user type's current estimate for its own parameters) the context
becomes `xform(c, w)`; repeat to a fixpoint. A parameter left `*` is
`error borrowck.unused_param` (rustc E0392): `PhantomData` is the fix
(std2's `Scope` does this). *IR change (ir271 M1):* the table
`var(S, i)` per declared parameter, computed once per program with a
rust-edition root after the structs are collected, stored in
front/types.

**D5.4 (variance of a slot).** `vars(T)` is the list parallel to
`slots(T)` of each slot's variance in `T`, by walking `T` from context
`+` with D5.2's and D5.3's constructor variances through `xform`; `var(T,
i)` is its `i`-th entry. A slot under a `*` parameter (bivariant: never
occurs for a slot that exists, by D5.3's error) is `*`.

## 6. The solve, and what an error is (S6)

**D6.1 (equations).** Given the liveness facts `Live('r, p)` (D3.7),
the constraints `C = {'a : 'b}` (D3.6) and the universals' values
(D4.5), the solution is the least assignment `val` with:
- (Liveness) `Live('r, p) ⟹ p ∈ val('r)`;
- (Outlives) `('a : 'b) ∈ C`, `'a ∉ U ⟹ val('b) ⊆ val('a)`;
- (Universal) `val('u) = Pts ∪ {end('v) | 'u ⊒ 'v}` for `'u ∈ U`,
  fixed, not grown; a constraint `'u : 'b` with `'u ∈ U` is not
  propagated but checked (D6.2.1).

Computed by: region values as bitsets of `|Pts| + |U|` bits (`Vec<u64>`
words per region); loan, local and call regions initialized from
liveness, universals fixed; a worklist over the edges `'b → 'a` of `C`,
each pop unioning `val('b)` into `val('a)` and pushing `'a`'s
successors when it grew; to a fixpoint. Monotone over a finite lattice:
terminates. This is rustc's NLL `propagate_constraints` without SCC
compression (added only if the budget of §15 fails).

**D6.2 (errors).** After the solve, in this order per body; an error
does not stop the solve, and every error of a body is reported (the
project's rule: every error of a compilation), deduped by §14.3.
1. **Universal violation** (`borrowck.outlives`; rustc "lifetime may
   not live long enough", E0621, E0623): for a constraint `('a : 'b) ∈
   C` with `'a ∈ U` and some `end('v) ∈ val('b)` with `'a ⋣ 'v`. The
   message names `'a` and `'v` (an elided region by its parameter, `'_`
   on `x`) and the location of the constraint; the blame walk follows
   `C` backwards from `'b` to the loan or universal that introduced
   `end('v)` and names that location too.
2. **A loan outliving its frame** (`borrowck.return_local`; E0515,
   E0597): D6.2.2 *applies* to loan `ℓ` of `P` iff `frame_owned(P)`
   (D1.6) and `end('u) ∈ val('ℓ)` for some `'u ∈ U`. It is not a
   separate error: it selects the code of the `(WD, ℓ)` conflict of
   D2.5 that meets `ℓ` on an exit path (the explicit `StorageDead` or
   `drop` of `root(P)`, or the implicit exit access of a parameter: a
   by-value parameter returned by reference is caught only by that
   rule). Such a conflict exists whenever D6.2.2 applies and `ℓ` is not
   killed, by the lemma: **(premise) the frame-owned root of a loan in
   scope at an exit has a `WD` access on the path to it** — an explicit
   `StorageDead` or `drop` for a non-parameter local (the builder's
   `all_storage`; a temporary made live before a `?` and left by its
   early return has none there, but is uninitialized and unborrowed
   there, so no loan of it is in scope) and the implicit exit access of
   D2.2 for a parameter — and `'ℓ : .. : 'u` gives `val('ℓ) ⊇ val('u)
   ⊇ Pts`, so `ℓ` is in scope at every point reachable from its
   creation, including that `WD`; if `ℓ` is killed on a path, the
   reference was overwritten there and nothing escapes on that path.
   The premise is a checked invariant: `--verify-places` on a
   rust-edition body reports a loan in scope at a `return` whose root
   is a non-parameter local with its storage still live there (no
   `StorageDead` on the path; `access.vl` `verify_exits`; its count on
   the corpus is 0). A loan that is
   not frame-owned (`&*x`, `&x.f`, `&s[i]` through `x: &'a T`, `s:
   &'a [T]`) carries `'a : 'ℓ` (supporting prefix), so `fn f(x: &T) ->
   &T { &*x }` yields `'a : 'ℓ : '0 : 'ret = 'a`: no `end` beyond
   `'a`'s, no error; its escape is D6.2.1's check.
3. **Access conflicts** (D2.5), each evaluated at the access's point
   with `scope(p)` from D2.4, in D2.4a's order.
4. **Moves** (§8) and **dropck** (§9).
5. **Statics.** `&S` of an immutable `static S` (an `LF_STATIC` local):
   a loan whose region is `'static` (`'ℓ := 'static`, value `Pts ∪
   Ends`), never killed (a static has no `StorageDead` and is never
   assigned); it takes part in conflicts like any shared loan (writes to
   an immutable static do not exist). `&S` and `&mut S` of a `static
   mut`: `error borrowck.static_mut_ref` (Rust 2024's rule: no
   references to a `static mut`), inside or outside `unsafe`, `try:`
   the raw address `&raw mut S` (`BK_RAW`, R1: no loan); ir271
   implements it at the front (the borrow expression's operand is a
   `static mut` item), so no loan of a `static mut` reaches the solve.

## 7. Two-phase borrows (S7)

**D7.1 (reservation and activation).** A `BK_MUT2` loan `ℓ` created at
`loc₀` into a temporary `t` (`(a,b) = (t, 0)`; verified shape: `_11 =
&'r45 mut2 _10` … `_4 = call Fmt::display(move _11, ..)`) has
*activation location* `loc_a` = the first location after `loc₀` in the
same block with an operand `move t` or `copy t`; if there is none, the
loan is never activated and stays class `S`. The builder guarantees
`loc₀` dominates `loc_a` within one block (`lower_arg`). Its access
`(Deep, Activate ℓ, P)` is performed at `loc_a` as D2.4a says.

**D7.2 (the reservation window).** For points `p` with `2·loc₀+1 ≤ p ≤
2·loc_a` (through the start point of the activation's location: its
operands are read in the window, D2.4a), `ℓ` has class `S` in D2.5. Allowed in the window: `Read` of
overlapping places, `BK_SHARED` borrows and `Reserve` of them
(`v.push(v.len())`), and reads through them; forbidden: `WA`, `WM`,
`WB`, `WD` of an overlapping place (`assign_borrowed`, `move_borrowed`,
`mut_twice`, `dropped_borrowed`), and an `Activate` of another loan of
an overlapping place (`v.push(v.pop().unwrap())`'s inner activation →
`mut_twice`, D2.5 step 6).

**D7.3 (activation).** At `loc_a` the access `(Deep, Activate ℓ, P)` is
checked against every `ℓ' ≠ ℓ` in `scope(2·loc_a)`: an overlapping
shared or reserved loan conflicts (`v.push(v.last().unwrap())` when
`last` returns `&T` whose loan is still live: it is, since the
argument's region reaches the call); from `2·loc_a+1` on (the mid point
of the activation's location), `ℓ` has class `M`. The loan's region
starts at `loc₀` (it is in scope from its creation), as rustc's.

**D7.4 (which borrows are two-phase).** Autoref'd receivers
(`lower_arg`: `i == 0 && arg.start == operand.start`), the `IndexMut`
autoref of `c[i] = ..` (the rewrite to `*c.index_mut(i)` makes it a
receiver; ir271 confirms), and the implicit reborrow of a `&mut` local
at an argument position once the builder emits it (D3.6, ir271 M2).
Explicit `&mut x` arguments are not two-phase (rustc rejects
`f(&mut v, v.len())`).

## 8. Moves and initialization (S8)

**D8.1 (move paths).** As `places/elab.vl` (`trackable`, `path_of`,
`whole_only`): a tree per trackable local (not `LF_STATIC`,
`LF_BORROWED`, `LF_FLAG`), a child per field and per variant payload;
no path through `PJ_DEREF`, `PJ_INDEX`, `PJ_CONST`, `PJ_UNION`, or
below a type with `impl Drop` (whole-only). `path(Q)` is `Q`'s path or
none; `base(Q)` the nearest ancestor place of `Q` that has a path, or
none.

**D8.2 (dataflows).** `MaybeInit(m, p)` and `MaybeUninit(m, p)` over
paths, forward in RPO (elab.vl's, gen/kill bitsets per block): a
`SK_ASSIGN`/`SK_CALL`/`SK_INTRINSIC` to `(a,b)` initializes
`path((a,b))` and its subtree; an `OK_MOVE Q` uninitializes `path(Q)`
and its subtree; `drop(P)` and `StorageDead(L)` uninitialize. On
entry: the parameters' paths initialized, every other path
uninitialized. `DefInit(m, p) ≝ ¬MaybeUninit(m, p)`. The checker runs
these on every rust-edition body: elab's fast path (no needs-drop
local: no paths) does not exempt a body from §8 (a glue-free non-`Copy`
struct is moved too), so the paths are built for the body when elab
skipped them.

**D8.3 (rules).** Each an `error borrowck.use_moved` (rustc E0382)
unless named, at the access's statement.
- (M1) A `Read`, a `WB`/`Reserve`/`Read` by a borrow, an `OK_MOVE`, or
  an `SK_MENTION` of `Q` at `p` with `path(Q) = m` requires `DefInit(m',
  2·loc(p))` for `m` and every descendant `m'` (deep); when `Q` has no
  path (through `*`, an index, a union), it requires `DefInit` of
  `base(Q)`; with no base, no check. A discriminant read (`RV_DISCR`)
  is not checked: elaboration's opened drops read the tag of a
  partially moved enum, and a `match` on a moved enum is caught at its
  payload's read; a length read (`RV_LEN`) requires `DefInit(m)` of
  the path alone (shallow, as D2.2 says). A place reached through a raw
  pointer (a deferred closure body's env, D10.4; none from 0.27.2,
  D19.4) is not checked (R1).
- (M2) `SK_ASSIGN`/`SK_CALL`/`SK_INTRINSIC` with destination `Q =
  L.π`, `π ≠ ∅`: requires `DefInit` of every strict-prefix path of `Q`;
  a prefix that was initialized and then moved (`MaybeUninit` by a move,
  `let q = p; p.a = 1;`) is `borrowck.use_moved` (E0382), a prefix never
  initialized on some path (`let p: P; p.a = 1;`) is
  `borrowck.assign_moved_part` (E0381 "partially assigned"); then
  initializes. `Q = (L, 0)`: no requirement (reinitialization), and it
  kills `L`'s loans through a deref (D2.3).
- (M3) An `OK_MOVE Q` whose path does not exist because `Q` goes
  through a `*` (a reference, a raw pointer, a `Box`'s deref call:
  R8), an index on a view, array or `Vec`, a static, or an
  `LF_BORROWED` local: `borrowck.move_out` (rustc E0507/E0508). MVS
  keeps `own.move_out` (`diff.vl`'s backstop) unchanged.
- (M4) An `OK_MOVE` of a strict sub-place of a value whose type has
  `impl Drop` (whole-only): `borrowck.move_from_drop` (E0509).
- (M5) A path moved in one iteration and used in the next is M1's fact
  (`MaybeUninit` at the loop head by the back edge); the message adds
  "in a previous iteration of the loop" when the move's location is
  reachable from the use's.
- (M7) An assignment (`WA`) to a whole local `L` (`(L, 0)`) that is
  not `mut` (no `LF_MUT`) requires `¬MaybeInit(path(L), 2·loc)`: a
  deferred `let x;` / `let x: T;` is assigned once on every path
  (`borrowck.assign_twice`, rustc E0384 "cannot assign twice to
  immutable variable"); an assignment inside a loop fails it by the
  back edge, one on each branch of an `if` passes. The plain `let x =
  1; x = 2;` is the front's ("cannot assign to immutable variable"), so
  only a deferred local reaches this rule.
- (M6) A move of a `Copy`-typed place is a copy: the builder emits
  `OK_COPY`, so no rule applies.

**D8.4 (who reports; Q2(b)).** For a rust-edition function the IR
dataflow (bc271 M3) reports `borrowck.use_moved`, `assign_moved_part`,
`move_out` and `move_from_drop`; the own pass's `own.moved`,
`own.partial` and `own.move_out` are suppressed for it (today they
fire: §0.1), so no body gets both. The own pass's view findings
(summaries, `own.conflict`, escapes) are muted on rust bodies at
v0.27.0 (`ocx.quiet`): **M3 task:** unmute them for rust bodies on the
corpus; if they agree with borrowck or only add true positives, keep
them (Q2(b) as intended); if they add false positives, leave them muted
and count the hole (R2). Also M3's: `own.drop_view` (an `impl Drop` on
a type holding a reference, MVS's rule) is suppressed for rust-edition
types, where dropck (§9) is the rule: `let x = 1; let d = D { r: &x };`
with `impl Drop for D` is accepted when `x` outlives `d`'s drop and
`borrowck.dropped_borrowed` when it does not. R2 closes in 0.27.2 with
std2 (every type
declares its regions; the own pass is off for the rust edition).

## 9. Drops and dropck (S9)

**D9.1 (dropck regions).** `dropck(T)` is the set of `T`'s slots that
must be live when a value of type `T` is dropped:
- `T` with no drop glue (`type_glue`): `∅` (every reference, view, raw
  pointer, scalar, `str`, `fn` type);
- `[T; n]`, tuples: `∪ dropck(elem)` mapped to the slots;
- a struct or enum **without** `impl Drop`: `∪ dropck(field type)` over
  all fields of all variants, mapped by D3.3's substitution;
- a struct or enum **with** `impl Drop`: `set(slots(T))`, every region
  of the type (rustc's rule without `#[may_dangle]`, L1), **except the
  compiler-known containers** (the table: MVS std's `Vec`, `String`,
  `HashMap`, `HashSet`, `BTreeMap`, `BTreeSet`, `BinaryHeap`,
  `MinHeap`, `VecDeque`, `Box`, keyed by the std item; std2's of the
  same names), for which it is `∪ dropck(τ)` over the *element* type
  arguments plus `set(slots(A))` of the allocator argument (an
  allocator reference must be live to free). `Allocator::FREES` does
  not change it: a non-freeing allocator's container still has glue;
- a closure type: `∪ dropck(type(xₖ))` over its by-value captures (a
  struct without `impl Drop`, D3.3).

**D9.2 (the rule).** At `SK_DROP drop(P)` with decision `≠
DS_REMOVED` at location `loc`: `Live('r, 2·loc)` for every `'r ∈
dropck(type(P))` mapped into `regions(P)`: a liveness fact (D3.7's
drop-liveness), not a constraint. Consequently a loan whose region
reaches such an `'r` is in scope at `2·loc`, and an earlier
`StorageDead` or `drop` of its place conflicts (D2.5, `WD`) →
`borrowck.dropped_borrowed`.

**D9.3 (what the table changes).** With it: `let mut v = Vec::new_in(a);
let x = 1; v.push(&x);` is accepted (rustc accepts: `Vec`'s
`#[may_dangle]`), and `x`'s `StorageDead` before `v`'s drop is no
conflict since `'x` (the element's region) is not in `dropck(Vec<&'x
i64, A>)`; without it the case is rejected and the translator would
have to reorder declarations. A user type with `impl Drop` holding
`&'x T` keeps rustc's stable rule: `x` must outlive the drop. The
container table is the one place the checker knows a std item by name
in 0.27.1.

## 10. Closures (S10)

**D10.1 (captures as places).** A closure captures whole variables only
(disjoint-field capture is 0.29's; L7): capture `k` is the place `(xₖ,
0)` of the enclosing body.

**D10.2 (the capture mode; Q5).** For a rust-edition closure, capture
`k` is *by value* if the closure is `move`, or if the body moves `xₖ`
(an `OK_MOVE` of a non-`Copy` `xₖ` or of a sub-place of it); else *by
`&mut`* if the body writes `xₖ` (an assignment to `xₖ` or a sub-place,
or a `drop` of it) or takes `&mut xₖ`/`&mut2 xₖ` (of it or a
sub-place); else *by `&`*. (0.14's "an immutable binding is captured by
value" copied a non-`Copy` value — a move in Rust's terms; the closure
cases are re-spelled with `move` where they relied on it.) *IR change
(ir271 M2):* the `aggregate closure` operands for by-reference captures
become `RV_REF` borrows `_t = &'cₖ xₖ` / `&'cₖ mut xₖ` into temporaries
(loans, D2.1; today `&raw xₖ`, `BK_RAW`, no loan) moved into the
aggregate, and `slots(C)` is D3.3's, each capture's loan region flowing
into the closure value's slot by `RV_AGG`'s rule (covariant). By-value
captures are `OK_MOVE`/`OK_COPY` operands as today.

**D10.3 (what the capture side gives).** With D10.2 the enclosing body
is checked exactly as rustc checks it: the closure value's liveness
keeps its capture loans in scope (`c += 10` while `bump` is live and
used later → `borrowck.assign_borrowed`; `move || n` moves or copies
`n`). A call of a closure value `c` (`call closure(..)(move _6, ..)`
with `_6 = &raw _3` at v0.27.0) is a reborrow of the closure: the env
operand is `&'e c` for an `Fn` closure, `&'e mut2 c` (two-phase, a
receiver) for `FnMut`, the kind inferred from the body (a write through
a by-`&mut` capture, or a `&mut` of one, → `FnMut`; else `Fn`; `FnOnce`
is 0.27.2's). *IR change (ir271 M2):* `&raw _3` → `RV_REF` of the
closure local with that kind. The callee's signature at that call is
D3.6's closure-value rule. *0.27.2:* the kind is D19.3's and the call
D19.5's.

**D10.4 (the closure body, deferred; superseded in 0.27.2 by D19.4).** The body's env stays `_1:
*closure` (raw) in 0.27.1; captured places `(*(*_1).k)` are reached
through a raw deref, so a borrow inside gets no supporting-prefix
constraint, and the body's loans of captured places are checked only
against each other and the body's own locals. Soundness holds because
D10.3 keeps the captured places borrowed for the closure value's
lifetime in the enclosing body (the env cannot outlive its captures;
0.14's escape check remains the backstop for a closure value escaping).
Such a body gets `warning borrowck.unchecked` (Q9) whose message names
the closure and its first captured variable, so the count of deferred
bodies is a gate number (≤ 10 on the corpus; the cases carry `//
WARNING: borrowck.unchecked`). 0.27.2 replaces the env by `&Env`/`&mut
Env`/`Env` per `Fn`/`FnMut`/`FnOnce` with universal regions `'cₖ` in
the body.

**D10.5 (late-bound regions in a closure's signature, deferred;
superseded in 0.27.2 by D20.3).** `|x:
&T| ..` has a late-bound input region: inside the body it is a
universal nothing outlives (returning `x` or storing it into a capture
is `borrowck.outlives`); 0.27.1 checks the closure body's parameters as
ordinary elided universals (E1), which is the same for non-escaping
uses and more permissive for escaping ones (R4). At a call of the
closure the region is instantiated fresh (D3.6, D4.3), as it should be.

## 11. Soundness, and the divergences from rustc (S11)

**Invariants of an accepted body.**
- (I1, provenance) Every reference value held in place `Q` at point `p`
  with slot region `'q` was produced by a loan `ℓ` (or entered through
  a universal `'u`) such that `'ℓ : … : 'q` by constraint paths: D3.6
  covers every statement that moves a reference between places
  (`RV_USE`, `RV_REF`, `RV_SLICE`, `RV_AGG`, `RV_CAST`, calls, returns),
  and projections through fields, derefs and view indexes are
  sub-sequences of slots (D3.3).
- (I2, liveness) If `Q` is use- or drop-live at `p` then `p ∈ val('q)`
  (D3.7), hence `p ∈ val('ℓ)` (D6.1 Outlives), hence `ℓ ∈ scope(p)`
  unless killed — and a kill (D2.3) overwrites a pointer on the path
  from `Q`'s root to `P`, after which (I1) no longer attributes the old
  value to `Q`.
- (I3, exclusivity) Two loans `ℓ₁` (class `M`) and `ℓ₂` of overlapping
  places are never both in scope at a point: creating the later one is
  a `WB`/`Reserve`/`Activate` access that conflicts with the earlier
  one in scope (D2.5), so the body was rejected.
- (I3′, reborrow chains) While a loan `ℓ` of `*r…` (`r: &'r mut T`) is
  in scope, any access to `r` itself is `rel(P_ℓ, r) = Extends` with
  first extra projection a deref of mode `mut`, so a `Deep` access
  (copy, move, `&r`, `&mut r`) conflicts (D2.5 step 2) and a `Shallow`
  write (`r = …`) does not conflict but kills `ℓ` (D2.3). Hence the
  chain `r → ℓ → …` is linear: at most one live path to `*r` through
  `r` at a time.
- (I4, no dangling) A loan's place `P` is not freed or overwritten while
  the loan is in scope: `StorageDead`/`drop`/assignment/move of `P` or
  of its overlapping prefixes are `W*` accesses conflicting with every
  in-scope loan of `P` (D2.5; the `Extends` rule distinguishes a
  shallow overwrite of a pointer from its referent). A reference
  escaping the function carries `end('u)` and is rejected unless its
  loan is of a place reached through a universal region that
  `⊒`-outlives `'u` (D6.2.1-2); the supporting-prefix rule (D3.6) makes
  a reborrow through `&'q` (or a view `'v`) inherit `'q : 'ℓ`, so the
  escaping region is `'q`'s and the universal check applies.
- (I5, two-phase) A reserved loan has class `S` until its activation
  and `M` after; the activation re-checks exclusivity (§7), so (I3)
  holds across the window.
- (I6, initialization) Every read is of a definitely-initialized path
  (§8), so no value is read after its move; elaboration already drops
  each value at most once.
- (I7, no duplicate `&mut`) The IR never copies a whole `&mut` place
  except as a call argument (verified), where D3.6 reads it as (after
  ir271 M2: the builder emits) the reborrow `&'new mut (*Q)`, a loan
  subject to I3′; so no two `&mut` values to one place exist without one
  being a reborrow of the other, and the reborrow's region is bounded
  by the outer reference's (`'q : 'new`).

- (I8, closure bodies; 0.27.2) §19's soundness paragraph: with the
  env a reference or a value (D19.4) and the requirements (D19.10),
  I1–I7 hold for a closure body as for any body.

From I1-I8: a use of a reference at `p` reads an object that is
initialized, not freed, and (for `&mut`) not aliased by another in-scope
reference: no aliasing violation of `&mut` and no dangling reference,
outside the holes named below.

**Deliberate permissiveness (more than rustc), each with its reason.**
- R1 `BK_RAW` (`&raw`, `as *const`) creates no loan and is a read (a
  write for `*mut` after ir271 M2); what happens through the raw
  pointer is `unsafe`'s. Reason: Rust's rule is the same.
- R2 MVS std types holding hidden views (`SliceIter<T>`, `Scanner`, …)
  have no slots, so a loan feeding them ends at the call; and the own
  pass's view findings are muted on rust bodies at v0.27.0 (§0.1), so
  these uses are **unchecked in 0.27.1** unless §8.4's M3 task unmutes
  them. The hole is counted: the corpus's cases that depend on it carry
  `// RUSTC: rejects R2`, and the gate prints their number. Reason:
  std2 replaces MVS std in 0.27.2 with declared regions; a one-release
  bridge. *Closed in 0.27.2* (Z4, Z7, Z8).
- R3 Per-instance checking (D4.4): a generic body rustc rejects for
  lacking `T: 'a` is accepted until an instance whose `T` carries
  regions exists, then rejected at that instance (the instance named).
  A template never instantiated is unchecked in 0.27.1 (as typeck
  leaves it; D4.4(d) closes it). Soundness: an instance's errors depend
  on its type arguments only through `slots(τᵢ)`, `dropck(τᵢ)` and the
  implied bounds of the signature's types, which the key captures (the
  variance of `S<τ>` is `S`'s, independent of `τ`; move paths depend on
  glue, which the key's drop bit captures), so solving one instance per
  key is complete for the instances that exist.
- R4 Closure bodies through a raw env (D10.4) and closure parameters
  not late-bound (D10.5). Reason: deferred to 0.27.2 with `Fn*`.
  *Closed in 0.27.2* (D19.4, D19.10, D20.3).
- R5 `edition.lenient` leniencies of 0.19's meanings (a `&T` of a plain
  value where `T` goes; a place where `&T` goes): closed by ir271 in
  0.27.1; after it, none.
- R6 `fn` pointer types carry no late-bound regions (D3.3). Reason: no
  `for<'a>` until 0.29; a `fn(&T) -> &U` value's call uses E1-E2 at the
  call.
- R7 Constant index projections `P[k]` vs `P[k']` with `k ≠ k'` are
  disjoint (D1.5), so `&mut a[0]` and `&mut a[1]` may coexist on an
  array and through a `&mut [T]`; rustc rejects both (only slice
  patterns are disjoint there). Sound, since the elements do not
  overlap, and more permissive. `P[i]` vs `P[j]` by locals may alias,
  as rustc.
- R8 Moving out of `*b` for a `Box` is `borrowck.move_out` (M3): no
  `DerefMove` (rustc allows it for `Box` only). A strictness in effect;
  listed with R-ids as the delta named it.
- R9 `&v[i]` on an MVS `Vec`: closed by D1.4 (§0.1); kept as a name so
  a case that pins the shape can cite it.
- R10 Fake borrows (D2.6) conflict only with `WA`, `WB` and `WD` (as
  rustc); a move of the scrutinee in a guard is not theirs: it is the
  move dataflow's at the next arm's test, which is L8.
- R12 A by-`&` capture of a variable whose type is a shared view (`[T]`,
  `str`: MVS's `&[T]`, which `&&[T]` collapses to) is a copy of the
  view into the closure, not a loan of the variable, until Z9 (ir271):
  sound, since a shared view is `Copy` and immutable, and the view's own
  region is carried by the copy; a reassignment of the variable while
  the closure is live is then not a conflict (rustc: it is). Reason:
  the `&&'a str` front gap (§13); ends with it. *Closed in 0.27.2*
  (Z9.6).
- R11 An MVS std type is `Copy` in the rust edition when it has no drop
  glue and `Copy` type arguments (`places::regions::rust_copy`), so
  `Range<i64>` is `Copy` here and a range used twice is a copy, not a
  use after a move as in rustc. Reason: MVS std declares no `Copy`;
  ends in 0.27.2 with std2's types. *Closed in 0.27.2* (Z7.1).

**Deliberate strictness (less than rustc).**
- L1 Dropck without `may_dangle` for user `impl Drop` types (as rustc
  on stable); std containers through the table (§9).
- L2 No rvalue static promotion: `let r: &'static i64 = &3;` is a
  temporary of its statement here (vole's temporaries, places-ir.md
  §3.7) → `borrowck.dropped_borrowed` at the temporary's `StorageDead`
  (rustc's E0716 for a temporary); rustc promotes. Q7: 0.27.3.
- L3 Temporaries' scopes are vole's (the statement; the block for `let
  r = &f(x)`), not Rust 2024's tail-expression rule: a difference only
  in `match`/block tail temporaries.
- L4 NLL only: problem case 3 (a conditional return of a borrow) is
  rejected as rustc's NLL does; the location-sensitive solve is
  0.27.4's. Also rustc's NLL limitations shared on purpose: one region
  per local, so a reassigned reference whose first loan survives on
  some path keeps that loan (D2.4a's conditional and loop examples; a
  plain `r = &a; r = &b` is accepted).
- L5 Opaque (`impl Trait`) regions invariant (0.27.2).
- L6 A guard's `ref mut` binding is read-only in the guard (as rustc:
  E0594 in guards; here `borrowck.guard_write`).
- L7 A closure captures whole variables (D10.1, Rust 2018's rule):
  `move || nn.v` captures `nn`, not the field, so a use of `nn.w` while
  the closure is live conflicts; Rust 2021's disjoint-field capture is
  0.29's.
- L8 A guard that moves the scrutinee (or a tested place) and then
  fails makes the next arm's test a read of a moved place, which M1
  rejects (`borrowck.use_moved`); rustc accepts, since it decides every
  discriminant before any guard runs. `lower_match` tests arm by arm
  and re-tests after a failed guard; the fix would be a decision-tree
  lowering, not planned. Case `rust_b_err_guard_move_then_test`.
- L9 (0.27.2) No higher-ranked subtyping of closure and `fn` values
  (D20.5): a value is accepted for an `Fn*` bound only if its signature
  matches up to a renaming of bound regions; rustc also instantiates a
  `for<'x>` value at an early-bound `'a`. Reason: no `for<>` until 0.29.
  (L10–L12 are reserved for 0.27.2.1's §21–§22.)

## 12. The MVS std boundary (S12, 0.27.1 only)

*Deleted in 0.27.2* (Z4): a rust program loads std2, whose functions'
`Σ_f` are D4.1's; `edition.std_copy` and `edition.std_by_value` retire
(their explain rows say 0.27.0–0.27.1). The text stays as 0.27.1's
record.

**D12.1 (conventions as types).** For an MVS std callee: a `let`
parameter of a compound type is `&'p T` (one slot `'p`), of a plain type
a copy (no slot); `inout T` is `&'p mut T`; `sink T` is `T`; a `[T]` or
`str` parameter is a shared view (one slot); a result `[T]`/`str` has
one slot; any other std result type has `slots = []` in 0.27.1 (R2). A
`Gpa`/allocator argument has no slot.

**D12.2 (the bridge: `callee_regions` of a std fn).** `Σ_f` for an MVS
std `f`: every parameter slot is a distinct universal (E1); the result's
slots relate by `front::own::summary::summary_of(f)` (`ViewSummary{ret,
sto, top, declared}`): for the result's level-1 slot `'o` and each
parameter `i` in `ret[S_L1_P]`: `'pᵢ : 'o` (the argument's own region);
in `ret[S_L1_STAR]`: every slot of `*pᵢ` outlives `'o`; the level-2
masks likewise for the result's nested slots; `top`: every reference
argument's slots outlive every result slot; an empty summary: the result
borrows nothing (`Vec::len`). `sto` masks become constraints from the
stored argument's slots into the `&mut` parameter's referent slots
(`'arg : 'referent`). `as_slice`/`as_mut_slice` (D1.4's shape) are
`ret[S_L1_P]` of `self`, so `&v[i]`'s loan ties to `v`. A std callee's
universal is *its call's* `RO_CALL` variable; nothing in MVS std's body
is solved. When the corpus shows false positives from `top`, the
per-callee fallback is a `#[views]` pin on the std item; if widespread,
the bridge narrows to "self/first-reference-argument only" and R2
grows. This bridge is deleted in 0.27.2.

**D12.3 (the two typeck codes).** `edition.std_copy` (`*x` of a getter's
copy) and `edition.std_by_value` (`&x` where std takes the value) are
front errors before the IR exists; no loan is involved. A std `let` of
a plain `T` given `&x` is read as a copy of `*x` (no loan outlives the
call).

## 13. Where the IR at v0.27.0 cannot express a rule (ir271's list)

| # | what | rule | milestone |
|---|---|---|---|
| 1 | `slots` for structs, enums, closures; `regions(P)` | D3.3 | ir271 M1 |
| 2 | one universal per signature region, slots bound to it; `'static`; elision at the signature | D3.2, D4.1-4.2 | ir271 M1 |
| 3 | `RO_CALL` per callee region, a per-call base | D3.2, D3.6 | ir271 M1 |
| 4 | the variance table `var(S, i)` | D5.3 | ir271 M1 |
| 5 | the regions dump (`--emit-places=regions`), §16 | — | ir271 M1 (format), bc271 M1 (content) |
| 6 | `&&` token; `edition.lenient` closed (R5) | — | ir271 M1 |
| 7 | `BK_RAW` mutability (`*const`/`*mut` distinct) | D2.2 | ir271 M2 |
| 8 | captures as borrows; the closure call's env reborrow | D10.2-10.3 | ir271 M2 |
| 9 | explicit reborrow `&'new mut (*Q)` for a `&mut` passed on; the verifier's "copy of an exclusive reference" | D3.6 | ir271 M2 |
| 10 | `BK_FAKE = 5`, the guard's fake loans and mentions; `ref mut` guard bindings as `&T` | D2.6 | ir271 M2 |
| 11 | `borrowck.static_mut_ref` at the front | D6.2.5 | ir271 M2 |
| 12 | `T_BORROWCK = 25`, `T_COUNT = 26` in `base/timer.vl` | §15 | bc271 M1 |
| 13 | `--verify-places`: every non-parameter local has a `StorageDead` on every exit path (D6.2.2's premise); "copy of an exclusive reference" after row 9 | D6.2.2, D3.6 | bc271 M2 |
| 14 | `AS_DISCHARGED`: a decision field on `SK_ASSERT` and the contract conjunct's switch (`AS_UNDECIDED=0, AS_KEPT=1, AS_DISCHARGED=2, AS_REFUTED=3`), printed as `; L1: ..` (empty), reserved for the Level 1 verdicts of the contracts design | §17 | ir271 M1 (reserved) |
| 15 | `f$checked`: what an `OK_FN f` of a contracted function names (the checking entry `fn f$checked(<params>) -> R { f$pre(SITE_INDIRECT, <params>); f(<params>) }`); D17.6's exception (a) applies to it when it is the exported symbol | D17.6 | ir272 (named now) |
| 16 | `where 'a: 'b` bounds read into the universals' order (D4.5) | D4.5 | ir271 M2 |
| 17 | the env parameter per kind (`&'e C`, `&'e mut C`, `C`); the call's access by the call kind and its adapters; `move` of an `FnOnce` callee | D19.4, D19.5 | clos272 M1 |
| 18 | `X_C`: the external signature regions as slots of `C`; bound regions `B_β` in a closure body | D19.1, D20.3 | clos272 M2 |
| 19 | the requirement table per closure type, read by the enclosing body's constraint pass at `RV_AGG AK_CLOSURE` | D19.10 | clos272 M2 |
| 20 | unsized places behind a pointer; `RV_LEN (*p)`; `RV_SLICE` of `(*p)`; reborrows of `&mut [T]` | Z9 | clos272 M3 |

ir271 M1's findings, recorded: `&&'a str` collapses to the view (a
known front gap, with a corpus case); an instance's `Fn` node is a clone
with `g = 0`, so the signature walk (`sig_of`) reads the template's
node; the region rows are four words and `RO_CALL` has one row per
callee region with the call's base in its `PStmt.e`.

Not needed: `TK_FALSE_EDGE` (verified), an unwind edge (panics exit).

## 14. The codes and the diagnostics

### 14.1 The codes

All errors unless marked; each has an `Explain` row in
`tools/explain/borrowck_table.vl` (the shape of `edition_table.vl`) and,
where a `try:` is named, a case in `tests/borrowck-try/NAME/main.vl`
(`// CODE: borrowck.x`, `// TRY: ...`).

| code | fires (rule) | rustc | `try:` |
|---|---|---|---|
| `borrowck.mut_twice` | D2.5: `Reserve`/`Activate`/`WB` vs a `mut` loan | E0499 | none mechanical; the help names both borrows |
| `borrowck.conflict` | D2.5: `Activate`/`WB` vs a `shared` loan; `RB` vs a `mut` loan | E0502 | `let n = v.len(); v.push(n)` when the shared loan is an argument of the same call (the own pass's `for_push`-style try, reused) |
| `borrowck.use_borrowed` | D2.5: `RC` vs a `mut` loan | E0503 | none |
| `borrowck.assign_borrowed` | D2.5: `WA` vs any loan | E0506 | shadowing (`let r = &b;`) when the loan's holder is reassigned on the path that keeps the loan in scope (D2.4a's conditional and loop shapes); else none |
| `borrowck.move_borrowed` | D2.5: `WM` vs any loan | E0505 | `.clone()` when `T: Clone` (as `own.moved`'s) |
| `borrowck.dropped_borrowed` | D2.5: `WD` vs a loan; D9.2 | E0597, E0713 | "declare `x` before `v`" when both are locals of one block (the reorder is mechanical: `fix` moves the `let`) |
| `borrowck.return_local` | D6.2.2 | E0515 | none; the help suggests returning an owned value |
| `borrowck.outlives` | D6.2.1; D19.10 case 1 | E0621, E0623, E0521 | "add `'a: 'b`", or "name the lifetime `'a` on `x`" when the blame path ends at two parameters of elided regions (E2 failed): `fix --suggested` writes `<'a>` on both |
| `borrowck.elision` | E4 at the signature (ir271) | E0106 | writes `<'a>` and `&'a` on the only reference parameter when there is one |
| `borrowck.unused_param` | D5.3 (ir271) | E0392 | adds a `PhantomData<&'a ()>` field |
| `borrowck.use_moved` | M1, M5 | E0382 | `.clone()` when `Clone` (as `own.moved`'s) |
| `borrowck.assign_moved_part` | M2 | E0381 | none |
| `borrowck.assign_twice` | M7 | E0384 | `let mut x;` on the deferred declaration |
| `borrowck.move_out` | M3 | E0507, E0508 | `.clone()`, or `&` the place (as `own.move_out`'s) |
| `borrowck.move_from_drop` | M4 | E0509 | none; the help names `mem::take`/`Option::take` |
| `borrowck.guard_write` | D2.5 vs a `fake` loan; L6 | E0510, E0594 | none; the help says to write after the match |
| `borrowck.static_mut_ref` | D6.2.5 (ir271) | the `static_mut_refs` lint (no E-code in 1.98) | `&raw mut S` |
| `borrowck.unchecked` (warning) | D10.4 only | — | kept from 0.27.0; the message names the closure. Retired in 0.27.2 (D19.4): fires on no body |
| `closure.kind` (0.27.2, the front) | D19.6; D19.3(c) | E0525; E0594, E0596 | none; the help names the bound to relax, or `.clone()` before the closure |
| `closure.sig` (0.27.2, the front) | D20.3, D20.5 | E0631 | none |
| `sync.not_send`, `sync.not_sync` (rust edition, 0.27.2) | AT3 | E0277 | none |

Eighteen `borrowck.*` codes (`assign_twice` from M3's rest, with
ir271's deferred `let`); 0.27.2 adds the front's `closure.*` two and
reuses `sync.not_send`/`not_sync` for AT3; rustc's E0521 and its
uncoded "lifetime may not live long enough" and "captured variable
cannot escape `FnMut` closure body" map to `borrowck.outlives`. The rustc column is the twin's map
(`tools/borrowck-twin.sh`): a rejecting case's first `error[E0xxx]` must
map to the case's expected code, or the case carries `// RUSTC:`.

### 14.2 Positions and instances (Q6)

An error's primary position is the access's statement node
(`PStmt.node`) — for a conflict the later access, for a move rule the
use, for a universal violation the constraint's statement; its
secondary position is the loan's statement node ("borrowed here"), and
for a move the move's. An error of an instance is reported at the
template's position. When the instance is the region-free one (D4.4(c))
or the body is not generic, nothing more is said; when it is found only
in a region-carrying instance, the message adds the instance (`in
f<&'x i64>`) and the call that made it (the instantiation's node).
Positions of std items are `<std>:L:C` in transcripts. The moves'
messages point at AST nodes because `fix` edits by node (0.27.3).

### 14.3 Dedupe

One error per `(loan, access place, code)` in a body (a loop reports
one conflict, not one per iteration path); one `borrowck.outlives` per
`('a, 'v)` pair; one `return_local` per loan; one `use_moved` per
path (its first use in location order, as the own pass reports once
per local), none for a use after a move reported `move_borrowed`; the
per-instance dedupe of D4.4(b). A body's errors are reported in
location order.

## 15. Timing and the budget

`T_BORROWCK` (liveness + constraints + solve + scope + accesses + moves
+ dropck) is taken out of `T_CHECK` as `T_PLACES_BUILD` is and printed
as `borrowck` by `--time-passes`. The rule: `T_BORROWCK ≤ ¼ · (T_CHECK
− T_OWN − T_PLACES_* − T_EFFECTS)` summed over the rust corpus, both
sums printed, and the largest case's ratio; on compiler/src `borrowck
0.0 ms` (nothing runs for MVS). MVS compile cost ≤ 1.03x 0.27.0
(`tests/compile_cost.sh`); its new `rust` row ≤ 1.5x. Inside borrowck:
liveness ≤ 30%, the solve ≤ 40%, scope and accesses ≤ 30%. If the
quarter fails: SCC compression first, then sparse values (interval
lists) for bodies over 512 points; the accesses × loans product is
capped by indexing loans per root local.

## 16. The regions dump (to agree with ir271)

`check --emit-places=regions` prints, per body after `--emit-places`'s
locals and `region 'rN: origin` lines (ir271's format for the tables:
`region 'r3: universal 'a (_1.0, _2.0)`, `region 'r9: call bb0[12].1`),
the solve's sections after the body's text, each line pinnable by a
`PLACES:` directive (`// FLAGS: --emit-places=regions` in the case; M1's
form, `rust_b_regions_view_first`):

```
region 'r17: reborrow bb0[9]         // the regions the checker adds (D3.6's reading)
live _5: bb0[3..7+] bb1[0..2]        // use-liveness, per local with a slot
drop-live _5: bb0[3..7+]             // drop-liveness, when not empty
constraint 'r11: 'r2 @ bb0[5]        // one per edge `'r11 : 'r2`, in generation order
value 'r11: bb0[5+..9] bb1[0..2] end('r3)
loan L1: &mut _2 @ bb0[5] 'r11       // M2 adds `scope bb0[5+..9]`
solved: 12 bodies, 3 reused (key)    // once, at the end of the run
```

A point set prints as runs per block, `bbK[x..y]` (inclusive) or
`bbK[x]`, an end a *half-name*: `i` is the start point of location `i`
of the block, `i+` its mid point; `bb0[3..7+]` is every point of
locations 3 to 7, `bb0[3+..7]` from the mid point of 3 to the start
point of 7. An empty set prints `-`. An `end` bit prints by its
universal's region (`end('r3)`; ir271 M1's named form `end('a)`,
`'_1` for an elided one, `'static`). The format is extensible with a
`reach` section for 0.27.4, and with the contracts design's `fact` and
`verdict` lines (reserved; `check --emit-facts` prints them in this
style: `fact bb0[3+]: _2 < _5  (switch bb0[2], checked)`, `verdict site
14/0: discharged (chained: _2 < _5, _5 <= _7)`), and a per-body
`verdict: clean|errors|deferred` line (D17.7) once M3 prints it
(`deferred` never from 0.27.2: D19.4).

## 17. Contracts in the rust edition

`requires`/`ensures` compile and run in the rust edition; the
expansion (`front/contracts/expand.vl`: `expand_contracts`, `make_pre`,
`make_body`, `replace_olds`; `front/contracts/desugar.vl`:
`desugar_call`) happens on the AST before the names are collected, so
the clauses reach the places IR as ordinary statements of ordinary
bodies. Verified shapes (v0.27.0, `--emit-places` on a rust-edition
file):

- `requires` becomes a companion `fn f$pre(?site: i64, <params>) {
  check }` whose body is `_3 = copy _2 >= const 0; switch` and, on
  failure, `intrinsic contract_check(..)` then `unreachable`. It is
  called at every call site before the call, on bit copies of the
  arguments: `_6 = copy _2; _4 = call take$pre(const 2, copy _6); _5 =
  call take(move _2)` (the `requires_call` block `{ let ?a0 = arg; .. }`
  is transparent, places-ir.md §3.7).
- `ensures` moves `f`'s body to `fn f$body(<params>)` and makes `f`'s
  body `{ let ?oldN = e; ..; let result = f$body(<params>); check;
  result }`: `_2 = copy _1` (the `old(x)`), `_3 = call half$body(copy
  _1)`, `_4 = copy _3 <= copy _2`, `switch`, `_0 = copy _3` or
  `contract_check` then `unreachable`.

**D17.1 (the rules apply as they are).** `f$pre`, `f` (the wrapper) and
`f$body` are three bodies, each checked by §1-§12 with no special case.
A clause's accesses are those of its statements: `Read` (`OK_COPY`) of
the places the condition names, at the points of the check's
statements — in `f$pre` at the start of its body, in the wrapper after
the `f$body` call and before the return; the `contract_check`
intrinsic reads its operands; a clause that borrows (`v.len()`:
`&'r _1` then a call) makes a loan like body code. At a call site the
`f$pre` call reads each argument place before the call moves or
reborrows it: a `copy` of a `&mut` argument for `f$pre` is D3.6's
reborrow, ending at the `f$pre` call (its parameter's region is a call
region related only through that argument); a by-value argument is a
bit copy into a borrowed temporary for `f$pre` (reads only) and then
moved by the call, so no M1 fact arises from the copy.

**D17.2 (`old(e)`).** `old(e)` is `let ?oldN = e;` at the wrapper's
entry, before the `f$body` call: `e` is evaluated as any initializer
(a copy of a `Copy` value, a move of a non-`Copy` one, a loan if it
borrows), and its value is held in `?oldN` across the body call until
the check. So `old(x)` of a scalar is a copy and creates no loan;
`old(v)` of a non-`Copy` `v` moves `v` before `f$body(move v)` and is
`borrowck.use_moved` (M1); `old(&x)` or `old(v.as_slice())` is a loan
whose region reaches the check, so it is in scope at the `f$body` call
and conflicts with a `move` of the place (`WM`, `move_borrowed`) or
with the implicit `&mut` reborrow of it (`WB` vs a `shared` loan,
`conflict`): the right verdict, since the promise would compare a
stale referent. A clause with a `Copy` `old(e)` is what the rules
accept with no loan involved.

**D17.3 (`ensures` on a `&mut` parameter's referent).** For `v: &mut
T` the wrapper passes `copy _v` to `f$body`, read as the reborrow
`&'new mut (*_v)` (D3.6) with `'v : 'new`; `'new` is live only to the
call (the temporary is not used after it), so after `f$body` returns no
loan of `*_v` is in scope and the check's `Read` of `*_v` (`*v ==
old(*v) + *n`) meets nothing; `old(*v)` reads `*_v` at entry before
the reborrow. So an `ensures` may say anything readable about `*v` at
exit, and a clause may hold a reference into `*v` across the body only
by the same loan rules (D17.2). The companion bodies share the
template's universals and dedupe key (D4.4): an error in a clause is
reported at the clause's position in the template.

**Finding (front, outside this spec).** A rust-edition function with a
clause and a `&T`/`&mut T` parameter does not check today: contracts
generate a property test for every contracted function and the
generator has no case for a pointer type (`error test.generate`, "no
generator for '&i64' (a pointer)"); MVS's `let T` of a compound type
has one. Until the generator reads `&T`/`&mut T` as `let`/`inout` in
the rust edition, D17.3's cases cannot be written; corpus271 writes
D17.1 and D17.2 on by-value parameters and D17.3 marked XFAIL on the
front. (The contracts/effects design takes it as ir271's fix, R1.)

The contracts/effects design adds four rules (its C3, C5, A4.1, O3.4;
the front's part is ir271's):

**D17.4 (a clause's shared context).** A clause is type-checked as the
body of its companion under the signature transformation `shared(τ)`:
`shared(&mut T) = &T`, `shared(&'a mut T) = &'a T`, `shared(T) = T`
otherwise. `f$pre`'s parameters are `shared(params(f))`; the wrapper's
`ensures` sees `params(f)` as `shared(..)` too (its locals rebound as
`&T` views, `let p: &T = &*p_mut`). So a clause cannot write through a
parameter by typing (a write through a `&T` of a non-`Freeze` `T` is
purity's, `interior`); D17.3's "the check's read of `*_v` meets nothing"
is then by construction. A by-value non-`Copy` parameter is read in
place in `f$pre` (a `BORROWED` bit copy): a `move` of it in a clause is
`error contract.move`; `result` in an `ensures` of `-> R` is a
read-only place of type `R`, a `move` of it `contract.move`; for `R =
&'a mut T`, `*result` may be read, and a read of `*self` (any place
`result`'s loan borrows) in that clause is `borrowck.use_borrowed` by
D2.5 (the wrapper's `result` holds the `M` loan through `'self : 'new :
'ret`, in scope until the return), with a contract-specific help
("`self` is borrowed by `result`; state the promise on `*result` or on
`old(..)`"). In MVS `shared` is the identity.

**D17.5 (`old(e)`, restricted).** `old(e)` is accepted iff `type(e)` is
`Copy`, `slots(type(e)) = []` (no reference, no view: D3.3) and
`type(e)` holds no raw pointer; else `error contract.old` (no
`.clone()` try in the rust edition: a clone allocates). So `old(r)` for
`r: &mut T` is rejected, `old(*r)` for a `Copy` `*r` accepted, `old(&x)`
rejected; D17.2's loan and move cases are unreachable by construction,
and `?oldN` is an ordinary `LF_TEMP` local read by `OK_COPY`.

**D17.6 (two `&mut` parameters are disjoint: the axiom and its
premise).** In a body `b`, parameters `p: &mut T` and `q: &mut U` have
`Overlap(*p.π, *q.ρ) = false` for all `π, ρ`, and `p: &mut T` is
disjoint from every `r: &V` parameter, **provided every caller of `b`
established it**: a rust-edition caller accepted by this checker (at
the call the two `M` loans, or the `M` and the `S` loan, are both in
scope, and D2.5 rejects the second's creation or activation when the
places overlap), or `unsafe` code whose SAFETY comment owns it. The
optimizer's `params_disjoint` and `param_frozen` are this axiom.
Exceptions, where it is off for `b`'s parameters: (a) `b` is an `extern
"C"` definition, `main`, or a function whose address is taken as an
`extern "C" fn` value (a C caller may pass aliasing pointers), and
`f$checked` when it is the exported symbol; (b) 0.27.x only: `b` is
reachable as a callback from an MVS std body through §12's bridge (its
address taken into a `fn` value or a closure passed to an MVS std item:
`sort_by`, `retain`, `for_each`) — nothing in MVS std's body is solved,
so MVS std is trusted like unsafe code, and a rust body it calls gets no
axiom in 0.27.1; closed in 0.27.2 with std2 (Z7: deleted); (c) a
D10.4-deferred closure body: its parameters are fine (its callers are
checked) but its captured places are reached through the raw env and
get no axiom, which D17.7's `deferred` verdict covers (deleted in
0.27.2: I8).

**D17.7 (the optimizer's gate).** `noalias_active(f)` is per body: for
a rust-edition body it is `borrowck_clean(f) ∧ !noalias_off`, where
`borrowck_clean(f)` holds iff the solve ran on `f` with no `borrowck.*`
error and `f` is not a D10.4-deferred body (its `borrowck.unchecked`
counts as not clean: the facts are off for that body only; no body is
deferred from 0.27.2); for an MVS
body it stays `own_mode == MODE_ERROR ∧ !noalias_off` until 0.28. The
readers are `gvn::has_ref_facts`, `params_disjoint`, `param_frozen` and
vecfacts' frozen header (`vec_apart`). **0.27.1's stopgap (shipped
with M1's fix, `rust_fn(f) ⇒ false`)** is replaced in M3 by the verdict,
which the code cache's key for the body includes (`clean`, `errors`,
`deferred`: §16's `verdict` line).

## 18. Implementation notes (non-normative)

`compiler/src/places/borrowck/`: `mod.vl` (the driver: per body, gated
by `rust_fn`, the dedupe key, the timer), `liveness.vl` (D3.7, bitsets
of locals per block, then per point), `constraints.vl` (D3.6, D3.3's
walks, `callee_regions`, D12.2), `solve.vl` (D6.1, worklist, bitsets;
D2.4's scope dataflow), `access.vl` (D2.2-2.5, §7), `moves.vl` (§8 on
elab's paths), `diag.vl` (§14). Every constraint keeps its location and
every loan its creation location, for 0.27.4's localized solve.

## 19. Closures: kinds and the environment (0.27.2; supersedes D10.4)

A closure expression at node `n` in a body `b` (the *enclosing body*: a
function instance, or the body of the closure `n` is nested in) has a
body `β` of its own (the front's synthesized `Fn` node,
`ClosureInfo.f`), solved as a body. `β` is solved before `b` (D19.10's
requirements are an input of `b`), so nested closures are solved
innermost first; `β` exists once per instance of `b`.

**D19.1 (the closure type).** The closure has captures `x₁..xₖ`
(D10.1: whole variables, in the front's capture order) with modes `m₁..mₖ
∈ {ref, mut, val}` (D19.2), parameter types `A₁..Aₙ` and result `R`
(D20.3) and a kind `kind(C) ∈ {Fn, FnMut, FnOnce}` (D19.3). Its type
`C = closure(n)` is nominal, one per `n` per instance of `b`. Its
*environment* `Env(C)` is the struct whose field `k` has type `&'cₖ
τₖ` (ref), `&'cₖ mut τₖ` (mut) or `τₖ` (val), `τₖ` the type of `xₖ` in
`b`. Its region slots (D3.3, amended):

    slots(C) = slots(Env(C)) ++ X_C

where `slots(Env(C))` reads the environment as the tuple of its fields
and `X_C` is the list of the closure's *external signature regions*
(D20.3) in order: the parameters left to right, then the result, each
type's slots in D3.3's order. Variance (D5.2, amended): a position of
`slots(Env(C))` has D5.2's closure-field variance; a position of `X_C`
has the variance it has in `fn(A₁..Aₙ) -> R` (`Aᵢ: −`, `R: +`, through
`xform`). `needs_drop(C)` iff some `val` capture's `τₖ` needs drop.
`Copy`/`Clone` per D19.7, `Send`/`Sync` per AT1, `dropck(C)` per D19.9.

**D19.2 (the capture mode; completes D10.2).** The mode is defined on
the body before the environment's shape is known, so it is not
circular. Let `β°` be `β` as the builder makes it with each captured
variable `xₖ` standing for an opaque place `Xₖ : τₖ`; the accesses are
D2.2's on places `Xₖ.π`.
- `mₖ = val` iff the closure is `move`, or `β°` has an `OK_MOVE Xₖ.π`
  with `π` free of deref-like projections (a move of `xₖ` or of a part
  of it; a move through a deref is M3's error whatever the mode);
- else `mₖ = mut` iff `β°` has a `WA`, `WB`, `Reserve` or `WD` access on
  `Xₖ.π` with no deref of a shared reference or of a raw pointer on `π`
  (a write through `&T` is the front's error; one through `*mut T`
  needs no exclusive capture, R1);
- else `mₖ = ref`.

So an immutable binding that the body neither moves nor writes is
captured by `&`, a `Copy` one too (its reads are `OK_COPY`, `RC`); the
by-value copy of a shared view (R12) is deleted with Z9.6. A `mut`
capture all of whose mut-making accesses pass a `PJ_DEREF` of `xₖ`'s
own `&mut` reference does not need `xₖ` to be `mut` (rustc's unique
borrow; here the same `&'cₖ mut τₖ` loan); any other `mut` capture of
a binding not declared `mut` is the front's "cannot assign to an
immutable variable" (rustc E0594, E0596).

*Nested closures.* The place of variable `x` in body `b`, `vp_b(x)`, is
`(L, ∅)` for a local `L` of `b`; for a capture `j` of `b` (`b` a
closure body, D19.4): `*((*_1).j)` for a `ref`/`mut` capture and
`(*_1).j` for a `val` one in a reference env, `*(_1.j)` and `_1.j` in a
by-value env. The capture operands of the closure's `RV_AGG
AK_CLOSURE` are `_t = &'cₖ vp_b(xₖ)` or `_t = &'cₖ mut vp_b(xₖ)` moved
in (a reborrow when `vp_b` has a deref: the supporting-prefix rule
applies), or `move vp_b(xₖ)` / `copy vp_b(xₖ)` for `val`.

*Implementation.* The front decides the modes while it checks the body
(`captured_by_ref`, `note_local_write`, `upgrade_captures`); its
decision must equal this definition. The corpus pins the capture
operands with `PLACES:` lines, one case per bullet.

**D19.3 (the kind).**
- (a) *Expected.* When the closure expression is checked where a value
  of a type `F` with `Fn*` bounds is expected (D20.3's expectation),
  `kind(C) = κ_exp`, the least of `F`'s `Fn*` bounds in the order `Fn <
  FnMut < FnOnce` (rustc takes the expected kind; the body does not
  change it).
- (b) *Inferred.* Otherwise, from `β°`: `FnOnce` iff some `val` capture
  `k` has an `OK_MOVE Xₖ.π` with `π` free of deref-like projections;
  else `FnMut` iff some `mₖ = mut`, or some `val` capture has a `WA`,
  `WB`, `Reserve` or `WD` access on `Xₖ.π` with no shared or raw deref
  on `π`; else `Fn`. A `move` closure that only reads its captures is
  `Fn`; a capture-free closure is `Fn`. (`drop(x)` is a call that moves
  `x`: an `OK_MOVE`, no separate case.)
- (c) *A fixed kind the body exceeds.* With `kind(C) = Fn` by (a), a
  `mut` capture, or a write access to a `val` capture as in (b), is
  `error closure.kind` at the first such write, naming the capture
  (rustc E0594, E0596: "cannot assign to `x`, as it is a captured
  variable in a `Fn` closure"). With `kind(C) ∈ {Fn, FnMut}` by (a), a
  moved `val` capture is M3 in `β` (`borrowck.move_out`, E0507: in a
  reference env `(*_1).k` has no move path, D19.7).

**D19.4 (the env parameter; IR change, clos272 M1).** For `k ≥ 1`,
`β`'s first parameter `_1` has type `&'e C` for `Fn`, `&'e mut C` for
`FnMut`, `C` for `FnOnce`: a *reference env* or a *by-value env*. For
`k = 0` there is no env parameter (as at v0.27.1: `closure_call`
passes none) and `β`'s parameters start at `_1`. Capture `k` is the
place `(*_1).k` (reference env) or `_1.k` (by-value env); the captured
variable of a `ref`/`mut` capture is `*((*_1).k)` or `*(_1.k)`.

`β`'s universals (D4.1 for a closure body) are `U_β = E_β ∪ L_β`:
- the *external* ones, `E_β = {'static} ∪ N_outer ∪ {one universal per
  slot of C}`; the slot universals are bound to `_1`'s slots after
  `'e` (to `_1`'s own slots for a by-value env), and those of `X_C`
  also to the signature's slots at their positions (one variable, two
  bindings, D3.2); `N_outer` are the named lifetimes of the enclosing
  items that `β`'s annotations name, each `b`'s own universal;
- the *local* ones, `L_β = {'e} ∪ B_β`: the env reference's region
  (absent for a by-value env) and the bound regions of D20.3. Both are
  late-bound (fresh per call, D20.2).

`⊒` on `U_β` is D4.5's over `type(_1)` and `β`'s signature: `&'e C`
gives `'s ⊒ 'e` for every `'s ∈ slots(C)`; a capture field `&'cₖ τₖ`
gives `'t ⊒ 'cₖ` for every `'t ∈ slots(τₖ)`; a struct in `τₖ` its
declared bounds; plus `b`'s order on `N_outer`, and D20.3's on `B_β`.
`Req(C)` (D19.10) is *not* assumed in `β`. With this rule every access
to a captured place in `β` goes through a reference or the by-value
env, every rule of §1–§9 applies with no exception, and no body gets
`borrowck.unchecked` (at v0.27.1 `_1: *C`, a raw pointer: D10.4).

*Lowering.* A reference env is passed as a pointer (today's ABI). A
by-value env is passed as a pointer to a temporary of the caller that
the callee owns: the caller does not drop it (it was moved, D19.5), the
callee drops the captures it did not move at its exit (elaboration over
`_1.k`'s move paths, D8.1). The convention is the same in both code
generators; `tests/same_output.sh` over the closure cases is the
witness.

**D19.5 (the call).** Let `r = c(a₁..aₙ)` be a call whose callee
expression, after the call's auto-deref, denotes a place `Q` of closure
type `C`: a closure local, `*p` for `p: &C` / `&mut C`, or, in an
instance, `Q : F` with `F = C` (the callee is then `β` directly). The
*call kind* `κ` is `kind(C)` when `Q`'s declared type is `C`, and the
least of `F`'s `Fn*` bounds when it is `F`; `kind(C) ≤ κ` holds by
D19.6. The call makes the access of `κ` to `Q`: `Fn`: `_t = &'t Q`
(`BK_SHARED`); `FnMut`: `_t = &'t mut2 Q` (`BK_MUT2`, created before
the arguments and activated at the call: a receiver, §7); `FnOnce`:
`move Q` (`WM`; `copy Q` when `C: Copy`, M6). The env operand passed to
`β` is formed from it by `kind(C)`:

| `κ` \ `kind(C)` | `Fn` | `FnMut` | `FnOnce` |
|---|---|---|---|
| `Fn` | `move _t` | — | — |
| `FnMut` | `_u = &'e (*_t)`; `move _u` | `move _t` | — |
| `FnOnce` | `_t = move Q`; `_u = &'e _t`; `move _u`; `drop(_t)` after the call | `_t = move Q`; `_u = &'e mut _t`; `move _u`; `drop(_t)` after the call | `move Q` |

(rustc's `call_once` of an `Fn` closure is the same shim.) For `k = 0`
no env operand is passed, and the access to `Q` is still made.

Then D3.6's call rule with `Σ_β = (U_β, [type(_1), A₁..Aₙ], R, ⊒_β ∪
Req(C))`: every universal of `β` except `'static` is instantiated fresh
(`RO_CALL`): `'e`, the slot universals, `B_β`. The env argument relates
the closure value's slots to the instantiated ones by `sub` with
D19.1's variance; for `k = 0` the same `sub(type(Q) ≤ C['c])` is made
at the call as a constraint, though no operand carries it. Hence a
capture loan outlives the call's `'cₖ`, the result's regions are within
the closure value's result slots, and an argument's regions contain its
parameter slots. A call with `κ = FnMut` through `p: &C` is the front's
"cannot borrow as mutable" (E0596); with `κ = FnOnce` through a
reference, `move (*p)` is M3 (E0507) unless `C: Copy`. *IR at v0.27.1:*
the direct call's `&'e c` / `&'e mut2 c` exists (D10.3); the adapters
of the table and `move Q` are clos272 M1's.

**D19.6 (bound satisfaction).** `C: Fn` iff `kind(C) = Fn`; `C: FnMut`
iff `kind(C) ∈ {Fn, FnMut}`; `C: FnOnce` always; a `fn` item or a `fn`
pointer satisfies all three; each also needs D20.3's signature match
(D20.5). Checked where the front checks a bound at instantiation.
Violation: `error closure.kind` (rustc E0525) at the argument, naming
the capture and the statement that moves (`FnOnce`) or writes
(`FnMut`) it; `help:` the bound to relax, or `.clone()` of the capture
before the closure for a move. With an expectation the kind is the
expected one (D19.3(a)), so D19.6 fails only for a closure checked
without one and bound later (a `let`-bound closure passed on).

**D19.7 (moves of the closure; `Copy`, `Clone`).** A call with `κ =
FnOnce` is a `WM` of `Q` (D2.2): a second call, or any use after it,
is M1, `borrowck.use_moved` (E0382), the message naming the first call
("a closure called by value"). In a by-value env, `_1.k` has move paths
(D8.1): moving a `val` capture out is tracked and the rest is dropped
at exit. In a reference env, `(*_1).k` has none: a move out of a
capture is M3. `C: Copy` iff no `mₖ = mut` and every `val` capture's
`τₖ: Copy` (a `ref` field `&'c τ` is `Copy`); `C: Clone` iff no `mₖ =
mut` and every `val` capture's `τₖ: Clone`, its clone cloning each
`val` field and copying each `ref` one; never by a user impl (no item
can name `C`). A `Copy` closure is copied, never moved (M6), an
`FnOnce` call of it included.

**D19.8 (escape).** 0.14's `check_scope_exit` (`front/closures/escape.vl`)
is off for rust-edition bodies: a closure value's escape is the
ordinary region verdict. Returning one that holds a `ref`/`mut` capture
of a frame-owned place is `borrowck.return_local` (D6.2.2: the
returned value's slots carry `end('u)`); storing it in a longer-lived
place is `borrowck.dropped_borrowed` at the captured local's
`StorageDead` (D2.5); a `move` closure of owned values escapes freely.
Until §21, a closure leaves a function only as a value of a generic
parameter's type; `-> impl Fn*(..)` is `edition.later:
impl_trait_return (0.27.2.1)`.

**D19.9 (drops).** `dropck(C) = ⋃ dropck(τₖ)` over the `val` captures
(D9.1), mapped into `C`'s slots; a `ref`/`mut` field and `X_C`
contribute nothing. A by-value env's unmoved captures are dropped at
`β`'s exit (D19.4); a reference env drops nothing.

**D19.10 (closure requirements; IR change, clos272 M2).** In `β`, a
universal violation (D6.2.1: a constraint `'a : 'b` with `'a ∈ U_β`
and `end('v) ∈ val('b)`, `'a ⋣ 'v`; read "`'a` must outlive `'v`") is
decided by where `'a` and `'v` are:
1. `'a ∈ L_β`: an error, `borrowck.outlives`. For `'a ∈ B_β` and `'v`
   a capture's slot: rustc E0521 ("borrowed data escapes outside of
   closure"), naming the parameter and the capture; `'v ∈ X_C` (a
   parameter returned where the result is external): rustc's "lifetime
   may not live long enough" (no code); `'a = 'e`: rustc's "captured
   variable cannot escape `FnMut` closure body" (no code).
2. `'a ∈ E_β`: no error in `β`; the *requirements* `'a ⊒ 'z` for every
   `'z ∈ ub('v)` are recorded, with `ub('v) = {'v}` for `'v ∈ E_β` and
   else the `⊒`-minimal elements of `{'z ∈ E_β | 'z ⊒ 'v}` (never
   empty: `'static`). `Req(C)` is the set of them, deduped: pairs over
   positions of `slots(C)`, `'static` and `N_outer`. (rustc's
   `ClosureRegionRequirements`. Its first step, shrinking a local `'a`
   to an external lower bound, is the identity here: by D19.4's `⊒`, no
   local universal outlives an external one.)
3. In `b`, at the `RV_AGG AK_CLOSURE` statement that creates the value,
   with destination slots `D = regions((a,b))`: for each requirement,
   the constraint `D_i : D_j` (`'static` and an `N_outer` region stand
   for themselves), recorded at that statement. These are ordinary
   constraints of `b`: one with a universal on the left is checked by
   D6.2.1 in `b`, and propagated again when `b` is a closure body.
4. `Req(C)` is part of `C`'s declared bounds for D4.5 (as `Scope<'scope,
   'env: 'scope>`'s are): a body that has a value of type `C` as a
   parameter (an instance with `F = C`) assumes them, and D19.5's call
   rule includes them in the callee's order.

*Soundness.* No position of `slots(Env(C))` is contravariant (a `fn`
type has no slot, R6); `X_C`'s have `fn` variance. Every later value
of type `C` is reached from the aggregate's destination by `sub` with
that variance, so the actual regions behind it satisfy what was imposed
on `D` (a covariant position's actual region contains `D_i`, a
contravariant one is contained in it, an invariant one is equal).
*Examples.* `let mut f = || { h.p = r; };` with `h: H<'_>` and `r:
&i64` captured by `&mut` and `&` stores a capture into a capture: `β`
needs the `r` field's inner slot to outlive `h.p`'s, both external, so
the requirement is checked at the closure's creation, where both are
`main`'s and it holds (rustc accepts; v0.27.1 reports
`borrowck.outlives` twice, a false positive). `let f = || x;` with `x:
&i64` captured by `&`: the result region is in `X_C` (D20.3), the env's
inner slot outlives it by a requirement, and `f()`'s result keeps `x`'s
loan (v0.27.1: a false `borrowck.elision`). AT6's spawned closures:
`'scope` is local, `ub('scope) = {'env}`.

**Soundness (I8).** With D19.4 every access to a captured place in `β`
is through `(*_1).k` or `_1.k`: the supporting-prefix rule binds a loan
of a captured place in `β` to `'cₖ` (through `&'e` for a `mut` capture,
stopping at the shared deref for a `ref` one, D1.3); the enclosing
body's capture loan (D10.2) outlives the call's `'cₖ` by D19.5's `sub`;
and what `β` stores into, or returns from, its environment is bounded
by the requirements D19.10 checks in `b`. So I1–I7 hold for `β` with no
raw hole: D17.6's exception (c) and D17.7's `deferred` verdict are
deleted, and `borrowck.unchecked` is retired.

## 20. Late-bound regions in bounds and closure signatures (0.27.2; supersedes D10.5)

**D20.1 (binders).** A bound `F: Fn*(A₁..Aₙ) -> R` on a generic item
`g` has three kinds of region: `g`'s named lifetimes (early-bound, as
D4.3 says of a lifetime that appears in a bound); `'static`; and the
*bound regions* `B = {'x₁..}`, one fresh per elided region in an input
position of `A₁..Aₙ` (E1 at the bound). An elided region in `R` is E2
over the bound's inputs alone (E3 cannot apply: no `self`); E2 failing
is `error borrowck.elision` at the bound (rustc E0106). The binder is
implicit: nothing is written `for<'x>` (0.29).

**D20.2 (the callee side; 0.27.1's).** In `g`'s body a call `f(a₁..)`
with `f: F` instantiates every bound region fresh (D3.6, `RO_CALL`),
related to nothing but through the arguments and the result: `g` may
call `f` at any `'x`.

**D20.3 (the closure's signature).** A closure expression has an
*expected bound* when it is checked where a value of type `F` with an
`Fn*(A..) -> R` bound is expected (an argument of `g` for a parameter
of type `F`, or of type `impl Fn*`); its parameter and result types
are then `A..` and `R` with the bound's types substituted, an
annotation on a parameter unifying with its `Aᵢ` (an annotated `&T`
against `&'x T`: the elided region is `'x`); a mismatch is `error
closure.sig` (rustc E0631). Each region position of the signature is:
- *bound* (in `B_β`, local): with an expected bound, a position of
  one of the bound's bound regions, renamed fresh for `β`; without
  one, each elided region of a written parameter annotation (`|x:
  &T|`), fresh per position;
- *named*: a lifetime written in an annotation, an enclosing item's
  (`N_outer`, external);
- *external* (in `X_C`): every other position, namely the regions of
  the bound's instantiation (`F: Fn(T) -> U` with `U = &'s i64` in the
  instance), every region of a parameter or result type not written
  and not given by a bound (inferred), and every elided region of a
  written result annotation (`-> &T`). These are regions of the
  enclosing body, carried by `C` (D19.1), not fresh per call.

There is no elision rule inside a closure's own signature: an elided
result region never links to a parameter's (rustc's rule). So `|p:
&i64| p` is rejected (`'p ∈ B_β` must outlive the external result
region: D19.10 case 1; v0.27.1 accepts it), `call(|p| p)` with `call<F:
Fn(&i64) -> &i64>` is accepted (E2 at the bound makes the result the
bound region), and `|| x` returns a region of `X_C` (D19.10's example).

In `β`, `⊒` relates a bound region only by `'static ⊒ 'x` and the
implied bounds of the `Aᵢ` (`&'x &'y T` gives `'y ⊒ 'x`). Hence a
value of a bound region cannot be stored into a capture (`'x ⊒ 'cₖ`
fails) nor returned unless the result's region is that bound region:
`borrowck.outlives` with rustc E0521's words, D19.10 case 1. This
closes R4.

**D20.4 (erasure).** Bound regions are not slots: `slots(C)` is D19.1's
(the env's and `X_C`), and `slots(fn(..)) = []` (R6). The erased TYPES
do not distinguish `fn(&'x T)` from `fn(&'a T)`; a bound's binder lives
in the bound's AST (`lifetimes_of` of the bound node) and in `β`'s
`B_β`.

**D20.5 (no higher-ranked subtyping of values; L9).** A closure or `fn`
value is accepted for a bound iff its signature matches the bound's up
to a renaming of bound regions (α-equivalence after D20.3's
deduction); a `fn` value whose signature names an early-bound `'a`
where the bound has a bound region is `error closure.sig`. rustc also
accepts a `for<'x> fn(&'x T)` where `fn(&'a T)` is expected, by
instantiation; vole does not until `for<>` (0.29). Calls are unaffected
(D20.2).

**D20.6 (a closure's `T: 'a`).** For D4.5, a declared `F: 'a` with `F =
C` means `'s ⊒ 'a` for every `'s ∈ slots(C)`: each capture's `'cₖ`, the
slots of each `τₖ`, and `X_C`. (For a `ref`/`mut` capture the `τₖ` part
follows from `'cₖ`'s by the field's implied bound.) `Scope::spawn`'s `F:
'scope` is this rule.

## 21–22. `impl Trait` in return position; the opaque instance (0.27.2.1)

Appended with 0.27.2.1 (D21, D22; L10–L12 are reserved for them).

## 23. std2 as the edition's std: the IR's rules (Z7–Z9)

Z1–Z6 (one std per edition, the prelude, the compiler-known items, no
mixing, the std2 tail, two stds in one binary) are the front's and the
loader's, in [front-rust.md](front-rust.md). With Z4, D12.1–D12.3 and
`callee_regions`'s bridge are deleted: `Σ_f` of a std2 function is
D4.1's reading of its rust-edition signature, as a program's.

**Z7 (std2's bodies are checked bodies).** `rust_fn(f)` holds for every
std2 body (Z1's `rust_at`, true in std2's files); §1–§10, §19, §20 and
§24 apply to them with no exception, and their `unsafe` internals are
R1's, each with its SAFETY comment. An instance of a std2 template made
by a program's types is solved per D4.4; its errors are reported at
the template's position (`<std>:L:C` in transcripts), naming the
instance and the program's call that made it (§14.2). *The cache:* a
body's verdict and messages are memoized in the tools' on-disk cache
by `(std hash, the body's item path, D4.4(b)'s key)`; a body whose
entry exists is not solved again. *The gate:* the `std2-check` row
solves every std2 body (every instance a std2 test makes, and each
template's region-free instance where one exists; a template with no
instance stays R3's until D4.4(d)), 0 errors. *The cost:* §15's
quarter holds over std2's bodies, and the `std-rust` compile-cost row
stays within 2.0x of MVS's `std`. D17.6's exception (b) (MVS std
callbacks) is deleted; D17.7's verdict applies to std2's bodies.

**Z7.1 (`Copy` in a rust program).** `τ: Copy` iff `τ` is a number,
`bool`, `char`, `&T`, a raw pointer, a `fn` type, a tuple or array of
`Copy` parts, a closure by D19.7, or a type with an impl of std2's
`marker::Copy` (written or derived). The heuristic of R11
(`places::regions::rust_copy`: no glue and `Copy` arguments) is
deleted; `Range<i64>` moves, as in rustc.

**Z8 (the own pass off).** For a rust program `own_mode = MODE_OFF` for
every body, std2's included: Q2 and D8.4's suppression are vacuous,
§0.1's muted view half and §8.4's M3 task are deleted, `own.drop_view`
does not run (dropck, §9, is the rule), and R2 is closed. `query own`,
`query views` and `--print-views` on a rust program say that the own
pass does not run in the rust edition. MVS programs are unchanged:
`tests/std/own.sh` and D17.7's MVS half stay as they are.

**Z9 (unsized `[T]` and `str`; IR change, clos272 M3; the type side
front272 M2).** In a rust program `[T]` and `str` are unsized types,
not MVS's views; no view type exists in a rust program (MVS's
`TyKind::Slice` view is untouched: the edition gates the type's
construction, and F21 gives the `Sized` rules).
- **Z9.1 (slots, variance).** `slots([T]) = slots(T)`, `slots(str) =
  []`, so `slots(&'a [T]) = slots(&'a mut [T]) = ['a] ++ slots(T)`,
  `slots(&'a str) = ['a]`, `slots(Box<[T], A>) = slots(T) ++ slots(A)`.
  `[T]`: `T: +`; the reference's variance is D5.2's (`&'a mut [T]`:
  `T: o`). D3.3's view clause, D1.2's view modes and D1.4 do not apply
  in a rust program from Z9 on.
- **Z9.2 (places).** A place of unsized type exists only as `*p`, `p`
  a reference, a raw pointer or (through its `deref` call, D3.8) a
  `Box`. No local, operand (`OK_COPY`, `OK_MOVE`), field or array
  element has an unsized type (F21 rejects it at the front; the
  verifier, `--verify-places`, checks it). D8.1: no move path through
  such a deref, and nothing of unsized type is moved.
- **Z9.3 (`RV_LEN`).** `RV_LEN (*p)` with `*p` unsized reads `p`'s
  length word; its access is D2.2's `(Shallow, Read, (*p))` (a loan of
  an element of `*p` does not conflict with it); M1 asks `DefInit` of
  `p`, the base. `RV_LEN a` of an array is its constant, as before.
- **Z9.4 (indexing).** `(*p)[i]` and `(*p)[k]` are `PJ_INDEX`/`PJ_CONST`
  after a `PJ_DEREF`: ordinary projections of an unsized place (they
  keep the element's slots, D3.3's array rule). A loan of `(*p)[i]` has
  `p` as its last supporting prefix through a `&mut`, and stops at a
  shared one, by D1.3 alone: D1.4's "an index on a view is a deref
  through `'v`" is retired. A bounds check is an `SK_ASSERT` over
  `RV_LEN (*p)`.
- **Z9.5 (slicing and reslicing).** `&'ℓ (*p)[a..b]` and `&'ℓ mut
  (*p)[a..b]` (`RV_SLICE`, or F20's `&*index(&*p, a..b)` call) is a
  loan of the place `(*p)`, the whole referent (a range is not a
  place; rustc's slicing borrows `*p` through `index`), of type `&'ℓ
  [T]`, with D3.6's supporting-prefix constraint through `p`. So
  *reslicing a local*, `let mut v: &[T] = ..; v = &v[a..];`, is
  `_t = &'ℓ (*v)[a..]; v = move _t`: the assignment's `WA` of `v` is
  `Shallow` against a loan that extends `v` through a deref
  (accepted, D2.5), and it kills the loan (D2.3); in a loop (`while
  v.len() > 1 { v = &v[1..]; }`) the same. Cases
  `rust_b_ok_reslice_local`, `rust_b_ok_reslice_loop`.
- **Z9.6 (reborrows).** `&'ℓ *p` and `&'ℓ mut *p` of an unsized `*p` are
  `RV_REF` of `(*p)`: loans of the referent whose result copies `p`'s
  length word. A `&mut [T]` passed on is reborrowed (`&'new mut2
  (*q)`) like any `&mut` (D3.6, I7: a `copy` of a whole `&mut [T]` is
  the verifier's error), which closes 0.27.1's "a `&mut [T]` view
  argument stays a copy". A by-`&` capture of a `&[T]` or `&str`
  variable is a loan `&'c &'a [T]` with two slots, so R12 is deleted,
  and `&&'a str` is an ordinary type (§13's ir271 finding closed).
- **Z9.7 (unsizing).** `&'a [T; n]` to `&'a [T]` (and `&mut`, `*const`,
  `*mut`) is an `RV_CAST` whose slots correspond positionally (`['a] ++
  slots(T)` on both sides), so D3.6's cast rule is `sub`; the length is
  the constant `n`. `&Vec<T, A>` to `&[T]` and `&String<A>` to `&str`
  are `deref` calls (D3.8).
- **Z9.8 (drops).** Nothing behind a `&[T]` or `&str` is dropped.
  `Box<[T], A>` and the containers are D9.1's table: `dropck(T) ∪
  set(slots(A))`.

*0.27.1's reslice, in its own terms.* With views (before Z9), D1.4
already makes `RV_SLICE` of a view-typed base a deref through `'v`:
the loan's place is the view's referent, one deref-like projection past
the base, not the base. The loan of `&v[a..]` for a view local `v` is
therefore of `v[..]` (`rel(v, v[..]) = PrefixOf` through a deref-like
projection), so `v = &v[a..]` is a shallow write that does not
conflict with it and kills it (D2.3). v0.27.1 records the loan as of
`v` itself (`Equal`) and reports `borrowck.assign_borrowed`, a false
positive (rustc accepts): a bug against D1.4, fixed by recording the
loan's place as D1.4 says until Z9.5 replaces it.

## 24. Auto traits (0.27.2; AT rules)

**AT1 (`Send`, `Sync`, compiler-known).** `Send` and `Sync` are traits
whose impls the compiler decides (std2's `marker.vl` declares neither;
they need no `use`, Z2). `τ: Send` and `τ: Sync` are decided
structurally by `front/threads.vl` with Rust's rules:
- numbers, `bool`, `char`, `()`, `str`, fieldless enums, `fn` types:
  both;
- `[T; n]`, `[T]`, tuples, and a struct or enum with no vouch (AT2):
  `Send` iff every part (every field of every variant, with the type
  arguments substituted) is `Send`, `Sync` likewise;
- `&T`: `Send ⇔ T: Sync`, `Sync ⇔ T: Sync`; `&mut T`: `Send ⇔ T: Send`,
  `Sync ⇔ T: Sync`; raw pointers: neither;
- a closure `C`: by its environment's fields, so per capture: a `ref`
  capture needs `τₖ: Sync`, a `mut` or `val` capture `τₖ: Send` (for
  `Send`); `X_C` adds nothing.
std2's own types follow from these and from std2's vouches (AT2):
`UnsafeCell<T>` and `Cell<T>` are `Send` iff `T: Send` and never
`Sync`; `Mutex<T>` is `Send` and `Sync` iff `T: Send`; `MutexGuard<'a,
T>` is never `Send`; the atomics are both; the containers by their
type and allocator arguments; `&'a Arena<P>` is not `Sync`.
`threads.vl`'s name list (`vouched_container`) and 0.21's view
exclusion (`&T` never `Send`) are MVS's: in the rust edition how long a
reference lasts is a region bound (`'static`, `'scope`), not a `Send`
fact. A `fn` pointer is `Send` and `Sync` (rustc's rule; 0.21 refused
it): what a call through it reaches is the shared-static rule's (E1;
an indirect call's effects are unknown, which that rule rejects in a
spawned body).

**AT2 (vouches).** `unsafe impl<P..> Send for X<..> where .. {}` and
`impl<P..> !Send for X<..> {}` (and `Sync`), parsed in the rust
edition: the positive vouch is `unsafe`, with its `SAFETY:` comment;
`!` before the trait is new syntax, and a negative impl of any other
trait is an error. Any vouch of a trait for `X` replaces AT1's
structural rule for every instance of `X`: `X<τ..>: Send` iff some
positive vouch applies to it (F4's applicability: its header unifies
and its `where` bounds hold). A positive and a negative vouch that
overlap are `trait.overlap` (F4). Stable rustc has no negative impls,
so a case using one is `// RUSTC: none` for the twin.

**AT3 (bounds).** `T: Send` and `T: Sync`, in a parameter list or a
`where` clause, are checked at instantiation by AT1–AT2 on the
argument `τ`; for a closure argument, per capture as AT1 says. A
failure is `error sync.not_send` / `sync.not_sync` (rustc E0277) at the
instantiating call, with the chain to the failing part (`threads.vl`'s
reason: the type, the field, the part).

**AT4, AT5** (leakage through an opaque type; the opaque instance's
`Ω: Send`) are 0.27.2.1's, with §21–§22.

**AT6 (`thread::scope`).** For the rust edition, 0.21's checks of
`thread::scope` and `Scope::spawn` (`check_scope`,
`check_scoped_spawn`, the `sync.scope_*` codes) are replaced by std2's
signatures and the ordinary rules:

    pub fn scope<'env, F, T>(f: F) -> T
        where F: FnOnce(&Scope<'_, 'env>) -> T
    pub struct Scope<'scope, 'env: 'scope> {
        scope: PhantomData<&'scope mut &'scope ()>,
        env: PhantomData<&'env mut &'env ()>, ..
    }
    pub fn spawn<F, T>(&self, f: F) -> ScopedJoinHandle<'scope, T>
        where F: FnOnce() -> T + Send + 'scope, T: Send + 'scope

In the body `β_f` of the closure passed to `scope`, the parameter's two
elided regions are bound regions (D20.1), the second being `'scope`,
local to `β_f` (D19.4), so nothing in it may outlive `f`'s call;
`'env` is early-bound (it appears in the bound, D4.3) and external
(`X_C`), with `'env ⊒ 'scope` implied by `Scope`'s declared bound
(D4.5); `Scope` is invariant in both (D5.2 through `PhantomData<&mut
..>`). A spawned closure `γ` must satisfy `F: 'scope` (D20.6) and
`Send` (AT3). Hence:
- *what a thread borrows from the caller lives across the scope:* `γ`'s
  capture of a variable `f` captured from the caller is a reborrow
  through `f`'s env slot `'c` (D19.2's nested places), so `'c ⊒
  'scope` fails in `β_f` with `'c` external and is propagated as `'c ⊒
  'env` (`ub('scope) = {'env}`, D19.10) to the caller, whose capture
  loan is live through the `scope` call;
- *a thread does not borrow `β_f`'s own locals:* a loan of one must
  outlive the universal `'scope`, so it is in scope at the local's
  `StorageDead`: `borrowck.dropped_borrowed`; `move` the value in;
- *the body changes nothing a thread borrows:* the spawned closure's
  loans are in scope until `β_f`'s exit (they reach `end('scope)`), so
  a conflicting access in `β_f` is D2.5's conflict;
- *what a thread changes:* a `mut` capture is allowed when its `τₖ:
  Send` (rustc's rule; 0.21 refused every write), exclusive by the
  loan;
- *joined before `scope` returns:* `'scope` cannot be named outside
  `β_f` and ends with `f`'s call.
`spawn_in(f, a)` requires `F: 'static` and `T: 'static` (and `Send`):
the thread may outlive everything. The `thread`, `sync` and `tls`
effect bits and the shared-static rule (`sync.global`) stay (E1).
