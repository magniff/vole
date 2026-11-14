# SRC: a source buffer that never moves (0.27.6)

`base::SRC` is every source file's text, one after another, and the
whole compiler indexes it by global offsets (tokens, nodes, diagnostics:
1,700 uses). In MVS up to 0.27.5 it is `static var SRC: [u8]`, a view of
the buffer `pcx.src_buf`. `add_source` appends a file with `buf_bytes`,
which can `realloc` the buffer, and then resets `SRC = buf_slice(all)`.
Any view of SRC held across an `add_source` would point into freed
memory. The rust edition's translation, `static mut SRC: &'static [u8]`,
claims a lifetime the buffer does not have. That claim is unsound, and so
is any `'static` result made from it. Because of this, gate 3's borrow
checker ties every SRC view (`tok_text`, `node_text`, `src(pcx)`,
`file_bytes`, ..) to the `pcx` it was read through.

## Audit (MVS, 0.27.5)

- **Who writes SRC.** It is set in three places: `load_sources`,
  `add_source` and `restore_sources`. `tools::fmt::pieces::read_pieces`
  also points it, for one lex, at a text of its own and then restores
  it. No code writes a byte of SRC (`SRC[i] = ..`: none).
- **Callers of `add_source`.** There are 15:
  - the module loader: `load_module`, the `<check>`, `<profile>` and
    `<trace>` sources, `load_std_if_named`/`load_std2`, `add_std_tree`;
  - `std2lazy::index_command`;
  - `import_c_headers`;
  - `add_arch_source`;
  - the generated sources: `parse_derived`, `parse_builtin`;
  - `embed::append_block_file`.

  None of them, and none of their callers, keeps a view of SRC live
  across the call. Each reads paths, symbols (`sym_text`: interned
  copies) and token offsets, or copies into a fresh buffer first.
  `expand_builtin_impls` reads `SRC[start..end]` in its loop but calls
  `parse_builtin` after the loop. `append_block_file`'s `rel` is a string
  table's (`str_at`), not SRC.
- **Long-lived holders.** No struct the front end keeps holds a view:
  Ctx has no `[u8]`/`str` field. The program's view items are cli's (of
  argv), explain/help (literals) and objfile's ASym/Found, which the back
  end makes after the last `add_source`.
- **Dynamic evidence.** The gate's stress-grow row (`VOLE_STRESS_GROW=1`:
  every growth moves the block and poisons the old one) self-compiles and
  runs the suite, so no view of a moved SRC is read on those paths.
- **One byte that is rewritten.** `add_source` drops the trailing NUL
  (`len -= 1`) and writes the next file over it. A held view that ends
  at the NUL would see that byte change. This is fixed first, in MVS, on
  its own: the NUL stays, a newline follows it, and the next file starts
  after that (each file still starts after a newline, which line and
  column counting rely on). The lexer reads such a NUL, which ends a
  file and is no file's text, as blank: a module of several files (std's
  tree, a C header's declarations) is lexed as one range across it. The
  tools' cache restores the same layout.

So MVS is sound today by discipline. The new representation makes that
discipline a property of base alone.

## Who loads a source set, and how often

`load_sources` is called by `build` (cli/build.vl), `fmt`'s
`read_paths`, the language server's `parses` (format), query's
`front_end` and textual's `read_places`; `restore_sources` by query's
cache. Each runs once per process. The language server's parent never
loads one: it forks a worker (`start_worker`), which loads the program
once (`answer::serve`, `load_program`) and is replaced by a new fork
when the program changes; `format`'s parse runs in a fork of its own
(`put_formatting`). `read_pieces` runs once per text fmt lays out: per
file of `fmt --all`, per edit of `volec edit`.

## Representation: (a), a reserved region that never moves

- **The region.** One virtual reservation per source set, made with
  `mmap(NULL, CAP, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANON|MAP_NORESERVE,
  -1, 0)`. Pages are committed when first touched, so the reservation
  costs address space, not memory. CAP is the caller's: 4 GiB by
  default (`SRC_CAP`), the self-compile's sources being about 16 MB.
  `VOLE_SRC_CAP=N` sets it for a run, for the test of a set that reaches
  its limit.
- **Failure is an error, never a null SRC.** A reservation mmap refuses,
  and a set that would pass its CAP, stop the compiler with one line,
  `error: cannot reserve N bytes for the sources` or `error: the
  sources pass the N bytes reserved for them (VOLE_SRC_CAP)`, and exit
  status 1 (base's `die2`). Nothing reads SRC after it.
- **Append-only.** `load_sources` and `add_source` read each file into
  a scratch buffer and copy it to the region's end, then write `'\n'`
  and a NUL. The next file starts after that NUL and a newline (the fix
  above), so no byte of a published SRC is ever written again. `SRC = region[0..len]` after each
  append. Offsets do not change, and files keep their starts and ends in
  `pcx.files`.
- **Never freed or unmapped.** A new source set in one process reserves
  a new region and leaves the old one mapped; no process makes more
  than one (above), so a long-lived process's address space grows by one
  CAP at most. `read_pieces` copies its text into a region of its own,
  of the text's size rounded up to pages, before SRC points at it, so a
  temporary SRC is region memory too. Buffers are never freed today
  either (base has no `buf_free`), so the memory a process keeps is the
  same as now.
- **Platform constants.** MAP_ANON and MAP_NORESERVE differ between
  Darwin (0x1000, 0x40) and Linux (0x20, 0x4000). base takes them from
  `std::TARGET_OS`, the per-OS tail of std (std/sys/macos.vl,
  std/sys/linux.vl) that the compiler is built with: a compiler built for
  aarch64-linux, or cross-built for x86_64-macos, gets its target's
  values by construction. (The chain rule: a std item new in 0.27.6 is
  used in compiler/src from 0.27.7, so the two values are written in base
  beside the selection, with their headers named.)
- **The unsafe.** It stays in base: the `mmap` extern, and the copies
  through the region's base pointer, each with UNSAFE/SAFETY: the write
  is past the published length and within CAP. SRC's readers stay as
  they are. `program_text` (lexer/embedded.vl) compares SRC with the
  region's base pointer instead of `src_buf`'s.

**Soundness.** For every published SRC value, the bytes `[0, len)` stay
mapped (the region is never unmapped), never move (the base is fixed),
and are never written again (appends go past `len`). A view of SRC is
therefore valid for the rest of the process, and `&'static [u8]` is its
true type. The translation's `static mut SRC: &'static [u8]` then holds
a `'static` value. Only base writes the static, and only in the
front end's single-threaded phase. middle/threads reads it after the
last `add_source`.

**Cost.**
- No copy on growth. `realloc` copies the whole text each time it
  doubles; this saves about 16 MB of copying per self-compile, for one
  copy of each file from the scratch buffer.
- One `mmap` per source set, one per `read_pieces`.
- No change to the 1,700 readers.
- Measured (aarch64-macos, 0.27.6): tests/compile_cost.sh before and
  after, in instructions, hello 98.8 to 98.4 M, std 1121.9 to 1116.4 M,
  check 8496.9 to 8464.6 M, rust 200.1 to 197.9 M (the same, within
  noise); the `VOLE_STRESS_GROW=1` self-compile gives the same object as
  without; x86_64-macos's objcheck of the compiler, 4 of 4.
- The language server over 5,000 edits of tests/lsp/prog's main.vl
  (didChange each, a hover every 50): the server's address space grew by
  0 KB (it loads no sources), its worker's by 6 MB (of 4.2 GB: the one 4
  GiB region, reserved once), with one worker throughout.

**Why not the others.**
- (b) Append-only chunks would make offsets per-file. Every
  `SRC[a..b]` and every token's start would have to become a
  (chunk, offset) pair, about 1,700 edits, for the same soundness.
- (c) An owned buffer with accessors keeps results non-`'static`.
  gate 3's C/D errors would then need a copy at each call, an allocation
  per diagnostic or symbol.

## The translator's side

`sig.vl`'s `static_result` gets one structural case, backed by this
invariant: a function whose every returned value is a range of SRC
(`SRC[a..b]`), or a call of such a function, has a `'static` result. Its
evidence is "base's region: never moved, freed or rewritten". That case
covers front/tests and lsp/answer's `tok_text`, check/arch's
`node_text`, lexer/blocks' `src`, lexer/strings' `label_line`,
unsafe_audit's `file_bytes`, check/literals' `src_text`,
check/format's `fixed_literal` and gpu_lint's `flag_prefix`.

## Not covered

Gate 3's C/D group is about 45 borrowck errors, about 12 of them views
of SRC; the other ~33 view storage this design does not touch. They
are front274's item (0.27.7, "Views of other storage"), in its order:
a scratch buffer read where it is consumed (modules' `joined`); a path
as a view of its own C string (linkfail's `root_path`, conflicts'
`path_of`, query's `bad_item_kind`); a reader that takes what it reads
(link_macho's `sym_name`); BUFS buffers frozen once written
(`buf_done`); and the translator's `'static` propagation, on
static_returns (sig.vl, this design's), whose rule already holds for
every static value: a function whose every return is one (a listed
static_result's call among them), or a range of one, returns
`&'static`, so a new static_result row propagates. The storage they
view: `buf_slice` views of BUFS buffers, which grow, are
cleared and are rewritten (lsp/complete's `signature`, `result_text`,
`field_text` and `call_snippet`, about 17; embed's `embed_type_name` and
`file_line_text`; modules' `joined`; cache's `get_str`), arch's tables
read through a raw pointer (`text`, `intr_text`), `cstr` views of paths
(linkfail's `root_path`), and views of tcx's own vectors.

## A growing buffer has no borrowed view (0.29)

`buf_slice(b)` returned a growing buffer's block as `&'static [u8]`,
good only until the next write to the buffer, with nothing to check
it. It is gone. A buffer is a number, so no borrow can end a view at
the next write; what a reader gets instead says what it has:

- `buf_copy(b)` (and `buf_copy_range`): the bytes copied into a `Vec`
  of the caller's, `&buf_copy(b)` where a `&[u8]` is read in one
  statement. A later write to `b` changes nothing in it.
- `buf_done(b)`: the buffer frozen and its bytes as `&'static [u8]`,
  which is true: every writer stops the compiler at a frozen buffer.
  For a buffer written for the last time (a text built and returned,
  a file read once).
- The operation done in base on the block, by value: `buf_append(dst,
  src)`, `intern_buf`, `find_sym_buf`, `buf_eq`, `buf_at`, `buf_len`.

Of the 1383 callers, 986 read the view in the statement that made it,
209 bound it and read it before any write (none held it across a
write of the same buffer in its own function), and 83 let it out of
its statement (returned it, stored it, or passed it on in a block's
value): the borrow checker listed those when the type became honest.
One wrote through the view's pointer (lsp/complete's put_completion:
`buf_set` now). Where older sections below say `buf_slice`, read
`buf_copy` or `buf_done`.

## Views of other storage (0.27.7)

Gate 3's borrow checker ties a view to the parameter it was read
through. `buf_slice`, `sym_text`, `cstr` and `c_slice` translate as
`-> &'static [u8]`. A function that wraps one of them and takes `&Ctx`
or `&Tcx` has its `&[u8]` result elided onto that parameter, so the
view borrows `pcx` or `tcx`, and the caller's next `&mut` conflicts
with it. Each class below is fixed where it is made, in MVS, by one
of two rules: a view that could change is consumed before the next
write, and a view of storage that is never written again is made
without the context.

- **A scratch buffer is read where it is consumed.** `joined` writes
  `a`, `sep` and `b` into `pcx.join_buf`, which it clears on every
  call, so its view lasts only until the next call and is never
  `'static`. It returns nothing. Its two consumers, `join_sym`'s
  `intern` and `qualified_if_known`'s `find_sym`, read
  `buf_slice(pcx.join_buf)` in their own call, so no view crosses a
  `&mut pcx`.
- **A path is a view of its own C string.** linkfail's `root_path`,
  conflicts' `path_of` and query's `bad_item_kind` take the `*u8`
  (a file's path, `--kind`'s argument), not `(f, pcx)` or `tcx`. A
  function with no reference parameter translates with a `'static`
  result, the convention `cstr` and `c_slice` keep. A file path and
  argv are never freed or written (paths: `load_sources`, `add_source`
  and the tools' cache's read buffer).
- **A reader takes what it reads.** link_macho's `sym_name` only
  reads the link, so it takes `l: Link`, not `inout`. That is `&Link`
  in the translation, and `sym_name(&l, l.imports[i])` is two shared
  reads, not rustc's E0503.

- **A buffer written for the last time is frozen.** `buf_done(b)`
  freezes buffer b and returns its slice; `buf_freeze(b)` freezes it
  without the slice. A frozen buffer is never written again: its cap
  word is stored as `-1 - cap`, so every one of base's writers
  (`buf_byte`'s `len >= cap`, and `buf_bytes`, `buf_str` and
  `buf_uint` through `buf_reserve`) reaches `buf_reserve`'s slow path,
  and `buf_reserve` and `buf_clear` stop the compiler there with
  `error: internal: buffer N written after buf_done froze it` and
  exit status 1. The writers' fast path costs nothing more. The
  slice is then valid for the rest of the process. Buffers are never
  freed, BUFS ids are never reused (`BUF_COUNT` only grows, and only
  `buf_new` assigns a slot), and a buffer's data moves only when it
  grows, which is a write. The frozen buffers are each producer's own
  fresh buffer (lsp/complete's `signature`, `call_snippet` and
  `mod_detail`; embed's `embed_type_name` and `file_line_text`),
  arch's table (`load_table` fills `table_buf` once) and the tools'
  cache's read buffer (`restore`). None of them is one of the buffers
  written directly, outside base (`BUFS[x].len = ..`: the code
  generator's asm and code buffers, objfile's out, the scratches).
  `volec __selftest freeze` writes to a frozen buffer and must stop
  with that error (tests/selftest.sh).

**The translator reads them as it reads SRC.** sig.vl's
static_returns already holds for every static value: a function whose
every return is a text literal, a range of SRC, a call of a function
with a `'static` result (static_result's list, or static_returns
itself), a local bound only to one, or a range of one, returns
`&'static`. So a frozen buffer's views need only rows in
static_result's list, each with its evidence, and they propagate from
there to their callers and to ranges of them:

- base's `buf_done`: the buffer is frozen (above), so its slice is
  valid for the process. lsp/complete's `signature`, `call_snippet`
  and `mod_detail`, embed's `embed_type_name` and `file_line_text`
  return it, and are `'static` by static_returns.
- arch's `text` (arch/table.vl) and `intr_text` (arch/mod.vl): ranges
  of `BUFS[pcx.table_buf].data`, the table, which `load_table` fills
  once and freezes before any reader runs.
- the tools' cache's `get_str` (tools/query/cache.vl): a range of
  `tcx.rd`, the read buffer `restore` freezes before `read_words`
  points `rd` at it (its only writer), or an empty literal. A second
  `restore` reads into a fresh buffer and leaves the first frozen.

A row is a function the translator cannot prove from its body (the
buffer it reads is named by an id, `pcx.table_buf`, or a raw pointer,
`tcx.rd`); the list stays explicit, so a new reader of a buffer that
is not frozen does not become `'static` by its shape.
