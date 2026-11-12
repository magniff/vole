<p align="center"><picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/vole-logo-round-dark.png">
  <img src="docs/assets/vole-logo-round.png" alt="The vole logo" width="260">
</picture></p>

# Vole

Vole is a compiled systems language built for AI agents to write and
maintain. No model has seen it in training, so the compiler carries the
knowledge: it prints the language on demand, answers questions about a
program by name, makes edits that are checked before anything is
written, and reports each problem as one line with a `try:` command to
run. The compiler is written in vole and generates native AArch64 and
x86-64 code with its own optimizer and assembler.

**Who it is for:** agents writing systems code, and the people directing
them: command-line tools, parsers and compilers, servers, GPU compute, a
terminal emulator. It fits where a program should say in its text what
it allocates and changes, and where the toolchain is driven from a
shell. It does not fit yet where you need packages (there is no package
manager), Windows, a stable language or a track record.

## An example

```rust
// Quicksort, in place: `&mut` lends the slice for writing, nothing is copied.
#[no_alloc] // checked: sorting allocates nothing
fn quicksort<T: Ord>(xs: &mut [T]) {
    if xs.len() <= 1 { return; }
    let p = partition(xs);
    quicksort(&mut xs[..p]); // one half, then the other
    quicksort(&mut xs[p + 1..]);
}

fn partition<T: Ord>(xs: &mut [T]) -> usize
    ensures result < xs.len()
{
    let last = xs.len() - 1;
    xs.swap(last / 2, last); // the middle element is the pivot
    let mut store = 0;
    for i in 0..last {
        if xs[i] < xs[last] {
            xs.swap(i, store);
            store += 1;
        }
    }
    xs.swap(store, last);
    store
}

fn main(gpa: Gpa) {
    let mut v: Vec<i64, Gpa> = Vec::new_in(gpa); // the allocator is explicit
    for x in [5, 3, 9, 1, 4, 8, 2, 7, 6] { v.push(x); }
    quicksort(&mut v); // &mut marks what the callee may change
    println("{v:?}"); // [1, 2, 3, 4, 5, 6, 7, 8, 9]
}
```

`volec query effects quicksort main.vl` answers `panic diverge`: an
index may fail its check, and the recursion may not end; no `alloc`, as
`#[no_alloc]` checks.

## Where it differs from Rust

Its surface is Rust's (syntax, ownership, `&T` and `&mut T` under a
borrow checker, lifetimes, traits, generics, std's names), so a model's
habits carry over. It differs in these places:

| | Rust | vole |
|---|---|---|
| allocation | a global allocator: `Vec::new()`, `Box::new(x)` | a capability: `fn main(gpa: Gpa)`, `Vec<T, Gpa>`, `Vec::new_in(gpa)`; what returns owned memory ends in `_in`; arenas |
| effects | none | inferred: `alloc(A)`, `io`, `static`, `panic`, `diverge`, `unsafe`; `query effects --why`; `#[pure]`, `#[no_alloc]`, `#[effects(..)]` are checked bounds |
| contracts | `assert!` in the body | `requires`, `ensures` on a signature: a caller that breaks one stops at its own line |
| macros | `println!`, `vec!`, `macro_rules!` | none: `println("{x}")`, `format_in`, `assert` are functions |
| arguments | positional | also named, `f(10, by: 3)`; no default arguments |
| numbers | every conversion written | lossless integer widening is implicit (`i32` to `i64`), except to an index, a `usize` |
| dispatch | monomorphized or `dyn` | monomorphized only: no `dyn`, no const generics, no `async` |
| C | `extern "C"`, `#[repr(C)]`, bindgen | the same, and `import "stdio.h" as c;` reads a header into `c::` |
| libraries | crates | std only: a program is its root file and its `mod` files |

Every difference, checked against the compiler: `volec guide rust`; the
grammar is [docs/grammar.md](docs/grammar.md).

## Tools

| | |
|---|---|
| `volec guide` | the language in about 2.5k tokens; `--find WORDS`, `guide TOPIC` |
| `volec check`, `explain CODE` | every error on one line, with a stable code and `try:` lines |
| `volec query context NAME` | an item's source, its callees and callers; also `refs`, `effects` |
| `volec edit patch`, `refactor rename` | checked edits (one that adds an error writes nothing), `undo` |
| `volec fix --suggested` | the errors' exact fixes; `fix` adds imports, `pub`, `unsafe` |
| `volec test`, `volec fuzz` | `#[test]`, `#[property]`, `#[fuzz]`, at -O0 and -O2 |
| `volec lsp` | a language server, with a VS Code extension in [editors/vscode](editors/vscode) |
| `std::cli` | command-line parsing for tools written in vole (clap's builder) |

More in [docs/query.md](docs/query.md), [docs/refactor.md](docs/refactor.md)
and [docs/lsp.md](docs/lsp.md).

## Maturity

Vole is at 0.28, before 1.0: no users yet, no stability promise, and
releases break programs (with a `volec fix` migration where one can be
written). The language is still being designed: expect it to change.

- **Works:** the self-hosting compiler (280k lines of vole, built by a
  chain of every release from a frozen Rust seed, each reaching a
  byte-identical fixpoint); std with collections, text, I/O, threads,
  atomics, `std::arch`, `std::gpu` (Metal), `std::window` (Cocoa) and
  `std::cli`; [examples/voltty](examples/voltty), a terminal emulator
  on them.
- **Platforms:** aarch64 macOS first; aarch64 Linux tested in every
  release gate. x86-64 code is generated, but not run since 0.15.
- **Speed:** 0.24's code took 0.89 of `cc -O2`'s time (geometric mean,
  one Apple silicon machine) on our own small suite with C twins; it
  says little about large programs.
- **Known gaps:** no Linux backend for std::window; std::gpu is Metal
  only.

## Build and start

On aarch64 macOS: git, Rust through rustup, the Xcode command line tools.

```sh
git clone https://github.com/magniff/vole && cd vole && git fetch --tags
bootstrap/bootstrap.sh       # replays the release chain; leaves target/volec
target/volec guide           # start here
```

## Links

[releases](docs/releases.md) (and other hosts), [roadmap](docs/roadmap.md),
[examples](examples/README.md), [AGENTS.md](AGENTS.md) (working on the
compiler), [release notes](https://github.com/magniff/vole/releases).
MIT licensed ([LICENSE](LICENSE)).
