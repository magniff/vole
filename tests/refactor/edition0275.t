## fix --edition rust (0.27.5): `str::from_utf8(x).unwrap()` only for a
## printed value that is bytes where it is declared (a binding written
## `[u8]`, a call whose result is written so), not a literal, an `if` of
## literals or a `str` binding: rustc rejects `str::from_utf8("..")`
## (E0308), which 0.27.4's translation wrote in 230 of gate 2's programs.
## Written, then built and run in the rust edition with the MVS
## program's output.
$ main.vl -o mvs
ok: built mvs
% ./mvs
Hello
no
text bytes by
second
98
$ fix --edition rust --list-left main.vl
fixed, 6 views to &[T], 2 prints given their format, 1 text literal to bytes, 2 byte views printed as text by str::from_utf8	main.vl	+9 -8 lines
% cat main.vl
// fix --edition rust (0.27.5): in a program that reads bytes as bytes
// too, only what is bytes where it is declared is printed through
// `str::from_utf8(..).unwrap()`: a binding written `[u8]`, a call whose
// result is. A literal, an `if` of literals, a `str` binding and an
// element of an array of `str`s are text already (`str::from_utf8("..")`
// is no Rust).
fn tag(b: &[u8]) -> &[u8] {
    &b[0..2]
}

fn main() {
    let raw: &[u8] = b"bytes";
    let s: &str = "text";
    let names: [&str; 2] = ["first", "second"];
    let c = std::env::args().count() > 5;
    println("Hello");
    println("{}", if c { "yes" } else { "no" });
    println("{s} {} {}", str::from_utf8(raw).unwrap(), str::from_utf8(tag(raw)).unwrap());
    println("{}", names[1]);
    println("{}", raw[0] as i64);
}
// EDITION: rust
$ main.vl -o prog
ok: built prog
% ./prog
Hello
no
text bytes by
second
98
