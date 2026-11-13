# How to add an X

Recipes for the changes made again and again (0.17): the files, the
commands in order, the test, the docs. `volec guide how TASK` prints
one; `volec query examples KIND` prints the items to start from, and
`volec query similar NAME` the items like one you name (copy the
nearest). In the vole repository (commands from its root):

- `add-std-fn`: a std function or method
- `add-std-module`: a std module (a file of compiler/std)
- `add-peephole`: an instruction-combining or e-graph rule
- `add-pass`: an optimization pass
- `add-diagnostic`: a compiler error, or a tool diagnostic with a code
- `add-test`: a test case
- `add-subcommand`: a `volec` command, or a `query` command
- `add-guide-text`: a paragraph or an example in the guide

In a program of your own:

- `add-module`: a module (a file) to a program

## add-std-fn

To add a std function or method.

std is `compiler/std/`: the module `std` (`std.vl`) and its modules
(`std::fmt` in `fmt.vl`, `std::collections::hash_map` in
`collections/hash_map.vl`); `compiler/std/embed.sh` builds it into the
compiler (`compiler/src/front/stdsrc_rust.vl`).

1. Find where it goes: `volec query similar str::trim` (or
   `Vec::swap`) prints its neighbours, with their files
   (`compiler/std/str.vl:333`); `volec query examples std-fn`.
2. Add it in its file, next to its kin, with an editor (std is one text
   to the compiler, `<std>`: `volec edit` does not write its files),
   then `volec fmt FILE`. A function that allocates takes its
   allocator: a constructor or an `_in` function with the allocator
   last (`Vec::new_in(a)`, `s.to_vec_in(a)`). `volec check` of any
   program then reads the edited files (`note check.std-files`), every
   function of std.
3. `compiler/std/embed.sh` (the commit hook runs it too).
4. A test: `tests/run/std2_NAME.vl` with `// EXPECT:` lines (edge
   cases: empty, too long, at the ends); see `add-test`.
5. The guide: a sentence and a `vole` example with its `out` block in
   `compiler/guide/std.md` (the API listing at its end is generated);
   `compiler/guide/embed.sh`.
6. `bootstrap/bootstrap.sh --dev --no-suite` (the compiler with the new
   std), then `tests/run.sh std2_NAME guide`, `tests/run.sh -O 0
   std2_NAME`; before reporting, `tests/affected.sh`.

## add-std-module

To add a std module (a file of `compiler/std`).

1. The file, `compiler/std/NAME.vl` (or `NAME/mod.vl`; a child of
   `std::a` in `a/`), and its `mod NAME;` (or `pub mod NAME;`) line in
   the parent's file: embed.sh finds the modules by those lines.
2. A build reads only the units of std a program reaches (the index
   embed.sh makes with the compiler, `std2_units`); `volec check` reads
   all of std. So check with a build too: `bootstrap/bootstrap.sh --dev
   --no-suite`, then `target/volec PROG.vl -o x` of a program that uses
   the module. A build made again with std whole says so (`tests/run.sh`
   counts them, `lazy std: N build(s)`; `VOLE_STD2_NORERUN=1` shows why).
3. Tests and docs as for `add-std-fn`. `volec guide std`'s index has a
   size limit (`tests/run.sh guide`: guide-std-index); a module with its
   own topic, or one programs seldom name, leaves the index
   (compiler/src/guide/stdapi.vl: `index_hides`).
4. The transcripts: `tests/run.sh query refactor walkthrough lsp stdpos`.
   They compare std's positions, counts and list of modules normalized
   (tests/stdpos.awk), so only one about std itself (`## exact-std`) or
   one whose output names the new items fails; rewrite it with its
   runner's `-u` (`tests/query/run.sh -u NAME`), which keeps the std
   numbers of a line that did not change otherwise, and read the diff.

## add-peephole

To add an instruction-combining or e-graph rule.

An algebraic identity on constants and operations (`(x + c1) + c2`):
a line of `crate::middle::egraph::rule_text`, such as
`(neg (neg x)) => x` or `(mul x c1) if (pow2 c1) => (shl x (log2 c1))`;
the array's length and `RULE_COUNT` grow by one, in the same edit
(`volec edit patch rule_text --pairs FILE` with a `@@ RULE_COUNT`
block for the second target, or `volec edit apply`). `volec --check-rules` tests every rule on
random values (the suite runs it).

Anything else (a select, a negated comparison, an address): a function
`combine_X(cx: &mut FnCtx, v: i64, pcx: &Ctx<Comp>) -> bool` in
`compiler/src/middle/fold/mod.vl`,
section "Instruction combining", called from `combine` on the
instruction's op; true when it changed `v` (in place, or with
`replace_same_type`, `make_const`, `op_before`). Templates: `volec
query examples peephole`.

Test: `tests/run/opt_NAME.vl`, a program with `// EXPECT:` and
`// CHECK:` / `// CHECK-NOT:` lines on the optimized IR (`--emit-ir`;
`tests/run/opt_egraph.vl`); `tests/run.sh opt_` at `-O 0`, `1`, `2`.

## add-pass

To add an optimization pass.

1. `volec edit new-file compiler/src/middle/NAME.vl < text` (adds
   the `mod` line): `pub fn NAME(cx: &mut FnCtx, fi: i64, pcx:
   &Ctx<Comp>) -> bool`, true when it changed function `fi`. Templates: `volec query examples pass`
   (`elide_copies`, `thread_tags`).
2. Call it in `compiler/src/middle/opt.vl`: in `simplify_function`
   (scalar, -O1 and -O2) as `if round == 0 && NAME(cx, fi, pcx) {
   verify_func(cx, fi, c"NAME", pcx); }`, or in `optimize_loops` (-O2) as
   `if NAME(cx, fi, pcx) { changed = true; light_cleanup(cx, fi, pcx); }`. `verify_func` checks the IR under
   `--verify-ir` and prints it under `--print-after-all`.
3. Test: `tests/run/opt_NAME.vl` with `// CHECK:` lines (see
   `add-peephole`); `tests/run.sh opt_`; `tests/fuzz/run.sh` (random
   programs at every level); `--time-passes` for its compile time.
   An alias fact (two accesses that never overlap) also needs a case
   that breaks if the fact is wrong: a write through another base (a
   pointer kept in a static, another Vec's buffer) between the two
   accesses, with no call between them (a call, or a write through the
   same base, is handled before the fact is asked, so such a case passes
   with a wrong fact too); `// FLAGS: --check-alloc` makes a stale read
   fault. Show that it can fail: make the fact always say "apart",
   `bootstrap/bootstrap.sh --dev --no-suite`, copy target/volec aside,
   `volec undo`, and run `tests/run.sh -c MUTANT -n NAME`: it must fail.
4. Docs: the module table of `compiler/src/middle/README.md`,
   `docs/optimizer.md`. Before reporting: `tests/affected.sh` (and
   `bench/run.sh`: no program may get slower).

## add-diagnostic

To add a compiler error, or a tool diagnostic with a code.

A compiler error (`error[type error] ... | help: ...`), where the
checker finds it: `err_begin(pos, pcx); err_str(c"...", pcx);
err_sym(name, pcx); err_help(c"try ...", pcx); err_end(pcx);`
(`err_end_soft(pcx)` goes on checking; `pcx` is the compiler's context,
a parameter of every function that reports).
Templates: `volec query examples diagnostic`. Test:
`tests/run/err_NAME.vl` with `// ERROR: text` lines, the help line
too (`// ERROR: help: ...`).

A tool diagnostic (`error edit.not-source: ...` then `try:` lines):
`let d = diag(c"error", c"tool.code", tcx); buf_str(d, c"...\n");` then
`try_end(try_begin(c"cmd", name, true, tcx, pcx))`: a command that runs as it is
written. Then its `explain` entry: an `Explain { code, severity,
means, fix, example }` in `crate::tools::explain::tools_table::TOOLS_TABLE`
(or `refactor_table`), `TOOLS_COUNT` and the array's length one more,
in one `edit apply`; the Diagnostics table of `docs/query.md` or
`docs/refactor.md`. `tests/refactor/run.sh` fails on a code without an
entry (a new tool's prefix, `run.`, goes into its list of prefixes,
the `grep -rhoE` above `self_explain`, or its entries read as `not a
code`). The prefixes are the
`c"(query|edit|...|run)\.` list of that `grep -rhoE` in
`tests/refactor/run.sh`. Test: a transcript (`tests/query/NAME.q`,
`tests/refactor/NAME.t`).

A `volec --help` row or a `volec CMD --help` text: 15 lines at most
each (`tests/run.sh guide`, its `help-CMD` checks); `volec --help` has
15 now, so a new row merges with another.

## add-test

To add a test case.

- A program: `tests/run/CATEGORY_NAME.vl` (the category is the name
  up to its first `_`: `std_`, `opt_`, `err_`...), or
  `tests/run/NAME/main.vl` for several modules. Directives in `//`
  comments: `EXPECT:` (stdout, a line each; holes `{num}`, `{int}`,
  `{..}` for what varies), `EXPECT-PPM:` (an image; `volec guide
  testing`), `STDIN:`, `ARGS:`,
  `EXIT:`, `STDERR:`, `ERROR:` (compiling fails with that message),
  `CHECK:` / `CHECK-NOT:` (the IR), `FLAGS:`; the header of
  `tests/run.sh` lists them all. Cases compile with `--deny-warnings`.
- Run it: `tests/run.sh NAME` (cases whose name holds NAME), with
  `-O 0` and `-O 1` too; one case alone: `tests/run.sh -n NAME`.
- A tool: a transcript, `$ ARGS` lines and their output:
  `tests/query/NAME.q` (on `tests/query/NAME/main.vl`),
  `tests/refactor/NAME.t` (in a copy of `tests/refactor/NAME/`; `%`
  lines run shell commands); `tests/query/run.sh -u` writes what the
  commands print now (read the diff before keeping it).
- Templates: `volec query examples test`.

## add-subcommand

To add a volec command, or a query command.

A command (`volec NAME ...`): its arguments, `pub fn NAME_leaf(gpa:
Gpa) -> Leaf<'static, Gpa>` (a table of `flag`s and `option`s,
`cli::line`), and `pub fn run_NAME(c: &Call<'_, Gpa>, tcx: &mut
Tcx<Comp>, pcx: &mut Ctx<Comp>) -> i64` reading `c.evs` (its arguments
in the line's order) or `c.m` (their Matches); diagnostics with `diag`,
written with `write_diags(tcx)` before it returns. Its name in `tops` and its leaf
in `leaf_of` (`compiler/src/cli/tree.vl`, volec's Command tree), and its
line in `run_call` (`compiler/src/tools/commands.vl`): `if name ==
"NAME" { return run_NAME(c, tcx, pcx); }` (`batch` runs it too). Its `--help`: a
`Help { cmd: "NAME", text: "..." }` row in `compiler/src/tools/help.vl`
(15 lines at most; `HELP_COUNT` and the array's length one more), and
the command in the list `tests/guide/run.sh` checks `--help` for.
Templates: `volec query examples subcommand` (`run_lint`).

A query (`volec query NAME ...`): its name in `command_name`
(`N_COMMANDS` one more), its branch in `answer`, its line in
`put_usage` and in the `query` row of the help table; `volec query
examples query-command`.

Docs: `docs/query.md` or `docs/refactor.md`, the tables of
`compiler/guide/tools.md` (then `compiler/guide/embed.sh`), the module
table of `compiler/src/tools/README.md`. Test: a transcript (`add-test`).

## add-guide-text

To add a paragraph or an example in the guide.

The guide is `compiler/guide/TOPIC.md` (the topics and their order:
`compiler/guide/topics.txt`). An example is a `vole` block, then an
`out` block with what it prints (an `in` block before it: its stdin; an
`err` block: it must fail to compile); each is compiled and run.
`tests/guide/run.sh -f compiler/guide/TOPIC.md` checks one topic as you
write it; then `compiler/guide/embed.sh`, `bootstrap/bootstrap.sh --dev
--no-suite` and `tests/run.sh guide`. The core topic has a budget (the test says).

## add-module

To add a module (a file) to a program.

1. `volec edit new-file shapes.vl < text` writes the file and adds
   `mod shapes;` to its parent (`main.vl`); or `volec refactor
   new-module crate::shapes` for an empty one.
2. Items another module uses are `pub`; there they are named
   `crate::shapes::area` or imported: `use crate::shapes::{Shape,
   area};` (`volec fix --only imports` adds the lines a check asks
   for).
3. Items that should move there: `volec refactor move area Shape --to
   crate::shapes` (their uses and imports follow).
4. `volec check`; build with the root, `volec main.vl -o prog`.

`volec guide modules` has the rules (paths, `pub`, `use`).
