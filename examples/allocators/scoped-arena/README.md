# Scratch memory per request: `arena_scope`

A small key-value store that answers one request per line of stdin
(`SET key n`, `ADD key n`, `GET key`, `SUM key...`). Every request needs
memory for a moment: its words, its keys in lowercase, the text of its
response. All of it comes from an arena made for that request and freed,
at once, when the request is answered:

```vole
let used = arena_scope(&gpa, |scratch| {
    let mut out = String::new_in(scratch);
    answer(&mut store, line, scratch, &mut out);
    println("{line:<24} -> {out}");
    scratch.used()
});
```

What must outlive a request is allocated elsewhere, on purpose: the map
on `Gpa`, and the text of its keys in an `Arena` kept for the whole
run. The compiler holds the line between the two: nothing that borrows
the scope's arena can leave the scope.

Every command below is run by `tests/walkthrough/run.sh` in a copy of
this directory, and its output is checked against this file;
`tests/examples/allocators-scoped-arena.test` runs the program.

## Run it

```console
$ volec main.vl -o store && ./store < requests.txt
SET apples 3             -> apples = 3
SET Pears 5              -> pears = 5
ADD apples 4             -> apples = 7
GET APPLES               -> apples = 7
GET plums                -> plums is not set
SUM apples pears plums   -> sum = 12 (not set: plums)
ADD pears lots           -> not a number: lots
FLY away                 -> unknown request: FLY away
8 requests, 2 keys; scratch per request at most 185 bytes
the keys' arena holds 11 bytes
ok: built store
```

No request frees anything by hand, and none leaks: `--check-alloc`
(which lists every block not freed at exit, and traps a use of an
arena's block after its scope) has nothing to say.

```console
$ volec --check-alloc main.vl -o store-checked && ./store-checked < requests.txt | tail -1
the keys' arena holds 11 bytes
ok: built store-checked
```

## How it works

`arena_scope(&gpa, f)` makes an arena whose memory comes from `gpa`,
calls `f` with a reference to it (a `&ArenaScope`), and frees the arena
when `f` returns; it returns what `f` returns. Allocating from it is
bumping a pointer, and freeing a block inside it is nothing (but for
the last one, which the pointer gives back): the scope's end frees
everything. One chunk is enough for every request here: the busiest
one used 185 bytes.

`answer` does not know or care what kind of allocator it is given:

```vole
fn answer<A: Allocator + Copy>(
    store: &mut Store<'_, Gpa, Gpa>, line: &str, scratch: A, out: &mut String<A>,
)
```

Inside, every temporary is made on `scratch`:
`line.split_whitespace().collect_in(scratch)`, `lower_in(words[1],
scratch)` (a lowercased copy), a `String<A>` listing the missing keys of
a `SUM`. Each is
dropped at the end of its scope, which on an arena frees nothing: the
scope's end frees it all. The response is written into `out`, a `String`
on the same arena.

A known key's value changes in place, through `get_mut`. A new key must
outlive the request, so it is copied out of the scratch into the store's
own arena before it goes into the map:

```vole
match store.values.get_mut(key.as_str()) {
    // A known key: its value changes in place.
    Some(v) => *v = new,
    // A new key: its text goes where the map's keys live. The
    // copy borrows the arena, not the request's scratch.
    None => {
        store.values.insert(store.names.alloc_str(key.as_str()), new);
    }
}
```

`alloc_str` copies the text into `names`, an `Arena` made once in `main`
(`Arena::new_in(gpa)`) and dropped at its end, after the store. The
`&str` it returns borrows the arena, so it lives as long as the arena,
and the store's type says so: `Store<'n, M, N>` holds `&'n Arena<N>` and
a `HashMap<&'n str, i64, M>`. The borrow checker keeps the map from
outliving the arena its keys are in; there is no `unsafe` in the
program.

## What the effects say

```console
$ volec query effects crate
lower_in<&ArenaScope<&Gpa>>	alloc(ArenaScope<&Gpa>) panic diverge
answer<&ArenaScope<&Gpa>>	alloc(Gpa, Arena<Gpa>, ArenaScope<&Gpa>) panic diverge
crate::main	alloc(Gpa, Arena<Gpa>, ArenaScope<&Gpa>, &Gpa) io panic diverge
```

`answer` allocates from all three: `Gpa` (the map grows), the keys'
`Arena`, and the request's `ArenaScope` (the scratch). `lower_in`, given
the scratch, allocates from it alone.

## What cannot leave the scope

A container on the scope's arena is gone when the scope ends, so it
cannot be the scope's value:

```console
$ cat > escape.vl <<'EOF'
> // EDITION: rust
> use std::alloc::arena_scope;
>
> fn main(gpa: Gpa) -> i32 {
>     let words = arena_scope(&gpa, |a| {
>         let mut v = Vec::new_in(a);
>         for w in "scratch words to keep".split_whitespace() {
>             v.push(w);
>         }
>         v
>     });
>     println("{}", words.len());
>     0
> }
> EOF
$ volec check escape.vl
escape.vl:6:21: error[borrowck.outlives] lifetime may not live long enough: the lifetime of the closure's parameter 'a' is only the call's, but it flows where a lifetime of the closure's signature, from outside it is required, which lasts longer | help: keep a copy of the value instead of the reference (`*p`, `.clone()`); a closure's result borrows from its parameter only when the bound it is passed for says so (`Fn(&T) -> &T`)
[exit 1]
```

Return what is computed from it instead (`.len()` inside the scope), or
copy it out to a longer-lived allocator.

No variable outside a scope can hold its arena's containers: their type
borrows the `ArenaScope`, and the borrow ends with the scope.

## Nor can a view of it

A slice is a view: it holds no allocator, so its type says nothing about
where its bytes live. A view of a scope's container returned from the
scope would point at memory the scope's end freed. The view cannot outlive the `Vec`
it views, which is dropped when the scope's closure returns:

```console
$ cat > view.vl <<'EOF'
> // EDITION: rust
> use std::alloc::arena_scope;
>
> fn main(gpa: Gpa) -> i32 {
>     let words = arena_scope(&gpa, |a| {
>         let mut v = Vec::new_in(a);
>         for w in "scratch words to keep".split_whitespace() {
>             v.push(w);
>         }
>         v.as_slice()
>     });
>     println("{}", words[0]);
>     0
> }
> EOF
$ volec check view.vl
view.vl:5:39: error[borrowck.return_local] a reference to 'v', a local of this function, escapes it (borrowed at view.vl:10:9) | help: return an owned value, or borrow from a parameter
view.vl:6:21: error[borrowck.outlives] lifetime may not live long enough: the lifetime of the closure's parameter 'a' is only the call's, but it flows where a lifetime of the closure's signature, from outside it is required, which lasts longer | help: keep a copy of the value instead of the reference (`*p`, `.clone()`); a closure's result borrows from its parameter only when the bound it is passed for says so (`Fn(&T) -> &T`)
[exit 1]
```

[check-alloc](../check-alloc/) has the other bugs of this kind, compile
errors too, and what `--check-alloc` still catches at run time: leaks,
and bugs in `unsafe` code.

## Read more

- `volec guide allocators`, section "Arenas".
- [arena-parser](../arena-parser/): a whole tree in an arena, timed
  against `Gpa`.
