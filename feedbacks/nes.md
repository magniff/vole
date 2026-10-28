# Tooling feedback: writing an NES emulator in Vole

What: an NES emulator in `examples/nes/` — a 6502, a 2C02, the APU's
frame counter, two controllers and eight mappers. 3,660 lines over 11
`.vl` files, no `unsafe`, no C, `std::gpu` for the window and the rest
from `std`. Verified against `nestest` (8,991 instructions), blargg's
instruction, timing, PPU and MMC3 ROMs, and 21 built-in checks that
assemble synthetic cartridges in memory.

Written by the agent that did the work, on 2026-10-28, from what it
actually ran.

## Verdict

Writing CPU-shaped code in Vole is a pleasure, and the checked-edit loop
is the reason: `volec check` takes **0.14 s** on the whole emulator and
the `-O2` build **0.22 s**, so a change is never a commit-sized
decision. The tooling's centre of gravity, though, is still the
compiler's own source tree. An emulator is the kind of program whose
bugs are not *type* errors but *timing* errors; for those, the compiler
gave me nothing, and the debugger is the one part of the toolset that
does not reach outside `compiler/`.

## What carried the work

- **`check` in a tenth of a second.** Ten modules, 3,660 lines, checked
  before every build. The absence of any perceptible wait is what made
  "write the whole emulator, then run it" survivable.
- **The diagnostics that were right the first time.** `let mut` is
  reported with the fix (`var x`) on every line; an array literal with
  40 elements where 38 were declared is one error at the literal, not
  forty. Over a 3.6k-line program I do not remember a diagnostic that
  sent me to the wrong line.
- **`query context NAME`.** Learning a module's shape (the PPU's
  register entry points, the cart's bank maps) without reading the file
  from the top stayed cheap.
- **`probe`.** Once found, it answered in one command what I had been
  doing with temporary `eprintln`s and three rebuilds: it printed
  `mode1 = true prg = true power = true` at `check.vl:235` and ran
  `--check` for me. It is the right tool for "which of the five
  conditions is false". Two problems, below.
- **The guide's semantic notes.** `&x` for inout, `~` for bitwise not,
  `loop` rather than `for`, `sink` for moving a parameter — each one
  caught before it became a Rust-shaped bug. An emulator is full of
  bitwise arithmetic, and the guide's warnings about the places Vole
  looks like Rust and is not were exactly on target.
- **`tests/run.sh nes`.** The built-in `--check` runs at -O0 in under a
  second, so the emulator has a real CI case with no ROM and no window.

## What cost time, ranked

### 1. No help for logic and timing bugs — the whole debugging surface is hand-built

The compiler is silent about an MMC1 PRG bank computed with `& 0x0e`
instead of `* 2`, or an MMC3 mode bit copied into `control` but never
`refresh()`ed. Both were found by the *checks I wrote*, not by the
toolchain, which is the right division of labour — but the loop to find
them was `eprintln` + `-O2` rebuild + rerun a ROM + grep the result.
Three of those in a row, then remove the prints by hand.

`probe` should have been the first move, and it would have been if
(a) it worked from the repo root, and (b) the docs said it applies to
any `main.vl`, not just a `tests/NAME` case. A line in `guide debug`
like "`probe FILE:LINE EXPR -- ARGS` runs any Vole program, including
the examples" would have saved an hour.

What the emulator needed beyond that was **observability in the
program**, so I built it: `--trace N` (nestest's shape), `--log N` (PPU
register writes with `sl`/`dot`/`fr`/`op`), `--state`, `--shot`,
`--dump-chr`, `--info`, `--pc`. That is the right shape for an emulator
— the debug flags are useful to a human too — but it is worth saying
that building a debugger *inside the program under test* was the single
largest source of scaffolding, and nothing in the toolchain looked at
it.

### 2. `query`/`edit`/`probe` still do not know about example program roots

This is the same friction as the galaga retrospective, and it was paid
again on the first real edit of this project:

```
$ target/volec edit patch examples/nes/check.vl --old 'let mut' --new 'var' --all
error query.no-match: no file 'examples/nes/check.vl' in the program
try: target/volec query items

$ target/volec probe examples/nes/check.vl:233 mode1 prg power -- --check
error probe.no-file: no file 'examples/nes/check.vl' in the program
try: target/volec query items
```

Both work after `cd examples/nes` and using the absolute path to
`target/volec`; neither `try:` line says so, and `query items` from the
root fails too. The workaround is repeated on every session and in
every example.

### 3. `edit patch` has no `--all`

Six `let mut`s in one file needed six fixes. `edit patch --all` is
rejected, `edit apply` wants a patch, and the fallback is the host's
edit tool or `sed` — which quietly leaves the checked-edit path. A
one-hunk primitive is fine; a bulk replacement is the other half of the
same job, and `refactor rename` covers identifiers but not text.

### 4. A window example's first `tests/run.sh` is 35 lines of linker errors

Adding `tests/examples/nes.test` with `// SOURCE` and `// ARGS: --check`
produced:

```
Undefined symbols for architecture arm64:
  "_CFFileDescriptorEnableCallBacks", referenced from:
      _vole.host_rom_path in prog.o
  ... 35 lines ...
```

The fix is the two directives the GPU examples already carry —
`// REQUIRES: metal` and `// LINK: std::gpu and std::window name the
frameworks they link` — but nothing in the error says so, and the
symbol is named after whichever Vole symbol happened to come first in
the object (`_vole.host_rom_path`), not after the function that needs
the framework. One line from `run.sh` ("this program imports
`std::window`/`std::gpu`; add `// LINK:` and `// REQUIRES: metal`")
would remove a round trip that every GPU-ish example pays once.

### 5. Conformance lives outside the test runner, by necessity

No ROMs are in the repository, so the emulator's real conformance —
`nestest`, `instr_test-v5`, `ppu_vbl_nmi`, the MMC3 suites — is a manual
run against files downloaded outside the tree. `--check` proves the
parts (parser, mappers, CPU loop, PPU, APU) but cannot prove a whole
game. That is a policy I agree with, but it leaves the most valuable
tests for this kind of program invisible to `tests/run.sh`; a documented
`examples/nes/run-roms.sh ROM_DIR` convention (not committed ROMs) would
at least make the manual suite reproducible.

### 6. Screenshot checks have no shape in the suite

Five of the conformance suites report their result *only on screen*
("PASSED" drawn with tiles). I wrote Python helpers to read the PPM
(`--shot`), crop the text, OCR it against the dumped CHR and compare a
region across seven screenshots. It worked, but it is throwaway code in
a temp directory, and for a graphics program it is the *only* assertion
that some features render. `// EXPECT-PPM: file` (or a golden-image
comparison with a tolerance) would be a natural test directive for the
GPU and emulator examples.

### 7. A `sed -i` rewrite of a `.vl` slipped past the query-first hook

One command rewrote `examples/nes/check.vl` (`sed -i '' 's/const
PAINT_PROGRAM: \[u8; 38\]/.../'`) and was not blocked, recorded or
answered with a hint. If the hook is meant to make source reads and
rewrites go through `query`/`edit`, this is a hole; if shell rewrites
are allowed, the hook's message should say so.

## What was never touched

`refactor rename|move|signature|field|variant`, `rewrite`,
`extract-function|inline|split`, `batch`, `undo`, `impact` and
`query effects`. An emulator is new code in one folder, not a change to
an existing program, so none of them had a job. The commands this work
actually used were `check`, `query context`, `query show`, `edit patch`,
`probe` and `tests/run.sh`.

## Fix list, in order

1. **Find the nearest `main.vl` for `query`/`edit`/`probe`, add
   `--root DIR`, and name the working invocation in every `try:` line.**
   The most repeated failure, for the second project running.
2. **`edit patch --all`.** Six identical one-line fixes should be one
   checked edit.
3. **Say "this example imports `std::window`/`std::gpu`; add `// LINK:`
   and `// REQUIRES: metal`" when `run.sh` sees those undefined
   symbols.** Cheap, and it is the first wall every graphics example
   hits.
4. **In `guide debug`, one line that `probe FILE:LINE EXPR -- ARGS`
   runs any program, examples included**, and an example with
   `-- ARGS` rather than `--input`.
5. **Fix the query-first hook's `sed -i` hole, or document that shell
   rewrites are allowed.**
6. **A golden-image test directive** (`// EXPECT-PPM`, a region and a
   tolerance) so rendering has an assertion in the suite, not in a temp
   directory.
7. **`agent-feedback --list`**, still only writable — the `-O2` and
   hook issues of the last project had no "has anyone seen this?"
   surface.

## Instrumentation gap

`.git/agent-tools.jsonl` records query-shaped events only, so this
session's record says where `query` was typed, not where the time went.
For this project the useful record would be different again: which ROM
was run, at which `-O` and how many frames, and whether its signature
read "Passed" — the emulator's own loop, not the compiler's. Logging
every tool call with duration and exit code (which the hooks already
see) would let the next retrospective say whether the time went to
checking, to running ROMs, or to writing the debug flags.

## One line

The language and the checked-edit loop made a 3,660-line emulator feel
small; the remaining gap is that a program whose bugs are timing, not
types, has to bring its own debugger, and the tool that would have
helped — `probe` — is documented and scoped as if only `compiler/`
existed.
