# io

## Files, paths, the environment, processes

Rust's std, with the allocator written where a call allocates. A path is
a `&str` (std2 has no Path or PathBuf). `File::open(p)?`,
`File::create(p)?`, `OpenOptions::new().append(true).create(true).open(p)?`;
`fs::read_to_string_in(p, gpa)?` (a `String<Gpa>`), `fs::read_in(p, gpa)?`
(a `Vec<u8, Gpa>`), `fs::write(p, data)?`, `fs::metadata(p)?` (`len()`,
`is_dir()`), `fs::create_dir_all(p)?`, `fs::remove_file`,
`fs::remove_dir_all`, `fs::rename(a, b)`, `fs::copy(a, b)`,
`fs::read_dir(p)?` (entries: `let e = e?; e.file_name()`, a `&str` into
the entry; `e.path()`), `fs::exists(p)?` (a `Result<bool>`). Errors are
`io::Error` (`e.kind()`, an `ErrorKind`; Display as Rust's: `No such file
or directory (os error 2)`), and `io::Result<T>` goes with `?`; `main`
may return it (an `Err` prints `Error: ` and its Debug form, exit 1); a
`run() -> io::Result<()>` and a `main` that prints `{e}` say it better.
`BufReader::new(f)` and `BufWriter::new(f)` keep their buffer inline (no
allocation). With `use std::io::BufRead`, `r.read_line(&mut s)?` appends a
line, its `'\n'` included (0 at the end), and `r.lines_in(gpa)` yields
each line as an `io::Result<String<Gpa>>`. With `use std::io::Write`,
`write(&mut w, "{x}")?` and `writeln(&mut w, "{x}")?` write formatted
text to a writer or a `File` (Rust's `write!`, `writeln!`),
`w.write_all(bytes)?` bytes. `env::args()` yields `&str`s
(`.collect_in(gpa)`), `env::var_in(name, gpa)` a `Result<String<Gpa>,
VarError>` (Rust's `env::var`), `env::current_dir_in(gpa)?`.
`Command::new_in(p, gpa)`, then `.arg(a)` and `.args(list)` (they chain:
`Command::new_in("echo", gpa).arg("hi").output()?`), `c.output()?`
(`status`, `stdout`, `stderr`), `c.status()?`, `c.spawn()?`;
`c.env_remove(name)`, and `c.foreground(true)`: while it waits, this
process ignores ^C (SIGINT) and ^\, which end the child (as a shell runs a
command).

```vole
use std::{fs, io};
use std::fs::File;
use std::io::{BufRead, BufReader, BufWriter, Write};
use std::process::Command;

fn run(gpa: Gpa) -> io::Result<()> {
    let path = "/tmp/vole-guide-files.txt";
    {
        let mut w = BufWriter::new(File::create(path)?);
        for i in 1..4 {
            writeln(&mut w, "line {i}")?;
        }
    }
    let mut r = BufReader::new(File::open(path)?);
    let mut line = String::new_in(gpa);
    let mut total = 0;
    while r.read_line(&mut line)? > 0 {
        total += 1;
    }
    println("{total} {} {}", line.lines().count(), fs::metadata(path)?.len());
    fs::remove_file(path)?;
    let mut c = Command::new_in("echo", gpa);
    c.arg("hi");
    let out = c.output()?;
    println("{} {}", out.status.success(), out.stdout.len());
    match File::open(path) {
        Ok(_) => println("still there"),
        Err(e) => println("{:?}", e.kind()),
    }
    Ok(())
}

fn main(gpa: Gpa) -> i32 {
    match run(gpa) {
        Ok(_) => 0,
        Err(e) => {
            eprintln("{e}");
            1
        }
    }
}
```
```out
3 3 21
true 3
NotFound
```
