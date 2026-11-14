# The XFAIL cases (0.30 census)

The census sorts the suite's XFAIL cases (`// XFAIL:` in `tests/run`'s cases
and `tests/borrowck-try`'s) by what is wrong. The 0.30 release rule is that
the count only goes down. A case that starts to pass is reported as XPASS,
which is a failure in `tests/run.sh`, and its XFAIL line is removed. So the
census has no stale class: every XFAIL case was failing at -O0 and at -O2
when the census was taken.

## How it was taken

The census was taken on 2026-11-14 on release-0.30.0, before this branch's
fixes. It covered 730 XFAIL lines: 725 in tests/run and 5 in
tests/borrowck-try.

1. **What vole does with each case:** `VOLE_TEST_XFAIL_WHY=FILE tests/run.sh
   -n NAME...` gives the first line of each failure, at -O0 and at -O2.
   `volec check` then gives the case's verdict and its first error.
2. **What rustc does:** `tools/borrowck-twin.sh --shim` and
   `tools/rustc-twin.sh` were run on the same cases. The first gives rustc's
   verdict and first error code. The second gives rustc's output, compared
   with the case's EXPECT lines.
3. **The class:** a script joins the two and picks a class by the rules
   below. Each case's reason text, `gap N`, is a group from the 0.28
   migration inventory (gap 2: std2 lacks a name; gap 8: borrowck errors in
   a translation MVS accepted; gap 17: errors at other places or codes; ...).

| class | what | cases |
|---|---|---|
| (a) | vole accepts what rustc rejects | 16 |
| (b) | vole rejects what rustc accepts | 39 |
| (c) | wrong code or output, a crash (no compiler crash among them) | 5 (+8 likely) |
| (d) | a std item missing (mostly an MVS name std2 does not have) | 32 |
| (e) | an optimizer or IR expectation (CHECK, places IR) | 19 |
| (f) | stale: passes now | 0 |
| (g) | not a goal (an MVS-only check rustc lacks too; the runner's own XFAIL test) | 6 |
| (h) | the case is wrong: the 0.28 translation of an MVS case | 510 |
| (v) | vole-only programs no twin covers (Arena, `extern "C"`, contracts, gpu) | 90 |

The (h) cases are the debt. They come in four kinds:

- **Both reject, and the directive is MVS's: 256.** vole and rustc both
  reject the program, but the ERROR directive names MVS's code or text
  (`error[own.conflict]`, `own.escape`, `own.move_out`, ...). In 136 of them
  vole's first error is a borrow check error, and the verdict is likely right
  already.
- **The text is not Rust: 139.** Unresolved std2 names, MVS syntax left over
  (`&mut` in an expression, typed closure parameters), missing impls.
- **The text breaks a Rust rule: 111.** The case expects acceptance, but the
  translation breaks a rule that both compilers enforce: E0308, E0106,
  lifetimes, E0596.
- **MVS's output expected: 4.** The program runs, but the expected output is
  MVS's and not rustc's (gap 9/10).

By the migration's gap groups: gap 17 (other places or codes) 152, gap 8 (borrowck
in a translation) 143, gap 2 (std2 lacks a name) 133, gap 3 (MVS modes in
types) 48, gap 7 (parse and tokens) 47, gap 20 (fails for another reason)
29, gap 4 (integer typing) 25, gap 25 (IR/asm directives) 21, gaps 5 and 18
16 each, the rest under 8; 56 cases have a reason of their own.

## Fixed in 0.30

These cases were fixed by a change to the compiler or std, not to the test:

- **`Ordering`'s discriminants are Rust's** (-1, 0, 1): `addr_of_temporary`
  and `temporary_conditional`.
- **A line printed from several threads is written in one call**:
  `thread_print`.
- **Two indexes of a place may alias, as rustc's** (R7 closed):
  `rust_b_err_index_mut_twice` and `rust_b_err_index_assign_vs_shared`.
- **A closure's requirement on an adapter's `Self::Item`**, where Copied's
  `T` or Map's `B` comes only from a bound, reaches the caller: this closes
  a use after free in safe code (`v.iter().copied().fold("", |a, x| x)`).
  Case: `sem_views_h_h_iter_fold`.
- **A fn item passed for `F: Fn(&T) -> R`** whose result borrows from its
  argument is an error in the instance (R6's flow): this closes a use after
  free in safe code (`apply(&v, sl)`). Case: `sem_poly_g06_generic_fnparam_call`.

These fixes also brought new rustc-strict checks without an XFAIL case of
their own: a union field borrowed outside `unsafe` (E0133), the R7 error
cases, and a closure calling a captured FnMut closure that is not
declared `mut` (E0596, `rust_b_err_capture_call_fnmut`).

Six cases expected MVS's output, or MVS's places IR, while vole's output
already was rustc's (the rustc twin's binary as the referee): their EXPECT
lines are now rustc's: `sem_own_map_sink_closure_count`,
`sem_own_add_owned_let`, `sem_own_borrow_sink_closure_ret_field`,
`sem_own_leak_borrowed_map_fold_ok` (a map's drop order, which Rust leaves
unspecified), `fmt_0253_slice_debug` and `places_temp_statement_end` (the
print's end is `PrintOut::end`).

The XFAIL count went from 730 to 717 (`grep -rhE "^ *// XFAIL" tests |
wc -l`).

The borrowck twin (`tools/borrowck-twin.sh --shim tests/run/rust_b_*.vl`):

| | cases | agree | divergences | mismatches |
|---|---|---|---|---|
| before | 462 | 419 | 10 (L13 1, L2 2, L7 2, L8 1, R3 1, R7 2, R8 1) | 0 |
| after | 469 | 427 | 8 (R7 closed) | 0 |

Two named divergences are kept, with their reasons in
docs/design/borrowck.md:
- R3: per-instance checking accepts a generic body that moves an `FnOnce`
  parameter twice when the instance's closure is Copy. This is sound for
  every instance; rustc rejects the template.
- R8: vole is stricter here (a move out of `*b` for a Box).

The rustc twin's usual set (`--guide rust_*_ok_* rust_t_*`): before, 439
programs with 308 agree, 0 differ, 9 named; after, 310 agree, 0 differ,
7 named.

## The plan for (h)

The compiler is not wrong in these cases. Each one needs one of three
things:

- a directive rewritten;
- the program rewritten as the Rust it meant;
- the case deleted where a `rust_b_`/`rust_t_` case already pins the same
  rule (with its name in the commit).

In order of cases per hour:

1. **The 136 "both reject, borrow check first" cases.** These need only
   their directive. When rustc's first error and vole's are the same rule at
   the same line, replace the MVS directive with vole's code and position
   (`tests/run.sh --bless` moves positions; the code is changed by hand),
   check the twin agrees, and remove the XFAIL line. Batch them by MVS code
   (own.conflict 87, own.escape 13, own.move_out 8, ...).
2. **The other 120 "both reject" cases.** Here rustc's first error is a type
   error or a missing name. Rewrite the program so that the error the case
   is about is the first one, or delete the case when a rust case covers the
   rule.
3. **The 111 "breaks a Rust rule" cases.** Rewrite them as valid Rust with
   the same intent; most are one `&`/`&mut`/`let mut` or a lifetime away.
   `volec fix --suggested` makes many of these edits exactly.
4. **The 139 "not Rust text" cases.** Rewrite them (the parse gaps, gap 7)
   or delete them (MVS std names that std2 renamed: the rename is the
   test).
5. **The output cases.** Rewrite the EXPECT lines to rustc's output, with
   the twin as the referee (done in 0.30 for the six whose output already
   was rustc's).

## What is left, by class

The census file (one row per case: class, gap, both verdicts, the reason,
vole's first error, rustc's text) and the script that made it were left
with the integrator's notes for this release; a fresh census is the same
three steps above.

**(a)**, beyond the five fixed:

- `rust_b_err_mv_assign_part_uninit`: rustc E0381, a partly assigned
  binding.
- `rust_b_err_mv_out_of_static`: rustc E0507. The static is read as
  `copy`, so no move is seen; the copy is made before places/build.vl's
  place_operand.
- `sem_core_shift`: rustc's deny lint for a constant shift that overflows.
- `sem_poly_th03_direct_closure_in_scope`: rustc E0596, an FnMut closure
  called through a binding that is not `mut`. The direct form is fixed. The
  form nested in a second closure is not: the outer closure's capture is
  inferred before the inner one's, so the outer takes c by `&`
  (front/closures/kinds.vl).
- `err_017_lifetime_quote`: rustc E0261, an undeclared lifetime.
- `err_017_label_use_quote`: a malformed loop label.
- `alloc_gpa`: `a < b < c` is accepted.
- The rest are translation artifacts (a static of an unsized `[T]`).

**(b)**:

- 14 are vole's allocator rule (`alloc.no_in`, `alloc.field`), so they
  belong in (g): the case should pass its allocator.
- `#[derive(Clone, Copy)]` on a union.
- A union pattern must name every field (rustc: exactly one).
- `&mut fn` is not taken as FnOnce.
- Trait-method inference gaps in `std_*` (`parse`, `Result`'s E, `TryInto`).
- `map(..).filter(..).fold(..)` is rejected by a borrow check error inside
  std's `Iterator::fold`. Found while fixing the use after free; it is in
  0.29.0 too.

**(c)**: `checkalloc_arena_*` (the arena's stale-block report),
`contract_*` (the requires message), `fmt_values` and
`sem_own_for_vec_take` (`sem_own_map_sink_closure_count` was MVS's expected
output; fixed above).

**(d)**: list the names, then either add them to std2 when Rust has them
(`count_ones` reachable, `BTreeMap` at `std::`) or rewrite the case to
Rust's name.
