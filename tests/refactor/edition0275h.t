## fix --edition rust (0.27.5): gate 3's shapes: `for &t in v.as_slice()`
## of a copy item, a char pattern on a `Some(spec)` of an Option<str>,
## a [u8] hole of a call with named arguments, an element of a view of an
## array of text compared with bytes. Written, then built and run in the
## rust edition with the MVS program's output.
$ main.vl -o mvs
ok: built mvs
% ./mvs
2
a 1
b
122
abc (-O2, abc)
true false
$ fix --edition rust --list-left main.vl
fixed, 1 parameter to &T, 5 views to &[T], 2 borrows written '&x', 2 vars to 'let mut', 1 integer annotated, 1 import, 4 text literals to bytes, 2 byte views printed as text by str::from_utf8	main.vl	+15 -14 lines
% cat main.vl
// fix --edition rust (0.27.5): a copy item of a Vec's as_slice() is
// `for &t in`; a `Some(spec)` of a match on an Option<str> is text, so
// its method's character pattern stays a char; a hole of a call with
// named arguments is wrapped as a positional one; an element of a view of
// an array of text is text (`.as_bytes()` where bytes are compared).
use std::fmt::Display; fn word() -> &'static str {
    "--a=1 --b"
}

fn name() -> &'static [u8] {
    b"abc"
}

fn known(name: &[u8]) -> bool {
    let all = ["xyz", "abc"];
    let names = &all[..];
    for i in 0..names.len() {
        if names[i].as_bytes() == name {
            return true;
        }
    }
    false
}

fn show<T: Display>(x: &T) {
    println("{}", x);
}

fn main(gpa: Gpa) {
    let mut v = Vec::<i64, Gpa>::new_in(gpa);
    v.push(4);
    v.push(5);
    let mut w = Vec::<i64, Gpa>::new_in(gpa);
    for &t in v.as_slice() {
        w.push(t);
    }
    println("{}", w.len());
    for x in word().split(' ') {
        match x.strip_prefix("--") {
            Option::Some(spec) => match spec.split_once('=') {
                Option::Some((k, n)) => println("{} {}", k, n),
                Option::None => println("{}", spec),
            },
            Option::None => {}
        }
    }
    let z: &[u8] = b"z";
    println("{}", z[0]);
    let lv: i64 = 2;
    show(&format_args("{} (-O{lv}, {})", str::from_utf8(name()).unwrap(), str::from_utf8(name()).unwrap(), lv = lv));
    println("{} {}", known(name()), known(b"q"));
}
// EDITION: rust
$ main.vl -o prog
ok: built prog
% ./prog
2
a 1
b
122
abc (-O2, abc)
true false
