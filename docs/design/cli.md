# std::cli: command lines (0.24)

A small, clap-like argument parser in std, with a builder and no derive.
The guide is `volec guide cli`; the code is compiler/std/cli.vl.

## The API

```text
Command::new_in(name, gpa)  .about(s) .version(s) .width(n) .arg(Arg) .subcommand(Command)
Arg::flag(name) | Arg::option(name) | Arg::positional(name)
    .short('x') .long(s) .help(s) .value_name(s) .default(s) .required() .multiple()
cmd.parse(args) -> Result<Matches, CliError>         args: any Iterator<Item = str>, argv[0] first
cmd.parse_in(args, a) -> Result<Matches<A>, CliError>
cmd.parse_or_exit(args) -> Matches                    an error: cmd.exit(e)
cmd.exit(e) -> !                                      prints, exits e.exit_code()
cmd.help_in(a), cmd.render_in(e, a) -> Buf<A>
m.flag(n) m.count(n) m.get(n) -> Option<str> m.values(n) -> [str]
m.get_as::<T: FromStr>(n) -> Result<T, CliError> m.subcommand() -> Option<(str, Matches)>
m.indices_of(n) -> [i64]                              (0.25) each value's (flag's) argument index
```

## Decisions

1. **Allocation is explicit.** `Command::new_in(name, gpa)` (std's `_in`
   form; there is no `Command::new` that allocates behind the caller's
   back). `Arg` is a plain value (views of its strings), built without
   an allocator. `parse` puts the Matches on the Command's Gpa,
   `parse_in` on any allocator, an arena included. The help and error
   text `exit` prints is built in a scoped arena and freed before the
   exit.
2. **The tree is flat.** Every command of the tree is one entry of
   `cmds` (with its parent's index) and every argument one entry of
   `args` (with its command's index); `.subcommand(c)` appends c's
   entries, renumbered. No recursive type, no `Box`.
3. **Matches are views.** Values are `str`s viewing the arguments (and
   defaults viewing the definition); nothing is copied. Each level (the
   command, then each subcommand on the line) has a slot per argument;
   after parsing, each slot's values are contiguous, so `values` is a
   slice. `subcommand()` copies the small vectors for the next level.
4. **Errors are values, printing is separate.** `CliError` holds what
   it is about (the kind, the text as given, the argument, a hint);
   Display gives `error: ...` and `try: ...`; `cmd.render_in` adds the
   usage line of the command concerned. `--help` and `--version` are
   CliErrors too (`exit_code` 0), so `parse` never prints. Effects:
   `parse` is `alloc(Gpa) panic diverge` (no io, no global; `query
   effects Command::parse`), only `exit` and `parse_or_exit` do io.
5. **The try line is exact.** An unknown option or command: the nearest
   by edit distance (with swaps: `--nmae` is 1 from `--name`; within a
   third of the word's length), else `--help`; `-verbose` suggests
   `--verbose`. A missing value or argument, a value given to a flag, a
   value that does not parse: the argument's spelling (`--out <FILE>`).
   Exit code 2, as clap's.
6. **Simple rules.** An option takes the next argument as its value even
   when it starts with `-` (negative numbers); options may repeat (`get`:
   the last, `values`: all); a positional takes one value, `.multiple()`
   all those left; a subcommand's name ends its parent's arguments.
   A required argument that is missing is reported at the end, so a
   later `--help` still prints the help.
7. **Gated.** Every section of std::cli is lazy behind the word `cli`
   (index.awk): a program that does not name it reads none of it.

## 0.25

`m.indices_of(name)`, clap's: the index among the arguments (the
program's name is 0) of each value, or of each time a flag was given; a
default has none. volec's own command line (compiler/src/cli/, on
v0.24.0's std::cli) needs the order of different options' values (`-l`,
`-L` and objects are linked in the order given; `edit patch`'s pairs
after `--in NAME` are NAME's); until 0.26 builds it, it finds a value's
place by the argv element the value views.

What volec's layer makes up for (compiler/src/cli/mod.vl), candidates
for later: a single-dash long option (`-framework`), an option whose
value is optional (`--stats`, `--stats=functions`), an option with two
values (`--overlay PATH COPY`), values and positionals starting with
`-` (clap's `allow_hyphen_values`: `query grep '-> bool'`), and parsing
on after an error (the tools report the NAMEs given with the error).

## Not in 0.24

Value enums (`possible_values`), `env` defaults, argument groups and
conflicts, a required subcommand, `--no-flag` negation, aliases, the
terminal's width (`.width(n)` sets it), and typed errors from `get_as`
that say why the value did not parse (the error names the argument and
the value).
