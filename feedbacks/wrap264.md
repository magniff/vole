# wrap264: compiler/src on `wrapping_*`, the alloc exemption narrowed (0.26.4)

## Verdict

Done, with one item stopped at the design, as the brief allows.
compiler/src writes every wrap site with `wrapping_*` (about 93 calls in
25 files; the census finds none left), the bootstrap's -O0 compilers
are built and run with the overflow checks on (chain-diverse: every
path gives the same compiler), 11 of tests/run's 60 flagged cases lose
`--overflow-checks=off` and the other 49 keep it with a reason, and
Comp's impl is `unsafe impl Allocator`. `WGSL_ARENA`, and Comp in
statics and fields, stay exempt: ending them needs the statics work (f).
Two real bugs came up on the way, each with its case.

## What worked

- The 0.26.3 census (`VOLE_OVF_CENSUS` with `--overflow-checks=on` at
  -O2): one suite run per level, through a wrapper given to `tests/run.sh
  -c` that keeps the notes out of the transcripts, gave every reached
  site with its count. The second run, after the change, gave none.
- Searching for the hash constants (FNV's prime and offset, the golden
  ratio, murmur's) found the sites no case reaches (the LSP's hashes,
  volec test's, the profile checksum, the link cache's key).
- `edit patch` with several `--old`/`--new` pairs, and `FILE:LINE` as the
  item, for the census positions.
- `chain-diverse.sh --no-same-output` as the proof for step 2: B1 (0.26.3
  at -O0, so with the checks) runs the whole compile of compiler/src.

## What cost time, ranked

1. The worktree sandbox refused many ordinary shell lines (loops, `$VAR`
   commands, `cd && git`), so each loop went into a script file.
2. A program that names no std (the extern-only cases) had no
   `wrapping_mul` at all: a bug in the lazy std's triggers, fixed in
   `int_method_name`. Until it was found the cases looked unmigratable.
3. The check hook runs the released 0.26.3, whose `check` of a scratch
   program reports `no method 'wrapping_mul'` where the build compiles
   it: the hook's errors on scratch files were the old binary's.
4. Telling an intended wrap from a bug took reading each: the Hacker's
   Delight loops are modulo 2^64 by design; the switch ranges wrap to at
   most 0 and are refused; fold_intr computed `1 << 64` for a bound it
   never read.

## Never used

`refactor`, `probe`, `reduce`, `volec fix --suggested`.

## Fix list, in order (tagged)

1. [0.26.4, f] End the rest of the exemption: the tables' `Vec<T, Comp>`
   into the compilation's context, and the WGSL checks' arena (or main's
   Gpa it is made from) passed to `check_block` through it: main to
   `compile_program` and to the tools' `load_program` (17 callers) and
   `run_check`, then `check_program`, `expand_embeds`, `make_items`.
2. [lang] std's integer methods are trait methods found by the lazy
   std's word triggers; Rust's are inherent. A method on a primitive
   could load its section by the receiver's type instead of a name list.
3. [hook] the check hook's binary should be the build it checks (as
   capab263 asked), or say which binary it ran.
4. [tests] tests/run.sh's `-c` with a wrapper or another path makes every
   transcript fail on the compiler's path in `try:` lines; a census mode
   in the runner (collect stderr notes, compare nothing) would help.
5. [census] `VOLE_OVF_CENSUS` covers AArch64 only; an x86 backend site
   would go unseen.
