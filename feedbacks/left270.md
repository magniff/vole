# left270: the compiler's last exempt statics, Ctx's raw tables, the rawptr hoist (0.27.0)

## Verdict

Steps 1 to 4 done; base::SRC is left for 0.27.x, with a design.

1. SYMS and TYPES split into a read-only lookup (the tasks') and a
   writing path (the main thread's), moved into `Ctx`, and the alloc
   exemption deleted: no static is exempt. Statics 188 to 177.
2. `refactor table` takes a context's field. Eight of Ctx's raw tables
   are Vecs, and 267 unsafe blocks went with them. Unjustified unsafe
   went from 3054 to 2788.
3. `fix --only rawptr` takes a nested call into a let. Run over
   compiler/src, it took 715 calls into lets and made 121 task contexts
   `inout FnCtx`. `cx: *FnCtx` parameters went from 143 to 24, and
   unjustified unsafe from 2788 to 2776.
4. Seven of the 8 view statics are gone (Tcx fields, a parameter); base::SRC
   stays, designed below. Statics 177 to 170.

## What worked

- A read-only lookup with a fallback beside each writer (find_type
  beside make_type, rt_panic_sym beside make_rt_panic_sym). The writers
  run on the main thread before the tasks (lay_out_types,
  prepare_tasks). The tasks' writes became reads that threads_writes.sh
  could check without new rules.
- `volec rewrite 'SYMS[$i].text' 'sym_text($i)'`: 598 sites in one
  checked edit.
- `fix --only statics --group` with a hand-written group file did the
  move of SYMS and TYPES into Ctx. Twelve own.conflict sites were left
  to take into lets by hand.
- For the hoist, rawptr-list's new `at FILE:LINE` column. It names the
  call that keeps a parameter raw. Before it, finding which of a
  parameter's hundred calls blocked it took a debug build each time.
- A small repro program per refusal (tests/refactor/rawptr0270 grew this
  way). Each of the tool's wrong turns showed up there before it reached
  compiler/src: hoisting a receiver, hoisting `&cx`, editing std,
  splitting a comment from its unsafe site.

## What cost time, ranked

1. The hoist's convergence. Each run's marks are monotonic, and a
   parameter marked nested-call by an inner call refused every outer
   hoist that reached it. Fixed: a callee kept raw only for nested-call
   can still be hoisted around (decidable_but_nested). It took several
   rounds over compiler/src (each about a minute) to find this and its
   relatives (a copied number `cx.a[v]` beside the access, `&cx` as the
   checker's `&*cx`, an inout argument's `unsafe { &*q }`).
2. Trial runs over compiler/src shared the worktree with the tool's own
   uncommitted source. One `git stash` with a pathspec, then dropped,
   lost two staged files; `git checkout -- compiler/src` lost a
   one-line fix twice. Commit the tool before every trial run.
3. The conversion's leftovers. The to-inout edit turns `unsafe { &*cx }`
   into `unsafe { &cx }` with its UNSAFE:/SAFETY: pair, which is now
   false (cx is inout). `fix --only unneeded-unsafe` keeps them (they
   are justified), and `unneeded-justified` would also take many older
   justified blocks. I used `rewrite 'unsafe { &cx }' '&cx'` and a
   script for the 47 comment pairs.

## Fix list

1. [tool] rawptr's to-inout edit should write `&cx`, not `unsafe {
   &cx }` with its pair, when the raw pointer given becomes the inout
   parameter itself (47 sites by hand in this run).
2. [tool] The hoist cannot reach a call on the right of `&&` or `||`,
   nor one in an argument that borrows a part of the context
   (`&cx.consts`, `&cx.pdom_cap`). These keep 17 parameters raw, ir_val,
   ir_arg and ir_operand among them. A block in place, `a && { let v =
   g(&cx); f(&cx, v) }`, would keep the short circuit; I did not write
   it, since the result reads badly.
3. [tool] The lets the hoist writes before a statement that shares its
   line (`else { let v = ..; f(&cx, v) }`) stay on that line: fmt keeps
   them as they are.
4. [tool] `edit patch --old` with a string the shell's quoting turned
   into `\\t` gives `patch.no-match` with the right diagnosis. A
   `--old-file` would avoid the quoting.
5. [tool] `refactor table` refuses intrs (a pointer into the table),
   str_h and found (grown by hand), ctoks and macros (the capacity in
   another context). Each is right, but each needs a hand step first.
6. [doc] A big read-only `*T` parameter becomes inout, not let. Inout is
   what makes nested reads conflict: `put(&c, 2, get(c, 3))` checks with
   get's `cx: Ctx` (a let). For read-only helpers (ir_val, ir_arg,
   is_const) a let would remove the nested-call class. Say why big
   becomes inout, or offer let.

## Step 4: the 8 view statics

Seven are gone; base::SRC stays (below).

- tools::reduce::program::WANT and tools::fmt::pieces::BAD_MESSAGE are
  Tcx fields: `reduce_want` and `bad_message`, each a Buf (an owned copy)
  read through buf_slice. `set_bad_message` and `bad_message` are the
  accessors.
- tools::refactor_shape::table::X_TEXT is gone: put_x reads
  `sym_text(tcx.x_sym)`, the Tcx field it was made from.
- tools::fmt::pieces::FT and tools::lsp::complete::TX are Tcx fields,
  `fmt_text` and `complete_text`, each a `Vec<u8, A>` copy of the text
  made by read_pieces and read_text. The pieces and tokens are offsets in
  that copy. fmt's save and restore of FT around a nested format is a
  clone. The completion lexers take the request's text as a parameter.
  Five places hand a token beside `&tcx` and now pass a copy
  (`to_vec_in`).
- tools::lsp::complete::PREFIX is two offsets in Tcx, `prefix_start` and
  `prefix_end`, read by match_rank.
- tools::textual::places::LINES_TEXT is a parameter: match_in and
  in_line_comment are given the text, which their two callers hold.

Tcx cannot hold a view, which is why FT and TX are copies, not views. I
tried `[u8]` fields and got own.escape in tools::patch::run_patch: the
whole of Tcx becomes a view of what it holds. Passing the text as a
parameter would have reached 108 functions for FT and 63 for TX
(`statics-list` with a probe group). A copy per format or completion
request is cheap, and the checker now checks the uses: the
`text.ptr`-laundered views are gone.

## 0.27.x item: base::SRC

base::SRC is a view of the source buffer (`pcx.src_buf`, a Buf). It has
1,335 uses: 856 in tools, 454 in front, 19 in base, 3 in middle, 2 in
back and 1 in places. About 1,190 are index or slice forms, about 252 of
them slices. load_sources, add_source and restore_sources take it again
after each append, because the buffer grows (moves) while views of it
are in use. A field cannot hold a view of what grows, under MVS or
under 0.27's references alike. Two designs:

1. **An append-only source store that never moves written bytes.** The
   texts live in fixed chunks (a new file goes into a new chunk, or a
   fresh one when it does not fit; a file never spans two chunks). A
   position stays a single i64 (chunk base + offset), and `src(pos, len)`
   returns a view that stays valid for the whole compilation. Ctx owns
   the store as a field, `pcx.src: SrcStore<A>`. Reads become
   `pcx.src.byte(k)` and `pcx.src.text(a, b)`. The views come from
   memory that is never freed or moved before the compilation ends,
   which is what the store itself guarantees (one unsafe site, in the
   store). The lexer's hot loops keep their pointer into one chunk.
2. **A pointer and length behind an accessor, as Sym's text is**
   (base::sym_text, step 1). `pcx.src_ptr`, `pcx.src_len` and `fn
   src(pcx) -> [u8]` in one `unsafe { ptr[0..len] }`, with the same
   argument as today's static: nothing reads a view of SRC across an
   append. This is mechanical, `rewrite 'SRC' 'src(pcx)'` plus `fix
   --only statics --group` for the functions without pcx. But it keeps
   the soundness argument informal: a view taken before an add_source
   and used after it dangles, and nothing checks that.

(1) is the one that makes the uses checked; (2) only removes the static.
Either way, about 252 slices are passed beside `&pcx` in some calls and
need the hoist or a copy where the checker objects. The count of those
calls is the first thing to measure.
