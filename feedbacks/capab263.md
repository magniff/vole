# capab263: allocation as a capability (0.26.3)

## Verdict

Done as designed: there is no default allocator type (alloc.default),
nothing allocates from nothing (alloc.no_in), Allocator is an `unsafe
trait` (alloc.safe_impl), and statics and fields hold no allocator their
types do not name (alloc.static through the auto trait AllocFree,
alloc.field). `_in` functions take their allocator last (alloc.last).
compiler/src keeps one exemption, a table of two entries in
front/check/alloc_rules.vl (base::comp::Comp and the static WGSL_ARENA),
until 0.26.4 moves its tables into context structs. tests/, examples/,
bench/ and the guide were moved over by `volec fix --only alloc`, and
the cases it could not reach were fixed by hand.

## What worked

- `fix --only alloc` in rounds. Once a new alloc.* error counted as the
  rounds' cascade and not as the edit's fault, one run went from a field's
  `Vec<u8>` to `struct P<A: Allocator>` and on to `P<Gpa>` at every use.
  The dry runs fell from 625 programs left to 65, all known.
- The case runner as the check for the intentional-error cases, after a
  --no-check pass.
- `query context` / `edit patch` on compiler/src; `refactor signature`
  for the Call<A>/Leaf<A> slot.
- Dry runs on a `git archive` copy with the build's binary copied in, so
  the worktree was never half-migrated.

## What cost time, ranked

1. Generic impls of user types (`impl<T> Bag<T>`): the arity error was a
   type error with no fix, and the fix-only check (no instance) has no
   allocator in scope. Fixed with an alloc.default impl-header fix and a
   note of each generic impl's span.
2. The edit check refused the rounds' own cascade (field `, Gpa` making
   alloc.field), so the first dry run left 625 programs.
3. Merges with release-0.26.3 (text263's String<A> in the same std
   types; the explain table counts); each moved the dry run's base.
4. `tests/guide/run.sh` reads the embedded guide; without `-f FILE` it
   tests the old text.
5. Hook friction: shell reads/writes of compiler/std and conflict files
   need `# no-query:`/`# no-tool:` each time; the check hook runs the old
   target/tools/volec, which cannot parse `unsafe trait`, so it reports
   50 std errors after every edit.
6. Generated files: `fix --force` plus regenerating the sinksweep
   templates from the fixed output (a line map), byte for byte after fmt.
7. What the fix could not reach, by hand: a payload-less variant
   (`E::None` of an `E<A>`: no argument binds A), a `use` alias of a
   generic type (`Map2<i64, i64>`), a generic enum's call arguments
   (no expected type to bind the allocator from), and the error cases,
   whose point is the error (err_text_020's `String::new()` was fixed
   into what it tests and had to be put back).
8. The checker's own gaps the turn found: derived traits bounded the
   allocator parameter (`A: Debug`); an enum variant's and a literal's
   arguments did not bind A; gpu lints keyed on `Device` missed
   `Device<Gpa>`'s methods; the build's lazy std did not load the `_in`
   form an alloc.no_in names (`env::get` was "no 'get' in module").

## What the suites found after the turn

The case runner passed the turn's 1360 changed cases at -O0 and -O2
(1326 pass, 33 xfail); the suites then found what no case had:

- `volec test` broke: std's `Fn(inout Gen)` bounds and the code the
  test generator writes named `Gen` bare (std is checked lazily: no
  case instantiated them). `--trace` printed `Ring::GN7std::Gpa::push`.
- a struct literal's untyped `0` bound `Range<i64>` before `s.len()`
  (`0..s.len()`), once calls were deferred for the allocator.
- trees no dry run covered: tests/gpu/support.vl (compiled with each
  case, not a root), tools/wgslc, tools/objcgen, the book (124 blocks)
  and the walkthroughs' heredoc programs.
- the reuse of an item's allocator parameter is wrong when its fields
  hold different allocators (scoped-arena's Store: a map on Gpa, an
  Arena for its keys): fixed by hand, `Store<Gpa, Arena>`.

## Never used

`refactor extract-function|inline|split`, `query effects|impact`,
`reduce`, `probe`.

## Fix list, in order (tagged)

1. [hook] check-after-edit should use the build it is checking
   (target/volec when newer than target/tools/volec), or say which
   binary it ran; its errors from an old binary look like new breakage.
2. [fix] the edit check's cascade rule (ALLOC_ROUNDS) could be general:
   a new error of the same `--only` family is the next round's.
3. [guide] tests/guide/run.sh could warn when compiler/guide differs from
   the embedded text instead of silently testing the old guide.
4. [query] `query grep` cannot print conflict markers; resolving a merge
   in compiler/src needs `# no-query`.
5. [fix] `fix --only alloc` could fix a `use` alias's arguments and give
   a payload-less variant its allocator from the expected type.
6. [fix] a `--dry-run` per tree could list the intentional-error cases
   (an `ERROR:` directive) apart, so a run over tests/ leaves them alone.
7. [fix] `fix --only alloc` could reuse an item's allocator parameter
   only for the same concrete allocator (it reuses it for any).
8. [suite] a check that every std function instantiates (`Fn(inout
   Gen)` was never checked) would have caught the test harness before
   the suites did.
