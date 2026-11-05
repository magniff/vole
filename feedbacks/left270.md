# left270: the compiler's last exempt statics, Ctx's raw tables, the rawptr hoist (0.27.0)

## Verdict

Steps 1 to 3 done; step 4 analysed, not done.

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
4. The 8 view statics: see "Step 4" below.

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

Read from the code, not tried:

- tools::fmt::pieces::FT (18 uses), tools::lsp::complete::TX (24) and
  PREFIX (a slice of TX, 4), tools::textual::places::LINES_TEXT (3).
  Each is a view of a text parameter laundered through `text.ptr` into
  the static. They can go now, as a parameter or a small view context
  made where the text lives and passed down. They cannot be Tcx's
  fields: Tcx outlives the text (own.escape).
- tools::fmt::pieces::BAD_MESSAGE (14), tools::reduce::program::WANT (3)
  and tools::refactor_shape::table::X_TEXT (3). These hold literals, a
  Buf's bytes (buf_slice) or a symbol's text (sym_text). They can be
  Tcx fields now. X_TEXT can also just be `sym_text(tcx.x_sym)` where it
  is used.
- base::SRC (1335 uses) is a view of the source buffer, taken again
  after every add_source (the buffer grows while views of it are used).
  A field holding a view needs the text never to move. Options: an
  append-only store whose earlier bytes stay put, or a pointer and
  length read through an unsafe accessor as Sym's text is (base::
  sym_text). As an owned `Vec<u8, Comp>` field of Ctx, index reads work
  now, but a slice of it passed beside an inout `pcx` is own.conflict.
  0.27's references do not change that: a `&[u8]` held by the context
  is still a borrow of what grows.
