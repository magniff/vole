## fix --edition rust (0.27.5): std::process's and std::env's rows, from
## std2's process (std2275): Command::new to Command::new_in on the
## function's allocator, process::id and Child::id (u32s), env::get_in
## (std2's var_in); a program or argument given as bytes is
## str::from_utf8(p).unwrap(). Written, then built and run in the rust
## edition with the MVS program's output.
$ main.vl -o mvs
ok: built mvs
% ./mvs
3
true
true
true
unset
$ fix --edition rust --list-left main.vl
fixed, 3 views to &[T], 4 vars to 'let mut', 1 import, 5 text literals to bytes, 5 std calls by rewrite.tsv, 6 byte views printed as text by str::from_utf8	main.vl	+16 -15 lines
% cat main.vl
// fix --edition rust (0.27.5): std::process's and std::env's calls that
// change in std2, by rewrite.tsv: Command::new (Command::new_in on the
// function's allocator), process::id and Child::id (u32s), env::get_in
// (std2's var_in); a program or argument given as bytes (a Vec<[u8]>'s
// element, a slice) is `str::from_utf8(p).unwrap()`.
use std::env; use std::process;
use std::process::Command;

fn run(gpa: Gpa) -> i32 {
    let mut words = Vec::<&[u8], Gpa>::new_in(gpa);
    words.push(b"/bin/sh");
    words.push(b"-c");
    words.push(b"exit 3");
    let mut cmd = std::process::Command::new_in(str::from_utf8(words[0]).unwrap(), gpa);
    for k in 1..words.len() {
        cmd.arg(str::from_utf8(words[k]).unwrap());
    }
    // (a byte read: the program's [u8] are bytes, not text)
    let z: &[u8] = b"z";
    if z[0] == b'z' {
        cmd.arg(str::from_utf8(&z[0..1]).unwrap());
    }
    match cmd.status() {
        Ok(st) => match st.code() {
            Some(c) => c,
            None => -1,
        },
        Err(_) => -2,
    }
}

fn main(gpa: Gpa) {
    println("{}", run(gpa));
    println("{}", (std::process::id() as i32) > 0);
    let mut c = std::process::Command::new_in("/bin/sh", gpa);
    c.arg("-c");
    c.arg("true");
    match c.spawn() {
        Ok(ch) => {
            println("{}", (ch.id() as i32) > 0);
            let mut w = ch;
            match w.wait() {
                Ok(st) => println("{}", st.success()),
                Err(_) => println("no wait"),
            }
        }
        Err(_) => println("no spawn"),
    }
    match std::env::var_in("VOLE_T_NOT_SET_X", gpa) {
        Ok(v) => println("set {}", v),
        Err(_) => println("unset"),
    }
}
// EDITION: rust
$ main.vl -o prog
ok: built prog
% ./prog
3
true
true
true
unset
