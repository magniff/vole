## XFAIL: RT-80: refactor rename FILE:LINE:COL with the column on no name (an operator, a keyword, past the line's end) renames the item around it (0.30.2)
## main.vl:3:11 is the `*` of `total * 2`, main.vl:3:40 is past the end
## of that line, main.vl:7:5 is the `let` of main: no name is there.
## rename renames the enclosing item instead: fn helper becomes doubled
## program-wide, and on the `let` it renames fn main. A position that
## names nothing must be refused, as a line between items is (`error
## query.no-match: no item at main.vl:5:1`); the message's exact text
## is the fixer's to set.
$ refactor rename main.vl:3:11 doubled
error query.no-match: no name at main.vl:3:11
[exit 1]
$ refactor rename main.vl:3:40 doubled
error query.no-match: no name at main.vl:3:40
[exit 1]
$ refactor rename main.vl:7:5 start
error query.no-match: no name at main.vl:7:5
[exit 1]
% cat main.vl
fn helper(x: i64) -> i64 {
    let total = x + 1;
    total * 2
}

fn main() {
    let v = helper(3);
    println("{v}");
}
