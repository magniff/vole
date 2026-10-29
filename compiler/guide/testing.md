# Tests, properties and fuzzing

Tests are written in the language (0.18) and run by `volec test`,
which builds them at -O0 and at -O2 and compares the two. Other builds
leave test items out; `check` and the queries see them.

A test that allocates takes the allocator as its parameter, as `main`
does: `#[test] fn t(gpa: Gpa) { var v = Vec::new_in(gpa); .. }` (there
is no `Gpa::default()` or `Gpa::new()`; the test runner gives the gpa,
and checks that the test frees what it allocates).

## #[test]

```vole
fn gap(v: [i64]) -> i64 {
    var best = 0;
    for i in 1..v.len() {
        if v[i] - v[i - 1] > best {
            best = v[i] - v[i - 1];
        }
    }
    best
}

#[test]
fn gap_of_three() {
    assert_eq(gap([1, 5, 6][..]), 4);
}

#[test]
fn parses() -> Result<(), std::ParseIntError> {
    let n = std::parse_int("12")?;
    assert(n == 12);
    Ok(())
}

#[test]
fn keeps_nothing(gpa: Gpa) {
    var b = Buf::new_in(gpa);
    b.push_str("dropped at the end");
}

fn main() -> i32 {
    std::print_int(gap([2, 9][..]));
    0
}
```
```out
7
```

- A `#[test]` takes nothing or `gpa: Gpa`, and returns `()` or a
  Result (an `Err` fails). Anything else is `test.signature`.
- Test builds use `--check-alloc`: a block left allocated fails the test
  (`check-alloc: 1 block of Gpa not freed ... allocated at FILE:L:C`).
- `#[cfg(test)] mod tests;` (a file, or `mod tests { .. }`) is a module
  only test builds have. It sees its parent's items without an import:
  `use super::*;` is refused (`import.wildcard`; no wildcard imports).
- `assert_snapshot(x)` compares `{x:?}` with
  `tests/snapshots/MODULE__TEST__N.snap`; the first run writes it, a
  change fails with the first differing line, `--accept` rewrites it.

## A check must be able to fail

A test, a `--check` mode, a verdict a demo prints: each is worth what it
can catch. One that passes whatever the code does proves nothing, and
reporting it as verified misleads. Before trusting a check:

- **Break the code on purpose once and see the check fail.** Flip a
  sign, drop a term, skip the kernel's write, start a loop one step late;
  run the check; it must fail. Then undo the break. A check that still
  passes tests nothing.
- **Compare with an independent reference**: a CPU version written
  apart from the code under test, a closed form, a published value;
  exactly where the arithmetic is exact (integers, a sort, a scan), and
  within a stated tolerance where it is not. "Not black", "no NaN" and
  "in range" are smoke tests, not checks of the result.
- **Check what the clamp or the construction does not already
  guarantee.** Positions clamped into a box are always inside it, so "no
  particle escapes" holds by construction: check what the walls must do
  instead (the velocity reflected, mass conserved). A total the update
  renormalizes is conserved whatever the physics; a quantity that
  settles in a few steps "grows" for any run. Ask: what wrong program
  passes this?

```vole
// The update clamps x into 0..1.
fn step(x: f64, v: f64, dt: f64) -> f64 {
    let y = x + v * dt;
    if y < 0.0 { 0.0 } else if y > 1.0 { 1.0 } else { y }
}

// Weak: true for any step that clamps, right or wrong inside.
#[test]
fn stays_inside() {
    assert(step(0.5, 100.0, 1.0) <= 1.0);
}

// Able to fail: the exact motion where the clamp does not act (break
// step's `v * dt` into `v` and this fails; stays_inside still passes).
#[test]
fn moves_by_v_dt() {
    assert_eq(step(0.25, 0.5, 0.5), 0.5);
}

fn main() -> i32 {
    0
}
```

## #[property]

A property's parameters are generated: 100 cases (`--cases N`), sizes
growing, a failure shrunk to a small input and printed with its seed.

```vole
fn clamp(x: i64, lo: i64, hi: i64) -> i64 {
    if x < lo { lo } else if x > hi { hi } else { x }
}

#[property]
fn clamp_stays_in(x: i64, lo: i64, hi: i64) {
    if lo <= hi {
        let c = clamp(x, lo, hi);
        assert(lo <= c && c <= hi);
    }
}

struct Small { n: i64 }

impl std::Arbitrary for Small {
    fn arbitrary(g: inout std::Gen) -> Small {
        Small { n: g.int_in(0, 9) }
    }
}

#[property]
fn small_is_small(s: Small) {
    assert(s.n >= 0 && s.n <= 9);
}

fn main() -> i32 {
    std::print_int(clamp(12, 0, 9));
    0
}
```
```out
9
```

- Numbers, bool, `Vec<T>`, `[T]`, `Buf`, `Option`, `Result`, tuples
  and the program's structs and enums are generated from their types;
  `impl std::Arbitrary` gives a type its own (`g.int_in(lo, hi)`,
  `g.choose(n)`, `g.bool()`, `g.size()`).
- Each case runs in a child process; its values are dropped after it,
  and a block it leaves allocated fails the case (a leak).
- A function with an `ensures` is tested as a property too, its
  requires filtering the inputs (`--no-contracts`: not).

## volec test

```text
$ volec test
test main.vl: 6 passed, 2 failed (1 case, 5 #[test], 2 #[property], 1 contract; -O0 and -O2 agree)
FAIL gap_needs_two: checks.vl:14:8: index out of bounds: index 1, length 1
  trace: checks.vl:14 checks::gap_needs_two
FAIL bubble_sorts (property, case 11 of 100, shrunk in 8 steps): not sorted
  input: v = [1, 0]
  try: volec test bubble_sorts --seed 0xf788dd27897d1fed main.vl
```

- The summary first, then one line per failure, its trace, its input
  and the command that replays it. `FILTER` runs the tests whose name
  holds it; `tests/NAME.in` with `NAME.out` are cases of the program.
- A test whose -O0 and -O2 runs differ is a `DIFF` line: the compiler's
  bug, not yours (`volec reduce --differs` shrinks it).
- `--seed H` replays a property's failure, `--accept` takes snapshots,
  case outputs and saved fuzz inputs, `-O N` runs one level.
- What a failing test printed is under its failure (`  stdout: x = 3`,
  `  stderr: ...`); `--show-output` (Rust's `--nocapture` too) prints
  every test's under its name (`OUTPUT NAME`), so a value is seen with
  `println`, not by failing an assert on purpose.

## #[fuzz] and volec fuzz

```vole
fn parse(data: [u8]) -> i64 {
    if data.len() >= 2 && data[0] == 'O' && data[1] == 'K' {
        return 1;
    }
    0
}

#[fuzz]
fn parse_never_crashes(data: [u8]) {
    let _ = parse(data);
}

fn main() -> i32 {
    std::print_int(parse("OK"));
    0
}
```
```out
1
```

`volec fuzz NAME [--time S]` builds the test binary with `--coverage`
(every block counts in std's map) and mutates inputs, keeping those that
reach new code. A crash is shrunk, saved under `.volec/fuzz/NAME/`
and replayed by every `volec test` after (`--accept` keeps it in
`tests/fuzz/NAME/`). A `#[fuzz]` takes one `[u8]` (or any generated
types, like a property).

## volec reduce over programs

- `volec reduce PROG.vl --differs [--input F]`: the program cut
  while its -O0 and -O2 runs disagree (a miscompile, to report).
- `--fails 'TEXT'`: while the build or the run prints TEXT.
- `--test NAME`: while test NAME fails as it does now.

Items, then statements, are cut by halves, then one by one; the result
is `PROG.min.vl`. For an input instead: `volec reduce FILE --until
'CMD'` (guide debug).

## tests/run.sh cases

The compiler's own suite (`tests/run.sh`) checks programs by `//`
directives; its header lists them all. Two help with programs whose
output varies:

```text
// EXPECT: 320 x 180 cells: {num} ms a step, {int} x {int} picture
// EXPECT-PPM: out.ppm tests/golden/NAME.ppm region 16,8,32,32 tolerance 8 allow 1%
```

- `EXPECT` holes: `{num}` a number, `{int}` an integer, `{..}` any
  text within the line; each line still matches one line.
- `EXPECT-PPM OUT REF`: the PPM the program wrote (OUT, in its run
  directory) against REF (the region's size), a channel off by at most
  the tolerance, up to `allow` of the pixels off. A failure gives the
  count, the worst pixel and `try: cp target/test-shots/CASE.ppm REF`.
- A check that cannot run here (window tests with no display frames:
  the screen locked) is `SKIP NAME: why`, counted apart, never a pass.
