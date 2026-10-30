# Feedback: embedwgsl260, `embed wgsl` blocks and gpu.*/wgsl.* codes

2026-10-30, release 0.26.0; all 7 steps. Stopped once at step 4's cost bar; the integrator ruled
that the budget is compile_cost's two-compilers ratio (1.00x), the source growth reported apart.

## Verdict

The syntax, the lexer hand-off and the item (a struct and a static) fit the design and cost nothing
measurable (check of compiler/src: 4,712M at step 3 against the base's 4,713M). The check-time path
does not fit its share: checking std::gpu::wgsl's front as part of compiler/src costs +680M
instructions (1.145x of the base; the share is 1.025x, +117M). The brief's assumption that the cost is
`reflect`'s reach into msl was wrong: the path never calls reflect, and `new_front` alone (the lexer
and Front's types) is +380M. Level-1 `contract.violated` does not exist in the compiler (only its
explain entry and a constant), so "make it carry gpu.X" had nothing to attach to.

Afterwards: a fluid2d-shaped program (12 blocks, 935 WGSL lines) checks in 69.5M instructions
against 54.3M with the same text as string constants.

## What worked

- `volec query context`, `edit patch`, `edit insert --before`: every compiler/src change went through
  them, with the check hook's result after each.
- `fix --suggested` for the one `pub` the lexer needed (SRC_BUF).
- `tests/run.sh FILTER` with directory cases (`err_embed_wgsl_apart/`) for multi-file errors.
- wgslc, built in 0.6 s, to get the real text of every wgsl.* message for the explain examples.

## What cost time, ranked

1. The cost measurement: tests/compile_cost.sh's `check` row compares two compilers on the same
   source, so a source change's own cost (what the brief's share is about) is invisible there (both
   pay it: 1.00x). Measuring it took a manual `/usr/bin/time -l volec check` of two source copies.
2. Finding that Level-1 contract.violated is not implemented (grep of the code, then the design
   docs' "left for 0.18.1").
3. The unsafe count: every read of TOKS (a raw pointer) is a new unjustified site; one justified
   helper per file instead.
4. fmt's roundtrip test dedents every line, so a block's text needed its own rule in the awk.

## Never used

`refactor`, `rewrite`, `batch`, `probe`, `reduce`.

## Fix list, in order

1. [tool:query] `name_position` looks for a definition's name in the next 24 tokens: a definition
   whose name is no token (a block's field, at its WGSL `fn`) took a later use's position.
2. [tool:compile_cost] a mode that measures a source change: one compiler, the base's and the
   head's compiler/src (`-s BASE_REV`), so a share of the budget can be read off directly.
3. [diag] Level-1 `contract.violated` (a requires false for constant arguments) is still to be built;
   explain lists it as if it existed.
4. [build] check-time WGSL needs a cheaper home: std::gpu::wgsl's front checked once (a separately
   compiled helper the compiler runs, or a cached check of std modules compiler/src does not
   change), else its 680M lands on every self-check.
5. [tool:query] `query refs CONTRACT_VIOLATED` shows the definition only; a "nothing uses this"
   note would have answered faster.
6. [test] tests/gpu uses `// NEEDS: metal`, tests/run `// REQUIRES: metal`; the brief named the
   second for a tests/gpu case.
