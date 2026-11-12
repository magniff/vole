# Trait purity: `PartialEq` and `Ord` are `#[pure]`

The most frequent words of a text, counted without regard to case. The
words are keys of a `HashMap`, as a type of the program, `Word`, with a
hand-written `Hash` and `PartialEq` that look at the lowercase bytes;
the counts are sorted by a hand-written `Ord`.

std declares the comparing methods `#[pure]`:

```vole
pub trait PartialEq<Rhs = Self> { #[pure] fn eq(&self, other: &Rhs) -> bool; }
pub trait Ord: Eq + PartialOrd { #[pure] fn cmp(&self, other: &Self) -> Ordering; }
```

A declaration on a trait's method binds every impl of it, the program's
and derived ones alike: an `eq` or a `cmp` may not allocate, do I/O or
touch a static. It may panic, loop, and read what it is given.

Why: the containers and algorithms that call them decide how often. A
`HashMap` hashes a key on every insert and every lookup, and every key
again each time it grows; a sort compares as often as its algorithm
needs, in its own order. A `cmp` that counted its calls in a static
would count the sort's internals, and change when they do; an `eq` that
printed would print a different trace for every version of the map. And
the optimizer may compute a pure call once and reuse it.

Every command below is run by `tests/walkthrough/run.sh` in a copy of
this directory, and its output is checked against this file;
`tests/examples/effects-trait-purity.test` runs the program.

## Run it

```console
$ volec main.vl -o words && ./words
26 words, 13 different
  5 The
  4 cat
  3 a
  3 mat
  2 on
ok: built words
```

## The impls' effects

```console
$ volec query effects crate
crate::lower	none
Word::hash<FoldHasher>	none
<crate::Word as PartialEq>::eq	panic
<crate::Count as Ord>::cmp	panic
<crate::Count as PartialOrd>::partial_cmp	panic
crate::trim_word	panic
crate::is_letter	none
crate::main	alloc(Gpa) io static panic diverge
```

`Word::hash` is `none`: it only feeds the hasher it is given. `Word::eq`
and `Count::cmp` may panic (an index, a slice), which `#[pure]` allows.

## A cmp that counts its calls

Counting how often `cmp` runs, in a static: one edit adds the static
and changes `cmp` (`edit apply` takes several items' new text, here on
stdin):

```console
$ volec edit apply <<'EOF'
> @@ new before Word
> // How many times cmp was called.
> static mut COMPARES: i64 = 0;
> @@ Count::cmp
>     fn cmp(&self, other: &Self) -> Ordering {
>         // UNSAFE: a static mut.
>         // SAFETY: the program has one thread.
>         unsafe { COMPARES += 1 };
>         if self.n != other.n {
>             return other.n.cmp(&self.n);
>         }
>         self.word.text.cmp(other.word.text)
>     }
> EOF
main.vl:57:5: error[effect] 'Count::cmp' implements 'Ord::cmp', which is #[pure], but it touches a static mut or a C static (static): 'COMPARES' at main.vl:60:18 is a static's (static) | help: pass the state in as a parameter, or remove #[pure] (the trait's) | try: volec query effects Count::cmp --why static  [edited: <crate::Count as Ord>::cmp]
error edit.breaks: 1 new error; nothing written; the error: main.vl:57:5: 'Count::cmp' implements 'Ord::cmp', which is #[pure], but it touches a static mut or a C static (static): 'COMPARES' at main.vl:60:18 is a static's (static)
try: volec edit apply --no-check
[exit 1]
```

The error is at the impl's `cmp`, and says whose declaration it breaks:
`Ord::cmp`'s, std's. (The help's two ways out are for a function of
your own; for std's traits, keep the count outside the impl: around the
calls of `sort` that you make.)

## An eq that prints

A debugging print in `eq`:

```console
$ volec edit patch Word::eq --old '        if a.len() != b.len() {' --new '        println("comparing {} and {}", self.text, other.text);
>         if a.len() != b.len() {'
main.vl:31:5: error[effect] 'Word::eq' implements 'PartialEq::eq', which is #[pure], but it does io: 'println("comparing {} and {}", self.text, ot..' at main.vl:34:9 calls 'std::fmt::println' | help: return the data and let the caller print it, or remove #[pure] (the trait's) | try: volec query effects Word::eq --why io  [edited: <crate::Word as PartialEq>::eq]
main.vl:51:10: error[effect] 'Count::eq' implements 'PartialEq::eq', which is #[pure], but it does io: 'word: Word<'a>' at main.vl:52:20 calls 'Word::eq' | help: return the data and let the caller print it, or remove #[pure] (the trait's) | try: volec query effects Count::eq --why io
error edit.breaks: 2 new errors; nothing written; the first in the edited text: main.vl:31:5: 'Word::eq' implements 'PartialEq::eq', which is #[pure], but it does io: 'println("comparing {} and {}", self.text, ot..' at main.vl:34:9 calls 'std::fmt::println'
try: volec edit patch Word::eq --old '        if a.len() != b.len() {' --new '        println("comparing {} and {}", self.text, other.text);
        if a.len() != b.len() {' --no-check
[exit 1]
```

Two errors: `Count`'s derived `eq` compares its `word` field with
`Word::eq`, so it breaks the same promise.

## Derived impls

`#[derive(PartialEq, Eq, PartialOrd, Ord)]` writes impls that compare
the fields, so they are pure when the fields' impls are: every number,
`&str`, `&[u8]`, and every type of std is. They are checked the same
way.

## Pure is not deterministic

`#[pure]` is about effects: no allocation, no I/O, no statics. It does
not make a function's result depend only on its arguments: an impl can
still read memory through a raw pointer it holds (in `unsafe` code), and
change what it answers. std's sort is tested with such comparators
(tests/run/std_sort_adversarial.vl: random, always-less, alternating):
they keep their state behind a pointer in each key, which is `unsafe`,
not `static`. An `Ord` that is not an order leaves a slice in some
order, never out of bounds.

## Read more

- `volec guide effects`, section "Declaring" (trait declarations).
- `volec guide traits`: traits, impls, derive.
- [pure-and-no-alloc](../pure-and-no-alloc/): `#[pure]` on functions.
