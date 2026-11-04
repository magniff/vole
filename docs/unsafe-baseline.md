# The unsafe baseline

Every unsafe site (an `unsafe { }` block, an `unsafe fn`, an `extern` block)
of the compiler and of std, made by `tests/unsafe_audit.sh -u` from

    volec query unsafe --summary --no-std     # compiler/src (the tree's root)
    volec query unsafe --summary std          # std

on Darwin arm64, 8b367409. The gate's unsafe-audit row
(bootstrap/gate.sh, tests/unsafe_audit.sh) fails when either count of
unjustified sites (without `// UNSAFE:` and `// SAFETY:` right above them,
AGENTS.md) rises above its line below; a lower count asks for this file
to be made again. The classes and the comments' rule: `volec query unsafe
--help`, docs/query.md; `unneeded`: unsafe blocks with nothing unsafe
inside (statics are safe), removable as they are.

baseline compiler/src unjustified: 3224
baseline std unjustified: 0

## compiler/src

```
sites: 3584 (3534 blocks, 8 unsafe fns, 42 extern blocks); unjustified: 3224; unneeded: 41

class	sites	unjustified
static-mut	1570	1404
raw-pointer	1405	1282
ffi	311	291
alloc	133	130
transmute/cast	116	108
other	49	9

module	sites	unjustified
crate::front	1102	1001
crate::tools	955	871
crate::middle	730	641
crate::back	550	526
crate::base	100	87
crate::gen0	52	36
crate::arch	50	50
crate::places	31	0
crate::guide	9	9
crate	3	3
crate::cli	2	0

file	sites	unjustified
compiler/src/back/codecache/mod.vl	56	56
compiler/src/base/mod.vl	51	49
compiler/src/tools/lsp/answer.vl	48	43
compiler/src/middle/gvn.vl	42	41
compiler/src/front/own/views.vl	39	39
compiler/src/tools/lsp/complete.vl	38	38
compiler/src/front/own/state.vl	37	37
compiler/src/middle/parallel.vl	37	37
compiler/src/middle/inline.vl	36	36
compiler/src/back/objfile/mod.vl	33	33
compiler/src/base/diag.vl	33	30
compiler/src/middle/loops.vl	33	33
compiler/src/middle/ir/mod.vl	31	30
compiler/src/front/check/alloc_rules.vl	30	0
compiler/src/back/regalloc/intervals.vl	29	29
compiler/src/front/own/fast.vl	29	23
compiler/src/back/objfile/output.vl	27	26
compiler/src/back/regalloc/scan.vl	27	27
compiler/src/front/effects/infer.vl	27	26
compiler/src/front/types.vl	27	26
(338 more; --all lists every one)

justification	sites	unjustified
missing both	3224	3224
justified	360	0
try: /Users/magniff/workspace/vole/.claude/worktrees/agent-a754ddc503608ea46/target/volec fix --only unneeded-unsafe
```

## std

```
sites: 913 (691 blocks, 188 unsafe fns, 34 extern blocks); unjustified: 0; unneeded: 3

class	sites	unjustified
ffi	458	0
raw-pointer	333	0
other	77	0
alloc	39	0
transmute/cast	5	0
static-mut	1	0

module	sites	unjustified
std::gpu	267	0
std	125	0
std::collections	118	0
std::sys	78	0
std::window	74	0
std::slice	53	0
std::sync	52	0
std::objc	51	0
std::fmt	31	0
std::thread	18	0
std::hash	8	0
std::io	7	0
std::str	7	0
std::iter	6	0
std::num	5	0
std::process	4	0
std::cell	3	0
std::env	3	0
std::random	2	0
std::string	1	0

file	sites	unjustified
compiler/std/gpu/hal/metal/bindings.vl	226	0
compiler/std/sys.vl	78	0
compiler/std/window/cocoa.vl	61	0
compiler/std/collections/raw_table.vl	52	0
compiler/std/flat/alloc.vl	45	0
compiler/std/collections/btree_node.vl	38	0
compiler/std/fmt.vl	31	0
compiler/std/objc/mod.vl	29	0
compiler/std/gpu/hal/metal/mod.vl	28	0
compiler/std/sync/atomic.vl	25	0
compiler/std/objc/foundation.vl	22	0
compiler/std/std.vl	22	0
compiler/std/slice.vl	21	0
compiler/std/thread.vl	18	0
compiler/std/collections/btree_map.vl	17	0
compiler/std/slice/stable.vl	16	0
compiler/std/flat/arch.vl	15	0
compiler/std/sync/mod.vl	15	0
compiler/std/flat/collections.vl	13	0
compiler/std/window/objc.vl	13	0
(27 more; --all lists every one)

justification	sites	unjustified
justified	913	0
try: /Users/magniff/workspace/vole/.claude/worktrees/agent-a754ddc503608ea46/target/volec fix --only unneeded-unsafe
```
