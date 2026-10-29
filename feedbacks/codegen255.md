# Feedback: codegen255, code generation and measuring (bss, statics, the 7x, --time-passes=instructions, --vec-stats=FN)

2026-10-29, release 0.25.5. Zero statics in bss on both object formats
and in the internal Mach-O linker; statics no code names left out; the
`-o`-linked compiler's 10x found (the internal linker's SDK version) and
fixed; `--time-passes=instructions` and `--vec-stats=FN` with a new
tests/perf suite; tests/threads_writes.sh made to check again; item 6
(a bounds check after `i < v.len()`) measured and left, with its cause.

## Verdict

The compiler's own tools made the code changes cheap; what cost the
time was the toolchain around the code: a linker header field nobody
compares with `ld`'s, a chained-fixups page count that only a crash
showed, and a race check that had been checking nothing for several
releases. Each was found by hand with `otool`, `dyld_info`, `sample` and
`vtool`. A test that diffs the internal linker's load commands against
`ld`'s for the same objects would have caught the first two in seconds.

## What worked

- `volec query context` and `query show` on gen_data, link_macho's
  writer and `cc_wanted`: the code and its callers at once; `query refs
  --count` to find every reader of a new static.
- `volec refactor move` for `all_zero` (gen0 to front::consteval): one
  call, every use rewritten, checked.
- `bootstrap/bootstrap.sh --dev --no-suite` (about 20 s, fixpoint) after
  every change: the bss writer and the linker were proven on the
  compiler itself, which is where the page-count bug showed (the
  `-o`-linked compiler crashed reading a bss table).
- `--emit-asm` / `--emit-ir` with `#[inline(never)]` and a value from
  `std::env::args()` (constants are otherwise propagated into the
  callee): the evidence for item 6 in two builds.
- `tests/objcheck.sh` (the internal assembler against the system's, per
  case) on the bss change: 640 cases identical.
- `bootstrap/gate.sh --only compile-cost`: one line, 1:23.

## What cost time, ranked

### 1. The 10x of a `-o`-linked compiler
The -O2 self-compile took 470G instructions in a compiler linked by
`volec -o` and 46G linked by `cc`, with the same objects. `sample`
pointed at libmalloc's tiny-free path, not at the compiler; finding that
the cause was LC_BUILD_VERSION's SDK field (12.0; macOS's malloc keeps
its old free path below SDK 13) took rewriting the binary with `vtool
-set-build-version` four ways and timing each. About 15 turns. A test
that compares the internal linker's load commands with `ld`'s (`otool
-l` of both, minus addresses) would have shown `sdk 12.0` against `sdk
26.x` at once.

### 2. The chained fixups' page count with bss
After bss, the `-o`-linked compiler crashed (garbage in a zeroed
table). The linker counted the `__DATA` segment's pages by its memory
size; the kernel then mapped `__LINKEDIT`'s bytes over the bss pages.
Found by comparing `dyld_info -fixup_chains` with `ld`'s output for the
same object: about 8 turns. The same load-command diff as in 1 would
have shown `page_count 8` against `2`.

### 3. tests/threads_writes.sh checked nothing
It grepped `static mut`; since the language spells it `static var`, it
found no statics and passed. I noticed only because my new
statics did not appear. Fixed (197 statics checked; two 0.25.4 statics,
`VEC_TMPL` and `WRAPS`, had slipped in unrecorded). 3 turns. A check
that finds zero items to check should fail.

### 4. New unsafe sites named only at commit
The check hook prints one aggregate warning (`4368 unsafe sites lack
// UNSAFE:`); the five sites my new code added were named only by the
commit hook, after the work was done. 2 turns. The hook could name the
unjustified sites in the items an edit touched.

### 5. Build options' help text shown nowhere
`Arg::option("time-passes").help(...)` on build_command is not printed
by `volec --help` (a hand-written summary in tools/help.vl) or by any
other command I found; a new build option is undiscoverable from the
command line. 2 turns looking.

### 6. The hook on a Python write to compiler/src
A Python heredoc rewriting base/timer.vl through a variable path ran;
the same shape for vectorize/legality.vl was blocked. Then `edit patch`
with the same `--old` text for two functions needed one call each
(`why`, `why_at`). 2 turns.

### 7. zsh in the Bash tool
`echo =====` fails (equals expansion), and a heredoc whose text holds
`EOF` needs another delimiter. 1 turn each.

### 8. same-output on an intended change of the output
`volec same-output OLD` against 0.25.4: 20,265 of 32,952 compilations
differ, all expected, with nothing to say so: 7,389 are errors whose
`try:` line names the compiler's path (old and new identical once the
path is replaced), 12,876 assembly files whose only differences are
zero statics' section and unnamed statics left out. Telling that took a
classifying script (about 25 minutes of runs). 3 turns.

## Never used

`probe`, `reduce`, `batch`, `undo`, `query impact`, `rewrite`,
`tests/affected.sh --list` beyond its plan.

## Fix list, in order

1. [test] tests/link: build one program with the internal linker and
   with `ld`, and diff `otool -l` (load commands, minus addresses and
   sizes) and `dyld_info -fixup_chains`'s page counts.
2. [test] tests/threads_writes.sh and every grep-based check: fail when
   the set checked is empty.
3. [hook] check-after-edit: name the unjustified unsafe sites in the
   items an edit touched, not only the program's total.
4. [tool:help] show a build's options (`volec --help options`, or `volec
   FILE.vl --help`) from build_command's own help strings.
5. [build] item 6: fold `x - 0` (and `x + 0`) across signedness of one
   width, or give a slice of `0..len` the length itself, so the range
   pass drops a Vec index's check after `0 <= i && i < v.len()`; with
   the adversarial tests (a length changed between test and access) and
   a mutant.
6. [lang] a `static var X: f64 = -0.0` is +0.0 (`1.0 / X` is inf; a
   local's is -inf, also on 0.25.4): the static's constant loses the
   sign.
7. [docs] docs/grammar.md lines 123, 127, 146 say `static [ "mut" ]`;
   the language spells it `static var`.
8. [tool:same-output] replace the compiler's own path in outputs before
   comparing; a `--allow KIND` for differences a change intends (a
   section's name, a static not emitted), counted apart.
9. [hook] query-first.py: block or allow Python writes to compiler/src
   the same way whatever the path's spelling.
