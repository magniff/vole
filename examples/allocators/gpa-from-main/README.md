# Where allocation comes from: `fn main(gpa: Gpa)`

A shop's orders, read from stdin (`customer item quantity price`, the
price in cents), totalled per customer and per item. The program is
small on purpose: what it shows is where its memory comes from.

Since vole 0.16 nothing allocates unless it is given an allocator.
There is no global `malloc` to reach for: the general-purpose allocator
is a value of type `Gpa`, `main` receives it as a parameter, and a
function that allocates either takes one as a parameter or works on a
container that holds one. So a function's signature says whether it can
allocate, and the compiler can prove it: `volec query effects` lists
what each function may do.

Every command below is run by `tests/walkthrough/run.sh` in a copy of
this directory, and its output is checked against this file;
`tests/examples/allocators-gpa-from-main.test` runs the program.

## Run it

```console
$ volec main.vl -o orders && ./orders < orders.txt
alice       4.55
bob         3.10
carol      11.00
dave       10.00
6 orders, 3 items, total 28.65
apples sold: 14
ok: built orders
skipped: bob apples one 120
```

## The allocator is a parameter

`main` takes the allocator as its last parameter (after `argc, argv`
when it takes those too). The runtime makes the one `Gpa` a program has
and passes it in; a program whose `main` takes none cannot allocate at
all (see [fixed-buffer](../fixed-buffer/)).

```vole
fn main(gpa: Gpa) -> i32 {
    let input = io::read_to_string_in(io::stdin(), gpa).unwrap();
    let orders = parse_orders(&input, gpa);
```

Each standard-library function that allocates has an `_in` form taking
the allocator last: `Vec::new_in(gpa)`, `String::new_in(gpa)`,
`HashMap::new_in(gpa)`, `io::read_to_string_in(r, gpa)`,
`format_in("..", gpa)`, `it.collect_in(gpa)`. A function of the program
that allocates takes it the same way and passes it on:

```vole
fn parse_orders<'a>(text: &'a str, gpa: Gpa) -> Vec<Order<'a>, Gpa> {
    let mut orders: Vec<Order<'a>, Gpa> = Vec::new_in(gpa);
    for line in text.lines() {
        let w: Vec<&str, Gpa> = line.split_whitespace().collect_in(gpa);
```

There are four kinds of function in `main.vl`, by what they are given:

| function | signature | allocates |
|---|---|---|
| `parse_orders` | `(text: &str, gpa: Gpa) -> Vec<Order, Gpa>` | from the `gpa` it is passed |
| `total` | `(orders: &[Order]) -> i64` | never: a slice and no allocator |
| `by_customer` | `(orders: &Vec<Order, Gpa>) -> HashMap<&str, i64, Gpa, FixedState>` | from the allocator the Vec holds: `orders.allocator()` |
| `count_items` | `<A: Allocator>(orders: &[Order], a: A) -> HashMap<&str, i64, A, FixedState>` | from whichever allocator the caller picks |

A container keeps its allocator, and its type names it: `Vec<T, Gpa>`
(three words: a `Gpa` takes no bytes). Its
`push`, `clone` and drop use the allocator it holds. That is why
`by_customer` needs no allocator parameter: it makes its map on the one
the orders' Vec was made with. And it is why `total`, which takes a
slice, cannot allocate: a slice is a view, it holds no allocator.

## What the compiler knows

`query effects` prints what each function may do, inferred from its
body and everything it calls (`volec guide effects`):

```console
$ volec query effects crate
crate::parse_orders	alloc(Gpa) io static panic diverge
crate::total	none
crate::by_customer	alloc(Gpa) panic diverge
count_items<Gpa>	alloc(Gpa) panic diverge
crate::main	alloc(Gpa) io static panic diverge
```

`total` is `none`: no allocation, no I/O, no statics, and not even a
possible panic. `count_items` is generic, so its effects are its
instances': here only `Gpa`. `parse_orders` does I/O (`eprintln` of a
bad line). For any effect in a set, `query effects parse_orders --why
io` (or `--why diverge`) shows the chain of calls it comes from.

## Forgetting the allocator

A type that names no allocator, or a call that takes one from nowhere,
is an error. Here `main` has the allocator and `shout` takes it, but
the calls and the types do not say so:

```console
$ cat > old.vl <<'EOF'
> fn shout(words: &[&str], gpa: Gpa) -> String {
>     let mut b = String::new();
>     for w in words {
>         if b.len() > 0 {
>             b.push_str(" ");
>         }
>         b.push_str(w);
>         b.push_str("!");
>     }
>     b
> }
>
> fn main(gpa: Gpa) -> i32 {
>     let mut words: Vec<&str> = Vec::new();
>     for w in "hello explicit allocation".split_whitespace() {
>         words.push(w);
>     }
>     let b = shout(words.as_slice(), gpa);
>     println("{b}");
>     0
> }
> EOF
$ volec check old.vl
old.vl:1:39: error[alloc.default] 'String' names no allocator: its 'A' is written, last | help: the allocator is part of the type: `Gpa` (the type of main's `gpa`), or a generic `A: Allocator` | try: volec fix --only alloc old.vl | try: volec fix --suggested old.vl
old.vl:2:17: error[alloc.no_in] 'String::new' allocates from nothing: pass the allocator, last, to 'String::new_in' | help: this function's `gpa` is the allocator to pass | try: volec fix --only alloc old.vl | try: volec fix --suggested old.vl
old.vl:14:20: error[alloc.default] 'Vec' names no allocator: its 'A' is written, last | help: the allocator is part of the type: `Gpa` (the type of main's `gpa`), or a generic `A: Allocator` | try: volec fix --only alloc old.vl | try: volec fix --suggested old.vl
old.vl:14:32: error[alloc.no_in] 'Vec::new' allocates from nothing: pass the allocator, last, to 'Vec::new_in' | help: this function's `gpa` is the allocator to pass | try: volec fix --only alloc old.vl | try: volec fix --suggested old.vl
[exit 1]
```

A call that allocates from nothing is `alloc.no_in`, naming its `_in`
form; a type that names no allocator is `alloc.default` (there is no
default allocator type). `fix --only alloc` makes the whole change:
every call becomes its `_in` form, passed the allocator in scope, and
every type names it:

```console
$ volec fix --only alloc --dry-run old.vl
--- a/old.vl
+++ b/old.vl
@@ -1,2 +1,2 @@
-fn shout(words: &[&str], gpa: Gpa) -> String {
-    let mut b = String::new();
+fn shout(words: &[&str], gpa: Gpa) -> String<Gpa> {
+    let mut b = String::new_in(gpa);
@@ -14 +14 @@
-    let mut words: Vec<&str> = Vec::new();
+    let mut words: Vec<&str, Gpa> = Vec::new_in(gpa);
$ volec fix --only alloc old.vl
fixed 4 suggested fixes	old.vl	+3 -3 lines
$ volec old.vl -o old && ./old
hello! explicit! allocation!
ok: built old
```

It compiles and runs, and frees what it allocated: `words`
and `b` are dropped at the end of `main`, so `--check-alloc` (below)
finds nothing left:

```console
$ volec --check-alloc old.vl -o old && ./old
hello! explicit! allocation!
ok: built old
```

A function that allocates and is not given an allocator cannot make
one: `gpa` is a name like any other, and here it is not in scope.

```console
$ cat > count.vl <<'EOF'
> fn count(text: &str) -> usize {
>     let words: Vec<&str, Gpa> = text.split_whitespace().collect_in(gpa);
>     words.len()
> }
>
> fn main(gpa: Gpa) -> i32 {
>     println("{}", count("one two three"));
>     0
> }
> EOF
$ volec check count.vl
count.vl:2:68: error[type error] undefined variable 'gpa' | help: a 'gpa: Gpa' comes from 'fn main(gpa: Gpa)': add the parameter `gpa: Gpa` to 'count' and pass it down | try: volec refactor signature count --add 'gpa: Gpa = gpa' --fill-calls --no-check count.vl
[exit 1]
```

The fix is a parameter, and the allocator passed at every call;
`refactor signature` does both (`--fill-calls`: each call gets `gpa`,
which is in scope at every call since the callers have one):

```console
$ volec refactor signature count --add 'gpa: Gpa = gpa' --fill-calls count.vl
added parameter gpa: Gpa to crate::count, 1 call	count.vl	+2 -2 lines
$ volec count.vl -o count && ./count
3
ok: built count
```

Nor can a `Gpa` be made, or kept in a static: `Gpa`'s one field is
private to std, so only std makes one (the one `main` gets), and a
static's type may hold no allocator (`alloc.static`).

```console
$ cat > forge.vl <<'EOF'
> static mut CACHE: Vec<i64, Gpa> = Vec::new_in(Gpa {});
>
> fn main() -> i32 {
>     let mine = Gpa {};
>     0
> }
> EOF
$ volec check forge.vl
forge.vl:1:1: error[alloc.static] the static 'CACHE' holds an allocator, 'Gpa' (in its type 'Vec<i64, Gpa>'): a static's type may not hold one | help: any function could allocate through it with nothing in its signature saying so: keep the value in main and pass it down (or what it allocates, as a slice)
forge.vl:1:47: error[field.literal-private] cannot make a 'Gpa' here: its field 'sealed' is private to module 'std::alloc' | help: a 'gpa: Gpa' comes from 'fn main(gpa: Gpa)' and is passed down as a parameter
forge.vl:4:16: error[field.literal-private] cannot make a 'Gpa' here: its field 'sealed' is private to module 'std::alloc' | help: a 'gpa: Gpa' comes from 'fn main(gpa: Gpa)' and is passed down as a parameter
[exit 1]
```

So the rule the effects state holds for every program: **a function
allocates only from allocators it was given** (its parameters, what it
captures, the containers it was handed) **or reaches through statics**
(and then it has the effect `static` too).

## Checking the frees

Every container here is dropped at the end of its scope: no `free` is
written. `--check-alloc` builds the program with a checking `Gpa` that
lists, at exit, every block still allocated (and stops at a use after
free or a double free: see [check-alloc](../check-alloc/)). It lists
nothing here: stdout is as before, and stderr has only the skipped
line.

```console
$ volec --check-alloc main.vl -o orders-checked && ./orders-checked < orders.txt > /dev/null
ok: built orders-checked
skipped: bob apples one 120
```

## Read more

- `volec guide allocators`: the `_in` forms, containers and their
  allocator, arenas, `--check-alloc`, `fix --only alloc`.
- `volec guide effects`: what `alloc(Gpa)`, `io`, `static`, `panic`,
  `diverge` mean, and how to promise them.
- [arena-parser](../arena-parser/), [scoped-arena](../scoped-arena/) and
  [fixed-buffer](../fixed-buffer/): the other allocators.
