# Command lines: std::cli (0.24)

`std::cli` parses a program's arguments: clap's builder, without derive.
A `Command` lists flags, options and positionals (and subcommands);
`parse` gives `Matches` or a `CliError`. `--help`, `-h` and (with a
version) `--version`, `-V` are built in. The design: docs/design/cli.md.

```text
use std::cli::{Arg, Command};
use std::env;

fn main(gpa: Gpa) -> i32 {
    let cmd = Command::new_in("grep", gpa).version("1.0").about("find lines")
        .arg(Arg::flag("count").short('c').help("print how many"))
        .arg(Arg::option("max").short('m').value_name("N").default("0"))
        .arg(Arg::positional("pattern").required())
        .arg(Arg::positional("file").multiple());
    let m = cmd.parse_or_exit(env::args());    // an error: printed, exit 2
    let max = match m.get_as::<i64>("max") { Ok(n) => n, Err(e) => cmd.exit(e) };
    for f in m.values("file") { .. }
    0
}
```

## Parsing and Matches

`cmd.parse(args)` takes any iterator of `str`, the program's name first
(`env::args()`, `line.split(' ')`, `v.iter()`); `parse_in(args, a)`
puts the Matches on allocator `a` (an arena). Accepted: `-v`, `-vvv`,
clusters `-vq`, `-ofile`, `-o file`, `-o=file`, `--out file`,
`--out=file`, `--` (the rest is positional), `-` (a positional). An
option takes the next argument even when it starts with `-` (`-n -5`).

```vole
use std::cli::{Arg, Command};

fn main(gpa: Gpa) -> i32 {
    let cmd = Command::new_in("tool", gpa)
        .arg(Arg::flag("verbose").short('v'))
        .arg(Arg::option("out").short('o').default("-"))
        .arg(Arg::option("jobs").short('j').default("1"))
        .arg(Arg::positional("file").multiple())
        .subcommand(Command::new_in("push", gpa).arg(Arg::flag("force").short('f')));
    let m = cmd.parse("tool -vv -ofile a b".split(' ')).unwrap();
    let jobs = m.get_as::<i64>("jobs").unwrap();
    println("{} {} {jobs} {}", m.count("verbose"), m.get("out").unwrap(), m.values("file").len());
    let p = cmd.parse("tool -j 4 push -f".split(' ')).unwrap();
    match p.subcommand() {
        Some((name, sub)) => println("{name} {}", sub.flag("force")),
        None => println("none"),
    }
    match cmd.parse("tool --outt x".split(' ')) {
        Ok(_) => println("ok"),
        Err(e) => print(cmd.render_in(e, gpa).as_slice()),
    }
    0
}
```
```out
2 file 1 2
push true
error: unknown option '--outt'
try: --out
usage: tool [options] [file]... [command]
```

- `m.flag(name)`: given (a default is not); `m.count(name)`: how many
  times; `m.get(name)`: the last value or the default, an
  `Option<str>`; `m.values(name)`: every value, a `[str]`;
  `m.get_as::<T>(name)`: parsed (`FromStr`), `Err(CliError)` naming the
  argument; `m.subcommand()`: `Option<(str, Matches)>`;
  `m.indices_of(name)` (0.25): each value's (or flag's) index among the
  arguments, for the order of different options (`-l m x.o -l z`). A
  name that is no Arg of that command panics.
- An Arg: `.short('x')`, `.long("s")` (its name by default),
  `.help(..)`, `.value_name("FILE")` (a positional's too, 0.25),
  `.default(..)`, `.required()`, `.multiple()` (a positional taking the
  rest), `.choices("fast|slow")` (0.25: another value is an error,
  `try: --mode <fast|slow>`). Options may repeat.
- (0.25) `Command::new_in(name, a)` takes any allocator, an arena too
  (`arena_scope(gpa, |a| ..)`: nothing on the Gpa). A program's own
  check fails in std::cli's form: `cmd.exit(CliError::custom("-b and -t
  together", "-b"))`; `e.letter()`: the unknown letter of a cluster.

## Subcommands, aliases, values (0.25.2)

```vole
use std::cli::{Arg, Command};

fn main(gpa: Gpa) -> i32 {
    let cmd = Command::new_in("vc", gpa).subcommand_required()
        .arg(Arg::option("root").short('R').global())
        .arg(Arg::option("color").alias("colour").hide())
        .arg(Arg::option("stats").default_missing("all"))
        .arg(Arg::option("overlay").num_values(2).value_name("PATH COPY"))
        .subcommand(Command::new_in("remove", gpa).alias("rm")
            .arg(Arg::flag("binary").short('b').conflicts_with("text"))
            .arg(Arg::flag("text").short('t'))
            .arg(Arg::positional("expr").multiple().allow_hyphen_values())
            .arg(Arg::positional("args").multiple().last()));
    let m = cmd.parse("vc --stats --overlay a b rm -R d -x -- -y".split(' ')).unwrap();
    let (name, sub) = m.subcommand().unwrap();
    println("{name} {} {} {}", m.get("stats").unwrap(), m.values("overlay").len(),
        sub.get("root").unwrap());
    println("{} {}", sub.values("expr")[0], sub.values("args")[0]);
    let lines: [str; 2] = ["vc", "vc rm -b -t"];
    for line in lines {
        match cmd.parse(line.split(' ')) {
            Ok(_) => println("ok"),
            Err(e) => print(cmd.render_in(e, gpa).as_slice()),
        }
    }
    0
}
```
```out
remove all 2 d
-x -y
error: missing command for 'vc'
try: vc remove
usage: vc [options] <command>
error: '-t' cannot be used with '-b'
try: drop '-t' (or '-b')
usage: vc remove [options] [expr]... [-- args]...
```

- `.global()`: a flag or option of a command that its subcommands
  accept too, before or after their names (`vc -R d rm`, `vc rm -R d`);
  every level's Matches reads it.
- `.alias(s)`: another long name (an Arg) or name (a Command), called
  again for more; `.hide()`: accepted, not in the help (a deprecated
  spelling). The did-you-mean measures aliases, suggests the own name.
- `.num_values(n)`: n values each time (`--overlay PATH COPY`; fewer:
  a MissingValue error). `.default_missing(s)`: an optional value,
  `--stats` gives s, only `--stats=x` gives x.
- `.allow_hyphen_values()`: a positional takes a word starting with `-`
  that is no option (`grep '-> bool'`). `.last()`: a positional of the
  words after `--` (`probe F:L EXPR... -- ARGS...`).
- `.conflicts_with(name)`: both given is an ArgumentConflict error;
  `Command::subcommand_required()`: none given is MissingSubcommand
  (`try:` names the commands). Exit code 2, as every error.

## Help and errors

`cmd.exit(e)` prints a CliError and exits with `e.exit_code()`: the
help or version on stdout (0), else on stderr (2) the error, a `try:`
line (the nearest option or command by edit distance, or the fix) and
the usage line. `cmd.render_in(e, a)` and `cmd.help_in(a)` give that
text as a `Buf`; `.width(n)` wraps the help (80). Parsing does no io
(`query effects`): only `exit` and `parse_or_exit` print.
