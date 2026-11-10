# Explore unknown code

`transit` plans the quickest routes across a city's train network: a
graph of stations (`graph.vl`), a binary heap (`heap.vl`), Dijkstra's
search with a cost for changing lines (`route.vl`), the timetable
(`network.vl`) and a few trips in `main.vl`. About 280 lines.

A bug report comes in: "Airport to Museum is one 16-minute ride on line
A, but the planner says 21 minutes." This session is the first look of
someone (or some agent) who has never seen the code: what is there,
where the total comes from, who touches what, what a type is, what a
piece of syntax means, all by asking the compiler instead of reading
files from the top. Then the fix, made by name. Every command below is
run by `tests/walkthrough/run.sh` on a fresh copy of this directory, and
its output is checked against this file.

## The symptom

```console
$ volec main.vl -o transit && ./transit
Airport -> Museum: 21 min
  line A  Airport    -> Museum      16 min
Airport -> Market: 25 min
  line A  Airport    -> Central     12 min
  line B  Central    -> Market       3 min
Beach -> Stadium: 41 min
  line C  Beach      -> Harbor      11 min
  line B  Harbor     -> Stadium     20 min
Airport -> Moon: no such station
ok: built transit
```

Every total is 5 minutes more than the legs add up to (10 when the trip
changes lines once).

## 1. What is there

`query items` with no module lists the modules, their files and how many
items each has; with a module, its items' signatures and lines, like a
generated header:

```console
$ volec query items
crate	main.vl	6
std	<std>	607
crate::graph	graph.vl	10
crate::heap	heap.vl	6
crate::network	network.vl	2
crate::route	route.vl	7
$ volec query items route
# crate::route	route.vl
8	const	pub const TRANSFER_MINUTES: i64 = 5
10	struct	pub struct Leg
17	struct	pub struct Route<A: Allocator>
23	struct	struct Step
30	fn	fn ride_cost(here_line: u8, minutes: i64, line: u8) -> i64
34	fn	pub fn quickest(g: Graph<Gpa>, from: i64, to: i64, gpa: Gpa) -> Option<Route<Gpa>>
68	fn	fn legs_to(how: Vec<Step, Gpa>, from: i64, to: i64, gpa: Gpa) -> Vec<Leg, Gpa>
```

## 2. The function that computes the total

`query context` answers in one call what takes several: the item's
source, the signatures of what it calls (the most specific first), the
types it uses and its callers, cut to a budget of tokens. What did not
fit is counted, with the commands that print it:

```console
$ volec query context quickest --budget 600
// crate::route::quickest	route.vl:34-64	effects: alloc(Gpa) panic diverge
pub fn quickest(g: Graph<Gpa>, from: i64, to: i64, gpa: Gpa) -> Option<Route<Gpa>> {
    let n = size(g);
    var best: Vec<i64, Gpa> = Vec::filled_in(n as usize, i64::MAX, gpa);
    var how: Vec<Step, Gpa> = Vec::filled_in(n as usize, Step { from: -1, line: 0, minutes: 0 },
        gpa);
    var h = new_heap(gpa);

    best[from] = 0;
    push(&h, Entry { cost: 0, node: from, line: 0 });
    while !is_empty(h) {
        let cur = pop(&h).unwrap();
        if cur.cost > best[cur.node] {
            continue;
        }
        if cur.node == to {
            break;
        }
        for e in edges_from(g, cur.node) {
            let cost = cur.cost + ride_cost(cur.line, e.minutes, e.line);
            if cost < best[e.to] {
                best[e.to] = cost;
                how[e.to] = Step { from: cur.node, line: e.line, minutes: e.minutes };
                push(&h, Entry { cost: cost, node: e.to, line: e.line });
            }
        }
    }
    if best[to] == i64::MAX {
        return None;
    }
    Some(Route { legs: legs_to(how, from, to, gpa), total: best[to] })
}
// calls (13)
crate::route::ride_cost	route.vl:30:4	fn	fn ride_cost(here_line: u8, minutes: i64, line: u8) -> i64
crate::route::legs_to	route.vl:68:4	fn	fn legs_to(how: Vec<Step, Gpa>, from: i64, to: i64, gpa: Gpa) -> Vec<Leg, Gpa>
crate::graph::size	graph.vl:21:8	fn	pub fn size(g: Graph<Gpa>) -> i64
crate::heap::new_heap	heap.vl:14:8	fn	pub fn new_heap(gpa: Gpa) -> Heap<Gpa>
crate::heap::is_empty	heap.vl:18:8	fn	pub fn is_empty(h: Heap<Gpa>) -> bool
crate::heap::pop	heap.vl:35:8	fn	pub fn pop(h: inout Heap<Gpa>) -> Option<Entry>
crate::graph::edges_from	graph.vl:53:8	fn	pub fn edges_from(g: Graph<Gpa>, i: i64) -> [Edge]
crate::heap::push	heap.vl:22:8	fn	pub fn push(h: inout Heap<Gpa>, e: Entry)
std::Vec::filled_in	<std>:1613:12	method	pub fn filled_in(n: usize, x: sink T, a: sink A) -> Vec<T, A>
std::Option::unwrap	<std>:131:12	method	pub fn unwrap(sink self) -> T requires self.is_some() else "called unwrap on None"
<std::Vec as Drop>::drop	<std>:436:8	method	fn drop(inout self)
std::Vec::as_mut_slice	<std>:396:12	method	pub fn as_mut_slice(inout self) -> inout [T]
std::Vec::as_slice	<std>:390:12	method	pub fn as_slice(self) -> [T]
// callers (1)
plan	main.vl:20:11	match quickest(g, a, b, gpa) {
note query.budget: over the budget of 600 tokens, left out: types or uses 8
try: volec query context quickest --budget 1800
```

The total is `best[to]`, the sum of `ride_cost(...)` along the way.
The context of `ride_cost` is small enough to print whole:

```console
$ volec query context ride_cost
// crate::route::ride_cost	route.vl:29-32	effects: none
// What a ride on `e` costs, arriving at its start on `here_line`.
fn ride_cost(here_line: u8, minutes: i64, line: u8) -> i64 {
    if line != here_line { minutes + TRANSFER_MINUTES } else { minutes }
}
// uses (1)
crate::route::TRANSFER_MINUTES	route.vl:8:11	const	pub const TRANSFER_MINUTES: i64 = 5
// callers (1)
route::quickest	route.vl:52:35	let cost = cur.cost + ride_cost(cur.line, e.minutes, e.line);
```

`ride_cost` adds a transfer whenever the ride's line differs from the
line the search arrived on. What line does the search arrive on at the
start?

## 3. Who writes what

`query refs` lists every resolved use, with its kind (`def`, `read`,
`write`, `init` for a struct literal, `call`, ...) and the enclosing
function. `--kind` keeps some kinds:

```console
$ volec query refs Entry.line --kind init
# route.vl
42:43	init	route::quickest	push(&h, Entry { cost: 0, node: from, line: 0 });
56:58	init	route::quickest	push(&h, Entry { cost: cost, node: e.to, line: e.line });
```

The first state is `Entry { ..., line: 0 }`. A search of the comments
says what 0 means (each hit names the item its comment documents, here
the field `Entry.line` and the function `ride_cost`):

```console
$ volec query grep start --comments
# heap.vl
6:48	comment	heap::Entry.line	// the line the state arrived on; 0 at the start
# route.vl
29:46	comment	route::ride_cost	// What a ride on `e` costs, arriving at its start on `here_line`.
```

And `query type` gives the type of the expression at a position (here
`cur`, on line 43, and the `e.minutes` passed to `ride_cost`):

```console
$ volec query type route.vl:43:13
bool	is_empty(h)
$ volec query type route.vl:51:57
()	{ let cost = cur.cost + ride_cost(cur.line, e.minutes, e.line); if cost < best[e.to] { best[e.to] =…
```

So at the start `cur.line` is 0, which is no line, and `ride_cost`
charges a transfer for the first ride. That is the bug.

## 4. Two side questions, answered without leaving the terminal

`main.vl` prints the line with `{l.line:c}`. What does `:c` do? The
guide answers from its own text:

```console
$ volec guide --find 'spec width align' --budget 900 | head -11
# formatting#format-strings
`{name:spec}`, `spec = [[fill]align][+][#][0][width][.precision][type]`:
`<` `^` `>` align (numbers go right by default, text left) with any fill
character (`{s:*^9}`), `+` signs a number, `#` writes `0x`/`0o`/`0b`
(and `0` pads after them), `0` pads a number with zeros after its sign,
the width and the precision are digits (precision also `*`: the next
argument), `.N` gives a float N decimals and cuts text to N; the type is
`?` Debug (`x?`, `X?` with hex numbers; `#?` over several lines),
`x`/`X` hex, `o` octal, `b` binary, `e`/`E` an exponent (`1.5e3`).
A width from an argument (`w$`, `1$`) is not read yet.
```vole
```

And the fix's condition, tried on a snippet before it goes in (`try`
runs statements with std imported and prints the last value with its
type):

```console
$ volec try 'println("[{:c}] [{}]", 65u8, 65u8)'
[A] [65]
$ volec try 'let here: u8 = 0; let line = 65u8; here != 0 && line != here'
bool = false
```

## 5. The fix

Before changing a function, what does the change touch? `query impact`
lists the calls by file, `query callers` each call:

```console
$ volec query impact ride_cost
crate::route::ride_cost	route.vl:30:4	fn	fn ride_cost(here_line: u8, minutes: i64, line: u8) -> i64	effects: none
route.vl	1	0	route::quickest
total	1	0	1 file
```

One call, in the same module. The fix is one condition, changed by name:

```console
$ volec edit patch ride_cost --old 'if line != here_line' --new 'if here_line != 0 && line != here_line' --show
patched crate::route::ride_cost	route.vl	+1 -1 lines
// route.vl:31
31	    if here_line != 0 && line != here_line { minutes + TRANSFER_MINUTES } else { minutes }
$ volec main.vl -o transit && ./transit
Airport -> Museum: 16 min
  line A  Airport    -> Museum      16 min
Airport -> Market: 20 min
  line A  Airport    -> Central     12 min
  line B  Central    -> Market       3 min
Beach -> Stadium: 36 min
  line C  Beach      -> Harbor      11 min
  line B  Harbor     -> Stadium     20 min
Airport -> Moon: no such station
ok: built transit
```

Airport to Museum is 16 minutes, Airport to Market 20 (12, a change, 3).

## Why not by hand

The usual first look is `ls`, `cat route.vl`, `grep -rn ride_cost`,
`grep -rn 'line: 0'`, then reading 280 lines to be sure nothing else
writes the line. Here every answer was exact and short:

- `query context` gave the function, what it calls and its callers in
  one answer of a known size, instead of three files opened to follow
  the calls;
- `query refs --kind init` found the struct literals that set the
  field, which no text search for `line` (31 matches: fields of four
  structs, two parameters, comments, a format string) separates from
  the rest;
- `query type` and `try` answered questions that a reader would
  otherwise settle by reasoning or by a throwaway program;
- the guide answered the syntax question from the compiler's own
  documentation, for this version of the language.

On a program of this size, reading it whole once is also reasonable
(`volec query show route.vl` prints a file); the queries pay off as
the program grows, and they cost the same at 300 lines as at 30,000.
