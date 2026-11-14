# Tool gaps in 0.30: the shortfalls of 0.29 and 0.30, grouped

The last 60 entries of `tools/agent-feedback --list` (2026-11-13 to
2026-11-14), after the first batch of 0.30, which took most of 0.29's
tool diaries. Each shortfall is listed once, even if it was reported
several times. The fixed ones say where they were fixed. The open ones
are sorted by cost (S: an hour or less, M: a day, L: more) for the next
round.

## Fixed

| shortfall | reported by | fixed |
|---|---|---|
| tests/run.sh: a case with `FLAGS: --check-alloc` passed while leaking unless it was a `std_` case | drop30 | 0.30, this list's commit: any case whose own FLAGS have `--check-alloc` fails on a leak (212 such cases: 0 fail) |
| `edit apply FILE`: a blocks FILE ending in `.vl` outside the program was taken for the root, and its own text was edited | t30edit, tailbase, find | 0.30, this list's commit: without `--root` the program is the default one (`tests/refactor/multi.t`) |
| `check --max-errors=3` from the tools' cache printed every cached error | t30edit | not reproducible on 0.30's tree: a check without a limit followed by one with `--max-errors=3` prints three errors and the stop line |
| tests/affected.sh: a `back/dwarf.vl` change planned 1194 cases, none built with `-g` | gfix290 | 0.30: the rule runs `debug_lines`, `tests/debug.sh`, `objcheck.sh debug_` |
| no fold of a constant predicate | find | 0.30: `refactor fold FN --as true\|false` (e068829e1) |
| `query grep` cannot search std's files; std hits are reported inside stdsrc.vl's string | finb, drop30 | 0.30: `--std`, `--in compiler/std/FILE.vl` (f16d24148) |
| after a std edit only the instances compiler/src uses are effect-checked | finb | 0.30: `check --std` (f16d24148); the gaps in it are listed below |
| no command puts a justification above a site by FILE:LINE; unneeded-and-justified blocks are not listed | tailbase | 0.30: `edit justify`; `fix --only unneeded-justified` |
| no `-u` for the book; `tests/refactor/run.sh -u` had no `-j` and no text filter | own290, fc290 | 0.30: `tests/book/run.sh -u`; `-u --grep TEXT`, `-j` |
| a std item changed: which transcripts print it | finb | 0.30: tests/affected.sh adds the transcripts that name a changed std item |
| `fix --suggested` 50 errors a run; a removed field's did-you-mean to another field | tailbase, tailcache | 0.30: every error; no rename for a removed field (62aaccd3f) |
| an import of a prelude name: no warning, no fix | own290 | 0.30: `use.redundant`, `fix --only redundant` |
| rewrite: `f($x)` does not match `crate::m::f($x)`; `(&mut x).m()`; parentheses left; `--text` stops at a generated file | tailbase, finb, find | 0.30 (t30rw): holes, parentheses, `--from`, `--not-in`; check each against its entry when it is next used |
| why a Vec-header summary is unknown; no `--vec-stats` for all functions | finb, s30self | 0.30: the reason on `--vec-stats=FN` (01937d08e); a whole-program tally is still open (below) |
| a FILTER of `-n` that selects nothing is silent | t30run | 0.30: a warning |
| the check cache kept the error of a program read with an edited std | t30std | 0.30 (5314ead52) |

## Open, by cost

### S: an hour or less

- **`volec batch`: a quoted word that starts with `<` is read as stdin**
  (`query items '<std>'`: `cannot read 'std>'`). The batch line's lexer
  should take `<` as a redirect only when it is unquoted. (h30tools)
- **query-first hook: its `try the whole line` names the volec of the
  session's start directory, not of the tree the command works in.**
  (h30tools)
- **tests/run.sh read while it is edited:** an edit of tests/run.sh
  during a run made the running shell fail with a syntax error at the
  end, and the tally was lost. The runner could copy itself to its WORK
  and exec the copy. (h30tools)
- **query grep: `( | )` in a TEXT that matches nothing:** say that it
  was searched as text (0.30 has `--regex` groups). Also say so for an
  escaped `\.` that finds nothing. (t30rw, s30self)
- **query grep on a file that is not vole (README.md):** it prints
  `0 hits`. It should refuse the path or search it as text. (vole)
- **guide embed.sh:** print the core guide's size against its 10240-byte
  budget. (fc290)
- **`check`'s help for an unknown `Mutex`:** it gives the old "no
  interior mutability ... `*T`" help. It should be `use std::sync::Mutex`.
  (tailmid)
- **hook query-first: a blocked line with a heredoc is echoed whole,
  twice.** It should be cut to its first lines. (t30rw, t30std)
- **`--print-checks` does not count a vector load's range check**
  (`v16u8::load(s, i)`). (s30text)

### M: a day

- **check --std's blind spots:** a pub fn of a gated module (std::unicode)
  whose body breaks its `#[effects]`, and a private fn passing `&[u8;
  19]` to `v16u8::load`, both pass. A std edit that uses a method the
  lazy std has not read passes too, and then makes every program build
  twice (`rerun_eager`; only tests/run.sh's last line says so). (s30text)
- **The builtin integer methods carry `diverge`** (their text is a
  loop: `u64::trailing_zeros`). `query show u64::trailing_zeros` finds
  no definition. (s30text)
- **The back end's internal errors do not name the function being
  compiled;** `--print-regalloc` prints a function only after its
  allocation. (s30text)
- **edit replace/insert of a std item by name** (`edit.not-source`):
  only `edit patch compiler/std/FILE.vl` works. (s30iter, s30text)
- **query refs: a write through a table's element
  (`pcx.types[t].a = x`) is listed as a read.** (s30self)
- **query refs (refs_of) accumulates its positions across calls in one
  process.** (t30rw)
- **check-after-edit hook:** it removes an import as unused while the
  Edits that use it are still arriving; it checks a compiler/std file as
  a program root. (t30rw)
- **edit insert: two inserts that need each other are each refused,**
  and the `try:` names `--no-check`, not `edit apply` with two blocks.
  (t30edit)
- **refactor extract-function refuses a function's tail with returns**
  (refactor.escapes); the call could be the tail expression. (t30rw)
- **premerge's unsafe row with uncommitted changes:** it falls back to a
  word heuristic and fails on help text that holds the word unsafe.
  (t30std)
- **query (std tree):** a query reads the built-in std though
  VOLE_STD_TREE names edited files (check, fix and query unsafe read
  them). (t30std)
- **perf-experiment: no baseline that is the branch's base built with
  today's tools.** (s30iter)
- **bench/run.sh --instructions:** instructions and time disagreed in
  sign once (fannkuch). It should print alternating wall times beside
  them. (s30iter)
- **--vec-stats: one function a build;** there is no `all` or module form
  to tally the reasons. (s30self)
- **query grep: only .vl files.** A program's WGSL, scripts and tsv
  files should be searchable per program. (vole)
- **tests/affected.sh counts stale untracked files as the branch's.**
  0.30 names them in the plan; still to do: leave out ignored scratch.
  (vole)

### L: more

- **batch saves nothing for whole-program queries:** each command forks
  and restores the program, then does its work anew. Measured again in
  0.30: the query suite's roundtrip check, 174 queries, took 68 s
  through one batch against 71 s one process each. Sharing the work
  would need a query server (the LSP's) for the tools. (t30run, h30tools)
- **lazy std: a u64 result of a C-imported function printed with `{}`
  makes the build redo with std whole.** (finc)
- **query unsafe std: blocks of std's generic functions that no program
  instantiates are listed as unneeded.** 0.30 made this exact for the
  audit (3b8826e63); check it against fina's 18 and 25 sites.
- **tools/rustc-twin's prelude.rs lacks `Vec::from_elem_in`.** (drop30;
  small, but the twin's prelude is maintained by hand)

## Kept here from 0.30's own work

- **The runners' pinned orders and counts** (item 3 of h30tools): see
  docs/releases.md's 0.30 notes when they are written. In short: a
  CHECK or ASM line pins an order. An unordered group, FileCheck's
  CHECK-DAG and ASM-DAG, would let a test pin "these instructions"
  without their schedule (`arch_a64_dot` failed only on order). EXPECT
  and STDERR are oracles: they need no bless command, since a change to
  them must be read. The perf suite's `loops.want` and `headers.want`
  pin the vectorizer's decisions on the program's own loops: also read,
  not blessed.
