## fix --edition rust (0.27.5): a result's 'a only on the parameters its
## views come from (MVS's view summary), an item's views by the item's
## region: temporaries given to the others need not outlive the result.
## Written, then built and run in the rust edition with the MVS
## program's output.
$ main.vl -o mvs
ok: built mvs
% ./mvs
volec fix main.vl 4
$ fix --edition rust --list-left main.vl
fixed, 5 parameters to &T, 20 views to &[T], 3 borrows written '&x', 1 access written '*r', 1 import, 2 copy types derived Clone, Copy	main.vl	+15 -14 lines
% cat main.vl
// fix --edition rust (0.27.5): a result's 'a only on the parameters its
// views come from, by MVS's view summary: `views(line, top, *leaf)` gives
// line, top and leaf's own views ('a in Leaf<'a>) the region, not tree
// nor the reference to leaf, so the temporaries `&tree_of(..)` and
// `&leaf_of(..)` need not outlive the Call.
use std::alloc::Allocator; #[derive(Clone, Copy)] struct Line<'a> {
    words: [&'a str; 3],
}

struct Leaf<'a, A: Allocator> {
    last: &'a str,
    n: i64,
    opts: Vec<i64, A>,
}

struct Tree<A: Allocator> {
    count: i64,
    subs: Vec<i64, A>,
}

#[derive(Clone, Copy)] struct Call<'a> {
    first: &'a str,
    top: &'a str,
    last: &'a str,
    count: i64,
}

fn tree_of(line: Line<'_>, gpa: Gpa) -> Tree<Gpa> {
    Tree { count: line.words.len() as i64, subs: Vec::new_in(gpa) }
}

fn leaf_of<'a>(line: &Line<'a>, gpa: Gpa) -> Leaf<'a, Gpa> {
    Leaf { last: line.words[2], n: 1, opts: Vec::new_in(gpa) }
}

fn parse<'a>(tree: &Tree<Gpa>, line: &Line<'a>, top: &'a str, leaf: &Leaf<'a, Gpa>) -> Call<'a> {
    Call {
        first: line.words[0], top: top, last: leaf.last,
        count: tree.count + leaf.n + tree.subs.len() as i64 + leaf.opts.len() as i64,
    }
}

fn call_of<'a>(line: &Line<'a>, gpa: Gpa) -> Call<'a> {
    parse(&tree_of(*line, gpa), line, line.words[1], &leaf_of(line, gpa))
}

fn main(gpa: Gpa) {
    let line = Line { words: ["volec", "fix", "main.vl"] };
    let c = call_of(&line, gpa);
    println("{} {} {} {}", c.first, c.top, c.last, c.count);
}
// EDITION: rust
$ main.vl -o prog
ok: built prog
% ./prog
volec fix main.vl 4
