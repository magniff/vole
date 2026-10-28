# std::cli: command lines (0.24)

A small, clap-like argument parser in std, with a builder and no derive.
The guide is `volec guide cli`; the code is compiler/std/cli.vl.

## The API

```text
Command::new_in(name, gpa)  .about(s) .version(s) .width(n) .arg(Arg) .subcommand(Command)
Arg::flag(name) | Arg::option(name) | Arg::positional(name)
    .short('x') .long(s) .help(s) .value_name(s) .default(s) .required() .multiple()
    .choices(s)                                       (0.25) "fast|slow"
    .global() .alias(s) .hide() .num_values(n) .default_missing(s)
    .allow_hyphen_values() .last() .conflicts_with(name)          (0.25.2)
Command::new_in(..) .alias(s) .hide() .subcommand_required()      (0.25.2)
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

`Command<A: Allocator = Gpa>`: `Command::new_in(name, a)` takes any
allocator (an arena: a program under --check-alloc keeps its blocks'
numbers); `exit` builds its text on it. `Arg::choices("fast|slow")`:
another value is InvalidValue, whose try: line names them (`--mode
<fast|slow>`), as the help does. `CliError::custom(message, try)`
(kind Custom): a program's own check, printed as std::cli's errors are.
`e.letter()`: the unknown letter of a cluster (`x` of `-vx`). A
positional's `value_name` is its name in the usage and errors.

`m.indices_of(name)`, clap's: the index among the arguments (the
program's name is 0) of each value, or of each time a flag was given; a
default has none. volec's own command line (compiler/src/cli/, on
0.25.1's std::cli, whose API is 0.24's) needs the order of different options' values (`-l`,
`-L` and objects are linked in the order given; `edit patch`'s pairs
after `--in NAME` are NAME's); until 0.26 builds it, it finds a value's
place by the argv element the value views.

What volec's layer makes up for (compiler/src/cli/mod.vl), candidates
for later: a single-dash long option (`-framework`) and parsing on after
an error (the tools report the NAMEs given with the error); 0.25.2 has
the rest (an optional value, two values, values starting with `-`).

Still to do (the examples' migration, cli-ex, found these too): env
defaults, `--no-flag`, the terminal's width (0.25.2 did the rest).

## 0.25.2

Clap's names for what volec's own command line needed (its layer,
compiler/src/cli/, can drop them once a release has them):

- `Arg::global()`: a flag or option of a command that its subcommands
  accept at any depth, before or after their names (`prog --root D sub`,
  `prog sub --root D`). It has one slot, on its command's level; Matches
  of every level below find it there (`find_at`: the level's own
  arguments first, then the global ones above). Its default and its
  being required are settled at the end of the line, an error about the
  last command; a subcommand's help lists it.
- `Arg::alias(s)`, `Command::alias(s)`: other names, any number (each
  call one, or several as `"a|b"`; up to 4 calls: an Arg stays a plain
  value with no allocation). The did-you-mean measures them and suggests
  the own name; `m.subcommand()` gives a command's own name.
- `Arg::hide()`, `Command::hide()`: accepted, not in the help, the usage
  or the did-you-mean (deprecated spellings).
- `Arg::num_values(n)`: `--overlay PATH COPY`, n values each time
  (`--overlay=PATH COPY` too), `values` in order; fewer at the end is
  MissingValue. `.value_name("PATH COPY")` names each in the help.
- `Arg::default_missing(s)`: an optional value, `--stats` gives s and
  only the `=` form gives one (`--stats=functions`, `-s=x`; `-sq` is
  `-s` then `-q`). The help writes `--stats[=<STATS>]`.
- `Arg::allow_hyphen_values()`: a positional so marked takes a word
  starting with `-` that is no option of the command (its own, the
  global ones above, `-h`, `--help`): `grep '-> bool'`. An option takes
  its next word anyway (decision 6).
- `Arg::last()`: a positional of the words after `--` only: `probe
  FILE:LINE EXPR... -- ARGS...`. Other positionals skip it; usage `[--
  args]...`.
- `Command::subcommand_required()`: no subcommand is MissingSubcommand,
  exit code 2; `render_in` names the visible subcommands, `try: prog
  <add|rm>` (one: `prog add`; long lists: `prog --help`), and the usage
  writes `<command>`.
- `Arg::conflicts_with(name)` (`"a|b"`: several): both given, either
  way round, is ArgumentConflict, exit code 2, both as written, the
  later first: `error: '-t' cannot be used with '-b'`, `try: drop '-t'
  (or '-b')`.
- The commands' table of a help was already one aligned line each, name
  then about; hidden ones are left out.

volec's own command line is on std::cli in 0.25.2, every command: a
build's options are one Command (compiler/src/cli/build.vl), `query`'s
another (cli/query.vl), and each other command lists its options in a
table read as events in argv's order (cli/events.vl: the flags, values,
words and errors, so that a command keeps its old messages, try: lines
and exit statuses; tools/cli-compat.py compares two volecs on the
transcripts, the docs' command lines and some 300 bad inputs). The
compiler is built by the previous release, so it uses 0.25.1's API;
the layer's rewrites (`--overlay PATH COPY`, `--stats[=F]`, dash words,
the words after probe's `--`) become 0.25.2's `num_values`,
`default_missing`, `allow_hyphen_values` and `last` when 0.26 builds
it. Two changes for the better: `--name=value` is taken wherever `--name
value` is, and `--` ends the options of every command.

Matches now keeps one vector of pairs (slot, argument index) while
parsing and the indices by slot after it, in place of 0.25's three: a
program under --check-alloc numbers its blocks as with 0.25.1's std::cli
(examples/allocators/check-alloc).

## Not in 0.24

Value enums (`possible_values`; 0.25: `choices`), `env` defaults,
argument groups and conflicts (0.25.2: `conflicts_with`), a required
subcommand (0.25.2), `--no-flag` negation, aliases (0.25.2), the
terminal's width (`.width(n)` sets it), and typed errors from `get_as`
that say why the value did not parse (the error names the argument and
the value).
