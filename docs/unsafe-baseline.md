# The unsafe baseline

Every unsafe site (an `unsafe { }` block, an `unsafe fn`, an `extern` block)
of the compiler and of std, made by `tests/unsafe_audit.sh -u` from

    volec query unsafe --summary --no-std     # compiler/src (the tree's root)
    volec query unsafe --summary std          # std

on Darwin arm64, fb8d9efe. The gate's unsafe-audit row
(bootstrap/gate.sh, tests/unsafe_audit.sh) fails when either count of
unjustified sites (without `// UNSAFE:` and `// SAFETY:` right above them,
AGENTS.md) rises above its line below; a lower count asks for this file
to be made again. The classes and the comments' rule: `volec query unsafe
--help`, docs/query.md; `unneeded`: unsafe blocks with nothing unsafe
inside (statics are safe), removable as they are.

baseline compiler/src unjustified: 4366
baseline std unjustified: 1194

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
sites: 1204 (977 blocks, 192 unsafe fns, 35 extern blocks); unjustified: 1194; unneeded: 13

class	sites	unjustified
ffi	718	715
raw-pointer	346	341
other	90	89
alloc	39	39
static-mut	6	5
transmute/cast	5	5

module	sites	unjustified
std::gpu	473	471
std	194	194
std::collections	135	135
std::window	77	70
std::sys	74	74
std::objc	63	63
std::sync	54	54
std::slice	53	53
std::fmt	22	22
std::thread	18	18
std::io	10	10
std::hash	8	8
std::iter	8	7
std::num	5	5
std::env	3	3
std::process	3	3
std::random	2	2
std::str	1	1
std::string	1	1

file	sites	unjustified
compiler/std/gpu/hal/metal/bindings.vl	396	396
compiler/std/sys.vl	74	74
compiler/std/window/cocoa.vl	64	57
compiler/std/collections/raw_table.vl	53	53
compiler/std/collections/btree_node.vl	52	52
compiler/std/flat/test.vl	45	45
compiler/std/flat/alloc.vl	43	43
compiler/std/objc/foundation.vl	36	36
compiler/std/gpu/wgsl/interp.vl	34	34
compiler/std/sync/atomic.vl	29	29
compiler/std/flat/fuzz.vl	28	28
compiler/std/gpu/hal/metal/mod.vl	28	26
compiler/std/objc/mod.vl	27	27
compiler/std/fmt.vl	22	22
compiler/std/std.vl	22	22
compiler/std/slice.vl	21	21
compiler/std/flat/arch.vl	20	20
compiler/std/thread.vl	18	18
compiler/std/collections/btree_map.vl	17	17
compiler/std/slice/stable.vl	16	16
(29 more; --all lists every one)

justification	sites	unjustified
missing both	1140	1140
missing UNSAFE:	54	54
justified	10	0
```
