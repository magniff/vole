## The refactorings keep 0.16's attributes (tests/refactor/attrs016/):
## signature and rename leave #[pure] #[no_io] on the function, move takes
## #[effects(...)] along, inline deletes a #[pure] function with them.
$ refactor signature mid --add 'c: i64 = 0' --fill-calls
added parameter c: i64 to crate::mid, 1 call	main.vl	+2 -2 lines
$ refactor move grow --to util
moved crate::grow to crate::util	2 files	+7 -5 lines
$ refactor inline twice
inlined crate::twice at 1 call, deleted it	main.vl	+1 -7 lines
$ refactor rename mid middle
renamed crate::mid to middle	main.vl	+2 -2 lines
% cat main.vl util.vl
use crate::util::grow;

mod util;

#[pure]
#[no_io]
fn middle(a: i64, b: i64, c: i64) -> i64 {
    a + (b - a) / 2
}

fn main(gpa: Gpa) {
    let mut v: Vec<i64, Gpa> = Vec::new_in(gpa);
    grow(&mut v);
    println("{}", middle(2, 10, 0) + (v.len() as i64) * 2 + util::one());
}
// EDITION: rust
pub fn one() -> i64 {
    1
}

#[effects(alloc(Gpa), panic, diverge)]
pub fn grow(v: &mut Vec<i64, Gpa>) {
    v.push(1);
}
% "$COMPILER" main.vl -o prog && ./prog
9
ok: built prog
