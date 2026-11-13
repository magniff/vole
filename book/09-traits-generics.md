# 9. Traits and generics

You've already used code that works for many types: a `Vec` of `i64`s
and a `Vec` of `&str`s are one `Vec`, and `sort` sorts numbers and
words alike. In
this chapter you'll write code like that yourself.

By the end you'll be able to write *generic* functions and types, which
take types as parameters; define *traits*, which say what a type can
do, and implement them for your types and for std's; make `+`, `<` and
`{x}` work on your own types; and handle a list of mixed kinds of things
with an enum, since vole has no trait objects. The running example is a
small geometry library: points, circles and rectangles.

## Generic functions

Here is a function that finds the largest element of a slice. Save it as
`largest.vl`:

```vole largest.vl
fn largest<T: PartialOrd + Copy>(items: &[T]) -> T {
    let mut best = items[0];
    for &x in items {
        if x > best {
            best = x;
        }
    }
    best
}

fn main() {
    let scores = [3, 9, 4];
    let words = ["pear", "fig", "plum"];
    println("{}", largest(&scores));
    println("{}", largest(&words));
    println("{}", largest::<f64>(&[1.5, 0.5]));
}
```

```out
9
plum
1.5
```

`<T: PartialOrd + Copy>` after the name makes `T` a *type parameter*: a
stand-in for a type, chosen at each call. `items: &[T]` is a slice of
`T`s, and the result is a `T`. The part after the colon is two
*bounds*, joined with `+`: they say what `T` must be able to do.
`PartialOrd` is for types whose values can be compared, which is what
`x > best` needs. `Copy` is for types that are copied and not moved
(chapter 4), which is what lets `items[0]` come out of a slice that is
only borrowed. Numbers and `&str` are both; you'll see how to give your
own types these abilities later in the chapter.

At each call, the compiler works out `T` from the arguments: `i32` for
the scores, `&str` for the words. When you want to say it yourself,
write it after `::`, as in `largest::<f64>(...)`. You met this
*turbofish* in chapter 2, with `parse::<i64>()`. As in chapter 7,
`&scores` borrows the array as a slice.

A generic function is a template. For each type it's used with, the
compiler makes a separate copy, with `T` replaced by that type, and
compiles it as if you had written it by hand. So `largest::<i32>` is as
fast as a `largest` written only for `i32`s, and there's nothing to look
up while the program runs.

## Generic types

Structs and enums can take type parameters too. `Option<T>` and
`Vec<T, A>` are written this way in std. Here is a stack of anything:

```vole
use std::alloc::Allocator;

struct Stack<T, A: Allocator> {
    items: Vec<T, A>,
}

impl<T, A: Allocator> Stack<T, A> {
    fn new_in(alloc: A) -> Stack<T, A> {
        Stack { items: Vec::new_in(alloc) }
    }

    fn push(&mut self, x: T) {
        self.items.push(x);
    }

    fn pop(&mut self) -> Option<T> {
        self.items.pop()
    }

    fn len(&self) -> usize {
        self.items.len()
    }
}

impl Stack<i64, Gpa> {
    fn sum(&self) -> i64 {
        let mut t = 0;
        for x in &self.items {
            t += x;
        }
        t
    }
}

fn main(gpa: Gpa) {
    let mut numbers: Stack<i64, Gpa> = Stack::new_in(gpa);
    numbers.push(4);
    numbers.push(9);
    println("{} {} {:?}", numbers.len(), numbers.sum(), numbers.pop());

    let mut names: Stack<&str, Gpa> = Stack::new_in(gpa);
    names.push("ada");
    println("{} {:?}", names.len(), names.pop());
}
```

```out
2 13 Some(9)
1 Some("ada")
```

A `Stack` has two type parameters, like the `Vec` inside it: `T`, what
it holds, and `A`, the allocator its memory comes from, which must be
an `Allocator` ([chapter 8](08-allocation.md)). `impl<T, A: Allocator>
Stack<T, A>` gives methods to every `Stack`, whatever `T` and `A` are.
`push` takes its value by value, `x: T`, because the stack keeps it
(chapter 4). `impl Stack<i64, Gpa>` gives a method only to stacks of
`i64`s: `sum` adds numbers, so it wouldn't make sense for a stack of
`&str`s, and calling `names.sum()` is an error.

A *type alias* gives a type a shorter name: `type Pair<T> = (T, T);`
makes `Pair<i64>` mean `(i64, i64)`. It's the same type, under another
name.

## Traits

`largest` needed its `T` to be comparable, and `PartialOrd` is how it
said so. `PartialOrd` is a *trait*: a named set of functions that a
type can provide.
Let's write a trait of our own. Start `shapes.vl`:

```vole shapes.vl
trait Shape {
    fn area(&self) -> f64;

    fn name(&self) -> &'static str {
        "shape"
    }
}

struct Circle {
    radius: f64,
}

struct Rect {
    width: f64,
    height: f64,
}

impl Shape for Circle {
    fn area(&self) -> f64 {
        3.14159 * self.radius * self.radius
    }

    fn name(&self) -> &'static str {
        "circle"
    }
}

impl Shape for Rect {
    fn area(&self) -> f64 {
        self.width * self.height
    }
}

fn main() {
    let c = Circle { radius: 2.0 };
    let r = Rect { width: 3.0, height: 4.0 };
    println("{} {:.2}", c.name(), c.area());
    println("{} {:.2} {}", r.name(), r.area(), Rect::area(&r));
}
```

```out
circle 12.57
shape 12.00 12
```

The trait declares two functions. `area` has no body, so every type
that implements `Shape` must write one. `name` has a body, a *default*,
used by any type that doesn't write its own: `Circle` does, `Rect`
doesn't, so a `Rect`'s name is `"shape"`.

`impl Shape for Circle` is where `Circle` provides the functions. Once
it has, they are `Circle`'s methods: `c.area()`. You can also call them
by the type's name, `Rect::area(&r)`.

Leave out a function that has no default, and the compiler says which
one:

```vole
trait Shape {
    fn area(&self) -> f64;

    fn name(&self) -> &'static str {
        "shape"
    }
}

struct Square {
    side: f64,
}

impl Shape for Square {
    fn name(&self) -> &'static str {
        "square"
    }
}

fn main() {
    let s = Square { side: 2.0 };
    println("{}", s.name());
}
```

```err
error[type error]: the impl of trait 'Shape' is missing 'area'
 --> main.vl: line 13, column 1
  = help: it has no default: write it in the impl
```

A type implements a trait at most once, so there's never a question of
which `area` a call means. A second `impl Shape for Square` is an
error, `conflicting impls of trait 'Shape' for 'Square'`.

You can implement your own traits for std's types too, such as `i64` or
`&str`:

```vole
trait Describe {
    fn describe(&self) -> &'static str;
}

impl Describe for i64 {
    fn describe(&self) -> &'static str {
        if *self < 0 {
            "negative"
        } else {
            "not negative"
        }
    }
}

fn main() {
    let debt: i64 = -5;
    let savings: i64 = 7;
    println("{} {}", debt.describe(), savings.describe());
}
```

```out
negative not negative
```

> **If you know Go:** traits are like interfaces, but a type has a
> trait only when there's an `impl` that says so, and every call is
> resolved when the program is compiled.

## Bounds

With a trait, we can write a function that works on any shape:

```vole skip
fn total_area<T: Shape>(items: &[T]) -> f64 {
    let mut t = 0.0;
    for s in items {
        t += s.area();
    }
    t
}
```

`T: Shape` is a bound, like `T: PartialOrd + Copy` was. Inside the
function, all the compiler knows about `T` is that it's a `Shape`, so
you may call `area` and `name` on it, and nothing else. When the bounds
get long, they can move to a `where` clause after the signature: `fn
total_area<T>(items: &[T]) -> f64 where T: Shape`.

Calling a bounded function with a type that doesn't have the trait is
an error that names the bound:

```vole
fn largest<T: PartialOrd + Copy>(items: &[T]) -> T {
    let mut best = items[0];
    for &x in items {
        if x > best {
            best = x;
        }
    }
    best
}

#[derive(Clone, Copy)]
struct Point {
    x: i64,
    y: i64,
}

fn main() {
    let points = [Point { x: 1, y: 2 }, Point { x: 3, y: 0 }];
    println("{}", largest(&points).x);
}
```

```err
error[type error]: the trait 'PartialOrd' is not implemented for 'Point'
 --> main.vl: line 19, column 19
  = help: required by the bound 'T: PartialOrd' of 'largest'
```

Which point is larger? Vole doesn't guess. You'll see two ways to tell
it in the next section: write `impl PartialOrd for Point`, or derive
one.

### Generics without bounds

A type parameter doesn't have to have a bound. There is little a
function can do with a bare `T`, though: move it, store it, hand it
back. The body is checked once, for every type `T` could be, so
anything more needs a bound that says the type can do it:

```vole
fn bigger<T>(a: T, b: T) -> T {
    if a > b {
        a
    } else {
        b
    }
}

fn main() {
    println("{}", bigger(3, 7));
}
```

```err
error[type error]: comparison requires numeric type, got 'T'
 --> main.vl: line 2, column 8
```

The error is at `a > b`: nothing says a `T` can be compared. It doesn't
matter that `main` only calls `bigger` with numbers. With the bound,
`fn bigger<T: PartialOrd>`, the body compiles, and the question moves
to each call: is this type `PartialOrd`? A bound works in both
directions: the body may use only what the bounds give it, and a caller
must bring a type that has them.

> **If you know Java or C#:** generics here are templates, as in C++:
> each type gets its own compiled copy, and nothing is erased.

## std's traits

Much of what feels built in is a trait in std, and your types can join
in. Let's give our geometry a point type, `Vec2`, that can be added,
printed and made from a pair of numbers:

```vole
use std::fmt;
use std::ops::Add;

#[derive(Clone, Copy)]
struct Vec2 {
    x: f64,
    y: f64,
}

impl Add for Vec2 {
    type Output = Vec2;

    fn add(self, o: Vec2) -> Vec2 {
        Vec2 { x: self.x + o.x, y: self.y + o.y }
    }
}

impl fmt::Display for Vec2 {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        write(f, "({}, {})", self.x, self.y)
    }
}

impl From<(f64, f64)> for Vec2 {
    fn from(p: (f64, f64)) -> Vec2 {
        Vec2 { x: p.0, y: p.1 }
    }
}

fn main() {
    let a = Vec2 { x: 1.0, y: 2.0 };
    let b = Vec2::from((0.5, 0.5));
    let c: Vec2 = (10.0, 0.0).into();
    println("{} {}", a + b, a + b + c);
}
```

```out
(1.5, 2.5) (11.5, 2.5)
```

- **Operators.** `a + b` calls `Add`'s `add`, and `type Output` says
  what type a sum is. The other arithmetic operators work the same way:
  `Sub` for `-`, `Mul` for `*`, `Div` for `/`, and `Neg` for a minus in
  front, `-a`. They live in `std::ops`. An operator takes its operands
  by value, so `Vec2` derives `Clone` and `Copy` (more on those below):
  without them, `a + b` would use `a` and `b` up.
- **Display** is the plain `{x}` in a format string. Its `fmt` borrows
  the value and gets a `Formatter` to write the text to, with `write(f,
  ...)`, whose `Result` it returns.
- **From and Into** convert between types. `impl From<(f64, f64)> for
  Vec2` makes `Vec2::from((0.5, 0.5))` work, and gives you `into()`
  for free, going the other way: `(10.0, 0.0).into()`, where the
  type it's converted into comes from `let c: Vec2`. Chapter 6 used the
  same trait to convert errors for `?`.

### Comparing: Eq and Ord

`==` comes from `PartialEq`, which chapter 5 derived. `<` and the other
comparisons come from `PartialOrd`, and a full ordering, the kind
`sort()` needs, from `Ord`, which has one function, `cmp`:

```vole
use std::cmp::Ordering;

#[derive(PartialEq, Eq)]
struct Version {
    major: i64,
    minor: i64,
}

impl Ord for Version {
    fn cmp(&self, o: &Version) -> Ordering {
        self.major.cmp(&o.major).then(self.minor.cmp(&o.minor))
    }
}

impl PartialOrd for Version {
    fn partial_cmp(&self, o: &Version) -> Option<Ordering> {
        Some(self.cmp(o))
    }
}

fn main() {
    let old = Version { major: 1, minor: 9 };
    let new = Version { major: 1, minor: 10 };
    println("{} {} {:?}", old < new, old == new, old.cmp(&new));
}
```

```out
true false Less
```

`cmp` returns an `Ordering`: `Less` if `self` comes first, `Equal`, or
`Greater` if `o` comes first. Here it compares the major numbers, and
`then` falls back on the minor ones when those are equal, as the word
counter's `sort_by` did in chapter 7.

Why two traits for one idea? Some types are only partly ordered. An
`f64` can be NaN, "not a number", which is neither less than, equal to,
nor greater than anything, so `f64` has `PartialOrd` (whose
`partial_cmp` may answer `None`) and not `Ord`. That is why `largest`
asked for `PartialOrd`: it wanted to work on floats too. For a type
with a full order, `partial_cmp` just passes the question to `cmp`.
`Eq` is to `PartialEq` what `Ord` is to `PartialOrd`: it has no
function of its own, and says that `==` is a full equality. With all
four, `Version`s can be compared with `<`, sorted with `sort()`, and
given to `largest` once they are `Copy`.

### Deriving

Writing `Ord`, `Hash` or `Debug` by hand gets old for a struct with
many fields, and the compiler can write them for you:

```vole
use std::collections::HashMap;
use std::hash::FixedState;

#[derive(PartialEq, Eq, PartialOrd, Ord, Hash, Debug, Clone, Copy)]
struct Version {
    major: i64,
    minor: i64,
}

fn main(gpa: Gpa) {
    let mut versions: Vec<Version, Gpa> = Vec::new_in(gpa);
    versions.push(Version { major: 1, minor: 10 });
    versions.push(Version { major: 0, minor: 9 });
    versions.push(Version { major: 1, minor: 2 });
    versions.sort();
    println("{versions:?}");

    let mut notes: HashMap<Version, &str, Gpa, FixedState> = HashMap::new_in(gpa);
    let current = Version { major: 1, minor: 10 };
    notes.insert(current, "current");
    println("{:?}", notes.get(&current));
}
```

```out
[Version { major: 0, minor: 9 }, Version { major: 1, minor: 2 }, Version { major: 1, minor: 10 }]
Some("current")
```

`#[derive(...)]` before a struct or an enum writes the impls:

- `PartialEq` and `Eq`: `==`, field by field.
- `PartialOrd` and `Ord`: compare the first field, then the next one if
  those are equal, and so on, in the order the fields are declared. For
  an enum, the earlier variant comes first.
- `Hash`: a hash of all the fields, so the type can be a `HashMap` key
  (with `Eq`).
- `Debug`: the `{x:?}` form, as in `Version { major: 0, minor: 9 }`.
- `Clone`: `x.clone()`, a copy of every field (a `Vec` field is copied
  too, with all its elements).
- `Copy`: the value is copied where it would otherwise move, as numbers
  are (chapter 4). That is why `current` can still be used after
  `notes.insert(current, ...)` above. Only a type whose fields are all
  `Copy` can be, and it needs `Clone` too.

`Display` can't be derived: how your type looks to a user is for you to
decide.

A misspelled derive is an error that lists the ones there are:

```vole
#[derive(Debg)]
struct Point {
    x: i64,
    y: i64,
}

fn main() {
    let p = Point { x: 1, y: 2 };
    println("{p:?}");
}
```

```err
error[type error]: cannot derive 'Debg' (derivable: PartialEq, Eq, PartialOrd, Ord, Hash, Debug, Clone, Copy, Default)
 --> main.vl: line 1, column 10
error[type error]: 'Point' does not implement Debug, which '{x:?}' needs
 --> main.vl: line 9, column 15
  = help: derive it: '#[derive(Debug)]' before the type, or write 'impl Debug for Point { fn fmt_debug(self, f: inout std::Fmt) { f.write("..", args); } }'
```

The second error follows from the first: fix the spelling and both go
away. This is a case for fixing errors from the top, as chapter 1
advised.

std has a few more traits you'll meet. One is `Default`, for types
with an obvious starting value: `#[derive(Default)]` writes it, and
`Version::default()` is then a `Version` of zeros.

## No trait objects: enums instead

Now for a list of mixed shapes: some circles, some rectangles. In many
languages you'd make a list of "anything that is a Shape". Try that in
vole:

```vole
trait Shape {
    fn area(&self) -> f64;
}

fn total(shapes: &[Shape]) -> f64 {
    let mut t = 0.0;
    for s in shapes {
        t += s.area();
    }
    t
}

fn main() {}
```

```err
error[type error]: 'Shape' is a trait, not a type (no trait objects: use a type parameter bounded by it, 'T: Trait')
 --> main.vl: line 5, column 20
```

A trait is not a type in vole. Every call to a trait's function is
decided when the program is compiled, never while it runs. A `&[T]`
with `T: Shape` is a slice of one kind of shape: all circles, or all
rectangles.

For a list of mixed kinds, use an enum with a variant for each kind,
and implement the trait for the enum by matching. Here is the finished
`shapes.vl`, with everything from this chapter in it:

```vole shapes.vl
use std::fmt;
use std::ops::Add;

#[derive(Clone, Copy)]
struct Vec2 {
    x: f64,
    y: f64,
}

impl Add for Vec2 {
    type Output = Vec2;

    fn add(self, o: Vec2) -> Vec2 {
        Vec2 { x: self.x + o.x, y: self.y + o.y }
    }
}

impl fmt::Display for Vec2 {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        write(f, "({}, {})", self.x, self.y)
    }
}

trait Shape {
    fn area(&self) -> f64;

    fn name(&self) -> &'static str {
        "shape"
    }
}

struct Circle {
    center: Vec2,
    radius: f64,
}

struct Rect {
    corner: Vec2,
    size: Vec2,
}

impl Shape for Circle {
    fn area(&self) -> f64 {
        3.14159 * self.radius * self.radius
    }

    fn name(&self) -> &'static str {
        "circle"
    }
}

impl Shape for Rect {
    fn area(&self) -> f64 {
        self.size.x * self.size.y
    }

    fn name(&self) -> &'static str {
        "rectangle"
    }
}

impl fmt::Display for Circle {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        write(f, "a circle at {} with radius {}", self.center, self.radius)
    }
}

enum AnyShape {
    Circle(Circle),
    Rect(Rect),
}

impl Shape for AnyShape {
    fn area(&self) -> f64 {
        match self {
            AnyShape::Circle(c) => c.area(),
            AnyShape::Rect(r) => r.area(),
        }
    }

    fn name(&self) -> &'static str {
        match self {
            AnyShape::Circle(c) => c.name(),
            AnyShape::Rect(r) => r.name(),
        }
    }
}

fn total_area<T: Shape>(items: &[T]) -> f64 {
    let mut t = 0.0;
    for s in items {
        t += s.area();
    }
    t
}

fn describe<T: Shape + fmt::Display>(s: &T) {
    println("{s}: area {:.2}", s.area());
}

fn main(gpa: Gpa) {
    let origin = Vec2 { x: 0.0, y: 0.0 };
    let c = Circle { center: origin + Vec2 { x: 1.0, y: 1.0 }, radius: 2.0 };
    describe(&c);

    let mut shapes: Vec<AnyShape, Gpa> = Vec::new_in(gpa);
    shapes.push(AnyShape::Circle(c));
    shapes.push(AnyShape::Rect(Rect { corner: origin, size: Vec2 { x: 3.0, y: 4.0 } }));
    shapes.push(AnyShape::Circle(Circle { center: origin, radius: 0.5 }));
    for s in &shapes {
        println("{:<10} {:>6.2}", s.name(), s.area());
    }
    println("{:<10} {:>6.2}", "total", total_area(&shapes));
}
```

```out
a circle at (1, 1) with radius 2: area 12.57
circle      12.57
rectangle   12.00
circle       0.79
total       25.35
```

`AnyShape` is a `Shape` too, so `total_area` works on a slice of them
like on a slice of circles. Each call to `area` on an `AnyShape` is a
`match` that picks the right function. (`describe` has two bounds: its
`T` is a shape that can also be printed.)

Why does vole work this way? A trait object in other languages is a
pointer to the value plus a hidden table of functions, looked up on
every call, and the value usually has to live on the heap. The enum has
no hidden pointers, needs no allocation, and its `match` is checked:
add a `Triangle` variant, and the compiler lists every `match` that
needs a new arm (chapter 5). The cost is that the list of kinds is
closed: someone using your library can't add a shape of their own
without changing the enum. This is a current design choice of a young
language, and may change.

If you write `dyn Shape`, the way Rust spells a trait object, the
compiler stops at the word: `'dyn' is a reserved keyword (reserved for
future use)`.

## Associated types: a short look

A trait can declare a type that each implementation chooses, an
*associated type*. You'll meet the most important one in the next
chapter: `Iterator` declares `type Item;`, the type of the values it
produces. Here is the idea on a small trait of our own:

```vole
trait Inventory {
    type Item;
    fn first(&self) -> Option<Self::Item>;
}

struct Shelf {
    books: [&'static str; 2],
}

impl Inventory for Shelf {
    type Item = &'static str;

    fn first(&self) -> Option<&'static str> {
        Some(self.books[0])
    }
}

fn first_of<I: Inventory>(inv: &I) -> Option<I::Item> {
    inv.first()
}

fn main() {
    let s = Shelf { books: ["Dune", "Emma"] };
    println("{:?}", first_of(&s));
}
```

```out
Some("Dune")
```

`type Item = &'static str;` in the impl says what `Item` is for a
`Shelf`, and `I::Item` in `first_of` means "whatever `Item` is for this
`I`". `Add`'s `type Output` was one of these.

## Summary

- A generic function or type takes type parameters, `<T>`; the compiler
  infers them, or you write them with the turbofish, `f::<i64>(...)`.
  Each type used gets its own compiled copy, so generics cost nothing
  at run time.
- A trait names functions a type provides; an `impl Trait for Type`
  provides them, once per type. A trait can have default functions.
- Bounds, `T: Shape + Display`, say what a type parameter must have;
  the compiler checks them at each call.
- Operators, printing and conversions are std's traits: `Add`, `Sub`,
  `Mul`, `Div`, `Neg`, `PartialEq` and `Eq`, `PartialOrd` and `Ord`
  (`cmp` returns an `Ordering`), `Hash`, `Display`, `Debug`, `From` and
  `Into`. `#[derive]` writes the comparisons, `Hash`, `Debug`, `Clone`,
  `Copy` and `Default`.
- There are no trait objects: for a list of mixed kinds, use an enum
  that implements the trait by matching.
- A trait can have an associated type, `type Item;`.

The next chapter puts traits and generics to work, with closures and
iterators.

## Try it yourself

- Add a `Triangle { base: f64, height: f64 }` to `shapes.vl`, as a
  `Shape` and as a variant of `AnyShape`, and see which `match`es the
  compiler asks you to update.
- Implement `Sub` and `Neg` for `Vec2`, and print `-(a - b)`.
- Derive the four comparison traits for a `struct Card { rank: i64,
  suit: i64 }`, sort a hand of five cards, and print it with
  `#[derive(Debug)]`.
