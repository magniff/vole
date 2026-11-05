# corpus271: the borrow checker's corpus and its rustc twin (0.27.1)

The twin script, 187 cases from the spec's rule ids, the try-tests, the
budget script and the cost row, before the checker existed.

## What worked

- rustc as the oracle before the spec was final: every case's verdict
  was checked by rustc before it was committed, and the twin found the
  spec's mistakes in its first round (a reassigned reference, a shared
  borrow's code against a mutable loan, fake borrows against moves, a
  partial assignment after a move, constant indices, Rust 2021's
  disjoint captures), each fixed in the spec before any code read it.
- A generator kept outside the tree: a case is a few lines of
  description (rule, code, body, the preludes it uses); the files are
  written, formatted, and their `ERROR` positions taken from rustc's
  first error, so a case's line and column are rustc's. Positive cases
  get their `EXPECT` lines from vole's run, compared with rustc's run of
  the same program.
- Blanking the directive lines rather than deleting them: rustc's
  positions are the case's.
- `XFAIL` with the milestone named for every rejected case: the corpus
  merges before the checker, and each milestone's flips are a grep.

## What cost time, ranked

1. Finding the common subset by trial: no `Box`, no `PhantomData`, no
   `&raw`, no deferred initialization (`let x;`) in the rust edition
   yet, no unsizing of `&[T; n]` to `&[T]` (`&a[..]`), integer literals
   `i32` in Rust (an `as *const i64` cast of `&1` does not compile there).
2. `println!` borrows its arguments: printing a mutably borrowed
   variable is E0502 in rustc and a copy here. The cases read such a
   variable by a copy instead.
3. `rustc -o /dev/null` fails for an accepted program (its temporary
   directory goes beside the output): `--emit=metadata` into a temporary.
4. `volec check --time-passes` under the tools' cache counts the cache's
   work in `check` (66 ms against 3.5 ms with `VOLE_CACHE=off`): the
   budget script turns it off.
5. `shell` builtins: a function named `times` in a POSIX script is the
   builtin.

## For the next corpus

- Write the twin first and run every case through it as it is written;
  a case whose verdict disagrees with rustc and names no class is a
  question for the spec, not for the case.
- A rejected case's column is rustc's until the checker's diagnostics
  land; re-key the positions once, when they do.
