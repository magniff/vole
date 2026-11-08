## (0.28.0) MVS's `collect_in(a)`: std2's collect_in takes two type
## arguments, the collection and the allocator (0.27.8 wrote
## `collect_in::<Vec<_, _>>(a)`, one of the two, a type error). Where the
## value goes to a written type (a let's annotation, the function's result:
## rewrite.tsv's `use=typed`) it is `collect_in(a)`, the collection that
## type; elsewhere `collect_in::<C, _>(a)`, C the collection MVS's call
## made, in full: a `Vec<_, _>` is not inferred from FromIteratorIn's impls
## (type.infer), and the allocator's `_` comes from the argument.
$ main.vl -o mvs
ok: built mvs
% ./mvs
[2, 1, 0] [0, 1, 4, 9] 2 [0, 1, 4]
$ fix --edition rust main.vl
fixed, 1 receiver, 1 var to 'let mut', 3 integers annotated, 5 std calls by rewrite.tsv, 2 text views to &str, 1 copy type derived Clone, Copy	main.vl	+8 -7 lines
% cat main.vl
#[derive(Clone, Copy)] struct Countdown { n: i64 }

impl Iterator for Countdown {
    type Item = i64;

    fn next(&mut self) -> Option<i64> {
        if self.n == 0 {
            return None;
        }
        self.n -= 1;
        Some(self.n)
    }
}

fn squares(n: i64, gpa: Gpa) -> Vec<i64, Gpa> {
    (0i64..n).map(|x| x * x).collect_in(gpa)
}

fn main(gpa: Gpa) {
    let c = (Countdown { n: 3 }).collect_in::<Vec<i64, Gpa>, _>(gpa);
    let s = (0i64..4i64).map(|x| x * x).collect_in::<Vec<i64, Gpa>, _>(gpa);
    let mut words: Vec<&str, Gpa> = Vec::new_in(gpa);
    words.push("a");
    words.push("b");
    let w: Vec<&str, Gpa> = words.iter().copied().collect_in(gpa);
    println("{c:?} {s:?} {} {:?}", w.len(), squares(3, gpa));
}
// EDITION: rust
$ check main.vl
ok: 0 errors in main.vl
$ main.vl -o prog
ok: built prog
% ./prog
[2, 1, 0] [0, 1, 4, 9] 2 [0, 1, 4]
