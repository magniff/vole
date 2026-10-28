# Working on vole (for agents)

Vole's compiler is written in vole: `compiler/src/`, a module tree
under `main.vl`. Releases, the bootstrap chain and the release gate are
in [docs/releases.md](docs/releases.md) and
[docs/roadmap.md](docs/roadmap.md); the language in
[docs/grammar.md](docs/grammar.md).

**New to vole? Run `target/volec guide` first**: the language in
about 2k tokens, for a reader who knows Rust (where it looks like Rust
and means something else, std's most used items, the first errors and
their fixes). Before using a construct you are unsure of, fetch the
lines on it: `target/volec guide --find WORDS` or `guide
TOPIC#SECTION` (`guide --list`: the topics; `guide --full`: the long
form). The text is `compiler/guide/*.md`; every example in it is
compiled and run by `tests/run.sh guide`.

## Read source through the compiler

The compiler answers questions about the program and makes checked
edits; `volec check` runs by itself after every edit (the hook,
below). **For an unfamiliar item, run `target/volec query context
NAME` first**: its source, the signatures of what it calls and its
callers, in one call (`target/volec query context run_gvn`). Use
these first:

| you want | run |
|---|---|
| an unfamiliar item: its source, callers and what it calls, in one call | `target/volec query context NAME` (replaces show + refs + def) |
| the source of an item; a whole small file | `target/volec query show NAME`; `query show FILE.vl` (a file under 300 lines is cheaper read whole) |
| every use of a name | `target/volec query refs NAME` (`--count`, `--in FILE`) |
| change a few lines of an item, checked | `target/volec edit patch NAME --old 'TEXT' --new 'TEXT'` (`--all`: every match, in an item or a FILE) |
| replace, add, remove an item | `target/volec edit replace\|insert\|delete NAME` (`< text`) |
| rename, move, change a signature, field or variant everywhere | `target/volec refactor rename\|move\|signature\|field\|variant ...` |
| missing imports, `pub`, `unsafe` blocks | `target/volec fix` |
| the errors' exact fixes (an error with `try: volec fix --suggested`: a did-you-mean, a conversion, a path, a `use`, a `pub`), instead of sed | `target/volec fix --suggested` (one checked edit, then the errors left; `--dry-run`, `--show`, `--at FILE:LINE`) |
| a bug: where it fails, the values at a line, which change broke a test | `target/volec guide debug` (`test` prints a crash's line and callers; `probe FILE:LINE EXPR... -- ARGS`; `reduce`) |
| build and test what a change touches | `bootstrap/bootstrap.sh --dev --no-suite`, `tests/run.sh FILTER...`, `tests/affected.sh` (the inner loop, below) |

Everything else (`query grep|items|type|effects|impact`, `edit apply`,
`rewrite`, `refactor extract-function|inline|split`, `batch`, `undo`):
`target/volec --help`, `target/volec CMD --help`, `target/volec
guide tools`, or `explain CODE` on any error; adding a std function, a
pass, a diagnostic: `target/volec guide how`. Every command in one
table: [docs/query.md](docs/query.md#every-command-at-a-glance-for-agents);
the edits in [docs/refactor.md](docs/refactor.md). NAME is `foo`,
`module::foo`, `Type::method`, `Struct.field` or `FILE:LINE`; a problem
is one line, `error CODE: message`, then `try:` lines to run as they are.
The program is the compiler's from the tree's root; an example's (any
program's) when a FILE or FILE:LINE argument is one of its files, or
with `--root DIR` (`query context examples/nes/check.vl:233`, `probe
examples/nes/check.vl:235 x -- --check`); a NAME the default program
lacks gets the `try:` of the program that defines it.

**Query and edit with `target/tools/volec` while you change the
compiler**: only a build whose suite passed goes there (`bootstrap.sh
--dev` with its suite; `--no-suite` leaves it, or copies the main
checkout's when the worktree has none), so it always works (your own
builds replace `target/volec`, and a broken one breaks `query`).

**Hooks.** `tools/agent-hooks/query-first.py` blocks shell commands that
read or rewrite `.vl` source (grep, sed, `sed -i`, Python writing
compiler/src) and suggests the query or `edit patch`; a `.vl` under
`tests/`, or a whole file under 300 lines, is read freely. When the tool
is not enough, rerun with a trailing reason, which is recorded: `#
no-query: need the comment above run_gvn, show omits it` (or `# no-tool:
...` for an edit). `check-after-edit.py` runs `volec check` after
every Write/Edit of a `.vl` file and every writing `volec` command:
what changed since the last check (new errors, how many fixed) is added
to that call's result; nothing added means no change, so do not run
`check` after an edit. Errors with an exact fix (`try: volec fix
--suggested`) it fixes itself and says so, each with its fix (`volec
undo` takes it back; `VOLE_HOOK_FIX=0`: off). `check` and a build
print `ok: ...` when there is no error. `turn-end.py` checks once more when you stop and
blocks the stop once if errors are left. When a tool falls short, record
it in one line: `tools/agent-feedback "query refs" "misses uses inside
never-instantiated generic fns"`; `tools/agent-feedback --find WORDS`
says whether someone has seen it already (`--list`: the last ones).

## The inner loop

Every suite run costs every agent on the machine: test what a change
touches, and leave the whole suite to the one who merges. Four tiers,
each run once by the one it names; **an agent runs tiers 1 and 2 only,
never the whole suite or a gate unless its task says so**:

1. **While working (agent):** `bootstrap/bootstrap.sh --dev --no-suite`
   builds `target/volec` in seconds (under 20 s) in a fresh worktree (the releases
   come from the main checkout's cache, only the working tree is built
   and its fixpoint checked; no suite runs, and `target/tools/volec`
   stays the last build whose suite passed). After an edit: the check
   hook's errors (or `target/volec check`), then only the cases the
   change concerns: `tests/run.sh FILTER...` (names containing a
   FILTER; `=NAME` one name; `-f FILE` a list; `-l` lists them), or
   `tests/affected.sh -O 2` for what the branch touches so far.
2. **Before reporting (agent):** `tools/premerge.sh` (prints `premerge:
   ok`) and `tests/affected.sh`: the tests `tests/affected.map` names for
   the paths changed since the branch's base, at -O0 and -O2 (`--list`
   prints the plan and why each item is in it; a changed test runs
   itself; an unknown path gets the smoke set). When `--list` says
   `linux: platform-relevant`, `tests/affected.sh --linux` runs the
   same plan in the aarch64-linux container too (colima must run).
3. **Per merge batch (integrator):** after merging the batch into the
   integration branch, one `tests/run.sh` and one `bootstrap/gate.sh
   --quick` (the chain, the suite at -O2, a short fuzz in every mode),
   and `bootstrap/bootstrap.sh --dev` there, which installs a tested
   `target/tools/volec`.
4. **A release:** one `bootstrap/gate.sh --release`, then `gate.sh
   --only bench` on an idle machine ([docs/releases.md](docs/releases.md),
   "The gate").

A test that fails in the plan is yours until shown otherwise: rerun it
alone (`tests/run.sh =NAME`) before calling it load or inherited.

## Before you commit, before a merge

- **Start from green.** Branch from the integration branch (`release-X`),
  not from a main nobody has checked; if your base fails tests, say which
  ones and fix or report them before your own work, so that your results
  are not mixed with inherited failures.
- **The commit hook** (`git config core.hooksPath tools/git-hooks`, once
  per clone) refuses a commit that adds `unsafe` without its `UNSAFE:`/
  `SAFETY:` comments, stages an unformatted `.vl`, changes `compiler/std`
  without the regenerated `compiler/src/front/stdsrc.vl`, or adds an
  example case whose SOURCE does not exist. It runs for every committer,
  under any agent harness (Claude Code's hooks do not run under opencode
  or other tools; git's do).
- **A change to an example** also needs its `tests/examples/*.test` case
  (`// REQUIRES: metal` and `// LINK:` for std::gpu/std::window) and
  `tests/run.sh example example_build`; moving an example moves its case.
- **Linux too:** a change to tests/, the runner, std, the LSP or anything
  platform-specific (`tests/affected.sh --list` says `linux:
  platform-relevant`) runs its plan in the Linux container before it is
  called done: `tests/affected.sh --linux` (colima must run). The whole
  container row (`bootstrap/gate.sh --only linux-aarch64`) is tier 3's.
- **Before reporting (tier 2):** `tools/premerge.sh` in the branch's
  worktree (base contained, unsafe justified, fmt, every touched program
  checks clean, the embedded std up to date, example cases' sources
  exist) prints `premerge: ok`, and `tests/affected.sh` passes; report
  its plan line (`plan: N of M cases; ...`) and result. No full suite,
  no gate: the integrator runs one per merge batch (tier 3).
- **Report what was asked, checkably:** a task's "Done means" list is
  answered item by item with the command or count that shows it (e.g.
  "argv uses in compiler/src: 0, `volec query refs arg_at --count`").
- **Mind the machine:** at most five agents build and test the compiler
  at once, and one gate runs at a time; under heavy load, timing results
  are not evidence (the runner SKIPs time budgets with the load).

## Conventions

- Commit as `git -c user.name=magniff -c user.email=tinysnippets@gmail.com
  commit -F msgfile`, the message in a file; no attribution trailers.
- A release's compiler is built by the previous release: features new in
  release N are used in `compiler/src` only from N+1.
- No undefined behaviour, no wildcard imports; compile speed is measured
  every release.
- `unsafe` must be justified. Try the safe way first (std's APIs, `Vec`,
  slices, `str`, or a new safe std function); use `unsafe` only when
  that is impossible, around the one operation that needs it, with a
  comment right above it:

  ```
  // UNSAFE: why this cannot be safe (C or the OS, allocator internals, a measured hot path)
  // SAFETY: why it is sound (bounds, lifetimes, aliasing, initialization, and what guarantees them)
  ```

  The same goes for an `unsafe fn` and an `extern` block. Never add
  `unsafe` (or let `volec fix` add it) to silence an error.
