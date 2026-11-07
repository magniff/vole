# Releases and the bootstrap chain

The vole compiler is written in vole. To build it on a machine that
has no vole compiler yet, the chain of releases is replayed from its
root, the seed:

```
seed (Rust)  ──builds──▶  0.1.0  ──builds──▶  next release  ──▶ ... ──▶  HEAD
```

- **The seed** is the original Rust implementation (`seed/`, Cranelift
  backend), tagged `seed`. It is frozen: its toolchain is pinned
  (`seed/rust-toolchain.toml`, `seed/Cargo.lock`), and it only ever has to
  build release 0.1.0. New language features never go into it.
- **Every release** is a git tag (`v0.1.0`, `v0.2.0`, ...) whose tree is
  self-contained: the compiler for that release in vole (`compiler/`),
  its examples (`examples/`), its test suite (`tests/`), the documentation
  of its language (`docs/`), and the chain tooling (`bootstrap/`). The tree
  of `v0.1.0` also holds the seed, so that one tag has everything.
- **Each release is built by the previous one**, and checked: it must reach
  the fixpoint (compiled by itself, it emits exactly what its first build
  emits) and pass its own test suite. (0.25.3) A tag cannot change, so a
  case of its own that cannot pass where the chain runs it is listed in its
  release's `known_failures` (releases.toml), with why; the suite then
  passes only when it fails exactly so, and the chain's summary says it
  (0.25.2.2: one hooks case, which takes the cache's `target/` path for a
  scratch copy).

`bootstrap/releases.toml` lists the seed's tag and the releases in order,
with the tag, where the compiler's source is, what builds it, how its
binary is invoked, where its test runner is and which hosts it supports.
`bootstrap/bootstrap.sh` replays the chain.

## Versions

| release | tag | built by | hosts | introduced |
|---|---|---|---|---|
| seed | `seed` | Rust 1.98.0 | aarch64-macos, x86_64-macos, x86_64-linux | the language, and its Rust implementation with a Cranelift backend |
| 0.1.0 | `v0.1.0` | seed | aarch64-macos, x86_64-linux, x86_64-macos | the compiler in vole: the seed's whole language, compiled to AArch64 (Apple's arm64 ABI) and x86-64 (System V, ELF and Mach-O) assembly; a test suite run without cargo |
| 0.2.0 | `v0.2.0` | 0.1.0 | aarch64-macos, x86_64-linux, x86_64-macos | the optimizer: SSA IR, SCCP, instruction combining, GVN, LICM, inlining, linear-scan register allocation; `-O0`/`-O1`/`-O2` (default `-O2`); random differential testing; `bench/` |
| 0.3.0 | `v0.3.0` | 0.2.0 | aarch64-macos, x86_64-linux, x86_64-macos | aggregates and memory: enums with fields and `match`, methods, slices, C interop (`extern "C"`, `#[repr(C)]`, unions, C's convention for aggregates); SROA, memory forwarding across blocks, dead stores, switches and jump tables; ABI conformance fuzzing |
| 0.4.0 | `v0.4.0` | 0.3.0 | aarch64-macos, x86_64-linux, x86_64-macos | loops and C headers: the compiler written in the 0.3 language; `import "x.h"` (a C preprocessor and declaration reader) and `--emit-header`; `use`, checked `as` to enums, enum ordering, `size_of`/`align_of`, `for x in s`; loop canonicalization, induction variables, rotation, unrolling, unswitching, strength reduction, value ranges and bounds-check elimination, aggressive DCE, tail recursion elimination |
| 0.5.0 | `v0.5.0` | 0.4.0 | aarch64-macos, x86_64-linux, x86_64-macos | generics, modules and the back end: generics by monomorphization, modules (`mod`, `pub`, `use`), several errors per compilation, a small `std`; register allocation by linear scan with interval splitting, a calling convention of vole's own, frames aligned above 16, instruction selection by rules, block layout, selects, leaf frames, sibling calls |
| 0.6.0 | `v0.6.0` | 0.5.0 | aarch64-macos, x86_64-linux, x86_64-macos | interprocedural: the compiler written as a module tree; string literals as slices, `if let`, `defer`, structural `==`, a prelude, inline modules, generic type aliases; a cost-model inliner, attribute inference, interprocedural constants, devirtualization, scalar promotion, heap to stack, global DCE; shrink-wrapping; `--time-passes`, `--stats` |
| 0.7.0 | `v0.7.0` | 0.6.0 | aarch64-macos, x86_64-linux, x86_64-macos | object files: an assembler in the compiler writes Mach-O and ELF objects, `cc` only links (the compiler builds itself 4.4× faster at `-O2`, 15.7× at `-O0`); fixed-array indexing is checked; the undefined behaviour left is documented |
| 0.8.0 | `v0.8.0` | 0.7.0 | aarch64-macos, x86_64-linux, x86_64-macos | no wildcard imports: `use x::*` and `import "h.h";` without `as` are removed, every name a file uses is declared, imported by name or written with its path; `volec --fix-imports` rewrites older code |
| 0.9.0 | `v0.9.0` | 0.8.0 | aarch64-macos, x86_64-linux, x86_64-macos | `unsafe`, traits and an e-graph: `unsafe` blocks and functions (safe code has no undefined behaviour; a warning in 0.9, an error from 0.10), `--fix-unsafe`; traits, bounds, operator traits, std `HashMap` and `sort`; array constants, line continuations; GVN on an acyclic e-graph with rewrite rules checked by `--check-rules` |
| 0.10.0 | `v0.10.0` | 0.9.0 | aarch64-macos, x86_64-linux, x86_64-macos | vectors and profiles: an unsafe operation outside `unsafe` is an error; vector types (`v4f32`, `v2f64`, ...) on NEON and SSE2; a loop vectorizer; profile-guided optimization; `--check-unsafe`; every error of a compilation reported |
| 0.11.0 | `v0.11.0` | 0.10.0 | aarch64-macos, x86_64-linux, x86_64-macos, aarch64-linux (cross-built) | feature-complete, and tools for agents: DWARF line tables (`-g`); aarch64-linux as a target and a host; a broader `bench/`, a cost model for the loop vectorizer, unrolling with run-time trip counts, an SLP vectorizer, division by constants, value ranges through phis; `volec query`, `check`, `fix`, `lint`, `same-output`, `edit` by name and semantic refactorings (`refactor rename`, `move`, `signature`, `field`, `variant`, `split`, `rewrite`, scripts, `undo`) |
| 0.12.0 | `v0.12.0` | 0.11.0 | aarch64-macos, x86_64-linux, x86_64-macos, aarch64-linux (cross-built) | the compiler's source reorganized through its own tools: folders by phase, no file over 1,000 lines, no re-exports, tidy imports, output identical to 0.11's; `edit patch`, `edit insert --in`, `query text`, a module's `use` lines and header as targets, `fix --only reexports` and `tidy-imports`, `split --reexport`; the release gate in one command (`bootstrap/gate.sh`) |
| 0.13.0 | `v0.13.0` | 0.12.0 | aarch64-macos, x86_64-linux, x86_64-macos, aarch64-linux (cross-built) | the tools, improved from 0.12's record: `edit patch` inside a line, `--pairs`, `edit wrap`, `edit new-file`, `signature --default`, `fix --in` over a subtree; section banners, `query grep`, `query type`, kinds of references; an on-disk cache (a query or `check` of an unchanged program in about 6 to 8 ms); `split` part names, layout kept by `move` and `split`, `refactor extract-function` and `inline`; `volec fmt` (the tree formatted), `explain` and `guide` |
| 0.14.0 | `v0.14.0` | 0.13.0 | aarch64-macos, x86_64-linux, x86_64-macos, aarch64-linux (cross-built) | closures and iterators: closures (captures by value or by reference, `move`, `Fn`/`FnMut` bounds, a non-capturing closure is a `fn`, an escape check); associated types; an `Iterator` trait, `for` over anything iterable, ranges as values, std's sources, adapters and consumers, chains compiled to the hand-written loop; std reads stdin (`read_line`, `read_stdin`, `Scanner`), text helpers, values changed in place, an introsort; did-you-mean across the program and std, helps for Rust habits; the tools on a user's program; the agent eval (`tests/agent-eval/`) and its 0.13 baseline |
| 0.15.0 | `v0.15.0` | 0.14.0 | aarch64-macos, x86_64-linux, x86_64-macos, aarch64-linux (cross-built) | errors, conversions, less boilerplate: `?` on `Option` and `Result`, generic traits, `From`/`Into`, `main` returning `Result`, std's I/O on `Result` with typed errors (`fix --only std015` moves 0.14 code); lossless integer widening and joins, `i64::MAX`; f-strings over `Display` and `Debug`, generic `print`/`format`; `#[derive(Eq, Ord, Hash, Debug, Clone)]`; named and default arguments, field shorthand; `==` on `Vec`, `Buf`, `HashMap` by contents; std loaded by sections; if-conversion, vector masks and min/max reductions, split accumulators, `ldp`/`stp` (iterloop from 2.1 to about 1.05 times C); the tools for agents (`query context`, budgets, std from any program, `try`, `batch`, `edit apply`, merge conflicts, `--json`, the check hook); back end, gen0 and base on closures and iterators; algorithm and tool examples; six harder eval tasks |
| 0.16.0 | `v0.16.0` | 0.15.0 | aarch64-macos, x86_64-linux, x86_64-macos, aarch64-linux (cross-built) | effects and explicit allocation: inferred effect sets (`alloc(A)`, `io`, `global`, `panic`, `diverge`, `unsafe`) shown by `query effects` (`--why`, `--has`), `#[pure]`/`#[no_alloc]`/`#[no_io]`/`#[no_panic]`/`#[effects(..)]` and `effects(..)` bounds checked transitively (std's `Eq`/`Ord`/`Hash` pure), `--verify-effects`; allocation explicit (`fn main(gpa: Gpa)`, `Vec::new_in(gpa)`, `fix --only alloc016` moves 0.15 code), the `Allocator` trait, `Gpa`, arenas, `arena_scope`, `FixedBuf`, a `Fmt` that never allocates; `#[sealed]` std types, `#[scoped]` arenas; `--check-alloc` (use after free, double free, leaks, arena resets and scopes); pure calls numbered and hoisted, arena allocation without a call; link inputs on the command line (`x.c`, `-l`, `-L`); examples in folders with READMEs, C interop and language tours; the compiler's source on 0.15's features; compiler tasks in the agent eval |
| 0.17.0 | `v0.17.0` | 0.16.0 | aarch64-macos, x86_64-linux, x86_64-macos, aarch64-linux (cross-built) | memory safety by mutable value semantics: owned values (`Vec`, `Buf`, `HashMap`, `Drop` types, what holds one) move and are dropped at the end of their scope (`Drop`, generated drop glue, drop flags, `.clone()` explicit); references `&T`/`&mut T` and slices split into read-only `[T]` and exclusive `&mut [T]`, second-class: views checked so none outlives or is invalidated under what it views, with inferred view summaries (`views(..)`, `stores(..)`, `#[views]` pins), two-phase receivers and reborrows, no lifetime annotations; `--values=error` the default (`warn`, `report`, `off` for 0.17 only); noalias and read-only facts from reference parameters, NRVO, moves elided in loops; std on values (`Drop` for the containers, `&Self`/`&mut Self` receivers, sorts on `&mut [T]`, `Eq`/`Ord`/`Hash` on `&Self`); `fix --values` and the corpus migrated; `query own`, `query views`, `explain own.*`, tests/own-try; familiar forms (`&mut x`, `v[i]` on Vec and Buf, indexing through a pointer by its type, `p.0`, `len()`, `panic`/`unreachable`, a larger prelude, module paths in code resolved as `use` lines, struct-like enum variants); `fix --suggested`, the `&f` diagnostic; `--trace`, `probe`, `reduce`, `volec test`, `guide debug`; compile speed (per-function IR and pipeline, -O1 leaf inlining, f-strings written in place: the compiler compiles itself 14% faster at -O0, 37% at -O2, in a third less memory) |
| 0.18.0 | `v0.18.0` | 0.17.0 | aarch64-macos, x86_64-linux, x86_64-macos, aarch64-linux (cross-built) | contracts and verification in the language: `requires`/`ensures` (`result`, `old(..)`, `else` messages, `debug` clauses), checked at run time, a requires at the call so the caller is blamed, pure conditions (`contract.effect`); std's own clauses (`unwrap`, `Vec::get`, ...); `assert`, `assert_eq`, `assert_ne`, `debug_assert`; every run-time check one line `FILE:LINE:COL: message` with the condition and its values; `query checks` (the checks the optimizer proved away and those left), `--no-positions`; `#[test]`, `#[cfg(test)]` modules, `assert_snapshot`, `#[property]` with inputs generated from the types and shrunk, contracts tested as properties, `#[fuzz]` with block coverage (`--coverage`, `volec fuzz`), leaks failing a test; `volec test` builds at -O0 and -O2 and compares them; `reduce` over programs (`--differs`, `--fails`, `--test`); `type X = distinct T`, `std::NonNull<T>` with the null niche (`Option<NonNull<T>>` is a pointer, FFI-safe, `_Nonnull` imported) and a checked `as NonNull<T>`; std's `Display`, `Debug`, `Iterator`, `Clone` on references, `fix --values` over traits; the agent eval's `+debrief` |
| 0.18.1 | `v0.18.1` | 0.18.0 | aarch64-macos, x86_64-linux, x86_64-macos, aarch64-linux (cross-built) | two use-after-free holes in safe code closed (a changed copy of a borrowed owned value; a reference into a Vec across a push); functions compiled in parallel (`-j N`, the same bytes at any N; the -O2 self-compile 2.13 s to 0.72 s at -j8) and incremental rebuilds from a code cache (a one-function edit 0.53 s, byte-identical to clean); V4: every `*T` raw, borrowing only `&`/`&mut`, the compiler and std on references; contracts in generated code (range fixes, `x % n` ranges, entry facts: the contracts bench 25% fewer instructions than without clauses); BinaryHeap/MinHeap, binding modes on references, `&f()` temporaries, let-else and the 0.18 eval's polish; a valgrind row and threads/incremental steps in the gate, a lock on the bootstrap cache |
| 0.19.0 | `v0.19.0` | 0.18.1 | aarch64-macos, x86_64-linux, x86_64-macos, aarch64-linux (cross-built) | CPU intrinsics and target features: `std::arch` with over 1,775 AArch64 intrinsics (NEON, crc, sha2, sha512, sha3, aes, pmull, dotprod, float), each checked lane by lane against a scalar reference, and 484 x86-64 intrinsics (SSE to AVX2, FMA, BMI, AES-NI, SHA, PCLMULQDQ) encoded as cc does but not run; unsigned, 64-bit and 256-bit vector types; target features inferred like effects, `has`/`detect` guards, foreign architectures constant false, `-C target-cpu`/`target-feature`; run-time detection and `#[multiversion]`; intrinsics pure to the optimizer, never hoisted above their guard, vectors in vector registers; `query arch`, `guide arch`, examples/arch, the fuzzer's arch mode, `volec assemble` |
| 0.19.1 | `v0.19.1` | 0.19.0 | aarch64-macos, x86_64-linux, x86_64-macos, aarch64-linux (cross-built) | two soundness fixes: the store intrinsics' destination is `&mut [T]` (a store through a read-only view, or while a view of the buffer is used, is an error), and 0.17's transitional rule accepting a read-only `[T]` where `&mut [T]` is wanted is gone (`fix --values` migrates); examples/arch/sha256sum, coreutils-compatible on the SHA-256 instructions, faster than macOS's sha256sum and OpenSSL, about 5 times coreutils' on Linux |
| 0.20.0 | `v0.20.0` | 0.19.1 | aarch64-macos, x86_64-linux, x86_64-macos, aarch64-linux (cross-built) | parameter conventions in Hylo's spelling, the default syntax: `let` (the default), `inout` with `&x` at the call, `sink`, `var`, accesses used as their values; Rust's spellings `conv.rust` errors with a `try:`, `fix --only conventions` migrates, std, tests, examples, bench and the eval on it (compiler/src on the 0.19 pragma until 0.21); std as a module tree; HashMap/HashSet on a Swiss table (foldhash, SipHash-1-3), BTreeMap/BTreeSet, ipnsort and driftsort; `String` and `str`, std::unicode (UTF-8, graphemes, width, case, Unicode 18), number formatting and parsing; std::io, fs, path, env, process, time, random; owned temporaries dropped at the statement's end; `volec lsp` |
| 0.21.0 | `v0.21.0` | 0.20.0 | aarch64-macos, x86_64-linux, x86_64-macos, aarch64-linux (cross-built) | concurrency: safe `std::thread::spawn` and `scope` with what crosses threads checked (Send and Sync from the types), `std::sync` (atomics with every ordering, Mutex, RawLock, Once, Condvar, mpsc channels), `#[thread_local]`, effects `thread`, `sync`, `tls`, atomics as barriers in the optimizer; the compiler's source in 0.20's conventions, the 0.19 spelling removed (`var`, `inout`, `sink` keywords; the mixed reading only inside fix's migrations); `.vl` sources and `VOLE_*` variables accepted |
| 0.22.0 | `v0.22.0` | 0.21.0 | aarch64-macos, x86_64-linux, x86_64-macos, aarch64-linux (cross-built) | GPU: `std::gpu`, a wgpu-like API native-first with the Metal backend (device, queue, buffers, textures, samplers, bind groups, compute and render pipelines, command encoders, headless surfaces) over `std::objc`, the sizes of runtime-sized arrays bound per dispatch and draw; `std::gpu::wgsl`, a WGSL compiler to MSL with reflection, `Device::shader_wgsl`; std's section index fixed (a hello world 357 M to 96 M instructions) and a compile-cost gate row; std own-checked; `f(x?)` into a `let` parameter kept alive through the call; `fn(T)` is `fn(let T)` |
| 0.23.0 | `v0.23.0` | 0.22.0 | aarch64-macos, x86_64-linux, x86_64-macos, aarch64-linux (cross-built) | windows: `std::window`, winit-like with events pulled, on Cocoa (windows, keyboard and text input with IME basics, mouse, scroll, scale, cursor, clipboard, frames on request, watched fds), loaded only when a program names it; voltty (examples/voltty), a terminal emulator on std::window and std::gpu: a core checked against alacritty_terminal by an oracle and a fuzzer, Core Text glyphs in an atlas, one instanced draw of 16-byte cells per frame with `cells.wgsl` through std::gpu::wgsl, damage tracking, no allocation per frame, a shell on a pty; the rename tools for 0.24: `rewrite --text`, `refactor extension`, `query grep --ignore-case`, releases.toml's `bin` and `ext` |
| 0.24.0 | `v0.24.0` | 0.23.0 | aarch64-macos, x86_64-linux, x86_64-macos, aarch64-linux (cross-built) | **vole**: tachyon renamed (`tachyonc` to `volec`, `.tach` to `.vl`, `TACHYON_*` to `VOLE_*`, symbols `_vole.`; no aliases) by the compiler's own tools and checked by same-output; the releases up to 0.23 still built as tachyonc through releases.toml's `bin` and `ext`; the logo; the language server with a VS Code extension (editors/vscode: highlighting, diagnostics, definitions, references, symbols, hovers with computed effects); `std::cli`, clap's builder without derive; `let` as a borrow, `str` and `Path` views to the own pass, `gl(make())`, the `make().v` double free fixed, an iterator's copied items kept refused (`own.move_out`, a stopgap); timing tests steady under load |
| 0.25.0 | `v0.25.0` | 0.24.0 | aarch64-macos, x86_64-linux, x86_64-macos, aarch64-linux (cross-built) | compile speed (the resolve scans, a line index, the lexer, data as bytes, the assembler, `ld` run directly, an in-house Mach-O linker by default on aarch64-macos: the -O0 self-compile and `check` near half the instructions, a hello world linked 4 times faster) and a semantics audit (five red-team audits, about 1,600 probes kept as tests, a value-semantics fuzzer as the gate's `fuzz-sem`; about 30 families of soundness bugs of released versions fixed: views, exclusivity, drops, threads, the optimizer); the Vole Book (book/, every example checked); std::cli across the examples; `#[link]` and `-framework`; every name resolved in the language server; the chain rebuilt from the seed and checked against recorded hashes (`chain-fresh`, `chain-diverse`) |
| 0.25.1 | `v0.25.1` | 0.25.0 | aarch64-macos, x86_64-linux, x86_64-macos, aarch64-linux (cross-built) | one standard style, applied to the whole tree: `volec fmt` groups imports (`std`, `crate`, the rest) and writes trailing commas in lists whose closing bracket starts a line; docs/style.md, `guide fmt` |
| 0.25.2 | `v0.25.2` | 0.25.1 | aarch64-macos, x86_64-linux, x86_64-macos, aarch64-linux (cross-built) | soundness fixes found by real programs (the -O2 vector loop unrolled by 3, an assignment's let-argument temporaries, std's move exemption narrowed); volec's command line on std::cli; `use.unused`; program roots for the tools; the language server for single files and C headers; WGSL's MSL reserved names; four test tiers, `tools/premerge.sh`, a commit hook, a Linux smoke row and a gate that cannot hang |
| 0.25.2.1 | `v0.25.2.1` | 0.25.2 | aarch64-macos, x86_64-linux, x86_64-macos, aarch64-linux (cross-built) | from the first GPU eval: `f(make()?)?`'s empty argument fixed; float math in std, in vole; std::gpu multiple render targets and depth-only passes; frames for an occluded window; twelve diagnostics; `fix --suggested` and the hooks made safe |
| 0.25.2.2 | `v0.25.2.2` | 0.25.2.1 | aarch64-macos, x86_64-linux, x86_64-macos, aarch64-linux (cross-built) | from the second GPU eval: a `requires` call's `?` arguments kept to the call; std::gpu layouts per entry point, `gpu.unwritten`, more storage formats, limits named; integer methods; ten diagnostics; `query show` across programs; the hooks quieter and clearer |

| 0.25.3 | `v0.25.3` | 0.25.2.2 | aarch64-macos, x86_64-linux, x86_64-macos, aarch64-linux (cross-built) | from the third GPU eval and the roadmap: mapped GPU views that cannot change (breaking: WebGPU's usage rule); a closure drops its by-value parameter; text blocks and `include_str`; the compiler at a terminal; `volec query unsafe` and its baseline; eleven diagnostics; the tools' cache checked; transcripts a std change cannot break; volec's command line on std::cli; the guide's GPU gaps |
| 0.25.4 | `v0.25.4` | 0.25.3 | aarch64-macos, x86_64-linux, x86_64-macos, aarch64-linux (cross-built) | `volec run`; the pathtrace feedback (`fmt_f64`, overlay and headless guides, adaptive array literals); a scripted event loop and GPU timestamps; std's unsafe all justified, six std soundness fixes; compiler/src's modernization begun (938 unneeded unsafe blocks gone, Vec facts in the optimizer, `refactor table`) |
| 0.25.5 | `v0.25.5` | 0.25.4 | aarch64-macos, x86_64-linux, x86_64-macos, aarch64-linux (cross-built) | no language change: six compiler tables to `Vec` (unsafe 4,365 → 3,425 unjustified); dependent edits in one checked call; the hooks check with the tree's std; transcripts a std change cannot break; `Atomic<T>` bounded (breaking), std's statics safe under threads; zero statics in bss, unused statics dropped, the `volec -o` 10x slowdown fixed; `--time-passes=instructions`, `--vec-stats=FN` |
| 0.26.0 | `v0.26.0` | 0.25.5 | aarch64-macos | the first step to Rust's surface: the places IR (places, moves, drop flags) at `check` behind `--places`; struct fields private unless `pub` (`field.private`, `fix --only pub`; `#[sealed]` retired); shaders as `embed wgsl` blocks, checked at `check` and in the LSP |
| 0.26.1 | `v0.26.1` | 0.26.0 | aarch64-macos | the places IR the one source of drops: kept bodies, drop shims, both code generators read it at every level (`VOLE_LOWER=ast`, `--no-places`: the escape); `own.move_out`; `Cell`, `UnsafeCell`, `Freeze` and the `interior` effect |
| 0.26.2 | `v0.26.2` | 0.26.1 | aarch64-macos | `usize` and `isize` their own types, `TryFrom`, saturating float casts, std's lengths `usize`; Rust's format strings, `format_args`, `fix --only fstring`; `where`, `impl Trait` arguments, `pub(crate)`; `defer` removed (breaking); shader parts and `#[repr(wgsl)]`; the IR places every drop, the AST lowerings gone |
| 0.26.3 | `v0.26.3` | 0.26.2 | aarch64-macos | allocation as a capability (no default allocator type: `alloc.default`, `alloc.field`, `alloc.static`, `alloc.last`; `unsafe trait`/`unsafe impl`, `AllocFree`; `fix --only alloc`); f-strings removed; `wrapping_*`, `checked_*`, `Wrapping<T>` and overflow checks at -O0 (`--overflow-checks`), shifts and `/ 0` as Rust's; std's text on `String<A>`, its bytes on `Vec<u8, A>`, `#[deprecated]` and `Buf` deprecated (`fix --only buf`); compiler/src on format literals and `usize` |
| 0.26.4 | `v0.26.4` | 0.26.3 | aarch64-macos | the compiler on Rust's overflow checks (its wrap sites `wrapping_*`, the bootstrap with the checks on); its raw-pointer parameters decided (`fix --only rawptr`: 1,416 of 2,583 `inout`); its statics in context structs, phases 1-3 (`fix --only statics`: the places IR's body, the tools' `Tcx`, front's pass contexts; 2,138 statics to 1,234); `Comp` an `unsafe impl Allocator` |
| 0.26.5 | `v0.26.5` | 0.26.4 | aarch64-macos | the compiler's statics in context structs, phases 4-6 (`base::ctx::Ctx<Comp>` passed as `pcx`, the tables code generation's tasks read through a let view per task, `WgslCx<Arena>`; 1,234 statics to 188); `fix --only statics` doing the by-hand steps and `--prune`; the alloc exemption down to `SYMS` and `TYPES` |
| 0.27.0 | `v0.27.0` | 0.26.5 | aarch64-macos | the rust edition begins (`// EDITION: rust`: references, `Deref`/`Index`, reference patterns, lifetimes and regions in side tables, `borrowck.unchecked`; 56 hand-translated cases); `compiler/std2`, the new std's API (1,414 items, 1,070 typechecking) and the translator's std rewrite table; SYMS/TYPES read-only in tasks and the alloc exemption deleted; Ctx's tables `Vec`s (unjustified unsafe 3,057 to 2,775) |
| 0.27.1 | `v0.27.1` | 0.27.0 | aarch64-macos | the rust edition's borrow checker: NLL on the places IR (docs/design/borrowck.md), 18 `borrowck.*` codes with `explain`, 193 programs checked against rustc; Rust's `Copy` rule, reborrows, captures as loans, deferred `let`; contracts typed by the shared rule; 0.27.0's -O2 aliasing miscompile fixed; docs/design/contracts-effects.md |
| 0.27.2 | `v0.27.2` | 0.27.1 | aarch64-macos | std2 the rust edition's std (1,032 of 1,413 std2 tests at -O0/-O2 under `--check-alloc`, gate 1); the front's rules (docs/design/front-rust.md: pattern and blanket impls, coherence, deref coercion, ranges, format specs); closures in full (kinds, captures, `Send`/`Sync`, bodies borrow-checked, `borrowck.unchecked` retired, E0594/E0596); `[T]`/`str` unsized; the borrow checker's verdict cache; every rust case on std2 |
| 0.27.2.1 | `v0.27.2.1` | 0.27.2 | aarch64-macos | std2 1,306 of 1,454 tests at -O0/-O2 under `--check-alloc`; `impl Trait` returns (§21) and the opaque instance (§22, narrowed: FL11); implied outlives bounds (D4.6); three consumed-value miscompiles fixed (D8.5), E0508, two-phase `write`; the front's std2 gaps (F13, F14.2, F18.4, F9.2, F26.3); floats, `std::env`; contracts and effects R2 (std2 declared, 27 `requires`, 11 `ensures`); hello-rust 3.48x; the gate's std2 builds halved |
| 0.27.3 | `v0.27.3` | 0.27.2.1 | aarch64-macos | the translator `fix --edition rust` and gate 2 (`tests/translate.sh`, the rustc twin); the i32 literal default (FL6); std2 1,402 of 1,472 tests at -O0; lazy std2 parsing (a rust hello world 2.32x MVS's); arrays' by-value IntoIterator |
| 0.27.4 | `v0.27.4` | 0.27.3 | aarch64-macos | gate 3 opens (`fix --edition rust` on compiler/src: 122 type errors, 3,048 borrowck behind them); inference from a later statement (FL1); `[T]`/`str` unsized places (Z9.1c); `&raw` and Rust 2024's `static mut` rule; `format_args` a value; std2 1,445 of 1,473 tests at -O0; a rust hello world 2.03x MVS's |
| 0.27.5 | `v0.27.5` | 0.27.4 | aarch64-macos | std2's `std::time`, `fs`, `process`, `cli` (gate 3 from 122 to 37 type errors); operands read where evaluated (D2.4a); text is not its bytes (F0.6); a generic iterator's item is its bound's (D4.6 f); std2 lexed by its units (a rust hello world 1.78x MVS's, the 2.0x ceiling enforced) |

Add a row here, and an entry to `bootstrap/releases.toml`, for every release.

### What's new in 0.27.5

Gate 3 at 37. std2 has the modules compiler/src uses: `std::time`, `std::fs`, `std::process` and `std::cli`, Rust-shaped, with the translator's rows bending MVS's calls onto them. `fix --edition rust` on a copy of compiler/src now leaves 37 errors (122 in 0.27.4), and `check --borrowck-partial` counts 154 borrowck errors behind them (3,048 in 0.27.4): a rust body reads each operand where it is evaluated (D2.4a), and borrowed literals are promoted (D2.8). In the rust edition, text is not its bytes (F0.6: a `&str` where a `&[u8]` goes is E0308), and the translator writes `b".."` or `.as_bytes()` where bytes are declared; a generic iterator's item is its bound's region, not a borrow of the iterator (D4.6 f); `AsRef` for `&T` with T = `str` no longer calls itself (a stack overflow at run time) nor gives a false outlives (Z9.1c); a borrowed array or tuple literal takes the expected type (F18.4). std2 is lexed by its units from an index made when it is embedded (Z5.2): a rust hello world's check is 1.78x MVS's (2.03x), and the 2.0x ceiling is enforced. MVS programs compile exactly as before. Built and tested on aarch64-macos only.

The front (fl10274):

- A place used mutably once its use is known takes IndexMut and
  DerefMut, as rustc's autoref does (F20.6): `vs[0].push(x)`,
  `ps[0].x.push(x)`, `m[i][j].push(x)`, `r[0].push(x)` through a
  `&mut Vec`, `v[0].iter_mut()`, the same in a closure, `match vs[0] {
  ref mut w => .. }`, and `w.x.push(x)` through a user DerefMut. In
  0.27.4 these read the index through Index and were
  borrowck.borrow_immutable where rustc compiles them. A type with Index
  and no IndexMut keeps `index`, and the write is borrowck's (E0596).
- A `&str` where a `&[u8]` goes is rustc's E0308 in the rust edition
  (F0.6): `str::from_utf8("Hello")`, a `&str` value, and a `&String`, which
  derefs to `str` only. The error's `try:` gives `b"Hello"` or
  `s.as_bytes()`. 0.27.4 took the text as its bytes, the view model of MVS
  (which keeps it). This hid 348 of gate 2's bad translations, most of
  them `str::from_utf8("..")` around a literal.

The front (front275):

- A rust body reads each operand where it is evaluated, as Rust does
  (borrowck.md D2.4a). A Copy place given as an argument, a literal's
  element or an assignment's right side is copied out at that point.
  - The view or reference it reads through ends there, so rustc's
    accepted shapes now pass the borrow checker:
    `err_begin(pcx.nodes[p].start, pcx)`, `pcx.nodes[p].b =
    pcx.nodes[q].a`, `v.push(v[0])`, `f(s.x, &mut s)`, `g(y, &mut y)`.
    Gate 3's `check --borrowck-partial` goes from 3,049 errors to 313
    (conflicts from 2,951 to 215).
  - It is also a run-time fix: `f(x, { x += 1; x })` now passes the old
    `x` first, and `v[{ y += 1; 0 }] = y` stores the old `y`, as in Rust.
  - MVS is unchanged.
  - The same goes for the left side of a primitive binary operator when
    its right side may run a statement: `pcx.nodes[n].a ==
    intern(c"Self", pcx)` is accepted, and `x + f(&mut x)` adds the old
    `x`.
- A shared borrow of a literal, or of an array, tuple or repeat of
  literals, lives for the whole body (borrowck.md D2.8, rustc's
  promotion), so `if sub { &["sub", "checked_sub"] } else { &["add"] }`
  can be used after its branch. `&[x, 1]` and `&[f()]` stay their
  branch's temporaries, as in rustc. A promoted borrow still cannot
  leave the function (L2).
- With both, gate 3's borrowck errors go from 307 to 286: conflicts from
  215 to 201, dropped_borrowed from 7 to 0. All 286 are the translator's
  to fix; for each shape rustc rejects the same code.
- std2 is lexed by its units (front-rust.md Z5.2). `embed.sh` writes an
  index of std2's units, made by the compiler (`volec __std2-index`).
  A build reads the index and lexes only the units it reaches, about
  half of std2's text. The tokens it keeps are the same as from lexing
  the whole text (tests/std2/units.sh).
  - A rust hello world's build is 1.78x MVS's, down from 2.08x. The 2.0x
    ceiling in tests/compile_cost.sh is now enforced.
  - The commit hook and the merge driver remake the index, like the rest
    of stdsrc_rust.vl. It adds about 150 KB to that file and 0.5% to the
    compiler's own compile.

The translator (g3274):

- A result's views where elision cannot tie them: with no parameter to
  borrow from, every view in the result is `'static`, inside it too
  (`Vec<Opt<'static>, Gpa>`); with two or more and no `self`, the
  function's `'a`, on the result and on each parameter taken by a shared
  reference (`&mut` ones keep their own). Gate 3's borrowck.elision: 40
  to 4.
- No move out of an index: an `if` of two places given to a reference
  parameter borrows each branch (`if c { &a.x } else { &a.y }`), and
  rewrite.tsv's `Vec::free`/`String::free` on an element (`$r=index`, a
  new condition) is `{ $r.clear(); $r.shrink_to_fit(); }`.
- `'static` results by an explicit list in sig.vl's static_result, each
  with its evidence: base::sym_text (intern's copies and the cache's
  buffer, never freed), tools::patch::target (argv),
  tools::testrun::build_key (a fresh buffer). A view of SRC is not
  `'static` (add_source reallocates it): tools/probe keeps two offsets
  in place of its view, and lex_text_block reads `SRC[0..lex_end]`
  itself. MVS's `static var SRC: [u8]` stays a known gap (its
  translation `static mut SRC: &'static [u8]` is unsound), a design item
  of 0.27.5's.
- `str::from_utf8(..).unwrap()` only for a printed value that is bytes
  where it is declared: a binding, parameter, field, static or constant
  written `[u8]` (or an element of one written `[[u8]; N]`), a call whose
  result is, a part, a borrow, a block or an `if` of such values. A
  literal, an `if` of literals, a `str` binding and an element of a
  `[str; N]` stay text: 0.27.4's twin agreed on 305 of the 911
  round-tripped programs, 230 of its rejections `str::from_utf8("..")`;
  the same programs now agree on 522 of 559. A literal that is a
  static's or a constant's `[u8]` value, or an `if` branch beside
  declared bytes, is `b".."`.
- std2's fs, process and env by rewrite.tsv's rows: `fs::exists`,
  `fs::append`, `fs::copy`, `Metadata::modified`, `DirEntry::is_*`,
  `Command::new` to `Command::new_in($1, $a)` (`$a`, when the function
  has no Gpa, a program allocator it makes before the call), `process::id`
  and `Child::id` as i32, `env::get_in` to `var_in`. A free function's
  row may name its module (`fs::copy`, not io::copy). Bytes given as a
  path, a program or an argument are `str::from_utf8(p).unwrap()`.
- A result's `'a` by flow: with MVS's view summary, only on the
  parameters the result's views come from, and on an item's region for
  an item with views taken by reference (`leaf: &Leaf<'a, Gpa>`), so a
  temporary given to another parameter need not outlive the result
  (cli/tree.vl's two borrowck.return_local).
- Gate 3: 127 (at std2's process) to 17 errors; 12 wait for std2's cli,
  2 for std::gpu, 1 for std::num; borrowck (partial) 142 to 139.

The borrow checker (bc275):

- A generic iterator's item is its bound's, not a borrow of the
  iterator (borrowck.md D4.6 (f)): in `fn first<'a, I: Iterator<Item =
  &'a str>>(args: I) -> Option<&'a str>`, `let mut it = args;
  it.next()` and a `for t in args` loop return the item. 0.27.4 tied
  the template's `I::Item` to `next`'s `&mut self` (E3) and reported
  borrowck.return_local, which blocked std::cli's `parse_in`. With
  `Item = &'b str` and an `&'a str` result it is borrowck.outlives, as
  in rustc. Cases `rust_b_proj_item_bound` and
  `rust_b_err_proj_item_bound`, both twinned with rustc.

std2 (std2275), for the modules compiler/src uses:

- `std::time`: `Duration` (`new`, `from_secs`..`from_nanos`,
  `from_secs_f64`/`f32` and their `try_`, `as_*`, `subsec_*`, `checked_*`,
  `saturating_*`, `mul_f64`, `div_f64`, `div_duration_f64`, the operators
  and Debug as Rust prints it: `1.5s`, `2ms`, `{:.2?}`), `Instant`,
  `SystemTime` with `UNIX_EPOCH` and `SystemTimeError`; and
  `std::thread::sleep`. Changed from Rust's: `as_millis`, `as_micros` and
  `as_nanos` are u64 (saturating), `UNIX_EPOCH` is a static, and there are
  no `Duration::ZERO`/`MAX` constants (a constant of a struct type waits
  for const evaluation). Seven std2_time cases, six of them twinned with
  rustc.
- `std::fs`: `File` (`open`, `create`, `create_new`, `options`,
  `metadata`, `set_len`, `sync_all`; Read, Write and Seek, and Read and
  Write for `&File`), `OpenOptions` (Rust's `&mut self` builder and its
  EINVAL rules), `Metadata` (`len`, `file_type`, `is_dir`, `is_file`,
  `is_symlink`, `permissions`, `modified` as a SystemTime), `FileType`,
  `Permissions`, `read_dir` with `DirEntry` (`path`, `file_name`,
  `file_type`, `metadata`), and `read_in`, `read_to_string_in`, `write`,
  `copy` (the permission bits too), `metadata`, `symlink_metadata`,
  `exists` (an `io::Result<bool>`), `remove_file`, `remove_dir`, `rename`,
  `create_dir`, `create_dir_all`, `remove_dir_all`. `std::io` gains
  `Seek` and `SeekFrom` (Rust's place), and `ErrorKind::InvalidFilename`;
  `[T]` and `[T; N]` are `AsRef<[T]>`. Changed from Rust's: a path is a
  `&str` until std::path, and a DirEntry's `path()` and `file_name()` are
  `&str` views of the entry (a name that is not UTF-8 is read_dir's
  InvalidData); `mode` and `as_raw_fd` are inherent until std::os. MVS's
  `fs::append` is gone: `OpenOptions::new().append(true).create(true)`.
  Four std2_fs cases, three twinned with rustc.
- `std::process`: `Command::new_in(program, a)` (its strings on a: the
  allocator named, Rust's `Command::new`) with Rust's `&mut self`
  builder: `arg`, `args`, `env_remove`, `stdin`/`stdout`/`stderr` with
  `Stdio::inherit`/`null`/`piped`, `spawn`, `status` and `output` (stdout
  and stderr piped and stdin /dev/null unless set, as Rust's, the bytes
  on clones of a); `Child` with its piped `stdin`/`stdout`/`stderr`
  (`ChildStdin` a Write, the others Read), `id`, `wait`, `try_wait`,
  `kill`; `ExitStatus` (`success`, `code`, `signal`, Display as Rust's:
  `exit status: 3`, `signal: 9 (SIGKILL)`); `exit`, `abort`, `id`.
  MVS's `foreground` stays (vole's own). Four std2_process cases, three
  twinned with rustc (the twin's prelude maps `Command::new_in(p, gpa)`
  to `Command::new(p)`).
- `std::cli`: MVS's parser (clap's builder without derive) in the rust
  edition: `Arg`, `Command`, `Matches` and `CliError` carry the lifetime
  of the text they are given (`Command<'a, A>`; a `Command<'static, A>`
  of literals parses any words), the builders take and return the value
  as clap's, `short` takes a char and `num_values`, `width` and `count`
  are usize; `indices_of` stays `&[i64]`. CliError is Debug. The
  translation's rows: `short(b'o')` is `short(b'o' as char)`, the usizes
  are cast, and `Command`, `Arg`, `Matches`, `CliError` written as types
  get their `'_`. MVS's 16 cli cases are std2_cli cases (`// RUSTC:
  none`: Rust's std has no command-line parser). With std::cli, gate 3
  goes from 127 errors to 37.
- `Clone` for `&T` (Rust's core): an allocator given by reference,
  `&ArenaScope<'_, Gpa>`, is `A: Allocator + Clone`.

### What's new in 0.27.4

Gate 3 opens. `volec fix --edition rust` run on a copy of compiler/src leaves N errors, printed by the gate's `gate3` row every release; 0.28 starts at N = 0. Its first full measurement was 1,414 (after 0.27.3's three parse shapes); 0.27.4 leaves 122 type errors, most of them std2 modules the compiler uses that std2 does not have yet (`std::cli`, `fs`, `process`, `gpu`), and `volec check --borrowck-partial` counts the 3,048 borrowck errors behind them, about 2,750 of one shape that 0.27.5's first item fixes (an operand read where it is evaluated, D2.4a). In the rust edition: a type is inferred from a later statement (FL1, F18.6: `Vec::new_in(a)` then a push, a later arm, `"4".parse().unwrap()`, `_` in a type); `[T]` and `str` are unsized places that `&[T]` and `&str` refer to (Z9.1c step B: impls keyed by them, method lookup through a view, `NonNull<[u8]>` 16 bytes); `&raw const`/`&raw mut` (F30.2), and a reference to a `static mut` refused as Rust 2024 does (D6.2.5); `format_args(..)` a Display value (F16.4); indexing through `&mut [T; N]` (F20.1). std2 passes 1,445 of its 1,473 tests at -O0 (1,402 of 1,472 in 0.27.3). A rust hello world's check is 2.03x MVS's (2.32x): builtin impls only for the primitives a program brings in (F15.1), and std2's own settled bodies are not borrow-checked again (Z7.2); the 2.0x ceiling is printed, enforced from 0.27.5. A crash on a closure capturing a widened integer, in MVS too, is fixed. MVS programs compile exactly as before. Built and tested on aarch64-macos only.

The front (integrator):

- `format_args(..)` is a value in the rust edition (F16.4): std2's
  `std::__rt::Interp`, a Display that writes the literal through the
  Formatter it is given, so it goes to a `T: Display` parameter,
  `to_string_in` or `write`. In 0.27.3 any such use was "unknown struct
  'Interp'" (102 of gate 3's errors). std2_fmt_format_args,
  std2_fmt_formatter_write_fmt and std2_fmt_write_write_fmt pass.

The front (front274):

- FL11: a template's opaque instance (borrowck.md §22) reports its type
  errors as rustc does (`x + x` of `T: Add<Output = T>` returned as an
  i64, E0308), where 0.27.2.1 reported only the bound-only rule's. The
  model gained what that needs: operators on a type parameter through
  its bounds, a bound's type arguments (`S: AsRef<str>`) and a trait
  parameter's default (`Rhs = Self`), `T::default()` and `T::CONST`,
  `*d` with `Deref`, `g[i]` with `Index`. An instance that meets a gap
  left (a generic method of a generic trait, a `where` predicate, a
  bound unresolved while it is made) is unsure, and its errors are
  forgotten; std2-check stays at 0.
- `g[i]` of a `g: &G`, G a struct with Index, reads through the reference
  (F26.3).
- FL1, stage 1: inference from a later statement (F18.6). In the rust
  edition a type parameter that a call, a variant or a struct literal
  leaves free is a type variable. It is solved by the first check that
  meets a definite type: `let mut v = Vec::new_in(a);` and then
  `v.push(2i64)` (also after a `v.len()`), a map by its insert, a value
  passed where its type goes, the tail, an `Err(..)` in a later arm.
  Solving retypes the function in place and makes its instances again.
  A variable still free at the function's end is the old `type.infer`,
  and so is a format hole, `as`, a capture or a method on it before then.
  An untyped literal fixes `i32` at once (`v.push(1)`: `Vec<i32>`, where
  rustc may infer from a later use; FL1, case `rust_f_fl1_literal_i32`).
  std2 at -O0: 1,430 pass, 39 xfail (1,400 and 69).
- FL1, stage 2 (F18.6 (d)-(f)). A `_` written in a type is a variable
  (`let f: FromFn<_> = from_fn(..)`, `let v: Vec<_, Gpa> = ..`); one
  never fixed is `type.infer` at the `_`, with one error for a `_` and
  the parameter it was bound to. A projection of a variable is solved
  with it: `let a: u32 = "4".parse().unwrap();`. A closure whose bound
  mentions a variable infers its own parameter. `e?` checked against a
  type checks its value first (`let n: u8 = s.parse().map_err(..)?`). A
  variant pattern of a variable's enum (the `?`'s match) names the
  solution's variant, which fixes a `FromStr` impl that read `0` fields.
  std2 at -O0: 1,438 pass, 31 xfail.
- An `if` with an `else`, a `match` or a block whose values are literal
  trees makes its `let` open (F18.5), as a literal does: `let e0 = if c
  { 1 } else { 0 };` takes `i64` from a later `for i in e0..np`, and
  `let b = if c { 0xf8000000 } else { 0 }; let x: i64 = b;` is no longer
  out of range for i32. A `for` range's open start takes the end's type.
- A spawned closure may reach a rust-edition `static mut`, directly or
  through what it calls, and so may a C function declared in the rust
  edition (F19.6). Every such use is in `unsafe`, as in rustc, so it is
  no longer `sync.global`. It keeps the `global` effect. An MVS `static
  var` stays for the main thread only. std2's checking allocator
  (`--check-alloc`) no longer makes every allocating thread
  `sync.global`.
- F30.2, `&raw const P` and `&raw mut P`, in the rust edition: a place's
  address, a raw pointer, with no reference made. `&raw mut S` of a
  `static mut` needs no `unsafe`; a field of one, `&raw const S.n`, does
  (E0133). `&raw mut` needs a `mut` place (E0596), and a temporary is an
  error (E0745). D6.2.5 is tightened: `&mut S` of a `static mut` is a
  reference even where a `*mut T` goes (`let p: *mut T = &mut S;`), and
  its help now gives `&raw mut S`. std2's checking allocator takes its
  lock's address that way. A place under the deref of a raw borrow is a
  place through the raw pointer: `(*&raw mut S).push(2)` and `&mut
  *&raw mut S` make no reference to the static (D6.2.5), as in rustc.
- `e as *const _` and `e as *mut _` take the pointee from the operand
  (F29.1). An integer cast to one is E0641.
- A closure whose body is a captured integer widened to its bound's
  result type (`move || k` with `FnOnce() -> i64` and `k` an i32, as a
  loop's `thread::spawn_in(move || k, gpa)`) failed the build ("places: a
  function not lowered from its body", MVS too): the capture is found
  under the widening cast now.

The translator (g3274):

- Gate 3 is measured: `tests/gate3.sh` translates a copy of compiler/src
  with `volec fix --edition rust --force` and checks it in the rust
  edition; it prints `gate3: N errors (by code: ...)`. The release
  gate's `gate3` row (--release) runs it, informational: it fails only
  when the translator or the check cannot run. N went 309 (33 parse
  errors hiding the rest) -> 1,414 (the real first wall) -> 122 (by
  code: 117 type error, 2 distinct.mix, 2 edition.lenient,
  1 item.private). Of the 122, 110 are std2's missing modules and items
  (`std::cli`'s `Matches` above all, `fs`, `process`, `gpu`,
  `env::get_in`, `count_ones`). borrowck runs only on a program with no
  type errors, so `check --borrowck-partial` (informational) checks the
  bodies that type-checked, and gate 3 prints that count too: 3,048
  (2,950 conflict, nearly all a Vec index's copy beside a `&mut` of its
  root, which rustc accepts: three XFAIL rust_b_ok_index_temp_ cases for
  0.27.5's fix).
- The first wall's three shapes: a static's `unsafe { }` that starts a
  statement and is an operand there is `(unsafe { .. })`, and a method
  on a static through the receiver's borrow wraps the call, not a copy;
  a typed receiver `self: *T` is `self: *mut T`; a name a file's use
  binds (`Tok::{Hash}`) gets no std import beside it. `&cx` of an inout
  parameter given to a `*T` is `cx` (the `&mut`, coerced).
- `[u8]` printed as text in a program that also reads its bytes is given
  `str::from_utf8(x).unwrap()`: a hole naming it (the named argument), an
  argument after the literal, `println(x)`'s value, an argument of a
  `T: Display` parameter; only what was written `[u8]` where it is
  declared. A text literal given to a `str` parameter stays text.
- rewrite.tsv's type rows are applied where the type is written (`Arena`
  -> `Arena<Gpa>`, `thread::JoinHandle<T>` -> `JoinHandle<T, Gpa>`,
  `ScopedArena`, `Fmt`, ...), their arguments kept, the names they write
  imported (a module a row's path starts with too: `use std::mem;`). A
  row's `$a` with no allocator argument is the enclosing `Gpa`
  parameter (`thread::spawn(f)` -> `thread::spawn_in(f, gpa)`); MVS's
  `to_string_in(x, a)` is std2's `format_in(x, a)`.
- An array's address cast to a raw pointer is `a.as_mut_ptr() as *mut U`
  (`as_ptr` for a `let`); a static's `.len()` stays inside its `unsafe
  { }`; an index of any integer type is cast to usize; a raw pointer's
  part `p[a..b]` is rewritten after the statics, its operands' edits
  folded in; a char literal MVS types as an integer is `b'a' as i64`;
  `&mut $1` of an argument written `&x` borrows x once.
- A `static mut`'s borrow is its raw address (F30.2, Rust 2024's
  static_mut_refs): a method on it is `(*(&raw mut V)).push(x)` (`&raw
  const` for a `&self` method), `&V` given to a `*T` is `&raw mut V`.
  `use std::string::str;` is dropped (std2 has no such module: `str` is
  the type). An impl of MVS's `Allocator` is std2's: `try_alloc` is
  `allocate` (the null pointer `Err(AllocError)`), `try_resize` is
  `grow` and `shrink`, which calls it (MVS's try_resize keeps
  min(old, new) bytes, as realloc does), `free` is `deallocate`; each
  body is kept, its parameters bound from the layouts. An `Iterator`
  impl's MVS-only `exact_len` and `at` are dropped: no std2 method is
  either (`at(k)` reads without advancing, so it is not `nth`, and
  `ExactSizeIterator::len` needs an exact size_hint).
- More shapes the rust edition reads otherwise: a local's or an array
  element's address cast to another pointee is `&raw const x as *mut U`
  (`&raw mut` for a `var`); `&p[i]` of a raw pointer is `p.add(i)`; a
  raw pointer to views `*[u8]` is `*mut &[u8]`; an inherent method's
  receiver of a type MVS copies is `self`; a `let` of an `if` with a
  literal branch is `: i64`, an i64 literal outside i32 under a cast
  gets a suffix (`u64` above i64::MAX); a literal branch of an `if`
  whose other branch is bytes is `b".."`; a row whose receiver is a
  row's call at the same place is applied; `push_fmt` is
  `std::fmt::write` (a program's own `write` shadows the prelude's);
  `memchr` is an iterator's position. compiler/src's `base::len_arg`,
  0.26.2's bridge to usize parameters, is gone (`e as usize` at its 19
  sites).
- Gate 2: tests/translate.sh translates with `--force` (the generated
  sweep cases); the corpus round-trips 43 of 50 (41 at 0.27.3's
  end). causes.tsv reclassified for every case the walls moved.

The front (fl10274):

- `[T]` and `str` are types of their own in the rust edition (Z9.1c,
  FL10's second stage): the unsized place, which `&[T]` and `&str`
  reference. `&T` with `T = &str` is a reference to the view, `&&str`,
  so `Iter<&str>` yields `&&str`, `copied` makes it `&str` again, and
  Vec<&str>'s `Extend<T>` and `Extend<&T>` are two impls. An impl for
  `[T]` and one for `&[T]` can both be written. A `?Sized` parameter
  binds the place: `io::copy` reads a `&[u8]`, and `&mut "ab".as_bytes()`
  is a `&mut &[u8]`. A Sized one bound to the place is `type.unsized`,
  rustc's E0277, so `Vec<[i64]>` is rejected. A method on a view probes
  as rustc's does: the place's `&self` method first, then the view's
  own impls. A `NonNull<[u8]>` is two words. Z9.1a's special case for
  reference impls over a slice is retired. std2 gains rustc's
  forwarding impls for references (`Borrow`, `AsRef`, `AsMut`, `Eq`,
  `Ord`). Not yet: an iterator of views collected in std2's generic
  instances (`[&str; 2].into_iter().collect_in(a)`, borrowck, D4.6,
  which also failed before) and `Box<[T]>`/`Box<str>` (std2's Box has
  a Sized T), both 0.27.5.
- `h[i]` of an `h: &mut [T; N]` (or `&[T; N]`, `&&[T; N]`) indexes the
  array through the reference, as rustc's autoderef does (F20.1); 0.27.3
  read it as a raw pointer's arithmetic, `unsafe` (about 32 of gate 3's
  errors). `<I as SliceIndex<[i64]>>::Output` takes the impl its trait
  arguments name (F8.1).
- A rust hello world's build costs about 2.0x MVS's (2.34x in 0.27.3);
  the 2.0x ceiling is enforced from 0.27.5, with std2 lexed lazily
  (tests/compile_cost.sh prints it). A build makes
  std2's builtin impls only for the primitives the program brings in
  (F15.1: it names them, a literal's suffix, or a word such as `chars`
  or `HashMap` that brings them through std2's types); i32, usize, u8
  and bool always. A build whose check fails without one is made again
  with every impl, so no other impl is chosen and the errors are the
  eager build's. A build does not borrow-check std2's own non-generic
  bodies, which the std2-check row checks clean (Z7.2); every instance
  of a std2 template a program reaches still is.

### What's new in 0.27.3

The translator and gate 2. `volec fix --edition rust FILE|DIR` rewrites an MVS program into the rust edition, directed by its types: parameter modes become `&T`, `&mut T` or `T`, `&x` at a call becomes the borrow the parameter takes, `var` becomes `let mut`, a view becomes a slice, a struct holding a view gets a lifetime, std calls follow `compiler/std2/rewrite.tsv`'s rows by type, contracts are carried, and an integer literal MVS typed i64 is annotated where the rust edition's i32 default would change it. `tests/translate.sh` measures the round trip (translated, built in the rust edition, the same output), and the rustc twin runs what round-trips under rustc; the release gate's `translate` row prints both, informational until 0.27.4 (the counts are in docs/roadmap.md's 0.27.3 gate record). In the rust edition an unsuffixed integer literal now takes its type from its first use, and is i32 when nothing fixes it (FL6, F18.5). 1,402 of std2's 1,472 tests pass at -O0 (1,306 of 1,454 in 0.27.2.1). std2 is parsed lazily, by the items a program reaches, and a `println` with no holes writes its literal directly: a rust hello world's check costs 2.32x MVS's (3.48x). Arrays iterate by value (`std::array::IntoIter` over `ManuallyDrop`), a rust-edition union drops none of its fields, an `if` condition's temporaries drop before its branch (L3), and std2 gains floats' methods, Unicode's tables, `std::sync::atomic` and more of `std::env`. Gate 3's first run: `fix --edition rust compiler/src` stops at 50 parse and import errors, all three translator shapes (an `unsafe { }` operand, a raw-pointer `self`, an import its file already binds); 0.27.4 prints its count. MVS programs compile exactly as before. Built and tested on aarch64-macos only.

Not in 0.27.3, by name: inference from a later statement (FL1), `[T]` and `str` as their own types (FL10's second stage, Z9.1c step B) and the opaque instance's other type errors (FL11), all 0.27.4; a rust hello world within 2.0x of MVS's (enforced from 0.27.4); std2's `std::cli`, `std::gpu`, `fs`, `Mutex` and `mpsc`, and `embed` blocks in the rust edition.

Gate 2's harness (twin273):

- `tests/translate.sh`: the round trip. Each MVS program of a set is copied into `target/translate`, translated in place (default `volec fix --edition rust`; `--translator CMD`, `--identity`), built with `--edition rust`, run, and compared with the reference. The reference is the case's EXPECT, EXIT and STDERR lines, or the MVS build's output (bench, `--ref build`). The sets:
  - `examples`: the tests/examples cases;
  - `bench`: bench/, bench/std, bench/vecloop;
  - `run`: tests/run's MVS cases that run;
  - `guide`: the guide's MVS programs;
  - `rust`: the rust corpus, the runner's own check.

  It prints one count per set, a cause per failure (`no-translation`, `type CODE`, `borrowck CODE`, `link`, `crash`, `output`, `exit`, `stderr`, `timeout`), the codes by frequency and the failures that look like Q7's (a borrowck error on a line that borrows a literal or a constant). `-f LIST` selects the programs a list names, and `-j N` sets the jobs. tests/translate/causes.tsv, the translator's record of why, is grouped by cause; a cause for a program that now round-trips is reported as stale (`--triage` appends the new failures as `?`). The release gate's `translate` row runs it with `--twin` (below). It is informational until 0.27.4: it prints both counts and never fails. Results:
  - the identity translator round-trips all 339 of the rust corpus's run cases;
  - the translator at its first merge round-trips 600 of 1,575 programs: run 575 of 1,347, examples 3 of 83, bench 1 of 44 (at -O2), guide 22 of 104;
  - Q7 (L2, rvalue static promotion): 0 failures borrow a literal or a constant, so L2 waits for a count that needs it.
- The rustc twin's shim, `tools/rustc-twin/` (plan-0271 §2.2). prelude.rs is the part of `allocator_api` that stable rustc lacks: one global allocator `Gpa`, with the `_in` functions as extension traits over it (`new_in`, `with_capacity_in`, `from_in`, `Box::new_in`, `collect_in`, `to_string_in`, `clone_in`, `to_owned_in`, `default_in`, `from_iter_in`, a slice's and a str's `_in` methods, `lines_in`). twin.py makes a rust-edition program Rust and keeps its line numbers:
  - main is wrapped;
  - a type loses its allocator argument, and a generic `A: Allocator` becomes Gpa;
  - the format functions become macros, and `format_in` and the free `X_in(.., gpa)` functions become their Rust names;
  - the check attributes are dropped.

  `tools/rustc-twin.sh CASE... [--guide]` runs a program under rustc and compares its stdout and exit code with the case's. A difference is named by `// RUSTC-DIFFERS: WHY` in the case, or in tools/rustc-twin/divergences.tsv for a program without a case. The rust corpus's run cases and the guide's rust-edition program: 304 of 341 agree, 5 named, 0 differ. `tests/translate.sh --twin` twins every program that round-trips, with one count per set: 366 of 598 agree at the translator's first merge. The differences are named in tools/rustc-twin/divergences.tsv: L7's field captures, and arrays' by-value IntoIterator. `--alloc-api` (in both tools, a manual mode) runs rustc as nightly (RUSTC_BOOTSTRAP=1) with Rust's own allocator_api (prelude_alloc.rs): `Vec<T, A>` and `Box<T, A>` are std's own, a String<A> wraps a Vec<u8, A>, and HashMap and HashSet hold their allocator. So a borrow of an allocator (`format_in(.., b.allocator())`, a String<&A>) is checked as rustc checks it: 305 of 348 agree on the rust corpus and the guide. Its summaries say `allocator_api, RUSTC_BOOTSTRAP=1`.
- In the rust edition an `if`'s condition and a match guard are terminating scopes, as a `while`'s condition was (borrowck.md L3, the Rust reference's "Temporary scopes"): their temporaries drop before the branch or the arm runs. MVS's order is unchanged. Case `rust_b_ok_temp_if_cond_scope`, which twins with rustc.
- Two cases agree with rustc on a temporary that holds a shared loan across a two-phase activation (D7.3): rejected when its type has a Drop impl, accepted otherwise. That is why `b.extend_from_slice(format_in(.., b.allocator()).as_bytes())` is rejected by both rustc and vole; `*b.allocator()` is accepted by both.
- `tools/borrowck-twin.sh --shim`: the verdicts through the shim. The gate row uses it: 365 of 400 agree (358 with `--std2`), 10 divergences, 0 mismatches. Seven `// RUSTC: none` markers ("no allocator until 0.27.3") are gone.
- `tests/translate.sh --record query|refactor`: the migration surface's record mode. Each transcript's program is translated in a copy, the suite's runner re-records the transcripts (`-u`), and the result is a diff to review (target/translate/record/SUITE.diff). With the identity translator, 0 of 42 query transcripts change. With the translator's first merge, 35 of 42 change (2,198 lines to review; 34 programs translated, 1 not). `tests/guide/run.sh --split DIR` writes the guide's blocks out for the runners.

The translator (tr273):

- `volec fix --edition rust FILE|DIR` translates an MVS program into the rust edition, in place (`--dry-run`: the diff only; `--list-left`: each place left to hand, `note fix.edition_left`). It is type-directed: the MVS front checks the program, and what it resolved decides each rewrite (`guide fix#edition`, `explain fix.edition_left`):
  - parameters: a let `x: T` is `x: &T` where MVS borrows and `T` for a copy, `inout T` is `&mut T`, `sink T` is `T` (`mut` when the body changes it), a view `[T]` is `&[T]` (`&str` in a program that uses its bytes only as text); receivers are `&self`, `&mut self` and `self`;
  - bodies: `var` is `let mut`, `inout r = &v` is `let r = &mut v`, the inout marker `&x` is `&mut x`, a borrow MVS makes is written `&x`, an access Rust does not dereference by itself is `*r`, `v.len` is `v.len()`, `println(x)` is `println("{}", x)`, a literal MVS types as i64 by default is annotated, an i64 index is cast `as usize`;
  - statics and pointers: `static var` is `static mut`, and each use outside unsafe code is put in `unsafe { }`; a raw pointer `*T` is `*mut T`, and its element `p[i]` is `(*p.add(i))`;
  - items: the derives get Rust's names (`Eq` with `PartialEq`, `Ord` with `PartialOrd`), the copy types derive Clone and Copy, Display's `fmt` returns its Result, an operator impl gets its `Output`, and a view result of a function that takes no reference is `&'static`;
  - std: each call with a rewrite.tsv row is written as the row says, chosen by type (`T: Copy`, `use=read`), with the row's `!` cases left to hand; std's paths become std2's, and the imports std2 needs are added. A closure literal that a row calls in place is inlined, its parameters bound to the arguments, and the `sort_by` rows dereference a Copy element.
- Struct regions: a struct or enum holding a view (`[T]`, `str`, a `let T` or `inout T` field, or another such type) is generic over its region, `struct Tok<'a> { text: &'a str }`, used as `Tok<'_>` elsewhere, or `Tok<'static>` as the result of a function that takes no reference; where elision does not decide, `'_` stays for a hand fix. Contracts carry over: their clauses are translated as the body is (`*v`, `old(v.len())`).
- FL6 (front273): an i64 literal at a generic position gets `i64` (`fold(0i64, ..)`, `Some(4i64)`, `(0i64..n).map(..)`), and a literal-only `let` its `: i64`; a text literal given as bytes is `b".."`; a raw pointer's part is `std::slice::from_raw_parts(..)`.
- Gate 2's counts, round-tripping through the translator: run 734 of 1,347, bench 15 of 44, examples 4 of 83. In 0.27.2.1 they were 598, 5 and 3. tests/translate/causes.tsv classifies the rest: std2 175 (`std::cli`, `std::gpu`, `Scanner`, `sync::Mutex`, `fs`, which are 0.27.4's), front 17 (`embed` blocks), borrowck 63, translator 454. The run corpus (tests/translate/corpus1.txt): 41 of 50.

The front (front273):

- FL6, the i32 literal default (front-rust.md F18.5): in the rust
  edition an unsuffixed integer literal with no context is an `i32`, as
  Rust's, and an unannotated `let` of literals is an integer inference
  variable, solved by its first use that gives it a type: an expected
  type (an argument, an annotation, the return, a field, `&x` where
  `&[u8]` goes, `a[0]`, `&a[..]`), the other operand of an operator, an
  assignment's value (`s += m.v`), a generic call's argument. `x += 1`,
  `x = 0` and `x < 10` keep it open; `let r = &x;` links r to x; a
  closure closes what it captures when it is checked. Around it, as
  rustc's: `&1` where `&T` goes is a T (`m.get(&1)`, `x.total_cmp(&0.0)`),
  a parameter's bound picks a literal's type through another
  parameter's bound (`K: Borrow<Q>`), an array of literals at a generic
  call takes the expected type's element (`Vec::from_in([1, 2], gpa)`),
  a closure argument is typed before the literal arguments when it can
  be (`map_or(0, |x| x + 1)`), `S(7)` of a tuple struct takes the
  expected type's arguments, and `-1` where an unsigned type goes is an
  error (E0600). The early closes that diverge from rustc are FL6's,
  by name; the corpus writes `1i64` where it meets one (31 cases). MVS
  is unchanged: its fallback stays `i64`, and no local is open.
- `b"..."` byte strings parse and are `&[u8]` (F23.2, FL12).
- `Tr::f(args)` takes Self from the expected type only when f returns
  `Self` (`Step::steps_between(&a, &b)` inside an impl, F8.2).
- `&T as *const U` with U not T is an error, rustc E0606 (F29.1); it
  read a T as a U.
- A bound that names no trait in scope no longer crashes a derived
  impl's supertrait check (`derive_generic.vl` read in the rust edition).
- front-rust.md names FR5 (integer widening) and FR6 (an index of any
  integer type), the rust edition's lenient MVS rules.
- On std2 a `&str` is Copy and clones by copying (F0.4): `parts.iter()
  .copied()` over a `[&str]`, `Option<&&str>::copied`, `r.clone()` of a
  `&&str`, `repeat_n("a", 2)`; of two impls a `&str` makes alike
  (`Extend<T>`, `Extend<&'a T>` of a `Vec<&str>`) the by-value one is
  taken (F26.3).
- `TryFrom::try_from(x)` takes Self from an expected `Result<Self, _>`
  (F8.2), and `x.try_into()` against an expected `Result<U, _>` is
  `U::try_from(x)`; without an expected type (a match's scrutinee, a
  generic instance) U waits for FL1 (0.27.4).
- A range value indexes a slice, an array or a str through Index (`a[r]`
  with `r: Range<usize>`, a RangeFull; a read, F26.3); a RangeFull's
  RangeBounds parameter comes from the expected type
  (`r.start_bound()` as a `Bound<&i64>`, F14.1).
- A `&mut self` method of str on a String's index borrows it through
  IndexMut (`s[1..].make_ascii_uppercase()`, `&mut s[1..]`), and needs
  the String mutable (own.readonly, rustc E0596).
- A `&mut self` method of a generic trait called on a `let` binding,
  `s.index_mut(r)`, is own.readonly as any other `&mut self` method
  (F6.3, rustc E0596); 0.27.2.1 accepted it.
- Known gap: `index_mut` on a `&mut [T]` receiver (`(&mut a[..])
  .index_mut(r)`, and so `&mut v[r]` with a range value r) is refused as
  "calling a method through a raw pointer is unsafe".

std2 (std273):

- f64's and f32's methods, Rust's names and meanings (front-rust.md
  F15.4's "come in 0.27.3"): `floor`, `ceil`, `round`,
  `round_ties_even`, `trunc`, `fract`, `abs`, `signum`, `copysign`,
  `is_nan` and the other tests, `min`, `max`, `clamp` (which panics on
  min > max), `recip`, `to_radians`, `to_degrees`, `sqrt`, `cbrt`,
  `hypot`, the trigonometric functions, `exp`, `exp2`, `ln`, `log2`,
  `log10`, `log`, `powi`, `powf`, `next_up`, `next_down`, `div_euclid`,
  `rem_euclid`, `total_cmp`, `to_bits`, `from_bits`. They live in
  std2's private `fmath` module, which uses MVS's std::math algorithms
  (fdlibm's, no libm). The transcendental functions are within an ulp
  or two of the libm Rust calls: their cases print 12 digits. `mul_add`
  is not in.
- char's classification and case use Unicode's tables (18.0.0, MVS's),
  in a private `unicode` module, in place of std2's approximations:
  `is_alphabetic`, `is_numeric`, `is_whitespace`, `is_lowercase`,
  `is_uppercase`, `to_uppercase` (`ß` gives `SS`), `to_lowercase`.
  `str::to_lowercase_in` applies Final_Sigma (`ΟΔΟΣ` gives `οδος`).
  The tables are str literals, because the front has no `b"..."` yet.
  char's and str's Debug escape the controls and every white space
  but `' '`, as Rust's do.
- `std::sync::atomic`, std::sync's first part: `Atomic<T>`, plus Rust's
  `AtomicBool`, `AtomicI8` .. `AtomicUsize` and `AtomicPtr` as its
  aliases, `Ordering`, `fence` and `compiler_fence`. The intrinsics are
  lowered by name, as MVS's are (Z3.1). A `static` atomic works. A
  load with Release, or a store with Acquire, panics, where rustc
  rejects it at compile time.
- `std::env`: `vars_in(a)`, an iterator of `(String<A>, String<A>)`;
  `current_dir_in(a)`, a `String<A>`, since std2 has no PathBuf yet;
  `set_current_dir`. The target's `environ` is in `std::__sys`.
- char is PartialEq, Eq, PartialOrd, Ord, Hash and Default; `()` is
  PartialEq, Eq, PartialOrd and Ord. Through `#[array_builtin]`,
  `[T; N]` is Clone, PartialEq, Eq, PartialOrd, Ord, Hash and Debug,
  and `&[T; N]` and `&mut [T; N]` are IntoIterator (`for x in &arr`,
  `derive(Clone)` on a struct with an array field). An array's Hash
  waits for FL10, as a slice's does. `&[u8]`'s `read_exact` leaves buf untouched at
  the end, as Rust's does. Fixed std2 bodies: Drain's and Cycle's
  `size_hint`, and Range's `size_hint`, now `A::steps_between`.
- rewrite.tsv gains 55 rows for the translator: MVS's math functions
  become methods, the unicode code-point tests become char's,
  `f64_to_bits` becomes `to_bits`, `parse_int` and `parse_f64` become
  `str::parse`, and the env items.
- std2's cases at -O0 and -O2 under `--check-alloc`: 1,361 of 1,468
  pass (1,309 of 1,454 in 0.27.2.1, with the other streams' merged
  fixes counted). There are 15 new cases, each agreeing with rustc
  (tools/std2-twin.sh), and 10 XFAIL cases now pass on std2's fixes. The 107 XFAIL cases left, by
  what they wait for: inference from a later statement or the expected
  type (FL1, 0.27.4) 48; arrays' by-value IntoIterator, which needs
  const generics or a ManuallyDrop (a union's field is dropped today)
  27; the integer literal's type from its use (FL6) 12; `[T]`/`&[T]`
  and the view receivers (FL10) 11; `format_args` 4; `write(w, ..)` on
  an io::Write 1; and 4 front singles: an empty enum's match, a
  supertrait default through a bound, Cloned's DoubleEndedIterator
  bound, and an Index bound on a type parameter. None waits for a
  std2 body.

The front's views, contracts and borrowck singles (front273b):

- Z9.1's second part, stage 1 (front-rust.md Z9.1b, FL10): in the rust
  edition `&mut X` of a reference-written view (`&mut &[u8]`, `&mut
  &str`), of Self in an impl for `&[T]` or `&str`, and of a Sized type
  parameter is a pointer to the view, not the exclusive view; `?Sized`
  is recorded on the parameter. 23 std2 cases pass (io's `Read for
  &[u8]`, patterns). Stage 2, `[T]` its own type (Z9.1c), is specified.
- A `requires` call's implicit `&mut` receiver of a view (a temporary
  `&mut` receiver) is bound exclusive (T3), not checked as a shared
  borrow.
- A trait default body's `requires` and `ensures` clauses are written
  into each impl that uses the default (C7.6), as a declaration's are.
- The borrow checker reads a substitution's impl bounds (borrowck.md
  L14): an equality bound through a supertrait, an Fn bound's
  signature, recursively and through blanket impls. 10 std2 cases pass.
- A `static mut` is unsafe to read or write in the rust edition
  (F19.6, rustc E0133).
- `write(w, ..)` on an io::Write goes through std2's IoFmt (F16.3).
- A struct's, enum's or trait's `where` predicate is no function's
  (F10.1): the parser made Flatten's a bound of the function before it,
  Cloned's `next_back`, so Cloned's DoubleEndedIterator now resolves.
- A rust-edition union drops none of its fields (F19.7); rustc's E0740
  for a field that needs a drop is FL12, a named divergence.
- Arrays' by-value IntoIterator (FL13): std2's `std::array::IntoIter<T,
  [T; N]>` over a `ManuallyDrop<[T; N]>` (a union), `#[array_builtin]`
  until const generics (0.29), where Rust has `IntoIter<T, N>`.
  `a.into_iter()` and `for x in a` move the elements out, by rustc's
  probe order (by value before `&[T; N]` and the slice); what is not
  yielded drops with the iterator. A pattern impl's trait defaults
  (F12.3) and its drop are found by its header. 24 std2 cases pass, and
  4 new rust cases twin with rustc (a partly consumed `[String; 3]`
  under `--check-alloc`, an early `break`).

Compile cost and the machine's load (cost273):

- **std2 is parsed lazily** (front/modules/std2lazy.vl). Its text is still
  lexed whole, then split into units: each item, each method of an inherent
  impl, and each default method of a trait (with its trait's header and
  required items). A build keeps only the units the program reaches by name:
  its own words, the known items and the names the compiler's lowerings and
  made code use; an item by its name, a trait by any of its items' names, a
  method once its type or trait is reached, a trait impl once both are. The
  rest is never parsed, derived, expanded (`#[builtin_impls]`) or collected.
  A lazy build with errors is made again with std2 whole, so its
  diagnostics are the whole std2's. Queries, `--std2-check` and
  `VOLE_STD2_EAGER=1` read std2 whole. The rust and std2 cases at -O0 give
  the same verdicts lazy and eager (2,095), and a sample's code is the same
  (85 of 85, after renumbering).
- **A lighter println**: on std2, `println("hello")` (`print`, `eprint`,
  `eprintln`) with a literal that has no hole is written as a format
  literal: its text through the Formatter's `write_str`, as Rust's. It no
  longer goes through str's Display and `Formatter::pad`, whose padding,
  char counting and UTF-8 encoding every hello world compiled.
- hello-rust from 371M instructions (3.76x its MVS row) to 231M (2.32x),
  `tests/compile_cost.sh`; std-rust from 729M to 637M; MVS's rows not
  dearer (hello 1.01x, std 1.00x, check 1.00x, rust 1.00x of 0.27.2.1).
  What is left over the 2.0x ceiling: std2 is still lexed whole, its builtin
  impls are made for every primitive, and its big modules are few units
  (0.27.4).
- The hooks' case "the check after the fixes timed out" gives the two real
  calls before it 8 s (scaled by the load up to 64 s), not 3 s: at 3 s
  (24 s under load) it failed in every suite row of 0.27.2.1's gate.

### What's new in 0.27.2.1

The rust edition grows toward Rust: 1,306 of std2's 1,454 tests pass at -O0 and -O2 under `--check-alloc` (1,035 of 1,413 in 0.27.2). `impl Trait` in return position (borrowck.md §21) and the opaque type-parameter instance (§22: an uncalled template's borrows are checked, and a parameter used beyond its bounds is `generic.unbounded_use`; its other type errors are 0.27.3's, FL11). The borrow checker takes rustc's implied outlives bounds (D4.6), and fixes three miscompiles of consumed values that 0.27.2 had: a collection consumed by value (`for x in v`, `extend`, `into_iter`), an arithmetic operator's by-value operands, and `(t, t)` not caught as a use after move (D8.5); a non-Copy element moved out of an array is E0508, and `write(f, .., f.width())` is a two-phase reborrow. The front fills std2's largest gaps (Extend and Borrow chosen by bounds and the expected type, literal temporaries typed by their annotation, traits in scope for methods, operators chosen by the right operand), with an impl-binding soundness fix (F14.2). std2 gains floats printed and parsed as Rust's, `std::env`, tuples' comparisons and Hash; contracts and effects R2 declare every std2 `pub` item's effects, with 27 `requires` and 11 `ensures`. A rust hello world's check costs 3.48x MVS's (4.38x in 0.27.2); the gate builds std2's tests half as often. MVS programs compile exactly as before. Built and tested on aarch64-macos only.

Not in 0.27.2.1, by name: the i32 literal default (FL6) and `[T]`/`&[T]` as distinct types (FL10), 0.27.3; inference from a later statement (FL1), 0.27.4; impl bounds read at a substitution (L14, 7 cases); arrays' by-value IntoIterator (const generics); a `requires` call on a temporary `&mut` receiver checked as a shared borrow.

The front's gaps behind std2's XFAILs (front2721b):

- A generic trait's impl is picked by an own type parameter's bound
  (`extend<I: IntoIterator<Item = T>>`: Extend<T> over Extend<&T>,
  F13.3), by the expected type (`let r: &i64 = w.borrow()`, F13.2) and,
  in an instance, by the receiver's type parameter bound (`s.as_ref()`
  with `S: AsRef<str>`, F13.4).
- Literals take their context: `let d: &[u8] = &[1, 2, 3]` is an array
  of u8 (F18.4), `s.get(1..3)` a `Range<usize>` (F18.3). Integer
  inference variables (a later statement's type) and the i32 fallback
  stay 0.27.3's (FL6).
- A template impl binds an instance's arguments by position only when
  its header names its parameters in order: `impl<T> SliceIndex<[T]> for
  Range<usize>` no longer covers `Range<i64>` (F14.2).
- A reference impl (`impl<A: PartialEq<B>, B> PartialEq<&B> for &A`)
  yields to a slice's own impl under Z9.1, so std2 can have Rust's
  reference impls; an ambiguity message for a pattern impl no longer
  reads past TLISTS (the crash at types.vl:608).
- `{:E}` is UpperExp, and `{:-}` sets Formatter's sign_minus.
- Deref coercion at an argument: `&Box<T, A>` where `&T` goes, and in a
  generic call through the Deref chain (`sum(rest)` binds A, F32.2).
- A bound's `Item = &T` through a supertrait binds T (`Copied<I>`'s
  DoubleEndedIterator impl, F11.5). Group 3's other `type.infer` cases
  (a later statement's type, a later match arm's) wait for FL1's deferred
  inference (0.27.4).

The front's smaller gaps (front2721c):

- A method call counts only the traits in scope: `self.v.fmt(f)` with
  only `Binary` imported is Binary's, not ambiguous with Display and
  Debug (F9.2).
- A trait default's own parameter, renamed where an impl has one of its
  name, is renamed in a path's head too: `B::from_iter_in(..)` in
  `collect_in` on a `Map`, `Zip` or `Enumerate` (F12.2).
- A struct's impl of a spec's trait writes the hole: `{:b}` with `impl
  Binary for W`, `{:x}`, `{:o}`, `{:e}` and `{:p}` likewise (F16.5).
- The primitives' builtin `Sum<&'a P>` and `Product<&'a P>`
  (`v.iter().sum()`, F15.1); char is Clone and Copy.
- std2's `Stdin::read_line` annotates its result, so the stdin cases run.
- An impl parameter fixed by a closure bound's result with arguments
  binds (`P: FnMut(I::Item) -> Option<B>`: MapWhile, Scan, FromFn, Fuse;
  F14.1), and a tuple of literals indexes as the impl's index type
  (`g[(0, 1)]` with `Index<(usize, usize)>`, F20.5).
- An operator's right operand of another type picks the impl for it:
  `s == "x"` for a String, `v == *slice`, a Vec against one on another
  allocator, `s + "bar"` (F26.3).
- `<T as Tr>::f(..)` in an expression, T a name: `<i32 as
  FromStr>::from_str("-7")` (F8.4).

The borrow checker (bc2721):

- Implied outlives bounds as rustc's well-formedness (borrowck.md
  D4.6): a struct's or enum's inferred outlives requirements (RFC 2093,
  `struct Iter<'a, T> { v: &'a [T] }` gives `T: 'a`), carried through
  nested fields; an elided lifetime of an impl's header (`impl Ord for
  str`) is the impl's own, the same at every `Self`; `&self` on an impl
  for `[T]` or `str`; `Self` of a trait's default method as a type
  parameter; a bound's `Item = T` and trait arguments
  (`B: FromIteratorIn<Self::Item, A>`) as equalities; a blanket impl's
  projection (`U::IntoIter` of an iterator); a substitution's own
  implied bounds (`&'m mut I` gives I's slots `: 'm`). 30 std2 tests and 3
  `rust_t_` cases that failed on `borrowck.outlives` or
  `borrowck.elision` now pass; `tests/std2/check.sh`'s known-gap XFAIL
  cases with borrowck errors in std2 fall from 45 to 9 (17 with
  std2's later tests: 14 a front
  gap: `&mut self` on an impl for a view type reads as `inout [u8]`;
  three Chain cases are L14, an impl's equality bound on a type
  argument). 11 `rust_b_implied_` cases, each agreeing with rustc.
- `for x in v` over a place moves v in the rust edition (D8.5): the
  loop's sequence owns it and `into_iter` takes it, where it was a
  borrowed copy, so v was dropped again after the iterator had freed it
  (a double free under `--check-alloc` for `for` over a Vec, a HashSet
  or a generic sequence, `extend`, `into_keys`, `into_values`,
  `flatten`). 9 cases that failed on it pass.
- Moves out of an index (D8.6, rustc E0508): an index of a non-Copy array
  or slice element is a place with no move path, a constant index too,
  so `let x = a[0]` is `borrowck.move_out`, named as "an element of an
  array (a slice) whose type is not Copy". A whole-array move, a borrow
  of an element, a Copy part or a Copy element's constant index stay
  allowed. By-value `for` over an array of non-Copy elements still
  reads them by reference (F22.1) until std2 has an array `IntoIter`.
- `write(w, ..)`'s writer is a two-phase reborrow, as Rust's `write!`
  receiver (D7.4): `write(f, "{}", f.width())` reads f while the
  reborrow is reserved, and f is usable after the call, where the
  desugaring moved f (`borrowck.use_moved`). 6 Formatter cases pass.
- An arithmetic operator moves its operands in the rust edition (D8.5):
  `a + b` is `Add::add(a, b)`, where the operands' bindings were
  borrowed copies, so an operand with a drop was dropped again at the
  end of its scope (a double free, already in 0.27.2); a comparison's
  stay borrowed. `rust_b_ops_` cases for `+`, `+=`, `==` and a use after
  the move.
- A statement's operands are read in order (D8.5): `(t, t)`, `[t, t]`
  and `S { a: t, b: t }` of a non-Copy t are a use after move (E0382),
  in generic bodies too, where the second move went unseen. 6
  `rust_b_moves_` cases.

std2 (std2721):

- Floats print and parse as Rust's (front-rust.md F15.6): std2's `flt`
  module finds a float's digits with big integers, the shortest that
  read back as the same float for `{}`, `{:?}` (with `.0`; the exponent
  form below 1e-4 and from 1e16) and `{:e}`, the exact value rounded
  half to even for `{:.N}` and `{:.Ne}`; `str::parse` rounds to the
  nearest float, subnormals included. f32 keeps its own shortest digits
  (`1.1f32` is `1.1`). The integers' `{:e}` is exact. Checked against
  rustc on the edge values (0.1, 1e21, 5e-324, NaN, -0.0, inf, f32's
  1.1 and MAX, the subnormal boundary); bool's FromStr too.
- `std::env`: `args()` and `args_os()` (views of argv, no allocator),
  `var_in`, `var_os_in`, the unsafe `set_var` and `remove_var`,
  `VarError`. argv is the target's: std2/rt/sys_macos.vl or
  sys_linux.vl, in `std::__sys` (the Linux file is built, not run).
  `vars_in` and the working directory are 0.27.3's.
- Tuples of 1 to 6 fields are `PartialEq`, `Eq`, `PartialOrd`, `Ord`
  and `Hash`; `std::hash::DefaultHasher`; `Debug` for `BufWriter`; the
  ExactSizeIterator lengths of chunks, windows, hash_map's iterators,
  `Empty` and `RepeatN`; char's Debug escapes combining marks.
- `write(w, ..)` stops at the first failed write and returns its error,
  as Rust's `write!` (a Formatter's failed write fails the later ones).
- The XFAIL std2 cases grouped by cause and owner; the cases that failed
  only on their own unused imports or test shapes are fixed.

Contracts and effects R2 (eff2721, docs/design/contracts-effects.md):

- A declared function's set is its signature (E3.1a): a rust-edition
  caller sees `#[effects(..)]`, not the body; the hidden bits the
  optimizer reads stay the body's. A list may name a type parameter
  (`#[effects(panic, T, A)]`, E3.3a): what the edges made for it do
  passes through, checked per instance; so does what a call through a
  fn value reaches (closed world), kept apart from the rest by the
  solve (`fixed ∪ dyn`, cycles split per member).
- Every std2 `pub` function and inherent method is declared: 626 of
  626 (`query items std --undeclared`), written by the new `volec fix
  --only effects` (`effects-std` prints std's lines, which
  tools/std2-effects.py writes into compiler/std2 as the union over
  the std2 cases).
- `global` is `static` (E1.2): left out of a set's display, shown by
  `--why static` and named so in messages (`touches a static mut or a
  C static`); `#[effects(global)]` and `--why global` stay as aliases.
- `Allocator::FREES` (E4.4a): `deallocate` of an allocator whose
  `FREES` is false (an arena, a scope, a FixedBuf, through `&A`) adds
  no `alloc(A)`: dropping a Vec on an arena is `#[no_alloc]`.
- A trait method's `requires`/`ensures` bind every impl in the program
  (C7.6), checked before the impl's own; `volec query contracts
  Tr::m` lists them and what each impl adds (`(trait)` marks a copy).
- std2's clauses: 27 `requires` (Vec's insert, remove, swap_remove,
  split_off; the slices' split_at, chunks, windows, swap,
  copy_from_slice...; String's char boundaries; Option's and Result's
  unwrap and expect; char::from_digit) and 11 `ensures` (Vec's push,
  pop, insert, remove, truncate, clear, reserve, with_capacity_in,
  `len() <= capacity()`; String's push and clear), each with a
  `std2_contract_*` case. A query in query mode no longer reaches ⊤
  through an error-typed instance's fn value.

Compile cost and the machine's load (cost2721):

- hello-rust from 4.38x its MVS row to 3.35x (`tests/compile_cost.sh`,
  434M to 327M instructions); MVS's rows are not dearer: hello 0.99x,
  std 0.99x, check 0.91x, rust 0.97x of 0.27.2. std2's declaration
  tables are walked by key, not scanned whole: the lifetimes by node,
  the `where` predicates by owner, METHODS by type and name, the impls
  by trait. gm_key keeps a method's name in the bits HMap hashes.
  std2's impls are not checked against their traits in every compile;
  the gate's `--std2-check` row checks them whole.
- What is left of hello-rust's cost over MVS's is structural: std2 is
  lexed and parsed whole (+47M), its 489 builtin impls are made and
  parsed (33M), and its println costs the back end +40M. A pass that
  left out the impls of traits nothing reaches was measured and dropped:
  println reaches nearly every trait, and the pass cost more than the 95
  impls it left out. 0.27.3 takes lazy std2 parsing, in sections as MVS's
  std is read, with a lighter std2 println.
- The gate builds std2's cases three times, not six. The std2-tests row
  reads its counts from the suite rows' case results ($VOLE_TEST_RESULTS),
  and std2-check compiles only the cases suite-O0 did not pass (283 of
  1,413), with the same tally.
- The check hook reports its rewrites when the check after them times
  out, and its compiler runs' limits grow with the load average (at most
  8 times): the hooks test "the hook's rewrites, each a changed line"
  failed under the gate's load.
- The stress-grow row's one-time segfault (arch_x86_sse3.vl at -O0 for
  x86_64-macos) did not recur in 42,400 compilations under load.

The front (front2721):

- `impl Trait` in return position (docs/design/borrowck.md §21): `fn f(..) -> impl Tr + ..` at the top of a free function's or an inherent method's result is an opaque type, one per function and instance (`front/opaque.vl`). Its hidden type is the body's type: every `return` and the tail must be that one type (`opaque.mismatch`), and it must meet each bound. A closure leaves its function by `-> impl Fn*(..)`, its parameters typed by the bound. The caller sees only the bounds' methods (rustc E0599 for any other), the bounds' traits and the blanket impls they entail. The type is `Copy` only when a bound says so, it converts to nothing, and `Send`/`Sync` leak from the hidden type. A caller checked before the function gets the function's body checked first. A hidden type that holds the result itself is `opaque.cycle` (E0720). `Option<impl Tr>`, a trait method's `-> impl Tr` and `let x: impl Tr` are `edition.later: impl_trait_nested (0.29)`.
- Regions of an `impl Trait` result follow Rust 2024: every input lifetime is captured. While the result is live, every argument's loan is too. Each slot of the hidden type is one of the inputs or `'static`, and a slot that holds loans of two unrelated inputs is `opaque.ambiguous` (rustc E0700). 24 `rust_b_rpit_*` cases, checked against rustc 2024 by `tools/borrowck-twin.sh`, which now reads a case's `// RUSTC-EDITION: 2024`. `volec explain opaque.mismatch|opaque.ambiguous|opaque.cycle`.
- `&T: Copy` on std2: a `T: Copy` bound holds for a shared reference (it failed for `&u8`).
- Generic bodies are checked by Rust's bound-only rule even when nothing calls them (borrowck.md §22, U1). Each generic function and generic impl method of a rust program's own files gets an *opaque instance*: every type parameter becomes an opaque type `Ω` that has only its bounds. A bound's method is a *virtual function*, its trait's signature with `Self := Ω`, which has no body and is never generated. `I::Item` is the bound's `Item = X`, or another `Ω`. The instance is type-checked and borrow-checked, never lowered. A method no bound gives is `generic.unbounded_use` (rustc E0599), even in a template with no caller, and a move or a borrow error there is reported too. An error a concrete instance already reported at the same position is not repeated, and no instance is named. std2's own templates are left to `--std2-check`. Other type errors in an opaque instance (operators through an `Add` or `PartialEq` bound, a bound's type arguments, `T::f()`, `where` on a projection) leave it out unreported until 0.27.3 (front-rust.md FL11). `--emit-places=regions` prints `opaque: N templates`. 13 `rust_b_opaque_*` cases. hello-rust's cost: +1%.
- Z9.1's first part: `size_of_val` of a slice is its length times the element's size, of a str its length (0.27.2 gave the view's 16 bytes). `size_of::<[u8]>()` and `size_of::<str>()` are `type.unsized` (E0277). The rest, `[T]` apart from `&[T]` (with `Box<[u8]>` at 16 bytes and `impl Read for &[u8]`), is 0.27.3's (front-rust.md FL10).

### What's new in 0.27.2

The rust edition's std is std2, Rust's std with explicit allocators: a rust-edition program now reads `std::vec::Vec`, `String`, `HashMap`, the iterator adapters, `fmt`, `io` and `thread` as Rust's, and 1,032 of std2's 1,413 tests pass at -O0 and -O2 under `--check-alloc` (gate 1). The front end fills the gaps std2's bodies hit (pattern and blanket impls, coherence, deref coercion, ranges, format specs; the rules are docs/design/front-rust.md). Closures are checked in full: their kinds, captures and signatures, `Send` and `Sync`, and the borrow checker reads their bodies (`borrowck.unchecked` is gone), with Rust's mutability errors E0594 and E0596. `[T]` and `str` are unsized types; their full representation, `impl Trait` in return position and the rest of std2 are 0.27.2.1's. MVS programs compile exactly as before; a rust hello-world's `check` costs about 4.2x MVS's (printed, not enforced; 2.0x is 0.27.4's target). Built and tested on aarch64-macos only.

The front (front272):

- `docs/design/front-rust.md`: the typing rules of the rust edition's
  front end with stable ids (F0.1 .. F32.1, Z1 .. Z9's front side, the
  bound-only rule D22.3), each anchored to the front item it changes;
  the codes with their rustc twins; the divergences from rustc (FR1 ..
  FR3, FL1 .. FL8); a map from every gap std2's bodies hit to its rule.
- Pattern impls (F4.1, F5.1, F6.1, F13.1, F14.1): an impl whose header
  is any type pattern, a blanket `impl<T: Tr> U for T`, one on an
  instance `impl<'a, T> Option<&'a T>`, for a reference `impl<'a, T>
  IntoIterator for &'a mut [T]`, or with a parameter only the trait's
  arguments fix `impl<T> SliceIndex<[T]> for usize`, is matched by a
  strict unifier that binds its parameters; its methods are found for
  the receiver's own type first, as Rust's probe does; `Self::A` inside
  an impl is that impl's own associated type, and a blanket impl's
  definition yields to a direct impl's.
- Supertraits (F2): `trait A: B + C`; a `T: A` bound gives T the
  supertraits' functions; an impl of A is checked to implement them
  (`error trait.unmet`).
- `where` predicates on any subject (F10, F21.3): `where Self:
  DoubleEndedIterator` on a trait method, `where I::Item: Clone` on a
  function, checked with the instance's parameters, or at the call for
  a method of one type, which is not the type's when they fail.
- A generic trait's default bodies (F12): `fn ne(&self, o: &Rhs) ->
  bool { !self.eq(o) }`, copied into each impl with the trait's
  arguments substituted; two traits' methods of one name on one type
  (F9.1); `Tr::m(x, args)` as the method call `x.m(args)` (F8.2).
- Coherence (F4.2, F9.3, F14.1): two impls of one trait whose headers
  unify and whose bounds can both hold are `error trait.overlap`; a
  method call that two traits' methods answer, with no inherent one,
  is `error method.ambiguous` with a `Tr::m(&x)` per trait; an impl
  parameter nothing fixes is `error trait.unconstrained`; a generic
  impl's supertraits and associated types' bounds are checked with its
  parameters as declared.
- Types (F1, F3, F5, F7): `char`, a Unicode scalar (`'é' as u32`, `u8
  as char`, `impl char { const MAX }`; other casts are `error
  type.cast`); tuple structs `struct P(i64, i64)` with `p.0` and the
  constructor `P(1, 2)`; unit structs `struct U;` as values;
  `Self(..)` and `Self` in an impl; several inherent impls of one type
  (`error impl.duplicate` on a clash).
- Patterns (F27): `let S { a, b: q, ref c, .. } = s;`, `S(x, y)`,
  `Self { .. }` and a unit struct's name, in `let` and `match`, checked
  for exhaustiveness field by field; a struct pattern on a place moves
  only what it binds.
- The primitives' impls (F15): `#[builtin_impls(i64, ..)]` on a std2
  trait makes its impls for the listed primitives.
- Smaller (F6.2, F8, F18, F19, F21, F23, F26): `<T as Tr>::A` in type
  position; the probe's `&` and `&mut` steps (`s.tag()` finding `impl
  Tag for &S`); a generic call's parameter bound from the expected type,
  else `error type.infer`; `_` in a turbofish; `use a::{self}`; `unsafe
  fn` types; `size_of::<T>()`; `b'x'` byte literals; `!x` bitwise on an
  integer; `[T]` and `str` by value are `error type.unsized`.
- Corpus: `tests/run/rust_f_*`, one case per rule, positive and
  negative. std2's root check: edition.later 254 -> 123 after the traits,
  -> 7 after the types (5 of them `auto_trait`).
- On std2 (front272, M3's rest): the integers' inherent methods
  (`wrapping_add`, `checked_mul`, `overflowing_sub`, `saturating_sub`,
  the bit counts and rotations) are the compiler's, from its list
  (F15.4, `#[builtin_methods]` in std2's `num::wrapping`);
  `size_of::<T>()` is a `usize`; fat raw pointers, `*const [T]` and
  `*mut str`, keep both words through casts and `&*p` (Z9.3); a raw
  pointer is not indexed, `*p.add(i)` and `slice::from_raw_parts`
  instead (F30.3, rustc E0608), with Rust's raw-pointer methods in
  std2; `for` is `IntoIterator::into_iter` and `Iterator::next` (F22.1);
  `alloc.field` does not look through a raw pointer (F33.1); an impl
  whose parameters its self type does not all fix (`impl<T:
  PartialEq<U>, U> PartialEq<[U]> for [T]`) is bound by unification,
  not by position.
- `&mut str` keeps its mutability (F0.1): a `&mut self` method of str
  on a `&str` is `own.readonly` (rustc E0596) and a `&str` where a
  `&mut str` goes a mismatch (E0308), where both were accepted; a
  `&mut str` coerces to `&str`, `&mut s` of a String to `&mut str`, and
  a String's `&mut self` str methods go through `as_mut_str`.
- `Vec<&str>` and `Vec<&[T]>` on std2 hold their views: a `*const T`
  with T a view stays thin; only a pointee written `[T]` or `str` makes
  a fat raw pointer (Z9.3).
- `for x in s` with `s: &mut [T]` iterates with IterMut (`impl
  IntoIterator for &'a mut [T]`), so `*x += 1` writes the element; a
  `&mut T` whose T is a `&mut [T]` is a reference to it, not the view
  (`mem::replace(&mut self.v, ..)` in IterMut::next).
- Operators through std2's ops traits (F26): `==`/`!=` are
  `PartialEq::eq`/`ne` (not structural), `<` and the rest
  `PartialOrd::lt`.. (not `Ord::cmp`), `%`, `& | ^`, `<< >>` (with an
  Rhs the literal takes, `v << 2` for `Shl<u32>`) and every `op=` form
  (`AddAssign::add_assign(&mut a, b)`) on a type with the impl; on a
  type parameter's value the bound must give the operator:
  `generic.unbounded_use` (rustc E0369) with the bound to add.
- Deref to a slice (F20): a Vec has its slice's methods (`v.iter()`,
  `v.last()`, `v.contains(&x)`, `v.reverse()` through `deref_mut`, so
  the borrow checker sees the `&mut v`). `&a` of an array or a Vec where
  `&[T]` is expected is the slice, and `&[]`, `&[4, 5]` take the
  expected element type (Z9.2). `s.get(0)` and `first`/`last` work: an
  unsuffixed literal for a parameter whose bound only usize meets is a
  usize; an impl parameter only the trait's arguments fix (`impl<T>
  SliceIndex<[T]> for usize`) is taken from the bound's (F14.1); `I::Output`
  under `I: SliceIndex<[T]>` is SliceIndex's, not Add's (F11.3).
- The tools' cache is keyed by which std a rust program reads
  (VOLE_STD2=0 or std2), so a check no longer restores the other's
  errors.
- Gate 1: std2's 1,413 cases, built with --check-alloc, pass 1,032 at
  -O0 and -O2 (552 when the round began). The fixes, with their rules:
  - Range literals are std2's ops types (`a..b` a `Range`, `..=b` a
    `RangeToInclusive`, `..` a `RangeFull`; Z3.1).
  - `write(w, "..")` and `writeln`. A hole's spec works on std2
    (width, fill, alignment, precision, `+`, `#`, `0`), and so do
    `{:#?}`, char's Display and Debug, and `{:?}` of an array as its
    slice (F16).
  - Deref coercion through several references, `&&&str` as a `&str`
    (F32.1).
  - `&mut F` is FnMut and FnOnce when F is FnMut, so std2's Map
    adapter works (F33.1).
  - A trait default's own parameter named as one of the impl's is
    renamed in its copy: fold's B inside `impl<B, I, F> Iterator for
    Map<I, F>` (F12.2).
  - An impl's free parameter comes from its bounds' constraints and
    from a closure's result (F14.1).
  - `Tr::m(&r, ..)` keeps Tr through a reference (F8.2).
  - A trait method's own generics see the trait's parameters.
- Z4.1: on std2, `edition.std_copy` and `edition.std_by_value` are not
  raised. `*s` of a shared view reads the view; `*x` of a value is
  rustc's E0614 and `&x` where a value goes is E0308. The two codes
  remain only with VOLE_STD2=0.
- A user program's check shows no std errors from templates it never
  instantiates (they stay visible with `--std2-check`). The derives
  write the item's lifetimes (F17).
- Known gaps: F18.3's `i32` default for an unsuffixed literal (the
  edition still falls back to `i64`; it needs integer inference
  variables). Z9.1's unsized representation (`&mut &[u8]` reads as
  `&mut [u8]`). An array's by-value `into_iter` (it needs const
  generics). `for x in arr` over non-Copy elements reads them by
  reference, until moves out of an index are tracked.
- The gate's std2-check row fails on a borrowck error in a std2 body or
  in a passing case's std2 instances; it prints as known gaps the
  6 bodies whose region-free instance does not type-check and the 45
  XFAIL cases whose std2 instances need rustc's implied outlives bounds
  (`&'a T` giving `T: 'a`; 0.27.2.1).

The front's side stream (front272b):

- `unsafe fn` types carry their unsafety (F19.3): in the rust edition an
  `unsafe fn` (or a C function) named as a value has the type `unsafe
  fn(..)` without `unsafe` around it, a call through one outside an
  `unsafe` block is `error unsafe` (rustc E0133), and a safe fn coerces
  to the unsafe type, not the reverse (E0308). The fn type's ABI bit is
  as before.
- Arrays as a template over their length (F15.3): `#[array_builtin(N)]`
  on an impl, a function or a method makes it an item over `[T; N]`,
  instantiated for each length the program uses (`impl<T: Clone>
  Clone for [T; N]`, `Vec::from_in([1, 2, 3], gpa)`), with N a `usize`
  constant inside it; std2's root check has no `edition.later` left.
- M2's gaps: a character literal is no longer accepted where a `u32`
  goes (`error distinct.mix`, rustc E0308; `'a' as u32` converts, and
  a `char` pattern still matches by scalar); the probe's autoref is one
  `&`, so a `&self` method of an `impl Tr for &S` is not found on an
  `S` (rustc E0599); an inherent constant of a generic impl (`impl<T>
  W<T> { const N: .. }`) is read, `W::<i64>::N` and `Self::N`, its
  type and value with the impl's parameters bound.
- The method probe is rustc's (F0.5, F6.2): at each autoderef step the
  receiver by value, then `&`, then `&mut`, and at each the methods whose
  receiver type is that type, inherent first. So `r.tag()` on `r: &S`
  is `S::tag(&self)`, not an `impl Tag for &S`'s `tag(&self)` (0.27.2's
  earlier answer), `s.c()` takes an `&S` impl's `c(self)` before S's
  `c(&mut self)`, and two traits' methods at one step are `error
  method.ambiguous` (rustc E0034).

Closures in full (clos272):

- A rust-edition closure has a kind, `Fn`, `FnMut` or `FnOnce`
  (docs/design/borrowck.md §19, D19.3): the expected bound's, or else
  inferred from its body. A closure that moves a capture captures it by
  value, `move` or not (D19.2), and is `FnOnce`: its call moves it, so a
  second call is `borrowck.use_moved`. A capture that is only read is
  borrowed, a `Copy` one too.
- The closure's environment is `&Env`, `&mut Env` or `Env` by its kind
  (D19.4), in both code generators, so its body is checked like any
  other: `borrowck.unchecked` fires on no body. Moving a capture out of an
  `Fn`/`FnMut` closure is `borrowck.move_out` ("a captured variable in an
  `FnMut` closure", rustc E0507).
- `FnOnce` bounds; `closure.kind` (rustc E0525) for an `FnOnce` closure
  where `Fn` or `FnMut` is asked. A closure with no `&mut` capture and
  `Copy` captures is `Copy` (D19.7).
- Reslicing a slice local, `v = &v[a..]`, is accepted (rustc accepts):
  the slice's loan is of what `v` points to, which the assignment kills
  (D1.4, Z9.5).
- Late-bound regions on the closure's side (§20, D19.10): a closure's
  type carries the regions of its signature that come from outside it
  (`X_C`), and what its body stores into or returns from its captures
  is checked where the closure is made (its requirements, rustc's
  closure region requirements). So `|| x` and `|| { h.p = r; }` are
  accepted and keep what they borrow borrowed (0.27.1: false
  `borrowck.elision`, `borrowck.outlives`), and `f()`'s result keeps
  the loan its closure's capture holds.
- A closure's `&` parameter is the call's (a bound region, D20.3):
  storing it into a capture is `borrowck.outlives` with rustc E0521's
  words ("borrowed data escapes outside of closure"), returning it from
  `|p: &i64| p` too (0.27.1 accepted it); the bound `Fn(&T) -> &T`
  makes `|p| p` the identity. A parameter written with another type
  than the bound's is `closure.sig` (rustc E0631). A reference into an
  `FnMut` closure's environment cannot escape a call.
- 0.14's escape check is off in the rust edition (D19.8): a closure
  leaving the scope of what it borrows is the borrow checker's
  `borrowck.dropped_borrowed`, and a `move` closure of owned values
  leaves freely. `borrowck.unchecked` is retired, and the test runner no
  longer passes `--allow=borrowck.unchecked`.
- An `Fn`/`FnMut` closure called through an `FnOnce`-bound parameter is
  moved by the call and dropped after it (D19.5). `borrowck.outlives`
  names its two lifetimes in the right order ("'b must outlive 'a").
- 42 `rust_b_clos_` cases, all agreeing with rustc but one marked R3.
- A `let` type annotation's lifetimes are constraints, as rustc's user
  type annotations: `let r: &'static i64 = &v;` of a local `v` is
  `borrowck.dropped_borrowed` (rustc E0597); 0.27.1 accepted it.
- A call through a `fn` value ties its result to its arguments (E1-E2
  over the `fn` type): 0.27.1 made no constraint there, so a result
  could outlive what it borrowed (R6). Its arguments are tied to each
  other too, and to the result, under a `&mut`: `fn store<'a>(x: &mut
  &'a i64, y: &'a i64)` called as a `fn(&mut &i64, &i64)` value no longer
  stores a `y` that dies first into `*x` unseen; the erased type's
  lifetimes are one region there, stricter than rustc (L13).
- `Send` and `Sync` are the rust edition's (borrowck.md AT1-AT3):
  compiler-known auto traits decided by a type's parts, Rust's rules
  (`&T` by `T: Sync`, raw pointers neither, `Cell` never Sync, a
  closure by its captures, `fn` pointers both); `unsafe impl Send for
  X {}` and the new `impl !Send for X {}` vouch for a type; a bound `T:
  Send` that fails is `sync.not_send` (`sync.not_sync`), naming the
  chain to the part that fails. 0.27.1 reported `edition.later`.
- A move through a pattern's binding (`let (a, n) = t;`, then `t.0`)
  gets `try: ... 'let (ref a, n) = t;'`, a borrow of the part, where it
  got `.clone()` inside the pattern, which does not parse.
- `--print-effects` leaves out the drop shims, which it printed as
  `(unknown)` (K-I7: nothing targets them, so nothing was masked).
- `thread::scope` is std2's signatures and the borrow checker (AT6):
  a thread may borrow from the caller and change what it borrows
  mutably when that is Send; borrowing a local of the scope's closure
  is `borrowck.dropped_borrowed` (rustc E0373), changing in the body
  what a thread borrows is a conflict, two threads writing one value
  `mut_twice`, a handle leaving the scope `outlives`. 0.21's
  `sync.scope_*` checks stay for MVS programs only; the shared-static
  rule stays for both. A declared `T: 'a` and a struct's declared
  `'b: 'a` are now constraints (D4.5): the parser kept neither.
- std2 states its Send and Sync as Rust's (AT2): `unsafe impl` vouches
  for Vec, Box, the iterators and drains, the hash table, the join
  handles; `impl !Sync` for Cell and the arenas (`&Arena` is neither).
  threads.vl's list of std names is MVS std's only.
- A closure that writes through a captured `&mut` binding not declared
  `mut` captures it uniquely (rustc's unique borrow): a shared use of
  it while the closure lives is `borrowck.conflict` (E0501).
- A fat raw pointer (`*const [T]`, `*mut str`) has no region of its own
  (Z9): `fn f(p: *const [u8], r: &T) -> &T` elides as Rust's. A
  closure captures a `&[T]` or `&str` variable by reference (R12's copy
  is gone; Rust 2021 copies it, L7).
- A shallow write or a scope's end does not conflict with a loan past a
  deref beyond a field (`h = H { r: &mut y }` while `*h.r` is borrowed,
  rustc accepts; D2.5 amended), and `borrowck.dropped_borrowed` points
  at the borrow, as rustc's E0597 and E0713, naming where the value is
  dropped.
- The rustc twin runs `--std2` in tests/affected.sh and the gate: 325
  `rust_b_` cases, 293 agreeing, 9 named divergences, 0 mismatches.
- borrowck's messages name a place as rustc's do: `s.n` through a
  reference, `*s` for a receiver's autoref, `v[_]` for an index, a
  closure's capture as the captured variable (`b.n`, `a.v`), where they
  printed the IR's `s ((*_1).0)`.
- `println("{}", r)` with `r: &mut T` reborrows r shared (rustc's
  format_args takes `&r`; the IR copied a `&mut`, I7), and an argument
  that is a value, `println("{}", String::from_in("abc", gpa))`, is
  dropped at the end of the statement (it leaked).
- A closure or a fn pointer is called through `&F` or `&mut F`
  (`compare(a, b)` with `compare: &mut F`, std2's sort and select); an
  `FnMut` called through `&F` is `borrowck.borrow_immutable` (E0596).
- A closure checked against a bound that names a projection, `F:
  FnMut(B, Self::Item) -> B`, gets the projection's regions from the
  instance (D20.3): std2's `Iterator::last`, `min_by` and `fold` under
  `reduce` check clean.
- The borrow checker's verdict cache (Z7): a std body's clean verdict
  is kept in the tools' cache directory (target/volec-cache,
  `$VOLE_CACHE`), keyed by D4.4(b)'s key, the compiler and std's text,
  and a later run does not solve it again (tests/std2/cache.sh).
- `tests/run.sh` picks the cases it gives `--verify-places` by their
  file name, not their path: every worktree and the gate verify the
  same ones.

std2's tests under `--check-alloc` (std272b):

- `--check-alloc` works on std2 (Z5): Gpa's implementation is the
  compiler's tail, `std::__gpa` (compiler/std2/rt/), C's malloc or, with
  the flag, MVS's checking allocator in std2's spellings: every block on
  pages of its own, a double, invalid or wrong-size free and a use after
  free stop the program with exit 101 naming where the block was
  allocated and freed, `Gpa::live_blocks`/`check_leaks` count and list
  the live blocks, and the ones left at exit are listed as MVS lists
  them (`check-alloc: N blocks of Gpa not freed`); a program's
  allocating calls store their sites as in MVS.
- The runner builds every `std2_` case with `--check-alloc` and fails
  one whose blocks are left at exit (a panicking one, or one whose
  STDERR expects the list, excepted); the gate's `std2-tests` row runs
  them at -O0 and -O2 and prints the count against gate 1's 1,000.

The rust corpus and the compile cost (mig272, lazy272):

- Every rust-edition case runs on std2: about 370 cases moved off
  `VOLE_STD2=0`, which remains only for the guide's runner and two
  cost and transcript rows. The editor hooks read a case's edition, so
  a rust case is no longer checked, or rewritten, as MVS.
- std2's declarations are checked lazily by name: trait defaults and
  integer methods are instantiated when used, the generic methods are
  indexed by template and name, and the variance table is built per
  instance. A rust hello-world's check went from 887M to 414M
  instructions; the compile-cost rows print hello-rust and std-rust.
- An inherent method that shares its name with a trait impl's method
  gets the symbol `T.m.n1`, not `T.m.-1`, which the system assembler
  rejected (x86_64-macos objcheck on std2's Formatter::write_str).

### What's new in 0.27.1

The rust edition's borrows are checked: NLL on the places IR, as rustc's, with the semantics written down as rules (docs/design/borrowck.md) and checked against rustc on 193 programs (0 disagreements but the named ones). A rust-edition program now gets Rust's errors for conflicting borrows, references that outlive what they borrow, use after a move, assignment twice and drop order, each with `explain`; closure bodies' inner borrows wait for 0.27.2 (`borrowck.unchecked` names them). Rust's `Copy` rule, reborrows, captures as loans and deferred `let x;` come with it. It fixes 0.27.0's -O2 miscompile of aliasing references in unchecked rust-edition code. MVS programs compile exactly as before. Built and tested on aarch64-macos only.

The borrow checker (bc271):

- `docs/design/borrowck.md`: the semantics as definitions and rules with
  stable ids (D1.1 .. D17.7, M1 .. M6, I1 .. I7, R1 .. R11, L1 .. L8),
  each anchored to the IR construct it reads; the decisions (per-instance
  checking with a dedupe key, the container table, Rust's capture
  modes, both positions); the divergences from rustc, more permissive
  (raw pointers, MVS std's hidden views, per-instance checking, closure
  bodies, constant indexes, `Copy` MVS std types) and stricter (dropck
  without `may_dangle`, no rvalue promotion, vole's temporaries, NLL
  only, whole-variable captures, a guard that moves the scrutinee); the
  contracts' rules (the shared context, `old`, the disjoint-parameters
  axiom, the optimizer's gate); the regions dump's grammar.
- `compiler/src/places/borrowck/`: liveness (use- and drop-liveness per
  point), the constraints (subtyping by variance over a place's region
  slots, the supporting prefixes of a borrow, a `&mut` passed on read as
  a reborrow, a call's regions from the callee's signature, `return`
  against the signature's), the solve (bitsets, a worklist, the
  universals fixed by the signature's order), the loans in scope and
  every access checked in order against the conflict table (two-phase
  receivers, kills, the code by the loan's kind), the universal
  violations, the moves on the IR (elaboration's paths and dataflows
  re-run: use after move, in a loop, a partial move, a move out of a
  reference, an index, a static, a value with `impl Drop`), dropck with
  the container table, the per-instance dedupe, the verdict per body
  that gates the optimizer's parameter alias facts and the code cache's
  key; `volec check --emit-places=regions`, the `borrowck` row of
  `--time-passes`; 18 codes with `explain`.
- The own pass's move findings and `own.drop_view` are off for a
  rust-edition position: the IR reports them. A rust-edition body gets
  the optimizer's reference-parameter facts only with a clean verdict
  (0.27.0 miscompiled `f(&mut x, &mut x)` at -O2 with them on).
- Known holes, each counted: closure bodies through the raw env
  (`warning borrowck.unchecked`, one per closure body: 106 in 32 of the
  284 rust_ cases, every one a closure body; the runner's
  `--allow=borrowck.unchecked` for rust-edition cases stays until 0.27.2
  types the environment), MVS std's hidden views (0.27.2 with std2), a
  by-`&` capture of a shared view copied until Z9 (R12). The budget:
  borrowck 4.4 ms against typeck 339.4 ms over the corpus (0.013, the
  bound 0.25; the largest case 0.065); compiler/src (MVS) gets no
  `borrowck` row.

The borrow checker's corpus and its rustc twin (corpus271):

- `tests/run/rust_b_ok_*.vl` and `tests/run/rust_b_err_*.vl`: 76
  programs the checker accepts and 113 it rejects, written from the
  spec's rule ids (each case's `// RULE: Dn.m`): the conflict table cell
  by cell, kills and reassigned references, reborrows through `&`,
  `&mut` and raw pointers, two-phase borrows, returns and elision,
  structs with lifetimes and variance, dropck and the container table,
  moves, closures' captures, MVS std's bridge, calls with the callee's
  regions, views, match guards' fake borrows, statics and contracts. A
  rejected case names the code, its position and the error count; until
  the checker's milestone that reports it lands, it is `XFAIL` with the
  milestone named.
- `tools/borrowck-twin.sh CASE...`: rustc as the oracle of accept and
  reject. Each case, its directives blanked and `println(` spelled
  `println!(`, is compiled by rustc; its verdict and its first error's
  code (mapped by the spec's table of codes) must be the case's, unless
  the case names the divergence's class (`// RUSTC: accepts|rejects
  CLASS`, from the spec's R1-R10 and L1-L8) or is outside the common
  subset (`// RUSTC: none`: MVS std's `Vec` takes an allocator,
  contracts are not Rust). The gate's `borrowck-twin` row runs it on
  every `rust_b_` case (a SKIP without rustc).
- `tests/borrowck-try/`: a case per code with a `try:` line, run by the
  own pass's try-test runner (`tests/own-try/run.sh -d DIR`, `// CODE:`).
- `tools/borrowck-budget.sh`: the `borrowck` pass's time over the rust
  corpus against typeck's, and their ratio (at most 0.25);
  `tests/compile_cost.sh`'s fourth row, `rust`, the check of the
  corpus's biggest case against the previous release (at most 1.5x).
- `rust_b_err_alias_params`: the program 0.27.0 miscompiled at -O2 (two
  `&mut` of one place to one call, and `&v, &mut v`: the parameters'
  alias facts taken for a body nobody checked), now `mut_twice` and
  `conflict`; `tests/same_output.sh`: every running `rust_t_`/`rust_b_ok_`
  case prints the same at -O0, at -O2 and at -O2 with `--no-noalias`.
- `rust_t_contract_*`: contracts in the rust edition, one case per rule
  of the contracts design's C3, C5 and C7.1 (a clause reads `&mut`
  parameters as `&`, `old(e)` only of a `Copy` value without regions, an
  impl's added `requires` checked per instance).
- `tools/checks-survey.sh`: `--print-checks` over bench/ and the
  examples at -O2, the checks left and removed (by ranges or otherwise),
  in user code and in std, by kind: the first survey since 0.18.1's.

The places IR carries what the borrow checker reads (ir271):

- Region slots for every type (docs/design/borrowck.md D3.3): a
  struct's and an enum's declared lifetimes and its type arguments', a
  closure's captures', a raw pointer's pointee's; each local gets a
  variable per slot, a parameter's are its signature's universals.
  `--verify-places` checks that every local and every place the body
  names has as many regions as its type has slots.
- Signatures read with their lifetimes (D4.1, D4.2): one universal per
  named lifetime (the impl's and the function's), `'static`, one per
  elided input region, one per slot of a type parameter's substitution
  shared by its occurrences; the elision rules E1-E3, and `error
  borrowck.elision` (E4, rustc E0106) at the signature; declared
  `'b: 'a` and the implied bounds of `&'a T`.
- A call gets one region per region of its callee's signature, its
  first in the call's region word (D3.2).
- The variance of every struct's and enum's parameters (D5.3), and
  `error borrowck.unused_param` for one no field uses (rustc E0392).
- The regions dump of `--emit-places` in the format of borrowck.md §16:
  `region 'r2: universal 'a (_1.0, return.0)`, `local _3.1`, `call
  bb0[12].1`, `bound 'r3: 'r2`, and a `variance S: 'a +, T o` line per
  rust-edition type.
- `&&'a T` and `&&mut T` parse (the lexer's `&&`), and `&'a str` keeps
  its lifetime.
- R5 closed: a reference given where its value goes, or a place where a
  reference goes, to a rust-edition function or a `let`'s written type
  is `error edition.lenient` with Rust's spelling as its `try:`.
- Operands follow Rust's Copy rule (D8.3): a value moves unless its
  type is Copy (scalars, `&T`, raw pointers, shared views, arrays and
  tuples of Copy, a `#[derive(Copy)]` or `impl Copy` type), glue or
  not; `let s = *r;` and `let s = v[0];` of a type not Copy move that
  place (the checker's `move_out`); a place moved into a call is a
  statement of its own at the argument. A derive's code keeps MVS's
  rules.
- A `&mut` given to a call is reborrowed (D3.6): `&mut2 (*r)` for a
  `&mut` parameter, `&(*r)` for a `&T` one; `--verify-places` refuses a
  copy of a whole `&mut` (I7).
- A match with a guard fake-borrows its scrutinee and every place its
  patterns test (`&'r fake`, D2.6), mentioned at each arm; a `ref mut`
  binding is a shared borrow in the guard.
- A closure's by-reference captures are loans, `&'c x` and `&'c mut x`,
  held in the closure's type (D10.2); a call of a closure value
  reborrows it, `&'e` or `&'e mut2` for one that writes a capture
  (D10.3).
- `&raw mut` loans (`BK_RAW_MUT`) for a `&mut x` given as a `*mut T`;
  `where 'a: 'b` predicates; `error borrowck.static_mut_ref` for a
  reference to a `static mut` (D6.2.5); a check's decision slot on
  asserts and contract conjuncts, printed `; L1:`.
- `Vec<&i64, Gpa>` keeps its element a reference, and `volec test` lends
  a contract's `&T` and `&mut T` parameters a generated value.
- Contracts in the rust edition: a clause reads its parameters shared
  (C3: a `&mut T` or `&mut [T]` is `&T` in a `requires` and an
  `ensures`, so a write through it is refused); `old(e)` takes a Copy
  value with no reference and no raw pointer (C5), and contract.old is
  reported before the borrow checker runs; a clause that moves a
  parameter or `result` is `error contract.move` (C3.2).
- A closure captures what it reads by `&`, an immutable variable too
  (Rust's rule, D10.2); a `move` closure copies or moves.
- Deferred initialization: `let x: T;` and `let x;` (typed by its first
  assignment), assigned without `mut`; one never assigned is an error
  (rustc E0282).

### What's new in 0.27.0

The rust edition begins: `// EDITION: rust` (or `--edition rust`) compiles a program with Rust's references, `let mut`, `Deref`/`Index`, reference patterns and lifetimes, on today's std, without a borrow checker yet (`warning borrowck.unchecked`; NLL is 0.27.1). The new std's API is written in full as `compiler/std2`, the std rust-edition programs get in 0.27.2. MVS programs compile exactly as before. Built and tested on aarch64-macos only.

The rust edition's front (ed270):

- A program whose root file's first line is `// EDITION: rust` (or
  compiled with `--edition rust`) is read with Rust's meanings, by the
  same front: `&T` and `&mut T` as values, `&x`, `&mut x`, `*r`, `let
  mut`, receivers `&self`, `&mut self`, `self`; lifetimes in generics,
  types, bounds and `where` (kept, not checked); `*const T` and `*mut T`;
  quoted labels. MVS's `var`, `inout`, `sink` and `defer` are names there.
  Every MVS program compiles as before (the compile cost of an MVS check
  is 1.00x of 0.27.0's base).
- Type checking: std's new `Deref`, `DerefMut`, `Index` and `IndexMut`
  (std::ops) on a program's types; `for` over `&v`, `&mut v` or a slice
  yields `&T` (`&mut T`), over a Vec or an array the values; patterns
  `&x`, `&(a, b)`, `&Some(k)`, `ref` and `ref mut`, match ergonomics;
  `#[derive(Clone, Copy, PartialEq, ...)]`; `where Self: Sized`,
  `?Sized`; a trait's defaulted parameter left out of an impl header
  (`impl PartialEq for P`); `union` a name but before a name; `&f(x)` of
  a value a temporary of its statement, as Rust's (of the block for `let
  r = &f(x);`): a second one in a statement no longer an error; a trait's
  `&Self` in an impl for str or a slice is the view (`other: &str`).
- The edition runs on MVS's std in 0.27.0, and two places differ from
  Rust's std, each its own error: `edition.std_copy` (`*x` of a getter's
  copy) and `edition.std_by_value` (`&x` where std takes the value).
- `edition.later`: what the edition reads but 0.27.0 does not have is one
  soft error naming the feature and its release (char, FnOnce, `impl
  Trait` returns, tuple structs, supertraits, associated constants,
  blanket impls and impls on an instance, `#[array_builtin(N)]`, `let
  x;`, a write through `*const T`, qualified paths `<T as Tr>::X`, auto
  traits `Send` and `Sync`, `#[builtin_impls(..)]`, ...); the item it is
  in is left out. std2 checked (`--max-errors=0`): 254 edition.later, 98
  plain errors left, of which 61 are two traits' methods of one name on a
  type (`fmt` of Display and Debug: method_name_clash, 0.27.2).
- Fixed for MVS too: a method's `where` on its impl's parameter bounded
  every method of the block (`get` needed `reset`'s `T: Zero`); two
  conflicting impls on a slice named a random symbol for the type.
- Regions: each rust-edition function's places body gets its region
  variables (a loan per borrow, one per reference in a parameter's or a
  local's type, one per call whose result holds one; `check
  --emit-places` prints them), every local's storage markers, and every
  body is built at check. Nothing is solved yet: one warning a function,
  `borrowck.unchecked`; 0.27.1's NLL solves them.
- `--allow=CODE` (repeatable; a family, `--allow=borrowck`) leaves a
  warning out, as rustc's `-A`; `--max-errors=N` (0: every error);
  `--edition rust`. `volec guide edition`,
  and `volec explain` for the four codes.

The rust edition's std, its API as a spec tree (std270):

- `compiler/std2` is the std that rust-edition programs get from 0.27.2:
  every item's signature in its final form and its doc, with a body where
  one is trivial and `todo()` otherwise, checked as its own root (`volec
  check --edition rust compiler/std2/std.vl`). It is a redesign of
  compiler/std, not a port: `v.get(i)` is `Option<&T>`, iterators yield
  `&T` and `iter_mut` `&mut T`, maps have `entry`, `Option` has `take`,
  `as_ref` and `as_mut`; allocation stays a capability (`Vec<T, A>`,
  `Box::new_in(x, a)`, `_in` forms, `clone_in(a)`), every iterator has a
  named type, and std's paths are Rust's (std::vec, std::collections,
  std::alloc). In 0.27.0 rust-edition programs still run on MVS's std;
  std2 is not built into the compiler before 0.27.2.
- Its modules: Option, Result and Box; the traits (PartialEq to Ord with
  Ordering, the operators with Rhs and Output, Deref, Index, DefaultIn
  beside Default, ToOwnedIn, ToStringIn, FromIteratorIn); Vec, the slices
  (MVS's free functions as methods, SliceIndex), str and char (Pattern
  over char, &str and closures), String; Hash, Hasher and BuildHasher,
  HashMap<K, V, A, S = FixedState> with Entry, HashSet; Iterator and its
  adapters; fmt over one Formatter<'a> type (no dyn); io; thread::scope
  with elided regions (no `for<>`); and the allocators: Allocator in
  Rust's shape with `FREES`, Gpa, Arena<P> with a safe `reset(&mut
  self)`, ArenaScope, TypedArena<T, P>, FixedBuf<'b>, AnyAlloc<'a>.
- A trait's impls for the primitive types are the compiler's, as MVS's
  are: `#[builtin_impls(i8, ..., bool)]` on the trait (42 traits), as
  `#[array_builtin(N)]` is for arrays; both wait for 0.27.2.
- `compiler/std2/checklist.tsv` (tools/std2-checklist.py) lists every item
  against MVS's std: 1,414 items, of which 297 kept, 15 renamed, 162
  changed and 940 new, and 70 MVS items gone, each with its replacement;
  every MVS item of the modules in scope is accounted for. Each item says
  what the real check makes of it (`typecheck.txt`, the front's 351
  errors on the tree, `volec check --edition rust --max-errors=0`, mapped
  to their items): 1,070 typecheck, 261 have only `edition.later` errors
  and 83 a plain one, 55 of those only because MVS's std is loaded
  beside std2 (std2_root, gone when std2 is the std). It names the
  features it waits for, the `edition.later` codes (impl_on_instance,
  char, the primitives' impls, FnOnce, impls for references, ...) and,
  for a plain error, the front gap it shows (`features.tsv`, each with
  its release: 0.27.2 but for `&&'a T`, 0.27.1), and the gate-1 test
  that will cover it.
- `compiler/std2/rewrite.tsv` is the std part of `fix --edition rust`'s
  table (0.27.3): 248 rows for 233 MVS items, each call, type name or
  impl shape that changes, chosen by type (`v.get(i)` is `v[i]` for a
  Copy T; MVS's unstable `sort` is `sort_unstable`; `m.reserve(n)` keeps
  its meaning as `m.reserve(n.saturating_sub(m.len()))`).
- `compiler/std/embed.sh --edition rust` embeds compiler/std2 as
  front/stdsrc_rust.vl (std2_source and its index), for 0.27.2; run now
  it would add about 0.26 MB to the binary. MVS's stdsrc.vl is unchanged.
- (fmt reads the rust edition since ed270, so compiler/std2 is formatted
  and checked by pre-commit, premerge and `fmt --all` like any file.)

The compiler's last exempt statics, Ctx's raw tables and its task contexts (left270):

- SYMS and TYPES (the symbols, their hash tables, the types, their lists
  and hash) are fields of `base::ctx::Ctx`. Each is read through a lookup
  that writes nothing: find_type, a symbol's find_sym, layouts made on the
  main thread by `lay_out_types` before code generation, the halves of
  256-bit vectors, and the runtime's symbols made in prepare_tasks. The
  tasks only read them. A symbol's text is a pointer and a length, read by
  `base::sym_text`. The alloc exemption (`is_exempt_static`) is deleted:
  no static is exempt. The compiler's statics went from 188 to 177.
- `volec refactor table Ctx.x` takes a struct's field `x: *T`, with its
  count and capacity fields, to `Vec<T, A>`, A being the struct's last
  type parameter (tests/refactor/table270.t). Ctx's structs, fns, statics,
  variants, modules, locals, relocs and consts are Vecs, and `fix --only
  unneeded-unsafe` took away the 267 unsafe blocks their indexing needed.
  The compiler's unjustified unsafe sites went from 3,054 to 2,788.
- `fix --only rawptr` takes a call into a let before its statement when
  it is nested in the arguments of another call given the same local
  (`ir_make(cx, ir_val(cx, ..))`, where both inout would be own.conflict).
  It does the same for an argument nesting such calls, an if's condition,
  an operator's operands (the left of `&&` and `||`) and a place's index.
  A run that takes some says so and decides no parameter; the next run
  decides them. rawptr-list names the call that keeps a parameter raw
  (`at FILE:LINE`) (tests/refactor/rawptr0270.t). Run over compiler/src,
  it made 121 task contexts `inout FnCtx`: `cx: *FnCtx` went from 143 to
  24. The 17 left for nested-call (ir_val, ir_arg and ir_operand among
  them) are called on the right of `&&` or `||`, or beside a borrowed part
  of the context. Unjustified unsafe went from 2,788 to 2,776.
- Seven of the tools' eight view statics are gone (statics 177 to 170).
  fmt's text and the completion's text are owned copies in `Tcx`
  (`fmt_text`, `complete_text`), so their pieces' and tokens' views are
  checked; fmt's failure message and reduce's first failure are Bufs in
  Tcx; the completion prefix is two offsets; the text a rewrite reads by
  lines is a parameter. Before, each was a parameter's view laundered
  into a static through its pointer. base::SRC stays: it views a buffer
  that grows (feedbacks/left270.md has a design for 0.27.x).

### What's new in 0.26.5

The compiler's statics in context structs, the rest: 1,234 statics to 188, the tables code generation's threads read included, and the alloc exemption down to two statics. Built and tested on aarch64-macos only.

The statics into context structs, phases 4-6 (statics265):

- `volec fix --only statics` does in the same run what the 0.26.4 phases
  did by hand: the group file's `use PATH` lines are added where a
  function takes the context, its `owner-use PATH` lines where an owner
  makes it; the statics are taken out of the `use` lines and their
  declarations deleted. A static in a format literal's hole becomes
  `{field}` and the named argument `field = cx.field`; among named
  arguments the context goes named, in its parameter's place; a static
  lent beside the context (`f(&X, &cx)`) is taken into a local and put
  back after the statement when `f` does not use it through the context.
  A function given the context before keeps it (made inout where it now
  changes the context), so a second group can join a context already
  passed down. Functions in a generated file are refused like `main`.
- `fix --only statics-list --group FILE --prune PREFIX,...` prints the
  group without the statics that make a refused function, or one outside
  the prefixes, take the context, in rounds (`--prune crate`: refusals
  only): what 0.26.4's phase 3 did in up to 80 runs by hand.
- compiler/src, phase 4: 772 statics of base, front, places, the tools,
  guide and cli are fields of `base::ctx::Ctx<Comp>` (base/ctx.vl), made
  once per process by `main` and passed as `pcx` to 3,441 functions (2,153
  inout), from `tools/statics/p4-ctx.group`; the tool added the 437 use
  lines and deleted the declarations, and ten arguments after the context
  were taken into lets by hand. Left for phase 5: the 70 tables code
  generation's tasks read (the AST, types, functions, symbols, buffers,
  files), which need the tasks' let view. Before it, six front tables
  became `Vec`s (`refactor table`) and 154 unsafe blocks went. Statics in
  compiler/src: 1,234 to 451; unjustified unsafe 3,217 to 3,063. `check`
  of compiler/src: 1.03x 0.26.4's; with one compiler, checking the source
  itself costs 11% more (the own pass +29%, over the `&pcx` arguments).
- The own pass asked whether a context type holds an inout access at
  every use, walking its hundreds of fields each time; it keeps the answer
  per type now (`Ctx.inout_memo`, `OwnCx.holds_memo`), and checking
  compiler/src costs 6.7% fewer instructions.
- Phase 5a: the 153 statics of middle, back, gen0 and arch that no code
  generation task reaches joined `pcx` (`tools/statics/p5a-ctx.group`);
  the tool gave the functions that had `pcx` already the new fields in
  place. front::cpp::eval's three statics went into the C import's
  `CImportCx`. Statics in compiler/src: 450 to 294.
- `fix --only statics` takes `view PATH EXPR` lines: a function that gives
  its calls the context as EXPR, let (a thread's task loop, which reaches
  it through a pointer). A view whose callees change the context is
  refused (refused-view), and `--prune` leaves out, in one round, what
  each of them writes.
- Phase 5b, the tasks' view: code generation's tasks are lent the
  context let. `middle::threads::run_pooled` gives a task
  `*(POOL_PCX as *Ctx<Comp>)`, the context of the `pool_run` or
  `pool_run_joined` that started the phase, set before the tasks start
  and cleared after the last is done; its `UNSAFE:`/`SAFETY:` comments
  say why no task reads a field while it changes (the main thread changes
  the context only in `join_task`, whose writes `tests/threads_writes.sh`
  checks). 105 tables the tasks read (the AST, functions, structs,
  modules, files, the IR's tables, the inliner's and the code cache's) are
  fields now (`tools/statics/p5b-ctx.group`, pruned from 253: what a
  task's code may write stays static, each with its reason in
  threads_writes.sh). `tests/threads_writes.sh` checks the context's
  fields as it does statics, `base::ctx::Ctx.FIELD` in its lists. A let
  `Ctx` is lent by address, never copied. Statics in compiler/src: 294 to
  190 (16 constants, 1 C-facing).
- Phase 6, the alloc exemption narrowed: no struct of compiler/src holds
  `Comp` unnamed and no static holds an allocator, but for `base::SYMS`
  and `front::types::TYPES`, the two the exemption still names
  (front/check/alloc_rules.vl, each with its reason: code generation's
  tasks reach `intern` and `make_type`, which add to them, so they wait
  for 0.27's split of a read-only lookup from the writing code). The
  WGSL checks' arena is `WgslCx<Arena>`, made by main and passed to
  `check_block` as `wgx` (`tools/statics/wgsl-ctx.group`, 71 functions);
  `buf_fmt` and the tasks' `cx_fmt` format into a String of their own,
  so `FMT_SCRATCH` and `FnCtx.fmt` are gone; the format checker's
  `Parsed` is `Parsed<A>`. Statics in compiler/src: 190 to 188;
  unjustified unsafe 3,063 to 3,057.
- A static lent beside the context as an element's address (`f(&X[0],
  &cx)`, `X` an array a raw pointer reaches past the element) is taken
  into a local whole now, not as that one element: phase 4 had made
  `front::own::infer::col_stored`'s two masks one, and the callee's write
  to the second went to the stack (a compiler built at -O0 crashed in the
  own pass; tests/refactor/statics0265.t, `&PAIR[0]`).

### What's new in 0.26.4

The compiler on Rust's overflow checks, its raw-pointer parameters decided, and its statics in context structs. Built and tested on aarch64-macos only.

The compiler on Rust's overflow checks (wrap264):

- compiler/src writes every place it relies on wrapping with
  `wrapping_*`: its hashes, the division magic numbers, the constant
  folders, negations of MIN, the C preprocessor's `#if` arithmetic. The
  census (the compiler built with `--overflow-checks=on` and
  `VOLE_OVF_CENSUS`, run over the suite and itself) finds none left.
- The bootstrap's -O0 compilers (chain-diverse's B2 and A2O0) are built
  and run with the overflow checks on: `--overflow-checks=off` is gone
  from bootstrap/.
- A C header's `#if` with `MIN / -1` no longer stops the compiler with a
  division overflow: the preprocessor's words wrap, as C's do.
- A program that names nothing else of std has std's integer methods
  (`wrapping_*`, `checked_*`, `overflowing_*`, `saturating_*`); before,
  `no method 'wrapping_mul' on type 'i64'`.
- Of tests/run's 60 cases built with `--overflow-checks=off`, 11 write
  their PRNGs and checksums with `wrapping_*` and lose the flag; the
  other 49 keep it, each with a one-line reason (they test wrapping, or
  the optimizer on wrapping operators).
- `base::comp::Comp`'s impl is `unsafe impl Allocator`, with its SAFETY
  comment; the alloc exemption keeps only Comp in statics and fields and
  the static `WGSL_ARENA`, until the statics work moves them into
  context structs.

The raw-pointer parameters (rawptr264):

- `volec fix --only rawptr` (`explain fix.rawptr`) decides each `p: *T`
  and `p: sink *T` parameter of a program's own safe functions by what
  its function does with it, over the whole program: one only read or
  written through becomes `p: inout T` (a let `p: T` when T is small or
  owned: a let parameter copies a larger plain value and reads it as a
  snapshot), its calls give `&x`, a parameter passed on `&p`, a raw
  pointer `&*q` (in a new unsafe block, with its comments, outside
  unsafe code), and `*p` becomes `p`. A pointer used as one (stored,
  returned, cast, compared, indexed, assigned, captured, given null or a
  C string, passed on to a parameter used as an address) stays `*T`, and
  so does one given to a call nested in the arguments of another call
  that takes the same place (`f(&cx, g(&cx))`: two inout accesses would
  be own.conflict). `--only rawptr-list` is the dry run, each parameter
  with its class and reason. A second run changes nothing.
- compiler/src on it: of its 2,583 `*T` parameters, 1,416 are `inout T`
  now (1,399 of them `FnCtx`: 580 only read, 731 written, 105 given a
  raw pointer by a thread or task root), 1,139 stay raw (813 C strings,
  141 nested calls, 211 indexed) and 28 cannot change (unsafe fns,
  receivers, `**T`). 104 unsafe blocks left with nothing unsafe are
  gone: unjustified unsafe sites 3,329 to 3,224 (docs/unsafe-baseline.md).
- The own pass memoizes, per function, whether a type holds an inout
  access (kinds::holds_inout walked every field of an inout context at
  every call): `check` of compiler/src 0.95x 0.26.3's.

The statics into context structs (statics264):

- `volec fix --only statics --group FILE` (`explain fix.statics`)
  moves a group of statics into a context passed down. The group file
  names the statics, the field each becomes, the parameter's name and
  type, and the owners that make the context as a local. Each function
  naming one of the statics, and its callers up to the owners, takes the
  context **last** (before a parameter with a default), so a call nested
  in another's arguments can take it too (`two(add(1, &cx), 2, &cx)`).
  It is inout where the function or a callee writes the context, let
  otherwise. Uses become `cx.field`, calls give `&cx` or `cx`. A method
  of the context's field whose argument changes the context gets that
  argument as a `let` before the statement. A function no owner reaches
  (`main`, a C entry, a function value, a trait's method) refuses the
  group, and nothing changes. `--only statics-list` is the dry run. A
  second run changes nothing.
- compiler/src, phase 1: the places IR's body and its control-flow graph
  (19 statics: places/ir.vl's `B_*`, `P_*` and `CUR_BLOCK`, places/cfg.vl's
  tables) are `places::ir::Body`, passed as `pbody` to 288 functions (105
  inout, 183 let) from four owners: check_program, lower_program, gen0's
  compile_program and `query drops`. None of them runs in a code
  generator's task. Statics in compiler/src: 2,138 to 2,149 (the tool
  adds 30 of its own, which phase 2 moves with tools'). `check` of
  compiler/src: 1.00x the base's, 0.95x 0.26.3's.
- compiler/src, phase 2: 673 of the tools' 760 statics are fields of
  `tools::ctx::Tcx` (tools/ctx.vl), made once per process by `main` and
  `cli::run::run` and passed as `tcx` to 1,228 functions (765 inout), so
  a batch's or the language server's later commands still see what the
  earlier ones left. The tool's own 32 are among them. 87 stay statics:
  59 whose users front, base or places reach through a hook (phase 4),
  7 slices viewing memory the context cannot name, 5 that code outside
  tools uses, and 16 never written. Statics in compiler/src: 2,151 to
  1,478. `check` of compiler/src: 1.00x the base's, 0.90x 0.26.3's; the
  source itself costs 4.9% more to check (the parameters and arguments
  added).
- compiler/src, phase 3: 244 of front's 843 statics are fields of six
  pass contexts, each made where its pass starts: the own pass's walk
  state (`front::own::ctx::OwnCx`, 83, made by check_program and by
  `query own`'s walk), the C import's (`CImportCx`, 85, made by
  import_c_headers), the embedded WGSL's check (`EmbedCx`, 40), the
  thread-safety pass's (`ThreadsCx`, 18), the contracts' expansion
  (`ContractsCx`, 9) and the target features' check (`FeaturesCx`, 9).
  What lives across functions or past its pass (the own pass's
  summaries, the effects, the checker's tables) is phase 4's. Statics
  in compiler/src: 1,478 to 1,234. `check` of compiler/src: 0.89x
  0.26.3's. With one compiler, checking the source itself costs 6.1%
  more than before phase 1 (phase 1 +0.9%, phase 2 +4.3%, phase 3
  +0.8%).

### What's new in 0.26.3

Allocation as a capability; compiler/src on 0.26.2's language (format
literals, `usize`); f-strings removed; std's text on `String<A>`;
`wrapping_*` and Rust's overflow checks. Built and tested on
aarch64-macos only.

- tools/unicode, the generator of std's Unicode tables, is removed: it
  had not compiled since 0.20's spellings and nothing built it. The
  tables stay as generated (Unicode 18.0.0); v0.26.2 has the generator.

f-strings removed (fstr263):

- `f"..."` is `error syntax.fstring` (`explain syntax.fstring`): once
  per file, at its first f-string, with how many the file has, and
  `try: volec fix --only fstring --keep-braces FILE`, which still reads
  them and rewrites every one as a format literal (a name hole stays, an
  expression becomes `{}` and an argument after the literal) or, away
  from a format function, `format_args(..)`. The rest of the file is
  checked as before. Use `--keep-braces` for code written for 0.26.2;
  without it the fix also doubles the braces of plain literals at format
  positions, as code from before 0.26.2 needs.
- The tree has none left: compiler/src (444, the release's first
  migration), std's comments, tools/ and the generators' output, bench/,
  examples/, tests/, tests/agent-eval (with `fix --only usize`), the
  Book, the guide's examples and docs/' examples. What remains is `fix --only fstring`'s own
  cases and the error's.
- The messages that named an f-string name the value of `format_args`:
  `a format_args value is a 'std::Interp' (a value that prints), not
  '[u8]'`; a contract message's holes (`contract.message`).

compiler/src on `usize` (usize263):

- `volec fix --only casts` removes a usize's `as i64` (`s.len as i64`,
  `v.len() as i64`) where the value means the same as a usize: an index;
  a slicing's end (`a[i..a.len as i64]` becomes `a[i..]`); a comparison
  with a usize, a literal or another removed cast; the bound of a `for`
  whose counter is used only in those ways; a `let` used only in those
  ways. It never touches a value that reaches `-` or other arithmetic,
  an i64 (a field, an argument, a comparison with an i64 counter), a sign
  test, a closure, or a generic instance's copy. `note fix.casts` counts
  every cast by class, and `--only casts-list` is a dry run that lists
  them.

Arithmetic, Rust's (arith263, decision 6):

- **Breaking: integer overflow panics at -O0.** `+ - *`, unary `-` and
  the shifts are checked when the overflow checks are on, -O0's default
  (rustc's debug builds): `attempt to add with overflow` at the
  expression, exit 101. At -O1 and -O2 they wrap, as before.
  `--overflow-checks=on|off` overrides the level (hashed by the code
  cache); std is built with the program's setting. A program that relies
  on wrapping writes `wrapping_*` or `Wrapping<T>`, or builds with
  `--overflow-checks=off`.
- **Breaking: `/` and `%` by zero, and `MIN / -1`, panic at every level**
  (`attempt to divide by zero`, `attempt to divide with overflow`), where
  `x / 0` was 0 and `x % 0` was x.
- **Shifts**: by the type's bits or more, a panic with the checks on; off,
  the amount is taken modulo the type's bits, as Rust's, also for 8- and
  16-bit operands (`1u8 << 9` is 2, was 0).
- **Constants** follow the same rule: with the checks on, a constant
  expression that overflows is the error `arith.overflow` (`volec explain
  arith.overflow`); a constant `MIN / -1` is one at every level.
- std's integer API, Rust's names and results, for every integer type, as
  methods with no `use`: `wrapping_{add,sub,mul,neg,shl,shr,div,rem,pow}`,
  `checked_*` (an `Option`), `overflowing_*`, `saturating_*`, and the
  signed types' `*_abs`; `std::num::Wrapping<T>` with `+ - * /` and unary
  `-` (`Wrapping(x)`, `.value`). tests/run/num_int_ops_rust.vl checks them
  against rustc's results (tools/intops/twin.py). std's own wrap sites
  (its hashes, PRNGs, SWAR parsing, bit counts) are written `wrapping_*`.
- compiler/src still relies on wrapping in 46 places (feedbacks/arith263.md
  lists them) and may not call `wrapping_*` until 0.26.4: the bootstrap's
  -O0 builds of it (chain-diverse's B2 and A2O0) pass
  `--overflow-checks=off` until then.

Text (text263; grammar.md, "Items"):

- Rust's `#[deprecated]`, `#[deprecated = "note"]` and
  `#[deprecated(since = "..", note = "..")]` on any item, a method or a
  struct's field: each use (a call, a name, a type, a path, a `use`, a
  field read, a struct literal) is `warning item.deprecated` with the
  note, and the help says where the item is marked. A use inside a
  deprecated item, and std's own uses, are not reported.
- `volec fix --only buf` turns each std `Buf` binding (a local, a
  parameter, a field, a result, with the bindings its value flows
  between) into `String<A>` when every write is text (a `push_str` of a
  `str`, a format write, a constant byte below 0x80) and into
  `Vec<u8, A>` when every write is bytes (a byte that is not a constant,
  a constant at or above 0x80, a `push_str` of a `[u8]`). Mixed writes,
  no write, a binding passed to a std function that takes a `Buf`, and a
  method with no form on the side decided are refused, each named
  (`note fix.buf-refused`). It never guesses. The method table it maps
  through is printed with every run (`note fix.buf-table`).
- std's text is a `String<A>` (breaking): `format_in` returns one (as
  Rust's `format!`), `read_line` fills one (a line that is not UTF-8 is
  `Err(IoError::Read)`, the line left empty), and so do `Command::help_in`
  and `render_in` (std::cli), `take_capture`, `objc::push_ns_string`,
  `Window::clipboard_get_in`, `gpu::Adapter::name_in`, the messages of
  `gpu::Error::Shader` and `Pipeline`, `ShaderEntry`'s names and
  `wgsl::target_error`. std's ambient `format(x)` is gone: write
  `format_in(x, gpa)`. A program written for the `Buf` these returned:
  `volec fix --only buf`.
- std's byte buffers are `Vec<u8, A>` (breaking): `read_stdin_in`
  (and the ambient `read_stdin`) return one, as Rust's `read_to_end`
  fills, and so does `gen_buf`; std's snapshot, fuzz, window
  and SPIR-V buffers moved too. std::gpu::wgsl keeps `Buf` inside for
  0.26.3 (its names are `[u8]` slices of the WGSL source, and they
  become `str` in 0.27), but none of its public functions takes or
  returns one: `translate` gives a `Vec<u8, Gpa>` (SPIR-V is bytes),
  and its messages and dumps a `String<A>`.
- **std's `Buf` is `#[deprecated]`**: each use outside std is `warning
  item.deprecated`, naming `String<A>` for text and `Vec<u8, A>` for
  bytes. `fix --only buf` takes a format write (`push_fmt`, `push_int`)
  as weak evidence of text, so a binding with only format writes and
  byte uses becomes a `Vec<u8, A>` (the write
  `extend_from_slice(format_in(.., v.allocator()).as_bytes())`).
  `String::free` is new (as `Vec::free`: the memory given back).
- The tree is off `Buf`: examples/, tests/, bench/, tools/, the guide
  and the Book by `fix --only buf` and by hand where it refused (Buf
  mentions 1048 before, a few cases whose point is `Buf` itself after,
  each with a `WARNING` directive), and compiler/src (its two scratch
  buffers are `String<Comp>`; no `std::Buf` left in it).

Allocation as a capability (capab263; grammar.md, "Allocators"):

- No default allocator type: `Vec<u8>`, `Buf`, `HashMap<K, V>` are
  `alloc.default` (breaking); a type names its allocator, `Vec<u8,
  Gpa>` or a generic `A`, so a signature says what a function may
  allocate from. `alloc.no_in` replaces 0.16's "allocation is explicit"
  message for `Vec::new()` and the other forms without an allocator.
- `alloc.field`: a struct or enum holding an allocator names it in its
  parameters (`struct P<A: Allocator> { v: Vec<u8, A> }`, used as
  `P<Gpa>`); a struct literal infers the allocator from its fields.
  `alloc.static`: a static's type holds none, checked through the new
  auto trait `AllocFree` (std), which looks through pointers.
  `alloc.last`: an `_in` function takes its allocator last.
- `unsafe trait` and `unsafe impl`, Rust's: `Allocator` is an unsafe
  trait, and every impl of it is `unsafe impl` with its SAFETY comment
  (`alloc.safe_impl`). std's Gpa, Arena, ScopedArena and FixedBuf are.
- std's types that hold an allocator say so: std::gpu's `Device<A>`,
  `Error<A>` and the other handles, std::window's, mpsc's, `Command`'s,
  std::test's `Gen<A>`.
- `volec fix --only alloc` makes the exact fixes in rounds (`Gpa` where
  the default was, the `_in` call with the allocator in scope, a struct
  made generic and then its uses). 0.16's `fix --only alloc016` is gone.
- The tree is moved over with it: tests/, examples/, bench/, the guide.
  compiler/src keeps one exemption until 0.26.4 (its allocator
  `base::comp::Comp` and the static `WGSL_ARENA`), in one table in
  front/check/alloc_rules.vl; its unused allocator `Ast` is gone.

### What's new in 0.26.2

`usize` and Rust's float casts, with std's lengths and indices in `usize`; Rust's format strings, `where`, `impl Trait` arguments and `pub(crate)`; `defer` removed; shader parts and the rest of `embed wgsl`; the places IR places every drop and the AST lowerings are gone. Built and tested on aarch64-macos only.

`where`, `impl Trait`, visibility and format literals (text262; grammar.md, "Items", "Modules", "Formatting"):

- `where P: B + C, Q: D` after a function's result type, a struct's,
  enum's or trait's generics, or before an impl's `{`: the bounds join
  the parameters' inline ones. A bound on a type that is not a parameter
  of the item (`I::Item: Display`) is `where.unsupported`. `where` is a
  keyword (it was reserved).
- Argument-position `impl Trait`, `fn show(x: impl Display)` (also `impl
  Fn(i64) -> i64`, `inout impl FnMut(i64)`): a hidden type parameter,
  named `impl Display` in messages; a turbofish gives only the written
  parameters. Anywhere else it is `type.impl-position`.
- `volec fmt` lays `where` out as a signature's continuation.
- `pub(crate)`, `pub(super)`, `pub(self)` and `pub(in path)` on items,
  fields, `use` and `mod`, as Rust's; `pub(in path)` naming no module
  around its item is `vis.path`. A private or restricted item used
  outside is `item.private` (it was a `type error`); it and
  `field.private` say where a restricted one is visible. `fix --only pub`
  widens a restriction to `pub(crate)` (and still writes plain `pub` on a
  private item: compiler/src may write `pub(crate)` from 0.26.3);
  `query context` and hover show a field's restriction.
- Format literals, Rust's `format!` without the `!`: a plain literal that
  is the first argument of `print`, `println`, `eprint`, `eprintln`,
  `format_args` (new: Rust's `format_args!`), `format_in` (the allocator
  last), `push_fmt`, `Fmt::write`, `panic`, assert's message or a
  contract's `else` is a format string: `println("{} {x:>4}", a.b)`,
  positional and named (`name = e`) arguments, `{0}`, `{name}`, `N$`,
  `.*`, and Rust's whole spec (fill, `^`, `+`, `#`, `o`, `e`, `p`), byte
  for byte rustc's. The errors `format.syntax`, `format.spec`,
  `format.args`, `format.expr-hole` (its fix moves the expression to an
  argument). `panic("bad {x}")` formats on the stack, so `#[no_alloc]`
  code may. **Breaking:** such a literal's braces are holes now
  (`println("{")` is `format.syntax`, `warning[format]` is gone); `fix
  --only fstring` doubles them. f-strings stay, with no warning, until
  0.26.3. `{:#?}` is `format.spec` "not in this release".
- The tools see a format string's holes as an f-string's: `query refs`,
  `refactor rename` (a local, an item, a width's `name$`), `query type`
  and hover; `volec fmt` keeps a literal's bytes.
- `volec fix --only fstring`, the migration, run once on code written
  before 0.26.2: an f-string at a format position loses its `f` (a name
  hole stays, the other holes' expressions become its arguments, in
  order), one anywhere else becomes `format_args(..)`, 0.17's
  `b.push_str(f"..")` becomes `push_fmt`, and a plain literal at a
  format position gets its braces doubled. It refuses nothing. The
  guide's examples are migrated; compiler/src, std, the examples and the
  tests are not yet (their migrated copies check clean).
- Rust's print macros get the call without the `!` as their help
  (`println!("{} {x:?}", a)`: write `println("{} {x:?}", a)`; `format!`
  is `format_in(.., gpa)`, `write!(f, ..)` `f.write(..)`).
- **Breaking:** `defer` is removed (Rust has none): `defer e;` and
  `defer { .. }` are `syntax.defer` (`explain` shows the guard that
  replaces it, a struct whose `Drop` does the work, alive to the end of
  the scope; `defer` stays a keyword so the error can name it). The
  examples close their descriptors and directories with guards (`Fd`,
  `Dir`, openhtop's `Restore`). `fix --values` no longer deletes `defer
  v.free()`.
- `edit`, `fix`, `fmt` and `undo` write a file reached through a symlink
  through it: the link stays a link.

- `usize` and `isize` are types of their own, 64 bits, no longer names of `u64` and `i64`: `u8`..`u32` widen to `usize` (and `i8`..`i32` to `isize`), and `usize`/`u64`, `isize`/`i64` convert by `as` or `TryFrom` (new in std and the prelude, with `TryFromIntError`; for every integer type to and from `usize` and `isize`). Indexing takes any integer type.
- **Breaking:** std's lengths, indices and counts are `usize` (`len()`,
  `capacity()`, `find`'s position, `Vec`'s and slices' indices), and so is
  a slice's or an array's `.len()`. `volec fix --only usize` writes the
  conversions the errors name; the examples, tests/run, the transcripts,
  the guide and the Book are migrated so. The new warning
  `num.unsigned-cmp` names a comparison a `usize` cannot fail (`i >= 0`):
  it found a countdown in bigint that never ended. std's UTF-8 counts,
  `splitn`/`replacen`'s and the SIMD loads' index stay `i64` until the
  next std migration.
- Rust's overflow checks are measured, not on: `$VOLE_PROTO_OVF` builds
  them (checks at -O0, wrapping at -O1 and up, decision 6 as revised);
  by default the code is unchanged.
- Float to integer `as` saturates for every target type, as Rust's: `300.7 as u8 == 255`, `70000.0 as u16 == 65535`, `-1.0 as u64 == 0` (they were 44, 4464 and `u64::MAX`); NaN is 0. The same in constants, the folder, both code generators and x86-64.

Shader parts and the rest of `embed wgsl` (embed262; grammar.md,
"Embedded blocks"; `guide gpu#one-module-per-kernel`,
`gpu#shared-constants-and-structs`):

- Parts: `embed wgsl K with A, shaders::B { .. }` makes K's module of
  its parts' texts (each part's own parts first, each once), then its
  own. A part is checked only inside the blocks that use it and has no
  `src` or entry points of its own (`embed.part_use`); `embed.with` (a
  name that is no block, const or struct), `embed.cycle`; a binding two
  parts declare is `wgsl.binding`, naming both.
- A block's `.wgsl` file is a file of the program: its errors are at
  `x.wgsl:L:C`, published by the LSP to its own URI, and `query grep`
  finds its lines; the code cache's version changes (10).
- `#[repr(wgsl)]` structs have WGSL's layout (`[f32; 3]` a `vec3<f32>`,
  16-aligned), and `with` names them and `const`s of literal values: the
  compiler writes their WGSL into the module (`gpu.repr` for a field
  WGSL cannot share).
- Check-time GPU diagnostics in one function's `let`s
  (front/embed/gpu_lint.vl): `gpu.entry` for an entry point named by a
  string, `gpu.layout` for a bind group entry the shader's group has
  not or of another kind, `gpu.usage` for a buffer of a constant usage
  used without its flag (`try:` the edit), and the warning
  `gpu.unwritten` for a uniform buffer nothing in the function writes.
- The examples' shaders are blocks: fluid2d's 17 constants are 5 parts
  and 12 kernels with a `#[repr(wgsl)] GpuParams`, and galaga, galaxy,
  life and nes; so are the guide's 20.

The places IR, the own pass's drops' end (placesir262a; places-ir.md §5,
step 7; compiler/src/places/README.md):

- The builder makes its own statement temporaries and assignment drops,
  and drops the old value at every owned assignment, wherever it stands
  (an arm's value, inside an expression), as Rust does: the own pass's
  desugaring leaked it there.
- A contract's and an assert's condition in the IR, a branch per
  conjunct, each evaluated exactly once on every path, as `&&` does; the
  failing path's form is `intrinsic contract_check(false, SITE, VALUE..)`
  and the conjunct.
- Drop shims are found by the type with its distinct types erased (R11:
  `Option<(str, Matches)>::unwrap` found none); `--verify-places` checks
  every drop that runs finds its shim.
- The own pass's drop half is deleted (step 7): the implicit defers and
  their placement at the checker's call sites, the statement
  temporaries' flags and defers, the assignment desugaring,
  `finish_drops` and the walk's drop recording, glue.vl's AST glue and
  `--no-places`; the IR places every drop. The own walk keeps the
  temporaries' hidden `let`s for its view checks and takes its drop
  events from the scopes; own.drop_view is reported on its own.
- A check builds the bodies that may drop (no `--places` needed, which
  now asks nothing more): their drop edges give the effects and `query
  refs`/`callees` the drops' calls, each named by the value dropped
  (`'l' at a.vl:13:9 calls 'Loud::drop'`); a value moved out is no
  longer counted as dropped.

The places IR, the AST lowerings' end (placesir262b; places-ir.md §8
step 8):

- `--check-unsafe` from the IR: a `*` of a raw pointer checks its
  pointee, an element of one (`p[i]`) the element, a slice of one its
  bytes, each at the statement's position (the 9 cases' reports are
  unchanged). No function falls back to the AST lowering any more.
- No function is lowered from the AST (step 8a): `lower_function` is
  gone and gen0's function walk is an atomic intrinsic's body only;
  `VOLE_LOWER` is gone (from the code cache's key too), and a build
  under `--no-places` is an error. compiler/src's objects are
  byte-identical before and after, at -O0 and -O2.
- A contract's or an assert's failing path from the IR (step 8b), in
  both generators: its site and its shown values are the IR's operands
  (`contract_assert_conj_side_effect` passes: a conjunct is evaluated
  once). Then the AST walks are deleted: statements, blocks and the
  defers, `if`, the loops, `match` and its patterns, assignments,
  operators, places, aggregates, variants and slicing, in both
  generators (2,267 lines net; `middle/lower/matching.vl` and both
  `control.vl`s gone). What the IR does not lower itself: a literal, a
  name or a check's site of an operand, and the calls, intrinsics and
  vector operations it drives with their operands bound.
- A hello world's compile cost back to before the flip (1.12x of 0.25.5
  to 1.08x): the calling conventions' classification no longer walks a
  large array's every element (std's 4096-byte print buffer cost 1.5M
  instructions in one 7-instruction function), and a function's entry
  block starts with its parameters again, so interprocedural constants
  reach them (println's length into fmt_str_fd, whose long-string loop
  then folds away). std_heavy: -2.1%.
- tests/run.sh builds every other case with `--verify-places` (by its
  name's cksum; `VOLE_VERIFY_EVERY=N`: every N-th, 0: none).

### What's new in 0.26.1

The places IR becomes the one source of drops for both code generators, and std gains `Cell` and `UnsafeCell`. Built and tested on aarch64-macos only.

A value whose type has a `Drop` impl is dropped whole, under its flag
(the release gate's fuzz-sem, seed 89): with a field assigned on one path
and the value moved on another, the IR dropped its fields and never
called its `drop`. A field assigned after the value may have moved is
now own.partial, as moving a field out of it is (Rust's E0382).

The places IR, agent A's half (placesir261a; design/places-ir.md §8,
compiler/src/places/README.md):

- Kept bodies: at a build whose code generators read the IR, each
  elaborated body is kept and loaded back when its function is generated
  (places/keep.vl); `check --keep-places --emit-places` prints them so.
- Drop shims (places/shim.vl, §3.9): one body per type with drop glue,
  `drop_in_place::<T>` (a `Drop` impl's call, then the fields', an
  enum's switch, an array's loop, a sink closure's capture under its
  flag), made on demand; `check --emit-places --emit-shims` prints them.
- The builder's cost: operands written straight into the IR, storage
  markers only for locals with drop glue outside `--emit-places` and
  `--verify-places`; the IR's share of `check` of compiler/src from
  544M to about 420M instructions.
- Effects see the IR's drops: each function's kept and flagged drops
  give its effect graph an edge to the `Drop::drop` functions their
  shims call (front/effects/infer.vl), the edges the own pass's drop
  placeholders give until they go.
- `volec query drops FILE:LINE`: a function's drops as the IR decides
  them, each with where it runs (query.md, "drops").

The places IR, the code generators' half (placesir261b; §8 steps 1 to 5,
compiler/src/middle/README.md, compiler/src/gen0/README.md):

- Both code generators read each function's kept body, at every level
  (step 6; `VOLE_LOWER=ast` or `--no-places`: the AST walks, until step
  8 removes them). -O1 and -O2 lower it to the SSA IR
  (middle/lower/places.vl): a scalar never borrowed is an SSA variable,
  blocks in reverse postorder, the IR's drops as calls of their shims (a
  flagged one under its flag), switches as one Switch, an assert's
  condition from the IR. -O0 generates from it (gen0/gen/places.vl): a
  statement temporary's slot shared once it is dead, a value read first
  by the next statement (or at a block's start, by every predecessor's
  end) kept in the accumulator, a call's compound result made in its
  destination. Every function of compiler/src and of tests/run comes
  from the IR but under `--check-unsafe`; compilers built so compile
  compiler/src byte-identically. The cost, compiler/src at -O0 (the
  gate's measure, instructions): 1.13x the AST walk's, under the 1.15x
  bar set for it; -O1 1.02x, -O2 0.985x; objects -0.2%, +0.1%, -0.8%.
- fold: a three-way select whose two constants were equal took the
  wrong one (`k ? false : false` for `!k`); tests/run/opt_ifconv_three_way.vl.
- ir: a block's predecessor list starts with room for 4, not 64, so
  that ir_shrink leaves it alone: -O1's lower to SSA of compiler/src
  1,489M to 1,352M instructions.

Cells (cells261, plan §1 g; grammar.md, "Interior mutability"; `guide
memory#cells`):

- `std::cell::UnsafeCell<T>` and `Cell<T>`, Rust's API: `new`, `get`
  (T: Copy), `set`, `replace`, `take` (T: Default), `swap`, `update`,
  `into_inner`, `as_ptr`; Clone, Default, Debug, Eq and Ord. A cell is
  owned (move-only) with no drop of its own: `needs_drop::<Cell<i64>>()`
  is false, and a `let` parameter of one is a reference to the caller's
  cell, so `fn bump(c: Cell<i64>) { c.set(c.get() + 1); }` changes it.
- `std::Freeze`, an auto trait: a type holding no UnsafeCell by value.
  The optimizer keeps no fact through a shared reference to what is not
  Freeze; an immutable static of it lives in writable data.
- No bit copy of a cell: `for c in arr` over an array of cells iterates
  the array in place; `v.get(i)` of a cell, and a closure given a
  borrowing iterator's cells, are `own.interior_copy` (try: `v[i]`).
- A cell is not Sync: an immutable `static` of one is `sync.static` (a
  `static var` or a `#[thread_local] static var` may hold one); a cell
  of a view is `cell.view_item`.
- A contract condition or a `#[pure]` function may not read a cell or an
  atomic (`contract.effect`, `effect`): the hidden effect `interior`,
  `query effects F --why interior`.
- std's Atomic and Mutex hold an UnsafeCell, and std::fmt's print state
  is one immutable static behind one: printing is `io panic`, no longer
  `global` (`query effects std::println`).

### What's new in 0.26.0

The first release of the move to Rust's surface
([design/rust-surface-plan.md](design/rust-surface-plan.md)): the places
IR at `check`, struct fields private unless `pub`, and shaders as
`embed wgsl` blocks. Built and tested on aarch64-macos only; Linux is
untested in this release.

Shaders as embedded blocks (embedwgsl260; grammar.md, "Embedded blocks";
`guide gpu#shaders-as-embedded-blocks`):

- `embed wgsl NAME { WGSL }` and `embed wgsl NAME from "x.wgsl";`, an
  item: an immutable static whose fields are `src`, the text, and one
  per entry point holding its name (`dev.shader_wgsl(K.src)?`,
  `compute_pipeline(s, K.step)`). `embed`, `wgsl` and `from` stay
  identifiers. The lexer hands the text to WGSL's rule (the `}` that
  matches outside comments): `1u`, `@` attributes and nested comments
  are no vole errors.
- `volec check`, the LSP and every checked edit run the text through
  std::gpu::wgsl's front end: its first error at its `.vl` position
  (`error[wgsl.type]`), in the file form at the `from` string with the
  file's `x.wgsl:L:C:`. `K.stpe` is `gpu.entry`, listing the block's
  entry points, the nearest as `fix --suggested`'s fix.
- `gpu.*` (11) and `wgsl.*` (21) are codes with `volec explain` entries;
  wgslc's own table is gone. New codes: `gpu.entry`, `embed.language`,
  `embed.unterminated`, `embed.name`.
- The tools: fmt keeps a block's lines as they are; `query grep`
  classifies its text by WGSL's rules; `query show K`, `edit patch K`,
  `query refs K.step` (the WGSL `fn step`); the LSP's go to definition
  (the `from` file, `K.step`), document symbols and diagnostics. VS
  Code: a WGSL grammar, injected into blocks. The 6 `include_str` of
  `.wgsl` files in examples are blocks' file form.
- Cost: `compile_cost`'s `check` 1.00x the base; compiler/src itself
  grows by the WGSL front it now checks (one compiler on both sources:
  4,693M to 5,373M instructions, 308 to 332 ms).

Private fields (privfields260, plan §1 k):

- Breaking: a struct's fields are private to the module that declares
  it (and the modules inside it) unless marked `pub`, Rust's rule.
  Outside, a read, a write or a borrow of a private field is
  `error[field.private]`, and a struct literal that names one is
  `error[field.literal-private]`; a struct with no fields has its
  literal anywhere, enum variants' fields stay public, and what the
  compiler writes itself (main's `Gpa {}`, structural `==`, derives,
  closures, f-strings) is let through. std's modules are modules like
  any (0.20's exception, std as one module, is gone). On a program's own
  field the help is its declaration with `pub`, and `volec fix --only
  pub` (or `--suggested`) writes the `pub`s; `v.len` on a `Vec` still
  reads as `v.len()`. `volec explain field.private`,
  `field.literal-private`.
- `#[sealed]` is that rule, so it changes nothing: `warning[attr.obsolete]`,
  and `volec fix --only obsolete-attr` deletes it. std has none left;
  `Gpa` holds a private zero-sized field (`_private: ()`: still size 0,
  a `Vec` on it three words), so no program writes `Gpa {}`.
- The migration, `pub` on the fields read across modules: 165 in
  std::gpu::wgsl, 47 in the rest of std (std::sys's C structs,
  `SendError.value`), 286 in compiler/src, 63 in the examples, 6 in
  tests/. std's `Atomic { v: 0 }` and
  `RawLock { .. }` statics are `AtomicU64::new(0)` and `RawLock::new()`
  (constant calls), and so must a program's be (`static N: AtomicI64 =
  AtomicI64::new(0)`). std::gpu::wgsl's `pub` fields are provisional:
  0.26.2's `pub(crate)` may narrow them. `pub(crate)`, `pub(super)` and
  `pub(in path)` come in 0.26.2.

The places IR (placesir260):

- **The places IR, behind `--places`** (compiler/src/places,
  [design/places-ir.md](design/places-ir.md)): every checked body as
  typed locals, places with projections, temporaries, borrows and storage
  markers, its drops elaborated per place (move paths, two dataflows,
  flags, open drops). `--emit-places[=all]` prints it, `--verify-places`
  checks it, `--places-diff` compares its drops with the own pass's (5
  differences left over tests/run, each the IR's more precise, listed in
  places/README.md), and a move-out backstop reports what the own pass
  would let through (nothing over compiler/src and tests/run). New
  directive `// PLACES:` in tests/run; `places_*` cases for the audit's
  findings and families. Off by default: the builder costs about 430M
  instructions at `check` of compiler/src, over its 340M budget (§6's
  fallback rule); 0.26.1 makes it cheaper before turning it on.

### What's new in 0.25.5

The last release before 0.26's rethink of the core semantics: no language
change (the user, 10-29), only the compiler's tables, the tools, the
harness, std's soundness and code generation. Six of compiler/src's hot
tables are `Vec<T, Comp>` (NODES, SRC, TYPES, SYMS, DEFS, FILES):
compiler/src's unsafe went from 4,489 sites (4,365 unjustified) to 3,519
(3,425); `check` costs 1.03x 0.25.4's, the compiler's own -O2
self-compile 30% more instructions (about 8,600 bounds-checked Vec
indexes, each inlined with its failure block: the next measured step).
A compiler linked by `volec -o` had run about 10 times slower than one
linked by `cc` (an old SDK version in its header; fixed). Breaking:
`Atomic<T>` takes integers, bool and raw pointers only, and
`std::process::Command` moves. Found and left for 0.26: `v[i]` reads `v`
before it evaluates `i`, so `v[grow(&v)]` reads freed memory in safe code
(semantics-inventory seam 32).

The edit tools (edit255, feedbacks/DIGEST-0.25.4.md §2):

- dependent edits as one checked call: `edit patch` takes `--pairs FILE`
  with `--old/--new`, `@@ FILE` blocks (std's files too) and an inline
  module's text; an empty OLD inserts NEW above a `FILE:LINE` (comments
  above many lines in one pairs file); OLDs that touch are fine, and
  `patch.overlap` names both pairs (docs/refactor.md, "Several dependent
  edits in one call");
- `edit.breaks` ends with the error it refused for; an imports round
  whose import does not resolve is taken back, so it no longer hides the
  edit's own error;
- the imports round is one process for all the edited files: a dry run
  of `refactor table FNS` (36 files) from 16 s to 2 s; the edit copies
  are `FILE.vole-edit-TAG~`, so two edits in one tree at once (parallel
  dry runs) no longer break each other;
- `edit.generated`: an edit of a `// Generated by SCRIPT` file is refused,
  naming SCRIPT (`--force`);
- `same-output` takes the two compilers' own paths in what they print as
  equal; `query unsafe` reads the tree's std when it differs from the
  compiler's, and prints `try: volec fix --only unneeded-unsafe` when
  blocks are unneeded; `refactor --script` runs `rewrite --text` steps.

std (std255):

- **Breaking:** `Atomic<T>` is bounded: `T: AtomicValue`, which only the
  integers, `bool` and raw pointers implement (the compiler's, as `Ord`
  for pointers; std seals the trait: its function returns a type private
  to std::sync::atomic, so no program can add a type). The arithmetic
  (`fetch_add`, `fetch_sub`, `fetch_nand`, `fetch_max`, `fetch_min`) takes
  `T: AtomicInteger` (the integers), `fetch_and`/`or`/`xor`
  `T: AtomicBitwise` (and bool). 0.25.4 compiled `Atomic` of a struct,
  whose load faulted at -O2, and `Atomic<f64>`, whose `fetch_add` added
  the bits as an integer; both are now "the trait 'AtomicValue' is not
  implemented for 'f64'", at the call that makes one.
- std's statics under threads: a `Fmt::to_fd` of a program's own takes
  print's lock at its first write and keeps it to its flush (0.25.4 used
  print's buffer without it, a data race with any other thread's print
  that mixed lines and could write past the buffer); the checking
  allocator (`--check-alloc`) holds a lock in each entry (0.25.4 reported
  double and invalid frees, or crashed, when threads allocated); the CPU
  feature word of `std::arch::detect` is an atomic. stdin's buffer and
  Linux's argument statics stay plain: a thread that reaches them is
  refused (`sync.global`).
- A `#[thread_local]` builds without `use std::thread` (0.25.4: "undefined
  variable 'thread_c_malloc'" in std).
- `std::__fmt_in_end` (what `format_in(f"..")` compiles to) takes two
  arguments, safely; `std::test_args` (a test binary's arguments) reads
  `env::args_os()`, safely, and the test main takes no argc and argv.
- `[T]::starts_with(p)` and `ends_with(p)` (Rust's; bytes included);
  `f64::next_up`, `next_down` and f32's.
- `std::process::Command`: any number of arguments (0.25.4 panicked past
  32, and refused more than 4 KB of them), `env_remove(name)`, and
  `foreground(true)`: while `status()` or `output_in` waits, this process
  ignores SIGINT and SIGQUIT and the child starts with their default
  actions (as a shell runs a command: ^C ends the child, whose end this
  process reports). Breaking: a Command owns Vecs, so it moves.

Code generation and measuring (codegen255):

- A constant `-0.0` keeps its sign: the constant evaluator negated a
  float as `0.0 - x` (+0.0), in a `static`, `static var`, `const`,
  `[-0.0; N]` and a struct's field, and in a C header's float macro
  (tests/run/float_neg_zero_const.vl).
- A compiler linked by `volec ... -o X` (the internal Mach-O linker, the
  default on aarch64-macos) ran its -O2 self-compile in about 10 times
  the instructions of the same objects linked by `cc` (470G against 46G,
  measured on 0.25.4). Not the -O level: the linker wrote the SDK version
  12.0 in LC_BUILD_VERSION, and macOS's malloc keeps its older, slower
  free path for a program built against an SDK before 13. The linker now
  writes SDK 26.0 (the minimum OS stays 12.0); `tests/link/run.sh`'s
  `internal-sdk` pins it. Programs that allocate much, linked by volec,
  are faster the same way (docs/optimizer.md, "0.25.5").
- A static whose initializer is all zero bytes and that can be written
  (a `static var`, or one holding a cell) goes in bss: `__DATA,__bss`
  (zerofill) on Mach-O, `.bss` (NOBITS) on ELF, in both the system
  assembler's spelling and the in-process object writer and linker. A
  hello world's -O2 object 9,864 bytes to 5,552; one with a
  `[u8; 65536]` static 78,496 to 8,896 bytes and 145M to 105M
  instructions to build. A constant `[x; N]` is evaluated once and
  copied (a `[0; 65536]` cost 39M instructions). The internal linker's
  chained fixups name the file's pages only (a bss page past them made
  the kernel map other bytes into it). Test `static_bss`.
- Statics no emitted function names are not written: a hello world 12
  statics to 8 (std's stdin buffer and position, hash seeds), a
  std-heavy program 43 to 15. Test `static_unnamed`.
- `--time-passes=instructions` counts each phase in instructions retired,
  from the system's counter (macOS: `proc_pid_rusage`'s
  `ri_instructions`; Linux: `perf_event_open`, user space), without the
  `clock()` replacement build docs/optimizer.md described; where Linux
  refuses the counter it stops with `time.instructions` (`volec explain
  time.instructions`). tests/perf (suite `perf`).
- `--vec-stats=FN`: a line for each loop of FN at -O2, vectorized (lanes,
  unroll) or the first reason it was not (a call, a gather, a branch, an
  unknown trip count, a float carried between iterations, the cost
  model, ...).
- tests/threads_writes.sh had stopped checking anything when `static
  mut` became `static var`; it checks the 197 statics tasks touch again.

compiler/src's tables (tables255, docs/design/modernize-0254.md step 4):

- Compiler/src's tables: NODES (8,608 references), SRC (by hand, a `[u8]`
  view), TYPES, SYMS, DEFS and FILES are `Vec<T, Comp>`, each with the
  fixpoint and `volec same-output` against the compiler before it (no
  difference but the compiler's own path); FNS and TOKS stay raw (each
  would take `check` past 1.03x). A codegen change keeps checked Vec
  indexing cheap: no `len - 0` for a slice from 0, a Vec's pointer and
  length loaded as one pair (tests/run/opt_vec_index.vl).
- A data race in the code generator: emission threads interned an
  intrinsic template's placeholder names into SYMS while others read it
  (`index out of bounds` once in arch-gen at -O2); the names are interned
  on the main thread, templates look them up.
- `volec refactor table X` refuses `X[f(..)]` where f may
  grow X (a call reaching a write of X or X_COUNT, through every call the
  checker resolved): the index is evaluated after X's buffer and length
  are read, so the element would be read through X's old header. Two such
  reads of NODES in front/own/drops.vl (`NODES[t_node(..)]`) take the
  index into a `let` first.
- `volec refactor table X` takes a rollback, `let m =
  X_COUNT; ... X_COUNT = m;` (m a `let` assigned nowhere), as
  `X.truncate(m)`.
- The AArch64 and x86-64 emission of an intrinsic's
  template found its placeholders' names by interning them, on the code
  generator's threads: a push to the symbol table racing with the other
  threads' reads (with SYMS a Vec, seen once as `index out of bounds:
  index 7578, length 7578` in arch-gen at -O2). They are now looked up
  (find_sym), the six slot names interned when the table is read.
- `volec fix --only unneeded-justified`: `unneeded-unsafe`'s
  blocks, and the unneeded ones whose `// UNSAFE:`/`// SAFETY:` comments
  justified them (a table's accessors), with those comments.

The hooks, the test harness and the guide (loop255, feedbacks/DIGEST-0.25.4.md §1 and §3):

- The check and turn-end hooks check with the tree's std: `volec check`
  reads the target's system file (compiler/std/sys/macos.vl,
  sys/linux.vl) from the tree as it reads std's other files when they
  differ from the built-in std, and `$VOLE_STD_TREE` names the tree to
  read wherever check runs (the hooks set it). A compiler before 0.25.5
  whose built-in system file is not the tree's gets one line,
  `note hook.stale-std`, instead of false `unresolved import` errors.
- The check hook runs compiler/guide/embed.sh after a change to the
  guide's source and names the files it rewrote.
- query-first.py lets through a `.vl` file the branch added (any tool),
  several small `sed -n` ranges of one file, reads of compiler/std's
  other files (`*.objc`, index.awk), and a Python script that only reads
  compiler source; a blocked line says which commands would have run
  alone.
- `tests/run.sh -n NAME`: one case, as `'=NAME'`, which zsh expands when
  unquoted; the runner ends a failed run with `try: tests/run.sh -n
  NAME ...` for the failing cases.
- Transcripts a std change does not rewrite: std's list of modules (as
  `query items` prints it) compares as one line; the LSP sessions compare
  std's positions normalized, and a request about a place in std's
  files names its line by its text (`"line":@LINE:std.vl:TEXT@`);
  every runner's `-u` keeps the std numbers
  of a line that did not change otherwise (tests/stdkeep.sh);
  views017 asks for its items by path. `tests/stdpos/run.sh --real`
  adds a function at the top of a std file and a std module, rebuilds,
  and runs the query, refactor, walkthrough and LSP suites.
- tests/refactor's `%` lines run the compiler under test as `volec`;
  `tests/affected.sh --linux` prints the container's failures with their
  differences; `tests/affected.sh` runs the compile-cost row (against the
  last release built here, about 3 s) when compiler/std, the front end
  or the optimizer change.
- `volec test`'s default time limit is `$VOLE_TEST_CASE_TIMEOUT` when
  set (10 s otherwise); the book's sessions give it nine times that on a
  loaded machine, as the watchdog does (the 0.25.4 gate's Linux rows).
- tests/fmt's `compiles` names a program changed during the run instead
  of `differ`.
- `guide how add-std-module` (index.awk's LAZY and GATES, closed gates,
  header comments, why a build fails where `check` passes, the
  transcripts), an alias fact's adversarial test and its mutant in
  `add-pass`, the code prefixes and the 15-line help limit in
  `add-diagnostic`.

### What's new in 0.25.4

`volec run`, the pathtrace laboratory's feedback (feedbacks/pathtrace-ui.md),
the bugs carried from 0.25.3, std's unsafe justified to the last site, and
the start of compiler/src's modernization (docs/design/modernize-0254.md:
its plan, its first three steps and the first tables). Language changes to
review: `const X: str` is allowed; an array of unsuffixed literals takes
the other side's type; `f"""` text blocks; a closure's `|x: sink T|` and
its Fn bound must agree. Breaking: std's `sys_poll` and `__io_error`
signatures, and `#[sealed]` on std's thread and sync handles (below).
compiler/src's unsafe: 5,380 sites (5,316 unjustified) in 0.25.3, 4,489
(4,365) now; std's: 1,204 (1,194), 893 (0).

- `const X: str = "...";` is allowed: text, a constant, each use the
  literal, as a `[u8]` constant's is (`guide text#string-constants`).
  0.25.3 refused it because, allowed, it crashed: the checker inlined a
  string constant's literal only when its type was `[u8]`, so a `str`
  one was read as an integer constant, a null slice.
- A closure's `let` parameter takes a value with no place (`f(make())`),
  lent as a temporary of the statement and dropped at its end, as a
  function's does; 0.25.3 said "this value has no place".
- A closure whose parameter is taken another way than its `Fn` bound
  gives it (`|r: sink R|` for `F: FnMut(R)`, `|r: R|` for
  `FnMut(sink R)`, a let one for an `inout` one) is refused as not
  satisfying the bound, naming both ways, with the fix (`fix
  --suggested`) that writes the bound's; 0.25.3 gave a type mismatch
  whose help was wrong ("this value has no place", `*R`, `&i64`).
- `f"""` is an f-string text block: a text block's lines and dedent
  with an f-string's holes, specs and `{{ }}`, quotes as text
  (`guide syntax#lexical`); 0.25.3 said "newline in string literal".
  The language server's completion reads text blocks as one literal.
- The gate no longer stops a step that waits for a slot while the other
  steps' jobs use them all: 0.25.2.2's and 0.25.3's container rows
  stopped a fuzz row so ("0 of 8 slots free (slots lost with killed
  jobs?)") while the other 18 rows ran on the same slots to the end; no
  slot was lost. A still step is stopped when a slot is free, or when no
  step moved for `$VOLE_GATE_STALL` s; its processes and what they wait
  on go to its log, and they get 10 s after TERM to give their slots
  back. Two self-test rows (`gate.sh --self-test`) pin it.
- The check and turn-end hooks notice a tools binary older than the
  tree's source (`volec --version` below compiler/src/main.vl's
  `version()`): right after 0.25.3 the stop hook reported 16 errors that
  were 0.25.3's text blocks read by 0.25.2.2. They check with a current
  target/volec instead, or not at all, and say so in one line
  (`hook.stale-volec`) with the `try:` that installs the release's build.
- An error whose fix `fix --suggested` refuses before making it (a
  conversion that loses the value, a cast of a cast, a call made to call
  itself, std's function for another type) no longer prints `try: volec
  fix --suggested`; the refusal's `note fix.refused` still says why.
- A `requires` or `ensures` message's f-string hole that is not an
  integer, or a fourth hole, is `contract.message`, which says what
  shows such a value (0.25.3: "expected 'i64', got 'str'", and a fourth
  hole was left out of the message silently). The holes stay integers.
- **`std::num::fmt_f64(v, decimals, &out) -> i64`**: a float with a
  fixed number of decimals (0 to `FIXED_DECIMALS_MAX`, 20) at the end
  of a `[u8; 32]`, no allocation, `fmt_i64`'s shape: `{v:.N}`'s text
  byte for byte (the exact value rounded to the nearest, a tie to the
  even digit, `-0.00`, `NaN`, `inf`; `{v:e}`'s when longer than 32
  bytes), checked against `format_in` on 149,331 generated cases
  (tests/run/std_num_fmt_f64.vl); `guide text#numbers-as-text-without-an-allocator`.
  examples/gpu/pathtrace uses it instead of its own `format_fixed`, and
  its camera's five C math calls are `f64` methods (no `unsafe` left).
- **`guide gpu-render#drawing-over-the-image-you-just-made`**: an
  overlay pass (`PassDesc::color(view, load: Load::Keep)`,
  `Blend::alpha()`, a vertex layout of position, colour and uv, an
  `R8Unorm` atlas with a white texel, text measured and drawn), compiled
  and its pixels read back by `tests/run.sh guide`; from pathtrace's UI.
- **`guide window#checking-the-pixels-headless`**: a windowed program's
  frame drawn into `RawSurface::Headless`, read back and written as a
  PPM (pathtrace's `--headless --ui` the worked example), pointed to
  from `guide gpu`'s `RawSurface::Headless`.
- `guide window`: the scale is the window's (`Size`, `Resize`), not the
  surface's; `Surface` has no `scale`, and the mouse example keeps it.
- `guide testing`: a `#[test]` sees its module's private functions and
  methods and every field (fields are as visible as their struct), with
  a two-file example; tests/guide/run.sh now runs `volec test` on a
  guide program with `#[test]`s, so their bodies are checked and run (a
  build leaves them out).
- **An array of unsuffixed literals takes the other side's type**, as a
  literal does: `if down { ACCENT } else { [0.20, 0.52, 0.70, 1.0] }`
  with `ACCENT: [f32; 4]` is a `[f32; 4]` (an `else if` chain too), and
  so is a match arm (before or after the typed one) and an element of
  `[[0.1, 0.2, 0.3, 1.0], ACCENT]`; 0.25.3 said `if/else branches have
  different types: '[f32; 4]' vs '[f64; 4]'`. A branch that is a local
  made of literals (`let base = [0.2, ...];`) gets the note at its `let`
  with the annotation and its `edit patch`, as a mismatch does.
- **The check hook formats a new file**: a `.vl` file the agent has just
  created with Write, outside compiler/src and compiler/std, goes
  through `volec fmt` before the check, and the hook names the changes
  as its other rewrites (`changed FILE:LINE: OLD -> NEW`, `the hook
  rewrote FILE: ...`; `volec undo` takes it back; VOLE_HOOK_FMT=0: off).
  An existing file still gets the one-line note only.
- **A windowed program's own event loop runs without a display**: with
  `VOLE_WINDOW_SCRIPT` set, `App::new_in` opens no window server and
  the events come from the script (std::window::script): keys (with
  their Text), mouse moves, presses, releases and clicks, scrolls,
  resizes, focus, Close and Quit, and each Frame as soon as the program
  asks for it, never from the 10 Hz timer a hidden window gets. The
  window's `raw_surface()` is null, which std::gpu takes for a headless
  surface, so the program needs no code for it; `shot FILE` writes the
  next frame presented as a PPM (`gpu::capture_next_frame`, which a
  program can call too). The GPU evals' agents could not test input or
  frame times; now `tests/examples/gpu-life-script.test` paints and
  steps examples/gpu/life and `pathtrace-script.test` clicks a button of
  pathtrace's panel, each against a golden region
  (`guide window#testing-input-without-a-display`). The test runner
  gets `// ENV: NAME=VALUE`.
- **GPU timestamps**, on WebGPU's timestamp-query: `dev.query_set(n)`,
  `enc.compute_pass_timed(set, begin, end, |pass| ..)` and
  `render_pass_timed`, `enc.resolve_query_set(set, first, count, buf,
  offset)` into a `BufferUsage::QUERY_RESOLVE` buffer, and
  `queue.timestamp_period()` (ns a tick). On Metal a timed pass is a
  command buffer of its own and its timestamps are the command buffer's
  `GPUStartTime` and `GPUEndTime` (already bound; counter sampling would
  have needed a dozen new Objective-C classes and methods for the same
  per-pass resolution on Apple GPUs, which sample at stage boundaries
  only); a submission with timed passes returns once they have
  finished. `dev.caps().timestamps` says whether a device has them
  (`gpu.unsupported` otherwise, never a wrong number).
  `tests/gpu/cases/timestamp_query.vl` checks that a kernel looping 8
  times longer measures longer (the ratio of medians), and
  `guide gpu#timing-gpu-work` uses them.
- `volec fix --only unneeded-unsafe`: the unsafe blocks with
  nothing unsafe inside (`volec query unsafe`'s `none (unneeded)`) taken
  away, the code in them kept in its scope (a block on lines of its own
  becomes its lines, one level less indented; a block on one line its
  code, parenthesized where operators around could bind otherwise); a
  block that declares and is not last, one with a string over several
  lines, one whose comments say `UNSAFE:`/`SAFETY:` are left and counted.
  Run over compiler/src: 938 blocks gone, the unjustified sites 5,315 to
  4,377, before the merge of
  bugs254 (docs/unsafe-baseline.md), every compilation of the corpus
  byte-identical (`volec same-output`). The plan for the rest of
  compiler/src's modernization: docs/design/modernize-0254.md.
- **`volec refactor table X`** (modernize-0254.md step 3):
  a raw table, `static var X: *T` with its X_COUNT and X_CAP grown by
  `grow`, becomes `static var X: Vec<T, Comp>` with every use: the grow
  goes, a store and its increment are `X.push(v)`, X_COUNT is `X.len()`,
  `= 0` `X.clear()`, `-= k` `X.truncate(..)`, the statics and their
  imports go. A use it cannot place (`&X[i]`, X passed or freed, X_CAP
  read, X_COUNT written, a call between a store and its increment that
  reads the count) is listed and nothing is changed
  (`refactor.table-use`; docs/refactor-shape.md, "refactor table").
- **`volec run [DIR] [OPTIONS] [-- ARGS...]`** builds the program whose
  root is DIR/main.vl (DIR: the current directory when none is given)
  and runs it: stdin, stdout and stderr its own, the words after `--`
  its arguments as they are (`--help` and `--json` too), its exit
  status volec's (128 + N when signal N ended it, as a shell says).
  OPTIONS are a plain build's (`-O0`, `-l`, `-L`, C files and objects,
  `-framework`, `--check-alloc`...; `--target` only the host's), and a
  build error is the plain build's (status 1, nothing run). The program
  is kept in volec's cache, never in DIR: CACHE/run/NAME-KEY/NAME, CACHE
  the tools' cache (./target/volec-cache, `$VOLE_CACHE`) or else
  `$TMPDIR/volec-cache`, which the code cache then uses too; KEY hashes
  the root's absolute path and the options. It is built again only when a
  .vl file under DIR or a file of the link changed, or another compiler
  runs (`volec test`'s check, now shared: tools/testrun/program.vl);
  `-o FILE` keeps a copy at FILE too. On a terminal: the build's lines,
  naming the program (`Finished NAME in 0.4s`; `Finished` alone when
  nothing changed), then `Running NAME`; elsewhere only the program's
  output. Its errors: `run.no-main` (a folder without main.vl: `try:
  volec run DIR/SUB` for a subfolder that has one, or the plain build of
  its one .vl file), `run.file` (a file for its folder), `run.args` (a
  second folder: the program's arguments go after `--`), `run.option`
  (`-c`, `-S`, `--emit-ir`, another target...); `volec explain run.no-main`.
  `$VOLE_CACHE_TRACE` gets `run fresh` or `run build`. `volec run` was
  `cli.not-a-command` in 0.25.3; `volec exec` now reads as `run`
  (tests/refactor/run254.t).
- The words after `--` reach a command as they are: `--json`,
  `--values=...` and `--help` there were volec's own before.
- **std's unsafe, every site justified**: `volec query
  unsafe std --summary` went from 1204 sites (1194 without `// UNSAFE:`
  and `// SAFETY:` above them, 13 unneeded) to 893 sites, 0 unjustified,
  3 reported unneeded (generic methods the query cannot see instantiated;
  they are needed). docs/unsafe-baseline.md's std line is 0, so the gate
  fails on any new unjustified site in std. Per class: ffi 718 to 456,
  raw-pointer 346 to 317, other 90 to 72, alloc 39, static-mut 6
  to 4, transmute 5. `[T]::get`'s unchecked read stays (1.9x faster than
  `s[i]` in a 400M-read loop at -O2).
- **Soundness fixes in std**: `RecvIter` holds its own reference to the
  channel and has `Drop` (iterating after both ends were dropped read
  freed memory); `SysDir` and `SysSpawnActions` have `Drop` (a dropped
  one leaked its handle); `strerror` and `ptsname` became `strerror_r`
  and `ptsname_r` (both raced between threads); `NsWindow::close` clears
  its view, layer and display link, so a closed window's methods do
  nothing instead of using a released object; stdin's buffer checks its
  `malloc` for null (a static array instead made every program's object
  64 KiB larger, and a hello world's build 1.46x dearer).
- **Breaking, std's signatures**: `sys_poll(fds: inout [SysPollFd], ...)`
  (it writes `revents`; it took the slice by `let`); `__io_error(kind,
  msg: [u8])` and `io::Error` keeps a message index, not a C string;
  `#[sealed]` on `SysDir`, `SysSpawnActions`, `Mutex`, `MutexGuard`,
  `Sender`, `Receiver`, `RecvIter`, `JoinHandle`, `Scope` and
  `ScopedJoinHandle`, whose fields hold raw pointers a struct literal
  could forge; `atomic_fence` and `atomic_compiler_fence` are safe; the
  private `utf8_word` is `unsafe fn`.
- **std::objc**: `selector(name: [u8])` and `class_named(name: [u8])`,
  safe, for the selectors and classes the bindings name; the generated
  bindings (tools/objcgen) carry their `UNSAFE:`/`SAFETY:` comments.
- **std's core sections**: `Mutex`, `Once` and `Condvar` moved to a lazy
  section of their own ("Mutex, Once and Condvar (0.21)"), so a program
  that prints does not read them; core is 157436 bytes of 163840.
- **A Vec's header out of its loops** (-O2;
  docs/optimizer.md, "0.25.4: Vec facts"; middle/vecfacts.vl): a let
  parameter's Vec does not change during the call, and a store to a
  Vec's element does not reach that Vec's ptr, len or cap, so GVN, LICM
  and the vectorizer (which now moves a loop's invariant loads out
  first) keep them from before the loop. `for i in 0..v.len() { s +=
  v[i] }` over a let parameter is vectorized again (55 to 36 ms on
  bench/vecloop, IntVec's 35), `v[i] = v[i] + 1` over an inout Vec
  loses its bounds check and is vectorized (26 to 9 ms), and a static
  Vec's ptr and len are read once before a loop that indexes it. What
  unsafe code must keep for it is in `guide unsafe`: nothing lent let
  changes during the call, through a raw pointer either.

### What's new in 0.25.3

The third round of the GPU eval (evals/tasks/0.25.2.2: the same ten
tasks on 0.25.2.2; no turns lost to the two bugs 0.25.2.2 fixed, where
round 2 lost about 30; the last round of the loop, as run-to-run noise
now exceeds a release's effect), what it found, and the roadmap's 0.25.3.

**Breaking:** std::gpu takes WebGPU's usage rule for mappable buffers
(`MAP_READ` only with `COPY_DST`, `MAP_WRITE` only with `COPY_SRC`), so
a buffer a kernel writes is read back through a copy into a
`MAP_READ | COPY_DST` buffer, and a mapped buffer stays mapped until
`unmap(dev)` (the soundness item below; `guide gpu#skeleton`). The
round 1–3 eval programs under evals/tasks/0.25.2* that read back
through a `STORAGE | MAP_READ` buffer stop at `gpu.usage` on 0.25.3;
they are records of their release.

- **The unsafe audit**: `volec query unsafe [FILE...|std]` lists every
  unsafe block, `unsafe fn` and extern block of a program (std's too;
  `--no-std`): its item, the operations inside it that need unsafe as
  the checker counts them, a class (`ffi`, `alloc`, `intrinsic`,
  `transmute/cast`, `raw-pointer`, `static-mut`, `other`), whether the
  comments right above it say `UNSAFE:` and `SAFETY:`, and blocks with
  nothing unsafe inside (`none (unneeded)`); `--unjustified`,
  `--summary`, `--json`. `volec check` warns about a site without both
  comments (`unsafe.unjustified`, the first five and a count; `check
  --deny-warnings` makes it an error); the commit hook and premerge ask
  the compiler for the sites a change adds (tools/unsafe-diff-check.py,
  its 12-line heuristic left for what the compiler cannot read); the
  baseline, docs/unsafe-baseline.md (compiler/src 5,316 unjustified of
  5,380 sites, 938 blocks unneeded; std 1,194 of 1,204), and the gate's
  `unsafe-audit` row, which fails when either count rises.

- **Soundness**: a mapped read view of a GPU buffer no longer changes
  under the program (the round 3 GPU eval's ocean: `let v =
  gpu::f32s(r.map_read(dev))`, then a copy into `r`, and `v` read 1,
  then 2, racing the GPU without a wait). As in wgpu, `map_read` leaves
  the buffer mapped until `buf.unmap(dev)`, in state kept with the
  native buffer: a copy into a mapped buffer (or `write_buffer`) stops
  with `gpu.state` where it is recorded, and `queue.submit` stops when
  the copy was recorded before the `map_read`; `unmap` takes the buffer
  `inout`, so the checker refuses it while a view is used, and
  `map_read_copy_in` maps, copies and unmaps. `dev.buffer` and
  `buffer_init` take WebGPU's rule (`gpu.usage`): `MAP_READ` with
  `COPY_DST` alone, `MAP_WRITE` with `COPY_SRC` alone, so the GPU
  reaches a mappable buffer only by copies (a kernel's output is read
  through a copy into a `MAP_READ | COPY_DST` buffer; the guide, tests
  and examples moved). `gpu::f32s`, `u32s`, `i32s`, their `_mut` forms
  and `bytes_of_*` are `#[views(..)]` of their argument, and the
  checker keeps such a declared cast (a `[u8]` viewed as `[f32]`)
  past its type filter, which had dropped it: `f32s(r.map_read(dev))`
  viewed nothing, so `r` could be unmapped, or a Vec grown, under it.
  Inference carries the cast on: a function of the program's own that
  returns it (through locals, calls, structs, other such functions) is
  inferred to view its parameter, with no `#[views]`.
- **Diagnostics from the third GPU eval** (evals/tasks/0.25.2.2: eleven
  messages that cost agents turns):
  - `fn bump(inout x: i64)` is `conv.mode_order`: the mode goes after the
    colon, `x: inout i64` (the exact fix; `let x: T` is `x: T`), and the
    function is checked as if so written; it was "'inout' is a keyword:
    rename it";
  - an unknown name std has in several modules (`Matches`: std::cli's and
    std::string's) gets the one whose module the file names, else each;
    it was std::string's, the module loaded first;
  - `gpu::Instance` after `use std::gpu::{Surface};` (or `fs::read_in`
    with no `use`): `use std::gpu;` brings the module's name (the fix adds
    it); `fs` was "vole's std has no such module";
  - `const X: str = "..."`: a `str` is a static's (the fix), bytes a
    constant's; it was "constants must be ... string literals";
  - `v == s` of a `Vec<u8>` and a `[u8]`: `v.as_slice() == s`, the exact
    fix; `Duration - Duration`: the type's methods for it
    (`b.saturating_sub(a)`, the fix);
  - `{s}` of a slice says why it has no Display; `{s:?}` of a slice whose
    elements have Debug **now works** (`[1, 2, 3]`, `Fmt::debug_slice`);
  - own.moved and own.move_out of a move-only value name the statement
    that moved it: a struct literal or a tuple (`let (a, b) = (self.a,
    self.b)`), and a std function that keeps it (`'Vec::push' keeps it`,
    not "take it let"); a std::gpu handle's help points at
    `volec guide gpu#handles`;
  - a value whose type came from its literals (`let dt = 1.0 / 60.0;`
    used as an f32): a note at the `let`, `note: FILE:L:C: 'dt' is 'f64'
    from its literals: annotate it, `let dt: f32 = ...``, beside the
    edit and the fix there (errors may now have `note:` lines about
    another place).
- **std::cli**: `m.get(name)`, `get_as` and `values` of a flag fail
  (`cli.kind`, at the caller's line: "read a flag with m.flag(NAME)");
  `m.get("headless").is_some()` on a flag was always false (one agent
  lost a 120 s GPU run to it). `m.flag(name)` of an option stays what it
  was: whether it was given.
- **The compiler at a terminal** (base/term.vl): a build shows its
  phases (`Checking main.vl ... ok` for each of the program's files, or
  `... 2 errors`; `Compiling main.vl (-O2, aarch64-macos)`; `Linking
  prog`) and ends with `Finished prog in 0.42s` or `Failed prog: 2
  errors`; each diagnostic is rustc's shape, coloured: the position as
  `FILE:LINE:COL`, the source line, a caret under what is at the
  position, the `help:` and a highlighted `try:`. `check` gives the same
  per-file lines and summary. `--color=auto|always|never` (auto: when
  stderr is a terminal) and `NO_COLOR` (no colour; `--color=always`
  overrides it). Off a terminal (an agent, a hook, a pipe, the tests)
  and with `--color=never` the output is 0.25.2's, byte for byte.
- **`main.missing`**: building an executable of a program with no `fn
  main` is a compiler error after the checks, with `try:` lines that add
  `fn main() -> i32 { 0 }` or build an object (`-c`), instead of the
  linker's `Undefined symbols: "_main"`.
- **A failed link is one vole error**, never the linker's text first
  (back/objfile/linkfail.vl reads ld64's, ld-prime's, GNU ld's and lld's):
  `link.undefined` (at the extern declaration of the symbol, naming its
  block's `#[link]`), `link.no-library`, `link.no-framework`,
  `link.duplicate`, `link.c-file` (a C file of the command line that does
  not compile: its errors under the error), `link.no-linker`,
  `link.no-input` (checked before the link) and `link.failed` (anything
  else, the linker's lines under it). `--verbose` prints the link's
  command and the linker's whole text. tests/refactor/tty253.t has a case
  for each that can be made on macOS and Linux alike.
- **`volec build main.vl -o x`** says `'build' is not a volec command or a
  file` with `try: volec main.vl -o x` (`cli.not-a-command`); `run` gives
  `volec main.vl -o main && ./main`, a near-miss of a command (`chek`)
  that command.
- **Text blocks**: `"""` ending its line opens a string literal of
  several lines, a line holding only blanks and `"""` closes it, and the
  closing line's indentation is removed from every line (a line
  indented less is `lex.text-block-indent`, whose fix `volec fix
  --suggested` makes). Escapes work as in `"..."`, a `\` at a line's end
  joins it to the next; `r"""` is a raw block, without escapes (WGSL,
  regular expressions), and `r#"""` .. `"""#` holds a line starting
  with `"""`. A text block is a string literal (`[u8]`, `str`, in a
  `const` or `static`); `volec fmt` keeps its lines; a CRLF file's line
  breaks are `\n` in the value. New codes: `lex.text-block-open`,
  `lex.text-block-indent`, `lex.text-block-unterminated` (`volec
  explain`). docs/grammar.md, "Text blocks"; `guide syntax`.
- **`include_str("shader.wgsl")` and `include_bytes("font.bin")`**: a
  file's contents as a string literal, read at compile time, the path
  relative to the file holding the call (Rust's `include_str!(..)` is
  the same call). include_str's file must be UTF-8 (`embed.utf8`, fixed
  to include_bytes by `fix --suggested`); include_bytes' value is a
  `[u8]` whatever its bytes. A missing file is `embed.missing` (naming
  the path it tried), a path that is not a literal `embed.path`. The
  embedded files are inputs of the build: the tools' cache holds only
  while each has the bytes it had, and the code cache rebuilds what a
  change changes (tests/embed/run.sh, the `embed-checks` suite). The
  language server's go to definition on the call opens the file.
- **The examples**: examples/gpu's shaders are raw text blocks (fluid2d,
  galaga, galaxy, life) or `.wgsl` files read by `include_str`
  (pathtrace, voxel), their output unchanged; voltty's shader is
  `include_str("cells.wgsl")`, and `render/embed.sh`, which made it a
  constant, is gone. The guide's GPU programs use text blocks.
- **`volec test` shows what tests print** (the round 3 eval's sdftext
  failed asserts on purpose to see values): a failing test's own stdout
  and stderr are under its failure (`  stdout: x = 3`), and the
  failure's reason is the runtime's report, no longer a line the test
  printed to stderr; `--show-output` (`--nocapture` too) prints every
  test's under its name (`OUTPUT NAME`; per level when -O0 and -O2
  printed different things). A run with every test passing and no flag
  prints what it printed before.
- **`query show TYPE` lists the type's methods** after its source, one
  signature line each from every `impl` (a trait impl's marked `//
  impl Display for Error`, a contract cut to `requires ...`), at most 50
  (`--all`: every one).
- **`query items` filters**: `--find WORD` (the items with WORD at the
  start of a word of their name, any case when WORD is lowercase),
  `--kind fn,method,struct,enum,trait,const,...` and `--names` (a line
  an item: its kind and full path). `query items std --find clamp`
  finds `f64::clamp`, `i64::clamp` and the rest; `--find PI` the
  language's own constants too (`f64::consts::PI`); `guide math`
  starts with it.
- **The check hook names every rewrite**: each change of its fixes is
  a `changed FILE:LINE: OLD -> NEW` line, repeats included (past 10,
  their summary line); an agent's own `volec fmt` gets the lines it
  changed (from `volec query diff`, at most 5). The hook itself formats
  nothing.
- **A std change no longer breaks unrelated transcripts**: the query,
  refactor, walkthrough and book runners compare std's positions
  normalized (tests/stdpos.awk): `<std>:LINE:COL` and
  `compiler/std/FILE.vl:LINE:COL` as `L:C`, the rows under a `# <std>`
  header, a std module's item count (`std::gpu<TAB><std><TAB>N`) and a
  std item's `refs --count`. A program's own positions compare exactly,
  and so does a transcript with a line `## exact-std` (a README's or
  chapter's `<!-- exact-std -->`): tests/query/stdpos0253.q (std.vl's
  lines as `<std>` and as the file, which must agree) and
  tests/refactor/stdedit.t (its own small std, edited by FILE:LINE).
  `-u` rewrites only a failing transcript, with the real numbers. The
  query and refactor runners take NAMEs, as the walkthrough runner does.
  tests/stdpos/run.sh (category `stdpos`) moves std's numbers in every
  transcript that has them and runs them: all pass but the exact-std
  ones, which must fail; `--real` adds a line to std.vl and std::gpu in
  a copy, rebuilds, and runs the three suites whole.
- **compiler/src/front/stdsrc.vl stays tracked, and is made, not
  merged**: a git merge driver (tools/git-hooks/merge-stdsrc, named by
  .gitattributes) makes it from the merged compiler/std (git merge-tree
  of the two commits, then that std's embed.sh), so two branches that
  both change std merge without a conflict on it; when compiler/std
  itself conflicts, or in a rebase or cherry-pick, it reports a conflict
  that says to run compiler/std/embed.sh. The commit hook makes it from
  the staged std and stages it (it refused a std change without it);
  `bootstrap.sh` makes it from compiler/std before HEAD's compile (a
  stale one in the work tree is replaced, and said), and premerge's
  `std` row checks the committed one, from HEAD's std, and says when the
  driver is not set up. Set up once per clone: `tools/git-hooks/setup.sh`
  (core.hooksPath and merge.stdsrc). Untracked was not chosen: every
  release tag's tree must build as `git archive` gives it (the chain),
  and the tools read the compiler's source, stdsrc.vl included, in a
  fresh worktree before any build (query, check, the hooks, premerge).
- **The agent hooks in a tree inside another checkout**: query-first
  judges a path inside the vole tree that holds it (the nearest directory
  with compiler/src/main.vl and tools/agent-hooks), before the git root,
  and scratch (target/, tmp/) by the path inside that tree, not by any
  target/ or tmp/ of the absolute path: a release's tree extracted under
  target/bootstrap (the chain runs its suite there) or a copy under /tmp
  is the compiler's source, and `sed -i` on it is blocked as in the
  checkout. tools/agent-hooks/test-nested-tree.py runs the hooks' cases
  in a copy under target/ and one under /private/tmp.
- **The guide's gaps from the round 3 GPU eval** (eight that cost
  agents turns), each with a compiled example: `guide gpu` opens with
  a skeleton (the window loop, a compute pass, a render pass, a
  readback through a `MAP_READ | COPY_DST` buffer) and a list of its
  sections, the rest a section at a time (`guide gpu#NAME`) or
  `--whole`. `gpu#handles`, where own.moved and own.move_out point:
  which std::gpu objects move and which copy, keeping them in a struct
  made by a `sink` constructor, a `Vec` or an array, using them in a
  pass's closure, one of two by a flag. `gpu#ordering`: the dispatches
  of one pass run in order, each seeing the writes of the ones before
  (Metal's serial compute encoder; no barrier), with the cost of a
  pass and a submit. `gpu#ping-pong`: two buffers, two bind groups, the
  parity, every step in one pass, the state in the buffer written
  last. `gpu#per-step-parameters`: why one uniform cannot vary across
  the steps of one submit, and three ways with their costs (a submit a
  step; a uniform range a step; a storage buffer of parameters indexed
  by a step the GPU counts). `window#mouse-and-surface-size`: map the
  mouse with `surf.width` and `.height`, which `configure` at each
  `Resize` sets, never a size taken at the start.
  `window#when-the-window-is-not-shown`: the 10 Hz timer's frames, and
  timing headless instead (submit N, `wait_idle`, divide: throughput,
  not latency). `text#string-constants`: `const X: [u8]`, `static X:
  str`, `static X: [str; N]`, text blocks and `include_str`; what
  `as_slice`, `as_bytes`, `format_in` and `extend_from_slice` turn
  into what; what `panic` and `println` take. compiler/guide/embed.sh
  writes a topic of more than 990 lines as several functions.
- **The chain and a tag's own suite**: a release's tree cannot change,
  so a case of its own that cannot pass where the chain runs it is
  listed in its releases.toml entry (`known_failures`, CATEGORY:COUNT)
  with why; its suite passes only when it fails exactly so, and the
  summary says it. 0.25.2.2 has one: a hooks case whose hook takes the
  cache's `target/` path for a scratch copy (fixed in 0.25.3's hook).
- **The tools' cache, fixed**: `query show` (and `context`) of one of
  std's items no longer crashes when it answers from the cache (SIGSEGV
  every time, in 0.25.2.2 too: `query show parse_primary` in the
  compiler, whose std has a `Front::parse_primary`). Its `// use` line
  asks what `std::NAME` names, which the front end answers from its
  scopes and its table of items' nodes; a program from the cache has
  neither, and the answer read that table through a null pointer. The
  cache now keeps those answers (its format 9: a cache of 0.25.2.2 is
  not read, and is made again), the answers from it are the same as
  without it, and the table is not read where it was not made
  (tests/query/stdcache0253.q).
- **The tools' cache, checked**: tests/cachediff/run.sh runs every
  command line of the query and refactoring transcripts and of the
  walkthroughs (1,297 lines, 132 transcripts) without the cache, with
  a fresh one and from it, on the same state of the program, and
  compares the output,
  the exit status and the files left (a sample in the suite, category
  `cachediff`; all of it in the gate's `cachediff` step, --quick too).
  What it found: `volec` run from `$PATH` never had a cache (the
  compiler hashes its own file, and found none by a name without a
  `/`); and a cache made by the compiler under one name (`target/volec
  check`) was read under another (`volec edit ...`), with its errors'
  `try:` lines naming the first: `check` printed them, and an edit
  compared them with its own check's, took them for new errors and
  refused itself (`edit.breaks`). The cache's key now has the name the
  compiler was run by (tests/refactor/cachename0253.t).

- **A closure drops its by-value parameter** (a leak since 0.19, F20):
  one given to an `FnMut(sink T)` bound (`map`, `for_each`, `fold`,
  `Option::map`, `map_err`, `and_then`, `unwrap_or_else`, a program's
  own) owns its argument and drops it at the end of its body unless the
  body moves it out (returns it, pushes it, passes it on to a `sink`
  parameter; on one path, by a drop flag); `|_|` drops it too. A closure
  may say so itself, `|d: sink D|` (was `conv.sink_type`). A let
  parameter still borrows, and a borrowing iterator's items (`w.iter()`,
  a HashMap's) stay the container's: `own.iter_item_copy` is kept
  (lifting it, `w.iter().collect_in(gpa)` still frees each element
  twice). Fuzzed: semfuzz's `--closure-params` (in the gate's
  `fuzz-sem`) and the argument sweep's `own_arg_temp_sweep_closure`
  (1,680 cases); 12 XFAILs (the leaks, `|d: sink D|`) now pass.
- **volec's command line on 0.25.2's std::cli**: the compiler is built by
  0.25.2.2, so the workarounds of compiler/src/cli/ for 0.25.1's std::cli
  are gone (line.vl 608 lines to 425): the line's words go to std::cli
  as they are, the order of different options' values is
  `Matches::indices_of`, a word starting with `-` that is no option is a
  word by `allow_hyphen_values`, `--overlay PATH COPY`, `--rename A B`,
  `--subst P R` take `num_values(2)`, probe's words after `--` are
  `last`, a build's `--stats` and `--print-checks` `default_missing`,
  and the editing commands' shared options `edit`'s `global` ones.
  Messages, `try:` lines and exit statuses are as before
  (tools/cli-compat.py: 0 differences on 1,438 command lines but `-O3`
  of `probe` and `test`), with the rules of every other option: `-O3` is
  `-O 3` (`-O takes 0, 1 or 2, not '3'`; probe took it and failed
  later), `-Iinc`, `-j2` are `-I inc`, `-j 2`, a cluster `-in` of
  `query grep` is `-i -n`, and `--rename=A B` is `--rename A B`.
  docs/design/cli.md, "0.25.3", lists what std::cli still has no rule
  for and volec keeps.

### What's new in 0.25.2.2

The second round of the GPU eval (evals/tasks/0.25.2.1: the same ten
tasks on 0.25.2.1; agent time 121 against 165 minutes, tool calls 586
against 849, hook blocks 5 against 53) and what it found.

- **Soundness**: a call to a function with a `requires` clause binds its
  arguments in a block of its own, checked apart from ordinary blocks,
  so the drop pass never kept a `?` argument or a temporary there to the
  call: `dev.compute_pipeline(dev.shader_wgsl(SRC)?, "main")?` passed a
  shader with no entry points (two agents; one lost 15 turns), and a
  render pipeline's the same. A struct literal's `let` field given
  `make()?` or a returning match was lent from a dropped binding. Both
  since 0.24; tools/sinksweep/argsweep.py adds `requires` callees and
  arguments through a call or a struct literal: 13,440 cases (3,619 of
  the new ones wrong on 0.25.2.1).
- **`volec fix` crashed** (a bus error, now and then) on a name std
  re-exports (`use std::I64_MIN`): it read the entry before its table
  for an item std's root has no key for. tests/refactor/fixstdpath.t
  runs it under guard malloc, where 0.25.2.1 crashes every time.
- **std::gpu**:
  - a pipeline's layout is the bindings its own entry points use, through
    the functions they call (WebGPU's `layout: "auto"`); it was every
    binding of the module's entry points of its stages, so two pipelines
    of one module could not have different bind groups.
    examples/gpu/life and voxel pass each pipeline only its bindings;
  - `gpu.unwritten`: a submit whose dispatch or draw reads a uniform
    buffer nothing wrote stops, naming the binding (three agents read
    zeros from one and lost turns to it);
  - Rgba16Float, Rgba8Uint and Rg32Float storage textures work (std
    called them storable; the translator refused them);
  - `gpu.limits` names the limit as a program writes it and how to raise
    it; `adapter.limits()` is the adapter's largest, and `device(lim)`
    refuses more; `Limits::default()` keeps 1 GiB buffers, as wgpu keeps
    a portable minimum.
- **Integers** have `abs`, `signum`, `min`, `max`, `clamp` and
  `pow(u32)` as methods (std::num's `Int`, as `Float` for floats).
- **Diagnostics**: a `std::` path to a prelude name (`std::num::parse_int`)
  says it is in the prelude, `std::heap_gpa()` that main takes the
  allocator; own.move_out of a field an `if` or `match` picks says to
  use it in each branch (not `std::take`, which would empty it); `*x` of
  a `for` loop's variable; `use cpu;` for a module in scope; a slice
  `static` gets its length (`static T: [f32; 5]`, an exact fix); a
  module of constants as a type (`gpu::BufferUsage`: its values are
  `u32`); `volec check` of a file not yet a module, `volec test` of two
  files; an Option pattern on a Result.
- **Tools**: `query show`'s other-program suggestions prefer the
  caller's program and examples, never evals/ or tests/; every method of
  std::gpu and std::window resolves (203 of 501 did not); `FILE.vl::item`.
  The check hook writes one line for repeated fixes, says which files it
  rewrote, checks `sed -i`/`perl -pi`/Python writes of a `.vl`, and notes
  an unformatted file; a blocked compound line comes with the line
  without its blocked part; reads of up to 200 lines of any `.vl` run.
  A trait impl's method is named by its type's path in `query` and
  hovers (`<crate::more::Meters as From>::from`). `bootstrap.sh`
  replaces `target/volec` by a rename: a copy over a binary a test still
  ran made macOS kill every later run of it (`Killed: 9`).
- **The guide**: `guide gpu-render` (the render sections, with a textured
  quad), buffer sizes and limits, one compute pass for many dispatches,
  atomics need read_write, the reserved names, uniforms before their
  first write, HiDPI units in `guide window`, integers in `guide math`,
  `parse_int`'s Result; fences say `vole`.

### What's new in 0.25.2.1

The first round of the GPU eval (evals/tasks/0.25.2: ten agents each
wrote a GPU program in vole from scratch) and what it asked for. The same
ten tasks run again on this release.

- **Soundness**: an argument that may return early, in a call whose
  result is `?`'d (`f(make()?)?`, `f(match ..)?`, `count(mk(7), 8)?`),
  reached the callee empty or leaked, at every level, since 0.24.0. The
  block a `?` becomes is now visited for statement temporaries, an arm's
  binding passed to a `let` parameter is held to the call, and an arm
  that returns produces no value (front/own/drops.vl). 4,340 generated
  cases (tools/sinksweep/argsweep.py; 1,577 wrong on 0.25.2) are tests;
  `fuzz-sem --try-args` is in the gate.
- **Float math in std, in vole** (no libm): `Float`'s methods on `f32`
  and `f64` with no `use` (`abs`, `floor` .. `fract`, `min`/`max`/
  `clamp`, `sqrt`, `cbrt`, `hypot`, the trigonometry and its inverses,
  `exp`, `exp2`, `ln`, `log2`, `log10`, `log`, `powf`, `powi`, ..), the
  same as functions in `std::math`, and `f64::consts::PI` and
  `f64::EPSILON` .. `NAN` (f32 alike). Within 1 ulp of macOS's libm for
  most (`tan` 3, `powi` 8; tests/run/math_vs_libm). A float method reads
  std by itself. fluid2d, openhtop and galaga use it; `guide math`.
- **std::gpu**: a pass has up to 8 color attachments
  (`PassDesc::color(..).with_color(..)`), checked against the pipeline's
  targets at `set_pipeline` (`gpu.format`); depth-only passes
  (`PassDesc::depth_only`, `RenderDesc::depth_only`);
  `Buffer::map_read_copy_in` for bytes that outlive the mapping.
  `gpu.layout` lists the layout's bindings and the one that does not fit,
  `gpu.usage` names the buffer and the flag it lacks, and two variables
  at one binding say to give each kernel its own module.
- **std::window**: a window the display cannot show (asleep, occluded)
  still gets frames, from a 10 Hz timer, and says so after 3 s; `guide
  window`.
- **Diagnostics**: a value with no `.clone()` (`Device`) gets `sink`,
  one owner or an index instead; `Gpa` in a test points to `#[test] fn
  t(gpa: Gpa)`; a module and an item of one name are named, with the
  `use` to write; an unknown variant gets a did-you-mean or the list;
  `parse_i64` and the like point to `parse_int`; `..f` (struct update)
  says what to write; an array literal where a slice goes takes its
  element type (`let xs: [u32] = [1, 2, 3]`); nearest names only when
  related; the `const` and f-string helps show the form to write; a
  failing `assert` shows a float operand.
- **Tools**: `fix --suggested` refuses a fix that changes a value's type,
  a cast of a cast, an import nothing needs, a second import, and a
  rename to the enclosing function (`note fix.refused`, with the reason;
  tests/refactor/fixsafe.t). The check hook applies only mechanical fixes
  (call marks, Rust's spellings, unused imports), shows each change
  (`changed FILE:LINE: old -> new`) and lists the rest as suggested, not
  applied. The query-first hook lets a program's own small files be read
  and says "NOTHING on this line ran" when it blocks a compound line.
  `query grep` finds text inside strings (WGSL); `query show
  std::gpu::Color` follows re-exports; `edit patch` takes several
  `--old`/`--new` pairs, checked together (`note edit.together`).
- **The guide**: six gpu sections (multiple render targets, depth-only
  passes, one module per kernel, atomics, a compute simulation, timing
  GPU work), `guide math`, and in `guide testing` "a check must be able
  to fail", with `gpa: Gpa` near the top.
- **Tests**: a case for examples/voltty/app; the hooks cases run the
  compiler under test.

### What's new in 0.25.2

Bugs that real programs found (the showcase examples and agents' large
ports; the fuzzers had not), the tools agents asked for, and a faster,
steadier way to test.

- **Soundness** (each also in 0.25.1):
  - `-O2`'s vector loop could be unrolled by 3, but the trip mask
    `trips & -(U*VF)` needs a power of two: a loop of 14 iterations ran
    past its end. It unrolls by 4, 2 or 1 now; 1,173 generated loops
    (tools/loopsweep) are tests.
  - `t = t.add(size(leaf_of(gpa)))`: an owned assignment whose right side
    lends a temporary to a `let` argument read a function's address
    instead of the value, at every level (or gave a false error). The
    checked right side's temporaries are no longer hoisted twice, and
    they drop after the old value (conventions.md, 2.2). 233 of 330
    generated sink/inout cases (tools/sinksweep) printed wrong values
    before; `fuzz-sem --assign-calls` finds it on 0.25.1.
  - std's exemption from the move checks is gone except for std's root,
    `std::iter` and `std::collections`; the survey found no double free
    left (tests/std/moves.sh). `std::gpu::wgsl`'s
    `let f = m.functions[h]` double frees fixed.
  - `requires`/`ensures` arguments resolve in the caller's module.
- **volec's command line is std::cli**: `fn main(gpa)` reads
  `std::env::args_os()`, one command tree (cli/tree.vl); the same
  behaviour on 1,334 command lines; a non-UTF-8 argument is exit 1.
  std::cli gained `global`, `alias`, `hide`, `num_values`,
  `default_missing`, `allow_hyphen_values`, `last`, `conflicts_with`,
  `subcommand_required` and the errors `MissingSubcommand` and
  `ArgumentConflict`.
- **Diagnostics**: unused imports are a warning, `use.unused` (an error
  under `--deny-warnings`; 79 removed from the tree); a mismatch names
  the literal default at its `let`; `str::from_utf8(b)?` is suggested
  only where it type-checks; `fix --suggested` reads edited std.
- **Tools**: query and edit work on any program, not only the compiler's
  (`--root DIR`, or a FILE argument's own program; `note
  query.other-root`); `edit patch` matches at other indentation
  (`patch.loose`); `fmt --changed`, `--since REV`; probe and reduce keep
  their scratch copies out of the source tree; `agent-feedback --list`,
  `--find`.
- **The language server**: a file outside any program is its own root;
  info diagnostics say why a file is not checked; `-I DIR`,
  `vole.includePaths` and `vole.cSources`; go-to-definition on header
  strings and `c::`/`py::` names, hovers with the C prototype.
- **WGSL**: the 498 MSL reserved names a shader could not use are
  renamed; device-limit asserts are `Error::Shader` and
  `Error::Pipeline`; `wgsl.target` errors point at the WGSL; `guide gpu`.
- **Examples**: examples/gpu/fluid2d (Stable Fluids, in a window and
  headless), examples/nes (an NES emulator), galaxy, pathtrace and voxel
  under examples/gpu.
- **Testing in tiers** (AGENTS.md, "The inner loop"):
  `bootstrap.sh --dev --no-suite` (build and fixpoint in seconds,
  `target/tools/volec` kept), `tests/affected.sh` (the tests a branch's
  paths name in tests/affected.map, `--list`, `--linux`), `tests/run.sh`
  with several filters, `=NAME`, `-f FILE`, `-l`; `tools/premerge.sh` and
  the commit hook tools/git-hooks/pre-commit (unsafe justified, fmt,
  checks, stdsrc, example sources). The runner: `// EXPECT-PPM`, EXPECT
  holes, SKIP with a reason off macOS for window and GPU programs, load-aware
  time budgets and watchdog; `volec test` reruns a case that timed out
  while starved of CPU.
- **The gate**: a `linux-smoke` row in `--quick`; one gate at a time
  across worktrees; the job slots come back when a job is killed, and a
  row that stalls fails instead of hanging; the Linux release row runs
  -O0 and -O2 (-O1 stays on macOS), its long jobs first; chain-fresh
  skips the last release's suite when every rebuilt compiler is the
  recorded bytes.
- **Breaking**: an unused `use` is a warning (an error with
  `--deny-warnings`). A non-UTF-8 argument to volec is an error.

### What's new in 0.25.1

- **One style, everywhere.** `volec fmt` writes one opinionated layout
  ([style.md](style.md), `volec guide fmt`): `use` items sorted, merged
  and grouped, `std` first, then `crate`, then `super`, `self` and child
  modules, a blank line between groups (a run of imports continues
  across blank lines); four spaces, 100 columns, deterministic wrapping;
  a trailing comma in every list whose closing bracket starts a line,
  none in a list closed on its last line (a tuple of one keeps its
  own). Comments are kept as written, and fmt is idempotent. Its check
  still refuses any change but blanks and trailing commas.
- **The tree is formatted**: `fmt --all` (now with `tools/`) over the
  compiler, std (stdsrc regenerated), tests, examples, bench and the
  agent eval's programs. `same-output` against 0.25.0 over the corpus
  differs only in position tables and the compiler's path in `try:`
  lines. The tools' transcripts whose positions moved were regenerated.
  Not formatted: the tools' fixture programs (tests/query,
  tests/refactor), files that do not lex (the syntax-error tests), the
  VS Code grammar samples, and the book's code blocks (fmt reads files,
  not Markdown).
- **Enforced**: `fmt --all --check` runs in tests/run.sh and so in
  the gate.
- `crate::tools::fmt::format_source(text)`: the formatter in the
  process, for the language server's format-on-save.
- **The language server** (`volec lsp`, the VS Code extension 0.25.1):
  format-on-save and range formatting through fmt's engine (no edits on
  code that does not parse); completion after `.` and `::`, of names,
  keywords and snippets, on buffers that do not parse too (about 1.6 ms
  median), resolved with the signature, effects and doc comment;
  signature help with the conventions (`let`, `inout`, `sink`); the
  extension formats on save, tab size 4.
- **The examples audited for 0.25**: `check-alloc` rewritten (the bugs
  it showed are compile errors now; `--check-alloc` is shown on leaks
  and unsafe code), hand-written frees removed, the Rust-era wording
  gone; `toposort` no longer crashes on an empty input line.
- **Generic inference through `inout` and coercions**: `[T]` is
  inferred from `&xs`, subslices, `Vec`, `Buf`, arrays and `String`,
  under `let`, `inout` and `sink`.
- **The README's example is a quicksort**, kept the same as
  tests/run/readme_example.vl by the `readme` check.
- **Breaking**: nothing in the language. Code that passed `fmt --check`
  under 0.25.0 may need a `volec fmt`.

### What's new in 0.25

The compile-speed release, and an audit that made the core semantics
sound. The designs and records: docs/design/compile-speed-025.md, the
five docs/design/semantics-audit-025-*.md, docs/design/value-semantics.md,
"Trusting the chain" below; the book is book/.

- **Compile speed** against v0.24.0 (each compiler on its own source,
  best of 7 on an idle machine, the table in docs/roadmap.md's
  Benchmarks): the -O0 self-compile linked 521 to 287 ms (11.37 to
  6.11 G instructions), `check` 298 to 206 ms (5.58 to 3.22 G), a cold
  `query refs` 707 to 334 ms, a hello world linked 31.7 to 7.3 ms, the
  -O2 self-compile 1054 to 923 ms; peak memory is higher (the -O0
  self-compile 431 to 476 MB, `check` 310 to 354 MB). How:
  the resolve scans made linear, a line index, a faster lexer, data
  emitted as bytes, a faster assembler, `ld` run directly, and an
  in-house Mach-O linker as the default on aarch64-macos
  (back/objfile/link_macho.vl; `cc` still links on Linux).
- **The semantics audit**: five red-team audits of the core (exclusivity,
  ownership, views, polymorphism, the core language), about 1,600 probe
  programs kept as tests (`sem_excl`, `sem_own`, `sem_views`,
  `sem_poly`, `sem_core`, each at -O0 and -O2 with `--check-alloc`), and
  a value-semantics fuzzer whose oracle is its own model of the
  language (tools/semfuzz; the gate's `fuzz-sem`). They found about 30
  families of soundness bugs **in released versions**, all fixed: use
  after free, double frees, leaks, aliasing and -O2 miscompiles:
  - views: origins are conservative by default (a call's result views
    everything its inputs view unless proven narrower), through `v[i]`,
    summaries, collections, closures, statics and std's own summaries;
    std's ownership exceptions audited, each with a written argument;
  - exclusivity: an `inout` access needs a mutable root (`own.readonly`),
    `&v[i]` beside `v`, statics against what callees write, closures in
    the lifetime model, structs with `inout` fields move-only, FixedBuf
    holding its memory `inout`;
  - drops: `?` on borrowed payloads, partial patterns and `_` arms,
    element stores, `Vec::set`, moves out of element parts, `x.drop()`
    an error, temporaries dropped at the end of their statement, `for`
    and the iterator adapters (Iterator's consumers take `sink self`);
  - threads: the drop check, no views across channels, locks or
    atomics, scoped whole-slice races, scope and handle escapes;
  - the optimizer: LICM no longer hoists guarded loads or expensive
    speculative calls, stale loop facts in value ranges, and SLP's
    nondeterminism under -j (a possible miscompile since 0.18.1);
  - and effects through `assert`, contract purity, unsafe int-to-pointer
    casts, float-to-int saturation, a captured-coercion miscompile.
- **New gate rows**: `fuzz-sem`, `fuzz-guard`, `compile-cost` (from
  0.22), `chain-diverse` (HEAD built by three paths, byte-compared and
  same-output on the corpus), `chain-fresh` (the seed and every release
  rebuilt into an empty cache, against bootstrap/chain-hashes/) and
  `compiler-memcheck`.
- **The Vole Book** (book/): 18 chapters and 3 appendices, every
  example compiled and run by tests/book (311 checks; a block whose
  output only macOS gives is marked `macos`).
- **std::cli** across the examples, with any allocator, choices and
  custom errors; `volec`'s own command line moves to it partly (the rest
  in 0.25.1).
- **`#[link]` and `-framework`**: a block names its libraries and
  frameworks, so `volec examples/voltty/app/main.vl -o voltty` builds
  with no extra arguments.
- **The language server** resolves every name: std, allocators,
  keywords and operators; std's sources are cached.
- **Diagnostics**: `println` takes `let`; 0.20's words throughout the
  helps; a panic shows its position.
- **The README** rewritten, with the round logo (and a dark variant).
- **Found by the release gate** and fixed: `env::args()` did not build
  on Linux unless the program also read files (since 0.20; std's one
  index is made from sys/macos.vl, and Linux's `sys_args` named
  std::sys's file functions), now `sys_args` calls libc there itself;
  `chain-diverse` judged earlier runs' compilations as its own.
- **Tested on aarch64 only**, as since 0.15 (`gate.sh --with-x86`).
- **Breaking**: the audit's errors refuse programs that were unsound
  (each with a `try:`); `x.drop()` is an error; Iterator's consumers take
  `sink self`.
- **Known issues**, for 0.25.1: a closure's by-value parameters leak
  (F20); values017; the rest of fix25j's diagnostics; the rest of
  `volec`'s command line on std::cli (branch cli-volec);
  `split_at_mut`; iterator items as views (the full fix of 0.24's
  stopgap); 26 OVERSTRICT cases measured (sound programs refused);
  `--check-alloc` is not thread-safe in a -j8 compiler.

### What's new in 0.24

The language is **vole** from this release; the design of the rename is
docs/refactor.md ("Renaming the language") and tools/rename-vole.sh, the server's
docs/lsp.md, the parser's docs/design/cli.md and `volec guide cli`.

- **The rename**: tachyon is vole. The compiler is `volec`, sources are
  `.vl`, the environment's variables `VOLE_*`, the symbols `_vole.`; no
  aliases are kept. It was done by the compiler's own tools, in one run
  of tools/rename-vole.sh (`refactor extension .tach .vl --all`,
  `rewrite --text` for the words in comments, strings and other files),
  every program's build compared before and after (`same-output`). The
  chain still builds the releases up to 0.23 as `tachyonc` from `.tach`
  sources (releases.toml's `bin` and `ext`); v0.23.0 builds this
  release's `volec`.
- **The logo** (docs/assets/vole-logo.png), at the top of the README.
- **The language server and a VS Code extension** (editors/vscode):
  highlighting for `.vl` (a TextMate grammar with its tests), the
  editor's brackets and comments, and from `volec lsp`: diagnostics as
  you type, go to definition, references, document symbols, and hovers
  showing a function's signature with its effects, declared or inferred,
  a line of why for each, and its CPU features (a call of a generic
  function: the instance's).
- **std::cli**: clap's builder without derive. Flags (counted), options
  with defaults, positionals (required, multiple), subcommands; typed
  values (`get_as::<T>`, `FromStr`); generated help and `--version`;
  errors in one line with a did-you-mean `try:`; the Matches on an
  allocator (an arena); `parse` is `#[no_io]`. voltty reads its
  arguments with it.
- **Language and safety**:
  - `let` is a borrow: a copyable `let` parameter is passed by reference
    when the result may hold a view of it, so `DirEntry::file_name(self)`
    is back;
  - `str` and `Path` are views to the own pass (a distinct type has its
    underlying kind);
  - `gl(make())`: a call's or a struct literal's value given to a
    generic `let` parameter is a temporary;
  - `make().v`: a field moved out of a temporary is no longer freed
    again with it;
  - **a stopgap for a double free in safe code**: `iter()`, `keys()`,
    `values()` hand out copies of items the container still owns, and
    keeping one (collecting, storing, returning, sinking it) freed it
    twice. Such a keep is now `own.move_out`, with `try:` lines
    (`.iter_ref().map(|x| x.clone())`); it is broader than needed (a
    named fn given to `map`, a destructured closure item, are refused
    too) until iterator items are views.
- **Timing tests** (voltty's renderer, the sort and parser examples) no
  longer fail under a loaded machine.
- **Found by the release gate** and fixed: `volec test` took every
  `#[test]`, `#[property]` and `#[fuzz]` for a contract, so it replayed
  no saved fuzz crash (the test list's prefix was cut at the old name's
  length); `env::args()` reads the arguments and its iterator does no
  io, so std::cli's `#[no_io]` parse builds on Linux too.
- **Tested on aarch64 only**, as since 0.15 (`gate.sh --with-x86`).
- **Breaking**: every name: `volec`, `.vl` (a `.tach` file is not a
  source any more), `VOLE_*`; programs read through the stopgap above.
- **Known issues**: a closure's by-value parameters leak; the stopgap's
  breadth; the four missing-feature XFAILs; std::window's Linux
  backends are not written; std's core is 144 KB.

### What's new in 0.23

Windows and input in std, and a terminal emulator on them; the design
is docs/design/terminal.md, the guide `tachyonc guide window`.

- **std::window**: windows and their input in the manner of winit, with
  events pulled (`app.wait()`, `poll()`, `wait_timeout(ms)`) rather than
  pushed, on Cocoa: `Frame` once per `request_frame`, `Key` (physical
  and logical keys, both sides' modifiers, repeat), `Text` and
  `Preedit` (IME basics), `Resize` in physical pixels with the scale,
  `Mouse`, `Scroll`, `Cursor`, `Focus`, `Readable` (a file descriptor
  watched by `app.watch`), `Close`, `Quit`; cursor icons, the clipboard,
  live resize, and `raw_surface()` for std::gpu. It sits behind a gate:
  a program that does not name it reads none of it.
- **voltty** (examples/voltty), the terminal emulator:
  - core/: vte's parser, Alacritty's terminal state (two grids, 10,000
    lines of scrollback, reflow, charsets, colours, hyperlinks), the
    input encoders (keys, mouse reporting, bracketed paste, focus) and a
    pty; held to alacritty_terminal 0.26 by an oracle and a differential
    parser fuzzer (the gate's `voltty-fuzz`); 1.3x to 2.7x
    alacritty_terminal's throughput;
  - render/: Core Text glyphs in an atlas, one instanced draw of 16-byte
    cells per frame on std::gpu with `cells.wgsl` compiled by
    std::gpu::wgsl, damage tracking, no allocation per frame; a full
    redraw 43 us of CPU, at parity with the Metal stand-in it replaced
    (41 us);
  - app/: a shell on a pty in a std::window window, one event loop. A
    first cut: no selection, scrollback view or configuration yet.
- **The rename tools**, for 0.24's tachyon to vole: `rewrite --text`
  (text edits of the tree: words, case, regexes, only comments, strings
  or code of sources, paths moved, checked), `refactor extension` (files
  renamed as `git mv` does, their mentions changed, each program's build
  compared before and after), `query grep --ignore-case` (an f-string's
  text a string), releases.toml's `bin` and `ext`; tools/rename-vole.sh
  is the rename, dry-run so far.
- **Tested on aarch64 only**, as since 0.15 (`gate.sh --with-x86`).
- **Known issues**: the 0.22.1 list stands; std::window and voltty are
  macOS only (the Wayland and X11 backends are designed, not written);
  fonts come through Core Text, a rasterizer in the language is planned
  after 0.24.

### What's new in 0.22

GPU support in std, native-first, on wgpu's model; the design is
docs/design/gpu.md (with "0.22.0 as built"), the guide
`tachyonc guide gpu`, the examples examples/gpu/{compute,triangle}.

- **std::gpu**: instance, adapter, device, queue, buffers, textures,
  samplers, bind groups, compute and render pipelines, command encoders
  and headless surfaces, on wgpu's model but with tachyon's values:
  resources dropped by their destructors, allocation through allocators,
  the validation rules as `gpu.*` contracts. The Metal backend
  (`std::gpu::hal::metal`, behind `hal::Api`) on macOS, built on
  **std::objc** (typed `objc_msgSend` bindings generated from tables by
  tools/objcgen, checked against the runtime); link with `-l objc`.
  Runtime-sized arrays' bounds go in a sizes buffer given per dispatch
  and draw. The per-frame functions allocate nothing (tests/gpu checks
  it). Encoding 10,000 draws: 266 µs against Objective-C's 256 µs
  (1.04x) and wgpu 30's 498 µs.
- **std::gpu::wgsl**: a WGSL shader compiler written in tachyon (front
  end, IR, uniformity analysis, an interpreter as the oracle, MSL with
  bounds checks and WGSL's float-to-int bounds), with reflection (the
  bindings, per-stage slots, workgroup sizes). `Device::shader_wgsl(text)`
  and `shader::from_wgsl` go straight into a pipeline; tools/wgslc is
  the command line. On the bench's corpus it translates in 2.9 ms where
  naga 29 takes 8.3 ms.
- **Compile speed**: std's section index lists no impls behind a closed
  gate, so a small program reads 144 KB of std instead of 660 KB: a
  hello world 357 M to 96 M instructions (0.27x), a std-heavy program
  0.96x, check of the compiler 1.01x. A new gate row, `compile-cost`, fails at 1.5x (small
  programs) or 1.15x (the compiler) of the previous release; a test
  bounds std's core size.
- **Soundness**: `f(x?)` into a `let` parameter freed the value before
  the call; it is kept through it. std goes through the own pass
  (tests/std/own.sh, its known findings in tests/std/own.allowed);
  std::num's digit writers take their buffers `inout`.
- **Fixes**: `check` no longer overflows its stack on an unimported
  `AtomicI64` or `Ordering` in a scope's closure; `fn(T)` is the same
  type as `fn(let T)` (std's consuming bounds say `sink`); fmt keeps
  `Vec<[i64; 2]>` and the lines after it; tests/run.sh's `TIMEOUT`
  directive (lru-cache at -O0).
- **Tested on aarch64 only**, as since 0.15 (`gate.sh --with-x86`); the
  GPU tests run where Metal is (`REQUIRES: metal`).
- **Known issues**, for 0.22.1: the let-as-borrow rule; a closure's
  by-value parameters leak (dropping them double-frees HashMap
  iteration items); `gl(make())`; `std::take(&self)`'s try; a generic
  struct over an associated type is not yet supported, so a build has
  one GPU backend; the own pass reads a `Buf<ScopedArena>` as viewing
  what is pushed into it (six allowed findings in std::gpu::wgsl::msl);
  std's core, read by every program, is 144 KB (printing's lock pulls
  in 0.21's atomics and locks, std::gpu's gate keeps its `mod` sections
  core), its bound 160 KB until it is under 128 KB again;
  the Vulkan, D3D12 and CUDA backends are not written (designed in
  docs/design/gpu.md).

### What's new in 0.21

The compiler's own source moves to 0.20's conventions, the 0.19
spelling goes, and std gains threads; docs/design/conventions.md (§9.3,
"0.21") and `tachyonc guide threads`.

- **Threads**:
  - `std::thread::spawn` (a `move` closure on a new thread; its
    `JoinHandle`'s `join` gives the result) and `std::thread::scope`
    (every thread started in it is joined before it returns, so they may
    borrow the caller's values), both safe; `yield_now`,
    `available_parallelism`;
  - **what crosses threads is checked**: Send and Sync computed from the
    types (raw and fn pointers neither; containers, Mutex, atomics and
    channels by their type arguments; views only into scoped threads, and
    only shared views of Sync data); a spawned closure's captures and
    result are Send and hold no view; a scope changes nothing it borrows;
    no thread reaches a `static var` (an effect bit beside `global`);
    `sync.*` diagnostics with `try:` lines;
  - `std::sync`: `Atomic<T>` (Rust's `AtomicI64` ... `AtomicPtr` as
    aliases) with every ordering, `Mutex<T>` (`with` runs a closure under
    the lock; `lock`'s guard stays unsafe until Drop on view types),
    `RawLock` (a futex mutex), `Once`, `Condvar`, and `std::sync::mpsc`
    channels; `#[thread_local]` statics;
  - effects `thread`, `sync` and `tls`;
  - atomics on AArch64 as LSE (`cas`, `swp`, `ld<op>`, macOS) or
    exclusive-pair loops (`--atomics=lse|llsc`, Linux's default), checked
    by litmus tests (MP, SB) and per kind, width and ordering; on x86-64
    compiled and object-checked, not run; the optimizer treats atomics
    and fences as barriers (GVN, LICM, promotion, the vectorizers, load
    pairing) and invents no stores;
  - printing from several threads takes one lock around std's buffer.
- **compiler/src in 0.20's conventions** (about 11,000 lines in 329
  files by `fix --only conventions`, 13 raw pointers by hand); the
  output is the same.
- **The 0.19 spelling is gone**: the root pragma is
  `syntax.legacy_removed`, `--syntax=mixed` is `syntax.mixed_removed`;
  the mixed reading exists only inside the migrations (`fix --only
  conventions`, `fix --values`, `--only std015|alloc016`), so no build,
  check, run, try or query accepts Rust's borrowing spellings; `var`,
  `inout` and `sink` are keywords.
- **`.vl` sources and `VOLE_*` variables** are accepted beside `.tach`
  and `TACHYON_*`, for 0.24's rename (nothing user-facing renamed yet).
- **Tested on aarch64 only**, as since 0.15 (`gate.sh --with-x86`).
- **Breaking**: `var`, `inout`, `sink` are keywords (a name spelled so
  is an error); the 0.19 pragma and `--syntax=mixed` are errors.
- **Known issues**: the small-program compile regression of 0.20 (a
  hello world 47 M to 317 M instructions) is being investigated, for
  0.21.1; the 0.20.1 list of docs/design/conventions.md stands.

### What's new in 0.20

The designs are docs/design/conventions.md (with T1, T2 and Phase M "as
built") and docs/design/collections-text-io.md; the language in
docs/grammar.md, "Additions of 0.20"; the server in docs/lsp.md.

- **Parameter conventions in Hylo's spelling, the default syntax.** A
  parameter is `let` (the default, not written: borrowed, read-only),
  `inout` (exclusive; `&x` marks it at the call, and only it) or `sink`
  (the callee takes it); receivers `self`, `inout self`, `sink self`.
  `var` replaces `let mut`, `static var` `static mut`, `inout r = &v;` an
  exclusive local access. Accesses are transparent (`r.push(9)`, `n +
  1`; `*` only for raw pointers), and `&T`/`&mut T` leave the types: an
  access in a type is `let T` or `inout T` (`inout [T]` for `&mut [T]`).
  Rust's spellings (`&T`, `&mut x`, `&self`, `let mut`, `*r` on an
  access, `move ||`, `static mut`, `&&T`, `env::var`) are `conv.rust`
  errors with a `try:` line giving the new form.
- **The migration.** `fix --only conventions` rewrites a program (`--in`
  for the files a merge brought); `refactor signature --convention`
  changes one parameter. std, tests, examples, bench and the agent eval
  are in 0.20's spelling. User code is read in it by default
  (`--syntax=0.20`; `--syntax=mixed` reads both); compiler/src keeps the
  root pragma `// tachyon-syntax: 0.19` until 0.21, whose first commit
  migrates it.
- **std as a module tree** (std::hash, std::str, std::io, ...), with the
  refactor tools working on it, and a benchmark harness against Rust's
  std and C (bench/std: a .tach, .rs and .c triple per operation, the
  same checksum).
- **Collections**: `HashMap` and `HashSet` on a Swiss table (group
  probing, NEON on AArch64) with foldhash, and SipHash-1-3 for untrusted
  keys; `BTreeMap` and `BTreeSet` (a NEON probe within a node); the
  ipnsort and driftsort sorts; std::slice's algorithms.
- **Text**: an owned UTF-8 `String` and `str` views; std::unicode on
  Unicode 18's tables: UTF-8 validation, chars, grapheme clusters,
  display width, case mapping, with NEON fast paths; number formatting
  and parsing (Schubfach shortest round-trip for floats, dec2flt
  parsing, integers).
- **I/O and the system**: std::io (readers, writers, buffering), fs,
  path, env (`env::get`/`get_in`), process, std::time, std::random,
  std::sys.
- **Owned temporaries dropped at the end of their statement**, and moves
  of closure captures checked.
- **`tachyonc lsp`**: a language server written in tachyon (definition,
  references, document symbols, diagnostics with their `try:` lines,
  hover with types, effects and why, and CPU features), from the same
  tables as `query` and `check`.
- **Compiler fixes from the migration (Phase M)**: `match` of an access
  matches through it, and a match of a part it cannot take borrows it;
  a view taken through an access views what it designates; a String or
  PathBuf place goes where its view does; a closure literal given to a
  let parameter is lent from the caller's frame; `Iterator::at` takes
  `inout self` (its default advanced a copy); an assignment through an
  access drops the old value; fmt keeps `let T` in function types and
  `sink *T`.
- **Caught by the release gate, fixed before the tag**: at -O0 std's
  path functions passed C a pointer into a copy of their `SysPath`
  (`SysPath::ptr` took `let self`, a copy for a plain type in 0.20),
  and `DirEntry::file_name` returned a view of a copied entry: file
  names came out as NUL bytes and files were not found (std_io,
  sys_files, sys_process); the calls pass their local's address, and
  `file_name` takes `inout self`. bench/matmul had been migrated to
  `inout f64` parameters it reads as raw pointers (now `*f64`).
- **Tested on aarch64 only**, as since 0.15 (`gate.sh --with-x86`).
- **Breaking**: the 0.19 spellings (`&T`, `&mut`, `&self`, `let mut`,
  `static mut`, `move ||`, `*r` on an access) are errors in user code
  (`fix --only conventions`; `--syntax=mixed` for one release reads
  both); `env::var` is `env::get`; std's API changed with the module tree
  and the new collections and text types.
- **Known issues, for 0.20.1**: `fn(T)` and `fn(let T)` are different
  types in the checker (fmt keeps the `let`); a closure's by-value
  parameter is not dropped (a leak, as in 0.19.1); a generic `let`
  parameter given an rvalue of a non-copyable type other than a closure
  literal errors; `fix --only conventions` drops the `&` of an inout
  argument inside an f-string hole and mis-migrates `Iterator::at`'s
  convention in some impls; `query def` does not take back the
  symbols of std's statics (`tachyon.static.std.X`); std's own
  functions are not checked by the own pass (how the -O0 bugs above
  slipped through); a small std program compiles with about 270 M
  more instructions than with 0.19.1 (std's text built whole), and
  `check` of the compiler does 13% more.

### What's new in 0.19.1

- **Two soundness fixes** (code 0.19.0 accepted could write through a
  shared view):
  - the store intrinsics (`vst1q_*`, `vst1_*`, `vst2q_*`,
    `_mm_storeu_*`, `_mm256_storeu_*`) took their destination as a
    read-only `[T]`; it is `&mut [T]` now: a `[T]` there is
    own.readonly with its fix (`&mut a[..]`, `v.as_mut_slice()`), and a
    store into a buffer while a view of it is used is own.conflict;
  - 0.17's transitional rule that accepted a read-only `[T]` where
    `&mut [T]` is wanted (`sort(v.as_slice())`) is removed: such an
    argument is own.readonly, with the fix (`v.sort()`,
    `v.as_mut_slice()`, `&mut a[..]`, or `refactor signature F --type s
    '&mut [T]'`); `fix --values` ends with these fixes, and 51 call sites
    of the corpus moved.
- **examples/arch/sha256sum**: coreutils' `sha256sum` (output, `-c`,
  `--tag`, escapes, messages, exit codes) on the ARMv8 SHA-256
  instructions behind `detect("sha2")`, with a portable fallback. On an
  M5: 1 GiB in 0.352 s (3.05 GB/s) against macOS's sha256sum 0.428 s and
  OpenSSL 4.0.3's 0.399 s; 10,000 small files 0.119 s against 0.227 s.
  In the linux/arm64 container: 0.381 s against coreutils' 1.799 s and
  OpenSSL 3.0's 0.407 s. Built with v0.19.0's features.
- **Breaking**: a read-only `[T]` passed where `&mut [T]` is wanted, and
  a store intrinsic given one, are errors (`fix --values`, or the
  `try:` lines).

### What's new in 0.19

The design, its decisions (D1-D20) and each task's notes ("as built")
are in docs/design/arch.md; the language in docs/grammar.md, "Additions
of 0.19"; `tachyonc guide arch`; examples/arch.

- **`std::arch`**: CPU intrinsics under their vendor names, read from
  tables (`compiler/arch/*.def`: signature, features, instruction,
  encoding, folds, semantics, doc), declared on use (std's text does not
  grow). **AArch64: 1,775+ intrinsics**, NEON integer and float, crc,
  sha2, sha512, sha3, aes, pmull, dotprod; each is checked lane by lane
  against a scalar reference generated from its semantics, with constant
  and run-time inputs at every level (`arch-gen`), crypto by known
  answers, and objcheck agrees with cc on aarch64-macos and
  aarch64-linux. **x86-64: 484 intrinsics** (SSE to SSE4.2, AVX, AVX2,
  FMA, POPCNT, LZCNT, BMI1/2, AES-NI, SHA, PCLMULQDQ), encoded byte for
  byte as cc does (`tachyonc assemble`, tests/arch/enc.sh: 7,777
  instructions) and compiled for x86_64-linux and x86_64-macos, but
  **never executed**: x86 testing is off by the user's instruction, and
  docs/design/arch.md ("T5 as built") lists what runs once it returns.
  Memory forms take slices and are checked (`vld1q_u8(s, i)`), the raw
  pointer forms are in `raw::` and `unsafe`.
- **Vector types**: unsigned, 64-bit and 256-bit portable vectors (30 in
  all) with 0.10's operations and `T::from_bits`; NEON's types are their
  aliases, x86's `__m*` opaque; 256-bit vectors run on AArch64 as pairs.
- **Target features, inferred like effects**: a function needs the
  features of the intrinsics it calls, over the call graph;
  `#[target_feature(enable = ..)]` pins one; a call is legal where the
  callee's needs are known (the build's features, a declaration, or a
  flow-sensitive `has("x")`/`detect("x")` guard: the then-branch, `&&`,
  after `if !G { diverge }`, `assert(G)`); another architecture's
  features are constant false (its branches checked, never generated),
  which replaces `cfg`. `-C target-cpu=NAME|native`, `-C
  target-feature=+x,-y`; baselines apple-m1 on macOS (crc, aes, sha2,
  sha3, dotprod always there), Armv8.0 on Linux. `arch.*` diagnostics
  with `try:` lines.
- **Run-time detection**: `detect("sha2")` reads one cached word (sysctl
  on macOS, getauxval on Linux, cpuid and xgetbv on x86-64), filled
  before main or on first use in a library; `#[multiversion("sha3",
  "dotprod")]` makes a version per feature set behind a chain of detects;
  `TACHYON_ARCH_DISABLE` clears bits, and the suite runs every program
  that detects a second time with every feature off.
- **The optimizer**: intrinsics with an exact generic equivalent become
  the generic vector op; the others are pure `Intr` ops, numbered by GVN,
  moved by LICM (never above their guard), folded on constants; vectors
  are passed in vector registers in tachyon's convention (a call of a
  SIMD helper from 12 instructions to 2; a loop over one 2.12 G to 0.94
  G instructions).
- **Two undefined-behaviour bugs found and fixed before the release**:
  LICM hoisted a `crc32` guarded by `detect` above the detect (it would
  run on a CPU without crc), and could do the same with a 256-bit load;
  the guard rule now covers every instruction that needs a feature.
- **Tools**: `query arch WORDS [--feature F] [--equiv NAME]` searches the
  tables; `query def/show` of an intrinsic give its features,
  instruction, semantics and equivalent, and functions show `features:`;
  `query features --why`; `guide arch` with task recipes; 13 `explain`
  entries; the fuzzer's arch mode (`-A`); `tachyonc assemble`.
- **examples/arch**: bytesearch (NEON, as fast as libc's memchr: 0.12 s
  against a scalar 1.87 s) and crc32 (the crc instructions, as fast as
  clang's: 0.09 s against 2.21 s), with walkthroughs. Next, built with
  v0.19.0: examples/sha256sum on the sha2 instructions, against the
  system's sha256sum, openssl and coreutils.
- **Caught by the release gate, fixed before the tag**: on
  aarch64-linux at -O2, a program whose `main` takes a Gpa and reads
  argv crashed (examples/arch/crc32): main's feature word was filled
  before its parameters were taken, so the init (getauxval, inlined)
  overwrote argc and argv; it now goes after them
  (tests/run/arch_detect_main_args).
- **Tested on aarch64 only**, as 0.15 to 0.18.1 (`gate.sh --with-x86`).

### What's new in 0.18.1

The compiler on threads, incremental rebuilds, V4 and the 0.18 eval's
polish; docs/optimizer.md, "0.18.1: threads", "0.18.1: incremental
rebuilds", "Contracts and generated code: the evidence";
docs/design/contracts-verification.md §4.3, §4.4 and T7/T8's notes.

- **Two use-after-free holes in safe code, closed** (both accepted by
  0.18.0):
  - changing a bitwise copy of an owned value the original still points
    to: `match *e { E::B(v) => v.push(..) }`, `let w = v.get(i);
    w.push(..)`, `for w in vv { w.push(..) }`, or assigning such a
    binding, freed or grew the buffer behind the original's back. It is
    own.readonly now, with the fix (match the reference, or change the
    element in place);
  - `let r = &v[i]; v.push(..); *r` was not seen (the loan of
    `&v.as_slice()[i]` held no view): the loan views v, so the push is
    own.conflict.
- **Functions compiled in parallel**: `-j N` (default: the processors
  online, at most 8, fewer for a small program); the middle and back
  end's per-function state is a `FnCtx` per thread, the tasks (scalar
  pipeline, components bottom-up, emission) on a pool, the join in
  order, so the output is the same bytes for every N (tests/threads.sh,
  a gate step: every program at -j1/-j3/-j8). The -O2 self-compile from
  2.13 s (v0.18.0) to 0.72 s at -j8, -O1 0.87 to 0.37 s, -O0 0.35 to
  0.30 s (its assembler on a thread of its own).
- **Incremental rebuilds**: a task whose inputs (its functions' IR by a
  128-bit hash, what the program knows of them, the types, the compiler
  and the options) are those of an earlier build takes that build's
  output from the code cache (`target/`, `--cache=on|off`); rebuilding
  the compiler after a one-function edit takes 0.53 s at -O2 -j8 (0.47
  s with nothing changed), byte-identical to a clean build
  (tests/incremental.sh, a gate step: 148 series of edits). Off below
  8000 IR instructions and in the suite.
- **V4: every `*T` is raw.** The legacy rule (a non-`mut` `*T`
  parameter of a safe function borrowed as `&mut T`) is gone: borrowing
  is `&` and `&mut` only, and dereferencing a `*T` needs `unsafe`.
  compiler/src (358 `&mut` and 222 `&` parameters, 882 call sites, by
  `fix --values`; same-output on 8940 compilations) and std (about 90
  receivers; `read_line(&mut buf)`) moved; 0.18.0 code gets an error
  whose `try:` is `fix --values`, which keeps a pointer that is really
  raw (moved, compared, stored) raw. Not yet: the Allocator trait's
  `self: *Self` (0.19).
- **Contracts in generated code, measured** (bench/contracts against
  bench/contracts_plain, instructions): as 0.18.0 shipped them, clauses
  cost 8% more than none; with two range fixes (a length read as `len
  - 0`; one step of transitivity: `i < n` and `n <= v.len()` give `i <
  v.len()`), `x % n` ranges, and entry facts (a callee no caller inlines
  assumes its checked requires; indirect calls, C-callable and
  address-taken functions assume nothing) they save 25%: prefix -83%
  (vectorizes), dot -59%, bucket +15%, window +24% (its clause's form,
  `i + 4 <= len`, is not chained to `i + 1 < len` yet: one more check
  per call). The survey: 1670 checks left over bench and the examples,
  1564 now.
- **The 0.18 eval's polish** (docs/eval/0.18-polish-results.md: Haiku
  1.85 to 1.74 times Rust's cost, Sonnet 1.51 to 1.43, within noise
  overall; the heap task Haiku 2.52 to 1.53, Sonnet 2.11 to 1.26; Opus
  1.18, Fable 1.06): std's `BinaryHeap` and `MinHeap` in the prelude,
  `Vec::sort_by_key`, `retain`, `contains`, `first`, `(a..b).rev()`;
  Rust's default binding modes on references (`match e { E::A(n) => *n
  }` on `e: &E`); `&f(x)` and `&recv.method()` take temporaries;
  `let-else`; indexing through a reference; `ok: ...` when a check or
  build has no error; `guide std` a first page of the most used items;
  the check hook applies errors' exact fixes; `--emit-ir` to stdout;
  guide-mini answers what agents guessed; one `len()` in the corpus and
  the guide.
- **The gate**: a valgrind memcheck row in the aarch64-linux container
  (the compiler on the suite's programs); `threads` and `incremental`;
  bootstrap.sh's shared release cache under a lock.
- **Tested on aarch64 only**, as 0.15 to 0.18 (`gate.sh --with-x86`).
- **Breaking**: `*T` parameters are raw (V4): code that passed `&x` to
  a non-`mut` `*T` parameter and read through it without `unsafe` gets
  an error naming `fix --values`; std's receivers and `read_line` take
  references.

### What's new in 0.18

The design, its decisions, each task's notes and the integration with
0.17 ("as built") are in docs/design/contracts-verification.md; the
syntax in docs/grammar.md, "Additions of 0.18"; `tachyonc guide
contracts`, `guide testing`, `guide types#distinct-types`.

- **Contracts**: `requires` and `ensures` clauses between a function's
  signature and its body (functions, impl functions), `result` and
  `old(e)` in an ensures, `else "message"` or `else f"..."`, `debug`
  clauses checked only in test builds (and with `--debug-contracts`).
  The words are contextual: no program breaks. Always checked, exit 101:
  - a **requires is checked at the call**, after the arguments are
    evaluated, so the failure blames the caller's line, and names the
    clause: `main.tach:18:16: requires failed: 's.len() > 0' of 'median'
    (main.tach:2:5): s.len() = 0`;
  - an **ensures is checked in the callee** at each return (the body is
    moved to a companion function and its result checked):
    `main.tach:8:5: ensures failed: 'result <= hi' of 'clamp': result =
    6, hi = 5`;
  - a failing `&&` chain reports the conjunct that failed and the
    integer operands of its comparisons and calls;
  - conditions are pure by 0.16's effects (`contract.effect` with the
    call and a `query effects --why`); owned parameters are read in
    place, never moved; `old(..)` of a by-value owned parameter or of a
    view is `contract.old` (`old(v.len())`, `old(v.clone())`).
  - std states its preconditions as clauses (`Option::unwrap`,
    `Result::unwrap`, `Vec::get`, `set`, `swap`, `insert`, `remove`),
    with their old messages, now at the caller's line.
- **Assertions**: `assert`, `assert_eq`, `assert_ne`, `debug_assert` in
  the prelude (the bang spellings `assert!` and so on are accepted),
  each failure with its condition's text and values.
- **One failure line for every run-time check** (an index, a slice, `as
  E`, a vector lane, a contract, an assertion, `NonNull`): `FILE:LINE:COL:
  message`, from a site table the checks pass to the runtime; the `note:
  build with --trace` line is gone. Every path the compiler writes into
  what it makes (these positions, `--trace`, `--check-alloc`,
  `--check-unsafe`, `tachyonc test`'s labels, `-g`'s compile unit, whose
  `DW_AT_comp_dir` is now the root's directory) is relative to the root
  file's directory (`-g`'s `.file` names are that directory joined with
  it, so any assembler resolves them), so the output is the same whatever the current
  directory and however the root's path is spelled
  (tests/refactor/paths018). `--no-positions` makes every site 0,
  so code that only moved compiles to the same assembly.
- **The optimizer proves, never assumes**: a contract check is a check
  like a bounds check, removed only where the range analysis decides it;
  `tachyonc query checks FN|MODULE` (and `--print-checks`) lists each
  check left after the optimizer and those it removed.
- **Tests in the language**: `#[test]` functions (taking nothing or
  `gpa: Gpa`, returning `()` or a Result), `#[cfg(test)]` modules that
  see their parent's items without an import (`use super::*;` stays an
  error: no wildcard imports), `assert_snapshot(x)` against
  `tests/snapshots/`; test builds use `--trace` and `--check-alloc`, and a
  test that leaks fails.
- **Properties**: `#[property]` functions whose parameters are generated
  from their types (numbers, bool, text, Vec, Option, Result, tuples,
  Buf, the program's structs and enums through a made `Arbitrary`, or the
  program's own `impl Arbitrary` taking `&mut Gen`); 100 cases with
  growing sizes, each in its own process and leak-checked; a failure is
  shrunk and replayed with its inputs. A function with an `ensures` is
  tested as a property, its `requires` filtering the inputs.
- **Fuzzing**: `#[fuzz]` targets (a `[u8]` parameter is the input);
  `--coverage` counts the program's blocks; `tachyonc fuzz NAME` mutates
  inputs that reach new counts (AFL's buckets, splices, the program's
  string constants), shrinks a crash and saves it; `tachyonc test`
  replays the saved crashes.
- **`tachyonc test`** builds the program and its tests at -O2 and -O0,
  runs every case (`tests/NAME.in`/`.out`) and test in its own process,
  several at once, and compares the two levels: a difference is a `DIFF`
  line, the compiler's bug. Summary first, one line per failure with its
  trace, input and `try:`; `--accept`, `--cases`, `--seed`,
  `--no-contracts`, `--no-check-alloc`.
- **`tachyonc reduce` over programs**: `--differs` (-O0 and -O2
  disagree), `--fails 'TEXT'`, `--test NAME`; the program is cut by its
  layout (items, then statements) to a fixpoint, into `PROG.min.tach` (a
  planted miscompile in a generated 428-line program: 12 lines).
- **Distinct types**: `type X = distinct T` is a type of its own (Go's
  defined types): literals convert, `as` converts to and from T for free,
  T's operators and comparisons between two X, T's `Eq`, `Ord`, `Hash`,
  `Debug`, `Display` and `Clone` without an impl, none of T's methods
  (`impl X` adds its own); over plain types only (`distinct.kind`);
  mixing is `distinct.mix` with the conversion `fix --suggested` writes.
  The code generators never see one.
- **`std::NonNull<T>`**: `NonNull::new` (an Option), `as_ptr`,
  `p.is_null()` on any pointer; the null niche makes an enum of a
  fieldless variant and a NonNull one pointer, so `Option<NonNull<T>>` is
  8 bytes, C's nullable pointer and FFI-safe (layout, both back ends, the
  C ABI, `--emit-header`, the ABI fuzzer); C headers' `_Nonnull`
  pointers import as NonNull. `p as NonNull<T>` from a raw pointer is
  checked (`null pointer made NonNull`, exit 101), so safe code cannot
  make a null one.
- **std's traits on references**: `Display` and `Debug` take `self:
  &Self, f: &mut Fmt`, `Iterator::next` `self: &mut Self`, `Clone::clone`
  `self: &Self`; derive and the f-string lowering follow; an impl written
  the 0.16 way is still accepted by the legacy rule. `fix --values` now
  rewrites a program's own traits with every impl together, and respells
  impls of std's traits as their declarations; the examples, the eval's
  tasks, the tests and the guide are in the reference spelling (every
  test prints what it printed).
- **With 0.17's value semantics** (the integration's decisions, each
  tested): a requires check reads the call's arguments in place; an
  ensures may not read a by-value owned parameter (gone after the body)
  or keep a view in `old(..)`; distinct types are plain, so not over a
  reference or a type with `Drop`; `NonNull` is `distinct *T`, a value;
  generators take `&mut Gen`; property and fuzz cases are leak-checked;
  the test runtime and the fuzzer are lazy sections of std.
- **The agent eval**: `+debrief` (after the task, the same session is
  asked what confused it, which diagnostics helped or misled, what it
  would change, and three ratings; its cost apart), `run.py debrief`,
  `costx`, `binaudit`, and the 0.18 plan (216 runs).
- **V4 decided** (the user, 2026-10-16): once the compiler's source has
  moved to `&`/`&mut` (0.18.1), the legacy rule that a non-`mut` `*T`
  parameter is a borrow goes, and every `*T` is raw.
- **Caught by the release gate, fixed before the tag**: the check-site
  table wrote paths as given, so the compiler built on aarch64-linux
  differed from the cross-built one (paths relative to the root's
  directory, tests/refactor/paths018); GNU as refused the companions'
  `f?pre` symbols (`f$pre` and `f$body` now, tests/refactor/symbols018);
  nonnull_cimport needs clang (`// REQUIRES: clang`, a new directive);
  iterchain ran 5.8% more instructions than with 0.17.0, its dot loop
  unrolled twice instead of four times because a constant only a check's
  cold failure reads counted in the unroller's size (no longer,
  tests/run/opt_unroll_exit_consts); and realpath per source file had
  made compilations slow under a large directory.
- **Tested on aarch64 only**, as 0.15 to 0.17 (`gate.sh --with-x86`).
- **Breaking**:
  - std's `Display`, `Debug`, `Iterator` and `Clone` are declared with
    references; 0.16-style impls (`self: *T, f: *Fmt`) still compile
    (`fix --values` respells them);
  - `unwrap` and `Vec::get`/`set`/`swap`/`insert`/`remove` failures are
    reported at the caller's line, and every run-time failure is one line
    with a position (programs that compare stderr see the new line);
  - a failure's position, and `--trace`'s, `--check-alloc`'s and
    `-g`'s file names, are relative to the root file's directory, not
    to the directory the compiler ran in;
  - the prelude gains `assert`, `assert_eq`, `assert_ne`,
    `debug_assert`, `assert_snapshot` (a program's own names hide them);
    `test`, `property`, `fuzz` and `cfg(test)` are attributes.

### What's new in 0.17

The design, its decisions, the prototype's measurements and each task's
notes ("as built") are in docs/design/value-semantics.md; the language
in docs/grammar.md, "Additions of 0.17: familiar forms" (references,
moves and drops, std on values, the familiar forms); `tachyonc guide
memory`, `guide views`, `guide debug`; the optimizer's side in
docs/optimizer.md, "0.17: value semantics in the optimizer", "0.17:
compile time" and "0.17: cheaper f-strings"; the eval iterations in
docs/eval/0.17-iterations.md.

- **Moves and drops**: a value of an owned type (a `Vec`, `Buf`,
  `HashMap`, a type with `Drop`, a struct, tuple, enum or array holding
  one) moves on `=`, a by-value argument, `return`, a struct literal's
  field and a `move` capture; the source is dead until it is assigned
  again. Values are dropped at the end of their scope, in reverse order,
  on every exit (`return`, `break`, `continue`, `?`), as implicit defers
  the checker places: `Drop` (`fn drop(self: &mut Self)`, in the
  prelude) first, then generated drop glue (field by field, a `match`
  for enums, a loop for arrays, a `move` closure's captures); a local
  moved on some paths only carries a drop flag; assigning an owned place
  drops its old value; a discarded owned temporary drops at the end of
  its statement. `drop(x)`, `forget(x)` (leaks are safe), `needs_drop::<T>()`,
  `std::take`, `std::replace`, `T: Copy` for plain types; there is no
  `Copy` derive: what owns nothing copies, and is `Clone` without an
  impl. A view type cannot implement `Drop` (`own.drop_view`). Errors:
  `own.moved` (a use after a move), `own.move_out` (out of an index, a
  reference, a static or a borrowed binding, including a copy of an
  owned element out of `get`/`last`/`unwrap`: `try:` `x.take()`,
  `.clone()`), `own.partial`.
- **References and views**: `&T` and `&mut T` (`&x`, `&mut x`, both
  tracked; `let r = &x; r.f` is safe), `&mut [T]` the exclusive slice
  and `[T]` the read-only one. They are second-class: no lifetimes are
  written, and the checker (`front/own`, on the typed AST, after effects)
  keeps every view inside what it views: nothing writes, moves or drops a
  place while a view or loan of it is used later (`own.conflict`: a push
  while a slice of the Vec is live, a `for` over `v` pushing to `v`,
  `f(&mut a, &a)`); no view outlives its owner (`own.escape`); writes
  through `&T` and `[T]` are `own.readonly`; statics hold only views of
  constant data and are invalidated by `global` calls (`own.static`).
  Origins have two levels (what a value views, and what the views it
  holds view), so a `Vec<[u8]>` of tokens is not a view of itself;
  `&mut self` receivers are two-phase (`v.push(v.len())`); a `&mut` local
  passed on is an implicit reborrow; liveness is implicit (a view not
  used again is no conflict); disjoint fields do not overlap. `==` and
  `<` on two references compare the values (raw `*T` compare addresses).
  A non-`mut` `*T` parameter of a safe function is checked as `&mut T`
  through 0.17 (the legacy rule the compiler's own source relies on),
  and a `[T]` is accepted where `&mut [T]` is wanted, taking the
  exclusive loan.
- **Inferred view summaries**: each function has one, as it has effects:
  which parameters its result points into (`views(s)`, `views(self)`,
  `views(*self)`: carries the views `self` holds) and what its `&mut`
  parameters may come to hold (`stores(word)`), computed callees first
  over the effects' components (a recursive component to a fixed point),
  generic results parametric in their type arguments, filtered by type,
  indirect calls the join of the functions of their type whose address is
  taken. `#[views(..)]` and `#[stores(..)]` pin one (`own.views` when the
  body exceeds it). They are why a parser that keeps views of its input
  checks clean: the first design's one region per signature rejected 3.4%
  of the eval's functions; summaries reject none of them.
- **`--values`**: `error` is the default (moves, drops, views and
  exclusivity are errors, and the optimizer uses them); `warn` and
  `report` keep 0.16's semantics (no drops) and warn or list; `off` turns
  the pass off. The opt-outs are for 0.17 only.
- **The optimizer** (docs/optimizer.md): under `--values=error` a `&mut
  T`/`&mut [T]` parameter shares no memory with another reference
  parameter or a static, a `&T`/`[T]` one nothing written through it is
  read-only, and a reference parameter passed to no call is not written
  by calls; gvn, licm, slp and the vectorizer use it (`--no-noalias`,
  `--vec-stats`): the vectorizer's run-time overlap tests go (stencil 4
  to 0, matmul 2 to 0, 18% and 21% fewer lines), and a kernel of 8
  streams past the 16-pair limit vectorizes, 2.06 times faster. NRVO
  builds a returned local in the caller's result; a move in a loop is a
  copy elided. Drop glue and std's `drop` impls are `#[inline]`, so the
  drops cost what the hand-written frees did.
- **std on values**: `Vec`, `Buf` and `HashMap` implement `Drop`
  (elements dropped when they need it); `free(self)` consumes (`defer
  v.free()` stays legal and is no longer needed); `v.take()` empties and
  keeps the allocator; read-only methods take `&Self`, changing ones
  `&mut Self`; `as_mut_slice`, `s.swap(i, j)`, `v.sort()`, `s.sort()`,
  `iter_ref`; `sort`, `sort_by` and the stable sorts take `&mut [T]` and
  move elements as bits (owned elements sort; sort's code 2386 to 1887
  lines); `Vec::filled_in` clones; `HashMap::get_mut` and
  `get_or_insert` give `&mut [V]`; `Eq`, `Ord` and `Hash` take `&Self`
  (derive follows; a 0.16 impl's `*Self` is taken as `&Self`); Scanner,
  the iterators, split, trim and Fmt are views with pinned summaries.
- **`tachyonc fix --values`**: a `*T` parameter becomes `&mut T` when
  the function writes through it (transitively, to a fixed point over
  the program) else `&T`, and its calls' `&x` `&mut x`; a written slice
  parameter `&mut [T]` (`v.as_mut_slice()`, `&mut a[..]` at the calls);
  an owned parameter only read `&T` with `&v` at the calls; `defer
  x.free()` deleted. It moved 108 of the 380 tests/run programs, 30 of
  the 39 agent-eval programs, 35 of the 43 examples and 11 of the 20
  bench programs; the rest by hand (written slice locals, handle copies,
  bigint's operators, ledger's two `get_mut`). Every tests/run and
  example case prints what it printed, every bench program gives the
  same output, check-tasks grades every solution as before, and
  `--check-alloc` reports fewer leaks (drops free what programs leaked).
- **For agents**: every `own.*` diagnostic is one line with both
  positions, a `help:` with the replacement text and `try:` lines that
  run as they are (`edit patch`, `refactor signature --type v '&Vec<T>'`,
  `query own`); tests/own-try runs each `try:` of 15 situations (§2.9's
  six, the rarer conflicts, the agents' patterns that must not be
  rejected) and checks the program after it. `tachyonc query own
  FILE:LINE:COL` (each local's kind, where it moved, the views it holds,
  what invalidated them), `query views NAME|TYPE|MODULE [--why]`,
  `views:` in `def`, `show` and `context`, `--print-views`, `explain
  own.*` (every code with its fix), `refactor signature --type` and
  `refactor field --type` to references, `fmt` on `&&T`.
- **Familiar forms** (the night of 10-15's agent-efficiency work,
  measured in docs/eval/0.17-iterations.md; grammar.md "Additions of
  0.17: familiar forms"): `&mut x`; a larger prelude (`Buf`, `HashMap`,
  `read_line`, `Scanner`, `trim`, `sort`, `sort_by`, the stable sorts,
  `parse_int`, `Fmt`, `panic`, `unreachable`, ...; std loaded only where
  one is used); `panic(msg)` and `unreachable()`, safe, exit 101; `v[i]`,
  `v[i] = x`, `v[a..b]` on Vec and Buf, checked; `p[i]` on any pointer
  to a Vec, Buf or slice indexes the pointee, decided by the type as
  written (safe through a borrow, `unsafe` through a raw pointer, whose
  error names `(*p)[i]`; `p[0]` on a `*i64` names `*p`); `p.0` through a
  pointer; `s.len()` on slices and `a.len()` on arrays, `v.len` read as
  `v.len()`; module paths in code (`lexer::next(..)`, `lexer::Tok { ..
  }`, patterns) resolved as `use` lines are, beside the module then at
  the root, `ambiguous module` with both `crate::` paths when they
  differ; struct-like enum variants (`E::V { a, b }`, in patterns too);
  `b.push_str(f"..")`; constant range bounds in patterns; Rust labels get
  their tachyon spelling as `try:`.
- **Diagnostics with their fix**: name and API errors carry exact `try:`
  lines (imports, std's function forms, Rust's types, missing match arms
  to paste, argument lists, conversions); `tachyonc fix --suggested`
  applies every error's recorded fix as one checked, undoable edit
  (`--at FILE:LINE`, `--dry-run`); `let f = &factorial;` is "a
  function's name is already a pointer to it" with `try: factorial`
  (issue #1), `(*g)(4)` on a fn value `try: g`.
- **Debugging tools**: `--trace` (a shadow stack: a failed check, a
  panic, SIGSEGV, SIGALRM, SIGINT print the frames with the statement
  each runs; about 25% slower when on, nothing when off); `tachyonc probe
  FILE:LINE EXPR...` (values at a line as the program runs, from copies
  of the files); `tachyonc reduce FILE --until CMD` (line-based delta
  debugging); `tachyonc test` (a program's `tests/NAME.in`/`.out` cases,
  a compact summary within a token budget; in the tachyon tree, failures
  marked new or failing too); `guide debug` (a five-step recipe).
- **The tools for agents**: a 2k-token core guide, example-first, and a
  tiered AGENTS.md; `guide how` recipes, `query similar`, `query
  examples`; std edited by name (`edit patch std::trim`) with std
  re-embedded; the hooks rewrite a read of `.tach` source into its query
  instead of blocking it, a Stop hook checks every program a session
  touched, the check hook reports new errors as a delta and runs `tachyonc
  test`; edit, refactor and rewrite fixes from the shortfalls agents
  recorded in 0.15 and 0.16.
- **Compile speed** (docs/optimizer.md, "0.17: compile time"): a profile
  of the self-compile and its hot spots fixed (the returns-twice scan
  from 32% of -O2 to 1.7%, block layout, dominators, call pieces, fixed
  intervals, the assembler's parsing); the IR's ids local to each
  function and a per-function pipeline (each function lowered,
  optimized, emitted and freed before the next: the prerequisite for
  per-function arenas and threads in 0.18); -O1 inlines small leaf
  functions; an f-string passed straight to `print`, `println`,
  `format_in` or `push_fmt` is written in place, without a closure, an
  `Interp` instance or a generic instance. Measured in "Benchmarks",
  0.17 (docs/roadmap.md).
- **The own pass's cost**: 6.3% of the type checker on the compiler's
  source, after the checker records what the pass's fast path needs (the
  checker itself 2% slower for it): about 8.5% over 0.16's checker in
  all, against the 8% budget. Accepted for 0.17.0; recovering it is a
  0.17.1 item.
- **The agent eval**: ten small iterations after the 0.17 validation
  round (docs/eval/0.17-iterations.md): a ~600-token guide with a
  read-the-code-first line, the familiar forms (Sonnet's name errors
  0.57 to 0.14 a run), the query-first hook's rewrites (blocks 21 to 8
  per 16 runs), indexing through `*Vec` (Sonnet on task 03 from 3.6-4.7
  to 2.1 times Rust's cost); refuted: a worked program in the prompt.
  Against Rust, Sonnet is at 1.4 to 1.9 times the cost on these tasks,
  Haiku at 1.7 to 2.3.
- **Caught by the release gate, fixed before the tag**: the SLP
  vectorizer's tables by instruction were sized once at the pass's
  start; with ids local to each function, a small function whose packing
  added more than half again its instructions wrote past them (glibc
  stopped the compiler on aarch64-linux; tests/run/opt_slp_grow, reduced
  from opt_slp with `tachyonc reduce`); the own pass read before its
  place masks when a dropped local had no place (a function past 64
  places: a "Bus error" once on macOS, an invalid read under valgrind;
  tests/run/own_many_places); objcheck now builds each program with its
  test case's `// FLAGS:` and leaves out XFAIL cases, read by the suite's
  own reader (tests/directives.awk). The compiler is clean under
  valgrind on aarch64-linux on the `opt_*`, `own_*` and `fmt_*` tests,
  the bench programs and its own -O2 self-compile.
- **Tested on aarch64 only**, as 0.15 and 0.16 (`gate.sh --with-x86`).
- **Breaking** (`tachyonc fix --values` moves 0.16 code; what it cannot
  is an error with the place and `try:` lines):
  - owned values move: a use after `let w = v`, after passing `v` by
    value, is `own.moved` (`&v`, `.clone()`); a copy of an owned element
    out of a Vec, a reference or an accessor is `own.move_out`
    (`take()`, `clone()`);
  - views are checked: a slice or reference used after its owner was
    written, moved or dropped, returned out of the function owning its
    memory, or two loans of one place in a call, are errors; `--values=warn`
    is the one-release opt-out;
  - `&x` is a tracked reference, not a raw `*T` (`let p: *T = &x;` for a
    raw one); `&x` where `&mut T` is wanted is an error naming `&mut x`;
  - slices are read-only: writing through a `[T]` parameter is
    `own.readonly` (`&mut [T]`, `v.as_mut_slice()`);
  - std: `free` consumes; sorts take `&mut [T]`; `Eq`/`Ord`/`Hash` take
    `&Self`; `HashMap::get_mut` gives `Option<&mut [V]>`;
  - `p[i]` on a raw `*Vec<T>`, `*Buf` or `*[T]` indexes the pointee (it
    was pointer arithmetic), in `unsafe`;
  - the prelude gains the names above (a program's own `trim`, `sort` or
    `panic` still hides std's); `views`, `stores` are attributes.

### What's new in 0.16

The design, its work split and each part's notes are in
docs/design/effects-allocation.md; the language in docs/grammar.md,
"Additions of 0.16"; `tachyonc guide effects` and `guide allocators`;
the optimizer's side in docs/optimizer.md, "0.16".

- **Effects**: every function has an inferred set of effects: `alloc(A)`
  (which allocators it allocates from: `alloc(Gpa)`, `alloc(Arena)`,
  `alloc(extern)` for C's malloc), `io`, `global` (reads or writes a
  static), `panic`, `diverge` (may not return: a `while` or `loop`, or
  recursion; a counted `for` returns), `unsafe`. Generic functions per
  instance; calls through `fn` values and closures by the functions of
  that type whose address is taken; C functions by a table of libc
  (libm and `mem*` none, malloc `alloc(extern)`, stdio `io`, exit `io
  diverge`) or their declarations. An allocator's own methods are its
  business: a call of `a.alloc(..)` is `alloc(Arena)`, not the Gpa the
  arena refills from; `arena_scope(gpa, f)` and `a.scope(f)` are the
  closure's effects minus its scoped arena, plus the parent's. `tachyonc
  query effects NAME` (`--has EFFECT`, `--why EFFECT`: the chain of calls
  down to the source, one line a step; a module), and `query def`, `show`
  and `context` print `effects: ...`.
- **Declarations, checked**: `#[pure]` (no `alloc`, `io`, `global`),
  `#[no_alloc]`, `#[no_io]`, `#[no_panic]`, `#[effects(alloc(Gpa),
  panic)]` (an upper bound), on functions, trait functions (binding every
  impl, derived ones too) and C declarations (trusted); bounds `F: Fn(i64)
  -> i64 + effects(panic)` checked where `F` is given. std's `Eq::eq`,
  `Ord::cmp` and `Hash::hash` are `#[pure]`. A broken declaration is one
  error naming where the effect comes from (`'f' is #[no_alloc], but it
  allocates from Gpa: 'v.push(x)' at a.tach:7:9 grows a Vec<i64>`) and the
  `query effects --why` command. `--verify-effects` checks the IR's
  calls of C and stores to statics against the inferred sets.
- **Allocation is explicit**, as in Zig: nothing allocates without an
  allocator. `fn main(gpa: Gpa)` (the last parameter after `argc, argv`)
  is where a program's general-purpose allocator comes from; it is passed
  down as a parameter (`Vec::new_in(gpa)`, `with_capacity_in`,
  `filled_in`, `Buf::new_in`, `HashMap::new_in`, `collect_in`,
  `format_in`, `read_stdin_in`, `split_in`, `split_whitespace_in`,
  `sort_stable_in`); a container carries its allocator (`push` grows
  with it; `v.allocator()`). The `Allocator` trait (`try_alloc`,
  `try_resize`, `free`; `alloc`/`resize` stop on out of memory); `Gpa`;
  `Arena::new_in(gpa)` (bump allocation in chunks, the last block grows
  in place, blocks over 32 KB of their own; `used`, unsafe `reset` and
  `free_all`), `arena_scope(gpa, |a| ..)` and `a.scope(|s| ..)` (all of
  the scope's memory given back at its end), `FixedBuf::new(mem[..])`;
  `try_push`, `try_reserve`, `AllocError`. A `Fmt` never allocates
  (print's path reaches no allocator), so `println` works in
  `#[no_alloc]` code.
- **`#[sealed]` and `#[scoped]`**: std's `Vec`, `Buf`, `HashMap`, `Gpa`,
  `Arena`, `ScopedArena`, `FixedBuf` and `Fmt` are sealed: their fields
  are private to std and only std makes them (`v.len()`, not `v.len`);
  `ScopedArena` is scoped: no value holding it leaves its scope (returned,
  captured by another scope, put in a static). A static holds a
  container through a constant constructor (`static mut V: Vec<i64,
  Arena> = Vec::new_in(Arena::none());`, set up in main).
- **`--check-alloc`**: the program is built with a checking `Gpa` (any
  `-O`): every block on pages of its own, never reused, so a use after
  free, a double free, a free of a wrong pointer, size or allocator stop
  the program with where the block was allocated and freed; leaks are
  listed at exit (`gpa.live_blocks()`, `gpa.check_leaks()` in a test).
  Arenas and `FixedBuf` are checked the same way (a view used after
  `reset`, after its scope ended, after its Vec grew). With
  `--check-unsafe` too, raw-pointer accesses into Gpa's blocks are
  checked exactly.
- **The optimizer uses the effects** (docs/optimizer.md, "0.16"): calls
  of functions that read nothing are value-numbered by callee and
  arguments and hoisted out of loops (`willreturn` from counted loops,
  `nopanic`), read-only calls merged within a block; an arena's bump
  allocation inlines without a call (bench/arena_trees, binarytrees on
  std's arenas: 33 ms against C's arena 41, binarytrees on malloc 154);
  the algorithm examples' gaps: derived `Ord` in registers, `u32`
  without redundant extensions, `count_ones`/`leading_zeros`/
  `trailing_zeros` (std, AArch64's `cnt`), a widening multiply-accumulate
  vectorized (Benchmarks, 0.16).
- **Formatting without allocation and faster**: an f-string's integer
  hole with a spec is formatted in one pass, `Buf::push_int` writes in
  place (bench/fmtloop about 0.8 of 0.15's).
- **Link inputs on the command line**: `tachyonc main.tach helper.c
  lib.o -l m -L dir -o prog` compiles C files with cc and links objects
  and libraries; `-lm` is added on Linux when libm is used; `// LINK:` in
  tests. `-S` writes the symbols of generics instantiated at C types.
- **The tools**: `fix --only alloc016` moves a 0.15 program to explicit
  allocation (the calls of 0.15's allocating forms become their `_in`
  forms, `gpa: Gpa` threaded from main through every caller, before any
  parameter with a default; the reads of sealed fields become their
  methods; what cannot take a parameter, an impl of std's trait, a
  function used as a value, a default, a write of a sealed field, is an
  error naming the place); `query effects`; `rewrite` with `--subst`,
  `--list` and name holes, `query callees` (`--transitive`, `--writes`),
  refs of locals, `edit patch --nth/--all`; fmt and the refactorings know
  0.16's syntax and keep effect attributes; `same-output` finds the old
  compiler on PATH; arrays have their slice's methods (`a.iter()`).
- **Examples** (examples/README.md): one folder each, with a README
  (what it shows, how to build and run it, its output, a walk through the
  code, the guide topics): the old examples on 0.15 and 0.16 idioms, C
  interop (qsort with tachyon callbacks, a libc tour, libm, a C file
  linked in and C calling tachyon), language tours (closures and
  iterators, errors and results, traits and generics, formatting); the
  algorithm examples and the tool sessions on explicit allocation;
  examples/allocators (Gpa from main, an arena parser, scoped arenas, a
  fixed buffer, five memory bugs `--check-alloc` stops) and
  examples/effects (`#[pure]` and `#[no_alloc]`, effect bounds, trait
  purity, `query effects` for agents), each README a tested session;
  every example's test also runs under `--check-alloc` in the gate.
- **Fixed**: at -O1 a nested pattern naming an enum's only variant
  (inside `Ok(..)`) branched to a block that did not exist ("cannot
  assemble"); examples/errors-and-results printed an error holding a
  view of input it had freed.
- **The compiler's source** on 0.15's features (f-strings for its
  messages and text, widening, `any`/`all`, field shorthand, named
  arguments) in the back end, base, gen0 and part of the front end (the
  lexer, C import, derive, conversions, associated types, patterns,
  modules); the checker finds types and instances by hash (it scanned);
  six modules over 1000 lines split with `refactor split`; same-output
  identical throughout. The rest of the front end and the tools move in
  0.17.
- **The agent eval**: compiler tasks (an optimization, a cross-module
  rename, a checker fix, a std method) run with and without the tools
  (`--set`, `--reps`, `plans/0.16.md`).
- **Tested on aarch64 only**, as 0.15 (x86_64 off by default,
  `gate.sh --with-x86`).
- **Breaking** (`tachyonc fix --only alloc016` moves 0.15 code; what it
  cannot is an error with the place and what to write):
  - allocation is explicit: `Vec::new()`, `Buf::new()`,
    `HashMap::new()`, `with_capacity`, `filled`, `collect()`,
    `format(x)`, `read_stdin()`, `split`, `split_whitespace`,
    `sort_stable` are errors naming their `_in` form; `main` takes
    `gpa: Gpa` to allocate; a parameter's default cannot allocate;
  - std's containers are sealed: `v.len`, `v.cap`, `v.ptr`, `b.bytes` and
    `Vec { .. }` literals outside std are errors (the methods: `len()`,
    `capacity()`, `as_slice()`); with_capacity reserves exactly what it is
    asked (at least 4), no longer the next power of two;
  - the I/O API: `read_line(&buf)` takes a `Buf` of any allocator;
    `read_stdin_in(gpa)`, `split_in`, `split_whitespace_in`, `format_in`;
    `Fmt::to_buf` is gone (`buf.push_fmt(x)` with a `Display`);
    `Fmt::spec` returns a `FmtSpec`;
  - `Eq`, `Ord` and `Hash` impls must be pure (no statics, I/O or
    allocation: keep a comparator's state behind a pointer);
  - the prelude gains `Allocator`, `Gpa`, `Arena`, `ScopedArena`,
    `arena_scope`, `format_in`; `pure`, `effects`, `no_alloc`, `no_io`,
    `no_panic`, `sealed`, `scoped` are attributes.

### What's new in 0.15

The design, its work split and each part's notes are in
docs/design/errors-formatting.md; the language in docs/grammar.md,
"Additions of 0.15"; `tachyonc guide conversions` and `guide formatting`.

- **Errors and `?`**: `e?` on an `Option` gives the value or returns
  `None`; on a `Result` the value or `Err(e)`, the error widened or
  converted by the function's error type's `impl From`. Inside a closure
  it returns from the closure; defers run. `fn main() -> Result<(), E>`
  prints `Error: {e:?}` on stderr and exits with 1. Errors name what to
  write (`-> Result<i64, E>`, `e.ok_or(..)?`, the `impl From` to add).
- **Generic traits, `From` and `Into`**: traits take type parameters
  (`trait From<T>`), impls name concrete types or their own parameters,
  bounds pass arguments (`T: From<U>`); a call picks the impl by its
  argument types. `From` holds without an impl for the identity and for
  widening (`i64::from(x_i32)`); `x.into()` is `U::from(x)` with `U` the
  expected type. std's `Option`/`Result` helpers: `ok_or`, `map`,
  `and_then`, `map_err`, `unwrap_or_else`, `err`.
- **std's I/O on `Result`**: `read_line(&buf) -> Result<bool, IoError>`,
  `read_stdin() -> Result<Buf, IoError>`, `parse_int -> Result<i64,
  ParseIntError>`, `Scanner::next_int -> Result<i64, ScanError>`; the
  error enums have `Display` and `Debug`. Option means absence, Result
  failure. `tachyonc fix --only std015` moves 0.14 code (exact but for
  `read_stdin` on a read error).
- **Widening**: a narrower integer converts implicitly to a wider one of
  the same signedness, and unsigned to a wider signed one, wherever a
  value meets an expected type (lets, assignments, arguments, returns,
  fields, elements) and where two types meet (operands, `if`/`match`
  branches, two arguments of one type parameter: `max(a_i32, b_i64)` is
  `max::<i64>`); never inside other types, never narrowing, never
  between integers and floats. An expected type flows into arithmetic
  (`let t: i64 = a_i32 * b_i32` multiplies in `i64`). `i64::MAX`,
  `u8::MIN`, ... are constants of the integer types (std's `I64_MAX`
  ... are the same).
- **Formatting**: f-strings, `f"p = {p:?}, x = {x:>4}, {n:08x}"`
  (width, alignment, zero padding, precision, hex, binary, a byte;
  `{{`), evaluated where written, holes once and left to right; a value
  of type `Interp` that any `T: Display` takes. `Display` and `Debug`
  (`fn fmt(self: *T, f: *Fmt)`, `fn fmt_debug`), implemented for the
  numbers, `bool`, `[u8]` (Debug quoted and escaped as Rust's), `Buf`,
  and Debug for `Option`, `Result`, `Vec`, `HashMap`; floats print the
  shortest decimal that reads back. `print`, `println`, `eprint`,
  `eprintln`, `format` and `Buf::push_fmt` take any `Display`; output
  goes through one static 4 KB buffer, one `write` per print, no heap:
  `bench/fmtloop` (10^6 formatted lines) matches the same text built by
  hand (`bench/fmtints`). `println!` and Rust's `fmt(&self, f: &mut
  Formatter)` get the tachyon form in their help; a plain literal with
  `{name}` of a local passed to print gets a warning.
- **derive**: `#[derive(Eq, Ord, Hash, Debug, Clone)]` on structs and
  enums (generic ones too, each parameter bound by the trait): Ord
  lexicographic in declaration order, Debug as Rust's (`P { x: 1, y: 2
  }`), Clone field by field (a Vec deep). `Clone` in std; tuples of
  Eq/Ord/Hash/Clone types are those too (`sort` sorts tuples,
  `HashMap<(i64, [u8]), V>`); `sort_stable` and `sort_stable_by`.
- **Less boilerplate**: named arguments after the positional ones, in
  the parameters' order (`area(w, h: 2)`); defaults on trailing
  parameters of functions and inherent methods (`fn f(x: i64, step: i64
  = 1)`), evaluated per call in the callee's module; field shorthand `S
  { x, y }`.
- **`==` on `Vec`, `Buf` and `HashMap` compares contents** (Vecs element
  by element, maps by entries in any order); `==` on a `Vec<T>` needs
  `==` on `T`.
- **Compile time**: std is loaded by sections: an index made with std's
  source (compiler/std/index.awk) lets the loader lex only the sections a
  program reaches (Vec and printing always; HashMap, iterators, text,
  conversions, Clone when named or needed). A small std program compiles
  faster than with 0.14.0 although std grew from 46 to 90 KB (`Benchmarks`,
  0.15).
- **The tools for agents** (docs/tool-gaps-014.md, from the 0.14 eval
  and development record; docs/query.md, docs/refactor.md): `query
  context NAME` (the item, what it calls and uses, its callers, fitted to
  a budget); `--budget N` on every query, long answers cut with the
  command that gets the rest; std from any program (`query items std`,
  `show std::read_line` with the `use` line, `text std:A-B`, `grep --in
  std`, a name std defines asked again with std); every spelling a tool
  prints accepted back as a name; `tachyonc try 'STATEMENTS'` (a snippet
  compiled and run with std, its value and type printed); `guide --find
  WORDS`, `explain WORDS`; `tachyonc batch` (several commands in one
  call); `edit apply` (blocks per item, or `query show`'s output edited)
  and `edit patch` over several targets; `edit.breaks` saying what broke
  and the refactoring that would carry the change; `query conflicts` and
  `edit resolve` for merge conflicts in `.tach` files; `--json` on every
  command; builds off a terminal print the one-line errors; the check
  hook (tools/agent-hooks/check-after-edit.py: errors after every edit
  of a .tach file); tachyonc recognised through copies and variables,
  `target/tools/tachyonc`. fmt, query and the refactorings know 0.15's
  syntax (`signature --add 'x: T = V'` declares a default; `--fill-calls`
  is 0.14's behaviour).
- **Loops as cc compiles them** (docs/optimizer.md, "0.15"): a select in
  the middle end and if-conversion of small branches in innermost loops
  (`if x > r { c += 1 }` is a sum); masks and minimum/maximum reductions
  in the vectorizer; one accumulator per copy in the run-time unroller
  for associative integer reductions; the vectorizer's cost model weighs
  a 64-bit multiplication lane by lane against the unrolled scalar loop;
  `ldp`/`stp` pairs on AArch64. bench/iterloop (six kernels by hand) went
  from about 2.1 times cc -O2's time to about 1.0 to 1.1 (Benchmarks,
  0.15).
- **Examples**: examples/algorithms, ten algorithms (Dijkstra, Kruskal,
  topological sort, string search, Huffman, an LRU cache, big integers,
  quickselect, sudoku, n-queens) in idiomatic 0.15, each with a README,
  a C reference and a test; examples/tools, eight sessions with the
  tools (exploring unknown code, fixing errors, merge conflicts, proving
  a change unchanged, renames and moves, rewrites, signatures and
  variants, splitting a module), each README a transcript that
  tests/walkthrough/run.sh replays.
- **The compiler's source**: the back end, gen0 and base iterate with
  `IntVec::items()`, `kids(n)` and std's `any`/`all`/`position`/`find`
  (through `rewrite`, which gained `$s...` holes over a block's
  statements); same-output identical, self-compile time unchanged. The
  front end and the tools move in 0.16.
- **The agent eval, harder**: tasks 13-18 (porting a C compressor, a
  pass over an interpreter's AST, a multi-module CSV query engine, a
  tight perf limit, three run-time bugs, an API refactor); `run.py
  --check-hook`, and the errors left at the end in each result.
- **Also**: `query refs` no longer counts a trait's `Self` as a use of
  each type implementing it; a negated suffixed literal under an
  expected type (`let d: i64 = -9223372036854775808i64`) is no longer
  out of range.
- **Tested on aarch64 only**: 0.15's release gate ran on aarch64-macos and
  aarch64-linux; x86_64 (the x86_64-linux container) is off by default
  from 0.15 (`bootstrap/gate.conf`, `gate.sh --with-x86`). Its one run on
  0.15's tree failed only the new walkthrough sessions (a path in their
  transcripts, fixed after).
- **Breaking**: `read_line`, `read_stdin`, `parse_int` and
  `Scanner::next_int` return `Result` (`fix --only std015`); `==` on
  `Vec`, `Buf`, `HashMap` compares contents, no longer the pointer; the
  prelude gains `Display`, `Debug`, `Clone`, `From`, `Into`, `format`,
  `eprint`, `eprintln` (a program's own names come first); `f(label:
  loop { .. })` is a named argument; integer types that mismatched before
  may now widen (a program valid in 0.14 keeps its types).

### What's new in 0.14

- **Closures** (docs/grammar.md, "Additions of 0.14"; `tachyonc guide
  closures`): `|x| x + k`, `move`, `|x| -> T { .. }`, patterns as
  parameters. Each closure has its own type; an immutable variable is
  captured by value (by reference above 32 bytes or when the closure
  takes its address), a `let mut` one by reference, everything by value
  with `move`. `Fn(A) -> R` and `FnMut(A) -> R` bounds, monomorphized,
  type the closure's parameters and bind what their result names; a
  closure that captures nothing coerces to a `fn`. A value holding a
  closure that borrows a variable cannot leave that variable's block.
- **Associated types**: `type Item;` in a trait, `type Item = T;` in its
  impls, projections `T::Item` and `Self::Item`, `F::Output` of fn types
  and closures, constraints `I: Iterator<Item = T>` (checked, and used
  for inference); a trait default copied into a non-generic impl is
  checked and compiled only when used; `impl<T> [T]` and `impl<T> Tr for
  [T]` for slices.
- **Iterators** (`tachyonc guide iterators`): the `Iterator` trait in
  the prelude; `for` over slices, arrays, `Vec`, ranges, iterators and
  types with an `iter()` method, or a pointer to one; `a..b` and `a..=b`
  as values; std's sources (`v.iter()`, ranges, `HashMap::iter`, `keys`,
  `values`), adapters (`map`, `filter`, `enumerate`, `zip`, `take`) and
  consumers on `fold` (`for_each`, `count`, `sum`, `min`, `max`,
  `collect` into a `Vec`), `sort_by` with an `FnMut` comparison.
- **Zero cost** (docs/optimizer.md, "0.14: zero-cost iterators"): an
  iterator chain, once inlined, is the hand-written loop, with no call,
  no frame slot and the same vector loop: copy elision, SROA to a
  fixpoint, threading on constant tags, the merging of counted exits,
  #[inline] functions optimized after inlining, closures called once
  always inlined. `bench/iterchain.tach` (six kernels with std's
  iterators and closures) against `bench/iterloop.tach` (the same
  loops by hand): `bench/run.sh` fails above a ratio of 1.05.
- **std** (`tachyonc guide std`): `read_line(&buf)`, `read_stdin()` and
  a `Scanner` read stdin without `unsafe`; `parse_int`, `trim`, `split`,
  `split_whitespace`, `is_space`, `is_digit`; `Vec::last`, `swap`,
  `insert`, `remove`, `truncate`, `extend_from_slice`;
  `HashMap::contains_key`, `get_mut`, `get_or_insert` (a one-element
  slice: `counts.get_or_insert(w, 0)[0] += 1`); `sort` is an introsort
  (4M random i64: 302 to 195 ms). std's functions that the program does
  not reach are dropped before the optimizer.
- **Diagnostics for newcomers**: did-you-mean for methods, fields,
  associated functions, variants and module items; an unknown name that
  std has gets its `use` line (and `tachyonc fix` writes it), one with
  no close match points to `tachyonc guide std`; helps for Rust habits
  (macros, `&str`, `&self`, `?`, `String`, `.chars()`, ...); a private
  item's help makes it `pub`; errors past a failed condition are
  reported in the same pass; `const S: [u8] = "..."`; an unsuffixed
  literal takes the type of the other branch or arm; `mod eval; use
  eval::eval;` as in Rust.
- **Tools on a user's program** (docs/refactor.md, docs/query.md):
  `undo` and `query diff` without git; `refactor rename` of a local or
  parameter (`FILE:LINE:COL`, `FN::local`), its captured uses included;
  comment mentions renamed only in backquotes; `refactor variant --add
  --arm-in SITE EXPR`; `edit patch FILE:LINE` between items; edits add
  the imports their new text needs; `refactor --script` heredocs; import
  paths in the file's style. query, refactor, rewrite and fmt know
  closures.
- **The agent eval** (`tests/agent-eval/`, docs/eval/): twelve tasks
  (write, fix, extend, refactor, perf) with hidden tests and Rust twins;
  `run.py` puts Claude Code or an Ollama model on each task in five
  conditions and reports. The 0.13 baseline (Claude Haiku and Sonnet,
  59 of 60 runs each; a partial Qwen3-Coder run) and what it changed are
  in docs/eval/0.13-findings.md.
- **No undefined behaviour, fixed**: slicing (and vector loads and
  stores) read the slice after its bounds, so a bound that grew the
  storage read freed memory; `Buf::push_str` of its own view read freed
  memory; the compiler indexed its tables through calls that can move
  them (a wrong struct or a crash on generic literals). The gate's new
  `stress-grow` step moves every table growth of the compiler and
  checks the self-compile and the suite.
- **Also**: `==` on slices without std and on types holding a part with
  an `impl Eq`; bounds of declared types (`HashMap<i64, i64>` as a
  field) checked once every impl is known; generic instances limited by
  the size of their type arguments (chains of hundreds of adapters);
  worktrees share the main checkout's release cache.
- **Breaking**: nothing (`move`, reserved before, is now a keyword; a
  program's own `Iterator` comes before the prelude's).

### What's new in 0.13

- **Edits** (docs/refactor.md): `edit patch` takes an OLD that starts
  or ends inside a line, in every form, and says where a multi-line OLD
  stops matching; `--pairs FILE` reads the pairs from a file (and `try:`
  lines with pairs of several lines suggest it); `edit wrap TARGET --in
  HEAD` puts a body or a range of lines in a block, re-indented; `edit
  new-file PATH` writes a file and its `mod` line in one checked edit;
  `refactor signature --type x T --default EXPR` rewrites each call's
  argument; `fix --in MODULE` covers the module's children for every fix.
- **Queries** (docs/query.md): `query items MODULE --comments` lists the
  section banners and the comments outside items, `query show
  MODULE::section TITLE` prints a section; `query grep` searches the
  program's text, each hit with its item and whether it is code, a
  comment or a string; `query type FILE:LINE[:COL]` gives an
  expression's checked type; `refs` and `callers` print each
  reference's kind (read, write, call, init, type, use, mod, pat), and
  `--kind` keeps some. The hook suggests `query grep` for text searches.
- **A cache** (docs/query.md, "Speed: the cache"): a command that reads
  a program in full leaves its front end under `target/tachyonc-cache`,
  and `query def`, `show`, `refs`, `callers`, `items`, `check` and the
  reading of `edit` take it from there while the program's files are
  unchanged: about 6 to 8 ms on the compiler's source instead of about
  60. `TACHYON_CACHE` names another directory, or `off`. The answers are
  the same: the tools' tests run every transcript with and without it.
- **Refactorings** (docs/refactor-modules.md, docs/refactor-shape.md):
  `split --plan` names each part from its banner, the type its items
  operate on or a common prefix (`--names` gives them); `move --after`
  and `--before ITEM`; the blank lines around moved items and their
  banners kept, so a move and the move back leave every file as it was
  (tests/refactor/roundtrip.sh); `refactor extract-function FN --lines
  A-B --to NEW` (parameters and result computed) and `refactor inline
  FN` (a small function's body at its calls).
- **`tachyonc fmt`** (docs/fmt.md): one layout for tachyon source, with
  no options; a formatted text must lex to the same tokens and comments
  or the file is left as it is. Every edit, fix and refactoring lays out
  the lines it writes the same way. The tree is formatted (only blanks
  changed: `same-output` against 0.12.0 is identical), and
  tests/fmt/run.sh keeps it so. **`tachyonc explain CODE`**: what a
  diagnostic code means, how to fix it, an example, for every code the
  tools print and the compiler's error and warning kinds.
- **`tachyonc guide`**: the language for a reader who knows Rust, built
  into the compiler (the core guide about 5k tokens, `guide TOPIC`,
  `--list`, `--all`; std's API made from std's own source); every
  example in it is compiled and run by `tests/run.sh guide`.
- **Breaking**: nothing in the language. `query refs` and `callers`
  print a kind column in each line.

### What's new in 0.12

- **The compiler's source, reorganized** (compiler/README.md): six
  folders by phase (`base`, `front`, `middle`, `back`, `gen0`, `tools`),
  each with a README; the 25 files over 1,000 lines split by concern
  into folders of their own (77 files before, 172 now, none over 1,000
  lines: `tachyonc lint --max-lines 1000`); every import names the module that
  defines what it imports (no re-exports), the `use` lines merged,
  sorted and wrapped. Done with the compiler's own tools, almost every
  edit through them (docs/agent-tool-usage.md, 0.12), and proven to
  change nothing: `same-output` identical over 4,668 compilations, the
  0.12.0 compiler emits what 0.11.0 does.
- **Tools** (docs/refactor.md, docs/refactor-modules.md, docs/query.md):
  `edit patch TARGET --old --new` and `edit insert --in` (edits inside an
  item, by its text, checked and undoable), `--show`, `query diff`,
  `query text FILE:A-B`, `query show FILE` and a module's regions;
  `MODULE::use` and `MODULE::header` as targets of `edit patch`,
  `replace`, `insert`, `delete`; `fix --only tidy-imports` and `fix
  --only reexports` (`// api:` keeps a re-export); `refactor split
  --reexport` and `--header`, parts headed by their banner, runs of items
  kept together, banners moving with most of their group; `move` and
  `split` leave tidy imports. The agent hook judges writes by the files
  written, logs which agent made each record, and with
  `tools/agent-feedback` finds the log without running git.
- **The gate in one command**: `bootstrap/gate.sh --release` runs the
  chain, the suite at every level, the fuzzers and the Linux containers
  at once and prints one table; `bootstrap.sh --history fast` checks the
  older releases' fixpoints without their suites;
  `tests/fuzz/forever.sh` fuzzes between releases.
- **Breaking**: nothing in the language or the command line.

### What's new in 0.11

- **Debug information**: `-g` writes DWARF line tables (and the compile
  unit's functions) in the assembly and in the objects the compiler
  writes, Mach-O and ELF; on macOS `dsymutil` runs after linking. lldb
  and gdb stop at source lines and show `file:line` in backtraces. The
  output without `-g` is unchanged.
- **aarch64-linux** as a target (`--target aarch64-linux`: AAPCS64, ELF,
  `import` of its headers) and a host, whose compiler is cross-built on
  another host and then rebuilds itself there to the same object (see
  "aarch64-linux: cross-built, then checked natively" below).
- **Faster code**: a cost model for the loop vectorizer (expected trips
  from constant bounds or the profile, and against unrolling a short
  loop whole), unrolling of loops with run-time trip counts, an SLP
  vectorizer (stores to the lanes of a vector packed with their values),
  division and remainder by constants as multiplications, value ranges
  through phis (more bounds checks removed), branches on `&&` threaded,
  equalities from branches. `bench/` has six more programs (binarytrees,
  fannkuch, json, mandelbrot, sort, wordcount), each with its C version,
  and a geometric mean against `cc -O2`: tachyon -O2 is at 0.95 of it
  (docs/roadmap.md, "Benchmarks").
- **Tools for agents** (docs/query.md, docs/refactor.md and the pages it
  links): `tachyonc query` (`def`, `show`, `refs`, `callers`, `items`,
  `stats`, `deps`, `unused`, `impact`), `tachyonc check` (the front end
  only, one line per error), `fix` (missing and unused imports, `pub`,
  `unsafe` blocks), `lint --max-lines N`, `same-output OLD_TACHYONC`;
  `edit replace|insert|delete NAME` and `undo`; `refactor rename`, `move`,
  `new-module`, `move-module`, `split`, `signature`, `field`, `variant`,
  the typed `rewrite`, and `refactor --script`. Every edit is checked
  before it is written (nothing is written when it adds an error).
  `--diagnostics=short`: one line per error, with a stable code and a
  suggested fix. AGENTS.md and a hook for agents working on the compiler
  (`tools/agent-hooks/`).
- **Fixed**: `x as i64 < n` compares (a primitive type takes no type
  arguments); it failed with "expected '>'" when `n` was followed by `.`.
- **Breaking**: nothing in the language. On the command line, a first
  argument `query`, `edit`, `undo`, `check`, `fix`, `lint` or
  `same-output` is a command, not a file to compile.

### What's new in 0.10 (in progress)

- **Unsafe operations are errors.** An unsafe operation outside unsafe
  code is `error[unsafe]` (a warning in 0.9); `tachyonc --fix-unsafe`
  still adds the blocks. `--allow-unsafe` is gone (breaking): the
  compiler's own source is in unsafe code (whole function bodies in one
  block where a function has several unsafe operations), and the
  bootstrap builds 0.10 through the interface `tachyonc-0.10`, which does
  not pass it. Releases before 0.10 are built as before.
- **Vector types** `v2f64`, `v4f32`, `v2i64`, `v4i32`, `v8i16`, `v16i8`:
  lanewise arithmetic, masks, select, lanes, sums, checked loads and
  stores (grammar.md, "Additions of 0.10"); NEON and SSE2. Their names are
  reserved (breaking, for programs naming an item so).
- **Loop vectorizer** for counted loops over slices and arrays, guarded
  at run time; `--no-vectorize`; `tests/fuzz/run.sh -V`.
- **Profiles**: `--profile-generate FILE` and `--profile-use FILE` (block
  layout, inlining, unrolling).

### What's new in 0.10

- **`unsafe` is enforced** (breaking): an unsafe operation outside an
  `unsafe` block or `unsafe fn` is an error, not a warning. Safe code has
  no undefined behaviour. The compiler's own source moved to `unsafe`
  blocks (its output byte-identical before and after).
- **Vector types** `v2f64`, `v4f32`, `v2i64`, `v4i32`, `v8i16`, `v16i8`:
  lanewise arithmetic, masks and `select`, lanes, horizontal sums, and
  bounds-checked loads and stores; NEON on AArch64, SSE2 on x86-64. Not
  allowed in `extern "C"` signatures yet.
- **A loop vectorizer**: counted inner loops (maps, integer reductions)
  and the loop around one inner loop (matmul), behind run-time checks
  that prove the bounds and rule out overlap, the original loop kept as
  the remainder; `--no-vectorize`. Float reductions are not vectorized
  (that would reorder additions).
- **Profile-guided optimization**: `--profile-generate`, then
  `--profile-use FILE`; the counts steer block layout, inlining and
  unrolling.
- **`--check-unsafe`**: a checking mode for `unsafe` code.
- **Every error of a compilation is reported**: declarations recover one
  by one, and a syntax error no longer stops the type checking of
  everything else.

### What's new in 0.9 (in progress)

- **Unsafe code.** `unsafe { ... }` blocks and `unsafe fn`: dereferencing,
  indexing and slicing raw pointers, integer-to-pointer casts, calls into
  C and to `unsafe fn`, and reading union fields are allowed only there,
  so safe code has no undefined behaviour. Pointer parameters (and
  `self: *T`) are *borrows*, dereferenced in safe code; passing a raw
  pointer to one is unsafe. In 0.9 an unsafe operation outside unsafe
  code is a warning (`warning[unsafe]`; `--deny-warnings` makes warnings
  errors), an error from 0.10; `tachyonc --fix-unsafe` adds the blocks.
  The compiler's own source is built with `--allow-unsafe` (interface
  `tachyonc-0.9`) until 0.10 migrates it. std's `panic`, `print_cstr` and
  `Buf::push_cstr` are `unsafe fn` (breaking). The tests, examples,
  benchmarks and fuzzers are unsafe-clean, and the test suite compiles
  every case with `--deny-warnings`.
- **Traits.** `trait` declarations (with default functions), `impl Trait
  for Type` for any type, generic impls with bounds, bounds `T: Hash +
  Eq` on functions, structs and enums, checked at instantiation, one impl
  per trait and type. Static dispatch only (no `dyn`). Operators on user
  types through std's `Add`, `Sub`, `Mul`, `Div`, `Neg`, `Eq` (before the
  structural `==`) and `Ord`. std gains `Hash`, impls for the primitives
  and byte strings, `HashMap<K: Hash + Eq, V>` and `sort`. Unbounded
  generics are unchanged.
- Smaller: array constants, string literals in static aggregates, line
  continuations in string literals, `if`/`else` inference of `Some`/
  `None`, and `$TACHYON_CC` naming a cross C compiler for `import`.
- **E-graph.** GVN's table is an acyclic e-graph with a table of rewrite
  rules (a small pattern language) and cost-based extraction;
  `tachyonc --check-rules` checks every rule on random values at every
  integer width (tests/run.sh runs it).

### What's new in 0.9

- **`unsafe`.** Raw-pointer dereference, indexing and slicing, integer to
  pointer casts, calls to C functions and to `unsafe fn`, and reading a
  union's field need an `unsafe { ... }` block or an `unsafe fn`: safe code
  has no undefined behaviour (see [grammar.md](grammar.md), which also
  states the gaps left: slices outliving their storage). A pointer
  parameter that is not `mut` is a borrow, and dereferencing it is safe.
  In 0.9 an unsafe operation outside `unsafe` is a warning
  (`--deny-warnings` makes it an error, as every test does); from 0.10 it
  is an error. `tachyonc --fix-unsafe` adds the blocks. Breaking: std's
  `panic`, `print_cstr` and `Buf::push_cstr` are `unsafe fn`.
- **Traits**: `trait`, default functions, `impl Trait for T`, generic
  impls with bounds, bounds on functions and types (checked at
  instantiation), one impl per trait and type; operator traits `Add`,
  `Sub`, `Mul`, `Div`, `Neg`, `Eq`, `Ord`. std: `Hash`, `Eq`/`Ord`/`Hash`
  for the integers, `bool` and `[u8]`, `std::HashMap`, `std::sort`. No
  trait objects yet. Unbounded generics mean what they did.
- Array constants, string literals in static aggregates, `\` line
  continuations in strings, `Some`/`None` inferred across `if`/`else`;
  `$TACHYON_CC` names a cross C compiler for `import`.
- **An e-graph**: GVN works on an acyclic e-graph (as Cranelift's aegraph)
  with 31 rewrite rules in a small pattern language, the cheapest member
  of each class extracted; `tachyonc --check-rules` tests every rule on
  random values at every integer width (run by the test suite). It costs
  about 5% of `-O2` compile time.

### What's new in 0.8

- **No wildcard imports** (breaking). `use a::b::*;`, `use E::*;` and
  `import "h.h";` without `as` are errors: every name a file uses is
  declared in it, imported by name (`use a::b::{c, d}`), or written with
  its path; C headers are imported as `import "stdio.h" as c;` and used
  as `c::printf`. What a name means is visible where it is used. The
  prelude, a fixed list, stays.
- **`tachyonc --fix-imports FILE...`** rewrites code written for 0.7 and
  earlier: each wildcard becomes the list of names the file uses through
  it, each header import gets `as c` and its uses `c::`. The errors for
  the removed forms suggest the same rewrite.
- The compiler's own source, the tests and the fuzzers use explicit
  imports (380 wildcards replaced; the compiler built before and after
  is byte-identical).

### What's new in 0.7

- **Object files.** The compiler assembles its own output: Mach-O for
  macOS (arm64, x86-64) and ELF for Linux; `cc` only links. `-c` writes an
  object, `-S` (or `--emit-asm`) assembly, any other output an executable.
  The objects are checked against `cc -c` of the same assembly over the
  whole corpus (`tests/objcheck.sh`), and are identical whatever the host.
  The compiler builds itself to an executable in 0.6 s at `-O2` (2.7 s
  with 0.6.0) and 0.12 s at `-O0` (1.9 s).
- **Indexing a fixed array is checked** (breaking): `a[i]` on `[T; N]`
  panics like slice indexing (exit 101) when out of bounds; the optimizer
  removes the checks it proves unneeded.
- **No undefined behaviour** is now a principle of the language;
  [grammar.md](grammar.md) lists what is defined and the little that is
  not yet (raw pointers, C calls), which 0.8 puts behind `unsafe`.
- The bootstrap uses objects from 0.7 on (interface `tachyonc-0.7`; the
  fixpoint compares objects).

### What's new in 0.6

The compiler's own source is a module tree in the 0.5 language (generics
for its arrays, `Option` for lookups, enum variants by name), checked to
emit byte-identical output to 0.5.0. Releases from 0.6 on name their root
file in `bootstrap/releases.toml`.

The language (see [grammar.md](grammar.md), "Additions of 0.6"); two
changes are breaking:

- **String literals are `[u8]` slices** (they were `(*u8, u64)` tuples):
  `.ptr` and `.len`, and `println("hello")` works. `c"..."` is still a
  `*u8`.
- **Two `*` imports bringing different things under one name** make it an
  error where the name is used (0.5 took the first).
- `if let` and `while let`; `defer` (run when the block is left, last
  first, on every way out but a panic); `==` and `!=` on structs, tuples,
  arrays and enums with fields, field by field; a prelude (`Option`,
  `Some`, `None`, `Result`, `Ok`, `Err`, `Vec`, `print`, `println`
  without `use`, shadowed by anything the program declares or imports);
  `#[inline]`, `#[inline(never)]`, `#[cold]`; inline modules
  `mod m { ... }`; generic type aliases; attributes before `pub`.

The optimizer (see [optimizer.md](optimizer.md)): a whole-program layer
at `-O2`: interprocedural constants (arguments into internal functions,
results out) and devirtualization, inlining bottom-up over the call graph
with a cost model and budgets, function attribute inference (readnone,
readonly, noreturn, willreturn, nopanic, nocapture; `--print-attrs`) used
by GVN, LICM and dead code elimination, scalar promotion of memory in
loops, small non-escaping heap allocations moved to the stack, global
dead code elimination, value ranges of sums and products. The back end:
shrink-wrapping (the frame only on the paths that need it), coalescing
hints for phis, comparisons with immediates. `--time-passes` and
`--stats` measure the compiler and its output; compile times are part of
every release from now on (see [roadmap.md](roadmap.md)).

### What's new in 0.5

The language (see [grammar.md](grammar.md), "Additions of 0.5"):

- **Generics** by monomorphization, checked at instantiation: generic
  functions, structs, enums and `impl` blocks, methods with type
  parameters of their own; type arguments written (`Vec<i64>`,
  `max::<i64>(..)`, `Vec::<u8>::new()`) or inferred from the arguments
  and the expected type. An error inside an instance names the
  instantiation chain. Bounds (traits) are left for later; adding them
  will not change what today's programs mean.
- **Modules**: a file is a module (`mod m;` loads `m.tach` or
  `m/mod.tach`); items are private unless `pub`; paths with `crate`,
  `self`, `super`; `use a::b::{c, d as e}`, `use a::b::*`, `pub use`;
  `import "h.h" as c;` puts a header's declarations under `c::`. Several
  files on the command line still make one root module.
- **Several errors per compilation**: the parser and the checker recover,
  and errors that follow from an earlier one are not reported.
- **A small standard library**, built into the compiler: `std::Option`,
  `Result`, `Vec`, `Buf`, printing.
- `size_of` and `align_of` are always the builtins; `#[repr(C,
  align(N))]` up to 4096, and C records aligned above 16 import normally.
- The layout and calling convention of plain functions and default
  types stay unspecified: at `-O1`/`-O2` plain functions now use a
  convention of tachyon's own; everything C can reach keeps C's.

The back end (see [optimizer.md](optimizer.md)): register allocation by
linear scan on SSA with lifetime holes and interval splitting, coalescing
hints and rematerialization, checked by `--verify-regalloc`; a calling
convention of its own (16 integer and 16 float argument registers on
AArch64, aggregates in registers); realigned frames; instruction selection
by per-target rule tables (scaled-index addressing, `lea`, `madd`, shifted
operands, `ubfx`, `tbz`, `csel`/`csinc`/`cmov` selects, libm calls as
instructions where exact); block layout by fall-through with cold paths
last and tail duplication; `stp`/`ldp` and other post-allocation
peepholes; leaf functions without frames; sibling calls; `setjmp` and
other calls that return twice handled soundly. Tests: `ASM(T):`
directives, `ERROR-COUNT:`, several `ERROR:` lines; random programs in
generics, register-pressure and calls modes; `--emit-mir`.

### What's new in 0.4

The compiler's own source is written in the 0.3 language (enums and
`match` for every kind of node, token, type and instruction; methods;
slices; `extern "C"` blocks), checked to emit byte-identical output to
0.3.0 by `tests/compare.sh`, which compares two compilers over the suite,
examples, benchmarks, random programs and the compiler itself.

The language (see [grammar.md](grammar.md)); two changes are breaking:

- **A slice's `len` is `i64`** (it was `u64`); indexing accepts any
  integer type.
- **The 0.2 form `extern fn f();` is removed**; use `extern "C" { ... }`.
- **`import "stdio.h";`** reads C headers: a C preprocessor and a C
  declaration reader, with the target's own predefined macros and include
  path (from `cc`, or `$TACHYON_CC`), so a header means what it means to
  C. Structs and unions (bit-fields, `packed`, `aligned`, `#pragma pack`)
  become `#[repr(C)]` types, typedefs and enums aliases, enumerators and
  constant macros typed constants, asm-label renames `#[link_name]`;
  what tachyon cannot express (`long double` on x86-64, `_Complex`,
  `__int128`, inline functions...) is left out, with an error naming the
  reason when it is used. `-I` adds directories; `--emit-imports` shows
  the result.
- **`--emit-header`** writes a C header for a program's `extern "C"`
  functions and statics and the types they need, each checked with a
  `_Static_assert` of its size and alignment.
- `use E::*;` and `use E::{A, B};`; `const` of enum types and of `c"..."`;
  `n as E`, checked (an invalid value exits with 101); `<`, `<=`, `>`,
  `>=` on fieldless enums and variant ranges in patterns; `size_of(T)` and
  `align_of(T)`; `for x in s` over slices and arrays; raw identifiers
  (`r#type`); `#[link_name]`; `#[repr(C, packed(N))]`. `import` and `use`
  are keywords.

The loop optimizer (see [optimizer.md](optimizer.md)): loop canonical form
and LCSSA, rotation, induction variables and exact trip counts, full and
partial unrolling, unswitching, strength reduction of addresses, value
ranges (bounds checks they prove are removed, guarded `match` arms become
decision trees, chains of tests become switches), dead loop deletion,
aggressive dead code elimination, tail recursion elimination with
accumulators. Tests: a loop mode for the random program generator
(`tests/fuzz/run.sh -l`), the ABI fuzzer through `import` (`-i`) and
through `--emit-header` (`-H`), a layout check of imported C records
against `cc` (`tests/cimport/layout.sh`), a stencil benchmark.

### What's new in 0.3

The language grew (see [grammar.md](grammar.md)); one change is breaking:

- **Assignment evaluates its right-hand side first**, then the place (a
  compound assignment then reads the old value), as Rust does; before, the
  place's address came first. `a[i].x = f()` is now safe when `f` moves
  `a`.
- **Enums**, fieldless (with discriminants, castable to integers, compared
  with `==`) or with tuple variants; **`match`** with literal, range,
  constant, binding, wildcard, tuple, variant and or-patterns and guards,
  checked for exhaustiveness (a missing case is named) and unreachable
  arms; `let` and `for` patterns must be irrefutable.
- **Methods** in `impl` blocks (`self: T` or `self: *T`, with `&` and `*`
  added at the call), associated functions (`T::f()`), `Self`; a field
  through a pointer to a struct (`p.f`).
- **Slices** `[T]`: `a[lo..hi]` (and `..`, `lo..`, `..hi`, `..=`) of arrays
  and slices, checked, and of raw pointers, unchecked; `s.len`, `s.ptr`;
  checked indexing. A failed check prints `index out of bounds: index I,
  length N` (or the range) on stderr and exits with 101.
- **C interop** is explicit, as in Rust: `extern "C" { fn ...; static ...; }`
  imports, `extern "C" fn` definitions (unmangled, callable from C) and
  pointer types, `extern "C" static` exports, `#[repr(C)]` structs, enums
  (an `int` tag, then a union of structs) and unions, `#[repr(C, packed)]`,
  `#[repr(C, align(N))]`, `#[repr(u8)]` and friends for enum tags.
  Everything in an `extern "C"` signature must be FFI-safe, which the
  compiler checks. Aggregates follow C's calling convention exactly
  (AArch64 HFAs and x-register pairs, System V eightbytes, MEMORY,
  packed and aligned types, variadic calls). The 0.2 form `extern fn f();`
  is still accepted (deprecated, meaning `extern "C"`); the compiler's own
  source uses it until 0.4.
- **Default layouts and conventions are unspecified**: a plain struct's
  fields are now ordered to save padding; only `#[repr(C)]` types have C's
  layout.
- Reserved words `enum`, `match`, `impl`, `union` are keywords; `self` and
  `Self` are no longer reserved.

The optimizer (see [optimizer.md](optimizer.md)): scalar replacement of
aggregates, an alias analysis that follows addresses to their objects
through variable offsets, load and store forwarding along the dominator
tree, copies read through and removed, dead store elimination, constant
local tables moved to read-only data, a `switch` terminator with jump
tables and binary searches. Tests: `tests/run.sh` and the fuzzers run in
parallel (`-j`); `// STDERR:` and `// CSOURCE:` directives; the random
program generator covers the new language; `tests/abi/run.sh` checks C
interop with random signatures in both directions.

### What's new in 0.2

The language is unchanged (every 0.1 program compiles and means the same).
The compiler gained a middle end and a register-allocating back end,
described in [optimizer.md](optimizer.md):

- `-O0` is the 0.1 code generator; `-O1` lowers to an SSA IR and runs SCCP,
  instruction combining, CFG simplification, GVN with load and store
  forwarding, and dead code elimination, then allocates registers by linear
  scan; `-O2`, the default, adds inlining and loop-invariant code motion.
- `--emit-ir`, `--verify-ir` and `--print-after-all` show and check the IR.
- One fix that is visible: `main` without a result type now exits with 0
  (it exited with whatever was left in the result register).
- Tests: `tests/run.sh -O LEVEL`, IR checks (`// CHECK:`, `// CHECK-NOT:`,
  `// CHECK-OPT:`), random differential testing (`tests/fuzz/run.sh`).
- `bench/run.sh` times programs at every level against the previous
  release, the seed and C (`cc -O2`); results are in
  [roadmap.md](roadmap.md#benchmarks).

## Hosts

A host is where the chain runs; every release builds for the host it runs
on. `bootstrap/bootstrap.sh` detects it with `uname` and fails early, with a
message, on a host that some release in the chain does not support.

| host | machines | needs |
|---|---|---|
| `aarch64-macos` | Macs with Apple silicon | git, Rust (rustup), the Xcode command line tools (`cc` is clang) |
| `x86_64-macos` | Intel Macs | the same |
| `x86_64-linux` | x86-64 Linux with glibc | git, Rust (rustup), a C compiler with the libc headers (`gcc` and `libc6-dev` on Debian/Ubuntu, or clang) |
| `aarch64-linux` (from 0.11) | AArch64 Linux with glibc | a C compiler with the libc headers; the chain itself runs on one of the hosts above (see below) |

Every host also needs the POSIX utilities that any Unix has (`sh`, `awk`,
`sed`, `tar`, `cmp`, `mktemp`); the scripts use nothing beyond POSIX, and
no tool of another host (no clang on Linux, no macOS-only command).
`bootstrap.sh` lists every missing tool at once. `CC` selects another C
compiler.

Rust: install rustup (https://rustup.rs). The seed's directory pins Rust
1.98.0 in `seed/rust-toolchain.toml`, and rustup installs it on first use;
if your rustup does not install toolchains automatically, run
`rustup toolchain install` once inside `seed/`.

On Apple silicon, `bootstrap.sh --host x86_64-macos` builds and checks the
chain for Intel Macs, running the x86-64 binaries under Rosetta 2.

### aarch64-linux: cross-built, then checked natively

0.11 adds the target and host `aarch64-linux` (the standard AAPCS64, ELF,
position independent). The chain cannot start there: the seed (Rust with
Cranelift, pinned) has no aarch64-linux backend, and neither has any
release before 0.11, so no step before HEAD runs on it. Rather than a new
seed, the compiler for it is cross-built, which is sound because a
compiler's output does not depend on the host it runs on (the fixpoint
check proves it for every host it runs on):

1. On a host where the chain runs (aarch64-macos, x86_64-macos or
   x86_64-linux), `bootstrap.sh --host aarch64-linux` runs the chain as
   usual (HEAD built by the last release, its fixpoint and its test suite
   on that host), then has HEAD's compiler compile its own source for
   aarch64-linux: `target/aarch64-linux/volec.o`, the object of the
   compiler that runs there (`cc -o volec volec.o -lm` links it
   there). On aarch64-linux itself, `bootstrap.sh` stops with this advice.
2. On aarch64-linux, the cross-built compiler builds itself. The object it
   writes must be the cross-built one, byte for byte (the host made no
   difference), and the compiler so built must write it again (the
   fixpoint); then the test suite runs there, with the random programs,
   the C interoperability checks and the object check.

`bootstrap/aarch64-linux-check.sh` does both: step 1 where it runs, step 2
in a linux/arm64 Debian container (`bootstrap/ci/linux-aarch64.Dockerfile`;
native on Apple silicon, e.g. with colima):

```
$ bootstrap/aarch64-linux-check.sh --worktree --dev --all-levels --fuzz=100 --abi=40 --objcheck --debugger
```

With `--compiler C` it skips step 1's chain: C (built and tested here
from the same tree, as `bootstrap/gate.sh` does) cross-compiles the
tree's compiler.

In `releases.toml`, `aarch64-linux` is a host of HEAD (and so of 0.11 and
every later release), and of no release before; the releases before 0.11
and their checks are unchanged.

## Semantic versioning

The version is about the **language** the compiler accepts. While the major
version is 0, the language is not stable:

- **0.x minor** (0.1.0 → 0.2.0): new features, and possibly breaking
  changes (something that compiled is rejected, or means something else).
  The release notes in the table above say which.
- **0.x patch** (0.1.0 → 0.1.1): fixes only; every program that compiled
  still compiles and means the same.

From 1.0.0 on, the usual rules apply: patch for fixes, minor for compatible
additions, major for breaking changes.

Whatever the version, a breaking change goes through two releases because
of the release rule below: the release that makes the change is still
written in the old language, and only the next one may use the new one.

## The release rule

**The compiler source of a release may only use language features that the
previous release's binary supports.** The binary of release N-1 is what
builds release N on a new machine; if N's source used a feature N-1 does not
have, the chain breaks.

A new feature is therefore adopted in two releases:

1. Implement the feature in the compiler, keeping the compiler's own source
   in the old language. Add tests for it to the suite. Cut a release.
2. Only after that release exists may the compiler's source use the feature
   (in the next release).

`compiler/README.md` lists the language subset the current source uses.

## Cutting a release

Say the last release is 0.2.0 and you have implemented a feature on main.

1. Check the source rule: the compiler in `compiler/src` must still build
   with the previous release:
   ```
   $ bootstrap/bootstrap.sh            # builds the seed, 0.1.0 and 0.2.0, then HEAD with 0.2.0
   ```
2. Add the tests for the new behaviour to `tests/` (`tests/run/*.vl` with
   `// EXPECT:` ... directives; see `tests/run.sh`), and examples if useful.
   Update `docs/grammar.md` for language changes.
3. Bump the version string in `compiler/src/main.vl` (`version()`).
4. Add the release to `bootstrap/releases.toml`:
   ```toml
   [[release]]
   version = "0.3.0"
   tag = "v0.3.0"
   compiler = "compiler/src"
   root = "main.vl"          # from 0.6: the root of the compiler's module tree
   built_by = "0.2.0"
   cli = "volec-0.1"
   tests = "tests/run.sh"
   hosts = ["aarch64-macos", "x86_64-linux", "x86_64-macos"]
   summary = "What 0.3.0 introduced."
   ```
   and a row to the table above.
5. Run the gate (below, and [roadmap.md](roadmap.md)): the chain with the
   new entry, in working-tree mode (the tag does not exist yet, so the new
   release is the working tree), and every check, on every host it lists:
   ```
   $ bootstrap/gate.sh --release        # everything, at once (docker running)
   $ bootstrap/gate.sh --only bench     # then alone, on an idle machine: the benchmarks
   ```
   Then commit, and tag the commit: `git tag v0.3.0`. From now on,
   `bootstrap/bootstrap.sh` builds the seed, 0.1.0, 0.2.0, then 0.3.0 from
   its tag, then HEAD.
6. Now (and not before) the compiler's source may use the new feature.

### Who tests what (0.25.2)

Every run of the whole suite costs every agent sharing the machine, so
each level of testing runs once, by the one it names (AGENTS.md, "The
inner loop"):

1. an agent while working: `bootstrap/bootstrap.sh --dev --no-suite`
   (the build and its fixpoint, no suite), then the cases it touches
   (`tests/run.sh FILTER...`);
2. an agent before reporting: `tools/premerge.sh` and
   `tests/affected.sh` (the paths changed since the branch's base,
   looked up in `tests/affected.map`, run at -O0 and -O2; `--linux` in
   the aarch64-linux container when the change is platform-relevant);
3. the integrator, once per merge batch: the whole `tests/run.sh` and
   `bootstrap/gate.sh --quick`;
4. a release: `bootstrap/gate.sh --release`.

### The gate

`bootstrap/gate.sh` runs the whole gate in one command, as parallel as
the machine allows, and ends with one table (each step, its result and
time, a line about it) and the failures' details; it exits 1 when a step
failed. Its logs are in `target/gate/<date>/` (`target/gate/last`), one
file per step.

```
$ bootstrap/gate.sh --quick            # before committing a big change: chain, suite at -O2, a short fuzz, linux-smoke
$ bootstrap/gate.sh                    # every step, modest fuzz counts
$ bootstrap/gate.sh --release          # every step, the release's fuzz counts
$ bootstrap/gate.sh --no-linux         # without the containers (--quick: without linux-smoke)
$ bootstrap/gate.sh --quick --no-wait  # fail at once if another gate runs, rather than wait for it
$ bootstrap/gate.sh --self-test        # the gate's own machinery: the lock, the stall check, the modes' steps
$ bootstrap/gate.sh --with-x86         # with x86_64 (off by default since 0.15)
$ bootstrap/gate.sh --only 'fuzz-*,objcheck'   # some steps (--list shows them)
$ bootstrap/gate.sh --release --bench  # the gate, then the benchmarks alone
$ bootstrap/gate.sh --only bench       # only the benchmarks
```

The steps: `chain` (`bootstrap.sh --dev --no-head-tests`: the releases,
then the working tree, built and checked for its fixpoint); then, at
once, `suite-O0`, `suite-O1`, `suite-O2`; `fuzz-plain`, `fuzz-loops`,
`fuzz-generics`, `fuzz-pressure`, `fuzz-calls`, `fuzz-lang06`,
`fuzz-vector`, `fuzz-div`, `fuzz-range`, `fuzz-arch` (0.19: the
intrinsics, `tests/fuzz/run.sh -A`), `fuzz-guard` (0.25: guarded
accesses far out of bounds and calls of 2^62 steps under conditions
that never hold, in loops, `-G`) and `fuzz-seed` (the seed as a third
oracle); `abi-plain`, `abi-import`, `abi-header`; `objcheck`;
`layout` (`tests/cimport/layout.sh` on the system headers); `debug`
(`tests/debug.sh`); `stress-grow` (0.14, not in `--quick`: the compiler
run with `VOLE_STRESS_GROW=1`, under which every growth of its tables,
`base::grow`, `buf_reserve` and the symbol tables, moves them, by half
their size from a capacity of 1, and fills the old block with 0xAA bytes
and keeps it; a read through a table pointer taken before a growth then
finds garbage instead of, by luck, the old data. Its self-compile must
give the same object as without, and the suite pass at -O0 and -O2. The
mode is for finding such reads, as `TYPES[template_instance(..)].a` was
before 0.14 read TYPES before the call that grew it; it costs little
time and about twice the memory); `examples-checkalloc` (0.16, not in
`--quick`: every example's test, tests/examples/*.test, with the program
built by `--check-alloc`, whose Gpa puts every block on pages of its own
and never reuses them, so a use after free, a double free or a wrong free
in an example stops it with where the block was allocated and freed;
added after examples/errors-and-results printed an error holding a view
of memory it had freed; through `VOLE_TEST_FLAGS=--check-alloc`, which
a case whose output differs by design with the flag declines with `//
NO-EXTRA-FLAGS: why`); `valgrind` (0.18.1, `--release` only, in the
`linux-aarch64` container, where valgrind is: `tests/valgrind.sh`, the
compiler under memcheck, its -O2 self-compile at `-j4` and the
compilations of the `opt_*`, `own_*` and `contract_*` cases and a few
examples at -O0 and -O2; any invalid read or write or use of an
uninitialised value fails it, leaks do not, as the compiler leaves its
memory to the exit; added after two memory bugs of 0.17, an SLP table
overflow and a read of the own pass's place -1, passed every macOS check
and only valgrind showed them; about 2 minutes, beside the container's other steps; on its own:
`bootstrap/aarch64-linux-check.sh --worktree --dev --compiler
target/volec --only valgrind`); `compile-cost` (0.21.1, in `--quick`
too, a few seconds: `tests/compile_cost.sh`, the instructions retired,
from `/usr/bin/time -l`, the fewest of three runs, of building a hello
world and tests/cost/std_heavy.vl and of `check` of a copy of
compiler/src, with this compiler and with the newest release built here
that is not this commit; it fails when a build costs more than 1.5 times
the release's or `check` more than 1.15 times, and prints the three
numbers with their ratios; added after 0.20's std made a hello world 5.5
times dearer unnoticed: std's index made 660 KB of std core;
`compiler/std/embed.sh --core` lists the core sections, each with the
section and the name that pull it in, and `tests/std/core_sections.sh`,
run by the suite, bounds their bytes); and the two containers: `linux-x86_64`
(`bootstrap/linux-check.sh`, which builds its own chain and so starts at
once) and `linux-aarch64` (`bootstrap/aarch64-linux-check.sh --compiler`:
the chain's compiler cross-compiles the tree; 0.25.2: the suite at -O0
and -O2, not -O1: the optimizer is the same for every target and -O1
runs on macOS, while what is Linux's own, the ABI, libc and the link,
-O0 and -O2 exercise; the three suites, objcheck and fuzz beside them
made the row the gate's longest, 140 minutes). Inside each container the
same steps run at once (`gate.sh --inside`), the longest started first,
and their rows appear in the table under the container's.

(0.25.2) `--quick` has a container row too, `linux-smoke`
(`aarch64-linux-check.sh --smoke`): agents' quick gates passed on macOS
while the tree failed in the container, which the release gate found 2.5
hours in. The chain's compiler cross-compiles the tree, and in the
container, after the fixpoint and the md5 check, the `smoke-*` steps
run at -O2: `smoke-runner` (`tests/run.sh runner`: tests/runner/run.sh
and the runner_* cases), `smoke-lsp`, `smoke-examples` (`example_build`:
every example builds), `smoke-cases` (`tests/run.sh _`: every case,
2,800 programs) and `smoke-walkthrough` and `smoke-book` (sessions that
differed on Linux before). Not query's and refactor's transcripts (serial:
6 and 8 minutes beside the rest), nor the formatter's: the full gate's
container runs them. It runs beside the macOS steps, about 3 minutes on
an idle machine. When docker is not running the row is `SKIP` (not pass), its note
`colima is not running: colima start` — never a pass; `--no-linux` leaves
it out, `--quick --no-x86` keeps it (x86_64 is another matter).

(0.25.2) One gate at a time, across the worktrees of the repository: a
gate takes the lock directory `gate.lock` in the git common dir (`git
rev-parse --git-common-dir`), its `owner` file naming the gate (pid, the
process's start time, worktree, arguments). A second gate prints one
line, `gate: waiting for the gate in WORKTREE (pid N, since T, gate.sh
ARGS): one gate at a time`, and starts when the first ends; with
`--no-wait` it fails (exit 3) instead. A lock whose holder is gone (no
such process, or another one with its pid) is taken over, saying so.
Seven agents' gates and suites at once had put the load at 100 to 167 on
12 cores. `bootstrap.sh --dev` and `tests/run.sh` take no lock (the
inner loop); nor does the gate inside a container.

(0.25.2) No silent hang: a release gate waited 2.5 hours on two runners
blocked reading the slot FIFO, every slot lost with jobs killed before
they gave theirs back. Every runner's job now gives its slot back
however it ends (a trap on EXIT, and on HUP, INT and TERM; semfuzz
counts the slots it holds and writes them back when killed or at exit),
and the gate
checks its steps (every 15 s; not the containers' rows, whose work is in
the VM — the gate inside a container checks its own): a step none of
whose processes used the CPU, started or ended for `$VOLE_GATE_STALL`
seconds (default 600; `sleep` does not count) is stopped and fails, its
note `stalled: ... with F of J slots free` (0 free: slots lost, e.g. a
job killed with -9). `bench` runs alone, at the end: benchmarks
need an idle machine.

(0.15) x86_64 is off by default: `bootstrap/gate.conf` sets `X86=0`, so
the `linux-x86_64` step (the emulated container: about half of the
release gate's machine time) is not run; `--with-x86` (or
`VOLE_GATE_X86=1`) runs it, `--no-x86` leaves it out whatever the
default. Since then programs are not run on x86_64 by the gate (the
x86_64-macos suite never was: Rosetta); the x86_64 back end is still
compiled and same-output still compares its assembly.

It stays parallel without overloading the machine: the test runners
(`tests/run.sh`, `tests/fuzz/run.sh`, `tests/abi/run.sh`,
`tests/objcheck.sh`) take their slots from one pool, a FIFO named by
`$VOLE_JOBSERVER` that the gate fills with `-j` lines (by default one
per CPU). Twenty steps share the CPUs, none waits for another's tail, and
no program runs late enough to hit its timeout.

**macOS checks every new program.** The first launch of an executable
that was just linked waits for syspolicyd and XProtect to check it:
0.2–0.4 s, against milliseconds for the compilation and the link of a
test (measured on 0.11, one test at a time: compile 5 ms, link 40 ms,
first launch 240 ms, a second launch 2 ms). Every test, random program
and ABI program is a new executable, so on macOS this wait is most of the
suite's time, and the checks are taken about one at a time, whatever the
number of CPUs: the gate's release run on macOS (8,300 programs at the
0.11 counts) took 33 minutes with the CPUs mostly idle, while the same
suite runs in 15 s in the aarch64-linux container. More slots do not help
(`--quick` took 3:53 with two slots per CPU, 2:27 with one). So on macOS
the gate runs a modest number of random programs, and the volume runs
in the aarch64-linux container, the same code generator. Ad-hoc signing
does not change it (the linker signs already). It does not apply to
programs a *developer tool* starts: add the terminal that runs the gate
to System Settings → Privacy & Security → Developer Tools (`spctl
developer-mode enable-terminal` makes Terminal appear in that list).
`gate.sh` times one launch when it starts and says when it is slow.

The containers get `--cpus N` each (default 8; at most what docker has:
with colima, `colima start --cpu 10 --memory 12`); x86_64-linux runs
emulated (Rosetta, in colima's VM), aarch64-linux natively, both at once.
Emulated, gcc and ld now and then crash (a segmentation fault in
collect2, two in one release run): the runners run `cc` once more when
it crashed (a signal, or gcc's "internal compiler error"), and say so in
the case's output; a crash of `cc` is not vole's.
An image is built again only when its recipe (the Dockerfile and the
files it copies) changes (`--rebuild-image` forces it, for a newer base
image). The x86_64-linux chain keeps its built releases in a docker
volume (`vole-bootstrap-x86_64-linux`), by tag and commit as
`bootstrap.sh` caches them, so a rerun builds only the working tree;
`gate.sh --fresh` (`linux-check.sh --fresh`) starts from nothing, as a
new machine does.

The history: `bootstrap.sh` checks every release's fixpoint but, by
default (`--history fast`), runs only the last release's test suite (the
release that builds HEAD); a suite that passed before for the same tag
and commit (in the cache) is not run again in either mode.
`--history full` runs every release's suite: an occasional complete
replay (with `--clean`, from nothing). `gate.sh --history full --fresh`
runs every suite on this host, but from the cache: `--fresh` empties only
the x86_64-linux container's volume. On this host a rebuild from nothing
is the `chain-fresh` step (0.25, below).

Between releases, `tests/fuzz/forever.sh` fuzzes in every mode, batch
after batch on new seeds, at the lowest priority (nice 19), so the gate's
fuzz counts can stay modest. It logs to `target/fuzz-forever/log`, keeps
failing programs in `target/fuzz-forever/failures/MODE/`, goes on from
where it stopped, and stops after the current batch once
`target/fuzz-forever/stop` exists:

```
$ tests/fuzz/forever.sh &      # --follow: test each new target/volec
$ touch target/fuzz-forever/stop
```

If a release changes how its binary is invoked or what it emits (another
command line), give it a new `cli` value and teach `compile_with` in
`bootstrap/bootstrap.sh` about it; the script keeps every interface that a
release in the chain uses. How a release's *source* is laid out is the
`root` key's business: from 0.6 the compiler is a module tree whose root
file (`compiler/src/main.vl`) is the only file on the command line; a
release without `root` (0.1.0 to 0.5.0) is compiled from all the `.vl`
files of its `compiler` directory, as one module. The builder's `cli` says
how to invoke the builder; the release's `root` says what to give it.

From 0.16 the gate gives each test program a minute (`VOLE_TEST_TIMEOUT`,
60; tests/run.sh's own default stays 20 s): its steps run side by side
with the Linux container, and the heavier examples at -O0 took longer
than 20 s on a loaded machine (the examples-checkalloc step: 2 minutes).

## Trusting the chain

Every compiler since 0.1.0 was built by the one before it. So a bug, or
worse, in a compiler that the chain trusted could live on in every later
one without being in any source. These are the checks against that, and
what remains trusted.

**The root of trust.**
- **rustc and cargo**, for the seed: the Rust compiler at the `seed` tag,
  pinned by its rust-toolchain.toml, with its crates (Cranelift) pinned
  by Cargo.lock (`--locked`).
- **git**: the tags' trees, read by `git archive` from the repository's
  objects.
- **The OS toolchain:**
  - `cc` and `ld` link every compiler of the chain. bootstrap.sh links
    with `cc`, even from 0.25 on.
  - Up to 0.6, `cc` also assembled the compiler's output; from 0.7 the
    compiler writes its own objects.
  - The system's libSystem, or glibc on Linux.
- **The kernel and the CPU.**
- **From 0.25, the compiler's own Mach-O linker,** `back/objfile/link_macho.vl`.
  It links what `volec -o` builds on aarch64-macos: the test suite's
  programs, examples and users' programs. It does not link the compilers
  of the chain, which `cc` links. `chain-diverse` links with `cc` too, so
  neither check depends on the new linker.

Nothing else is trusted: no binary built before, no cache.

**The checks**

| check | what it shows | where |
|---|---|---|
| the fixpoint | each compiler, built by its builder and then by itself, emits the same bytes | every bootstrap step |
| `chain-fresh` | the seed is built again by cargo, and every release again from its tag into an empty cache (`bootstrap.sh --clean --cache DIR --until LAST --history none`). What each release emits for itself is compared by SHA-256 with `bootstrap/chain-hashes/<host>.txt` and with the shared cache; (0.25.2) no suite runs when they agree (the bytes are those whose suite passed at the release), and the last release's runs when one differs (chain-fresh fails then anyway) | `gate.sh --only chain-fresh`, part of `--release` |
| `chain-diverse` | HEAD's compiler by three paths: the normal chain (-O2); a path with no optimizer before the last step (the previous release at -O0, then HEAD at -O0, which builds HEAD at -O2); and the chain at -j1. The paths must end in the same bytes, and the -O2-built and -O0-built compilers must give the same output on the whole corpus (`same-output`) | `gate.sh --only chain-diverse`, part of `--release` |
| `valgrind` | the compiler's own -O2 self-compile (at -j4) and the opt_, own_ and contract_ cases plus examples, under memcheck: no invalid read or write, no use of an uninitialised value | aarch64-linux container, `--release` |
| `compiler-memcheck` | the same set on macOS, two ways. With the compiler built `--check-alloc`, a use after free or double free of Gpa memory stops it. Under Guard Malloc, the same for the memory it takes from malloc itself. The objects must be the plain compiler's | every gate but `--quick` |
| `stress-grow` | with every table growth moving and poisoning the old block, the self-compile is the same and the suite passes | every gate but `--quick` |
| `fuzz-seed` | random programs give the same output from the seed, the oracle written in Rust, as from HEAD | every gate |

**chain-fresh's record.** A release adds its line when it is tagged, with
`bootstrap/chain-fresh.sh --record`. The first record (0.25) was written
from the long-lived shared cache. The first fresh run then confirms that
the cache holds what the tags rebuild to. A mismatch is not to be
re-recorded: find which release differs, and why.

**chain-diverse's argument** (after Wheeler's diverse double-compiling):
- A3 is what the normally built compiler A2 emits for HEAD at -O2.
- B3 is what B2 emits for the same input. B2 is a HEAD compiler that no
  optimizer touched.
- If an optimizer bug had miscompiled the compiler in a way that changes
  what it does, A3 and B3 would differ.

For both to be wrong the same way, the -O0 back ends of the previous
release and of HEAD would both have to miscompile HEAD into the same
wrong behaviour as the optimizer did. The corpus comparison widens this
check from the compiler's own source to every program in the corpus.

**The stricter checker as an audit of the compiler** (from 0.25, as
the semantics fixes merge). When a fix makes the checker reject code it
used to accept, it checks compiler/src and compiler/std too.

Every site it rejects in the compiler is a place where the compiler may
have had latent undefined behaviour: a view outliving its buffer, an
exclusivity violation, a missing drop. Its own builds would not have
shown it. For each site:
1. **Record it** in the fix's commit message or in a list in its PR:
   the error's code, the file and line, and the item.
2. **Review it before changing it.** Read the code through
   `volec query context`, and decide whether the rejected pattern was
   only unprovable or could actually misbehave: which input, which
   path, what happens.
3. **For a real case:**
   - write a test that showed it, if one can (a compilation whose output
     was wrong, or a memcheck failure);
   - check whether a release shipped it; for one that did, `chain-diverse`
     and `same-output` against that release tell whether any output
     changed.
4. **Only then patch it.** Do not satisfy the checker by mechanical
   rewrites (an `unsafe` block, a copy, a reordered borrow) without
   steps 2 and 3. `fix --suggested` must not be applied blindly to
   compiler/src for these codes.
5. **Summarize** in the release notes: how many sites, and how many were
   real.

## Adding a host

A new host (say `aarch64-linux`) needs:

1. A backend for it in the compiler: an instruction set file next to
   `compiler/src/gen0/arm64.vl` and `x86_64.vl`, and the back end's
   `compiler/src/back/mc_arm64.vl` and `mc_x86_64.vl` (or a new
   object format and ABI in an existing one), a target name in
   `compiler/src/gen0/target.vl`, and its detection in `host_target()` in
   `main.vl`. The release that adds it is built on an existing host,
   and is checked on the new one by cross-compiling: its assembly for the
   new target must be the same wherever it is produced, and the suite must
   pass there (`tests/run.sh -t <target>`).
2. The host in `bootstrap/bootstrap.sh` and `tests/run.sh` (the `uname`
   mapping and how `cc` links for it).
3. The host in `hosts` of that release and of HEAD in `releases.toml`.

The chain on the new host starts at the seed, so the seed must run there
too, or every release before the one adding the host must already support
it. When neither holds, a new seed release (a frozen tag that runs there)
starts the chain; that is a decision to document here.

## Building and testing

With a compiler binary at hand (`target/volec`, as `bootstrap.sh` leaves
it), on aarch64-macos:

```
$ target/volec compiler/src/main.vl -o volec.s   # the compiler (its root file), by itself
$ cc -arch arm64 -o volec volec.s -lm
$ tests/run.sh -c ./volec                            # the test suite, for the host
$ tests/run.sh -c ./volec prog_                      # only cases named *prog_*
$ tests/run.sh -c ./volec prog_ =lsp -f more.txt     # (0.25.2) the union: *prog_*, the lsp suite, a file's filters
$ tests/run.sh -l opt_loop                           # (0.25.2) what a filter selects, run nothing
$ tests/affected.sh --list                           # (0.25.2) the tests the branch's changes touch (tests/affected.map)
$ tests/run.sh -c ./volec -t x86_64-macos            # x86-64, under Rosetta
$ tests/run.sh -c ./volec -O 0                       # at another optimization level
$ tests/fuzz/run.sh -c ./volec -n 500                # random programs, -O0 vs -O1 vs -O2
$ tests/abi/run.sh -c ./volec -n 150                 # C interop: random signatures, both ways
$ tests/objcheck.sh -c ./volec                       # objects (and -g line tables) against cc -c
$ tests/debug.sh -c ./volec                          # -g under lldb or gdb (0.11)
$ bench/run.sh -c ./volec                            # benchmarks
```

and on x86_64-linux:

```
$ target/volec compiler/src/main.vl -o volec.s
$ cc -o volec volec.s -lm
$ tests/run.sh -c ./volec
```

`volec --target T` picks the target (`aarch64-macos`, `aarch64-linux`, `x86_64-linux`,
`x86_64-macos`); the default is the host. The assembly for a target is the
same on every host, so a compiler can cross-compile itself.

`tests/run.sh` is a POSIX shell script: it needs the compiler and `cc`, not
cargo. Its directives (`// EXPECT:`, `// EXIT:`, `// ARGS:`, `// STDIN:`,
`// ERROR:`, `// XFAIL:`, `// XFAIL(<target>):`, `// CHECK:`,
`// CHECK-NOT:`, `// CHECK-OPT:`, `// STDERR:`, `// CSOURCE:`) are described
at its top. A release's suite must pass at every optimization level. The
runners take `-j N` (default: the number of CPUs); their reports do not
depend on it. (0.25.2) `// EXPECT:` lines take holes for what varies
(`{num}`, `{int}`, `{..}`), `// EXPECT-PPM: OUT REF [region X,Y,W,H]
[tolerance N] [allow P%]` compares an image the program wrote with a
reference under `tests/golden/`, and a check that cannot run on this
machine (the window tests while the screen is locked or the display
asleep) is a `SKIP NAME: why` line and a `skip` column, never a pass;
the gate lists the SKIP lines under its table. A case's time limit
(20 s, `TIMEOUT`, `$VOLE_TEST_TIMEOUT`) is extended by itself again, up
to 8 times, while the load average is above the CPUs
(`tests/watchdog.sh`: parallel agents made the litmus cases time out); a
program killed at its limit fails with `timed out: killed after N s ...`.
The load and the CPUs are `tests/load.sh`'s: on Linux the CPUs are the
cgroup's quota when it is lower (a container's `--cpus`). In the
linux-aarch64 container the load average is the virtual machine's: a
host loaded by other work is invisible there (its stolen time counts as
running), so `volec test` judges a case stopped by `--timeout` by the
processor time it used: under half the limit, it was waiting, and runs
again (twice at most). Off macOS, `example_build` skips the examples on
std::gpu and std::window (`SKIP example_build NAME: ...`).
`tests/runner/run.sh` checks these pieces of the runner.

The seed keeps its own tests, run with cargo:

```
$ cd seed && cargo test
```

## The whole chain on a new machine

On macOS (Apple silicon or Intel):

```
$ xcode-select --install                                  # git and clang
$ curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
$ git clone <repository> vole && cd vole && git fetch --tags
$ bootstrap/bootstrap.sh
```

On x86-64 Linux (Debian/Ubuntu shown):

```
$ sudo apt-get install git gcc libc6-dev curl ca-certificates
$ curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
$ git clone <repository> vole && cd vole && git fetch --tags
$ bootstrap/bootstrap.sh
```

This builds the seed from the `seed` tag with cargo, builds 0.1.0 (from
`v0.1.0`) with the seed, checks 0.1.0's fixpoint, does the same for every
later release (0.2.0 is built by 0.1.0), runs the last release's test
suite, and finally builds, checks and tests HEAD (`--history full` runs
every release's test suite as well). It prints a
summary and leaves the HEAD compiler in `target/volec`.

To check the Linux chain from any machine with docker:

```
$ bootstrap/linux-check.sh                   # HEAD and the tags, from a fresh clone
$ bootstrap/linux-check.sh --seed-tests      # also the seed's cargo tests on Linux
$ bootstrap/linux-check.sh --all-levels --fuzz=200   # also -O0/-O1/-O2 and random programs (each mode)
$ bootstrap/linux-check.sh --abi=150 --bench          # also C interop fuzzing and the benchmarks
$ bootstrap/linux-check.sh --fresh --history full     # without the cache volume, every release tested
```

It builds a minimal Debian image (`bootstrap/ci/linux-x86_64.Dockerfile`:
only git, gcc, libc6-dev, curl, ca-certificates and rustup; again only
when that recipe changes), clones the repository inside it, runs
`bootstrap.sh` (its cache in a docker volume, see "The gate"), checks the
md5 example against `md5sum`, then runs the checks asked for at once
(`bootstrap/gate.sh --inside`).

Built steps are cached in `target/bootstrap/<host>/`; a rerun only rebuilds
HEAD. (0.18.1) Runs from several worktrees share the main checkout's
cache safely: a release's entry is written under a lock (`<entry>.lock`,
a directory made by `mkdir`, with its holder's pid), built in
`<entry>.building` and renamed into place once its fixpoint (and suite)
passed, so no run sees a half-built entry or deletes another's tree (two
gates built 0.17.0 into it at once, and one removed the other's tree
mid-suite). A second run waits for the lock, then finds the entry built;
a lock whose holder is gone, or older than
`VOLE_BOOTSTRAP_LOCK_STALE` minutes (120), is taken over. Options of `bootstrap.sh`:

```
--until 0.1.0      stop after a release: a from-scratch build of any release
--worktree         build the working tree instead of HEAD in the last step
--dev              before the tags exist: missing release tags are skipped, and
                   the seed comes from the working tree without a `seed` tag
--host HOST        build for HOST instead of the detected host
--seed-bin PATH    use an existing seed binary
--clean            empty the cache first
--out PATH         also copy the final compiler to PATH
--history MODE     fast (the default): every release's fixpoint, the last
                   one's suite; full: every release's suite too; none
                   (0.25.2): no release's suite
--no-head-tests    build HEAD and check its fixpoint, not its suite
--no-suite         (0.25.2) the agent's build: --no-head-tests and
                   --history none; target/tools/volec is not replaced
```
