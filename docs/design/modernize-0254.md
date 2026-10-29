# Modernizing compiler/src (0.25.4): the plan

compiler/src still writes much of its code as it was written before vole
had generics: `base::IntVec` (a raw pointer, a count, a capacity), tables
kept as a raw static pointer with a `_COUNT` and a `_CAP` beside it,
buffers that are `i64` handles into a global `BUFS`, C strings (`c"..."`,
`*u8`), structs reached through `*FnCtx`. Almost all of compiler/src's
unsafe code is this code: an index into a raw table needs `unsafe`, an
index into a `Vec` does not.

This file is the plan for replacing those idioms. It gives what there is
(§1), what a `Vec` costs against them (§2), the rules every step keeps
(§3), the steps in order (§4) and the first step, done (§5).

The rules come from the brief and AGENTS.md: the compiler emits the same
output after each step (`volec same-output`, byte for byte), the fixpoint
holds, the suite stays green, and the gate's `compile-cost` row does not
rise against 0.25.3. compiler/src may use 0.25.3's language only (the
bootstrap rule): a step may need a new tool, but its code uses nothing
new in 0.25.4.

## 1. The inventory

The counts are from the tools, on the base `ae68b63e` (0.25.3), unless a
row says otherwise. `refs` is `volec query refs NAME --count`; `grep` is
`volec query grep TEXT --code --count` (text, not names);
`static` is `volec query items --kind static`.

The unsafe sites come from `volec query unsafe --summary --no-std`: 5,408
sites (5,357 blocks, 10 `unsafe fn`s, 41 extern blocks), 5,315
unjustified, 938 unneeded. By class: static-mut 2,480, raw-pointer
1,431, other 946 (the 938 unneeded among them), ffi 302, alloc 134,
transmute/cast 115.

What each block needs, from `--json` (the operations of each block, after
step 1's 938 are gone, 4,419 blocks):

| what a block needs | blocks | where most are |
|---|---:|---|
| only an index into a static raw table (`NODES[n]`, `SRC[i]`, `SITES.data[i]`) | 2,480 | front 1,444, tools 711 |
| only raw-pointer accesses (`cx.f` through `*FnCtx`, `v.data[i]`, `*p`) | 909 | middle 412, back 285 |
| both of those | 513 | tools 170, front 121, middle 116 |
| a C call (with pointer accesses or not) | 369 | tools 94, back 91, middle 84 |
| other mixes (casts, unsafe fns) | 148 | tools 111 |

Of the 909 raw-pointer-only blocks, 625 go through `cx.` (a `*FnCtx`),
about 73 only through an IntVec's `.data[i]`, 211 through other pointers.
Of the C calls, 124 blocks call only `free` and 70 only `strlen`,
`memcpy`, `memcmp` or `memset`.

The 2,480 table-only blocks, by the tables they index (the names in each
block's text; 235 index only IntVec statics or a small table): NODES in
1,129 of them, TYPES 302, FNS 256, SRC 245, SYMS 235, TOKS 139, DEFS 133,
FILES 128, LOCALS 110, STRUCTS 81, ENUMS 76, BUFS 71. A block becomes
unneeded when every table it indexes is safe, so the order matters; taken
greedily, the blocks freed:

| tables safe | blocks freed (cumulative) |
|---|---:|
| NODES | 562 |
| + SRC | 699 |
| + TYPES | 835 |
| + FNS | 969 |
| + SYMS | 1,085 |
| + TOKS | 1,198 |
| + DEFS | 1,305 |
| + FILES | 1,421 |
| + LOCALS, BUFS, MODULES, STRUCTS, ENUMS, CLOSURES, VARIANTS | 1,735 |
| + 10 more (INTRS ... FRAGS) | 1,912 |

The idioms:

| idiom | count (command) | files | modern form | unsafe it carries |
|---|---|---|---|---|
| `base::IntVec` | 2,823 refs (`refs crate::base::IntVec`: 1,387 literals, 1,206 types, 230 imports); `.data[` 5,067 (grep); `.count` 4,642 (grep); `IntVec::push` 2,407, `get` 201, `pop` 41, `items` 35, `set` 21 refs; 519 statics; about 170 struct fields in 25 structs (FnCtx 104, IRFunc, CcCtx, Link, Audit...) | every directory | `Vec<i64, Comp>` (base/comp.vl: `Comp {}` is a constant, so a static can hold one; a `Gpa` cannot) | `.data[i]` is a raw index: about 73 blocks need nothing else, and IntVec statics are part of the 235 table blocks and of the 513 mixed ones |
| table triples `static var X: *T` + `X_COUNT` + `X_CAP`, grown by `base::grow` | 242 pointer statics (`static`), 20,918 refs to them (NODES 8,608, TYPES 1,321, FNS 990, SRC 928, DEFS 889, TOKS 648, SYMS 631, FILES 603, BUFS 566); 59 `_CAP` statics; `grow` 84 refs | front, tools, middle, back | `static var X: Vec<T, Comp>`: `X[i]` stays, `X_COUNT` is `X.len()`, grow-and-store is `X.push(v)` | the 2,480 static-mut blocks, part of the 513 mixed |
| buffer handles: `buf_new()` into `BUFS` | `buf_new` 1,514, `buf_str` 7,383, `buf_bytes` 10,938, `buf_byte` 1,472, `buf_int` 652, `buf_slice` 1,424, `buf_write_fd` 206, `BUFS` 566 refs (`BUFS[` 485, grep) | every directory | `std::Buf<Comp>` values, or kept as handles with safe accessors | the API itself is safe; the 485 direct `BUFS[b]` uses are static-index (71 table-only blocks name BUFS) |
| C strings | `c"` about 15,300 (`query grep 'c"' --strings`: 16,336, of which 1,009 in the generated std text); `*u8` 2,900 (grep); `cstr` 171, `intern_c` 481, `streq` 328, `strlen` 113 refs | every directory | `str` / `[u8]` literals and parameters (`buf_bytes`, an `intern` of `[u8]`) | `strlen` and `*u8` indexing: the 70 strlen/memcpy blocks and part of the raw ones |
| `*FnCtx` and other `*T` parameters | `*FnCtx` 1,498 (grep), `sink *` 1,478 (grep) | middle, back, gen0 | `inout FnCtx` (`fix --values` made `*T` parameters references in 0.17) | `cx.f` is a field through a raw pointer: 625 blocks |
| hand-written containers | `alloc_array` 391, `alloc_zeroed` 94 refs; `middle::lower::ssa::HMap` 410 refs (raw keys and values, 117 statics); `free` in 140 blocks | middle, back, front | `Vec<T, Comp>`, `HashMap<K, V, Comp>` | `free` (124 blocks), raw indexing |
| `static var` globals | 1,806 statics (626 `i64`, 519 `IntVec`, 231 `bool`, 117 `HMap`, 242 pointers) | everywhere | contexts passed down (contracts-verification.md §4.3, `refactor context`) | none: statics are safe (`guide unsafe`); they are the parallel code generator's problem, not this plan's |
| unneeded unsafe blocks | 938 (`query unsafe --summary`) | 225 files | none | 938 sites, all unjustified |

## 2. Vec<i64> against IntVec

The question: does the compiler get slower when its IntVecs and tables
become `Vec`s? Micro-benchmarks of what the compiler does with them, at
-O2 on aarch64-macos, built by 0.25.3, the code compared in the emitted
assembly (`volec -O2 --emit-asm`). The programs are in the brief's
scratch; the shapes are below.

**The load.** The machine was shared: load average 3.1 to 4.1 on 12
cores while the timings ran (`uptime` before and after each run), so the
timings are indicative, not evidence; the assembly is the evidence. Three
runs each; the ranges are over the runs.

Kernels on 4M i64 (15 rounds; a sum 5 times a round, each call given a
different argument so that the optimizer cannot reuse a pure call's
result):

| kernel | IntVec (ms) | Vec<i64> (ms) | the code at -O2 |
|---|---:|---:|---|
| push 4M (fill) | 133-144 | 115-129 | the same shape; Vec reloads its length twice after the store, calls `reserve_more` out of line |
| `for i in 0..len { s += v[i] }` (v a let parameter) | 39-41 | 47-58 | IntVec (passed by value, in registers) is vectorized, 8 lanes; Vec (a let parameter, passed by address): the bounds check is gone, but `ptr` is reloaded every element, so the loop is only unrolled by 4 and not vectorized |
| `for x in v.iter()` | (no iterator) | 28-31 | vectorized, 8 lanes: the fastest |
| `v[i] = v[i] + 1` (v inout) | 93-95 | 129-138 | Vec reloads `len` and `ptr` and checks the bound every element (the store might, as far as the optimizer knows, change the Vec's header); IntVec reloads `data` too but has no check |
| data-dependent index (`k = (x*7 + k) & 65535`, L1-resident) | 40-49 | 57-60 | Vec: a header reload and a bounds check per access; IntVec unrolled by 2 |

A static table of 48-byte nodes, as NODES (raw `*Node` + count, against
`static var VEC: Vec<Node, Comp>`):

| kernel | raw (ms) | Vec (ms) | the code |
|---|---:|---:|---|
| add 1M nodes, 10 rounds | 35-36 | 40-41 | push through `reserve_more` |
| walk 10M links (48 MB, latency-bound) | 758-859 | 749-864 | per access: raw loads the static pointer (1 load); Vec loads `ptr` and `len` (2) and compares |
| mark: `X[i].end = X[i].start + X[i].kind` over 1M | 53-60 | 52-75 | the same plus a compare and branch per element |

**The conclusion.** Vec<i64> is not slower where it matters least
(growth: faster) and not slower on memory-bound work; it costs a bounds
check and a header reload on each access in loops over a Vec reached
through a parameter or a static, about 20 to 40% on such a loop alone
(the reload, not the check, also blocks vectorization). The compiler's
tables are mostly read at data-dependent indices (`NODES[NODES[n].a]`),
so each access gets its check. Whether that shows in the compile time is
for the gate's `compile-cost` row: the first table step (NODES, the
hottest: 8,608 references) measures it before the others follow.

What to fix first, in the optimizer (middle/), as step 2:

1. **Loads from a `let` parameter's header are loop-invariant.** A `let`
   parameter cannot change during the call (the law of exclusivity), so
   `v.ptr` and `v.len` of a `let v: Vec<T>` may be hoisted out of a loop
   whatever the loop stores. This gives the let-parameter loop the
   IntVec's vectorized code back, and the existing bounds-check
   elimination then has a hoisted `len` to work with.
2. **A Vec's buffer does not alias its header.** A store through `ptr`
   (an element, a T) cannot write `ptr`, `len` or `cap` of the same Vec:
   the buffer is a block from the allocator and the struct is `#[sealed]`.
   With that fact (alias classes for sealed std containers' buffers),
   `ptr` and `len` of an `inout` Vec or a static Vec are hoisted out of
   loops whose only stores are to elements, and `for i in 0..v.len() {
   v[i] = ... }` loses its per-element check.
3. Where an index loop only reads, `for x in v.iter()` is already the
   fastest form: the migration's rewrites should write it where the index
   is only used to read the element (`rewrite 'for $i in 0..$v.len() {
   $s... }' 'for $x in $v.iter() { $s... }' --subst '$v[$i]' '$x'`, as
   docs/refactor-shape.md shows for IntVec).

Neither fix is needed before the first table step: that step measures
what the checks cost in the compiler as it is, and the fixes come with
the step whose loops they speed.

## 3. Rules for every step

- One idiom, one tool run (or a script of them), its output proven
  byte-identical: `volec same-output OLD` (the corpus: tests/run,
  examples, bench, compiler/src; every target, -O0 to -O2). The tool
  prints the compiler's own path in `try:` lines, so OLD and the new one
  differ there; compare after replacing OLD's path by `target/volec`
  (§5 does it), or run both from the same path.
- After each step, `volec fix --only unneeded-unsafe` (step 1's tool)
  takes away the blocks the step made unneeded, and `tests/unsafe_audit.sh
  -u` lowers the baseline.
- Generated files are their scripts' (`// Generated by ...`:
  front/stdsrc.vl from compiler/std/embed.sh, arch/tables.vl from
  compiler/arch/embed.sh, guide/text from compiler/guide/embed.sh): a
  step changes the script and regenerates (`embed.sh -c` checks it).
  `fix --only unneeded-unsafe` leaves them; `rewrite` and `edit` do not.
- A global step (one that touches every module: a table, a type every
  module names) runs alone, as one branch, merged before the next starts.
  A module step runs in parallel with module steps on other modules
  (`--in MODULE` on every tool), at most five at once (AGENTS.md).
- Each step reports the unsafe counts before and after (`query unsafe
  --summary --no-std`), the same-output line and, when it touches a hot
  path (tables, IntVec in middle/back), the `compile-cost` row.

## 4. The steps, in order

Each step: the idiom and its scope; the tool; the unsafe it is expected
to remove; its risk; what it can run in parallel with.

**Step 1. Unneeded unsafe blocks (done, §5).**
- Idiom, scope: `unsafe { }` around nothing unsafe; all of compiler/src.
- Tool: `volec fix --only unneeded-unsafe` (new in this step; `rewrite
  'unsafe { $b }' '$b'` matches one-statement blocks only and cannot
  splice a block's statements into the block around it).
- Unsafe removed: 938 blocks.
- Risk: low; the edit is checked, its output proven identical.
- Parallel: no (225 files); it ran alone.

**Step 2. The optimizer's Vec facts (§2: 1 and 2).**
- Idiom, scope: middle/ (LICM, alias classes, bounds-check elimination);
  no source idiom changes.
- Tool: none (a compiler change); tests: bench pairs of IntVec and Vec
  loops whose assembly the fix must match, the fuzz-sem row.
- Unsafe removed: none; it removes the cost the later steps would add.
- Risk: medium (an optimizer change; same-output is not the proof here:
  the output changes, so the suite, the fuzzers and the assembly are).
- Parallel: yes with steps 3 and 4 (other directories); before the
  middle/ and back/ parts of steps 6 and 7.

**Step 3. The table tool.**
- Idiom, scope: a new `volec refactor table X [--count X_COUNT] [--cap
  X_CAP] [--alloc base::comp::Comp]` in tools/refactor_shape: the triple
  becomes `static var X: Vec<T, Comp> = Vec::new_in(Comp {});`, reads of
  `X_COUNT` become `X.len()`, the grow-and-store sequence (`X = grow(X,
  X_COUNT, &X_CAP); X[X_COUNT] = v; X_COUNT += 1;`, and its variants)
  becomes `X.push(v)`, `X_COUNT = 0` becomes `X.clear()`, `X_COUNT -= k`
  becomes `X.truncate(X.len() - k)`; a use it cannot place (`&X[i]` kept
  as a raw pointer, `X` passed to C, `X_CAP` read) is listed and refused.
  The 0.18 plan named it (contracts-verification.md §4.1, step 3) and it
  was never built; without it, a table is a dozen hand edits plus
  `rewrite --text X_COUNT 'X.len()' --word`, which cannot tell a read
  from a write.
- Unsafe removed: none by itself.
- Risk: low (a tool; transcripts in tests/refactor).
- Parallel: yes, with step 2 and with step 6's module branches.

**Step 4. Tables to `Vec<T, Comp>`, hottest first, one table a branch.**
- Idiom, scope: the 242 table statics. First NODES (front/ast; 562
  blocks freed alone), with the `compile-cost` row: it is the measure for
  every table after it. Then SRC, TYPES, FNS, SYMS, TOKS, DEFS, FILES
  (1,421 blocks with NODES), then the next 17 (1,912 in all), then the
  long tail by module.
- Tool: `refactor table` (step 3), then `fix --only unneeded-unsafe`.
- Unsafe removed: about 1,900 of the 2,480 table-only blocks for the 25
  largest tables, plus the mixed blocks whose raw part goes in steps 6
  and 7. SRC becomes `Vec<u8, Comp>` (or a slice of one); its
  `SRC[a..b]` slices stay.
- Risk: medium. Performance: every access is checked (§2), measured on
  NODES first; if NODES costs more than the gate allows, step 2's fixes
  come first, then NODES again. Semantics: a raw `&NODES[i]` kept across
  a push was a stale pointer already (the stress-grow gate row finds
  them); as a Vec it is a view the own pass may refuse (`own.static`);
  the tool lists each one.
- Parallel: no: each table touches every module that reads it (the
  unsafe blocks around its uses go). One table a branch, merged before
  the next; small tables private to one module can go in module branches
  (step 7).

**Step 5. IntVec's uses moved to the API Vec shares, module by module.**
- Idiom, scope: the 2,823 IntVec references, in branches by directory
  (front, tools, middle, back with gen0, base with arch, cli and guide).
  First base/ gives IntVec the methods Vec has: `len()`, `iter()`,
  `clear()`, `truncate(n)`, `last()`, and `pop()` returning an `Option`
  (its 41 callers given `.unwrap()`); then each module rewrites:
  `$v.data[$i]` to `$v.get($i)` and `$v.data[$i] = $x` to `$v.set($i,
  $x)`, `$v.count` to `$v.len()`, `$v.count = 0` to `$v.clear()`, `(&$v).items()`
  to `$v.iter()`, with `--where '$v: IntVec'` (and `*IntVec`) and `--in
  MODULE`; the read-only index loops to `for x in v.iter()`.
- Tool: `volec rewrite` (typed; the pilot in §5 ran the same rewrites);
  `refactor --script` for a module's set, checked once (a `rewrite --text`
  line cannot join a script: tools/agent-feedback).
- Unsafe removed: each `.data[i]` becomes a checked `get`, so the blocks
  holding only IntVec accesses go at once (about 73 alone; the IntVec
  statics' share of the 235 table blocks), and the mixed ones go when
  their tables have (step 4). The pilot freed 2 of its file's 12 blocks
  because the other 10 also index SRC and NODES: tables first.
- Risk: low per module (each rewrite is checked); a checked `get` per
  access costs what §2 measured, in middle/ and back/ above all
  (compile-cost per branch there).
- Parallel: yes, the directories' branches with each other (each touches
  only its own files after base/'s methods are merged), not with a table
  step on the same files.

**Step 6. IntVec becomes `Vec<i64, Comp>`.**
- Idiom, scope: base::IntVec's definition, its 1,387 literals
  (`rewrite 'IntVec { data: 0 as *i64, count: 0, cap: 0 }'
  'Vec::new_in(Comp {})'`), its 1,206 type names, the 25 structs with
  IntVec fields.
- Tool: `rewrite`, then `rewrite --text IntVec 'Vec<i64, Comp>' --word
  --code`; the own pass's errors where a copy was meant (`let a = b` of
  an IntVec made two handles to one buffer; a Vec moves): each is a
  `.clone()` or a reference by the error's `try:`.
- Unsafe removed: IntVec's own (base/mod.vl, 3 blocks) and `grow` for i64.
- Risk: high, which is why step 5 comes first: a struct holding a Vec is
  owned, so `let f = IRFUNCS[i]` (a copy out of a table of IRFunc, which
  holds IntVecs) becomes a move out of an index. FnCtx's 104 IntVec
  fields are reached through a pointer and move nowhere. Locals now drop
  at their scope's end (Comp frees through C's free): the compiler's
  memory falls, its output does not change.
- Parallel: no (one branch; it touches every file).

**Step 7. `*FnCtx` and other pointer parameters to `inout`.**
- Idiom, scope: `cx: sink *FnCtx` (1,498) in middle, back, gen0; then the
  other `*T` parameters of front and tools.
- Tool: `volec fix --values` (0.17; parameters written through become
  `inout`, read ones `let`), per directory with `--in`; FnCtx's own
  functions first.
- Unsafe removed: the 625 blocks reached only through `cx.`, and the
  rest of the 513 mixed ones once their tables are safe.
- Risk: medium: two `*FnCtx` to one context in one call (an alias the
  raw pointers allowed) is an exclusivity error now; each is a real
  question about the code.
- Parallel: middle with back with gen0 only once FnCtx's signature
  functions are merged (they cross the three).

**Step 8. Strings: `c"..."` and `*u8` to `str` and `[u8]`.**
- Idiom, scope: the C-string parameters of the compiler's own functions
  (`buf_str`, `intern_c`, `die`, `diag`, `streq`, `cstr`), then their
  15,300 literals.
- Tool: base/ gets the `[u8]` forms (`buf_bytes` exists; `intern` exists);
  `rewrite 'buf_str($b, $s)' 'buf_bytes($b, $s)'` where `$s` is a literal
  (a `--where '$s: *u8'` and the literal's spelling: the `c` prefix goes,
  the escapes stay; tools/agent-feedback: rewrite cannot match on a
  literal's kind, so the text step is `rewrite --text 'c"' '"'` on the
  files a module branch owns, then checked).
- Unsafe removed: the strlen/memcmp blocks (about 70) and `*u8` indexing;
  compile speed gains a strlen per literal.
- Risk: low; parallel by directory once base/'s forms exist.

**Step 9. Buffers: `BUFS[b]` read directly.**
- Idiom, scope: the 485 direct `BUFS[b]` uses outside base/ (`.len`,
  `.data`) to `buf_len(b)`, `buf_slice(b)`; the handles themselves stay
  (they are stored in tables and IntVecs as numbers: making them
  `Buf<Comp>` values is a redesign of their owners, after 0.25.4).
- Tool: `rewrite 'BUFS[$b].len' 'buf_len($b)'` and similar, per module.
- Unsafe removed: the 71 table-only blocks naming BUFS, and BUFS's share
  of the mixed ones.
- Risk: low; parallel by directory.

**Step 10. Hand-written containers.**
- Idiom, scope: `alloc_array` scratch arrays (391) with their `free`s
  (124 free-only blocks), `ssa::HMap` (410 refs) to `HashMap<i64, i64,
  Comp>` (measured first: HMap is in the SSA builder's hot loop).
- Tool: rewrite per module; HMap: its methods first given HashMap's
  names (as IntVec's in step 5), then the type.
- Unsafe removed: about 150 blocks (the frees, the raw indexing).
- Risk: medium for HMap (performance), low for scratch arrays; parallel
  by module.

**Step 11. What stays, justified.**
- Idiom, scope: the C calls (ffi, 302 sites), the allocator islands
  (base/comp.vl, base/mod.vl), the thread pool, the object writer's bytes.
- Tool: by hand, `// UNSAFE:` and `// SAFETY:` above each (`query unsafe
  --unjustified FILE`).
- Unsafe removed: none; the unjustified count goes to the sites left.
- Risk: low; parallel by directory.

The order, with what may overlap:

```
1 (done) ─┬─ 2 (middle) ─────────────────────────┐
          ├─ 3 (tool) ─ 4: NODES ─ SRC ─ TYPES ... ┴─ 5 (by directory, ×5) ─ 6 ─ 7 ─ 8, 9, 10, 11 (by directory)
```

Steps 2 and 3 run beside each other; step 4's tables run one at a time;
step 5's directories run beside each other; 6 alone; 7 by directory
after FnCtx's signatures; 8 to 11 by directory, beside each other.

## 5. Step 1, done; the pilot

**Step 1.** `volec fix --only unneeded-unsafe` (tools/fix/unneeded.vl,
docs/refactor.md's fix table): each `none (unneeded)` block of `query
unsafe` taken away, its code kept in its scope (a block on lines of its
own: its lines, one level less indented; on one line: its code, in
parentheses where operators around could bind otherwise); a block is
opened only when it is its block's last statement or declares nothing at
its own level. Over compiler/src: `fixed 933 unneeded unsafe blocks, 5
left as they are`. The 5: std_source in front/stdsrc.vl (generated:
compiler/std/embed.sh changed instead, with compiler/arch/embed.sh, whose
tables.vl the tool had also rewritten; both regenerate to the tool's
text, `embed.sh -c` clean), and 4 that declare before other statements or
spread over lines (`let call = unsafe {`), done by `edit patch`.

| `query unsafe --summary --no-std` | before | after step 1 | after the pilot |
|---|---:|---:|---:|
| sites | 5,408 | 4,470 | 4,468 |
| unjustified | 5,315 | 4,377 | 4,375 |
| unneeded | 938 | 0 | 0 |

The proof: the fixpoint (`bootstrap.sh --dev --no-suite`: fixpoint ok),
and `volec same-output` of the new compiler against the one built before
the change: 32,760 compilations, 7,401 of them differing only in the
compiler's own path in `try:` lines (each compared again with OLD's path
replaced: 0 differ).

The other checks: `tools/premerge.sh`: `premerge: ok`;
`tests/affected.sh`: plan 2584 of 2765 cases, -O0 3511 passed and 70
xfail, -O2 1138 passed and 38 xfail, abi and fuzz pass; `bootstrap/gate.sh
--only compile-cost`: hello 80.2 M 0.98x, std 1020.3 M 1.00x, check
4057.7 M 1.00x against 0.25.3.

**The pilot** (a different shape: one idiom, one module, the migration's
mechanics): tools/fixunsafe.vl's IntVecs (a static, five locals, four
parameters) as `Vec<i64, Comp>`, by

```
volec rewrite '$v.data[$i]' '$v[$i]' --where '$v: IntVec' --in crate::tools::fixunsafe --no-check
volec rewrite '$v.count' '$v.len()' --where '$v: IntVec' --in crate::tools::fixunsafe --no-check
volec rewrite 'IntVec { data: 0 as *i64, count: 0, cap: 0 }' 'Vec::new_in(Comp {})' --in crate::tools::fixunsafe --no-check
volec edit patch compiler/src/tools/fixunsafe.vl --old ': IntVec' --new ': Vec<i64, Comp>' --all --no-check   (and 'inout IntVec', the use line)
volec fix --suggested                                  (the Comp import)
volec edit patch ... --old 'var ranges = Vec::new_in' --new 'var ranges: Vec<i64, Comp> = Vec::new_in'  (x5: a local's T is not inferred from its pushes)
volec rewrite '$v.count' '$v.len()' --where '$v: Vec<i64, Comp>' --in crate::tools::fixunsafe   (4 sites nested in the first rewrite's)
volec fix --only unneeded-unsafe --in crate::tools::fixunsafe
```

The file's raw `index` operations went from 37 to 0 and SITES's
static-index ones with them; 2 of its 12 blocks became unneeded and went;
the other 10 index SRC, NODES, FILES and DEFS (tables: step 4). What the
pilot taught the plan: the typed rewrites carry the work, but a type
change cannot be one checked edit (each rewrite breaks what the next
reads, so `--no-check` until the last; `refactor --script` refuses a
`rewrite --text` line), a Vec local needs its type written, and in a
module that also reads tables, an IntVec step alone frees little: tables
first.
