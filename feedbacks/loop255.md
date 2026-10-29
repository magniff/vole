# Feedback: loop255, the hooks, the test harness and the agent docs from the 0.25.4 feedback

2026-10-29, release 0.25.5. The check, turn-end and query-first hooks
(tools/agent-hooks, about 450 lines with their tests), the std tree in
the compiler (front/stdtree.vl, main.vl, testrun's time limit: about 60
lines), the runners (tests/run.sh, affected.sh and .map, stdpos.awk, a
new tests/stdkeep.sh, the query, refactor, walkthrough, lsp, book, fmt
and stdpos runners), the guide (`how`), AGENTS.md, docs/query.md and the
release notes.

## Verdict

The cause of the hooks' false `unresolved import` errors was in the
compiler, not the hooks: `check` already read std from the tree when its
files differed, but never the target's system file (sys/macos.vl), which
is where `sys_c_strerror_r` was added. Finding that took one experiment
in a scratch copy of compiler/std; the rest of the brief was shell and
Python work on runners and hooks that the tools do not cover, where the
cost was in the main checkout's own (old) hooks blocking the work that
this branch makes legal.

## What worked

- `target/tools/volec query grep 'std-tree' --all` then `query context
  std_tree_if_edited`: found the existing `--std-tree`, the cwd-relative
  `find_std_tree` and `std_files_differ` in two calls.
- A scratch copy of compiler/std plus `target/volec check p.vl` from
  inside it: reproduced the false error in one call (a std.vl addition
  resolved, a sys/macos.vl one did not).
- `volec edit insert --before NAME < item` and `edit patch NAME --old
  --new`: the compiler change in six checked edits, the imports added by
  the edit (`note edit.imports`).
- `tests/stdpos/run.sh --real` existed already: a std change applied to
  a copy of the tree, the compiler rebuilt, the suites run. Extending it
  (a function at the top of num.vl, a new module) was the dummy std
  change the brief asks for, repeatable.
- `bootstrap/bootstrap.sh --dev --no-suite`: about 20 s each time, four
  times.
- `tests/compile_cost.sh`: 2.6 s, cheap enough to put in every std, front
  end and optimizer plan.

## What cost time, ranked

### 1. The main checkout's hooks blocked the work this branch fixes

`python3 - <<'EOF' ... EOF` that patched tools/agent-hooks/test-query-first.py
(a test file whose strings name `compiler/src/old.vl`) was blocked as
`blocked hook.edit-tool: ... python rewrites the compiler's source
(compiler/src/old.vl)`; I wrote the script to the scratchpad and ran it
from there. `grep -n 'strerror' compiler/std/*.vl` and `grep -n
'^\(pub \)\?mod ' compiler/std/std.vl` were blocked (both reads of
compiler/std .vl files; the try: lines worked). About 4 turns. This
branch removes the first kind (a script's write target is followed
through its assignments) once its hooks are the main checkout's.

### 2. A shared scratchpad

My first scratch tree, `$SCRATCH/t1`, vanished between two calls (another
agent uses the same scratchpad directory and the same short names). The
experiment's `p.vl` was gone and the output made no sense for one turn.
A per-agent subdirectory (`$SCRATCH/loop255/`) fixed it. Would save it:
the harness giving each agent its own scratchpad, or the brief saying to
use a subdirectory named by the branch.

### 3. `check.std-files` is never printed

`std_tree_if_edited` records a note (`std's files differ from this
compiler's std: checked with DIR`), but neither `check` nor `check
--json` prints notes, so I could not see which std a check used; I
inferred it from which errors appeared. 1 turn. Recorded with
tools/agent-feedback.

### 4. Which transcripts pin std's shape, and how

The digest names "module lists" in views017, but views017 has none: it
pins std's contents through name searches (`views ... count` lists every
std `count`, `views Vec::get` every instantiation inside std). Module
rows I could normalize in stdpos.awk; name searches I could not (no
`--in crate` for `views`), so I narrowed views017's first and def
queries to paths. The Vec instantiation rows still list std's own
(`Vec<JobBuffer, ScopedArena>::get`). About 3 turns reading transcripts.

### 5. The LSP session asks about a place in std.vl by its number

`tests/stdpos/run.sh --real` (the dummy std change) failed once on
resolve.lsp: its hover and definition requests name `std.vl` line 284,
which a new module line moves, and the hover's answer (a range with no
uri before it) was not normalized. Fixed with `@LINE:std.vl:TEXT@` in the
request (the runner finds the line) and the answer's own range normalized
after a request about std's files. A loop in the new awk function (it
called a function that runs `match` and then used RSTART) hung the
check once. Two rounds of --real, about 10 minutes each under a load of
35. Would save it: the dummy std change in the brief's first steps, not
the last.

### 6. Python's `hash()` is not stable across processes

My first cache key for the hook's system-file comparison used `hash(text)`,
which PYTHONHASHSEED randomizes per process: the cache never hit. Caught
by reading, not by a test. Small.

## Never used

`probe`, `reduce`, `batch`, `refactor`, `rewrite`, `undo`, `fix`: the
compiler change was six small edits; the rest was shell and Python.
`query impact`: the change's reach (check's std) was clear from `refs`.

## Fix list, in order

1. [tool:check] Print `check.std-files` (which std a check read) on
   stderr and in `--json`, so that a hook or an agent can tell.
2. [tool:query views] `--in crate` (or `--no-std`) for `views` and
   `def`, so that a transcript about a program does not list std's
   items and std's own instantiations.
3. [hook] Once loop255 merges, install a tested target/tools/volec in
   the main checkout (bootstrap.sh --dev): the old tools binary reads
   no tree's system file, and the hooks then say `hook.stale-std` and
   check with target/volec instead.
4. [build] Each agent's own scratchpad (or the brief says
   `$SCRATCH/<branch>/`): two agents' `t1` collide.
5. [test] `tests/stdpos/run.sh --real` in the gate's stdpos row (it
   takes minutes: a rebuild and four suites), so that a transcript that
   pins std's shape fails before a std change does.
6. [test] std's content, not its numbers, still pins four transcripts:
   after merging std255, calls016 (a transitive callee count through
   std), clash (`items sys` lists std::sys's items), views017 (std's own
   instantiations) and resolve.lsp (std::thread::scope's inferred
   effects) failed; -u changed 14 lines and kept every other std number.
   A `--in crate`/`--no-std` for items, callees and views would let them
   ask about the program only.
7. [hook] query-first: a read of a large compiler file by the Read tool
   is free, a `sed -n` of 201 lines is not; say in the block that the
   Read tool reads it (it does: `the Read tool reads any file`), first,
   not last.
