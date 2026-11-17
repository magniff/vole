## XFAIL: RT-190: refactor rename (and query refs/def) at the name of a compiler-provided integer method (`wrapping_add`, `count_ones`) acts on the enclosing item: fn helper or fn main is renamed (0.30.2)
## main.vl:2:7 is the `wrapping_add` of `a.wrapping_add(8)`, main.vl:7:23
## the `count_ones` of `helper(a).count_ones()`: both are names, of
## methods the compiler provides (RT-137: query def and items do not know
## them). rename renames the item around the name: fn helper becomes wadd
## program-wide (the edit checks), and on count_ones fn main becomes ones;
## query refs main.vl:7:23 lists `5:4 def fn main() {`. A name that is no
## item of the program must be refused, as RT-80's positions on no name
## must; the message's exact text is the fixer's to set. RT-80's fix
## alone (a name token at the position) does not refuse these.
$ refactor rename main.vl:2:7 wadd
error query.no-match: no item named 'wrapping_add' in the program at main.vl:2:7
[exit 1]
$ refactor rename main.vl:7:23 ones
error query.no-match: no item named 'count_ones' in the program at main.vl:7:23
[exit 1]
% cat main.vl
fn helper(a: i64) -> i64 {
    a.wrapping_add(8)
}

fn main() {
    let a = 7i64;
    let z = helper(a).count_ones();
    println("{z}");
}
