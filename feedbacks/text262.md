# Feedback: text262, `where`, `impl Trait`, visibility and format literals

2026-10-30, release 0.26.2. Steps 1 to 5 of brief-text262 and the docs of
step 6: `where` and argument-position `impl Trait`; `pub(crate)`,
`pub(super)`, `pub(self)`, `pub(in path)` with item.private and
vis.path; format literals (Rust's std::fmt at std's format positions,
rustc's output byte for byte), with the tools seeing their holes; `fix
--only fstring`, with the guide migrated. `{:#?}` is format.spec "not in
this release".

## Verdict

The compiler's tools carried the language work: `query context` before
each unfamiliar item, `edit patch`/`edit insert` with the check after
each, and `bootstrap.sh --dev --no-suite` at 20 to 60 s. Two things cost
more than the code: splitting one working tree into a commit per step
(the steps touch the same files), and std's core budget, which a format
spec in every program's Fmt path breaks by itself.

## What worked

- Comparing with rustc 1.98.0 directly: the spec case's lines are
  rustc's output, and three of my guesses (`{:#X}` is `0x2A`, `^` puts
  the odd pad byte on the right, `-0` is `+0` for an integer) were wrong
  before rustc said so.
- tests/refactor, tests/query and tests/lsp transcripts recorded with
  `-u`: a new transcript is one file and one run.
- Making the format literal the f-string's Interp node, its names Ident
  nodes at their own positions: rename, refs of an item, the effects,
  the own pass and both IRs saw them unchanged; only `query refs` of a
  local and item rename needed a "name inside a string token" check.
- `fix --only fstring` over scratch copies: compiler/src 430 rewritten
  (the brief's 417 and this stream's own), std 382 (368 rooted at std.vl,
  14 in the flat test and fuzz sections, which only a program naming
  them reads), examples 516, every copy checking as before.

## What cost time, ranked

1. One commit per step from one working tree: steps 2 and 3 share
   lookup.vl, the explain tables, stdsrc.vl and the docs; the split was a
   backup, a hand-made step-2 tree, a build and its tests, then a
   restore. An agent doing several steps should commit each before
   starting the next.
2. std's core budget (tests/std/core_sections.sh): 587 bytes of room
   on the base; Rust's specs in fmt_pad, fmt_radix and the sign took
   1.4 KB after trimming comments, so the bound went up to 164 KiB (its
   own commit), and format_args/__panic_fmt went to a lazy section.
3. The hook's `target/tools/volec` was older than the base (no
   `format_args`, usize impl errors): every edit's check showed 8 to 50
   bogus errors, and each had to be checked against `target/volec check`.
4. `fix` writes a file reached through a symlink as a plain file
   (examples/voltty/app/pty.vl -> ../core/pty.vl became a copy): the
   tree trial had to skip symlinked paths.
5. Rule 4 of the migration (double a plain literal's braces) cannot
   tell a 0.26.1 literal from a migrated one, so a second run (or two
   programs sharing a file) doubles braces again. The trial runs each
   file once (`--in` its program's files not yet fixed).
6. Positions inside a string token: `token_at(p)` is the first token at
   or after p, so a hole inside a literal is the token before it.
7. The disk filled up halfway through (other worktrees).

## The chain

0.25.5, stage 1, cannot build a format literal: `println("{} {x}", x)` is
type error "'println<[u8]>' expects 1 arguments, got 2", and
`println("plain {x}")` prints `{x}` with a warning. compiler/src keeps its
f-strings until the release after 0.26.2 builds it.

## `defer` removed (decision 20)

compiler/src's one use was macro_fstring_help's, gone with its rewrite.
The Defer node stays: the own pass places every drop as an implicit
Defer and a temporary's drop (drops.vl temp_make) as a plain one, so
middle/lower's and gen0's DEFERS, places/build's EN_DEFER and the plain
Defer branches of the checker, the own walk, fixvalues' scan and
extract serve the compiler's own defers: there is nothing for A and B
to delete in the places IR. What went: the parser's statement (now
syntax.defer), the checker's no-return/`?`/break rules, IN_DEFER, fix
--values' rule 1. Eight tests of the deferred statement's own rules are
gone (a guard cannot write a local, `return` from itself or hold an
inout access); lang06_defer is lang06_guard.

## The tests the migration left (76: the check refuses their fix)

`fix --only fstring --keep-braces` checks each program after its edit
and refuses an edit that brings a new error. All 76 had errors before
the edit, exactly as they stand: they are error tests, or tests whose
FLAGS (`--values=off`) the fixer's check does not use. The edit
reworded or moved those errors (an f-string quoted in a message, a
column), and the check counts a reworded error as a new one. They hide
nothing: f-string holes are read as ordinary code by the own pass (a
`sink` call in a hole moves its argument, own.moved as an argument
does), `sink` is never a name (`"{sink}"` and `f"{sink}"` are both
parser errors), and sem_own_closure_temp_to_let_param is an XFAIL with
that very error. (A first reading of their error lines, in this file's
previous version, took three of them for compiler bugs: wrong.)

The categories, by the error the check saw:

own.conflict: arch_err_store_view.vl, checkalloc_arena_grow.vl, checkalloc_slice_push.vl, closure_returns_capture_view.vl, err_closure_view_across_call.vl, err_own_cast_view_grow.vl, err_own_unmap_live_view.vl, err_own_user_dunder.vl, err_temporary_own.vl, err_vec_elem_receiver.vl, generic_struct_fcall_view.vl, own_report_basics.vl, own_slice_receiver.vl, scope_result_view_grow.vl, sem_excl_cl_capture_vec_push_while_view.vl, sem_excl_cl_view_live_closure_call.vl, sem_excl_cl_view_made_after_closure.vl, sem_excl_cp_closure_capture_by_copy_mutated_after.vl, sem_excl_ex_slice_noalias_O2.vl, sem_excl_il_borrowed_elem_across.vl, sem_excl_il_field_of_local.vl, sem_excl_il_loop_carried.vl, sem_excl_il_view_across_inout.vl, sem_excl_il_view_struct_across_inout.vl, sem_excl_lb_view_result_then_write.vl, sem_excl_lv_borrowed_elem_assign.vl, sem_excl_pj_let_result.vl, sem_excl_vf_inout_field_slice_passed.vl, sem_poly_c03_var_change_while_closure_live.vl, sem_poly_c04_owned_let_moved_while_live.vl, sem_poly_f12_fnptr_returns_view_of_arg.vl, sem_poly_f13_fnptr_field_returns_view.vl, sem_poly_g07_closure_view_then_mutate.vl, sem_poly_g16_pick_view.vl, sem_poly_g25_generic_view_struct_mutate.vl, sem_poly_r13_default_returns_view.vl, sem_poly_r14_trait_generic_returns_view.vl, sem_poly_r16_assoc_item_view.vl, sem_poly_x04_closure_field_returns_view.vl, sem_poly_x05_map_returns_captured_view.vl, sem_poly_x06_sink_closure_holds_view.vl, sem_poly_y01_closure_in_vec_conflict.vl, sem_poly_y02_closure_in_option_conflict.vl, sem_views_l_l11.vl, sem_views_sv_sv15_lexer_owns.vl, tests/own-try/lexer_owns/main.vl, tests/own-try/view_push/main.vl.

own.escape: closure_store_capture_direct.vl, closure_store_generic_capture.vl, closure_store_nested_capture.vl, closure_store_std_generic.vl, sem_poly_f14_fnptr_stores_arg.vl, sem_poly_f15_fnptr_stores_arg_direct.vl, sem_poly_f17_closure_stores_arg.vl, sem_poly_g15_push_view_param.vl, sem_views_lb_lb12_temp_loop.vl, sem_views_lb_lb13_temp_loop_method.vl, sem_views_lb_lb14_temp_struct_lit.vl, sem_views_lb_lb15_array_temp.vl, sem_views_lb_lb16_temp_owned_loop.vl, sem_views_lb_lb17_temp_owned_user.vl, sem_views_temp_receiver_escape_loop.vl.

own.moved: checkalloc_uaf_copy.vl, sem_excl_cp_vec_move.vl, sem_excl_sk_sink_then_inout.vl, sem_poly_f06_fnptr_sink_moves.vl, sem_poly_f24_fnptr_sink_twice.vl, sem_poly_y17_sink_generic_twice.vl.

other: err_conv_keywords.vl, fmt_err_holes.vl, sem_own_closure_temp_to_let_param.vl.

own.static: err_own_static_readonly.vl, sem_excl_st_view_static_across_global.vl.

effect: sem_core_eff_display_io.vl.

sync.not_send: sem_poly_th23_spawn_generic_closure.vl.

own.move_out: sem_poly_x13_sink_partial_move.vl.

Left as well: the 13 generated sweep tests (tools/sinksweep), the 4
f-string tests (fstring, interp in their names), tests/refactor,
tests/query and tests/lsp (their transcripts quote the code) and
tests/agent-eval (a solution.patch must apply).

## std migrated (0.26.2)

`fix --only fstring --keep-braces` over std: 368 f-strings from the
std.vl root and 14 in flat/test.vl and flat/fuzz.vl (which a plain
std.vl root does not load: `--in` them), 0 left. std's core is then
168410 of 168960 bytes (tests/std/core_sections.sh): 550 bytes of room,
tight; the next std change to the core sections needs the bound raised
or a section made lazy. The hello world's compile cost against 0.25.5
went to 1.13x (it was 1.07x): the format literals' calls in std's core.

## Never used

`refactor extract-function`, `inline`, `split`; `probe` and `reduce`
(no bug needed them); `batch`.

## Fix list, in order

1. [tool] done (tools/proc's rename_file): `fix` and `edit` write through a
   symlink, not over it; tests/refactor/symlink0262.
2. [tool] `fix --only fstring` rule 4: record which literals 0.26.1
   would have printed as they are (e.g. only in files that still hold an
   f-string, or behind `--plain-braces`), so that a second run is a no-op.
3. [compiler] done: macro_error's help for `println!(..)` is the call
   without its `!` (`println("{}", 1)`), `format!` `format_in(.., gpa)`,
   `write!(f, ..)` `f.write(..)`.
4. [lsp] done: hover on a name in a literal's hole answers the name's
   range (tests/lsp/fmtlit).
5. [compiler] an `unsafe { .. }` inside an f-string hole is not an unsafe
   site for unsafe.unjustified (examples/allocators/check-alloc: 3 more
   once migrated).
6. [std] `{:#?}`: Fmt's alternate flag and an indenting writer, derive
   (Debug) following it.
7. [tool] `query stats --all` is the only way to list a program's files;
   a `query files ROOT` would do it directly.
8. [tool] `fix`'s check compares errors by their text: an edit that
   rewords an error the program already has is refused as "new"
   (edit.breaks). Comparing by code and item would let the 76 error
   tests above migrate.
9. [tool] the check hook's mechanical fixes rewrite test fixtures:
   editing tests/refactor/tools017/main.vl removed calc.vl's unused
   import, which the transcript needs. Fixtures under tests/ should be
   checked, not fixed.
10. [compiler] the Defer node now means "a drop": rename it (NodeKind::Drop,
   temp_make's a DropIf) once the places IR is the only lowering.
