## (0.28.0) A call of a value (a closure, a fn pointer, a generic
## `F: Fn(..)`) borrows the arguments of its `let` parameters as a call of
## a function does: the checker's borrow of an argument is a `let`
## parameter's, `&T` in the translation, so the argument is written `&e`
## (`sum(make(4, gpa))` -> `sum(&make(4, gpa))`, `f(1)` -> `f(&1i64)`); a
## reference already (`f(v)` of a `&Vec` parameter) is left as it is.
## 0.27.8 borrowed only the arguments of the program's functions.
$ main.vl -o mvs
ok: built mvs
% ./mvs
6 3 9 5
5 8
$ fix --edition rust main.vl
fixed, 3 parameters to &T, 6 borrows written '&x', 2 vars to 'let mut', 1 '.len' to '.len()', 5 integers annotated, 3 types, 1 std call by rewrite.tsv	main.vl	+11 -10 lines
% cat main.vl
fn make(n: i64, gpa: Gpa) -> Vec<i64, Gpa> {
    let mut v: Vec<i64, Gpa> = Vec::new_in(gpa);
    for i in 0..n {
        v.push(i);
    }
    v
}

fn apply<F: Fn(&i64) -> i64>(f: F) -> i64 { f(&1i64) + f(&2i64) }

fn twice(f: fn(&Vec<i64, Gpa>) -> i64, v: &Vec<i64, Gpa>) -> i64 { f(v) * 2 }

fn last(v: &Vec<i64, Gpa>) -> i64 { v[v.len() - 1] }

fn main(gpa: Gpa) {
    let sum = |v: &Vec<i64, Gpa>| -> i64 {
        let mut t: i64 = 0;
        for x in v.iter().copied() {
            t += x;
        }
        t
    };
    let sq = |x: &i64| -> i64 { x * x };
    let inc = |x: i64| x + 1;
    let v = make(3, gpa);
    println("{} {} {} {}", sum(&make(4, gpa)), sum(&v), sq(&3i64), inc(4i64));
    println("{} {}", apply(|x| x + 1), twice(last, &make(5, gpa)));
}
// EDITION: rust
$ check main.vl
ok: 0 errors in main.vl
$ main.vl -o prog
ok: built prog
% ./prog
6 3 9 5
5 8
