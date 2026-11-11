## 0.26.3: f-strings are removed. Each file with one has error
## syntax.fstring once, at its first f-string, with how many it has; the
## f-strings are still read, so the rest is checked (the type error
## after them), and the try: line runs `fix --only fstring`, which
## still reads them and rewrites them all.
$ check
main.vl:8:13: error[syntax.fstring] f-strings are removed (0.26.3): a format string takes the values as arguments (2 in this file, the first here) | help: a name stays in its hole and an expression goes after the literal: `println("{n} {}", v.len())`; elsewhere `format_args("..", args)` | try: volec fix --only fstring --keep-braces main.vl
main.vl:11:18: error[type error] expected 'i64', got 'bool'
util.vl:2:13: error[syntax.fstring] f-strings are removed (0.26.3): a format string takes the values as arguments | help: a name stays in its hole and an expression goes after the literal: `println("{n} {}", v.len())`; elsewhere `format_args("..", args)` | try: volec fix --only fstring --keep-braces main.vl
[exit 1]
$ explain syntax.fstring
syntax.fstring: error (from 0.26.3)
An f-string, `f"x = {x}, len {v.len()}"` (0.15 to 0.26.2), is removed: a format string is Rust's, a plain literal that is the first argument of println, print, eprintln, format_in, panic, write, writeln, a contract's `else` or format_args (0.26.2). A hole names a local, a parameter, a const or a static, or takes the next argument, `{}`; an expression is an argument after the literal. The error comes once per file, at its first f-string, with how many the file has.
fix: Write the plain literal: a name hole stays, another hole becomes `{}` (`{:spec}`) and its expression an argument after the literal, in order. `volec fix --only fstring --keep-braces` (the try: line) rewrites every f-string of the program so.
example:
    fn main() {
        let v = [1, 2, 3];
        let n = 3;
        println(f"n = {n}, sum {v[0] + v[1]}");   // now: println("n = {n}, sum {}", v[0] + v[1]);
    }
    
    main.vl:4:13: error[syntax.fstring] f-strings are removed (0.26.3): a format string takes the values as arguments
      help: a name stays in its hole and an expression goes after the literal: `println("{n} {}", v.len())`; elsewhere `format_args("..", args)`
      try: volec fix --only fstring --keep-braces main.vl
$ fix --only fstring --keep-braces
fixed 3 f-strings and format literals	2 files	+3 -3 lines
% cat main.vl util.vl
// f-strings are removed (0.26.3, tests/refactor/fstring0263.t): error
// syntax.fstring once per file, at its first, with how many it has.
mod util;

fn main() {
    let n = 3;
    let v = [1, 2, 3];
    println("n = {n}");
    println("sum {}, {n:>4}", v[0] + v[1]);
    util::show(n);
    let z: i64 = true;
}
pub fn show(n: i64) {
    println("{n} items");
}
$ check
main.vl:11:18: error[type error] expected 'i64', got 'bool'
[exit 1]
