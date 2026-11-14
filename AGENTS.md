# Working on vole (for agents)

Vole's compiler is written in vole: `compiler/src/`, a module tree
under `main.vl`. Releases, the bootstrap chain and the gate are in
[docs/releases.md](docs/releases.md) and [docs/roadmap.md](docs/roadmap.md);
the language in [docs/grammar.md](docs/grammar.md).

**First, in a new worktree, run `bootstrap/bootstrap.sh --dev
--no-suite`** (seconds): before it there is no compiler here. It leaves
two: `target/volec`, your build of this tree (check, build and test
with it), and `target/tools/volec`, the installed, tested one (query and
edit with it while you change the compiler: it works when your build
does not). For an example or a test alone either one does.

**One language, with Rust's surface** (`target/volec guide rust`: where
vole differs from Rust). **New to vole? Run `target/volec guide`**
(about 10k bytes); before a construct you are unsure of, `guide --find
WORDS` or `guide TOPIC#SECTION` (`guide --list`; send `--full` and `std
--whole` to a file). A static of compiler/src is read and written only
through its accessors at its file's end (`get_x()`, `set_x(v)`), whose
UNSAFE:/SAFETY: lines say which functions and threads write and read
it: a change to who does keeps them true.

## Read source through the compiler

The tools answer questions about a program and make checked edits.
**For an unfamiliar item, `target/volec query context NAME` first**: its
source, what it calls and its callers, in one call.

| you want | run |
|---|---|
| an item's source, callers, what it calls | `target/volec query context NAME`; `query show NAME` (or a FILE); `query refs NAME` (`--count`, `--in FILE`) |
| change a few lines, checked | `target/volec edit patch NAME --old 'TEXT' --new 'TEXT'` (`--all`; a FILE too: a `.wgsl`, a text file git tracks); by position: `--at FILE:LINE --old A --new B`, many: `--from LIST` (`FILE:LINE<TAB>OLD<TAB>NEW` lines, one check) |
| replace, add, remove an item | `target/volec edit replace\|insert\|delete NAME` (`< text`) |
| an unsafe site's comments | `target/volec edit justify FILE:LINE --unsafe 'WHY' --safety 'WHY SOUND'` |
| rename, move, change a signature, field or variant everywhere | `target/volec refactor rename\|move\|signature\|field\|variant ...`; a predicate now constant: `refactor fold FN --as true\|false` |
| an idiom everywhere, typed | `target/volec rewrite 'OLD' 'NEW' --where '$v: T' --dry-run` (`--in FILE\|MODULE\|std`, `--not-in ITEM`; a list: `--from FILE`, one check) |
| imports, `pub`, unneeded `unsafe`; the errors' exact fixes | `target/volec fix`; `fix --suggested` (`--dry-run`, `--at FILE:LINE`) instead of sed |
| std: search, change, check every body | `query grep TEXT --std` (`--in compiler/std/FILE.vl`), `edit patch compiler/std/FILE.vl ...` then `sh compiler/std/embed.sh`, `target/volec check --std` (seconds), `tools/std-effects-diff.sh [BASE]` |
| a bug: where it fails, the values at a line | `target/volec guide debug` (`test`, `probe FILE:LINE EXPR... -- ARGS`, `reduce`) |
| an example, GPU or not | `target/volec guide gpu-workflow`; in its directory `check`, `query`, `edit` mean that program (else `--root examples/X/main.vl`) |
| what a change did in the optimizer, and its cost | `target/volec build --help`, `tools/perf-diff.sh A B FILE.vl`, `tools/perf-experiment.sh -b BASELINE`, `bench/run.sh --instructions -p BASELINE`, `query asm NAME` |
| build and test what a change touches | `bootstrap/bootstrap.sh --dev --no-suite`, `tests/run.sh FILTER...`, `tests/affected.sh` (below) |

The rest: `target/volec --help`, `CMD --help`, `guide tools`, `explain
CODE` on any error, `guide how` (a std function, a pass, a diagnostic),
[docs/query.md](docs/query.md#every-command-at-a-glance-for-agents),
[docs/refactor.md](docs/refactor.md). A problem prints as one line,
`error CODE: message`, then `try:` lines to run as they are.

**Hooks** (Claude Code's, tools/agent-hooks): a shell read or rewrite of
compiler/src or compiler/std beyond a 200-line range is blocked with
the query or edit to use (override with a trailing `# no-query: why` or
`# no-tool: why`); every edit is checked and what changed is added to
its result (nothing added: no change; do not run `check` again). **Under
another harness** nothing does this: read with `target/tools/volec
query`, run `target/volec check --changed` after your edits (every
program you touched, checked and its layout compared) and `volec fmt
FILE` on what you wrote. When a tool falls short: `tools/agent-feedback
"TOOL" "what"` (`--find WORDS` first).

## The inner loop

Every suite run costs every agent on the machine: test what a change
touches. **An agent runs tiers 1 and 2 only, never the whole suite or a
gate unless its task says so**:

1. **While working (agent):** `bootstrap/bootstrap.sh --dev --no-suite`
   (under 20 s; the fixpoint checked), then the cases the change
   concerns: `tests/run.sh -j 2 FILTER...` (options before the filters;
   `-n NAME` exactly; `-l` lists; a suite's own by name:
   `refactor:NAME`, `query:NAME`, `lsp:`, `fmt:`; `--cases-only`;
   `--bless NAME` rewrites `// ERROR:` positions that only moved). Its
   first line is the plan: read it before waiting.
2. **Before reporting (agent):** `tools/premerge.sh` (prints `premerge:
   ok`) and `tests/affected.sh` (the tests tests/affected.map names for
   what changed since the base, at -O0 and -O2; `--list`: the plan and
   why; a plan over 600 cases: `--narrow`). `linux: platform-relevant`
   in the plan: `tests/affected.sh --linux` too (colima).
3. **Per merge batch (integrator):** one `tests/run.sh`, one
   `bootstrap/gate.sh --quick`, then `bootstrap/bootstrap.sh --dev`,
   which installs a tested `target/tools/volec`.
4. **A release:** `bootstrap/gate.sh --release`, then `--only bench` on
   an idle machine (docs/releases.md, "The gate").

A test that fails in your plan is yours until shown otherwise: rerun it
alone (`tests/run.sh -n NAME`) before calling it load or inherited.

## Before you commit, before a merge

- **Start from green:** branch from the integration branch (`release-X`);
  if your base fails tests, say which before your own work.
- **The commit hook** (`tools/git-hooks/setup.sh` once per clone) refuses
  an `unsafe` without its comments, an unformatted `.vl`, an example case
  whose SOURCE is missing, and stages `compiler/src/front/stdsrc.vl` for
  a std change. It runs under any harness.
- **A change to an example** needs its `tests/examples/*.test` case
  (`// REQUIRES: metal`, `// LINK:` for std::gpu/std::window) and
  `tests/run.sh example_NAME example_build`.
- **Report what was asked, checkably:** each "Done means" item with the
  command or count that shows it; premerge's result and affected.sh's
  plan line (`plan: N of M cases; ...`) and result.
- **Mind the machine:** a few agents build and test at once; one gate at
  a time (`gate.sh` waits for another, `--no-wait` fails). Timings under
  load are not evidence: count instructions.

## Conventions

- Commit as `git -c user.name=magniff -c user.email=tinysnippets@gmail.com
  commit -F msgfile`, the message in a file; no attribution trailers.
- A release's compiler is built by the previous release: features new in
  release N are used in `compiler/src` only from N+1.
- No undefined behaviour, no wildcard imports; compile speed is measured
  every release.
- `unsafe` must be justified. Try the safe way first (std's APIs, `Vec`,
  slices, `str`, a new safe function); use `unsafe` only when that is
  impossible, around the one operation that needs it, with a comment
  right above it (an `unsafe fn` and an `extern` block too):

  ```
  // UNSAFE: why this cannot be safe (C or the OS, allocator internals, a measured hot path)
  // SAFETY: why it is sound (bounds, lifetimes, aliasing, initialization, and what guarantees them)
  ```

  Never add `unsafe` (or let `volec fix` add it) to silence an error. In
  compiler/src and std a site without both comments, and in compiler/src
  a block with nothing unsafe inside, is an error (`volec check
  --deny=unsafe`, `tools/premerge.sh`, `tests/unsafe_audit.sh`); `volec
  fix --only unneeded-unsafe` removes an unneeded block.
