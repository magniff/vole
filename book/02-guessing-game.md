# 2. A guessing game

Let's write a real program. It's a classic: the computer picks a number
between 1 and 100, you guess, and it tells you whether your guess is
too small or too big until you get it right.

The game is small, but it touches a lot of vole: reading input,
variables, text, numbers, decisions, loops, errors, and a library
module. This chapter moves fast and explains each idea only as far as
the game needs. Don't worry if something feels unexplained; the
chapters after this one go through every idea properly, and this one
points to them as it goes.

We'll build the game in four steps, running it after each one.

## Step 1: reading a guess

Start a new file, `guess.vl`, with a program that asks for a guess,
reads it and prints it back:

```vole guess.vl
use std::io;

fn main(gpa: Gpa) {
    println("Guess the number!");
    println("Please input your guess.");

    let mut line = String::new_in(gpa);
    io::stdin().read_line(&mut line).unwrap();

    println("You guessed: {}", line.trim());
}
```

Build it and run it. When it waits, type a number and press Enter:

```console
$ volec guess.vl -o guess
ok: built guess
```

```text
$ ./guess
Guess the number!
Please input your guess.
42
You guessed: 42
```

There is quite a lot in these few lines. Let's go through them.

### Using the standard library

```vole skip
use std::io;
```

Vole comes with a standard library, `std`, organized in modules.
`std::io` is the module for input and output. This line makes it
available under its last name, `io`, so we can write `io::stdin()`.
A `use` line can also bring one item of a module into scope by name:
after `use std::io::stdin;` the call would be just `stdin()`.

In chapter 1 we used `println` without any `use` line, because it's in
the prelude, the handful of names every file gets for free. Everything
else in the standard library is imported like this, one name at a
time. Vole has no way to import "everything from a module": every name a
file uses is either defined in it, imported by name, or written out as
a path like `std::io::stdin`. When you read vole code, you can always
find where a name comes from.

### The allocator

```vole skip
fn main(gpa: Gpa) {
```

This `main` takes a parameter: `gpa`, of type `Gpa`, the program's
*general-purpose allocator*. An allocator is where memory comes from.
The text you type has to be stored somewhere, and its length isn't
known in advance, so the program needs memory it can grow.

In many languages, memory comes from a hidden global allocator that
any function can use. Vole doesn't have one. A program gets its
allocator as a parameter of `main`, and passes it to whatever needs
memory. That makes it visible in the code which parts of a program
allocate, and it lets you choose a different allocator for some part of
it. Chapter 8 is all about this; for now, `fn main(gpa: Gpa)` is how
a program that needs memory starts.

### Variables

```vole skip
    let mut line = String::new_in(gpa);
```

This line makes a variable. A variable made with `let mut` can change
later; one made with a plain `let` cannot. We'll be changing this one,
so it is a `let mut`.

`line` is a `String`, a growable piece of text. `String::new_in(gpa)`
makes an empty one that gets its memory from `gpa`. (`Type::name` is
how you call a function that belongs to a type.) The `_in` at the end
of the name is a convention you'll see all over the standard library:
it marks a function that allocates, and it takes the allocator as its
last argument.

What happens if you forget the allocator? Here's a program that tries:

```vole
fn main() {
    let mut line = String::new();
    line.push_str("hi");
    println("{line}");
}
```

```err
error[alloc.no_in]: 'String::new' allocates from nothing: pass the allocator, last, to 'String::new_in'
 --> main.vl: line 2, column 20
  = help: main takes the allocator: `fn main(gpa: Gpa)`, passed down as a parameter
  = try: volec fix --only alloc main.vl
```

The error says what to write instead, and its `help:` line says where
the allocator comes from. Many vole errors end with `try:` lines like
these. They are meant to be used as they are: either code to put where
the error is, or a command to run. `volec fix` is a command that
rewrites code for you; we'll meet it properly in chapter 17.

### Reading the line

```vole skip
    io::stdin().read_line(&mut line).unwrap();
```

`io::stdin()` is the program's standard input: what you type, or what
another program sends it. `read_line` reads one line from it and
appends it to `line`.

Look at the `&mut` in `&mut line`. In vole, a function can't change a
value you pass it unless it says so in its signature, and when it does,
the call says so too, with `&mut`: the function *borrows* `line` for
the length of the call, with permission to change it. Reading this
line, you know that `read_line` will change `line`, and that's the
only argument it may change. A plain `&line` lends the value for
reading only. Write that here and the compiler stops you:

```vole guess.vl
use std::io;

fn main(gpa: Gpa) {
    println("Guess the number!");
    println("Please input your guess.");

    let mut line = String::new_in(gpa);
    io::stdin().read_line(&line).unwrap();

    println("You guessed: {}", line.trim());
}
```

```err
error[type error]: expected '&mut String<Gpa>', got '&String<Gpa>'
 --> guess.vl: line 8, column 27
  = help: the types differ in mutability (rustc E0308): the parameter takes an exclusive reference, `&mut x`
  = try: &mut line
  = try: volec fix --suggested guess.vl
```

The error says what `read_line` expects, a `&mut String<Gpa>` (a
`String` whose memory comes from a `Gpa`), and what it got. It also
says how to fix it: the first `try:` line is the code to write there,
and the second is a command that fixes every error in the file that has
an exact fix.

This idea, that functions say what they do with their arguments, is at
the heart of vole. Chapter 3 has more on `let` and `let mut`, and
chapter 4 explains borrowing.

Reading can fail: the input might be closed, or a disk might fail.
So `read_line` doesn't return the number of bytes it read directly. It
returns a `Result`, a value that is either `Ok` with the number in it
or `Err` with an error. `.unwrap()` takes the number out of an `Ok`, and
stops the program with an error message if it's an `Err`. That's
the right choice for a first program; chapter 6 shows how to handle
errors properly.

### Printing with a format string

```vole skip
    println("You guessed: {}", line.trim());
```

The first argument of `println` is a *format string*: each `{}` in it is
replaced by the value of the next argument, and `{name}` by the value of
the variable `name` (`println("{line}")`). `line.trim()` is
`line` without the spaces and the newline around it. (When you type a
number and press Enter, the Enter is part of the line.)

## Step 2: comparing with a secret

Now let's give the game a secret number and compare the guess with it.
For the moment, the secret is always 42. Random numbers come in the
last step; a fixed number makes the game much easier to test.

```vole guess.vl
use std::io;

fn main(gpa: Gpa) {
    println("Guess the number!");
    let secret = 42;

    println("Please input your guess.");
    let mut line = String::new_in(gpa);
    io::stdin().read_line(&mut line).unwrap();

    let guess = line.trim().parse::<i32>().unwrap();
    println("You guessed: {guess}");

    if guess < secret {
        println("Too small!");
    } else if guess > secret {
        println("Too big!");
    } else {
        println("You win!");
    }
}
```

If you type 50, it says:

```in
50
```

```out
Guess the number!
Please input your guess.
You guessed: 50
Too big!
```

`let secret = 42;` makes a variable that never changes, so it's a
`let`. Its type is `i32`, a 32-bit signed integer: vole picks `i32` for
a whole number unless something says otherwise.

The line we read is text, and we want to compare numbers, so we
convert it:

```vole skip
    let guess = line.trim().parse::<i32>().unwrap();
```

`parse::<i32>()` reads the text as an `i32`. The `::<i32>` part says
which type to parse into; you'll see this form, called a *turbofish*,
whenever a function needs to be told a type. Parsing can fail too (what
if the user types "seven"?), so `parse` returns a `Result` as well, and
we `unwrap` it.

Then `if`, `else if` and `else` pick one of three messages. A
condition doesn't need parentheses around it, but the braces around
each branch are required.

### When unwrap stops the program

What happens if you type something that isn't a number? Let's ask the
shell to type it for us, using a pipe:

```console
$ volec guess.vl -o guess
ok: built guess
$ echo seven | ./guess
Guess the number!
Please input your guess.
guess.vl:11:17: requires failed: 'self.is_ok()' of 'Result<i32, ParseIntError>::unwrap' (<std>:2849:13)
$ echo $?
101
```

`parse` returned an `Err`, and `unwrap` stopped the program. The message
starts with the file, line and column of the `unwrap` that failed. Then
it says which check failed: `unwrap` requires its `Result` to be an
`Ok` (that is the `self.is_ok()`), and this one wasn't. The position at
the end is where the standard library states that requirement. The
program exits with status 101, which in vole always means "stopped by
a failed check". A failure like this is called a *panic*.

A panic is not a crash. Vole checks the things that could go wrong in a
program (an index past the end of a list, an `unwrap` of an error), and
stops cleanly with a message when one does, instead of reading or
writing memory it shouldn't. We'll handle bad input properly in the next step.

## Step 3: guessing until you win

One guess isn't much of a game. Let's keep asking until the guess is
right, and deal with input that isn't a number instead of stopping:

```vole guess.vl
use std::io;

fn main(gpa: Gpa) {
    println("Guess the number!");
    let secret = 42;

    let mut line = String::new_in(gpa);
    let mut tries = 0;

    loop {
        println("Please input your guess.");
        line.clear();
        if io::stdin().read_line(&mut line).unwrap() == 0 {
            println("Giving up? The number was {secret}.");
            return;
        }

        let guess = match line.trim().parse::<i32>() {
            Ok(n) => n,
            Err(_) => {
                println("That's not a number. Try again.");
                continue;
            }
        };
        tries += 1;

        if guess < secret {
            println("Too small!");
        } else if guess > secret {
            println("Too big!");
        } else {
            println("You win! It took you {tries} tries.");
            break;
        }
    }
}
```

Here's a game where the player guesses 50, then 25, then types "seven"
by mistake, then guesses 42:

```in
50
25
seven
42
```

```out
Guess the number!
Please input your guess.
Too big!
Please input your guess.
Too small!
Please input your guess.
That's not a number. Try again.
Please input your guess.
You win! It took you 3 tries.
```

Let's look at what's new.

### loop, break and continue

```vole skip
    loop {
        ...
    }
```

`loop` repeats its body forever, until something leaves it. `break`
leaves the loop: we break when the player wins. `continue` skips the
rest of the body and starts the next round: we continue when the input
isn't a number. And `return` leaves the whole function, which for
`main` means the program ends.

Vole also has `while` and `for` loops; chapter 3 shows them.

### Reusing the line

`line.clear()` empties `line` at the start of each round, because
`read_line` *adds* to what's already there. We make `line` once,
before the loop, and reuse its memory every time.

### The end of the input

`read_line` returns how many bytes it read. Zero means there is nothing
more to read: the input has ended. That happens when input comes from a
file or a pipe, or when you press Ctrl-D in a terminal. Without that
check, the loop would ask forever, so we print the secret and leave.

### match

```vole skip
        let guess = match line.trim().parse::<i32>() {
            Ok(n) => n,
            Err(_) => {
                println("That's not a number. Try again.");
                continue;
            }
        };
```

Instead of unwrapping the result of `parse`, we look at it with
`match`. A `match` compares a value against *patterns*, one per arm,
and runs the arm that fits.

- `Ok(n) => n` fits when parsing worked. It names the number inside `n`,
  and the arm's value is `n`.
- `Err(_) => { ... }` fits when parsing failed. The `_` means we don't
  care what the error was. This arm prints a message and continues the
  loop, so it never produces a value at all.

The whole `match` is an expression: its value is the value of the arm
that ran, and that's what `guess` is set to. Vole checks that a match
covers every possible case; leave out the `Err` arm and the program
won't compile. Chapter 5 is about `match` and the types it works best
with.

### Counting tries

`let mut tries = 0;` starts a counter, and `tries += 1;` adds one to
it. Because it changes, it's a `let mut`. If you left the `mut` out,
the compiler would tell you:

```vole
fn main() {
    let tries = 0;
    tries += 1;
    println("{tries}");
}
```

```err
error[type error]: cannot assign to immutable variable 'tries'
 --> main.vl: line 3, column 5
  = help: make it mutable: `let mut tries`
```

## Step 4: a random secret

A game whose answer is always 42 gets old quickly. The standard
library has a random number generator in `std::random`. Here is the
finished game:

```vole guess.vl mvs
use std::io;
use std::io::BufReader;
use std::random::Xoshiro256pp;

fn main(gpa: Gpa) {
    println("Guess the number!");
    var rng = Xoshiro256pp::from_entropy();
    let secret = rng.random_range_i64(1, 101);

    var input = BufReader::new(io::stdin());
    var line = String::new_in(gpa);
    var tries = 0;

    loop {
        println("Please input your guess.");
        line.clear();
        if input.read_line(&line).unwrap() == 0 {
            println("Giving up? The number was {secret}.");
            return;
        }

        let guess = match line.trim().parse::<i64>() {
            Ok(n) => n,
            Err(_) => {
                println("That's not a number. Try again.");
                continue;
            }
        };
        tries += 1;

        if guess < secret {
            println("Too small!");
        } else if guess > secret {
            println("Too big!");
        } else {
            println("You win! It took you {tries} tries.");
            break;
        }
    }
}
```

Only two lines changed, besides the new `use` line:

```vole skip
    var rng = Xoshiro256pp::from_entropy();
    let secret = rng.random_range_i64(1, 101);
```

`Xoshiro256pp` is the name of a fast random number generator (the
algorithm is called xoshiro256++). `from_entropy()` starts it from
random data the operating system provides, so every game is different.
`random_range_i64(1, 101)` gives a number from 1 up to, but not
including, 101.

`rng` is a `var` because drawing a number changes the generator's
state, so the next number is different.

Here's one game. Yours will have a different secret, of course:

```text
$ ./guess
Guess the number!
Please input your guess.
50
Too big!
Please input your guess.
25
Too small!
Please input your guess.
37
Too big!
Please input your guess.
31
Too small!
Please input your guess.
34
You win! It took you 5 tries.
```

### What the compiler knows about your program

Here's a preview of something vole does that most languages don't. The
compiler works out what each function may do, and it will tell you:

```console mvs
$ volec query effects main guess.vl
crate::main	alloc(Gpa) io panic diverge
```

That one line says `main` allocates memory from a `Gpa`, does
input and output, uses some global state (`read_line` keeps its input
buffer in one), may panic (all those `unwrap`s), and may never return
(the `loop`). You never wrote any of that down: the compiler worked it
out from the code. Chapter 12 shows how to use this, and how to make the compiler
hold a function to a promise such as "this never allocates".

## Summary

You wrote a complete program, and on the way you met:

- `use` lines, which bring standard library names into scope by name;
- `fn main(gpa: Gpa)`, the allocator, and the `_in` functions that use
  it;
- `let` for values that stay put, `let mut` for ones that change;
- `&mut` at a call, marking the argument the function may change;
- `Result`, `unwrap`, and `match` on `Ok` and `Err`;
- format strings;
- `if`/`else`, `loop`, `break`, `continue` and `return`;
- panics: clean stops with a message and exit status 101.

The next chapter starts going through these ideas one at a time, with
the basics: values, types, functions and control flow.

## Try it yourself

- Make the game print "Way too big!" when the guess is more than 20
  above the secret.
- Count the invalid inputs too, and print both counts at the end.
- Make the range a constant at the top of the file: `const MAX: i64 =
  100;`, and use it in `random_range_i64` and in the opening message.
