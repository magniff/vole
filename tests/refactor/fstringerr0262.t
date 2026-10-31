## 0.26.2: `fix --only fstring` checks its edit by the errors' codes and
## items, not their text: the program's own.moved is reworded (the
## f-string its message quotes becomes a format string), no error is
## added, and the edit is written; the error is still there.
$ check
main.vl:17:26: error[own.moved] 'copy' is used here after it moved into 'sum(sink v)' at 16:26 | help: use it before the move, pass a copy where it moves ('.clone()'), or let the callee read it: a let parameter ('x: T'), not 'sink' | try: volec edit patch main.vl:16 --old 'println(f"first {sum(copy)}");' --new 'println(f"first {sum(copy.clone())}");'
[exit 1]
$ fix --only fstring --keep-braces
fixed 2 f-strings and format literals	main.vl	+2 -2 lines
% cat main.vl
// `fix --only fstring` on a program with an error (tests/refactor/
// fstringerr0262.t): the edit rewords it (its message quotes the f-string)
// and adds none, so it is written.
fn sum(v: sink Vec<i64>) -> i64 {
    var t = 0;
    for x in v.as_slice() {
        t += x;
    }
    t
}

fn main(gpa: Gpa) {
    var v: Vec<i64> = Vec::new_in(gpa);
    v.push(1);
    let copy = v;
    println("first {}", sum(copy));
    println("again {}", sum(copy));
}
$ check
main.vl:17:29: error[own.moved] 'copy' is used here after it moved into 'sum(sink v)' at 16:29 | help: use it before the move, pass a copy where it moves ('.clone()'), or let the callee read it: a let parameter ('x: T'), not 'sink' | try: volec edit patch main.vl:16 --old 'println("first {}", sum(copy));' --new 'println("first {}", sum(copy.clone()));'
[exit 1]
