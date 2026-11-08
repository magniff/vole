## fix --edition rust (0.27.5): MVS std's cli.vl shapes (gate 2's free
## sample). A derive's impl, the checker's, gets no rule's edit
## (`#[derive(PartialEq, *Eq, *Debug, *Clone)]` was written), and an enum
## without fields derives Copy with its own derive; a char pattern of
## std's method on text stays a char (`s.split('|')`); a function that
## writes through a Fmt returns std::fmt::Result with `Ok(())`, its calls
## `?`'d, an empty `return;` in it `return Ok(());`; a row's `&mut $r` of
## a `&mut` parameter is `&mut *out`. Written, then built and run in the
## rust edition with the MVS program's output; tests/run/
## rust_t_cli_shapes is the translation, which the rustc twin builds.
$ main.vl -o mvs
ok: built mvs
% ./mvs
6 <--help> <out> false
<out><out>
$ fix --edition rust --list-left main.vl
fixed, 3 parameters to &mut T, 1 receiver, 6 views to &[T], 2 '&x's to '&mut x', 2 vars to 'let mut', 1 import, 2 text literals to bytes, 4 types, 6 std calls by rewrite.tsv, 3 copy types derived Clone, Copy	main.vl	+23 -22 lines
% cat main.vl
// fix --edition rust (0.27.5): MVS std's cli.vl shapes. A derive's
// impl is the checker's, which no rule edits (`#[derive(Eq)]` stays
// itself); a char pattern of std's method on text stays a char
// (`s.split('|')`); a function that writes through a Fmt returns
// std::fmt::Result, `Ok(())`, its calls `?`'d and an empty `return;`
// `return Ok(());`; a row's `&mut $r` of a `&mut` parameter reborrows it
// (`&mut *out`).
use std::fmt::Debug; use std::fmt::Formatter as Fmt; use std::fmt::Display; #[derive(PartialEq, Eq, Debug, Clone, Copy)]
enum Kind {
    Flag,
    Value,
}

#[derive(Clone, Copy)] struct Opt<'a> {
    name: &'a str,
    kind: Kind,
}

fn put_name(f: &mut Fmt<'_>, name: &str, flag: bool) -> std::fmt::Result {
    if name.len() == 0 {
        return Ok(());
    }
    if flag {
        f.write_str("--")?;
    }
    f.write_str(name)?;
 Ok(()) }

impl Display for Opt<'_> {
    fn fmt(&self, f: &mut Fmt<'_>) -> std::fmt::Result {
        if self.name.len() == 0 {
            return Ok(());
        }
        f.write_char(b'<' as char)?;
        put_name(f, self.name, self.kind == Kind::Flag)?;
        f.write_char(b'>' as char)?;
     Ok(()) }
}

fn add(out: &mut String<Gpa>, o: Opt<'_>) {
    std::fmt::write(&mut *out, o).unwrap();
    std::fmt::write(&mut *out, o).unwrap();
}

fn main(gpa: Gpa) {
    let s: &str = "a|bb|ccc";
    let mut n: i64 = 0;
    for part in s.split('|') {
        n += part.len() as i64;
    }
    let o = Opt { name: "help", kind: Kind::Flag };
    let v = Opt { name: "out", kind: Kind::Value };
    println("{} {o} {v} {}", n, o.kind == v.kind);
    let mut out = String::new_in(gpa);
    add(&mut out, v);
    println("{}", out);
}
// EDITION: rust
$ main.vl -o prog
ok: built prog
% ./prog
6 <--help> <out> false
<out><out>
