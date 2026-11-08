## fix --edition rust (0.27.6): the std::gpu::wgsl port's classes
## (tests/translate/wgsl-classes.md, 1 to 8): a prelude variant's `use`
## goes; `Buf<A>` is `Vec<u8, A>`; a Buf's push_fmt, push_str and `len`
## through a field or a parameter take their rows (`len()` once); a text
## literal where a row's bytes go (`$b1`) is `b".."`; a bytes hole of a
## function's format call is bound by a `let`; parse_f64 of bytes is
## `str::from_utf8(&s[..]).unwrap().parse::<f64>()`; a non-Copy element
## bound by `let` is `&fs[0]`. Written, formatted (fmt takes the output as
## it is), then built and run in the rust edition with the MVS program's
## output; the rustc twin agrees (rust_t_wgsl_classes).
$ main.vl -o mvs
main.vl:9:22: warning[item.deprecated] use of deprecated struct 'Buf': use String<A> for text, Vec<u8, A> for bytes (volec fix --only buf) | help: marked #[deprecated] at <std>:518:5
main.vl:12:15: warning[item.deprecated] use of deprecated struct 'Buf': use String<A> for text, Vec<u8, A> for bytes (volec fix --only buf) | help: marked #[deprecated] at <std>:518:5
main.vl:22:20: warning[item.deprecated] use of deprecated struct 'Buf': use String<A> for text, Vec<u8, A> for bytes (volec fix --only buf) | help: marked #[deprecated] at <std>:518:5
main.vl:44:24: warning[item.deprecated] use of deprecated struct 'Buf': use String<A> for text, Vec<u8, A> for bytes (volec fix --only buf) | help: marked #[deprecated] at <std>:518:5
main.vl:51:15: warning[item.deprecated] use of deprecated struct 'Buf': use String<A> for text, Vec<u8, A> for bytes (volec fix --only buf) | help: marked #[deprecated] at <std>:518:5
ok: built mvs
% ./mvs
22 15 1.5 2 1
$ fix --edition rust --list-left main.vl
fixed, 1 parameter to &T, 1 parameter to &mut T, 1 receiver, 5 views to &[T], 1 '&x' to '&mut x', 2 borrows written '&x', 5 vars to 'let mut', 3 '.len's to '.len()', 2 imports, 5 text literals to bytes, 2 types, 8 std calls by rewrite.tsv, 3 byte views printed as text by str::from_utf8	main.vl	+26 -25 lines
$ fmt main.vl
formatted	main.vl	+6 -3 lines
% cat main.vl
// fix --edition rust (0.27.6): the classes the std::gpu::wgsl port found.
// A prelude variant's `use` goes; Buf<A> is Vec<u8, A>; a Buf's
// push_fmt, push_str and len through a field or a parameter take their
// rows (`len` once); a text literal where a row's bytes go is b".."; a
// bytes hole of a function's format call is bound by a `let`; parse_f64
// of bytes is str::from_utf8's; a non-Copy element bound by `let` is a
// reference.

use std::alloc::Allocator;

pub struct Fr<A: Allocator> {
    pub emsg: Vec<u8, A>,
}

impl<A: Allocator> Fr<A> {
    pub fn err(&mut self, what: &[u8]) {
        self.emsg.extend_from_slice(b"ref to ");
        { let what = str::from_utf8(what).unwrap();
            std::fmt::write(&mut self.emsg, "'{what}' is not here").unwrap() };
    }
}

fn note(out: &mut Vec<u8, Gpa>, what: &[u8]) {
    { let what = str::from_utf8(what).unwrap();
        std::fmt::write(&mut *out, "'{what}' is not here").unwrap() };
}

fn num(s: &[u8]) -> f64 {
    str::from_utf8(&s[0..3]).unwrap().parse::<f64>().unwrap_or(0.0)
}

fn half(x: i64) -> Option<i64> {
    if x % 2 == 0 { Some(x / 2) } else { None }
}

struct F<A: Allocator> {
    params: Vec<i64, A>,
}

fn count(fs: &Vec<F<Gpa>, Gpa>) -> i64 {
    let f = &fs[0];
    f.params.len() as i64
}

fn main(gpa: Gpa) {
    let mut f = Fr { emsg: Vec::new_in(gpa) };
    f.err(b"x");
    let mut b: Vec<u8, Gpa> = Vec::new_in(gpa);
    b.push(b'1');
    b.push(b'.');
    b.push(b'5');
    b.push(b'x');
    let mut out = Vec::new_in(gpa);
    note(&mut out, &b[3..4]);
    let mut fs: Vec<F<Gpa>, Gpa> = Vec::new_in(gpa);
    let mut p: Vec<i64, Gpa> = Vec::new_in(gpa);
    p.push(1);
    fs.push(F { params: p });
    match half(4) {
        Some(h) => println("{} {} {} {} {}", f.emsg.len(), out.len(), num(b.as_slice()), h,
            count(&fs)),
        None => println("odd"),
    }
}
// EDITION: rust
$ main.vl -o prog
ok: built prog
% ./prog
22 15 1.5 2 1
