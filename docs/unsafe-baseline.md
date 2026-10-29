# The unsafe baseline

Every unsafe site (an `unsafe { }` block, an `unsafe fn`, an `extern` block)
of the compiler and of std, made by `tests/unsafe_audit.sh -u` from

    volec query unsafe --summary --no-std     # compiler/src (the tree's root)
    volec query unsafe --summary std          # std

on Darwin arm64, 8f222dd7. The gate's unsafe-audit row
(bootstrap/gate.sh, tests/unsafe_audit.sh) fails when either count of
unjustified sites (without `// UNSAFE:` and `// SAFETY:` right above them,
AGENTS.md) rises above its line below; a lower count asks for this file
to be made again. The classes and the comments' rule: `volec query unsafe
--help`, docs/query.md; `unneeded`: unsafe blocks with nothing unsafe
inside (statics are safe), removable as they are.

baseline compiler/src unjustified: 4366
baseline std unjustified: 0

## compiler/src

```
sites: 4478 (4427 blocks, 10 unsafe fns, 41 extern blocks); unjustified: 4366; unneeded: 0

class	sites	unjustified
static-mut	2486	2411
raw-pointer	1429	1410
ffi	304	293
alloc	134	134
transmute/cast	116	110
other	9	8

module	sites	unjustified
crate::front	1685	1641
crate::tools	1224	1169
crate::middle	728	728
crate::back	579	576
crate::base	109	101
crate::gen0	87	87
crate::arch	51	51
crate::guide	10	10
crate	3	3
crate::cli	2	0

file	sites	unjustified
compiler/src/front/own/drops.vl	78	77
compiler/src/tools/lsp/complete.vl	61	61
compiler/src/tools/lsp/answer.vl	59	57
compiler/src/back/codecache/mod.vl	57	57
compiler/src/base/mod.vl	55	53
compiler/src/tools/fixconv.vl	50	50
compiler/src/front/own/views.vl	45	45
compiler/src/front/types.vl	44	43
compiler/src/middle/gvn.vl	44	44
compiler/src/middle/inline.vl	41	41
compiler/src/middle/parallel.vl	39	39
compiler/src/middle/loops.vl	38	38
compiler/src/base/diag.vl	37	35
compiler/src/front/own/state.vl	37	37
compiler/src/tools/fixvalues.vl	37	37
compiler/src/front/check/synth_mode.vl	36	32
compiler/src/front/own/moves.vl	36	30
compiler/src/front/own/walk.vl	34	34
compiler/src/back/objfile/mod.vl	33	33
compiler/src/front/conv.vl	33	32
(329 more; --all lists every one)

justification	sites	unjustified
missing both	4366	4366
justified	112	0
```

## std

```
sites: 893 (671 blocks, 188 unsafe fns, 34 extern blocks); unjustified: 0; unneeded: 3

class	sites	unjustified
ffi	456	0
raw-pointer	317	0
other	72	0
alloc	39	0
transmute/cast	5	0
static-mut	4	0

module	sites	unjustified
std::gpu	267	0
std	123	0
std::collections	118	0
std::window	74	0
std::sys	73	0
std::slice	53	0
std::sync	52	0
std::objc	51	0
std::fmt	22	0
std::thread	18	0
std::hash	8	0
std::io	7	0
std::str	7	0
std::iter	6	0
std::num	5	0
std::env	3	0
std::process	3	0
std::random	2	0
std::string	1	0

file	sites	unjustified
compiler/std/gpu/hal/metal/bindings.vl	226	0
compiler/std/sys.vl	73	0
compiler/std/window/cocoa.vl	61	0
compiler/std/collections/raw_table.vl	52	0
compiler/std/flat/alloc.vl	41	0
compiler/std/collections/btree_node.vl	38	0
compiler/std/objc/mod.vl	29	0
compiler/std/gpu/hal/metal/mod.vl	28	0
compiler/std/sync/atomic.vl	25	0
compiler/std/fmt.vl	22	0
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
(26 more; --all lists every one)

justification	sites	unjustified
justified	893	0
```
