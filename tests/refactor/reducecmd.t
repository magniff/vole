## `volec reduce` over a program (0.18): it is made small (items, then
## statements, left out) while it stays interesting.
## --differs: -O0 and -O2 disagree (here a test-only switch makes -O2 read
## the literal 12345 as 12346, in one of 30 functions of 428 lines)
% VOLE_PLANT_MISCOMPILE=1 "$COMPILER" reduce main.vl --differs
reduced main.vl: 429 lines to 13 in 308 runs; written to main.min.vl
fn f17(x: i64) -> i64 {
    let mut t = x;
    t = t + 12345;
    t
}

fn main() -> i32 {
    let mut total: i64 = 0;
    total += f17(total % 1000);
    println("{total}");
    0
}
// EDITION: rust
% wc -l < main.min.vl | tr -d ' '
13
## --fails TEXT: its build or run prints TEXT
$ reduce crash.vl --fails 'index out of bounds'
reduced crash.vl: 21 lines to 9 in 35 runs; written to crash.min.vl
fn last(v: [i64]) -> i64 {
    v[v.len]
}

fn main() -> i32 {
    let b = [4, 5];
    println("{}", last(b[..]));
    0
}
## nothing to keep
$ reduce main.vl --differs
error reduce.not-failing: main.vl: -O0 and -O2 agree on it as it is (nothing to keep)
[exit 1]
$ reduce crash.vl --fails 'no such text'
error reduce.not-failing: crash.vl: its build and run do not print the text as it is (nothing to keep)
[exit 1]
