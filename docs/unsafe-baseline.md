# The unsafe baseline

Every unsafe site (an `unsafe { }` block, an `unsafe fn`, an `extern` block)
of the compiler and of std, made by `tests/unsafe_audit.sh -u` from

    volec query unsafe --summary --no-std     # compiler/src (the tree's root)
    volec query unsafe --summary std          # std

on Darwin arm64, d6e69d01d. The rule (0.29) is none: the gate's
unsafe-audit row and tools/premerge.sh's unsafe row (tests/unsafe_audit.sh)
fail on any site of compiler/src or std without `// UNSAFE:` and
`// SAFETY:` right above it (unjustified, AGENTS.md) and on any unsafe
block of compiler/src with nothing unsafe inside (unneeded), and name
each one; `volec check --deny=unsafe` reports them as errors where they
are. The three lines below are 0 and stay 0; the counts by class, module
and file are the record of what is left. The classes and the comments'
rule: `volec query unsafe --help`, docs/query.md. std's unneeded count
is not judged (tests/unsafe_audit.sh says why).

baseline compiler/src unjustified: 0
baseline compiler/src unneeded: 0
baseline std unjustified: 0

## compiler/src

```
sites: 320 (275 blocks, 6 unsafe fns, 39 extern blocks); unjustified: 0; unneeded: 0

class	sites	unjustified
ffi	209	0
raw-pointer	82	0
other	18	0
alloc	11	0

module	sites	unjustified
crate::tools	140	0
crate::base	102	0
crate::front	32	0
crate::back	22	0
crate::middle	18	0
crate	4	0
crate::arch	1	0
crate::cli	1	0

file	sites	unjustified
compiler/src/base/mod.vl	82	0
compiler/src/tools/proc.vl	22	0
compiler/src/tools/query/cache.vl	22	0
compiler/src/tools/lsp/mod.vl	15	0
compiler/src/back/objfile/mod.vl	8	0
compiler/src/base/timer.vl	8	0
compiler/src/middle/threads.vl	8	0
compiler/src/tools/probe/mod.vl	8	0
compiler/src/back/objfile/output.vl	7	0
compiler/src/base/comp.vl	7	0
compiler/src/front/check/mod.vl	7	0
compiler/src/middle/lower/ssa.vl	6	0
compiler/src/tools/lsp/stdfiles.vl	6	0
compiler/src/tools/testrun/mod.vl	6	0
compiler/src/tools/snippet.vl	5	0
compiler/src/tools/testrun/program.vl	5	0
compiler/src/main.vl	4	0
compiler/src/tools/lsp/format.vl	4	0
compiler/src/tools/query/checks.vl	4	0
compiler/src/tools/query/mod.vl	4	0
(49 more; --all lists every one)

justification	sites	unjustified
justified	320	0
```

## std

```
sites: 897 (730 blocks, 129 unsafe fns, 38 extern blocks); unjustified: 0; unneeded: 18

class	sites	unjustified
ffi	489	0
raw-pointer	227	0
other	156	0
alloc	23	0
transmute/cast	2	0

module	sites	unjustified
std::gpu	267	0
std::window	92	0
std::sys	78	0
std::alloc	55	0
std::objc	52	0
std::sync	51	0
std::vec	37	0
std::thread	36	0
std::collections	26	0
std::process	23	0
std::fs	16	0
std::test	16	0
std::ptr	15	0
std::str	14	0
std	13	0
std::slice	12	0
std::boxed	11	0
std::string	11	0
std::__sys	10	0
std::env	10	0
std::io	9	0
std::mem	8	0
std::__gpa	5	0
std::array	4	0
std::capture	4	0
std::fmath	4	0
std::cell	3	0
std::panic	3	0
std::time	3	0
std::char	2	0
std::hash	2	0
std::random	2	0
std::fmt	1	0
std::option	1	0
std::result	1	0

file	sites	unjustified
compiler/std/gpu/hal/metal/bindings.vl	226	0
compiler/std/sys.vl	78	0
compiler/std/window/cocoa.vl	63	0
compiler/std/alloc.vl	55	0
compiler/std/vec.vl	37	0
compiler/std/thread.vl	36	0
compiler/std/objc/mod.vl	30	0
compiler/std/gpu/hal/metal/mod.vl	28	0
compiler/std/sync/atomic.vl	27	0
compiler/std/collections/hash_map.vl	26	0
compiler/std/process.vl	23	0
compiler/std/objc/foundation.vl	22	0
compiler/std/fs.vl	16	0
compiler/std/test.vl	16	0
compiler/std/window/script.vl	16	0
<std>	15	0
compiler/std/ptr.vl	15	0
compiler/std/str.vl	14	0
compiler/std/std.vl	13	0
compiler/std/window/objc.vl	13	0
(23 more; --all lists every one)

justification	sites	unjustified
justified	897	0
try: /Users/magniff/workspace/vole/.claude/worktrees/fina/target/volec fix --only unneeded-justified
```
