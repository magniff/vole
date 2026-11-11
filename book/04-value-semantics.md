# 4. Ownership and borrowing

This is the chapter that makes vole different from the languages you
probably know, so we'll take it slowly. It answers two questions every
program has to answer somehow: when two parts of a program use the same
data, who may change it? And when is its memory given back?

By the end of the chapter you'll know what it means that every value in
vole has one owner, when a value is copied and when it is moved, and how
a function says what it does with each argument: borrows it to read,
borrows it to change, or takes it. You'll also meet the *borrow
checker*, the part of the compiler that makes sure a borrowed value is
still there, and unchanged, for as long as someone is looking at it.

Our running example is a playlist: songs, and functions that add to a
playlist, total it up, and put it away.

## The problem

Here is a small program in Python:

```text
a = [1, 2, 3]
b = a
b.append(4)
print(a)        # [1, 2, 3, 4]
```

`b = a` didn't copy the list. It made a second name for the same list,
so a change through `b` shows up through `a`. That's convenient, and
it's also the source of a whole family of bugs: a function that changes
a list its caller still uses, two parts of a program that each think
they own some data, a loop that changes the list it's going through.
Python pays for this sharing in another way too: a garbage collector
has to work out, while the program runs, when nobody can reach a value
any more.

Other languages answer the same questions differently. C lets you share
freely and makes you call `free` yourself, at exactly the right moment,
or else.

Vole's answer is Rust's, and it's called *ownership*. Every value has
exactly one owner, the variable that holds it. Other parts of the
program can *borrow* the value for a while, through a *reference*, and
the compiler checks two things about every borrow: the value outlives
it, and while anyone can change the value, nobody else is looking. So
you can always change what is yours (`let mut`), and nothing changes
behind your back. The rest of this chapter is about how that works, one
rule at a time.

## Copies and moves

Start with the simplest values:

```vole
fn main() {
    let a = 5;
    let mut b = a;
    b += 1;
    println("{a} {b}");
}
```

```out
5 6
```

Nobody is surprised that `a` is still 5. `b = a` gave `b` its own 5.
Numbers, `bool`s and `char`s are *copied* by `=`: afterwards there are
two values, each with its own owner.

A list is different. A `Vec` (a growable list, chapter 7) holds its
elements in memory it got from an allocator, and that memory can be
large. Copying it on every `=` would be slow, and sharing it is what
we're trying to avoid. So what does `=` do with a `Vec`? Let's try.
Here's our song type (structs are chapter 5's subject; for now, a
`struct` is a value with named fields) and a playlist:

```vole playlist.vl
struct Song { title: &'static str, seconds: i64 }

fn main(gpa: Gpa) {
    let mut list: Vec<Song, Gpa> = Vec::new_in(gpa);
    list.push(Song { title: "Blue Moon", seconds: 185 });
    list.push(Song { title: "Summertime", seconds: 210 });
    let copy = list;
    println("{} {}", list.len(), copy.len());
}
```

```err
error[borrowck.use_moved]: 'list' is used here after it moved (moved at playlist.vl: line 7, column 16)
 --> playlist.vl: line 8, column 22
  = help: use it before the move, pass a clone where it moves, or take it by reference
```

`let copy = list;` did not copy the list. It *moved* it: the list now
belongs to `copy`, and `list` is no longer a variable you can use. The
error says where the value was used and where it moved. Nothing was
copied, and there is still exactly one owner, so there is still nobody
who can change the list behind anybody's back.

Moving is what `=` does with every value that isn't one of the simple
copied kinds: a `Vec`, a `String`, and a struct too, whatever its
fields are. Passing a value to a function moves it in the same way, and
so does returning it.

A struct made only of copied things can ask to be copied as well, with
a line above it:

```vole
#[derive(Clone, Copy)]
struct Song { title: &'static str, seconds: i64 }

fn main() {
    let first = Song { title: "Blue Moon", seconds: 185 };
    let mut edit = first;
    edit.seconds = 190;
    println("{} {}", first.seconds, edit.seconds);
}
```

```out
185 190
```

With `#[derive(Clone, Copy)]`, a `Song` behaves like a number: `let mut
edit = first;` copied it, and changing `edit` left `first` alone.
Without that line, `first` would have moved, and the last line would be
the error we just saw. Types that are copied this way are called
`Copy` types. A struct that holds a `Vec` or a `String` can't be one:
there is no cheap way to copy what it owns. (Chapter 9 explains what
`derive` writes.)

(The type of `title`, `&'static str`, is the type of a string literal.
The section on lifetimes, later in this chapter, explains it.)

## Drops: giving memory back

A value has exactly one owner at a time. That makes the second
question, when to give the memory back, easy: when the owner goes away.
At the end of the block where a variable was declared, its value is
*dropped*, which for a `Vec` means its memory goes back to the
allocator. You never call `free`.

To watch drops happen, we can give a type some code to run when it is
dropped, with `impl Drop`:

```vole drops.vl
struct Noisy { id: i64 }

impl Drop for Noisy {
    fn drop(&mut self) {
        println("dropping {}", self.id);
    }
}

fn main() {
    let a = Noisy { id: 1 };
    let b = Noisy { id: 2 };
    {
        let c = Noisy { id: 3 };
        println("the inner block ends ({})", c.id);
    }
    let d = Noisy { id: 4 };
    drop(d);
    println("main ends ({} {})", a.id, b.id);
}
```

```out
the inner block ends (3)
dropping 3
dropping 4
main ends (1 2)
dropping 2
dropping 1
```

Reading the output from the top:

- `c` is dropped when the inner block ends, right after its last line.
- `drop(d)` drops `d` early, on the spot. After it, `d` can't be used:
  it moved, into `drop`.
- `a` and `b` are dropped when `main` ends, the last declared first.

Drops happen on every way out of a block: falling off the end,
`return`, `break`, `continue`. A value that was moved somewhere else
isn't dropped where it was; its new owner drops it later. So every
value is dropped exactly once, and you never free memory twice or
forget to free it.

You'll rarely write `impl Drop` yourself. A struct without one is
dropped field by field, so a struct holding a `Vec` frees the `Vec`'s
memory with no code from you.

## &: borrowing to read

Now let's write functions that work on a playlist. The first one only
reads it. If it took the list by value, the call would move the list
into the function, and the caller would lose it. What we want is to
lend the list for the length of the call:

```vole playlist.vl
struct Song { title: &'static str, seconds: i64 }

fn total_seconds(list: &Vec<Song, Gpa>) -> i64 {
    let mut total = 0;
    for song in list {
        total += song.seconds;
    }
    total
}

fn main(gpa: Gpa) {
    let mut list: Vec<Song, Gpa> = Vec::new_in(gpa);
    list.push(Song { title: "Blue Moon", seconds: 185 });
    list.push(Song { title: "Summertime", seconds: 210 });
    println("{} seconds", total_seconds(&list));
    println("{} songs", list.len());
}
```

```out
395 seconds
2 songs
```

`&Vec<Song, Gpa>` is the type of a *reference* to a list: a way to
reach a list that someone else owns. `&list` at the call makes one. We
say `total_seconds` *borrows* the list. Nothing is copied, however long
the list is, and when the function returns, the borrow is over and
`main` still owns its list, as the last line shows.

Through a `&` reference you can read and nothing else: `total_seconds`
can't push a song or change one. You use a reference much as you would
the value: `list.len()` and `song.seconds` work through one, and a
`for` loop over a reference to a list visits references to its
elements. Where you need the value itself, `*r` is what the reference
`r` points to.

Any number of `&` references to a value can exist at once. Readers
don't get in each other's way.

## &mut: borrowing to change

A function that changes its argument asks for a different kind of
reference, `&mut`:

```vole playlist.vl
struct Song { title: &'static str, seconds: i64 }

fn add_song(list: &mut Vec<Song, Gpa>, title: &'static str, seconds: i64) {
    list.push(Song { title, seconds });
}

fn trim_all(list: &mut Vec<Song, Gpa>, limit: i64) {
    for song in list {
        if song.seconds > limit {
            song.seconds = limit;
        }
    }
}

fn main(gpa: Gpa) {
    let mut list: Vec<Song, Gpa> = Vec::new_in(gpa);
    add_song(&mut list, "Blue Moon", 185);
    add_song(&mut list, "Summertime", 210);
    trim_all(&mut list, 200);
    for song in &list {
        println("{} {}", song.title, song.seconds);
    }
}
```

```out
Blue Moon 185
Summertime 200
```

`&mut list` lends the list for changing, and you can see it at the
call: reading `main`, you know which calls may change `list` without
looking at the functions. A `&mut` can be made only of a `let mut`
variable; you can't lend for changing what you may not change yourself.

Inside `trim_all`, the loop over a `&mut` list visits `&mut` references
to its songs, so `song.seconds = limit` changes the song in the
caller's list.

### One change at a time

A `&mut` reference comes with a promise: while it exists, it is the
only way to reach the value. No other reference, `&` or `&mut`, may be
in use at the same time. Here's a function that appends one list to
another, called with the same list twice:

```vole playlist.vl
struct Song { title: &'static str, seconds: i64 }

fn append(to: &mut Vec<Song, Gpa>, from: &Vec<Song, Gpa>) {
    for s in from {
        to.push(Song { title: s.title, seconds: s.seconds });
    }
}

fn main(gpa: Gpa) {
    let mut list: Vec<Song, Gpa> = Vec::new_in(gpa);
    list.push(Song { title: "Blue Moon", seconds: 185 });
    append(&mut list, &list);
    println("{}", list.len());
}
```

```err
error[borrowck.conflict]: cannot borrow 'list' as immutable because it is also borrowed as mutable (mutably borrowed at playlist.vl: line 12, column 12)
 --> playlist.vl: line 12, column 23
  = help: use the shared borrow before the mutable one, or take it again after
```

Think about what `append` would do: push onto a list while looping over
it. Each push could move the songs to a bigger block of memory while
the loop is still walking the old one. Inside `append` nothing looks
wrong; the trouble is the call. So that's where the rule is checked:
`list` can't be borrowed to read while it is borrowed to change. This
is the borrow checker at work, and its rule is short:

- any number of `&` references, **or**
- exactly one `&mut` reference,

and never both at once. Everything else in this chapter follows from
it. Because of it, a function holding a `&mut` knows nobody else sees
the value half-changed, and a function holding a `&` knows the value
won't change while it reads.

### When a borrow ends

A borrow doesn't last to the end of the block. It lasts until the
reference is used for the last time:

```vole
fn main(gpa: Gpa) {
    let mut scores: Vec<i64, Gpa> = Vec::new_in(gpa);
    scores.push(185);
    let first = &scores[0];
    println("first: {first}");
    scores.push(210);
    println("{} scores", scores.len());
}
```

```out
first: 185
2 scores
```

`first` borrows from `scores`, and `push` needs to change `scores`. But
`first` is never used after its `println`, so by the time of the push
the borrow is over. Use `first` after the push, and the two overlap:

```vole
fn main(gpa: Gpa) {
    let mut scores: Vec<i64, Gpa> = Vec::new_in(gpa);
    scores.push(185);
    let first = &scores[0];
    scores.push(210);
    println("first: {first}");
}
```

```err
error[borrowck.conflict]: cannot borrow 'scores' as mutable because it is also borrowed as immutable (borrowed at main.vl: line 4, column 18)
 --> main.vl: line 5, column 5
  = help: use the shared borrow before the mutable one, or take it again after
```

The message names both places: where the shared borrow began (line 4)
and where the list is borrowed to change (line 5). And it's right to
complain: the push may move the elements, and `first` would be left
pointing at memory the list no longer owns. In C, this is a bug that
shows up some of the time. Here it doesn't compile, and the help says
how to fix it: use `first` before the push, or take it again after.

## Taking a value

The third thing a function can do with an argument is keep it. Then the
parameter has no `&`: the value moves in, and the function is its new
owner.

```vole playlist.vl
struct Song { title: &'static str, seconds: i64 }

fn put_away(shelf: &mut Vec<Vec<Song, Gpa>, Gpa>, list: Vec<Song, Gpa>) {
    shelf.push(list);
}

fn main(gpa: Gpa) {
    let mut shelf: Vec<Vec<Song, Gpa>, Gpa> = Vec::new_in(gpa);
    let mut list: Vec<Song, Gpa> = Vec::new_in(gpa);
    list.push(Song { title: "Blue Moon", seconds: 185 });
    put_away(&mut shelf, list);
    println("{} list on the shelf, with {} song", shelf.len(), shelf[0].len());
}
```

```out
1 list on the shelf, with 1 song
```

`put_away` takes the list and pushes it onto a shelf of lists, which it
only borrows. The call says `list`, with no `&`: the list moves into
the function and from there into the shelf, without its songs being
copied. After the call,
`main` has no `list` any more; use it and you get the "used after it
moved" error from the start of the chapter.

So a function's signature tells you what it does with each argument:

| the parameter | the call | what happens |
|---|---|---|
| `list: &Vec<Song, Gpa>` | `f(&list)` | the function reads it |
| `list: &mut Vec<Song, Gpa>` | `f(&mut list)` | the function may change it |
| `list: Vec<Song, Gpa>` | `f(list)` | the function takes it; the caller's is gone |

For a `Copy` type, like an `i64`, taking is copying, which is why
numbers are passed without any `&`.

## Methods and their receivers

Methods (chapter 5) make the same three choices for the value they're
called on, in how they write `self`:

```vole playlist.vl
struct Song { title: &'static str, seconds: i64 }

impl Song {
    fn minutes(&self) -> i64 {
        self.seconds / 60
    }

    fn extend(&mut self, seconds: i64) {
        self.seconds += seconds;
    }

    fn into_title(self) -> &'static str {
        self.title
    }
}

fn main() {
    let mut song = Song { title: "Blue Moon", seconds: 185 };
    song.extend(60);
    println("{} minutes", song.minutes());
    let title = song.into_title();
    println("{title}");
}
```

```out
4 minutes
Blue Moon
```

`&self` borrows the song to read it, `&mut self` borrows it to change
it, and a plain `self` takes it: `into_title` uses the song up and
hands back its title, and `song` can't be used after it. At the call
you write no `&`: `song.extend(60)` borrows `song` the way `extend`
asks for.
The variable still has to be a `let mut` for a `&mut self` method.

## Returning values

Returning a value moves it to the caller, like any other move. That's
how a function makes something and hands it over:

```vole
fn countdown(from: i64, gpa: Gpa) -> Vec<i64, Gpa> {
    let mut v = Vec::new_in(gpa);
    let mut n = from;
    while n > 0 {
        v.push(n);
        n -= 1;
    }
    v
}

fn main(gpa: Gpa) {
    let v = countdown(3, gpa);
    println("{v:?}");
}
```

```out
[3, 2, 1]
```

The `Vec` made inside `countdown` isn't dropped when the function ends:
it moved out, into `main`'s `v`, and `main` drops it. However big it
is, moving it costs the same: a `Vec` is a pointer, a length and a
capacity, and those are what move. Its elements stay where they are.

## Slices

A reference doesn't have to be to a whole value. A *slice* is a
reference to a run of elements inside an array or a `Vec`: `&v[1..3]`
is elements 1 and 2 of `v`, of type `&[i64]`. It's a pointer and a
length, and making one copies nothing.

```vole
fn sum(xs: &[i64]) -> i64 {
    let mut t = 0;
    for x in xs {
        t += x;
    }
    t
}

fn main(gpa: Gpa) {
    let mut lengths: Vec<i64, Gpa> = Vec::new_in(gpa);
    lengths.push(185);
    lengths.push(210);
    lengths.push(143);
    println("{} {} {}", sum(&lengths), sum(&lengths[1..3]), sum(&lengths[..1]));
}
```

```out
538 353 185
```

A function that reads a list should take a slice, `&[i64]`, and not a
`&Vec<i64, Gpa>`: then it works on a whole `Vec` (`&lengths` becomes a
slice of all of it), on a part of one, and on an array. `&mut [i64]`
is a slice whose elements can be changed.

Text works the same way. A `String` owns its text, and a `&str` is a
slice of text someone else owns: a part of a `String`, or a string
literal, whose text is in the program itself.

```vole
fn first_word(text: &str) -> &str {
    match text.split_once(' ') {
        Some((word, _)) => word,
        None => text,
    }
}

fn main(gpa: Gpa) {
    let title = String::from_in("Blue Moon", gpa);
    let word = first_word(&title);
    println("{word}");
}
```

```out
Blue
```

`first_word` returns a piece of the text it was given. No text was
copied: `word` points into `title`'s memory. A slice is a borrow like
any other, so the rules you've seen apply to it. `title` can't be
changed or dropped while `word` is still to be used.

## Lifetimes

How does the compiler know that `word` borrows from `title`? It doesn't
look inside `first_word` at the call. It reads the signature: one
reference goes in, a reference comes out, so the result borrows from
the argument. Most functions that return a reference are like this, and
you write nothing special.

When there are two references to borrow from, the signature has to
say which:

```vole
fn longer(a: &str, b: &str) -> &str {
    if a.len() >= b.len() { a } else { b }
}

fn main() {
    println("{}", longer("Blue Moon", "Summertime"));
}
```

```err
error[borrowck.elision]: the result of 'longer' borrows, but from which parameter is not said: it has no single reference parameter and no `&self`
 --> main.vl: line 1, column 32
  = help: name the lifetime the result borrows from: `fn f<'a>(x: &'a T, y: &U) -> &'a T` (rustc E0106)
```

The fix is the one in the help: give the borrow a name. A name for how
long a borrow lasts is a *lifetime*, written with a `'` in front:

```vole
fn longer<'a>(a: &'a str, b: &'a str) -> &'a str {
    if a.len() >= b.len() { a } else { b }
}

fn main(gpa: Gpa) {
    let title = String::from_in("Blue Moon", gpa);
    let best = longer(&title, "Summertime");
    println("{best}");
}
```

```out
Summertime
```

`<'a>` declares the lifetime, and the three `&'a str` say: the result
borrows from both `a` and `b`, and is good for as long as both are. A
lifetime changes nothing about how the program runs. It's a label that
tells the compiler, and the reader, where a reference comes from.

A struct that holds a reference needs a lifetime too, so that the
compiler knows a value of that type can't outlive what it borrows:

```vole
struct Pick<'a> {
    title: &'a str,
    rank: i64,
}

fn main(gpa: Gpa) {
    let title = String::from_in("Summertime", gpa);
    let pick = Pick { title: &title, rank: 1 };
    println("{}: {}", pick.rank, pick.title);
}
```

```out
1: Summertime
```

One lifetime has a name of its own: `'static`, for what lives as long
as the program. A string literal is a `&'static str`, because its text
is part of the program. That's why `Song`'s `title` could be a plain
`&'static str` earlier, with no `<'a>` on `Song`: our titles were all
literals.

What the lifetimes are for is the second half of the borrow checker's
job: no reference may outlive what it borrows from. Here a function
tries to return a reference to its own local variable:

```vole
fn title_or_default(titles: &Vec<String<Gpa>, Gpa>, gpa: Gpa) -> &str {
    let fallback = String::from_in("(untitled)", gpa);
    if titles.is_empty() {
        return &fallback;
    }
    &titles[0]
}

fn main(gpa: Gpa) {
    let titles: Vec<String<Gpa>, Gpa> = Vec::new_in(gpa);
    println("{}", title_or_default(&titles, gpa));
}
```

```err
error[borrowck.return_local]: a reference to 'fallback', a local of this function, escapes it (borrowed at main.vl: line 4, column 16)
 --> main.vl: line 4, column 9
  = help: return an owned value, or borrow from a parameter
```

`fallback` is dropped when the function returns, so a reference to it
would point at freed memory. The help gives the two ways out: return a
value the caller can own (a `String`), or return something borrowed
from a parameter. Returning `"(untitled)"`, a literal, would work too:
it's `'static`, so it outlives everything.

> **If you know C or C++:** a reference is a pointer that the compiler
> has checked. It is never null, never dangling, and never a way to
> change something another part of the program is reading.

## When to clone

Sometimes you really do want two independent values: a copy of a list
to change while the original stays as it was. That's `clone()`:

```vole
fn main(gpa: Gpa) {
    let mut original: Vec<i64, Gpa> = Vec::new_in(gpa);
    original.push(185);
    original.push(210);
    let mut edited = original.clone();
    edited.push(143);
    println("{original:?} {edited:?}");
}
```

```out
[185, 210] [185, 210, 143]
```

`clone()` makes a full copy: new memory, every element copied. It's
explicit because it can be expensive, and seeing it in the code tells
you where the copies are. The compiler's help for a "used after it
moved" error often offers a `clone()`. Before taking it, ask whether a
borrow would do: if the function only reads, give it a `&`, and nothing
is copied at all.

## Summary

This chapter was about how vole shares data safely:

- every value has one owner; numbers and other `Copy` types are copied
  by `=`, and everything else (`Vec`, `String`, a struct) is moved,
  leaving the old name unusable;
- a value is dropped at the end of its owner's scope, exactly once;
  `drop(x)` drops it early, and `impl Drop` runs code then;
- a function borrows what it reads (`&T`, `f(&x)`), borrows what it
  changes (`&mut T`, `f(&mut x)`), and takes what it keeps (`T`,
  `f(x)`);
- methods take `&self`, `&mut self` or `self`, and a call borrows the
  receiver without `&`;
- the borrow checker allows any number of `&` references or one `&mut`,
  never both, and a borrow lasts until the reference's last use;
- returning a value moves it to the caller;
- a slice (`&[T]`, `&str`) borrows part of what something else owns;
- a lifetime (`'a`) names a borrow where a signature or a struct has to
  say where a reference comes from; `'static` is the whole program;
- `.clone()` is for when you really want two values.

With these rules in hand, the next chapter builds types of your own:
structs, enums, and the pattern matching that takes them apart.

## Try it yourself

- Write `fn longest(list: &[Song]) -> &Song`, which returns the longest
  song. Why does it need no lifetime written out?
- Write `fn remove_short(list: &mut Vec<Song, Gpa>, limit: i64)`, which
  removes the songs shorter than `limit` seconds. (`list.retain(|s|
  s.seconds >= limit)` keeps the others; chapter 7 has more on `Vec`.)
- Call `song.minutes()` after `song.into_title()`. Read the error, and
  fix it by moving the call.
