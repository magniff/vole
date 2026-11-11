# 18. Project: a command-line tool

This last chapter puts the book together in one program you might
actually use. We'll take the word counter that has been growing since
chapter 7 and turn it into `tally`, a small text-statistics tool in the
spirit of Unix's `wc`: it counts the lines, words and bytes of files,
and can list their most common words.

On the way you'll use most of what the earlier chapters taught:
modules, `std::cli` for the command line, borrowed text, an arena, a
`Result`-based error type, effects, contracts, tests and the tools. By
the end you'll have a program of about 280 lines in three files, with
tests, and a feel for how to structure a small real program on your
own.

## The plan

Here's what `tally` will do:

```text
usage: tally [options] [file]...
  -w, --words        count only words (default: lines, words, bytes)
  -t, --top N        print the N most common words
  -i, --ignore-case  fold case before counting
  -h, --help         this help
```

`tally notes.txt diary.txt` prints a line of counts for each file and
a total, as `wc` does. With `-t 3`, it adds a table of the three most
common words. With no files, it reads its standard input. A file that
can't be read is an error on stderr and exit status 1; a mistake on
the command line gets a message saying what to type instead, and exit
status 2.

The program keeps chapter 11's three files, each with one job:

- `main.vl` reads the command line and the files, and decides what to
  print;
- `count.vl` counts: it takes text and returns numbers, and does no
  input or output at all;
- `report.vl` formats the numbers.

The rule for `count.vl` is the important one. Code that only computes
is the easiest to test, since a test just calls it and looks at the
result, and it can't be broken by someone adding a stray `println`. We'll
have the compiler hold it to that.

## Step 1: arguments with std::cli

Chapter 11's word counter took its files from `env::args()` and the
number of words to show from the `WC_TOP` environment variable. That
works, but a real tool has options, a `--help`, and useful messages
when you get them wrong. That's what `std::cli` is for.

Here's chapter 11's program moved onto it. Only `main.vl` changes:

```vole main.vl
// tally: the most common words in the files named on the command line.
mod count;
mod report;

use std::{env, fs, io};
use std::cli::{Arg, Command, Matches};
use std::collections::HashMap;

fn run(m: &Matches<Gpa>, n: usize, gpa: Gpa) -> io::Result<()> {
    let mut counts: HashMap<String<Gpa>, i64, Gpa> = HashMap::new_in(gpa);
    for path in m.values("file") {
        let text = fs::read_to_string_in(path, gpa)?;
        count::add_words(&mut counts, &text, gpa);
    }
    let top = report::top(&counts, n, gpa);
    report::print_table(&top);
    Ok(())
}

fn main(gpa: Gpa) -> i32 {
    let cmd = Command::new_in("tally", gpa)
        .about("the most common words of files")
        .arg(Arg::option("top").short('t').value_name("N").default("5").help("how many words"))
        .arg(Arg::positional("file").multiple().help("the files to read"));
    let m = cmd.parse_or_exit(env::args());
    let n = match m.get_as::<usize>("top") {
        Ok(n) => n,
        Err(e) => cmd.exit(e),
    };
    match run(&m, n, gpa) {
        Ok(()) => 0,
        Err(e) => {
            eprintln("tally: {e}");
            1
        }
    }
}
```

`count.vl` and `report.vl` are chapter 11's, unchanged:

```vole count.vl
// Counting the words of a text.
use std::collections::HashMap;

// Letters, digits and apostrophes are parts of words. So is every
// byte of a non-ASCII character (0x80 and up), so "café" stays whole.
fn is_word_byte(b: u8) -> bool {
    match b {
        b'a'..=b'z' | b'A'..=b'Z' | b'0'..=b'9' | b'\'' => true,
        0x80..=0xff => true,
        _ => false,
    }
}

// The word without the punctuation around it: "end!" is "end".
fn trim_punct(word: &str) -> &str {
    let bytes = word.as_bytes();
    let mut start = 0;
    let mut end = bytes.len();
    while start < end && !is_word_byte(bytes[start]) {
        start += 1;
    }
    while end > start && !is_word_byte(bytes[end - 1]) {
        end -= 1;
    }
    &word[start..end]
}

// Adds the words of text to counts, lowercased.
pub fn add_words(counts: &mut HashMap<String<Gpa>, i64, Gpa>, text: &str, gpa: Gpa) {
    for word in text.split_whitespace() {
        let w = trim_punct(word);
        if w.is_empty() {
            continue;
        }
        *counts.entry(w.to_lowercase_in(gpa)).or_insert(0) += 1;
    }
}
```

```vole report.vl
// The table of the most common words.

use std::collections::HashMap;

pub fn top(counts: &HashMap<String<Gpa>, i64, Gpa>, n: usize, gpa: Gpa) -> Vec<(String<Gpa>, i64),
    Gpa> {
    let mut pairs: Vec<(String<Gpa>, i64), Gpa> = Vec::new_in(gpa);
    for (word, k) in counts {
        pairs.push((word.clone(), *k));
    }
    pairs.sort_by(|a, b| b.1.cmp(&a.1).then_with(|| a.0.cmp(&b.0)));
    pairs.truncate(n);
    pairs
}

pub fn print_table(rows: &[(String<Gpa>, i64)]) {
    for row in rows {
        println("{:<12}{:>5}", row.0, row.1);
    }
}
```

Let's try it on a small file:

```console
$ printf 'The cat sat on the mat.\nThe dog sat on the cat.\n' > notes.txt
$ volec main.vl -o tally
ok: built tally
$ ./tally -t 3 notes.txt
the             4
cat             2
on              2
```

### Describing the command line

`Command::new_in("tally", gpa)` starts a description of the program's
command line, and each `.arg(...)` adds one thing it accepts:

- `Arg::option("top")` is an option that takes a value: `--top 3`, or
  `--top=3`. `.short('t')` adds the one-letter form, `-t 3`;
  `.value_name("N")` is what the help calls the value;
  `.default("5")` is used when the option isn't given; `.help(..)` is
  its line in the help.
- `Arg::positional("file")` is an argument without a dash in front, and
  `.multiple()` lets it take all the rest: any number of files.

Each method returns the changed `Command` or `Arg`, so the calls chain.
Once the description is complete, `cmd.parse_or_exit(env::args())`
reads the actual arguments. It returns a `Matches`, the parsed
command line, or, if the arguments don't fit the description, prints a
message and exits.

From the `Matches`, `m.values("file")` gives the positional values, as
a slice of `&str`, and `m.get_as::<usize>("top")` parses an option's value
as a number. Parsing a number can fail, so it returns a `Result`, and on
an `Err` we hand the error back to `cmd.exit(e)`, which prints it the
same way `parse_or_exit` would.

Notice that `run` takes the `Matches`, not the arguments: by the time
`run` starts, the command line is known to be well-formed.

### Help and errors for free

`--help` (or `-h`) is built in, written from the description:

```console
$ ./tally --help
tally
the most common words of files

usage: tally [options] [file]...

arguments:
  <file>...      the files to read

options:
  -t, --top <N>  how many words [default: 5]
  -h, --help     print this help
```

And here's what a user sees for a typo, a value that isn't a number, and
a file that isn't there:

```console
$ ./tally --tpo 3 notes.txt
error: unknown option '--tpo'
try: --top
usage: tally [options] [file]...
$ echo $?
2
$ ./tally -t many notes.txt
error: invalid value 'many' for '--top <N>'
try: --top <N>
usage: tally [options] [file]...
$ echo $?
2
$ ./tally nope.txt
tally: No such file or directory (os error 2)
$ echo $?
1
```

A misspelled option gets the nearest real one on a `try:` line, the
same way the compiler's own errors do, and the usage line. Command-line
mistakes exit with status 2, by convention, so that scripts can tell
"you called me wrong" from "I failed": the missing file is our own
error, from `run`, with status 1.

`std::cli` also does subcommands (as in `git commit`), counted flags
(`-vvv`), and `--version`. `volec guide cli` has the rest.

## Step 2: the whole tool

Now let's write the rest: the line, word and byte counts, the `-w` and
`-i` options, standard input, and an error type of our own. Here is the
complete program, one file at a time.

### Counting

`count.vl` is new. Start with it, because the others depend on it:

```vole count.vl
// Counting: the lines, words and bytes of a text, and how often each
// word occurs. Nothing here reads or writes: the functions take text and
// give back numbers, which makes them easy to test.

use std::alloc::Allocator;
use std::collections::HashMap;

pub struct Counts {
    pub lines: usize,
    pub words: usize,
    pub bytes: usize,
}

impl Counts {
    pub fn add(&mut self, other: &Counts) {
        self.lines += other.lines;
        self.words += other.words;
        self.bytes += other.bytes;
    }
}

// The lines, words and bytes of text, as wc counts them: a line ends with
// a newline, a word is a run of anything but spaces.
#[no_io]
pub fn count(text: &str) -> Counts {
    let mut lines: usize = 0;
    for b in text.as_bytes() {
        if *b == b'\n' {
            lines += 1;
        }
    }
    Counts { lines, words: text.split_whitespace().count(), bytes: text.len() }
}

// Adds one to freq for each word of text, without the punctuation around
// it. The keys borrow from text: no word is copied.
#[no_io]
pub fn add_words<'a, A: Allocator>(freq: &mut HashMap<&'a str, i64, A>, text: &'a str) {
    for word in text.split_whitespace() {
        let w = trim_punct(word);
        if !w.is_empty() {
            *freq.entry(w).or_insert(0) += 1;
        }
    }
}

// Chapter 7's: letters, digits and apostrophes are parts of words, and
// so is every byte of a non-ASCII character, so "café" stays whole.
fn is_word_byte(b: u8) -> bool {
    match b {
        b'a'..=b'z' | b'A'..=b'Z' | b'0'..=b'9' | b'\'' => true,
        0x80..=0xff => true,
        _ => false,
    }
}

// Chapter 7's: the word without the punctuation around it.
fn trim_punct(word: &str) -> &str {
    let bytes = word.as_bytes();
    let mut start = 0;
    let mut end = bytes.len();
    while start < end && !is_word_byte(bytes[start]) {
        start += 1;
    }
    while end > start && !is_word_byte(bytes[end - 1]) {
        end -= 1;
    }
    &word[start..end]
}

#[test]
fn counts_lines_words_bytes() {
    let c = count("the cat\nsat\n");
    assert_eq(&c.lines, &2);
    assert_eq(&c.words, &3);
    assert_eq(&c.bytes, &12);
}

#[test]
fn trims_punctuation(gpa: Gpa) {
    let mut freq: HashMap<&str, i64, Gpa> = HashMap::new_in(gpa);
    add_words(&mut freq, "(the) end. The end!");
    assert_eq(&freq["end"], &2);
    assert_eq(&freq["the"], &1);
    assert_eq(&freq.len(), &3);
}

// Every word is counted once: the counts add up to the number of words.
#[property]
fn counts_add_up(bytes: Vec<u8, Gpa>, gpa: Gpa) {
    let pieces = ["a", "b", " ", "\n"];
    let mut text = String::new_in(gpa);
    for b in &bytes {
        text.push_str(pieces[(*b % 4) as usize]);
    }
    let mut freq: HashMap<&str, i64, Gpa> = HashMap::new_in(gpa);
    add_words(&mut freq, &text);
    let mut total = 0;
    for (_, k) in &freq {
        total += *k;
    }
    assert_eq(&total, &(count(&text).words as i64));
}
```

`count` counts a text's lines (its newlines), words (runs of
non-space) and bytes, the three numbers `wc` prints, and returns them
in a `Counts`. `add_words` counts each word. Both are marked
`#[no_io]` (chapter 12): the compiler checks that nothing they do, or
call, reads or writes anything. The functions marked `#[test]` and
`#[property]` at the end are the tests; we'll come back to them.

The interesting part is `add_words`'s map. Chapter 11's version made a
lowercased `String` for every word it saw, then stored it as a key:
a new allocation for each of the thousands of words in a file. This
one doesn't copy anything. The keys of `freq` are `&str`s that borrow
from `text` (chapter 4): each key is just the address and length of the
word in the text that's already in memory.

That's only safe if the text outlives the map, and the compiler checks
exactly that: a reference can't be used after what it points to is gone
or has changed. The lifetime `'a` in `add_words`'s signature is that
promise: the keys are good for as long as the text is. If `main` dropped
the text while the map was still around, the program wouldn't compile. You get the speed of pointers into a
buffer, the way a C program would do it, without the risk of a pointer to memory that is gone.

`trim_punct` and `is_word_byte` are chapter 7's, unchanged.
`trim_punct` borrows too: `&word[start..end]` is a slice of
`word`, so "(end)." becomes "end" without copying. And `add_words` is
generic over the map's allocator (`A: Allocator`), so it works with a
map on any allocator: in the tests, the `Gpa`; in `main.vl`, an arena.

### Reporting

`report.vl` prints the counts and the table:

```vole report.vl
// The report: the counts, and a table of the most common words.

use std::collections::HashMap;

use crate::count::Counts;

// One line of counts, as wc prints them.
pub fn print_counts(c: &Counts, name: &str, words_only: bool) {
    if words_only {
        println("{:>8} {name}", c.words);
    } else {
        println("{:>8} {:>8} {:>8} {name}", c.lines, c.words, c.bytes);
    }
}

// The n most common words, most common first; as common, alphabetically.
pub fn top(counts: &HashMap<String<Gpa>, i64, Gpa>, n: usize, gpa: Gpa) -> Vec<(String<Gpa>, i64),
    Gpa> {
    let mut pairs: Vec<(String<Gpa>, i64), Gpa> = Vec::new_in(gpa);
    for (word, k) in counts {
        pairs.push((word.clone(), *k));
    }
    pairs.sort_by(|a, b| b.1.cmp(&a.1).then_with(|| a.0.cmp(&b.0)));
    pairs.truncate(n);
    pairs
}

// The width of the word column: the widest word, and at least 4.
fn word_width(rows: &[(String<Gpa>, i64)]) -> usize {
    let mut w = 4;
    for row in rows {
        if row.0.width() > w {
            w = row.0.width();
        }
    }
    w
}

// How many spaces after word, to fill a column w wide.
fn padding(word: &str, w: usize) -> usize
    requires word.width() <= w
{
    w - word.width()
}

// The rows as a table, the counts lined up however wide the words are.
pub fn print_table(rows: &[(String<Gpa>, i64)]) {
    let w = word_width(rows);
    for row in rows {
        print("{}", row.0);
        for _ in 0..padding(&row.0, w) {
            print(" ");
        }
        println("{:>6}", row.1);
    }
}
```

`top` is chapter 11's, and so is its sort: by count, highest first,
and alphabetically among words with the same count, so the output is
the same on every run. (A `HashMap`'s order is unspecified, so without
the second rule, words with the same count could come out in any
order.)

The table is new. Chapter 11 gave the word column a fixed width of
12, which breaks for a longer word. Here, `word_width` finds the
widest word first, and `print_table` pads each word to that width.
Width, not length: `width()` is how many columns the text takes in a
terminal, which for a word like "café" is less than its number of bytes
(chapter 7).

`padding` has a contract: `requires word.width() <= w`. If a later
change ever computed the width wrong, the program would stop with a
message naming the call, instead of printing a ragged table, or
subtracting below zero. It costs one comparison per row.

### The program

Last, `main.vl`, which ties it together:

```vole main.vl
// tally: count the lines, words and bytes of files, and their most
// common words.
mod count;
mod report;

use std::{env, fmt, fs, io};
use std::alloc::{Allocator, arena_scope};
use std::cli::{Arg, Command, Matches};
use std::collections::HashMap;
use std::fmt::{Display, Formatter};
use std::io::Read;
use std::string::FromUtf8Error;

use crate::count::Counts;

// What can go wrong.
enum TallyError<A: Allocator> {
    // a file can't be read
    File(String<A>, io::Error),
    // stdin can't be read
    Stdin(io::Error),
    // stdin isn't UTF-8 text
    NotText,
}

impl From<io::Error> for TallyError<Gpa> {
    fn from(e: io::Error) -> TallyError<Gpa> {
        TallyError::Stdin(e)
    }
}

impl From<FromUtf8Error<Gpa>> for TallyError<Gpa> {
    fn from(_e: FromUtf8Error<Gpa>) -> TallyError<Gpa> {
        TallyError::NotText
    }
}

impl Display for TallyError<Gpa> {
    fn fmt(&self, f: &mut Formatter) -> fmt::Result {
        match self {
            TallyError::File(path, e) => write(f, "{path}: {e}"),
            TallyError::Stdin(e) => write(f, "stdin: {e}"),
            TallyError::NotText => write(f, "the input is not UTF-8 text"),
        }
    }
}

// Counts one text, and adds its words to totals. The text's own word
// counts live in an arena, freed all at once when the text is done.
fn tally(text: &str, fold: bool, totals: &mut HashMap<String<Gpa>, i64, Gpa>, gpa: Gpa) -> Counts {
    arena_scope(&gpa, |a| {
        // the words, lowercased if asked: in the arena
        let words = if fold {
            text.to_lowercase_in(a)
        } else {
            String::from_in(text, a)
        };
        let mut freq = HashMap::new_in(a);
        count::add_words(&mut freq, &words);
        for (word, k) in &freq {
            *totals.entry(String::from_in(word, gpa)).or_insert(0) += *k;
        }
    });
    count::count(text)
}

fn run(m: &Matches<Gpa>, top: usize, gpa: Gpa) -> Result<(), TallyError<Gpa>> {
    let fold = m.flag("ignore-case");
    let words_only = m.flag("words");
    let mut totals: HashMap<String<Gpa>, i64, Gpa> = HashMap::new_in(gpa);
    let files = m.values("file");
    if files.is_empty() {
        let mut bytes: Vec<u8, Gpa> = Vec::new_in(gpa);
        io::stdin().read_to_end(&mut bytes)?;
        let text = String::from_utf8(bytes)?;
        report::print_counts(&tally(&text, fold, &mut totals, gpa), "", words_only);
    }
    let mut all = Counts { lines: 0, words: 0, bytes: 0 };
    for path in files {
        let text = match fs::read_to_string_in(path, gpa) {
            Ok(t) => t,
            Err(e) => return Err(TallyError::File(String::from_in(path, gpa), e)),
        };
        let c = tally(&text, fold, &mut totals, gpa);
        report::print_counts(&c, path, words_only);
        all.add(&c);
    }
    if files.len() > 1 {
        report::print_counts(&all, "total", words_only);
    }
    if top > 0 {
        let rows = report::top(&totals, top, gpa);
        println("");
        report::print_table(&rows);
    }
    Ok(())
}

fn main(gpa: Gpa) -> i32 {
    let cmd = Command::new_in("tally", gpa)
        .about("count the lines, words and bytes of files")
        .arg(Arg::flag("words").short('w').help("count only words"))
        .arg(Arg::option("top")
            .short('t')
            .value_name("N")
            .default("0")
            .help("print the N most common words"))
        .arg(Arg::flag("ignore-case").short('i').help("fold case before counting"))
        .arg(Arg::positional("file").multiple().help("the files to read (none: stdin)"));
    let m = cmd.parse_or_exit(env::args());
    let top = match m.get_as::<usize>("top") {
        Ok(n) => n,
        Err(e) => cmd.exit(e),
    };
    match run(&m, top, gpa) {
        Ok(()) => 0,
        Err(e) => {
            eprintln("tally: {e}");
            1
        }
    }
}
```

There are two new ideas here: an arena, and an error type.

### An arena per file

Look at `tally`. Counting a file's words needs memory: a copy of its
text (lowercased, when `-i` is given), and the map of its words, whose
keys borrow from that copy. All of that is needed only while the file
is being counted.
Afterwards, the words and their counts are added to `totals`, and
nothing else is kept.

That's the case an arena is for (chapter 8). `arena_scope(&gpa, |a| {
... })` makes an arena, runs the closure with it, and frees everything
allocated from it, all at once, when the closure returns. Inside, the
copy and the map come from `a`. The compiler makes sure nothing
allocated from the arena escapes the closure: the map's type names
the arena, and returning it, or storing it in `totals`, would be an
error. What does leave is copied out explicitly:
`String::from_in(word, gpa)` makes a `String` on the `Gpa` for each
word added to `totals`.

So however many files you give `tally`, the memory for one file's
scratch work is freed before the next file starts, without a single
`free` in the code.

### Errors

`run` returns a `Result<(), TallyError>`, an enum of the things that
can go wrong. Each variant carries what the message will need: the
file's name and the `io::Error`, for a file that can't be read.
`impl Display` turns each variant into a message, and `main` prints it
after `tally:` and exits with status 1. This is the `run`/`main` shape
chapter 11 used, with an error type that says more than an
`io::Error` alone.

The two `From` impls let `?` convert errors (chapter 6). In `run`, the
lines that read standard input use `?` twice:

```vole skip
        io::stdin().read_to_end(&mut bytes)?;
        let text = String::from_utf8(bytes)?;
```

`read_to_end` can fail with an `io::Error`, and `String::from_utf8`,
which checks that the bytes are UTF-8 text, with a `FromUtf8Error`. `?`
turns each into a `TallyError` through its `From` impl and returns it.
Reading a file doesn't use `?`,
because the error needs the file's name added, so it builds the
`TallyError::File` by hand.

### Running it

```console
$ printf 'The cat sat on the mat.\nThe dog sat on the cat.\n' > notes.txt
$ printf 'the end\n' > end.txt
$ volec main.vl -o tally
ok: built tally
$ ./tally notes.txt end.txt
       2       12       48 notes.txt
       1        2        8 end.txt
       3       14       56 total
$ ./tally -t 3 notes.txt
       2       12       48 notes.txt

The      2
cat      2
on       2
$ ./tally -i -t 3 notes.txt end.txt
       2       12       48 notes.txt
       1        2        8 end.txt
       3       14       56 total

the      5
cat      2
on       2
$ ./tally -w notes.txt
      12 notes.txt
$ printf 'one two\nthree\n' | ./tally
       2        3       14
```

Without `-i`, "The" and "the" are different words; with it, they're
one. `-w` prints just the words. The last line counts standard input,
which has no name to print.

And the errors:

```console
$ ./tally notes.txt nope.txt
       2       12       48 notes.txt
tally: nope.txt: No such file or directory (os error 2)
$ echo $?
1
$ printf '\377\n' | ./tally
tally: the input is not UTF-8 text
$ echo $?
1
```

`\377` is a byte that can't appear in UTF-8 text, so the input isn't
text, and `String::from_utf8` said so.

## Step 3: tests

The functions at the end of `count.vl` are tests (chapter 13).
`counts_lines_words_bytes` and `trims_punctuation` are `#[test]`s: they
call the counting functions on a small input and check the answers.

`counts_add_up` is a `#[property]`: `volec test` generates its
argument, a `Vec<u8>` of random length and content, a hundred times,
and runs it on each. The test turns the bytes into a text of "a", "b",
spaces and newlines, counts it both ways, and checks that the word
counts in the map add up to the number of words `count` found. If they
ever didn't, `volec test` would shrink the input to a small one that
still fails, and print it. Its `gpa` is the test's allocator, as a
`#[test]`'s is; only `bytes` is generated.

```console
$ volec test
test main.vl: 3 passed (2 #[test], 1 #[property]; -O0 and -O2 agree)
```

The tests are built twice, at `-O0` and `-O2`, and the results
compared; and with `--check-alloc`, so a test that leaked memory would
fail.

`volec test` also runs whole-program tests: a file `tests/NAME.in` is
given to the program as its standard input, and its output is compared
with `tests/NAME.out`. Let's make one from our notes, checking the
output by eye before keeping it:

```console
$ mkdir tests
$ cp notes.txt tests/basic.in
$ ./tally < tests/basic.in > tests/basic.out
$ cat tests/basic.out
       2       12       48
$ volec test
test main.vl: 4 passed (1 case, 2 #[test], 1 #[property]; -O0 and -O2 agree)
```

Now any change that alters what `tally` prints for that input fails
`volec test`. Add a case for each behaviour you care about, and the
tool is protected against regressions.

## Step 4: checking the promises

We promised that `count.vl` does no I/O. `volec query effects` shows
what each of its functions may do:

```console
$ volec query effects crate::count
crate::count::Counts::add	none
crate::count::count	panic diverge
add_words<&ArenaScope<&Gpa>>	alloc(ArenaScope<&Gpa>) panic diverge
add_words<Gpa>	alloc(Gpa) panic diverge
add_words<A>	alloc io tls thread sync panic diverge (unknown)
crate::count::is_word_byte	none
crate::count::trim_punct	panic diverge
crate::count::counts_lines_words_bytes	panic diverge
crate::count::trims_punctuation	alloc(Gpa) panic diverge
crate::count::counts_add_up	alloc(Gpa) panic diverge
```

Allocation, panics and loops, and no `io` in anything the program
runs. The generic `add_words` is listed once for each allocator it's
used with, and once as `add_words<A>`, the function before an allocator
is chosen, about which nothing is known. The tests are listed too,
since they're functions of the module. The
`#[no_io]` marks make this a rule, not just an observation. Suppose
someone adds a debugging print to `count`, with chapter 17's `edit
patch`:

```console
$ volec edit patch count::count --old 'let mut lines: usize = 0;' --new 'println("counting {} bytes", text.len()); let mut lines: usize = 0;'
count.vl:25:5: error[effect] 'count::count' is #[no_io], but it does io: 'println("counting {} bytes", text.len())' at count.vl:26:5 calls 'std::fmt::println' | help: return the data and let the caller print it, or remove #[no_io] | try: volec query effects count::count --why io  [edited: crate::count::count]
error edit.breaks: 1 new error; nothing written; the error: count.vl:25:5: 'count::count' is #[no_io], but it does io: 'println("counting {} bytes", text.len())' at count.vl:26:5 calls 'std::fmt::println'
try: volec edit patch count::count --old 'let mut lines: usize = 0;' --new 'println("counting {} bytes", text.len()); let mut lines: usize = 0;' --no-check
```

The edit is refused, and the message says why and what to do: return
the data and let the caller print it.

## Step 5: polish

A few last checks before calling it done. Is everything formatted?

```console
$ volec fmt --check main.vl count.vl report.vl
$ echo $?
0
```

Silence and status 0: yes.

Is it fast enough? `volec main.vl -o tally` builds at `-O2` already.
Here is `tally` on a 50 MB text file of random dictionary words, on
one machine (yours will differ). The numbers are the CPU time the
program used, from `/usr/bin/time`:

```text
$ volec main.vl -o tally && /usr/bin/time -p ./tally -t 5 big.txt
  535313  4816443 50000043 big.txt

arachnactis      302
autoinoculable   301
annoy            299
Balsamodendron   297
alloisomerism    297
...
user 0.76
```

That's about 65 MB a second, counting every word into a map. Built at `-O0`, the same run takes about 7 seconds,
which is why `-O0` is for the edit-and-rebuild loop and `-O2` for the
tool you use. (`wc`, which doesn't keep a map of words, takes a tenth
of a second.) Chapter 16 shows how to find out where the time goes.

## Where to go from here

You've built, tested and polished a real tool, and you've used most of
the language on the way. Some ideas for taking `tally` further:

- an option for the minimum word length, or a list of words to ignore
  (`--ignore the,a,an`);
- `-l` and `-c` for lines and bytes only, as `wc` has;
- sorting the table alphabetically, with an `--order` option whose
  value is checked against a list.

And beyond `tally`, the repository has larger programs to read and
learn from:

- `examples/voltty`, a terminal emulator, and `examples/httpd`, a small
  web server: bigger programs in many modules;
- `std::gpu` and `std::window`, for graphics and computation on the GPU
  (`volec guide gpu`, `volec guide window`);
- `docs/roadmap.md`, for where vole is going next.

## Summary

- A small program is easiest to keep right with one job per module, and
  the computing separated from the input and output (`#[no_io]`).
- `std::cli` describes a command line with `Command` and `Arg`, parses it
  with `parse_or_exit`, and gives `--help` and helpful errors for free.
- Borrowed `&str`s as map keys count words without copying them, and
  the compiler checks that the text outlives them.
- An arena per file frees each file's scratch memory at once.
- An error enum with `Display` and `From` impls gives `?` and clear
  messages; `run` returns it, `main` prints it.
- `#[test]`, `#[property]` and `tests/NAME.in`/`.out` cases, run by
  `volec test`, keep it working.
- `volec query effects`, contracts and `volec fmt` check the promises
  the code makes.

That's the end of the book's chapters. The appendices that follow are
for looking things up: keywords and operators, how to read the
compiler's diagnostics, and a guide for readers coming from Rust, C,
Go and other languages.

## Try it yourself

- Add `--min-count N`, which leaves words seen fewer than N times out
  of the table. Use `m.get_as::<i64>` as `top` does.
- Make `tally` print each file's error and go on to the next file,
  exiting with status 1 at the end if any failed. Where does the
  `TallyError` get printed now?
- Add a program test for input that isn't text. Its exit status isn't
  0: what does `volec guide tools` say goes in `tests/NAME.exit`?
