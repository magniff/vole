# Vole with Rust's surface: the plan

A design document, 2026-10-30, written as the companion to
[rust-with-allocators-contracts-polonius.md](rust-with-allocators-contracts-polonius.md) (below, "the proposal"). It
reconciles two reviews of that proposal (one by Opus, one by Fable,
argued to agreement) with the decision taken since:

> Vole becomes Rust's surface in full: `&T` and `&mut T` are first-class
> types, Rust's syntax with Rust's meaning, a std of its own, Polonius,
> contracts and effects kept, allocators explicit with no implicitness,
> no macros for now, no `dyn`.

That decision is not argued again here. This document says how to get
there, what to correct in the proposal, and what is left to decide.
Nothing in it has been implemented.

## 0. What changes against the proposal

| proposal | this plan | why |
|---|---|---|
| three releases: N both checkers, N+1 compiler migrated, N+2 MVS removed | three phases with point releases and numbered gates: 0.26 decisions under MVS, 0.27.0–0.27.x the rust edition, 0.28 the flip; then 0.29 (the cuts, GPU first class) and 0.30 (Vulkan, regex) | every non-mechanical decision moves into 0.26, where today's tools make it; 0.27 is still 60–70% of the work |
| Polonius as Datalog relations, semi-naive, with a prefilter | rustc's current reformulation (`-Zpolonius=next`): NLL constraints, then loan reachability over a localized constraint graph; the location-insensitive solve is NLL and ships first | the Datalog engine was shelved upstream for its cost on large functions |
| `static mut` safe under the effect rule | Rust's rule: no references to a `static mut`; compiler globals become context structs in 0.26 | `f(&mut G)` where `f` writes `G` is a `noalias` miscompile (core audit 2, excl S10) |
| `Vec<T, A>` with no default | the same, and stronger: allocation is a capability, a function allocates only through an allocator reachable from its parameters, and types that hold one say so in their parameters (§2.0, decision 1) | a signature should say whether a function can allocate; `A = Gpa` would make `fn foo(v: &mut Vec<u8>)` read as allocator-free |
| allocator first: `Rc::new_in(gpa, x)`, `format_in(a, ..)` | allocator last, Rust's `allocator_api` order: `Box::new_in(x, a)` | twin fidelity; nightly's names exist |
| wrapping integers kept, `x / 0` panics | Rust's arithmetic with overflow checks always on: overflow, `/ 0` and over-shift panic, `wrapping_*` explicit | the proposal's own argument for division applies to `+`; with `usize`, `len() - 1` on empty must panic, not loop 2^64 times |
| a refuted contract is an error "decided by the optimizer" | decided by the fixed Level 1 procedure, before inlining, the same at every opt level | otherwise -O2 rejects what -O0 accepts, and an optimizer change breaks builds |
| "facts flow both ways across a call" | the callee's `requires` survives the call only for `&` and Copy arguments | anything reachable from a `&mut` may have changed |
| Send and Sync inferred with one positive vouch | auto traits with a positive *and* a negative vouch | `MutexGuard` holds a Sync `&Mutex` and must not be Send |
| no aliasing model | Tree Borrows, checked dynamically by `--check-unsafe` | `noalias` and `readonly` are only as sound as the unsafe code under them |
| "fits inside the own pass's slot" | budget: borrowck at most a quarter of typeck; typeck itself grows (autoderef, coercions, regions) and is measured | the own pass is 32% of check today; the cost of references is mostly in the type checker |

Corrections to the proposal's text: the pins are 66 attribute uses (53
`#[views]`, 13 `#[stores]`), all in compiler/std, none in compiler/src;
the 174 counts mentions, strings and std's embedded copy in
`front/stdsrc.vl`. §6 needs
`let mut arena`, `#[derive(Clone, Copy)]` on `Tok`, "three words" for
`Tok` and four for `Vec<T, &'a Arena>`, and a `requires` on `next` (its
bounds fact would otherwise cross the call from the body, which the
thesis forbids); the 3.4% is against the one-region rule that Revision 1
replaced; the thesis should say that effects stay inferred from bodies
(a flat set union, which converged), and that what failed is a summary
lattice with no identity, walked over the AST.

## The releases at a glance

| release | what |
|---|---|
| 0.26.0–0.26.x | Phase 1, under MVS (§1): the places IR, private fields, Rust's arithmetic, `usize`, `String`, the cell type, allocation as a capability, format literals, the raw-pointer decisions, the compiler's statics into context structs; `embed wgsl` and check-time WGSL (§10.4) |
| 0.27.0–0.27.x | Phase 2 (§6): the rust edition in the compiler and the new std, NLL first and the location-sensitive solve in a point release, `fix --edition rust`, gates 0–3; std::gpu's API with typed blocks |
| 0.28 | Phase 3 (§7): compiler/src flipped; MVS, the own pass and the old std deleted; then invariant newtypes and `debug requires` on `unsafe fn` |
| 0.29 | the cuts of §6 (const generics, `Rc`/`Arc`, `RefCell`, `may_dangle`, ...); GPU first class: translation ahead of time, interpreter tests, the eval gate |
| 0.30 | `embed regex`; Vulkan and Linux when the Linux backend returns (§13) |
| later | panics that unwind (decision 18) |

## 1. Phase 1, 0.26.x: every decision, under MVS

Each item lands in vole as it is today, with today's tools. When 0.26 is
done, the flip of the compiler's source is type-directed translation and
nothing else.

| item | what | the number |
|---|---|---|
| a. the places IR | a MIR-like lowering: places, explicit temporaries, drops and drop flags; move and drop elaboration per place on it; effects inferred on it (drops become IR, so `#[no_alloc]` must see them there). Today the middle IR starts at -O1 (`middle/ir/mod.vl`); the places IR runs at `check` and -O0 too, so `check` gets a whole new lowering | the own audit's 19 findings (already fixed on the own pass's drops) and the post-audit drop family (`793e4b8c` with `51075d9c`, `ea70255c`, `1d4215a4`) still passing on the IR's drops; the own pass's drop code deleted (0.26.1); `check` of the compiler within 1.10x of 0.25.5's. `e1bbdd94` is a view-summary family and stays the own pass's until 0.27 ([places-ir.md](places-ir.md) §11) |
| k. private fields | fields private to their module unless `pub`, as in Rust (0.25.6's plan; grammar.md: "vole has no private fields yet") | needed by (g), by `Gpa`'s private constructor and by invariant newtypes (§9.3) |
| b. arithmetic | Rust's, overflow checks always on; `wrapping_*`, `checked_*`, `Wrapping<T>`; float-to-int `as` saturating | bench at -O2 with checks on and off (time, instructions, vector loops); `--print-checks` counts removed by the range pass; the wrap-reliant sites in compiler/src (hashes, PRNGs) |
| c. `usize` | lengths and indices `usize`, `isize` where signed | `as i64` in compiler/src: 1,188 in code (`query grep 'as i64' --code --count`) |
| d. text | `Buf` → `String`, `[u8]` as text → `str` | `Buf`: 475 (`query grep Buf --word --count`) |
| e. raw-pointer parameters | the legacy `*T` parameters (the proposal counts 3,903, from its prototype; recount with `query`) decided into `let`, `inout` or a real raw pointer | unjustified unsafe sites, from 3,425 (`query unsafe --summary`) |
| f. globals | the 1,841 `static var` in compiler/src into context structs passed down `inout`; the context holds `Comp` and `Ast` as real arenas (§9.1) | `static var` count; compile cost. The largest MVS refactor attempted here (0.25.5 moved six tables): it changes most signatures and every view summary, so it runs last, alone, and stops at the first point release that fails the gate's compile-cost row |
| g. a cell type | `UnsafeCell<T>` and `Cell<T>` in std (0.25.6's plan); `#[sealed]` is retired by (k), so (g) only adds the cells | needed before arenas (`Allocator::allocate` takes `&self`) and before std's print statics move behind a `Sync` cell (§9.2) |
| h. allocation as a capability (§2.0) | every `_in` takes its allocator last; `Ambient` and every constructor without `_in` removed; the `= Gpa` defaults removed from std's types; types holding an allocator made generic over it (rule 3); statics and thread-locals refused an allocator in their type (rule 1); `Allocator` an `unsafe trait` | 0 uses of `Ambient`; 0 `= Gpa` defaults; 0 structs with an allocator field not in their parameters |
| i. format literals | f-strings become Rust's format grammar in plain functions: `println("{x} {y:?}")`, `format_in("{x}", a)` | 1,248 f-strings (814 in compiler/src, 434 in std) |
| j. small syntax | `where` as sugar for inline bounds; argument-position `impl Trait` | |
| GPU | `embed wgsl NAME { .. }`, check-time WGSL, `gpu.*`/`wgsl.*` as codes (§10.4) | the 0.26 row of §10.4 |

**The chain rule inside 0.26.** A release's compiler is built by the
previous one, so an item that changes the language lands in two steps:
the feature in point release k, and compiler/src's use of it in k+1.
This applies to (b), (c), (d) and (i). (k) is one step: `pub` on a field
already compiles under 0.25.5, which ignores it, so compiler/src's `pub`s
land in 0.26.0 before the rule turns on (stage 1 compiles compiler/src
against 0.25.5's embedded std; the tree's std is first compiled by
build1). The same holds for std APIs: one added in 0.26.k is used in
compiler/src from 0.26.k+1. Arithmetic is
order-sensitive: `wrapping_*` must exist in release k, and in k+1 the
hash and PRNG sites are rewritten to it before the checks turn on.
The first build of k+1, by k, then has no checks; its fixpoint build has
`wrapping_*` in its source and does not panic on its own hashes.

**Compile cost in 0.26.** Every point release passes the gate's
compile-cost row (it fails at 1.15x of the previous release for the
compiler, 1.5x for small programs). The places IR has its own budget,
`check` of the compiler within 1.10x of 0.25.5. Because (a), (f), (h)
and effects on the IR compound, 0.26 as a whole is held to 1.25x of
0.25.5, measured by its last point release.

**The order, at most three agents in each point release** (§13; agreed
in the 0.26.0 review, 2026-10-30):

| point release | in parallel |
|---|---|
| 0.26.0 | (a) the places IR, steps 1–3: built and elaborated at `check` by default, checked against the own pass by `--places-diff`, one agent ([places-ir.md](places-ir.md)); (k) private fields, which also retire `#[sealed]`; `embed wgsl` with the `gpu.*`/`wgsl.*` codes |
| 0.26.1 | (a) steps 4–8: both code generators read the IR and the own pass's drop code goes (two agents); (g) the cell type (after k) |
| 0.26.2 | effects on the places IR (after a); the features of (b), (c), (d) and (i), with (j) and `pub(crate)`/`pub(super)` (one agent, in sequence); embed's follow-ups: shader parts, the file form's own `FILES` entry, fluid2d, diagnostics 2–7's text forms, shared `const`s and `#[repr(wgsl)]` |
| 0.26.3 | (h) the capability rules (after g and k); compiler/src's migrations to (c), (d), (i) and `pub(crate)`, and (b)'s second step (the wrap sites, then the checks on), as one agent; (e) starts as a long branch |
| 0.26.4+ | (f) the statics, last and alone, because it changes most signatures; (e) merges when done |

**The 0.26.0 budget.** `check` of compiler/src at most 1.13x 0.25.5's
(the gate's row stops at 1.15x), shared out: the IR 1.10x, `embed
wgsl` 1.025x, private fields noise. Agents measure with
`tests/compile_cost.sh` against their branch's base and 0.25.5. The
IR gives back the own pass's drop placeholders (228M instructions) only
in 0.26.1.

Each item has one owning agent and its own design brief before code, as
the project does for every release; the integrator merges per batch
(AGENTS.md, tier 3).

## 2. Explicit allocation in Rust's surface

One rule: **an operation on a container may allocate from that
container's allocator; every other allocation names its allocator as a
value argument, last.** So `push`, `extend`, `clone()`,
`entry().or_default()` and `String::from_utf8(vec)` allocate from the
allocator the type already names (`alloc(A)` shows it), and nothing else
allocates without a value in the call.

| Rust | vole |
|---|---|
| `Vec::new()`, `with_capacity(n)` | `Vec::new_in(a)`, `Vec::with_capacity_in(n, a)` |
| `Box::new(x)`, `Rc::new(x)`, `Arc::new(x)` | `Box::new_in(x, a)`, and `Rc::new_in`/`Arc::new_in` when they land in 0.29 (§6), nightly's names |
| `String::from(s)`, `to_string()`, `to_owned()`, `to_vec()` | `String::from_in(s, a)`, `to_string_in(a)`, `to_owned_in(a)`, `to_vec_in(a)`; no `From<&str> for String` |
| `collect()` | `collect_in(a)` over `FromIteratorIn` |
| `format!(..)`, `vec![..]` | `format_in("{x}", a)` (inline captures only: there are no variadics), `Vec::from_in([..], a)` |
| `concat`, `join`, `repeat`, `replace`, `to_uppercase` | `_in(a)` each |
| `slice::sort` (stable: allocates) | `sort_in(a)`; `sort_unstable` keeps Rust's name and meaning and is `#[no_alloc]` |
| `HashMap::new()`, `RandomState` | `HashMap::new_in(a)` with a fixed-seed hasher, as today (no ambient randomness); `with_hasher_in(h, a)` for a seeded one (decision 2) |
| `thread::spawn(f)` | `thread::spawn_in(f, a)`; today it allocates through C, unnamed; `thread::scope` stays allocation-free |
| `panic!("{x}")` | formats into a fixed stack buffer and truncates, so `panic` stays callable from `#[no_alloc]` code |
| `Default` | for types that hold no allocator; `DefaultIn<A>` with a built-in derive for those that do |
| `env::args()`, `fs::read_to_string`, `Path::join` | `_in(a)` each |
| a `static` container | impossible: a static's type may not hold an allocator (§2.0 rule 1); programs keep containers in `main` and pass them down |
| returned closures (`impl Fn`) | no allocation; nothing changes |

`Gpa` stays zero-sized, with no public constructor (private fields,
Phase 1(k)): the runtime makes one, `main` receives it.

### 2.0 Allocation is a capability, visible in the signature

The rule above makes every allocation *name* an allocator somewhere. The
stronger rule, the one this plan adopts (decision 1): **a function can
allocate only through an allocator reachable from its parameters, and
its signature shows that one is.** A function given no allocator cannot
allocate at all. That is a safety property (no unexpected OOM or latency
in a path that was handed none) and a performance one (no hidden
`malloc` in a hot loop). Stated exactly: **a function allocates no heap
memory, and none from memory its caller owns, unless an allocator is
reachable from its parameters.** It may still build a `FixedBuf` over
its own locals; that is visible in its body and in its effects as
`alloc(FixedBuf)`, and harmless: what it allocates is tied to the
frame's region and cannot escape the call. The rules that make it hold by construction:

1. **No ambient authority.** `Gpa` has no public constructor (only `main`
   receives one), and every other allocator is built from a parent
   (`Arena::new_in(parent)`) or over memory it is lent
   (`FixedBuf::new(&mut buf)`). **The type of a `static`, a `static mut`
   or a thread-local may not contain an allocator**, checked on the type
   by the auto trait `AllocFree` ("holds no allocator": no allocator
   type, no `AnyAlloc<'_>`, nothing whose parameters name one, no
   closure capturing one). It is not enough that no
   constant makes a `Gpa`: a static set at run time (`OnceLock<Vec<u8,
   Gpa>>`, a thread-local initialized from `main`'s `gpa`) would let any
   function allocate with no parameter. So an allocator value inside a
   function can only have come in through a parameter. Today's holes
   are closed: `Ambient` and the constructors without `_in` go (Phase
   1(h)); `thread::spawn` and panics stop allocating through C.
   `Allocator` is an `unsafe trait`, as in Rust: every impl is `unsafe
   impl` with a SAFETY comment naming where its memory comes from, so a
   type built from nothing over `malloc` (today's `Comp {}`, `Ast {}`)
   is visible as the global allocator it would be.
2. **No default allocator type.** `Vec<T, A>`, `String<A>`,
   `HashMap<K, V, A>`, `Box<T, A>`, `Arena<P>`: `A` is always written.
   `fn foo(v: &mut Vec<u8, Gpa>)` says it may allocate from `Gpa`;
   `fn foo(v: &mut Vec<u8>)` is an error with `try:` lines for `Gpa`
   and for a generic `A`. This is the one deliberate break of "a Rust
   program that uses only what vole has is a vole program": Rust's
   `Vec<T>` is `Vec<T, Global>`, and vole has no `Global`.
   `rustc-twin`'s shim writes `Gpa` into the Rust side.
3. **A type that holds an allocator says so in its parameters.** A field
   of allocator type, or of a type holding one (`Vec<Tok, Gpa>`,
   `&'a Arena<P>`), is allowed only if the struct is generic over it or
   the allocator type appears in the struct's parameters:
   `struct Parser<'s, A: Allocator> { toks: Vec<Tok<'s>, A> }`, used as
   `Parser<'s, Gpa>` or `Parser<'s, &'a Arena<P>>`. Otherwise `fn f(p: &mut
   Parser)` could allocate with nothing in its signature saying so.
   Rule 2 makes allocators visible in std's types; rule 3 makes them
   visible in every type.
4. **What a signature then says.** The parameter types decide what a
   function may allocate from, readable without its body:

   | parameter | may the function allocate? |
   |---|---|
   | `&[T]`, `&str`, `&T` where `T` holds no allocator | no, by construction |
   | `&Vec<T, A>` | only through `A` (e.g. `clone`, which reuses `A`) |
   | `&mut Vec<T, A>`, `Vec<T, A>` | yes, from `A` (`push`, `extend`) |
   | `a: &'a Arena<P>`, `gpa: Gpa`, `a: A` | yes, from it |
   | `f: F` where `F: FnMut(..)` | whatever `f`'s captures may: the caller passed them |
   | `x: &T` or `x: T` with `T` a type parameter (`T: Clone`, `T: Display`) | whatever `T` holds: the caller chose `T` (`Vec<u8, Gpa>` makes `x.clone()` allocate). A bound `T: AllocFree` (the auto trait of rule 1) rules it out |

   Effects then report what the body actually does: `alloc(A)` is
   inferred, and `#[no_alloc]` forbids it even when an allocator is
   reachable ("may hold a Vec, must not grow it"). The capability rule
   says what *can* happen from the signature; the effect says what
   *does*.

**What it costs.**

- Verbosity: application code writes `Vec<u8, Gpa>`, `String<Gpa>`.
  That is the point, but no std alias (`type GVec<T> = Vec<T, Gpa>`) is
  offered: it would hide the allocator again.
- Generic pressure: libraries that grow containers are generic over `A`
  or take `AnyAlloc<'_>` (§2.1). Libraries that only read take `&[T]`
  and `&str`, and the guide teaches that first. Most programs have one
  or two allocator types, so monomorphization adds few instances.
- `Clone`: kept with Rust's meaning (it reuses the source's allocator,
  which the parameter type shows); `clone_in(a)` moves to another.
  `#[derive(Clone)]` on a type generic over `A` needs `A: Clone`. A
  stricter variant, `Clone` only for allocator-free types, is possible
  but breaks every derive; not recommended.

**Zig, for comparison.** Zig 0.15 went further and made its containers
unmanaged: no stored allocator, `list.append(gpa, x)`,
`list.deinit(gpa)`. That needs no rule 3, because no type holds an
allocator, but it needs an explicit `deinit` everywhere. Vole has
Rust's `Drop`, and `Drop` needs the allocator to free, so vole's
containers stay managed. Rules 1–3 give the same guarantee Zig's design
gives (an allocator in the signature or no allocation), with RAII kept.

### 2.1 Arenas, first class (Zig's model, with regions)

Std keeps arenas as a first-class way to allocate, not a crate's
afterthought: Zig's discipline, allocators as values that compose, with
Rust's regions making the parts that are `unsafe` or attribute-checked
today safe. What std has now, and what it becomes:

| today (0.25) | becomes | what regions buy |
|---|---|---|
| `Arena`, a copyable handle to its state; `reset` and `free_all` are `unsafe` | `Arena<P: Allocator>` owns its chunks (taken from parent `P`, Zig's `ArenaAllocator.init(child)`); `Drop` gives them back; containers allocate through `&'a Arena<P>` | `reset(&mut self)` is safe: the exclusive borrow proves no container, `&T` or `&str` in the arena is live. `free_all` is just the drop |
| `ScopedArena` with `#[scoped]` (not returned, not captured, not in a static) | `arena.scope(\|s: &Scope<'_>\| ..)`, `arena_scope(parent: &P, \|s\| ..)` over any parent allocator: the scope is a late-bound region, as `thread::scope`'s is. This is also the scratch checkpoint: a nested scope gives back what it allocated while older containers stay live (a `mark`/`reset_to(&mut self)` pair cannot work, since every older container holds `&'a Arena<P>`) | `#[scoped]` is deleted: the region keeps what was allocated in the scope inside it |
| `FixedBuf`, holding a view of `mem` with `#[views(mem)]` | `FixedBuf<'b>` over `&'b mut [u8]` (counters in a `Cell`), allocating through `&FixedBuf<'b>` | the `#[views]` pin becomes the type's region |
| `Arena::none()`, a constant for statics | removed: there are no static containers | |
| (none) | `arena.alloc(x) -> &'a mut T` for `T` without drop glue (`needs_drop::<T>()` false, checked at compile time); `alloc_slice_copy`, `alloc_str -> &'a str`; `TypedArena<T>` runs drops at its own drop | reference graphs (`&'a Node`) in an arena, with no raw pointers and no indices |

The choice of type: `Arena` uses `Cell` for its bump pointer (Phase 1(g)),
because `Allocator::allocate` takes `&self`.

Arenas compose like Zig's allocators: an arena over a fixed buffer
(`Arena<&'b FixedBuf<'s>>`: no heap at all), an arena over an arena
(per-request inside per-connection), a scope over either. Every
container names its arena in its type (`Vec<Tok<'s>, &'a Arena<P>>`).
`alloc(A)` shows which arena an allocation comes from, and a
`#[no_alloc]` function cannot allocate from any of them.

**Erasing the allocator's type.** Zig passes one `Allocator` type, a
pointer and a vtable, so library code is not instantiated once per
allocator. Vole has no `dyn`, but std can define the same thing as a
plain struct of function pointers: `AnyAlloc<'a>`, made from any `&'a
A` (`a.erase()`), itself an `Allocator`. A library taking `a: AnyAlloc<'_>`
compiles once. A library generic over `A: Allocator` inlines the arena's
bump. Std offers both, and the guide says when to use each (decision 9).

The arena patterns `--check-alloc` already checks (blocks given back at
a reset or a scope's end) stay; the borrow checker makes them compile
errors in safe code, and `--check-alloc` keeps checking unsafe code.

## 3. Std: the traits Rust's surface needs

Changed in shape by explicit allocation:

- `FromIterator<T>` → `FromIteratorIn<T, A>` (`from_iter_in(iter, a)`);
- `ToString` → a blanket `ToStringIn` over `Display`;
- `ToOwned` → `ToOwnedIn<A>`, and `Cow<'a, B>` → `Cow<'a, B, A>`;
- `Default` plus `DefaultIn<A>`; `mem::take` only for `Default` types;
- `Clone for Vec<T, A> where A: Clone`, plus `clone_in(b)`;
- `Allocator` in Rust's shape (`&self`), with the blanket impl for `&A`;
- `Borrow<str> for String<A>`, so `HashMap::get(&str)` works: `Q: ?Sized`
  is in the minimum, and `Hash` must not depend on `A`.

New, because references make them expressible: `Deref`/`DerefMut`,
`Index`/`IndexMut`, `AsRef`, `From`/`Into`/`TryFrom`,
`PartialEq`/`PartialOrd` (floats), `Hasher`/`BuildHasher`, `Send`/`Sync`
as auto traits.

Different from Rust because there is no `dyn`: `Formatter` is a concrete
type over an internal sink enum, not `&mut dyn Write` (a generic
`Formatter<W>` would monomorphize every `Debug` per sink); `Error` has
no `source()`; `?` converts through `From` only.

Without macros: `println`, `print`, `eprintln`, `format_in`, `write`,
`panic`, `assert`, `assert_eq`, `unreachable`, `todo` are functions whose
format literal the compiler checks; `#[derive]` stays built in;
`matches!` and `dbg!` have no form (use `if let`, `let else`);
thread-locals are `#[thread_local] static` with a `with(|x| ..)` API,
holding allocator-free values only (§2.0 rule 1).

## 4. The borrow checker

**IR.** Phase 1's places IR, the one IR for moves, drops, borrows,
effects and lowering. Regions are inferred per function; signatures
carry them, elided by Rust's rules.

**Algorithm.** rustc's reformulation of Polonius:

1. constraint generation as NLL does it, `'a: 'b @ p`, from the IR;
2. region liveness from the IR's liveness pass;
3. the location-insensitive solve (this is NLL): most functions end here;
4. only on functions where step 3 finds an error, the location-sensitive
   solve: a loan is live at `p` if its issuing region reaches, in the
   localized constraint graph, a region live at `p`. This is what accepts
   problem case 3.

**Cost.** Liveness is bitsets over points × regions; reachability is
about loans × edges, and only where step 3 found an error. Budget:
borrowck at most a quarter of typeck on the self-build, measured at
gates 2 and 3 (§6).

**Two-phase borrows.** A flag on the creation of a `&mut`: between
reservation and activation it conflicts like a shared borrow. 422 call
sites need it (`v.push(v.len())`).

**Drop check.** A drop uses every region in the type except those of
`#[may_dangle]` parameters. Variance is computed once per type
definition, as a fixpoint over fields; `&mut T` and `UnsafeCell<T>` are
invariant. Until `may_dangle` lands, dropck is conservative.

**Threads.** Send and Sync are auto traits. Scoped threads use ordinary
`'scope`/`'env` regions. In the user-visible lattice, the effects `global` and
`sync` on statics only concern `static mut`, which is `unsafe` to touch
at all, so Phase 1(f) is mandatory; the internal static-access bit of
§9.2 covers `Sync` cells too.

**`rustc-twin`.** A guide or bench program accepted only by the
location-sensitive solve is twinned with nightly's `-Zpolonius=next`;
the rest with stable rustc plus an `allocator_api` shim (`String<A>`,
`collect_in`, `format_in`, `to_string_in` as extension traits).

## 5. Unsafe and contracts under references

**Aliasing model: Tree Borrows.** It accepts what real unsafe code does
(two-phase borrows, a `&mut` passed and re-read, round trips through
raw pointers), has simpler state than Stacked Borrows, and justifies
both `noalias` on `&mut` and `readonly` on `&` outside `UnsafeCell`.
`--check-unsafe` (middle/unsafecheck.vl) gains retag events into a
shadow tree per allocation, as a gate row. It is the only way std's
SAFETY comments get checked; without it the core audit's `noalias`
miscompiles come back through unsafe code. Raw pointers are spelled
`*const T` and `*mut T`.

**Contracts.**

- Order at a call: evaluate the argument places, run `requires` over
  shared reborrows of them, then take the `&mut` borrows (two-phase
  covers receivers). This is today's `requires_call` order.
- A clause is type-checked with every `&mut T` parameter seen as `&T`,
  so it cannot write through its parameters. That is not "mutates
  nothing": `&Cell<T>` writes through `&`. The purity check
  (`contract.effect`, no `io`, `alloc`, static access or interior
  mutation) stays alongside the types.
- `old(e)`: `e` is evaluated at entry into a Copy temporary
  (`old(v.len())`, `old(*r)`); `old(r)` of `r: &mut T` is rejected.
- `ensures` on `-> &mut T` may read `*result` and `old` facts only:
  `self` is borrowed by `result`.
- After a call, the optimizer keeps the callee's `requires` for
  arguments the callee cannot have changed: `&T` with `T: Freeze`, and
  Copy values that contain no raw pointer. It drops it for anything
  reachable from a `&mut`, a raw pointer or an `UnsafeCell`.
- Refuted at compile time means refuted by the Level 1 procedure
  (intervals, congruences, callees' `ensures`; no solver), before
  inlining; a refutation in a monomorphized instance names the instance.

## 6. Phase 2, 0.27.x: the rust edition

The compiler's own source stays MVS throughout 0.27. One program is one
edition; no mixed-edition modules are needed. The binary carries two
fronts, two stds and two preludes (stdsrc.vl twice), and tests, `query`,
`fix`, the LSP and the guide get an edition switch (`// EDITION:` in
tests/run).

**The std's API comes first.** The translator type-checks its output
against the new std, so the new std's API is fixed before the translator
is written. It is a redesign, not a port: `v.get(i)` returns
`Option<&T>`, iterators yield `&T` (`iter_mut` yields `&mut T`),
`entry`, `Option<&mut T>`, `take`.

**The minimum 0.27 holds:** references, regions, elision, variance, NLL,
two-phase borrows, autoref and autoderef, `Deref`, `Index`, reborrows,
match ergonomics, closures with `Fn`/`FnMut`/`FnOnce` and late-bound
regions in bounds (`retain`, `sort_by`, `for_each` need them), `[T]` and
`str` behind references, `Box<T, A>`, `*const`/`*mut`, `impl Trait` in
argument and return position of free functions and inherent methods
(returned closures and `-> impl Iterator<Item = &T>` are what agents
write; return position is an opaque type with Rust 2024's capture rule,
shipped without `use<..>`, which only removes captures; in trait
methods it is cut to 0.29), guards with `Deref` and
`Drop` (std::gpu's mapped views and passes, §10.1), built-in impls for
`[T; N]` of every `N` (`Clone`, `Copy`, `Debug`, `PartialEq`, `Hash`,
`Default`, `IntoIterator` where `T` has them, with a built-in by-value
`array::IntoIter<T, N>`; `Vec::from_in([..], a)` is a built-in generic
over the length) until const generics replace them, a compiler-provided
`Has<M>` for buffer usage sets (§10.1),
the std core (Vec, String, HashMap, slices, iterators, fmt, io,
`thread::scope`, and the arenas of §2.1 with `AnyAlloc`), and the
translator.

**Cut to 0.29:** const generics, `Rc` and `Arc`, `RefCell` (its `Ref`
and `RefMut` guards) and `Mutex`'s lock guard (`with(|d| ..)` stays),
explicit `for<'a>`, disjoint-field closure capture (whole variables
first), user-defined DSTs (`?Sized` only for `str` and `[T]`), unsize
coercions beyond `&[T; N] → &[T]`, `#[may_dangle]`. **Cut to a 0.27
point release:** the location-sensitive solve, added behind the NLL
filter once NLL is green.

Until `#[may_dangle]`, dropck is conservative: a `Vec<&'a T, Gpa>`
needs `'a` live at its drop, which the translator meets on declaration
order (a borrowed value declared after the Vec holding it). It reorders
the declarations or reports them; containers on a non-freeing allocator
(`Allocator::FREES`, §9.1) are not affected when `T` needs no drop.

**The translator, `fix --edition rust`.** It is type-directed: `let`
parameters become `&T` (or `T` for Copy), `inout` becomes `&mut T`,
`sink` becomes `T`, a view `[T]` becomes `&[T]`, `&x` at a call becomes
`&mut x` or `&x` from the parameter's type, `var` becomes `let mut`.
`v.len` on a std container (a read, which 0.17's
`len_reads_as_method` lets through) becomes `v.len()`. Two parts are
not mechanical:

- *regions on structs.* `query views` is level-aware but indexed by
  parameter, with no identity: it says which parameters a result views,
  not which of a struct's two regions. Where it decides, the translator
  writes the region; elsewhere it writes `'_` and lets 0.27's inference
  fail loudly, for a hand fix;
- *std calls.* A rewrite table per std item (`v.get(i)` →
  `*v.get(i).unwrap()` or `v[i]`, `.copied()`), chosen by type.

**Gates, one number each, per point release:**

0. a hand-translated subset of tests/run passes in the rust edition;
1. the new std passes its tests at -O0 and -O2 under `--check-alloc`;
2. `fix --edition rust` round-trips the examples, bench and tests, and
   the guide and bench programs twin with rustc;
3. `fix --edition rust compiler/src`, run under 0.27, leaves N errors.
   N is printed every point release. Phase 3 starts at N = 0.

At every gate, an MVS program compiles no slower than under 0.26's last
release: the existing compile-cost row measures the MVS front's `check`
of the compiler and a hello-world, and the binary's size with two
embedded stds is printed. The per-release no-regression rule holds for
the two-front binary too.

**The migration surface beyond compiler/src and std,** translated or
regenerated at gate 2: the run cases (about 2,800 in tests/run, with
`// EDITION:`), the transcripts of tests/query (70) and tests/refactor
(160), whose positions move with every std rewrite and which are
regenerated by the runner's record mode and reviewed as a diff, the LSP's
tests, the guide's 38 topic files (their examples are compiled by
`tests/run.sh guide`), the examples (each with its tests/examples case),
tests/wgsl, the Book, and every `explain` entry.

## 7. Phase 3, 0.28: the flip

The compiler's source is translated by `fix --edition rust`, with
Phase 2's hand fixes, and 0.28 is built by 0.27. The chain is unchanged:
each release is built by its predecessor and reaches its fixpoint, so
`chain-fresh` stays valid. 0.28 deletes the own pass, the MVS edition,
the old std, the `own.*` codes, `query views` and `fix --only
conventions`; there are no users, so there is no deprecation release.
The guide, the Book, `explain`, the LSP and the suite's MVS cases go to
the rust edition in the same release (the suite already translated at
gate 2).

0.28.x, right after the flip, adds what needs only Rust's surface and
Phase 1's private fields: invariant newtypes and `debug requires` on
`unsafe fn` (§9.3). 0.29 adds the cuts of §6, and the proposal's §10
(Level 1 `static requires`, const generics) follows from there.

## 8. Risks

- **0.27 is most of the work** and the longest time with two fronts in
  one binary. Gate 3's N is the progress number; if it stalls, the plan
  is wrong somewhere, not late.
- **Compile speed.** References move cost into the type checker
  (autoderef, coercions, region variables), not only into borrowck.
  Measure typeck and borrowck separately from gate 0 on.
- **Overflow checks and the optimizer.** A checked `+` on an induction
  variable blocks SCEV, unrolling and vectorization unless the range pass
  proves no wrap. Measured in Phase 1(b), before anything depends on it.
- **Agents.** The product question is decided, but it should still be
  measured: run the eval tasks on the rust edition once gate 2 passes
  and compare borrow errors per run, turns, and the share of errors with
  a mechanical `try:` against the Rust baselines and against 0.25.
- **Diagnostics.** Borrow errors have fewer mechanical fixes than vole's
  errors today. Every `borrowck.*` code needs an `explain` and, where one
  exists, a `try:` that a test runs.

## 9. Arenas, effects, contracts: what they are for

The three things vole keeps over Rust, measured in the tree at 0.25.5
(Fable took effects and contracts, Opus arenas). The finding common to
all three: **std uses them, the compiler and agents do not.**

| | std | compiler/src (code only) | agent-written evals (149 files) |
|---|---|---|---|
| arenas (`arena_scope`, `Arena::new_in`, `FixedBuf`) | gpu, wgsl | 2 (`cli/build.vl`, `cli/run.vl`: config reading) | 0 |
| contracts (`requires`, `ensures`) | 132 `requires` (121 in std::gpu), 0 `ensures` | 0 (4 `debug requires`) | |
| effect declarations (`#[pure]`, `#[no_alloc]`, `#[effects]`) | 125 `#[pure]` (122 on functions, 3 on `Eq::eq`, `Ord::cmp`, `Hash::hash`); 149 `#[effects]`, nearly all on `extern "C"` declarations, plus `Allocator`'s methods | 0 | |

None of the three is dead weight; each was blocked or blunted by
something the flip removes. The plan treats adoption as a deliverable
with a number, starting with the compiler.

### 9.1 Arenas

**What they buy, measured.** `bench/arena_trees` (binarytrees, nodes in
two arenas, one reset per tree): 32 ms against binarytrees' 168 ms and
`cc -O2`'s arena twin at 39 ms (roadmap, 0.18.1 bench); 693 M
instructions against 5,102 M. The bump path inlines through the generic
`Allocator`, the refill is cold. No other feature in vole has a 5x on
the bench.

**Why nobody uses them.** The bench is all `unsafe`: raw `*Node`,
`unsafe { a.reset() }`, `unsafe { a.free_all() }`. MVS has no type that
says "a reference into this arena", so a graph in an arena is raw
pointers, a reset is the programmer's promise, and a scope needs
`#[scoped]`, a special second-class rule. Regions remove all three
(§2.1): `arena_trees` becomes safe code, `&'a Node<'a>` with
`arena.alloc(..)` and a safe `reset(&mut self)`.

**The compiler was designed for them and could not have them.**
`base/comp.vl` defines two allocators: `Comp` for what lives as long as
the compilation (types, symbols, texts), `Ast` for tokens and nodes, to
be "released once the program is lowered", and says "T6 makes each an
arena". Neither happened: both are zero-sized structs calling `malloc`
per block, so a static can hold them (`static var NODES: Vec<Node, Comp>
= Vec::new_in(Comp {})`). That is a global allocator in all but name,
and the AST is never released, because nothing can prove that no view
into it survives lowering.

rustc is the existence proof for the other design: `TyCtxt<'tcx>`,
types interned as `&'tcx` pointers into arenas living as long as the
compilation. The plan for vole's compiler:

1. Phase 1(f)'s context struct holds `Comp` and `Ast` as real arenas
   (still MVS: handles, unsafe reset with a SAFETY comment).
2. After the flip: `Ctx<'c>` holds `&'c Arena<Gpa>`; the AST arena is a
   region `'ast`, dropped after lowering, and borrowck proves nothing
   refers into it. `Comp {}` and `Ast {}` as constants are deleted.
3. The middle end runs a scratch arena per function per worker
   (passes allocate worklists and maps per function, in parallel at
   -j8), reset after each function: no malloc/free churn, no contention
   on the C allocator between threads.
4. Tables keep `u32` ids, not `&'c Node` graphs: ids are half a
   pointer, and the on-disk cache needs a serializable form (it is the
   largest part of a cold `check` of the compiler: 137 ms cold, 17 ms
   warm, `--time-passes` at 0.25.5). rustc does the same (ids for cacheable data,
   `&'tcx` for interned types). The arena owns the storage either way.

Number: malloc calls and peak RSS of a self-build, and `check` time,
before and after each step.

**One rule std needs for this to work: allocators that do not free.**
A node in an arena usually holds a list (`kids: Vec<Node, &'a Arena<P>>`).
That Vec has a `Drop`, so `needs_drop::<Node>()` is true and
`arena.alloc(node)` is refused, which pushes everyone to `TypedArena` or
raw pointers again. `comp.vl` already planned the answer ("its `free` a
no-op, so values in it skip destruction"): an associated constant
`Allocator::FREES: bool` (false for `Arena<P>`, its scopes and
`FixedBuf`; true for `Gpa`, and for `AnyAlloc`, which cannot know what
it erased), and `needs_drop::<Vec<T, A>>() == needs_drop::<T>()` when
`!A::FREES`. The element drops still run where `T` needs them; only the
no-op frees are skipped. bumpalo's `into_bump_slice` is the library form
of the same thing; vole can make it the type system's. One behaviour
changes with it: today's `Arena` gives a large block (over 32 KB, a
chunk of its own) back individually (`arena_large_free`,
`flat/alloc.vl`). With `FREES = false` a skipped drop keeps it until the
arena is reset or dropped. That is the arena's contract, and
`--check-alloc` reports an arena's high-water mark.

**Making agents reach for them.** Agents allocate with `Gpa` because the
guide teaches it first and nothing tells them otherwise. Two tools:
`volec run --alloc-profile` (allocation counts per call site, from the
checking allocator `middle/checkalloc.vl` already builds), with a `try:`
on a hot site whose blocks die together ("these 40k blocks are freed at
the end of `parse`: give `parse` an arena"); and a guide topic
`guide arenas` with the four patterns (per-parse, per-frame,
per-request, per-function scratch), each compiled by the guide's tests.

### 9.2 Effects

**What they buy today.** The optimizer reads three bits through
`middle/ipo.vl: effects_attrs`: `willreturn` (no `diverge`), `nopanic`,
and `readnone`/`readonly` only for C functions with numeric parameters
(libm); for vole functions those come from the IR's own inference.
LICM, GVN and DCE use them on calls (the `purecall` bench: 291 → 74 ms
in 0.16, mostly from the IR's inference). The other consumers: the
thread check for statics, `--check-alloc`'s sites, contract purity
(`contract.effect`), the code cache's hash, `query effects --why`, the
LSP. Production use is the C boundary (most of std's 149 `#[effects]`), three pure
trait methods (`Eq::eq`, `Ord::cmp`, `Hash::hash`, which make HashMap
and contract conditions sound) and 122 `#[pure]` pins in std.

**The lattice is saturated.** `--print-effects` on compiler/src: of
8,321 functions, 83% are `global`, 46% carry all of `alloc io global
panic diverge` (11% exactly that set), 5% are `none`. It is not only the compiler's statics:
every program that prints is `io global`, because `println` reaches the
static `FMT_THREADED`. Today the effects carry information only on leaf
functions.

**Per effect, under Rust's surface:**

| effect | fate | why |
|---|---|---|
| `io` | keep | irreducible: no type says a function writes a file |
| `alloc(A)` | keep | a type says *which* allocator, not *whether* a call allocates; `#[no_alloc]` is the only way to say a loop allocates nothing, and `alloc(&'a Arena<P>)` vs `alloc(Gpa)` is what composes with arenas |
| `panic` | keep, and decide its interaction with overflow checks (below) | irreducible |
| `diverge` | keep | `willreturn` for LICM |
| `unsafe` | keep | informational, own body only |
| `global` | shrinks to "touches a `static mut`", which is already `unsafe` | Phase 1(f) and Rust's static rules; std's print statics go behind a `Sync` cell so `println` stops being `global`. The 83% disappears |
| `thread`, `sync`, `tls` | cut from the user-visible lattice | their job (turn off `readnone` for memory other threads see) is now Send/Sync and `UnsafeCell`'s; keep an internal bit only if measuring shows the optimizer needs it |
| CPU features | keep | a capability, not memory |

New with references: a function is `readonly` by its signature when
its parameters are `&T` with `T: Freeze` (no `UnsafeCell` anywhere in
`T`) or Copy types that contain no raw pointer, its body touches no
static of any kind (static access stays an effect bit, internal if not
user-visible), and it has none of `io`, `alloc` or `unsafe`. Raw
pointers are Copy and a `Sync` cell in a static writes without
`global`, so neither condition may be dropped. Today `readnone` is
granted only to C functions with numeric parameters, for exactly these
reasons; afterwards it holds for most of std's accessors.

**The stability rule.** Effects are inferred from bodies callees-first,
the same shape that broke the view summaries. It did not break effects
because the lattice is a few bits, monotone, with no identity to lose
(the core audit found no inference hole). What is wrong is the meaning
of a declaration: today callers see the inferred set even under a
declaration, so a body change silently changes every caller. The rule:

1. a declared bound is the signature: callers see the declaration;
2. std's `pub` items declare their effects, written once by `fix --only
   effects` and shown by `query items`; a std body that outgrows its
   declaration is an error in std, not a change in user programs. A
   declaration on a generic item is parametric: it names the body's own
   effects plus those of its callback and type parameters, per instance
   (`fn retain<F: FnMut(&T) -> bool>(&mut self, f: F)` declares
   `#[effects(panic, F)]`): a type or callback parameter named in the list
   stands for its effects, so `#[effects(alloc(A), T)]` on a function
   with `T: Clone` reads "mine plus `T`'s". In a bound the list says
   what the parameter may do (`F: FnOnce() + effects(alloc(A), panic)`).
   Inference needs no quantification; declarations do, and `fix --only
   effects` writes this form;
3. everything else is inferred and pinnable; a program's `pub` items get
   a lint with a `fix`, not a requirement;
4. trait methods and the C boundary declare, as today.

**Inference moves to the places IR**, after drop elaboration and before
borrowck. Today drop placeholders are made in the type checker so the
inference sees them; once drops are IR (Phase 1(a)), `#[no_alloc]` sees
every drop, including the ones the own audit found missing. Generics
and closures need nothing new: effects are exact per monomorphized
instance, so inference needs no quantification; declarations on generic
items use rule 2's parametric form.

**Panics and overflow checks.** With overflow checks always on
(decision 6), every `+` may panic, so `#[no_panic]` fails on all
arithmetic unless the checks are discharged, and the guide promises
effects never depend on `-O`. Resolution: `#[no_panic]` is checked
against Level 1 (§9.3), a fixed procedure independent of `-O`, which
discharges counted loops (`i` below `n`, `n <= len`). Arithmetic it
cannot discharge is written as `wrapping_*` or `checked_*` in a
`#[no_panic]` function, with a `try:` saying which. That is strict, and
it is what no-panic code in Rust does by hand.

**New uses:** `#[no_panic]` as a proof (std::gpu's kernel entry points,
voltty's per-frame path); `#[no_alloc]` plus a frame arena in real-time
loops, with `alloc(&'a Arena<P>)` allowed and `alloc(Gpa)` refused by
`#[effects(alloc(FrameArena))]` on a newtype arena; capability bounds on
workers (`spawn_in<F: FnOnce() + Send + effects(alloc(A), panic)>`
forbids io in a pool).

### 9.3 Contracts

**What they buy today, measured.** The bench pair (docs/optimizer.md,
0.18.1): prefix sum -83% instructions, dot -59%, window +24%, bucket
+15%, the program -25%. Two kernels win because the clause gives the
loop its bound; two lose because the check costs more than it saves
when the callee is not inlined. Under Rust's surface three of the four
need no contract: prefix is `v[..n].iter().sum()`, dot is `zip`, window
is `windows(4)`. Only bucket's `ensures 0 <= result && result < n`, a
fact about a computed index, buys what iterators cannot.

**Where they beat Rust's idioms:**

- *data-dependent indices*: what is left after iterators is gathers,
  interpreters and parsers (`--print-checks` on bench: json's `s[pos]`,
  interp's `code[pc]`, fannkuch's `perm[k - i]`); the fact is on the
  index value, and an `ensures` on its producer or an invariant newtype
  is the only carrier;
- *the compiler's tables*: `nodes[n]` with `n` an id made elsewhere.
  compiler/src at -O2 keeps 10,942 index checks and removes 5,769;
- *checks hoisted to a caller* that already holds the fact, when the
  callee is not inlined;
- *preconditions that are not bounds*: std has 132 `requires`, and 121
  are std::gpu's validation rules (`self.caps.compute`, `!buf.mapped`,
  `bytes_per_row % 256 == 0`). The other 11 are `Option::unwrap`,
  `Result::unwrap`, six index bounds of std.vl's slice operations, and
  three of std::cli's `!self.is_flag(name)`: what Rust's own panics
  express. After the flip, 55 of the 121 are types, 12 are Level 1
  errors on constants and 54 remain checks (§10.1(7)).

**Level 1, realistically**, is the range pass's procedure (intervals,
congruences, entry facts from `requires`, result facts from `ensures`,
one transitivity step), run once on the places IR before inlining, the
same at every `-O`. The 0.18.1 survey says what it discharges: 31 of
211 std contract checks at call sites (15%), all "an index loop bounded
by `len()`". Expect 15–25% of clauses to become statically decided. The
procedure serves `#[no_panic]` and `contract.violated`. It is not a
verifier, and Level 2 (`volec verify`) is not planned until the
compiler carries its first hundred clauses.

**The cheap, durable uses, first after the flip:**

1. **`debug requires` on every `unsafe fn` with a precondition**, the
   checked half of its SAFETY comment: free in a build, checked by every
   `volec test` and by the `--check-unsafe` gate row. Std has about
   900 SAFETY comment lines and 0 `debug requires`. Number: `unsafe fn`
   without a clause, to 0.
2. **Invariant newtypes, sound under privacy.** `struct NodeId(u32)
   requires ..` or `struct Port(u16) requires self.0 < 1024`: checked at
   every constructor and at the exit of every `&mut self` method, a fact
   outside the module. 0.18 deferred this (Q13) for lack of a module
   boundary; Rust's private fields are that boundary.
3. **`ensures` on std's length-changing operations** (`push`, `pop`,
   `truncate`) and `requires` on `split_at`, `chunks_exact`: the facts the
   range pass needs to carry lengths across calls.
4. **The compiler's tables**: `fn node(&self, n: NodeId<'t>) -> &Node`,
   aimed at the 10,942 checks. "Ids are made below `len()`" is a fact
   only about the table that made the id: once the AST arena is dropped
   after lowering and the middle end has per-function scratch tables
   (§9.1), an id from one table is meaningless in another. So the ids
   are branded by their table's region (`NodeId<'t>`, made only by
   `Table<'t>::push`, invariant in `'t`: the proposal's §10 branded
   indices). The invariant `self.0 < table.len()` then holds because
   the tables only grow while `'t` lives, and a stale id is a borrow
   error, not a wrong index.

Number for all of it: `--print-checks` totals (left, removed by ranges,
removed by contract facts) over bench, examples and compiler/src, every
release. 0.18 built the measure, and nobody has tracked it since.

### 9.4 Verdicts

- **Arenas: keep, and make them first class in fact.** The biggest
  measured win of the three (5x on the bench), blocked only by MVS's
  missing reference type. The compiler is their first customer
  (`Comp`, `Ast`, per-function scratch), with `Allocator::FREES` so
  arena nodes can hold arena lists.
- **Effects: keep, and change three things:** declarations are
  signatures (std's `pub` declares), inference moves to the places IR,
  and `global`/`sync`/`thread`/`tls` leave the user's lattice. `panic`
  against overflow checks is decided: `#[no_panic]` is checked by
  Level 1 (decision 13).
- **Contracts: keep, and narrow the claim.** Iterators take most loop
  cases away. What stays is API preconditions that are not bounds,
  facts about computed indices, `debug requires` as a checked SAFETY
  comment, and invariant newtypes. The last two cost almost nothing and
  come first.

## 10. GPU compute and graphics, first class by 0.29

std::gpu (WebGPU's object model, Metal first, 1.9x faster than wgpu on
the draw bench) and its shader compiler std::gpu::wgsl (WGSL to MSL,
SPIR-V and a CPU interpreter, 12.7k lines) become a first-class part of
the language by 0.29, with diagnostics at least as good as the host
language's. Evidence from the three GPU eval rounds (thirty Haiku demos,
evals/tasks/0.25.2*):

- **The agents' failures were mostly not GPU failures.** Across the 30
  ANALYSIS.md files: `own.move_out` 27 and `own.moved` 9 against
  `gpu.layout` 8, `gpu.usage` 6, `gpu.limits` 4, `wgsl.*` 5. Round 3's
  top complaint (six agents) was "which GPU handles move and which
  copy". Rust's surface answers that by itself.
- **No eval agent used shader files.** 0 `.wgsl` files in the evals (the
  tree has some: voltty's `cells.wgsl` and `tests/wgsl/cases`, read with
  `include_str`); all 30 programs wrote WGSL as string constants (about
  175 of them, 4,944 lines with `\n\`
  continuations), edited them by Python string replacement because
  `edit patch` and `query grep` cannot see inside a string, and three
  agents asked for a `wgsl {}` block by name.
- **Host and shader structs are declared twice, unchecked:** in round 3,
  seven WGSL structs have a vole struct of the same name next to them,
  none with `#[repr(C)]`.
- **The `gpu.*` names are not codes yet.** They live in the `else
  "gpu.usage: .."` text of all 121 of std::gpu's `requires` clauses;
  `explain` knows none of them.

### 10.1 What "first class" means

1. **Shaders are checked by `volec check` and the LSP**, at positions
   in the `.vl` file, with `wgsl.*` codes, `explain` entries and `try:`
   lines. No shader error waits for run time.
2. **Shaders are written as embedded blocks** (§11), `embed wgsl CELLS {
   .. }`, or read from a file with `embed wgsl CELLS from "x.wgsl";` for
   shaders shared with other tools. One checker serves both. The file
   form reuses `include_str`'s machinery (`front/embed.vl`): its path
   rules and its `embed.missing`, `embed.path` (raised in `parse_include`, front/parser/exprs.vl) and `embed.utf8` codes
   apply unchanged, and `include_str` stays for plain text.
3. **One struct definition for host and shader.** A block may name vole
   `const`s of `i32`, `u32`, `f32`, `bool` (and arrays of them) and
   structs whose fields are host-shareable (`i32`, `u32`, `f32`,
   `[f32; 2/3/4]` as `vec2/3/4<f32>`, nested such structs, fixed arrays);
   such a struct gets `#[repr(wgsl)]`, `repr(C)` with WGSL's vector
   alignment, so `vec3` aligning to 16 is computed once and cannot
   disagree. `bool`, `usize`, `i64`, pointers, `Vec` and references in a
   shared struct are errors naming the field. Resolution is one-way: the
   block sees those vole items and exports only its entry points and
   bindings.
4. **The host↔shader interface is typed.** A block is a constant of a
   type the compiler makes for it: `s.step: Entry<Compute>` (with its
   workgroup size, so `step.dispatch_for(&mut pass, n)` computes the
   group count), `s.vs` and `s.fs` for render stages, and per
   `@group(N)` a bindings struct, `Bindings0<'a> { particles: &'a
   Buffer<Particle, Storage>, params: &'a Buffer<Params, Uniform> }`.
   `dev.shader(&s)` (0.27's typed form; today's path is `dev.shader_wgsl(src)`) does no run-time parse and cannot fail on the
   source; a missing entry point cannot be named; a bind group that
   does not match its layout is a type error.
5. **Resources in Rust's surface.**
   - `ComputePass<'e>` and `RenderPass<'e>` are guards with `Drop` that
     end the pass, holding only `&'e mut Encoder`. Bind groups and
     pipelines keep their resources alive by the hal's reference count,
     not by borrows: wgpu 22 removed resource lifetimes from its passes
     (`forget_lifetime`) because they were unusable. Today's
     closure-scoped passes go.
   - `map_read(&mut self) -> BufferView<'_, T>` and `map_write` borrow
     the buffer exclusively and unmap on drop; the view derefs to
     `&[T]` / `&mut [T]`. Round 3's soundness bug (a copy recorded into
     a buffer while its view lives) becomes a borrow error. A copy
     recorded *before* the map and submitted after still needs the
     run-time mapped state at `submit`, as 0.25.3 built: both stay.
   - `Frame<'s>` must be presented; `Surface<Configured>` as typestate.
   - `std::objc`'s `Id<T>` owns with `Drop`, `Ref<'a, T>` borrows (today
     a view hack holding a `&u8`).
6. **Usage as typestate.** `Buffer<T, U>` with marker types (`Storage`,
   `Uniform`, `Vertex`, `Index`, `CopySrc`, `CopyDst`, `MapRead`,
   `MapWrite`, `QueryResolve`). A combination is a tuple of up to four
   markers, `Buffer<Particle, (Storage, CopyDst)>`, and an operation
   bounds it with `U: Has<Vertex>`. With no variadics and no macros the
   per-arity impls would be hand-written, so `Has<M>` is
   compiler-provided, like `Send`. No const generics needed.
7. **Validation, sorted by where it can be decided.** Of std::gpu's 121
   `requires` (all of them carry a `gpu.*` name in their text today):
   - *gone, by types*: 55. `gpu.usage` 26 (typestate), `gpu.layout` 7
     (typed bindings), `gpu.align` 10 (element offsets on `Buffer<T, U>`
     and typed views), the mapped state and `configured` 9 (exclusive
     mapped views, `Surface<Configured>`), the shader kind 1 (translation
     ahead of time per backend), `u32` counts and typed binding sizes 2;
   - *compile errors when the arguments are constants* (Level 1,
     `contract.violated`): 12. Bind-group and vertex-buffer slot indices,
     builder counts against 8 (attributes, vertex buffers, colour
     targets, pass attachments), anisotropy 1..16, query-set size, the
     surface format. Builder counts need a straight-line builder chain;
     otherwise they stay run-time checks;
   - *run time by nature*: 54. Device capabilities (`gpu.unsupported`,
     11), device limits (10), ranges (17), format agreement between
     passes, pipelines and views (9), the mapped state at submit and
     empty passes (3), texture-copy byte alignments (3, Level 1 when
     constant), `gpu.unwritten` (1). None of these cost an agent a turn
     in three rounds.
8. **Tests without a GPU.** `volec test` runs compute kernels on the
   WGSL interpreter on the CPU and, where a GPU is present, on the GPU
   too, and compares them. Kernel tests then need no GPU, which will
   matter when the Linux backend returns (§13).
9. **Shaders translated ahead of time.** The MSL and SPIR-V are made at
   compile time and embedded; Metal's own compile stays at run time
   behind the pipeline cache (shipping `xcrun metal` in a build is
   fragile for about 20 ms warm).

### 10.2 The diagnostics, from the transcripts

The ten worth building first, each from a failure the eval agents hit:

| # | code | what it says | `try:` |
|---|---|---|---|
| 1 | `borrow.moved` (E0382's shape) | `'dev' was moved into 'Sim { dev, .. }' (main.vl:40) and used here`; help: Device, Buffer and BindGroup own native objects and move | `volec refactor field Sim.dev '&Device<..>'` |
| 2 | `gpu.layout` | `bind group 0 of 'evolve' (main.vl:12-18) wants @binding(1) uniform 'params', but entry 1 is storage buffer 'cells'`; with typed bindings, a type error at the field | the binding the shader declares |
| 3 | `gpu.usage` | `buffer 'verts' (usage COPY_DST, created main.vl:22) bound as VERTEX`; with typestate, `expected a Buffer<_, U> with U: Has<Vertex>, found Buffer<_, CopyDst>` | `edit patch main.vl:22 --old 'CopyDst' --new '(Vertex, CopyDst)'` |
| 4 | `gpu.unwritten` (warning, at check time) | `uniform 'params' (main.vl:31) is bound to 'evolve', but no write_buffer or map_write reaches it` | `queue.write_buffer(&params, 0, &bytes)` |
| 5 | `wgsl.type` | `main.vl:48:17: no '+' for f32 and i32` (today's run-time text, at check time) | `f32(i)` |
| 6 | `gpu.entry` | `the block 'CELLS' has no @compute fn 'evolve'; its entry points: init (compute), step (compute)` (with typed blocks it cannot be written at all) | `CELLS.step` |
| 7 | `wgsl.binding` | `@group(0) @binding(0) is already 'cells' (line 3)`; help: one module per kernel, or distinct bindings | |
| 8 | `borrow` on a mapped view | `'r' is mutably borrowed by the mapped view 'v' (main.vl:40) and copied into at main.vl:45`; help: the GPU writes under the view | end the view first, or `v.to_vec_in(a)` |
| 9 | `gpu.repr` | `Particle.vel ([f32; 3]) is at offset 12 in a host struct, 16 in WGSL (vec3 aligns to 16)`: only for a struct declared outside a block's reach, since shared structs cannot disagree | `vel: [f32; 4]`, or `_pad: f32` after `pos` |
| 10 | `contract.violated` | `bind_layout(4): bind groups are 0..3 (std::gpu::MAX_BIND_GROUPS)` | `bind_layout(3)` |

Plus three host-side diagnostics round 3 asked for: `use
std::gpu::{Surface}` reported as "unknown module 'gpu'" should say `use
std::gpu;`, a misplaced parameter mode should say where it goes, and
`volec test` should show printed output. The `gpu.*` and `wgsl.*` names
become real codes with `explain` entries before any of this.

### 10.3 How it lives with the rest of the change

| plan item | interaction | resolution |
|---|---|---|
| overflow checks always on (decision 6) | WGSL wraps and defines `/ 0`; the translator keeps WGSL's rules | no conflict while shaders are WGSL. It is the main reason not to write kernels in vole syntax (below) |
| `usize` lengths | shader indices are `u32`, buffer sizes `u64` | shared structs use `u32`/`f32` fields; a `usize` field in one is an error. Rust's literal inference also fixes round 3's "float literals are f64" (`let dt = 1.0 / 60.0` into an `f32` field, four agents) |
| allocation as a capability (§2.0) | `Device` holds the resource table and per-encoder frame arenas, so it holds an allocator | `Device<A: Allocator>` by rule 3. Applications use `Device<AnyAlloc<'a>>`, written out, made by `gpu::Instance::new_in(gpa.erase())`: one instance of std::gpu per program, and `fn kernel(dev: &Device<AnyAlloc<'_>>)` shows it can allocate. `Buffer` holds no host allocator: GPU memory is `io`, reached through `&Device` |
| the cuts to 0.29 | passes need `Drop` with a region (in the minimum); typestate needs marker types, not const generics; keepalive is the hal's count, not `Rc`/`Arc` | nothing std::gpu needs is cut |
| the std redesign's critical path | the wgsl compiler (12.7k lines, plain data in `Vec`s) is a mechanical rewrite; the API (~3.4k lines), the Metal hal and `std::objc` are the design work | the API rewrite and typestate go in 0.27 with the new std; the hal and objc go with std's unsafe core |
| effects | `io` on every device call stays; `sync`/`thread` leaving the user lattice does not touch `Device: Sync` or `Encoder: Send`, which are kinds | none |
| the compiler runs the shader compiler | `volec check` calls std::gpu::wgsl | allowed by the chain rule since 0.23 (std::gpu::wgsl shipped in 0.22; compiler/src may use it from the next release); after the flip it may move into compiler/src or stay shared |

**Not now: kernels in vole syntax** (`#[gpu] fn`, single source in the
rust-gpu or CUDA style). Every token would mean something else on the
device: `+` panics on the host and wraps in WGSL, `usize` against `u32`,
no allocation, no effects. That is the "looks like Rust, means something
else" problem the surface change exists to remove, and no agent asked
for it. Kept as a possibility after 1.0, if CUDA becomes a target (PTX
from the wgsl IR, as gpu.md's CUDA readiness describes).

### 10.4 When

| release | GPU work |
|---|---|
| 0.26 (MVS) | `embed wgsl NAME { .. }` and `embed wgsl NAME from "..";` as the one shader form, checked in `volec check` and the LSP; shared `const`s and `#[repr(wgsl)]` structs; `gpu.*` and `wgsl.*` as real codes with `explain`; static `gpu.entry` for constant names; the VS Code injection grammar; the check-time text forms of diagnostics 2–7 (their typed forms need 0.27's typed blocks and typestate) and, for 1, a better `own.move_out` help text, since `borrow.moved` is 0.27's; the three host-side ones; the guide and `examples/gpu/fluid2d` rewritten to blocks. All of it survives the flip |
| 0.27 | std::gpu in the rust edition: guards, exclusive mapped views, `Buffer<T, U>` typestate, `Device<A>`, typed blocks (`Entry<Compute>`, `BindingsN<'a>`); examples/gpu round-trip at gate 2 |
| 0.28 | the flip |
| 0.29 | translation ahead of time, interpreter tests in `volec test`, diagnostics 8–10; gate: the ten-task GPU eval rerun against rounds 1–3 (failed tool calls, turns lost to GPU errors, run-time contract failures that became check errors) |
| 0.30 | `embed regex`. The Vulkan hal (the SPIR-V writer exists and passes `spirv-val`; the hal does not) waits for the Linux backend's return (§13) |

## 11. Embedded language blocks

Shaders motivate a general mechanism: a block of another language inside
vole source, parsed and checked by the compiler, producing a typed
value. `wgsl` is the first language and, for a while, the only one.

**The rule: one syntax and one compiler interface, for a closed set of
languages.** Each language is compiler code behind a fixed interface:

1. find the block's end (its own lexer: a WGSL block ends at the brace
   that matches outside comments; a content-agnostic delimiter like
   `"""` is exactly what makes today's shaders opaque to every tool);
2. parse;
3. check, with access to the vole items the language admits;
4. produce a value: a compile-time constant of a type the compiler
   makes, or an expression with typed holes;
5. report positions (the `.vl` file's own) and its own diagnostic codes,
   each with an `explain` entry;
6. optionally, `fmt` and LSP hooks. By default `fmt` keeps the block
   verbatim and re-indents it.

No user-defined languages: that is procedural macros, running program
code at compile time, which "no macros", compile speed, determinism and
the chain's byte-identical fixpoint all exclude. Adding a language is a
compiler change, the way `derive` is.

**Spelling.** `wgsl { .. }` reads as Rust's struct literal (`Name {
.. }` after `=`), which breaks "a Rust token never means something
else". `wgsl! { .. }` is what Rust readers know from yew's `html! {}`
and leptos' `view! {}`, but it reopens "no macros, bang or otherwise".
Decided: **a contextual keyword prefix, `embed wgsl { .. }`**. It
clashes with no Rust form, says what it is, and lets the set grow
without new keywords. A block is an item that names its constant,
`embed wgsl CELLS { .. }`, so the generated type has a name for `query`,
the LSP and errors; the file form is `embed wgsl CELLS from "x.wgsl";`
(decision 15).

**Parts (0.26.2, proposed).** WGSL has no includes, and fluid2d and three
of the eval programs build each kernel from shared text. A block may
name other blocks whose text comes before its own, in one module:
`embed wgsl STEP with COMMON, NOISE { .. }`. A part has no entry points,
and parts may not form a cycle. `with` is a contextual word, like
`embed` and `wgsl`, not Rust's `use`, so no Rust token gains a second
meaning; `K(A, B)` was rejected because it reads as a call or a
tuple-struct constructor. The clause is additive, so 0.26.0's blocks
need no migration when it lands. Decided: decision 19.

**Two kinds of block, not one feature.** `wgsl` is a compile-time
artifact: a zero-sized constant with generated types and an embedded
translation, no run-time cost, no allocator. An `html` block would be a
run-time template: interpolations evaluated per render, a
`String<A>` from `render_in(a)`, and escaping chosen by type and by
context (text, attribute, URL, script). That is a templating engine with
a checked front end. The interface can host both, but the second kind
is a separate decision with its own budget.

**Which languages, by value per cost:**

1. `wgsl`: 0.26.
2. `regex`: checked and compiled at build time into an automaton, no
   run-time parse, no allocator for matching. Agents write regexes
   constantly and get them wrong at run time, and the terminal and CLI
   tools use them. About 0.30.
3. `sql`: typed, injection-safe parameters, once vole has a database
   client. Not before.
4. `html`: the run-time kind, with the escaping engine. Last.

Not worth a block: assembly (`std::arch` intrinsics cover it), C (`import
"x.h"` already reads headers), JSON (a derive is better).

**A language is "in"** when it has its injection grammar for the editor
(one file in the VS Code extension), `explain` entries for its codes, a
guide section whose examples the guide's tests compile, and `query grep`
and `refs` over its tokens. The same bar as a std module.

## 12. Decisions

All taken on 2026-10-30. Decisions 1, 15 and the direction itself are
the user's own choices; the others are this document's recommendations,
which the user accepted as a whole.

1. **Allocation is a capability** (§2.0): no default allocator type; a
   function allocates only through an allocator reachable from its
   parameters; a type that holds an allocator has it among its
   parameters. Rule 3 is an error, not a lint, and its `try:` adds the
   type parameter (`fix` writes it). `Clone` keeps Rust's meaning and
   reuses the stored allocator, which the parameter type shows;
   `clone_in(a)` moves to another.
2. **Hashing:** a fixed seed by default (deterministic gates), seeded
   through `with_hasher_in`; HashDoS documented in the guide.
3. **Polonius:** NLL in 0.27.0; the location-sensitive solve in a 0.27
   point release, behind the NLL filter.
4. **Tree Borrows** is the aliasing model, checked by `--check-unsafe`
   as a gate row.
5. **Panics** format into a fixed buffer and truncate; they never
   allocate.
6. **Arithmetic:** overflow checks always on, no release switch, as for
   contracts. Their cost on the bench is measured in Phase 1(b) before
   anything else depends on it.
7. **No deprecation period:** MVS is deleted in 0.28.
8. **The cuts of §6** move to 0.29; gate 3 says whether compiler/src
   needs any of them earlier.
9. **Arenas** (§2.1): std ships `Arena<P>`, scopes, `FixedBuf<'b>`,
   `alloc(x) -> &'a mut T`, `TypedArena<T>` and `AnyAlloc<'a>` in the
   0.27 minimum. Std's containers are generic over `A: Allocator`;
   the guide recommends `AnyAlloc` for application code that passes an
   allocator through many layers, and gate 3 measures compile time and
   code size on the compiler to confirm it.
10. **`Allocator::FREES`** (§9.1): containers on a non-freeing allocator
    need drop only if their elements do.
11. **The compiler adopts its arenas** (`Comp`, `Ast`, per-function
    scratch) in Phase 1(f), and as regions after the flip.
12. **Effect declarations are signatures**; std's `pub` items declare
    theirs (§9.2). `sync`, `thread` and `tls` leave the user lattice.
13. **`#[no_panic]` is checked by Level 1**; arithmetic it cannot
    discharge is written `wrapping_*` or `checked_*` (§9.2).
14. **Level 1 only:** no `volec verify` until the compiler carries a
    hundred clauses (§9.3).
15. **The embedded-block spelling** (§11): `embed wgsl NAME { .. }`, an
    item that declares the constant and its generated type together
    (`embed wgsl CELLS { .. }`), and `embed wgsl NAME from "x.wgsl";`
    for the file form.
16. **GPU by 0.29** (§10.4): blocks and check-time WGSL in 0.26; the API
    in the rust edition, with typed blocks and typestate, in 0.27;
    translation ahead of time, interpreter tests and the eval gate in
    0.29; Vulkan with the Linux backend's return (§13). Shaders stay WGSL; kernels in vole syntax not before
    1.0.
17. **`Device<AnyAlloc<'a>>`** is the application spelling of a GPU
    device: one instance of std::gpu, the allocator visible (§10.3).

Taken after the 0.26.0 review (2026-10-30), the user accepting both:

18. **A panic exits with 101, with no unwinding**, as today, for now.
    The user wants unwinding later (Rust's default, with `catch_unwind`
    and drops on panic); it is deferred to save time, not rejected, and
    becomes its own item after the flip: unwind edges and cleanup blocks
    in the places IR, landing pads in both code generators. The places IR has no unwind edges, and calls and
    drops are statements ([places-ir.md](places-ir.md) §3.10). The
    consequences:
    - a panic in a spawned thread ends the process, and there is no
      `catch_unwind`;
    - `Drop` is not cleanup on panic: voltty's terminal restore stays
      an atexit or signal handler;
    - `assert`, a failed `requires` and `panic` share the one exit-101
      path, with one `explain` entry;
    - `--check-alloc` reports no leaks on exit 101;
    - the rustc twin runs with `-C panic=abort` and compares exit codes
      (101 against 134), and a test expecting a panic is compared by
      its exit code only.
19. **Shader parts are spelled `embed wgsl K with A, B { .. }`** (§11),
    in 0.26.2.

## 13. How the work runs (the user's constraints, 2026-10-30)

- **Few agents.** At most three work at once, usually two, each on its
  own files, so that branches do not conflict. 0.26.0's three items
  (the places IR, private fields, `embed wgsl`) are the maximum; the
  statics refactor, 1(f), runs alone.
- **aarch64 macOS only.** No Linux testing at all for the duration of
  this plan: no colima, no containers, no VMs. `tests/affected.sh
  --linux` is not run, the gate's `linux-smoke` and `linux-aarch64` rows
  stay off (their SKIP is expected), and "platform-relevant" in an
  affected plan is ignored. This overrides AGENTS.md's Linux rule for
  this work. While untested, Linux may bitrot; release notes say macOS
  only.
- **The Linux backend returns later**, as its own piece of work: the
  aarch64-linux and x86_64-linux targets back under test, the
  container rows of the gate, and the Vulkan hal (tested on lavapipe).
