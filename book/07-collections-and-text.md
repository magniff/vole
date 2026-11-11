# 7. Collections and text

Most programs spend their time on lists of things, tables of things,
and text. This chapter covers the containers you'll use every day:
`Vec`, a list that grows; `HashMap` and `HashSet`, for looking things up;
and `BTreeMap`, when order matters. Then text: `&str` and `String`,
bytes, and format strings in full.

By the end of the chapter you'll have written a word counter: it reads
text, counts every word in it, and prints the most common ones as a
table. Chapter 11 splits it into modules, chapter 17 works on it with
the compiler's tools, and chapter 18 grows it into a real command-line
tool.

## Vec: a list that grows

A `Vec` holds any number of values of one type, one after the other.
Start a new file, `scores.vl`:

```vole scores.vl
fn main(gpa: Gpa) {
    let mut scores: Vec<i64, Gpa> = Vec::new_in(gpa);
    scores.push(72);
    scores.push(95);
    scores.push(88);
    println("{} scores, the first is {}", scores.len(), scores[0]);
    println("{scores:?}");
}
```

```out
3 scores, the first is 72
[72, 95, 88]
```

`Vec<i64, Gpa>` is "a Vec of `i64`s, in memory from a `Gpa`"; the
first type in the angle brackets says what it holds. `Vec::new_in(gpa)`
makes an empty one. A Vec needs memory that can grow, so it takes the
allocator, as `String::new_in` did in chapter 2. The Vec remembers it,
so `push` doesn't need it again.
[Chapter 8](08-allocation.md) is about allocators.

`push` adds a value at the end, `len()` says how many there are, and
`scores[0]` is the first one: indexes start at 0. `{scores:?}`
prints the whole Vec. The `:?` asks for the *Debug* form, meant for
programmers rather than users; you'll see more of it at the end of the
chapter.

### Taking values out

`pop` takes the last value off. The Vec may be empty, so `pop` returns
an `Option`: `Some(value)`, or `None` when there was nothing to take.
`while let` (chapter 5) runs until it gets a `None`:

```vole
fn main(gpa: Gpa) {
    let mut stack: Vec<&str, Gpa> = Vec::new_in(gpa);
    stack.push("first");
    stack.push("second");
    stack.push("third");
    println("{:?}", stack.last());
    while let Some(top) = stack.pop() {
        println("{top}");
    }
    println("{:?} {}", stack.pop(), stack.is_empty());
}
```

```out
Some("third")
third
second
first
None true
```

`last()` and `first()` look at an end without taking anything, and
also return an `Option`.

### Indexes are checked

What happens if you ask for an element that isn't there?

```vole
fn main(gpa: Gpa) {
    let mut v: Vec<i64, Gpa> = Vec::new_in(gpa);
    v.push(1);
    println("{}", v[3]);
}
```

```out exit=101
main.vl:4:19: index out of bounds: index 3, length 1
```

Every index is checked when the program runs. A bad one is a panic:
the program stops with the position, the index and the length, and
exits with status 101. It never reads memory past the end of the Vec.

### Looping, and changing elements

`for x in &v` visits each element in order. To change the elements as
you go, loop over `&mut v`:

```vole
fn main(gpa: Gpa) {
    let mut prices: Vec<i64, Gpa> = Vec::new_in(gpa);
    prices.push(10);
    prices.push(25);
    prices.push(40);
    for p in &mut prices {
        *p *= 2;
    }
    let mut total = 0;
    for p in &prices {
        total += p;
    }
    println("{prices:?} total {total}");
}
```

```out
[20, 50, 80] total 150
```

The loop borrows the Vec, as chapter 4 described. Inside `for p in
&prices`, `p` is a reference to each element in turn, to read. Inside
`for p in &mut prices` it is a `&mut`, and `*p` is the element itself,
to change. A plain `for p in prices`, with no `&`, takes the Vec: the
loop owns the elements, and `prices` is gone after it.

### Sorting and searching

```vole
fn main(gpa: Gpa) {
    let mut v: Vec<i64, Gpa> = Vec::new_in(gpa);
    for x in [31, 4, 15, 9, 26] {
        v.push(x);
    }
    v.sort();
    println("{v:?} {} {}", v.contains(&9), v.contains(&10));
    v.retain(|x| x % 2 == 1);
    println("{v:?}");

    let mut fruit: Vec<&str, Gpa> = Vec::new_in(gpa);
    fruit.push("pear");
    fruit.push("fig");
    fruit.push("banana");
    fruit.sort_by_key(|s| s.len());
    println("{fruit:?}");
}
```

```out
[4, 9, 15, 26, 31] true false
[9, 15, 31]
["fig", "pear", "banana"]
```

`sort()` puts the elements in increasing order, and `contains` says
whether a value is there (it only looks, so it takes a reference:
`&9`). `retain` keeps only the elements for which a
test is true, and `sort_by_key` sorts by something computed from each
element: here, the length of each word.

`|x| x % 2 == 1` is a *closure*, a small function written right where
it's used: it takes `x` and returns whether `x` is odd. Chapter 10 is
about closures; for now, read `|x|` as "given x".

### Pushing while looping

Here's a mistake that is easy to make. Let's double a list by pushing a
copy of each element while we loop over it:

```vole
fn main(gpa: Gpa) {
    let mut v: Vec<i64, Gpa> = Vec::new_in(gpa);
    v.push(1);
    v.push(2);
    for x in &v {
        v.push(*x);
    }
    println("{v:?}");
}
```

```err
error[borrowck.conflict]: cannot borrow 'v' as mutable because it is also borrowed as immutable (borrowed at main.vl: line 5, column 14)
 --> main.vl: line 6, column 9
  = help: use the shared borrow before the mutable one, or take it again after
```

Pushing can move a Vec's elements to a bigger block of memory, and the
loop is still walking the old one. In many languages this is a bug you
find at run time, if you're lucky. In vole it doesn't compile: the loop
holds a shared borrow of `v` for as long as it runs, and `push` needs a
mutable one. The fix is to loop over the indexes instead. `0..v.len()`
is worked out once, when the loop starts, so the loop sees the two
elements that were there and stops:

```vole
fn main(gpa: Gpa) {
    let mut v: Vec<i64, Gpa> = Vec::new_in(gpa);
    v.push(1);
    v.push(2);
    for i in 0..v.len() {
        let x = v[i];
        v.push(x);
    }
    println("{v:?}");
}
```

```out
[1, 2, 1, 2]
```

### Passing a Vec to a function

A Vec is a value with an owner, so the rules of
[chapter 4](04-value-semantics.md) apply: a function borrows it to
read it, borrows it to change it, or takes it, and its signature says
which.

```vole
fn total(v: &Vec<i64, Gpa>) -> i64 {
    let mut t = 0;
    for x in v {
        t += x;
    }
    t
}

fn add_bonus(v: &mut Vec<i64, Gpa>, bonus: i64) {
    for x in v {
        *x += bonus;
    }
}

fn main(gpa: Gpa) {
    let mut points: Vec<i64, Gpa> = Vec::new_in(gpa);
    points.push(3);
    points.push(4);
    add_bonus(&mut points, 10);
    println("{points:?} {}", total(&points));
}
```

```out
[13, 14] 27
```

`total` reads (the call says `&points`, and no copy is made),
`add_bonus` changes the caller's Vec (the call says `&mut points`), and
a parameter with no `&`, `v: Vec<i64, Gpa>`, would take it.

## Arrays, Vecs and slices

Vole has three kinds of lists, and they work together:

- An *array*, `[i64; 3]`, has a length fixed in its type. It's a plain
  value: `let b = a;` copies it.
- A `Vec<i64, Gpa>` can grow, and its elements live in memory from an
  allocator.
- A *slice*, `&[i64]`, borrows elements that something else owns: an
  array, a Vec, or a part of either.

A function that only reads a list should take a slice. Then it works on
all three:

```vole
fn largest(xs: &[i64]) -> i64 {
    let mut best = xs[0];
    for &x in xs {
        if x > best {
            best = x;
        }
    }
    best
}

fn main(gpa: Gpa) {
    let days: [i64; 4] = [12, 19, 7, 15];
    let mut temps: Vec<i64, Gpa> = Vec::new_in(gpa);
    temps.push(3);
    temps.push(-2);
    println("{}", largest(&days));
    println("{}", largest(&temps));
    println("{}", largest(&days[2..4]));
}
```

```out
19
3
15
```

`&days` and `&temps` borrow all of the array and of the Vec, and
`&days[2..4]` is the slice of elements 2 and 3: the start is included,
the end is not. Making a slice copies nothing, and the compiler checks
that it isn't used after what it borrows from changes, as chapter 4
showed. (`for &x in xs` takes each element out of its reference: `x` is
an `i64`, not a `&i64`.)

## Text: &str and String

Text in vole is UTF-8, and comes in two types, like lists do:

- `&str` borrows text that something else owns. A string literal is a
  `&str`, and so is every piece cut out of other text.
- `String` owns its text, and can grow. Its memory comes from an
  allocator, which is in its type: `String<Gpa>`.

### Taking text apart

`&str` has the methods you'd expect, with the names Rust uses. Here
are the most common:

```vole
fn main() {
    let line = "  width = 80  ";
    let (key, value) = line.split_once('=').unwrap();
    let n = value.trim().parse::<i64>().unwrap();
    println("[{}] is {n}", key.trim());
    println("{:?} {}", line.find("80"), line.contains("width"));
    println("{} {:?}", line.trim().starts_with("width"), line.trim().strip_prefix("width"));
    for part in "a,b,,c".split(',') {
        print("[{part}]");
    }
    println("");
    for word in "the quick\n  brown fox".split_whitespace() {
        print("<{word}>");
    }
    println("");
}
```

```out
[width] is 80
Some(10) true
true Some(" = 80")
[a][b][][c]
<the><quick><brown><fox>
```

- `trim()` removes the whitespace at both ends.
- `split_once(p)` cuts at the first `p`, giving the two sides, or
  `None` if there is no `p`.
- `parse::<i64>()` reads a number, as in chapter 2.
- `find(p)` gives the byte index where `p` starts, or `None`; `contains`,
  `starts_with` and `strip_prefix` do what their names say.
- `split(p)` gives the pieces between each `p`, empty ones too;
  `split_whitespace()` gives the words, however much space is between
  them; `lines()` gives the lines.

A *pattern* `p` can be a `&str` (`"80"`) or a single `char` (`'='`).

Every one of these returns pieces of the original text: `key`, `value`
and each `part` borrow from `line`. Nothing was copied, and none of
them needed an allocator.

### Building text: String

When you need new text, make a `String`:

```vole
fn main(gpa: Gpa) {
    let mut s = String::new_in(gpa);
    s.push_str("vole");
    s.push_str(" is ");
    write(&mut s, "{} letters", 2 + 2).unwrap();
    println("{s}");

    let name = String::from_in("Ada", gpa);
    println("{name} has {} letters", name.len());
}
```

```out
vole is 4 letters
Ada has 3 letters
```

`String::new_in(gpa)` makes an empty one, and `String::from_in("...",
gpa)` one with some text already in it. `push_str` appends text, and
`write` appends formatted text: where to write, a format string and its
arguments. Writing can fail in general (to a file, say), so `write`
returns a `Result`; into a `String` it can't, hence the `unwrap()`. A
`String` has every method a `&str` has (`name.len()`, `name.trim()`).

A function that only reads text takes a `&str`, and you can give it a
borrowed `String` or a literal:

```vole
fn shout(s: &str, gpa: Gpa) -> String<Gpa> {
    s.to_uppercase_in(gpa)
}

fn main(gpa: Gpa) {
    let name = String::from_in("ada", gpa);
    println("{}", shout(&name, gpa));
    println("{}", shout("lovelace", gpa));
}
```

```out
ADA
LOVELACE
```

### Methods that make new text take an allocator

`to_uppercase_in` makes a new `String`, so it needs memory, so it takes
the allocator. The methods that build text all work this way: their
names end in `_in` and the allocator is their last argument.
`to_lowercase_in`, `replace_in(from, to, gpa)` and `repeat_in(n, gpa)`
are the ones you'll use most. If you reach for the name without `_in`,
the compiler tells you:

```vole
fn main(gpa: Gpa) {
    let name = "vole";
    let loud = name.to_uppercase();
    println("{loud}");
}
```

```err
error[alloc.no_in]: 'to_uppercase' allocates from nothing: pass the allocator, last, to 'to_uppercase_in'
 --> main.vl: line 3, column 16
  = help: this function's `gpa` is the allocator to pass
  = try: volec fix --only alloc main.vl
  = try: volec fix --suggested main.vl
```

That `_in` is the whole rule, and it's how you can tell, reading a
line of code, that it allocates.

If a function insists on a `String` and you give it a literal, you get
a type error with the conversion in its `try:` line. Here a map's keys
are `String`s, so a new key has to be one too:

```vole
use std::collections::HashMap;

fn main(gpa: Gpa) {
    let mut ages: HashMap<String<Gpa>, i64, Gpa> = HashMap::new_in(gpa);
    ages.insert("ada", 36);
    println("{:?}", ages.get("ada"));
}
```

```err
error[type error]: expected 'String<Gpa>', got '&str'
 --> main.vl: line 5, column 17
  = help: a String owns its text, on an allocator: `String::from_in(s, gpa)`; a `str` is a view of one (a `str` parameter takes both)
  = try: String::from_in("ada", gpa)
```

You'll meet `HashMap` properly in a moment.

> **If you know Rust:** the methods have Rust's names, but anything
> that allocates takes an allocator and ends in `_in`:
> `to_uppercase_in(gpa)`, `format_in("..", gpa)`, `collect_in(gpa)`.
> The allocator is part of the type, too: `String<Gpa>`, `Vec<T, Gpa>`.

### Characters and bytes

UTF-8 uses one byte for each ASCII character and two to four for
others. `len()` counts bytes; `chars()` goes through the characters,
each a `char` (chapter 3):

```vole
fn main(gpa: Gpa) {
    let word = "café";
    println("{} bytes, {} characters", word.len(), word.chars().count());
    for c in word.chars() {
        print("{c} ");
    }
    println("");
    let mut s = String::new_in(gpa);
    s.push('☺');
    println("{s} is {} bytes", s.len());
    let b = word.as_bytes()[0];
    println("{b} {} {}", b as char, b == b'c');
}
```

```out
5 bytes, 4 characters
c a f é
☺ is 3 bytes
99 c true
```

`s.push('☺')` adds one character to a `String`, however many bytes it
takes. Text can't be indexed with a number, because a position in the
middle of a character isn't one; `word.as_bytes()` is the same text as
a slice of bytes, `&[u8]`, which can. `word.as_bytes()[0]` is the first
byte of the text, and `b'c'` is the byte for the letter c.

## Bytes: &[u8] and Vec<u8, A>

Not all data is text. A file might be an image, and a network packet
is just bytes. For those, vole has `&[u8]`, a slice of bytes, and
`Vec<u8, A>`, a growable buffer of them, the bytes' `String`:

```vole
fn show(bytes: &[u8]) {
    match std::str::from_utf8(bytes) {
        Ok(text) => println("text: {text}"),
        Err(e) => println("not text: {e}"),
    }
}

fn main(gpa: Gpa) {
    let mut b: Vec<u8, Gpa> = Vec::new_in(gpa);
    b.extend_from_slice(b"hi");
    b.push(0x21);
    show(&b);

    let mut raw: Vec<u8, Gpa> = Vec::new_in(gpa);
    raw.push(0xff);
    raw.push(0x41);
    show(&raw);
}
```

```out
text: hi!
not text: invalid utf-8 sequence of 1 bytes from index 0
```

`b"hi"` is a literal of bytes, not text, and `&b` borrows the `Vec`'s
bytes as a slice. `std::str::from_utf8` checks that bytes are valid
UTF-8 and, if they are, gives you a `&str` of the same bytes, without
copying them. Bytes that aren't UTF-8 are an `Err`.

Use `&str` and `String` for text, and `&[u8]` and `Vec<u8, A>` when the
topic is bytes. Text becomes bytes for free, with `as_bytes()`; the
other way round goes through `std::str::from_utf8`, because not every
byte sequence is text.

## Reading all of stdin

Now we can start the word counter. Its first job is to read everything
on standard input. Start `words.vl`:

```vole words.vl
use std::io;

fn main(gpa: Gpa) {
    let text = io::read_to_string_in(io::stdin(), gpa).unwrap();
    let words = text.split_whitespace().count();
    println("{} lines, {words} words, {} bytes", text.lines().count(), text.len());
}
```

```in
The cat and the dog.
The END, the end!
```

```out
2 lines, 9 words, 39 bytes
```

`io::read_to_string_in(io::stdin(), gpa)` reads all of standard input
into a `String`, and returns a `Result` because reading can fail (and
because the input might not be UTF-8). From there it's all `&str`
methods. `lines()` gives the lines one at a time and
`split_whitespace()` the words, and `count()` counts them. Chapter 10
is about this kind of value, an *iterator*, and the many things you can
do with one.

Reading everything at once is the simplest way when the input fits in
memory. For input too big for that, chapter 2's `read_line` reads a
line at a time, and `io::stdin().lines_in(gpa)` gives the lines one by
one (`volec guide io`).

## HashMap: looking things up

A `HashMap` stores *values* under *keys*, and finds a value from its
key quickly, however many there are:

```vole
use std::collections::HashMap;

fn main(gpa: Gpa) {
    let mut ages: HashMap<&str, i64, Gpa> = HashMap::new_in(gpa);
    ages.insert("ada", 36);
    ages.insert("alan", 41);
    let old = ages.insert("ada", 37);
    println("{old:?} {:?} {:?}", ages.get("ada"), ages.get("bob"));
    println("{} {}", ages.contains_key("alan"), ages.len());
    println("{:?} {}", ages.remove("alan"), ages.len());
}
```

```out
Some(36) Some(37) None
true 2
Some(41) 1
```

`HashMap<&str, i64, Gpa>` maps `&str` keys to `i64` values. It isn't in
the prelude, so the program starts with a `use` line. `insert` returns
the value the key had before, if any. `get` returns an `Option`: a
reference to the value, or `None` when the key isn't there. `remove`
takes the key out and gives back its value.

### Counting

Counting things is the most common job for a map, and it has methods
of its own:

```vole
use std::collections::HashMap;

fn main(gpa: Gpa) {
    let mut counts: HashMap<&str, i64, Gpa> = HashMap::new_in(gpa);
    for w in "a b a c a b".split(' ') {
        *counts.entry(w).or_insert(0) += 1;
    }
    println("{:?} {:?} {:?}", counts.get("a"), counts.get("b"), counts.get("z"));
}
```

```out
Some(3) Some(2) None
```

`counts.entry(w)` is `w`'s place in the map, whether or not there is a
value in it yet. `or_insert(0)` puts `0` there if it's empty, and gives
back a `&mut` to the value inside the map. The `*` in front reaches
through that reference, and `+= 1` adds one to the value. You'll write
this line often enough that it soon reads naturally. (`get_mut(k)` gives
an `Option` of the same kind of reference, for changing a value only if
it's there.)

### The order of a HashMap

You can loop over a map's pairs, but in no particular order:

```vole skip
    for (word, n) in counts.iter() {
        println("{word} {n}");
    }
```

The order depends on the keys' hashes, and can change when the map
grows. When order matters, sort the pairs, as the word counter will
do, or use a `BTreeMap`.

### Your own types as keys

A key needs two things: a way to compare keys for equality, and a
hash. Numbers, `&str`, `String` and tuples of them have both. For your
own struct, add `#[derive(PartialEq, Eq, Hash)]` above it; chapter 9
explains what that writes.

### HashSet, BTreeMap and heaps

A `HashSet` is a map with keys and no values, for asking "have I seen
this?". A `BTreeMap` is a map that keeps its keys sorted, so looping
over it goes from the smallest key up, and `range` gives part of it:

```vole mvs
use std::BTreeMap;
use std::HashSet;

fn main(gpa: Gpa) {
    var seen: HashSet<i64, Gpa> = HashSet::new_in(gpa);
    println("{} {} {}", seen.insert(3), seen.insert(3), seen.contains(3));

    var grades: BTreeMap<i64, str, Gpa> = BTreeMap::new_in(gpa);
    grades.insert(90, "A");
    grades.insert(70, "C");
    grades.insert(80, "B");
    for (score, grade) in grades.iter() {
        print("{score}:{grade} ");
    }
    println("");
    for (score, grade) in grades.range(75, 95) {
        print("{score}:{grade} ");
    }
    println("");
}
```

```out
true false true
70:C 80:B 90:A 
80:B 90:A 
```

`insert` on a set says whether the value was new. `range(75, 95)`
includes 75 and stops before 95, like `75..95`.

`HashSet` and `BTreeMap` aren't in the prelude, so they need a `use`
line. Two more containers are in the prelude: `BinaryHeap`, a *priority queue*, where
you push values in any order and `pop` always gives back the largest
one left, and `MinHeap`, which gives back the smallest.

## Counting the words

Back to the word counter. Each word should be counted without the
punctuation around it ("dog." is "dog") and without caring about case
("The" is "the"). Here is `words.vl` again, counting:

```vole words.vl
use std::io;
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

fn count_words(text: &str, gpa: Gpa) -> HashMap<String<Gpa>, i64, Gpa> {
    let mut counts: HashMap<String<Gpa>, i64, Gpa> = HashMap::new_in(gpa);
    for word in text.split_whitespace() {
        let w = trim_punct(word);
        if w.is_empty() {
            continue;
        }
        *counts.entry(w.to_lowercase_in(gpa)).or_insert(0) += 1;
    }
    counts
}

fn main(gpa: Gpa) {
    let text = io::read_to_string_in(io::stdin(), gpa).unwrap();
    let counts = count_words(&text, gpa);
    println("{} different words, 'the' {:?} times", counts.len(), counts.get("the"));
}
```

```in
The cat and the dog.
The END, the end!
```

```out
5 different words, 'the' Some(4) times
```

`trim_punct` moves two indexes inwards past the bytes that aren't part
of a word, then returns the slice between them, `&word[start..end]`: a
piece of the word, with nothing copied. `bytes[start]` is one byte of
the text.

`count_words` lowercases each word with `to_lowercase_in(gpa)`, which
makes a new `String`, and that `String` becomes the key. That's why the
map's keys are `String<Gpa>` and not `&str`: a lowercased word is new
text, not a piece of the input. The map takes the `String`, and drops
it with the map at the end of the program. Looking a word up doesn't
need a `String`, though: `counts.get("the")` takes a `&str`.

## Formatting with format strings

The last step is printing a table, so let's look at format strings in
full. A hole is `{name}`, a variable's value, or `{}`, the next argument
after the string; an expression is always an argument (`{}` and then
`n * 2`), never inside the braces. After the name, or right after `{`, a
colon starts a *format spec*:

```vole
fn main() {
    let n = 42;
    let pi = 3.14159;
    let word = "vole";
    println("[{n:>6}] [{n:<6}] [{n:06}]");
    println("[{n:x}] [{n:X}] [{n:b}]");
    println("[{pi:.2}] [{pi:8.3}]");
    println("[{word:>8}] [{word:<8}] [{word:?}]");
    println("{{n}} is {n}, and twice that is {}", n * 2);
}
```

```out
[    42] [42    ] [000042]
[2a] [2A] [101010]
[3.14] [   3.142]
[    vole] [vole    ] ["vole"]
{n} is 42, and twice that is 84
```

- A number is a *width*: `{n:>6}` pads to six places, on the left
  (`>`, right-aligned) or the right (`<`). Numbers go right by default,
  text left. A `0` before the width pads with zeros.
- `.2` gives a float two decimals.
- `x`, `X` and `b` print an integer in hex or binary.
- `?` is the Debug form: text in quotes, a Vec in brackets, an `Option`
  as `Some(...)`.
- `{{` and `}}` are a literal brace.

Every type you can print has a *Display* form (the plain `{x}`) or a
Debug form (`{x:?}`), or both. Numbers and text have both; a `Vec` or an
`Option` has only Debug, because there's no single obvious way to show
one to a user. For your own types, `#[derive(Debug)]` writes the Debug
form for you (chapter 5), and chapter 9 shows how to write a Display
form.

Formatted text can also become text you keep, instead of being printed:

```vole
fn main(gpa: Gpa) {
    let label = format_in("{}-{}", 3, "vole", gpa);
    println("{label} has {} bytes", label.len());
    let mut report = String::new_in(gpa);
    for i in 1..4 {
        write(&mut report, "{} ", i * i).unwrap();
    }
    println("{}", report.trim());
}
```

```out
3-vole has 6 bytes
1 4 9
```

`format_in("...", gpa)` makes a `String`, the allocator after the
arguments; `write` appends to one you have.

## The word counter

Now let's finish the program. To print the most common words, we take
the pairs out of the map into a `Vec`, sort it, and print the first
five rows. Here is the complete `words.vl`:

```vole words.vl
// Count the words on stdin, and print the most common ones.
use std::io;
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

fn count_words(text: &str, gpa: Gpa) -> HashMap<String<Gpa>, i64, Gpa> {
    let mut counts: HashMap<String<Gpa>, i64, Gpa> = HashMap::new_in(gpa);
    for word in text.split_whitespace() {
        let w = trim_punct(word);
        if w.is_empty() {
            continue;
        }
        *counts.entry(w.to_lowercase_in(gpa)).or_insert(0) += 1;
    }
    counts
}

// The pairs, most common first; words with the same count in
// alphabetical order.
fn sorted_counts(counts: &HashMap<String<Gpa>, i64, Gpa>, gpa: Gpa) -> Vec<(String<Gpa>, i64), Gpa> {
    let mut rows: Vec<(String<Gpa>, i64), Gpa> = Vec::new_in(gpa);
    for (word, n) in counts {
        rows.push((word.clone(), *n));
    }
    rows.sort_by(|a, b| b.1.cmp(&a.1).then_with(|| a.0.cmp(&b.0)));
    rows
}

fn print_table(rows: &[(String<Gpa>, i64)], top: usize) {
    let shown = rows.len().min(top);
    println("{:<12} {:>5}", "word", "count");
    println("{:<12} {:>5}", "----", "-----");
    for (word, n) in &rows[0..shown] {
        println("{word:<12} {n:>5}");
    }
}

fn main(gpa: Gpa) {
    let text = io::read_to_string_in(io::stdin(), gpa).unwrap();
    let counts = count_words(&text, gpa);
    let rows = sorted_counts(&counts, gpa);
    print_table(&rows, 5);
    println("{} different words", counts.len());
}
```

```in
The cat and the dog. The END, the end!
A cat? A dog, a bird; a cat.
It's the end.
```

```out
word         count
----         -----
the              5
a                4
cat              3
end              3
dog              2
8 different words
```

Let's look at the two new functions.

`sorted_counts` copies each pair into a Vec of tuples. Looping over a
borrowed map gives references to its keys and values. `word.clone()` is
needed because the map keeps its own keys: `counts` is only borrowed
here, so its `String`s stay in it, and the Vec gets copies. `*n` copies
the count out of its reference.

Then `sort_by` sorts the rows with a comparison we give it: a closure
that takes two rows, `a` and `b`, and says which goes first. `x.cmp(&y)`
compares two values and answers with an `Ordering`: `Less`, `Equal` or
`Greater`. `b.1.cmp(&a.1)` compares the counts the other way round, so
the bigger count goes first. When the counts are equal, `then_with`
asks the second question: `a.0.cmp(&b.0)` compares the words, so ties
come out in alphabetical order. Without that, the order of equal counts
would be the map's order, which is no order at all.

`print_table` takes a slice of rows, so `main` passes `&rows`. It works
out how many rows to show, makes a slice of that many, and loops over
it. `for (word, n) in ...` takes each tuple apart as it goes.
The header uses the same widths as the rows, so the columns line up.

Try it on a bigger text, any text file you have:

```sh
volec words.vl -o words
./words < some-book.txt
```

> **If you know Python:** there are no list comprehensions or
> `Counter`. Loops like these do the job, and chapter 10's iterator
> chains (`map`, `filter`, `collect_in`) fill the role of
> comprehensions.

## Summary

- `Vec<T, Gpa>` grows: `push`, `pop` (an `Option`), `len`, checked
  `v[i]`, slices `&v[a..b]`, `sort`, `sort_by_key`, `sort_by`, `retain`,
  `contains`. `for x in &v` reads the elements, `for x in &mut v`
  changes them.
- Arrays have a fixed length; slices borrow from either; functions that
  read a list take a slice.
- `HashMap` finds values by key; `*m.entry(k).or_insert(0) += 1`
  counts; its order is unspecified. `HashSet` for membership, `BTreeMap` for
  sorted keys, `BinaryHeap` and `MinHeap` as priority queues.
- `&str` borrows UTF-8 text and `String` owns some; a literal is a
  `&str`. Its methods (`trim`, `split`, `lines`) copy nothing; methods
  that make text take an allocator and end in `_in`.
- `&[u8]` and `Vec<u8, A>` hold bytes; `std::str::from_utf8` checks
  them into text.
- format specs: width and alignment, zero padding, precision, hex,
  Debug.

The word counter called `gpa` a lot. The next chapter is about where
memory comes from: why every allocation names its allocator, and the
allocators you can choose instead of `gpa`.

## Try it yourself

- Make the counter take the number of rows from the first line of
  input, as `5` or `10`, with `split_once('\n')` and `parse`.
- Print each word's share of all the words as a percentage with one
  decimal: `{p:.1}%`.
- Skip short words: change `count_words` so it ignores words of one or
  two bytes.
