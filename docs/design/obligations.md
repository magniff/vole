# Trait obligations: one place proves `T: Trait<Args>` (design, 0.30.2)

Status: **M1 in** (0.30.2, the selection table; §11 says where the code
differs from this text), M2 next; M3 onwards in a later round. It is the
root fix for the class of soundness
findings reviews 3–5 of 0.30.1 kept finding (an impl's predicate assumed
in its body and required nowhere). Each 0.30.1 fix closed one path
through which an obligation was discharged. This design removes the
paths and leaves one: rustc's architecture of **selection**,
**confirmation** with nested obligations, **projection** obligations,
**associated-type bounds**, and **well-formedness** checks of each impl.
Region obligations reach the borrow checker through one interface.

## 1. Why the class keeps reopening

`T: Tr<Args>` is proven today in at least seven places, each with its
own idea of which impl applies and what it requires:

| where | what it decides | what it misses (a finding) |
|---|---|---|
| front `implements`, `implements_with`, `impl_applies`, `impl_bindings` (traits.vl, convert) | the impl, by types with lifetimes erased | nothing about regions, by design |
| places `bound_ties`, `impl_bound_ties`, `impl_predicates`, `param_bound_predicates`, `trait_arg_ties` (regions.vl) | an instance's region bounds for each `T: Tr` it was given | **re-selects** the impl, without trait arguments: "the first class with an impl" (A4, m10–m13); lifetimes in trait arguments (A1); projection bounds (A5) |
| front `check_impl_statics`, `non_static_in` and 10 helpers (traits.vl) | whether an impl's type is `'static` for `trait St: 'static` | reads the written syntax: projections resolved by name (review 4 F2), `fn` types, aliases |
| places `check_super_predicates`, `super_impls`, `super_assoc` (impl_regions.vl) | supertrait impls' predicates at a concrete impl | generic impls (only at uses), trait arguments |
| front `where_preds_hold`, `assume_where_preds`, `pred_holds` | `where` predicates at a call, assumed in a body | compound subjects with lifetimes: not assumed in the body (RT-C301-11), impl-level compound predicates owned by nothing |
| front opaque instances (`opaque_unsure`, `opaque_unsure_tmpls`, `generic.unchecked`) | the generic check of a template | gives up where the front cannot prove an Ω's obligation, and moves the check to instances |
| `check_constrained`, `check_drop_impls` | E0207, E0366/E0367 | inherent impls (u31) |

Each is a partial copy of one algorithm. A finding is a program that goes
through the copy which lacks the case. Patching a copy (0.30.1, rounds
3–6) closes that path and not the next one. The one fix is to have one
algorithm and to make every one of these callers ask it.

## 2. The model

**An obligation** is `O = (Self, TraitRef, cause, env)`:

- `Self` and each trait argument are a *type with regions*. That is the
  front's lifetime-erased type `t` plus the slot vector of
  `regions::bind_walk` (one region per slot of `t`, the D4.2 walk), so
  the regions travel with the type without changing the type interner.
  `Region` is `'static`, a named universal of the item (U_NAMED), a
  slot of a substitution (U_SUBST k j), an Ω's slot, or an inference
  variable of a body.
- `TraitRef = (trait, [arg types with regions])`. For a projection
  bound, `<P as Tr<A>>::X == Y` or `P::X: B`, see §5.
- `env` is the **parameter environment**: the item's own predicates
  after elaboration (§4).

**A region predicate** is `a: b` between two `Region`s, or `T: 'a` for
a type with regions. It is decomposed into slot predicates by the D4.6
rules (a type outlives `'a` when every slot does, and a type parameter's
slots are its substitution's).

**The solver** is `prove(O) -> Proof`. A `Proof` is either `Ok(region
predicates)`, `Err(the unmet obligation, its cause chain)`,
`Ambiguous(candidates)`, or `Deferred`. It is one module,
`front/obligations.vl` (types; selection and confirmation), together
with `places/obligations.vl` (it turns the region predicates of a proof
into a signature's bounds or a body's constraints, §7).

## 3. Selection and confirmation

**Selection** asks which impl or where clause proves `Self: Tr<Args>`.
It matches **every** impl of `Tr` against the full trait reference: its
header's self type *and* trait arguments, by `match_type` (types only,
regions erased, as rustc selects modulo regions). The candidates are:

1. a predicate of `env` that unifies (a `Param` candidate: `T: Tr<U>`
   in the bounds, a supertrait of one, a where clause on a compound
   type). Then the proof needs no impl, and its predicates were the
   caller's to prove;
2. the impls whose header matches and whose type-level where clauses
   hold (recursively; a cycle or the depth limit is `Ambiguous`, never
   a no);
3. the builtins (Copy for primitives, Fn for closures, Sized, auto
   traits).

Exactly one candidate means it is selected. Two or more is `Ambiguous`:
in a template it is `Deferred` to the instance, whose types are
concrete; in an instance it is an error, `trait.ambiguous` (rustc
E0283), because coherence (`check_overlap`, extended to compare trait
arguments) leaves at most one impl per concrete trait reference. There
is no class order: a pattern, blanket or direct impl competes on equal
terms (A4, m10–m13), and the one chosen is the one the trait arguments
pick (m01–m05, RT-C301-15).

**The selection is recorded once.** The front stores each proof's
choice in a side table, `Ctx.selections`, keyed by (use node or
instance, bound index). The places read the table and never select
again. The front decides the method and the places check the lifetimes
of the same impl, so the two cannot disagree. That disagreement is the
root of A4.

**Confirmation** happens once impl `i` is selected for `O`. Unify its
header *with regions* against `O`: walk the impl's self-type node and
**each trait-argument node** against `O`'s slot vectors (bind_walk over
both, the head of today's `impl_bound_ties` extended to the trait
arguments). This gives a map from the impl's lifetimes to regions and
from its type parameters to types with regions. A lifetime at two
places equates two regions, and a `'static` written there is `region:
'static`. The **nested obligations** are then the impl's predicates
under that map:

- each lifetime bound (`'a: 'b`, the header's and the `where`'s, which
  is one list, `join_where_lifetimes`) becomes a region predicate;
- each type parameter's lifetime bound (`T: 'a`, `T: 'static`) becomes
  a region predicate on the mapped type;
- each trait bound and each where clause (`T: Sup`, `I::Item: Sup`,
  `Vec<T>: Clone`) becomes a new obligation, proven recursively, whose
  region predicates join the result.

The result of `prove(O)` is the union of these region predicates.
Lifetimes in trait arguments are mapped like the self type's, which
closes A1 (`impl<'a: 'static, A> Extend<W<'a>> for Out<A>`, std's
`impl<T, U: From<T>> Into<U> for T` with `From`'s impl bounded, f12,
f43, f47, h03, g02).

**Supertraits.** Proving `Self: Sub` also proves `Self: Sup` for each
supertrait of `Sub` (elaborated, its arguments substituted), as nested
obligations. At the impl, §6 proves them from the impl's own env
(E0478). At a use with `T: Sub` in env, they are in env by elaboration
(§4). So a caller through `T: Sub` meets Sup's impl's predicates in the
caller of the instance (review 4's c12, review 5's s01–s15).

## 4. The parameter environment and its elaboration

The env of an item is its predicates: the type parameters' bounds, its
`where` clauses (on parameters, projections and compound types alike),
the impl's predicates for a method, and the **implied bounds** of its
signature's types (D4.5: `&'a &'b T` gives `'b: 'a`, a struct's
declared `'b: 'a`). These are closed under:

- **supertraits**: `T: Sub` adds `T: Sup<args>`;
- **associated-type bounds**: `T: Tr` with `trait Tr { type A: Sup; }`
  adds `<T as Tr>::A: Sup` (A6 at uses);
- **associated-type constraints**: `T: Iterator<Item = X>` adds
  `<T as Iterator>::Item == X`.

A body is checked once under its env, an Ω per type parameter as
today. Its obligations on Ωs are proven by `Param` candidates. A
compound where clause (`where Option<T>: Clone`, `where V<T>: Sup`) is
an env predicate like any other, so the opaque model no longer meets a
form it "does not cover". **The opaque unsure path is removed**
(`opaque_unsure`, `opaque_unsure_tmpls`, the D4.4(g) exception for
them, `warning generic.unchecked`), and RT-C301-4/5/11/14 and
`rt_c301_011_where_compound_impl_predicates` (d14, d17) close: the
predicate is assumed in the body and proven at the call.

## 5. Projection obligations

`<P as Tr<A>>::X` is normalized by selecting `P: Tr<A>`:

- if selection is an impl, X is the impl's definition under the
  confirmation map, regions included (today's `proj_map` and
  `super_assoc`, which then becomes "normalize `Self::A` of the
  supertrait", selected by the full reference, review 4 F3);
- if it is a `Param` candidate, X stays an opaque projection type
  (`Ω::X`), with the env's equalities and bounds about it.

A **projection bound** `I::Item: Sup` (a where clause, an impl's
nested obligation) is the obligation `(normalize(I::Item)): Sup`. It is
proven like any other: after normalization at an instance (A5: f28,
b03, b02, b05), from the env in a template. `T::X: 'static` is the
region predicate on the normalized type. It is never proven by
"another bound trait's `X: 'static` of the same name" (review 4 F2), and
never from the written syntax.

## 6. Well-formedness of each impl (one pass, at the impl)

One pass `check_impl_wf(i)` replaces `check_impl_statics`,
`check_super_predicates`, `check_constrained` and `check_drop_impls`.
It proves the following with the impl's env (its predicates and the
implied bounds of its header) as the assumptions:

- **supertraits** (E0478, E0277): `Self: Sup<args>` for each
  supertrait. The region predicates of the proof must follow from the
  env (the region solver of today's `impl_regions::solve`, over the env's
  facts);
- **`trait St: 'static`** (E0477, E0310): `Self: 'static` as a region
  predicate on the header type with regions. This replaces
  `non_static_in` and its ten helpers (≈ 400 lines that read syntax);
- **associated-type bounds** (E0803's family, E0277, E0477; A6: b01,
  q01–q03): for each `type A: B` of the trait, `(the impl's A): B`;
- **constrained parameters** (E0207), for trait **and inherent** impls
  (u31: a type parameter used only in a method's signature): today's
  `constrains`, without the inherent-impl exemption for type
  parameters;
- **declared lifetimes** (E0261, j11, j13): every lifetime in the
  impl's `where` and its methods' signatures is declared by the impl
  or the method. Today an undeclared one in an impl `where` is dropped
  silently (`join_where_lifetimes` joins only declared ones);
- **Drop** (E0366, E0367): the header names the type with distinct
  parameters, and its env adds no predicate the type's declaration
  lacks. This is today's `drop_impl_wrong`, rephrased as: the Drop
  impl's env must be implied by the declaration's;
- **impl-level compound where clauses**: they are kept on the impl
  (today they get owner 0 and belong to nothing). They are assumed by
  its methods and become nested obligations of confirmation, like any
  other predicate (j06, j07 `where Self: 'static`).

## 7. How region obligations reach the borrow checker

There is one interface, `places/obligations.vl`:

- **An instance's signature** (`sig_compute`): for each obligation the
  front recorded for the instance (its bounds, the where clauses of its
  callee chain, the method's impl), the region predicates of its
  recorded proof are pushed to `sig.bounds` in U_SUBST and U_NAMED
  universals, as today's `bound_ties` does. The instance assumes them
  and its call proves them (D4.4). This replaces `bound_ties`,
  `impl_bound_ties`, `impl_predicates`, `param_bound_predicates`,
  `trait_arg_ties`, `impl_class` and `may_apply`. The equality ties
  (`B::Item` and `A::Item` one region, L14) come out of confirmation
  as pairs of predicates both ways, from the one selected impl only.
- **A body's call** of a function or method whose obligation was proven
  by an impl: the callee instance's signature carries them. A body's
  own obligations on Ωs are `Param` candidates and add nothing.
- **An impl's WF** (§6): the predicates are solved against the impl's
  env, with no body, by the small solver of `impl_regions`.

Nothing else turns a trait proof into regions.

## 8. What it replaces, its size, its order

Replaced, with the lines they hold today (`volec query show`):

| function(s) | file | lines |
|---|---|---|
| `impl_bound_ties` 153, `impl_predicates` 82, `param_bound_predicates` 32, `impl_class` 16, `may_apply` 10, `outlives_named` 15, `names_lifetime` 21, `ref_over` 31, `trait_arg_ties` 49, most of `bound_ties` (84) | places/regions.vl | ≈ 480 |
| `check_impl_statics` 39, `non_static_in` 171, `lifetime_static_in` 28, `param_static` 14, `param_assoc_static` 21, `assoc_static_in` 29, `impl_assoc_static` 8, `plainly_static` 43, `trait_static` 22, `omega_static` 24 | front/traits.vl | ≈ 400 |
| `check_super_predicates` 55, `super_needs` 47, `lifetime_needs` 15, `impl_proves` 60, `super_impls` 67, `super_assoc` 35 | places/impl_regions.vl | ≈ 280 |
| `where_preds_hold` + `pred_holds` (≈ 75), `assume_where_preds` 62 | front/traits.vl | ≈ 140 (into env elaboration) |
| the unsure path of `build_opaque_instances` (≈ 60 of 164), `Ctx.opaque_unsure_tmpls`, `generic.unchecked`, the D4.4(g) exception in `borrowck::solve::substitution_pair` | front/opaque.vl, solve.vl | ≈ 90 |
| `implements`, `implements_with`, `impl_applies` (their selection part; `impl_bindings` and `match_type` stay as the matcher) | front/traits.vl, convert | ≈ 100 |
| `check_constrained` 86, `check_drop_impls` + `drop_impl_wrong` 217 | coherence.vl, traits.vl | ≈ 300 (moved into §6, mostly kept) |

That is ≈ 1,800 lines touched, of which ≈ 1,300 are removed. New code:
selection with the side table ≈ 300, confirmation with the regioned
header walk ≈ 400, projection normalization ≈ 250, env elaboration
≈ 250, the places interface ≈ 200, the WF pass ≈ 350, diagnostics
≈ 150. That is ≈ 1,900 lines, plus ≈ 60 cases (each review finding
below, as err and ok pairs).

**Time:** 12–15 agent-days, plus a review round per milestone. Its own
release, 0.30.2 (or the first part of 0.31, before performance work,
which it affects through selection caching).

**Order** (each milestone ends green, with its findings' XFAILs
removed):

1. **M1 selection table** (2 days). The front records each proof's
   selection, by the full trait reference, and the places read it
   (`impl_bound_ties` keeps its body but takes the impl from the
   table). Closes A4 at the root, m01–m13 and RT-C301-15 (no candidate
   sets, no class order), review 4 F3's form at uses.
2. **M2 confirmation with regions** (3 days). The header walk over the
   self type and the trait arguments, and nested obligations recursively.
   Replaces `impl_bound_ties`, `impl_predicates`, `trait_arg_ties`,
   `param_bound_predicates`. Closes A1 (f12, f43, f47, h03, g02, h05),
   review 4 F1's forms (c13–c19, t01–t08), review 5's s-group through
   supertrait obligations.
3. **M3 env elaboration and the end of the unsure path** (3 days).
   Compound where clauses, supertraits and associated-type bounds in
   env. Closes RT-C301-4, 5, 11, 14, d14, d17, j06, j07, review 3 F3,
   review 4 F5's generic.unchecked.
4. **M4 projections** (2 days). Normalization with regions, projection
   bounds as obligations. Closes A5 (f28, b02, b03, b05), review 4 F2
   (projections by trait, not name), `<H as Tr>::X` through a
   supertrait.
5. **M5 the WF pass** (2–3 days). Supertraits from the impl's env,
   `'static` traits by region predicates (deleting `non_static_in`),
   associated-type bounds at the impl (A6: b01, q01–q03), E0207 for
   inherent impls (u31), E0261 (j11, j13), E0366/E0367 as an env
   implication (f06, f31, f32, f34, f35), impl compound where clauses
   owned by the impl.
6. **M6 deletion and an independent red-team round** (1–2 days). The old
   functions are deleted. Every rt_c301 XFAIL of this class is removed,
   and the 0.31 count of 0 holds for it.

## 9. The findings of reviews 3–5, and how each closes

| finding | what it was | closes by |
|---|---|---|
| R3 F1 | `non_static_in` read written syntax (aliases, `Self::Raw`, `fn` types) | M5: `Self: 'static` is a region predicate on the header type |
| R3 F2 | the lifetime map per bound, not over the whole signature | unchanged: `impl_regions::compare` (method vs trait signature) is not an obligation; it stays |
| R3 F3 | unsure templates' instances skipped (D4.4(g)) | M3: no unsure path |
| R3 F4, R4 F4a | Fn bounds naming a trait parameter or `Self::R` | M4: compared after normalization (today's `bound_lifetimes_as` is its stopgap) |
| R3 F5, R4 w04, w16 | widen_i32 | not this design: literal typing (RT-C301-10, 0.31) |
| R4 F1 (c13, c15, c19, c12, c06) | impl predicates not required at a generic call; supertraits | M2 (confirmation), M5 (supertraits at the impl) |
| R4 F4b (a08, a12) | header and where were two lists | done (`join_where_lifetimes`); kept as the impl's env |
| R4 F2 (a30–a36) | projection 'static by another trait's name; E0207 | M4 (normalization), M5 (E0207) |
| R4 F3 (c01, c09) | supertrait impl chosen without trait arguments | M1 and M4 (`super_assoc` becomes normalization) |
| R4 F5 | std's hash_map entries' undeclared `S: BuildHasher` | done (std fixed). M5 would report it as E0277 at the struct, as rustc does |
| R5 A1 | lifetimes in trait arguments (f12, f43, f47, h03, g02, h05) | M2 |
| R5 A2 | an operator or a method through a generic trait bound (`T: AddAssign<U>`, f42) and `where Self: 'static` (j06) | M1 and M2 (the operator's impl is a selection like any other), M3 (where Self in env) |
| R5 A3 | Drop impl's `'a: 'static` (f31, f06, f32, f34, f35) | done in 0.30.1 round 6 (`trait.drop_impl`); M5 rephrases it |
| R5 A4 | pattern impl hidden by a direct one (m10–m12) | stopgap in round 6 (every candidate's predicates); M1 at the root |
| R5 A5 | projection bounds `I::Item: Sup` (f28, b02, b03, b05) | M4 |
| R5 A6 | associated-type bounds `type A: Sup` (b01, q01–q03) | M5 at the impl, M3 at uses |
| R5 u31 | E0207 of an inherent impl | M5 |
| R5 j11, j13 | undeclared lifetime in an impl's where | M5 (E0261) |
| R5 m01, m03, m04, m13 (false errors) | every candidate's predicates required | M1 |
| R5 s07, g02, g09, g14, h05 (false errors) | predicates not assumed where rustc's env has them | M3 (elaboration) and M2 |
| R5 u33 (false error) | a parameter constrained through a projection's binding | M5: `constrains` through the env's equalities |

## 10. Invariants the implementation keeps

- **I-O1.** Exactly one function selects an impl for a trait reference.
  Every caller reads the recorded selection.
- **I-O2.** Every predicate an impl's body may assume (its header, its
  `where`, its parameters' bounds, its supertraits) is a nested
  obligation of every confirmation of that impl, or is proven at the
  impl from what every value of its header type has.
- **I-O3.** No proof reads written syntax for a lifetime fact. Lifetime
  facts come only from types with regions and the env.
- **I-O4.** Ambiguity, a cycle or a depth limit is never a "yes": it
  is a deferral or an error.

A test suite (`tests/run/rust_o_*`) states each invariant with must-fail
cases, one per path of §1. A canary in the gate counts the callers of
`select` against the callers of `match_type` on impls (0 outside
`select`).

## 11. Status and where the code differs (0.30.2)

**M1, the selection table: in.** `front/obligations.vl`'s `select(tr, t,
targs)` is the one function that chooses an impl for a trait reference.
It tries every impl of `tr` (its chain, `impls_start`) and keeps each
whose header matches `t` and whose bounds hold (`impl_applies`), whose
trait arguments are `targs` (`impl_targs`, or completed from them,
`complete_impl_targs_by`), and, for a parameter only the trait arguments
bind, whose bounds hold for the whole binding (`U: From<T>` of
`impl<T, U: From<T>> Into<U> for T`, which `impl_applies` leaves
unchecked). One is the choice; two are `SEL_AMBIG`; none after a depth
limit cut a search short is `SEL_LIMIT` (never a no). The front's
`has_impl` and `implements_with` ask it (their own builtins, an Ω's
bounds, `Into` by `From`, the intrinsics, are unchanged, before it). The
places' `impl_bound_ties` (`places/regions.vl`) takes the impl from it for
an instance's bound, for each supertrait (its arguments read with the
bound's and `Self`, `super_args`) and for each bound of the chosen impl's
parameters (read with the impl's bindings), and `trait_arg_ties` too;
`impl_class`, `may_apply` and `param_bound_predicates` are deleted, and
with them the class order and the "every candidate's predicates"
stopgap of 0.30.1's round 6.

Where the code differs from §3:

- **The table's key is the trait reference** (trait, self type, the
  context's `Self`, the trait arguments), not (use node or instance,
  bound index): an instance's types are concrete, so its reference is
  what the use determines, and uses that share one share the choice
  (`Ctx.sel_map`, `Ctx.sel_rows`). A choice is recorded only when made at
  the top of a search (`assoc_depth` 0, every impl known), with no depth
  limit met inside it (`Ctx.depth_cuts`, counted at each limit of the
  front's searches) and of types with no inference variable, Ω, opaque,
  error or closure type in them; a new impl empties the table. Every
  later ask of the same reference, the front's and the places', reads it.
- **The places' code is in `places/regions.vl`** (`impl_bound_ties`,
  `chosen`), not yet `places/obligations.vl`: M2 moves it there with the
  confirmation walk.
- **A bound whose arguments the places cannot read** (one naming what
  does not resolve with the instance's types and `Self`, the instance's
  impl type) is asked with no arguments (`targs` -1): one impl is the
  choice; several are each required, their predicates and their
  parameters' bounds', the 0.30.1 stopgap kept for this case alone. A
  bound written without arguments on a trait that has some (`T:
  PartialEq`) is asked with the trait's defaults (`PartialEq<T>`), and
  with none when no impl proves those (the front reads such a bound as
  "any arguments").
- **`trait.ambiguous`** (two impls for a reference whose arguments are
  known) and **`trait.overflow`** (a chain of nested bounds deeper than
  `MAX_ASSOC_DEPTH`) are reported at the call that made the instance.
  Neither occurs in the suite or in our own code: coherence leaves one
  impl per reference, and the front's own search meets the depth limit
  first (it then says the trait is not implemented).
- **Not yet through `select`:** the front's method dispatch in an
  instance (`convert::dispatch`, `has_generic_trait_fn`): `t.up()`
  through `T: Sub` with `trait Sub: Sup<i32>`, for a type with impls of
  Sup<i32> and Sup<i64>, is refused as ambiguous (rustc takes the bound's
  impl); the projections' impls (`direct_impl`, `proj_walk`, M4) and the
  impl-level checks of `impl_regions` (M5).

M1's cases: `tests/run/rt_c301_015_*` (review 5's m01, m03, m04, m13),
`tests/run/rust_o_m1_*` (the A4 forms m05, m10, m11; trait arguments
told apart by a nested type, a blanket impl beside a concrete one, a
supertrait's arguments, an impl parameter's bound with arguments three
levels down, impls told apart only by a region or `&'a T` beside
`&'static T`, which coherence refuses).
