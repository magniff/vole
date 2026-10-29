# Feedback: tables255, the compiler's hot tables to `Vec<T, Comp>` (modernization step 4)

2026-10-29, release 0.25.5. Converted NODES, SRC, TYPES, SYMS, DEFS and
FILES (one commit each, about 300 files touched, 1,036 unsafe sites
gone: 4,489 to 3,509 after the merges); two codegen fixes for what a
Vec index costs (middle/lower/expr.vl, back/isel/mod.vl); `refactor
table` refuses an index that may grow the table and takes a rollback as
a truncate; `fix --only unneeded-justified`. FNS and TOKS left for the
compile-cost limit.

## Verdict

`refactor table` and `fix --only unneeded-unsafe` did almost all of the
work: a table is a 10 to 50 second run, and same-output proved each one.
The time went to measuring (a 1.03x limit inside a 1% to 3% noise) and
to the one real finding: a Vec index reads its header before its index,
which the raw tables hid and which is a use after free in safe code for
a local Vec.

## What worked

- `volec refactor table NODES`: 38 files, 1 push, 107 len()s, 1
  reserve() in 16 s; TYPES 10 s, FNS 23 s, SYMS 3 s dry. After edit255
  merged, dry runs in scratch copies (`--root DIR/compiler/src/main.vl`)
  never disturbed the tree.
- `volec fix --only unneeded-unsafe`: 506 blocks after NODES in 1 s,
  every edit checked.
- `bootstrap/bootstrap.sh --dev --no-suite`: 10 to 20 s, fixpoint each
  time; it caught the NODES index bug on the first build
  (`front/own/drops.vl:1405:16: index out of bounds: index 1256772,
  length 1256772`), the check message naming the line exactly.
- `volec same-output OLD -j 6`: 32,940 compilations in about 20 minutes;
  after edit255 merged one line, `identical 32940 compilations`.
- `--emit-ir` and `-S` with `#[inline(never)]` on a 40-line program: they
  showed the `sub x, 0` and the two `ldr` in a minute.
- `--time-passes`: which phases a bigger source costs (inlining +33%,
  loop passes +21%).
- `tests/affected.sh -c COPY`: running the plan on a copy of the
  compiler let me rebuild target/volec meanwhile (plan 2540 of 2783, ok).
- The check hook after each `edit patch`; `edit patch --all` for
  repeated lines; `edit insert --after NAME`.

## What cost time, ranked

### 1. A Vec index evaluates its header before its index
`NODES[n] = NODES[t_node(..)]` failed the bounds check: `v[i]` lowers to
`v.as_slice()[i]` with the slice taken first. A local
`v[grow(&v)]` (grow pushing) compiled, ran, and `--check-alloc` said
`use after free: block #3 (128 bytes), allocated at uaf3.vl:11:9, freed
at uaf3.vl:3:9`. Not a language change I could make in 0.25.5; I made
the tool refuse such indexes for tables (2 in NODES, 9 in SYMS, all
hoisted). About 1 hour with the tool change. What would fix it: the
index evaluated before the base's view is taken (as Swift does), or the
exclusivity check refusing an argument that writes what the access reads.

### 2. Measuring a 1.03x limit
`check`'s instructions move by 1% between runs of the same binary
(0.25.4: fewest 4,432 to 4,570 M across my sessions), and by 3% at a
load of 40: the gate's 3 runs read `check 4720.2 M 1.05x` where 9 runs
read 1.03x. I wrote an interleaved min/median script and compared
compilers in pairs on one copy of the source. About 2 hours of runs. A
`check` count that does not depend on the machine (or a limit with the
noise stated) would have saved most.

### 3. Finding the cost of NODES
NODES alone: check 1.04x. The IR of a static Vec read showed `sub v47,
v46` (len - 0, typed u64 from an i64: instcombine's `x - 0` fold only
replaces same-typed values, `replace_same_type`) and `ldr` + `ldr` (isel's
pair_accesses wanted equal types). Two small changes, 1.02x to 1.03x. 1
hour. The -O2 self-compile grew 46.2 G to 58.0 G instructions with
NODES (the compiler's speed did not change): 8,600 inlined as_slice
calls and failure blocks to compile. Not fixed: it needs lowering a Vec
index without the call, or shared failure blocks.

### 4. SRC is not a triple
SRC is a Buf's bytes, set in three places; refactor table needs X and
X_COUNT. By hand as a `[u8]` view: 8 errors from the checker, each an
`expected '*u8', got '[u8]'` at a lexer call taking the raw pointer;
fmt's read_pieces was refused with `own.escape: 'base.SRC' would hold a
view of 'text'` and needed the same raw-pointer slice its FT uses.
30 minutes.

### 5. A merge that conflicted under my script
My convert script ran `git merge release-0.25.5` and went on to convert
SYMS on top of a conflicted merge (docs/releases.md and a transcript).
`git reset --hard`, merge again, resolve, rebuild. 15 minutes. My
script's fault (no exit on a failed merge).

### 6. `query refs` of a busy name
`volec query refs crate::base::SRC` (939 uses) prints counts per file,
also with `--in crate::front` and `--budget 200000`; listing the uses
that are not `SRC[` meant a dry run of refactor table instead.
(tools/agent-feedback)

### 7. `fix --help` at most 15 lines
Adding `unneeded-justified` to the help made it 16 lines and the guide
suite's help check failed (`FAIL help-fix`); the text had to be folded
into the line before. The limit is only in tests/guide/run.sh.

### 8. Reading compiler files over 300 lines
`sed -n 1068,1300p table.vl` was blocked (233 lines); the Read tool
or two ranges did it. Fine, one turn.

## Never used

- `rewrite`, `refactor --script`: the tables needed refactor table or a
  handful of `edit patch`es.
- `probe`, `reduce`: the failures named their line.
- `tests/affected.sh --linux`: the plan says platform-relevant; not run
  (colima not checked), left to the integrator's gate row.

## Fix list, in order

1. [lang] `v[f()]`: evaluate the index before taking the base's view (or
   refuse it in the exclusivity check); today `v[grow(&v)]` on a local
   Vec is a use after free in safe code.
2. [build] Lower a Vec's `v[i]` without the as_slice call, and share a
   function's bounds-failure blocks: the -O2 self-compile grew 28%
   (46.2 G to 60.3 G) with six tables.
3. [test] compile-cost: a count stable under load (the fewest of more
   runs, or user-mode instructions only), and the noise printed with the
   ratio.
4. [tool:refactor] refactor table for a table that is a view of a buffer
   (SRC), and the comments naming X_COUNT (still left).
5. [tool:query] `query refs NAME --lines` (every use line, no per-file
   summary) for scripts.
6. [build] instcombine's `x - 0` and `x + 0` across signedness (i64 and
   u64 of one size), not only in lower_slicing.
7. [test] tests/guide/run.sh's 15-line `--help` limit named in
   docs/refactor.md or the help source.
