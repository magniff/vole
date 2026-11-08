## (0.28.0) MVS's `{x:c}` writes a byte as a character; the rust edition
## has no `c` and printed the number. The value is `x as char`, as rustc
## prints a char: a positional argument is wrapped (`s[0] as char`); a
## name in the literal is `{b_c}`, with the named argument `b_c = b as
## char` at the end of the print's call, once (a plain `{b}` in the same
## literal prints the number, as MVS's did).
$ main.vl -o mvs
ok: built mvs
% ./mvs
vore 118 v
$ fix --edition rust main.vl
fixed, 1 text literal to bytes, 5 bytes printed as chars	main.vl	+3 -2 lines
% cat main.vl
fn shift(b: u8, k: u8) -> u8 { b + k }

fn main() {
    let b: u8 = b'v';
    let s = "ole";
    println("{b_c}{}{}{} {b} {b_c}", s[0] as char, shift(s[0], 3) as char, s[2] as char, b_c = b as char);
}
// EDITION: rust
$ check main.vl
ok: 0 errors in main.vl
$ main.vl -o prog
ok: built prog
% ./prog
vore 118 v
