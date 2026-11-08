## fix --edition rust (0.27.5): std::cli's type rows' `'_` take the
## signature's region ('static, or the function's 'a); an inout slice
## parameter given an array or a part of one is `&mut`; an assignment to
## a Vec's element whose index reads the Vec computes the index first.
## Written, then built and run in the rust edition with the MVS
## program's output (the rustc twin has no std::cli; the inout and index
## shapes are twinned apart, rust_t_inout_index).
$ main.vl -o mvs
ok: built mvs
% ./mvs
true
2 3 3 9
$ fix --edition rust --list-left main.vl
fixed, 1 parameter to &mut T, 4 views to &[T], 2 '&x's to '&mut x', 2 vars to 'let mut', 1 import, 2 types, 1 std call by rewrite.tsv	main.vl	+12 -11 lines
% cat main.vl
// fix --edition rust (0.27.5): std::cli's types written with a region by
// their type rows (`Arg<'_>`, `Command<'_, A>`) take the region the
// signature gives them: 'static for a result with nothing to borrow from,
// the function's 'a with two parameters it could borrow from. An inout
// slice parameter given an array or a part of one is `&mut`. An element
// of a Vec indexed by an expression that reads the Vec is assigned with
// the index computed first (Rust's IndexMut borrows the Vec before).
use std::cli::Arg; use std::cli::Command;

fn flag<'a>(name: &'a str, help: &'a str) -> Arg<'a> {
    Arg::flag(name).help(help)
}

fn build(gpa: Gpa) -> Command<'static, Gpa> {
    Command::new_in("demo", gpa).arg(flag("verbose", "say more"))
}

fn first(v: &mut [i64]) -> i64 {
    v[0] += 1;
    v[0]
}

fn main(gpa: Gpa) {
    let c = build(gpa);
    let words: [&str; 2] = ["demo", "--verbose"];
    match c.parse(words.iter().copied()) {
        Ok(m) => println("{}", m.flag("verbose")),
        Err(_) => println("error"),
    }
    let mut a = [1i64, 2, 3];
    let x = first(&mut a);
    let z = first(&mut a[1..3]);
    let mut kept = Vec::<i64, Gpa>::new_in(gpa);
    kept.push(1);
    kept.push(2);
    { let at_ix = kept.len() - 2; kept[at_ix] = 9 };
    println("{} {} {} {}", x, z, a[1], kept[0]);
}
// EDITION: rust
$ main.vl -o prog
ok: built prog
% ./prog
true
2 3 3 9
