## fix --edition rust (0.27.4, gate 3's second wall): `[u8]` printed as
## text in a program that also reads its bytes is given
## `str::from_utf8(x).unwrap()`: a hole that names it (the named argument
## `x = ..` at the end of the literal's call), an argument after the
## literal, the value of `println(x)`, an argument of a `T: Display`
## parameter. A `str` value, a field or a binding declared `str`, is
## printed as it is, and a text literal given to a `str` parameter stays
## a text literal. Written, then built and run in the rust edition with
## the MVS program's output.
$ fix --edition rust --list-left main.vl
fixed, 1 parameter to &T, 7 views to &[T], 1 borrow written '&x', 1 '.len' to '.len()', 1 print given its format, 1 import, 1 text literal to bytes, 4 byte views printed as text by str::from_utf8, 1 copy type derived Clone, Copy	main.vl	+11 -10 lines
% cat main.vl
// fix --edition rust (0.27.4, gate 3's second wall): a program that uses
// its bytes as bytes too keeps `[u8]` as `&[u8]`; where one is printed as
// text it is given `str::from_utf8(x).unwrap()` (a hole naming it gets the
// named argument, an argument after the literal and the value of
// `println(x)` are wrapped, and so is one given to a `T: Display`); a
// value declared `str` is `&str` already, and a text literal given to a
// `str` parameter stays one.
#[derive(Clone, Copy)] struct Opt<'a> { name: &'a str, help: &'a str }

fn option(name: &str) -> Opt<'_> {
    Opt { name: name, help: "none" }
}

fn first(v: &[u8]) -> u8 {
    v[0]
}

fn shown<T: std::fmt::Display>(x: &T) {
    println("[{}]", x);
}

fn show(name: &[u8], n: i64) {
    println("'{name}' has {} bytes, first {}: {name}", name.len(), first(name), name = str::from_utf8(name).unwrap());
    println("{} and {}", str::from_utf8(name).unwrap(), n);
    println("{}", str::from_utf8(name).unwrap());
    shown(&str::from_utf8(name).unwrap());
}

fn main() {
    let o = option("budget");
    println("{} {}", o.name, o.help);
    show(b"hello", 2);
}
// EDITION: rust
$ main.vl -o prog
ok: built prog
% ./prog
budget none
'hello' has 5 bytes, first 104: hello
hello and 2
hello
[hello]
