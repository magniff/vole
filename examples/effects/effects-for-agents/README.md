# Effects for agents: moving a module onto an arena

A session of the kind an agent runs: a task, the queries that answer it
without reading every function, one checked refactoring, and a
declaration that keeps the result true. The program renders a small
subset of Markdown to HTML (`markup.vl`; `main.vl` renders two
documents). The task:

> `markup` makes many small blocks for each document, each freed on its
> own when it is dropped. Move the module's allocations into an arena
> that `main` empties after each document, and make sure nothing in
> `markup` allocates from the general-purpose allocator again.

Every command below is run by `tests/walkthrough/run.sh` in a fresh
copy of this directory (a git repository, so that the edits are
journaled and `git diff` shows them), and its output is checked against
this file. `tests/examples/effects-effects-for-agents.test` runs the
program as it is before the session.

## 1. Before

```console
$ volec main.vl -o render && ./render > before.txt && head -4 before.txt
<ul>
<li><a href="#arenas">Arenas</a></li>
<li><a href="#why-arenas">Why arenas?</a></li>
</ul>
ok: built render
$ volec --check-alloc main.vl -o render-checked && ./render-checked > /dev/null
ok: built render-checked
```

Nothing is left allocated: every value is dropped at the end of its
scope. They are made at five places of `markup.vl`: the lines' `Vec`
(in `lines`), each heading's id (`slug`), the headings' `Vec`
(`headings`), and the HTML's `String<Gpa>`, grown in `inline` and in
`render`, which returns it; `main` drops it after printing it. One
arena can hold all of them, emptied at once.

## 2. What allocates, and from what

The question "what in this module allocates from `Gpa`?" has an exact
answer:

```console
$ volec query effects crate::markup --has 'alloc(Gpa)'
crate::markup::lines	alloc(Gpa) panic diverge
crate::markup::slug	alloc(Gpa) panic diverge
crate::markup::inline	alloc(Gpa) panic diverge
crate::markup::headings	alloc(Gpa) panic diverge
crate::markup::render	alloc(Gpa) panic diverge
```

All five functions. Four of them take `gpa: Gpa`; the fifth, `inline`,
takes no allocator, so a search for the parameter misses it (the type
of its `out` names one):

```console
$ grep -c 'fn .*gpa: Gpa' markup.vl
4
$ volec query refs Gpa --in crate::markup | grep inline
37:40	type	markup::inline	fn inline(text: &str, out: &mut String<Gpa>) {
$ volec query effects markup::inline --why 'alloc(Gpa)' | head -2
crate::markup::inline	alloc(Gpa) panic diverge
  'out.push_str(if code { "</code>" } else { "<..' at markup.vl:41:13 calls 'String::push_str'
```

`inline` appends to a `String<Gpa>` it is given, and a String grows
with the allocator it holds: the `out` that `render` made on `gpa`.
`--why` follows the chain from a function to the line that has the
effect; the first step is the one in the function asked about.

## 3. The refactoring, planned by the compiler

Four parameters change type, `Gpa` to a reference to the arena,
`&'a Arena<Gpa>`. `refactor --script` runs several refactorings and
checks the program once, at the end, all or nothing; `--dry-run` shows
the diff and the errors without writing. A first script with just the
four parameters (and the `use`):

```console
$ cat > steps.txt <<'EOF'
> edit patch markup.vl --old 'use std::alloc::Allocator;' --new 'use std::alloc::{Allocator, Arena};'
> refactor signature markup::lines --type gpa "&'a Arena<Gpa>"
> refactor signature markup::slug --type gpa '&Arena<Gpa>'
> refactor signature markup::headings --type gpa "&'a Arena<Gpa>"
> refactor signature markup::render --type gpa '&Arena<Gpa>'
> EOF
$ volec refactor --script steps.txt --dry-run | grep ': error'
main.vl:10:40: error[type error] expected '&Arena<Gpa>', got '&Gpa'  [edited: crate::main]
markup.vl:11:5: error[type error] the trait 'FromIteratorIn<&str, &Arena<Gpa>>' is not implemented for 'Vec<&str, Gpa>' | help: required by the bound 'B: FromIteratorIn<&str, &Arena<Gpa>>' of 'Split::collect_in'  [edited: crate::markup::lines]
markup.vl:17:40: error[type error] expected 'Gpa', got '&Arena<Gpa>'  [edited: crate::markup::slug]
markup.vl:56:58: error[type error] expected 'Gpa', got '&Arena<Gpa>'  [edited: crate::markup::headings]
markup.vl:67:41: error[type error] expected 'Gpa', got '&Arena<Gpa>'  [edited: crate::markup::render]
warning edit.breaks: 5 new errors (dry run); the first: main.vl:10:40: expected '&Arena<Gpa>', got '&Gpa'
```

The errors are the rest of the plan: the types that name `Gpa` (a
`Vec<&str, Gpa>` collected on the arena is a `Vec<&str, &Arena<Gpa>>`,
a `String<Gpa>` a `String<&Arena<Gpa>>`), `inline`'s `out`, and the
call in `main`, which must now pass an arena. What is returned borrows
the arena, so `slug` and `render` get a lifetime to say so (`lines` and
`headings` have one already, their text's). The script grows to cover
them, and renames the parameters to say what they are:

```console
$ cat > steps.txt <<'EOF'
> edit patch markup.vl --old 'use std::alloc::Allocator;' --new 'use std::alloc::{Allocator, Arena};'
> refactor signature markup::lines --type gpa "&'a Arena<Gpa>"
> refactor signature markup::slug --type gpa "&'a Arena<Gpa>"
> refactor signature markup::headings --type gpa "&'a Arena<Gpa>"
> refactor signature markup::render --type gpa "&'a Arena<Gpa>"
> refactor signature markup::inline --type out '&mut String<&Arena<Gpa>>'
> edit patch markup::lines --old "-> Vec<&'a str, Gpa>" --new "-> Vec<&'a str, &'a Arena<Gpa>>"
> edit patch markup::slug --old 'fn slug(' --new "fn slug<'a>(" --old '-> String<Gpa>' --new "-> String<&'a Arena<Gpa>>" --old 'String::<Gpa>::new_in' --new 'String::new_in'
> edit patch markup::headings --old "Vec<Heading<'a, Gpa>, Gpa>" --new "Vec<Heading<'a, &'a Arena<Gpa>>, &'a Arena<Gpa>>" --all
> edit patch markup::render --old 'fn render(' --new "fn render<'a>(" --old '-> String<Gpa>' --new "-> String<&'a Arena<Gpa>>" --old 'String::<Gpa>::new_in' --new 'String::new_in'
> refactor signature markup::lines --rename-param gpa arena
> refactor signature markup::slug --rename-param gpa arena
> refactor signature markup::headings --rename-param gpa arena
> refactor signature markup::render --rename-param gpa arena
> edit replace main <<END
> fn main(gpa: Gpa) -> i32 {
>     let docs = [
>         "# Arenas\nAn *arena* hands out memory\nby bumping a pointer.\n\n# Why arenas?\nFreeing is `free_all`: once.",
>         "# Effects\nEach function has a set: `alloc(Gpa)`, *io*, ...",
>     ];
>     // One arena for every document: what render makes for a document
>     // is freed at once, before the next one.
>     let mut arena = std::alloc::Arena::new_in(gpa);
>     for doc in docs {
>         // (the rendered String is a temporary: dropped at the end of
>         // the statement, before the reset)
>         print("{}", markup::render(doc, &arena));
>         arena.reset();
>     }
>     0
> }
> END
> EOF
$ volec refactor --script steps.txt
patched crate::markup	markup.vl	+1 -1 lines
changed parameter gpa to &'a Arena<Gpa> in crate::markup::lines, 1 argument in 1 call	markup.vl	+2 -2 lines
changed parameter gpa to &'a Arena<Gpa> in crate::markup::slug, 1 argument in 1 call	markup.vl	+2 -2 lines
changed parameter gpa to &'a Arena<Gpa> in crate::markup::headings, 1 argument in 1 call	markup.vl	+2 -2 lines
changed parameter gpa to &'a Arena<Gpa> in crate::markup::render, 1 argument in 1 call	2 files	+2 -2 lines
changed parameter out to &mut String<&Arena<Gpa>> in crate::markup::inline	markup.vl	+1 -1 lines
patched crate::markup::lines	markup.vl	+1 -1 lines
patched crate::markup::slug	markup.vl	+2 -2 lines
patched crate::markup::headings	markup.vl	+3 -2 lines
patched crate::markup::render	markup.vl	+2 -2 lines
renamed parameter gpa to arena of crate::markup::lines	markup.vl	+2 -2 lines
renamed parameter gpa to arena of crate::markup::slug	markup.vl	+2 -2 lines
renamed parameter gpa to arena of crate::markup::headings	markup.vl	+3 -3 lines
renamed parameter gpa to arena of crate::markup::render	markup.vl	+4 -4 lines
replaced crate::main	main.vl	+7 -2 lines
script steps.txt: 15 commands	2 files	+21 -15 lines
$ git diff --stat
 main.vl   |  9 +++++++--
 markup.vl | 27 ++++++++++++++-------------
 2 files changed, 21 insertions(+), 15 deletions(-)
```

`Arena::new_in(gpa)` makes an arena whose chunks come from `gpa`, and
a `&Arena<Gpa>` is an allocator. `reset` frees everything allocated
from it but keeps its memory for the next document; the arena gives
the memory back when it is dropped, at the end of `main`. `reset` takes
`&mut self`, so the compiler refuses it while anything still borrows
the arena: here nothing does, the HTML `render` returns is a temporary
of the `print` statement, dropped at its end. Keeping it past the
reset is an error, and nothing is written:

```console
$ volec edit patch main --old 'print("{}", markup::render(doc, &arena));' --new 'let html = markup::render(doc, &arena);' --old '        arena.reset();' --new '        arena.reset();
>         print("{html}");'
main.vl:16:9: error[borrowck.conflict] cannot borrow 'arena' as mutable because it is also borrowed as immutable (borrowed at main.vl:15:40) | help: use the shared borrow before the mutable one, or take it again after  [edited: crate::main]
error edit.breaks: 1 new error; nothing written; the error: main.vl:16:9: cannot borrow 'arena' as mutable because it is also borrowed as immutable (borrowed at main.vl:15:40)
try: volec edit patch main --old 'print("{}", markup::render(doc, &arena));' --new 'let html = markup::render(doc, &arena);' --old '        arena.reset();' --new '        arena.reset();
        print("{html}");' --no-check
[exit 1]
```

## 4. Checked

The same output, and nothing left allocated:

```console
$ volec main.vl -o render && ./render | diff before.txt - && echo same output
same output
ok: built render
$ volec --check-alloc main.vl -o render-checked && ./render-checked > /dev/null
ok: built render-checked
$ volec query effects crate::markup
crate::markup::lines	alloc(Arena<Gpa>) panic diverge
crate::markup::slug	alloc(Arena<Gpa>) panic diverge
crate::markup::inline	alloc(Arena<Gpa>) panic diverge
crate::markup::headings	alloc(Arena<Gpa>) panic diverge
crate::markup::render	alloc(Arena<Gpa>) panic diverge
```

Every function of `markup` now allocates from the arena only, and none
has `static`: since nothing obtains an allocator out of thin air (a
`Gpa` exists only as `main`'s parameter and the copies passed down), a
function without `alloc(Gpa)` and without `static` cannot reach a `Gpa`
at all.

## 5. Locked

The effects are inferred: today `render` allocates only from the arena,
but a later change could add a `gpa` parameter, a `Vec` on `Gpa` passed
in, a debugging print. A declaration makes the current set a promise,
checked on every build:

```console
$ volec edit patch markup::render --old 'pub fn render' --new '#[effects(alloc(Arena<Gpa>), panic, diverge)]
> pub fn render' --show
patched crate::markup::render	markup.vl	+1 -0 lines
// markup.vl:67
68	#[effects(alloc(Arena<Gpa>), panic, diverge)]
```

`render`'s set covers everything it calls, so the one declaration
guards the whole module (`diverge` is the loops over the text). A debugging print three calls down, in `slug`:

```console
$ volec edit patch markup::slug --old '    let mut dash = false;' --new '    eprintln("slug of {title}");
>     let mut dash = false;'
markup.vl:69:5: error[effect] 'markup::render' is #[effects(alloc(Arena<Gpa>), panic, diverge)], but it does io: 'headings(ls.as_slice(), &arena)' at markup.vl:72:14 calls 'markup::headings' | help: return the data and let the caller print it, or add 'io' to #[effects(alloc(Arena<Gpa>), panic, diverge)] | try: volec query effects markup::render --why io  [in crate::markup::render]
error edit.breaks: 1 new error (1 in crate::markup::render, which the edit does not change); nothing written; the error: markup.vl:69:5: 'markup::render' is #[effects(alloc(Arena<Gpa>), panic, diverge)], but it does io: 'headings(ls.as_slice(), &arena)' at markup.vl:72:14 calls 'markup::headings'
note edit.together: change crate::markup::render in the same edit: one `edit apply FILE` with a block per item, or `edit patch --pairs FILE` with `@@ NAME` blocks
try: volec query show crate::markup::render
try: volec edit patch markup::slug --old '    let mut dash = false;' --new '    eprintln("slug of {title}");
    let mut dash = false;' --no-check
[exit 1]
```

Refused, and nothing written: the edit tools check the program with the
change before writing it. A build, a `volec check` or the check hook
an agent runs after each edit reports the same error.

## What the agent used

| step | command | instead of |
|---|---|---|
| what allocates, from what | `query effects MODULE --has 'alloc(Gpa)'` | reading every function and its callees |
| why this one | `query effects NAME --why EFFECT` | following calls by hand into std |
| the plan | `refactor --script --dry-run`: the errors are the remaining steps | editing and building until it compiles |
| the change | `refactor --script`, checked once, all or nothing | a series of edits, some leaving the program broken |
| proof | `--check-alloc`, `diff` of the output, `query effects` again | trusting the change |
| the lock | `#[effects(alloc(Arena<Gpa>), panic, diverge)]` | a comment |

## Read more

- `volec guide effects` and `volec guide allocators`.
- `volec guide tools`: query, edit, refactor; docs/refactor.md.
- [../../tools/](../../tools/): more sessions with the tools.
