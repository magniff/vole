## fix --edition rust (0.27.5): bytes declared by a static or a constant
## (`[u8]`, `[[u8]; N]`), through a borrow, an `unsafe` block or an `if`
## of them, are printed through `str::from_utf8(x).unwrap()`, and a
## literal where such bytes go (a static's or a constant's value, an
## `if` branch beside them) is `b".."`: gate 3's `&SRC[a..b]`, `KNOWN[i]`
## and `if c { &s[1..] } else { s }`. Written, then built and run in the
## rust edition with the MVS program's output.
$ main.vl -o mvs
ok: built mvs
% ./mvs
static static bytes
[sta]
two
115
$ fix --edition rust --list-left main.vl
fixed, 6 views to &[T], 1 print given its format, 4 text literals to bytes, 5 byte views printed as text by str::from_utf8	main.vl	+9 -8 lines
% cat main.vl
// fix --edition rust (0.27.5): bytes declared by a static or a constant,
// through a borrow, an `unsafe` block or an `if` of them, are printed
// through `str::from_utf8(..).unwrap()` too; a literal where such bytes
// go (a static's or a constant's value, a branch beside them) is `b".."`.
static DATA: &[u8] = b"static bytes";
const WORDS: [&[u8]; 2] = [b"one", b"two"];

fn main() {
    let c = std::env::args().count() > 5;
    let part = &DATA[0..6];
    let short = if c { &part[1..3] } else { part };
    let shown = if c { b"none" } else { &DATA[7..12] };
    println("{part} {short} {shown}", part = str::from_utf8(part).unwrap(), short = str::from_utf8(short).unwrap(), shown = str::from_utf8(shown).unwrap());
    println("[{}]", str::from_utf8(unsafe { &DATA[0..3] }).unwrap());
    println("{}", str::from_utf8(WORDS[1]).unwrap());
    println("{}", DATA[0] as i64);
}
// EDITION: rust
$ main.vl -o prog
ok: built prog
% ./prog
static static bytes
[sta]
two
115
