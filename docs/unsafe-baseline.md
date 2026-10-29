# The unsafe baseline

Every unsafe site (an `unsafe { }` block, an `unsafe fn`, an `extern` block)
of the compiler and of std, made by `tests/unsafe_audit.sh -u` from

    volec query unsafe --summary --no-std     # compiler/src (the tree's root)
    volec query unsafe --summary std          # std

on Darwin arm64, 029e8c96. The gate's unsafe-audit row
(bootstrap/gate.sh, tests/unsafe_audit.sh) fails when either count of
unjustified sites (without `// UNSAFE:` and `// SAFETY:` right above them,
AGENTS.md) rises above its line below; a lower count asks for this file
to be made again. The classes and the comments' rule: `volec query unsafe
--help`, docs/query.md; `unneeded`: unsafe blocks with nothing unsafe
inside (statics are safe), removable as they are.

baseline compiler/src unjustified: 5316
baseline std unjustified: 1194

## compiler/src

```
sites: 5380 (5330 blocks, 10 unsafe fns, 40 extern blocks); unjustified: 5316; unneeded: 938

class	sites	unjustified
static-mut	2459	2420
raw-pointer	1428	1411
other	946	946
ffi	300	296
alloc	134	134
transmute/cast	113	109

module	sites	unjustified
crate::front	1905	1887
crate::tools	1539	1497
crate::back	757	757
crate::middle	754	754
crate::gen0	211	211
crate::base	124	121
crate::arch	70	70
crate::guide	15	15
crate	4	4
crate::cli	1	0

file	sites	unjustified
compiler/src/front/own/drops.vl	85	85
compiler/src/tools/lsp/complete.vl	81	81
compiler/src/back/codecache/mod.vl	65	65
compiler/src/gen0/x86_64.vl	65	65
compiler/src/tools/lsp/answer.vl	65	64
compiler/src/gen0/arm64.vl	58	58
compiler/src/base/mod.vl	55	53
compiler/src/tools/fixconv.vl	54	54
compiler/src/front/own/views.vl	52	52
compiler/src/front/own/state.vl	49	49
compiler/src/base/diag.vl	47	46
compiler/src/front/types.vl	47	47
compiler/src/front/own/walk.vl	46	46
compiler/src/middle/gvn.vl	46	46
compiler/src/middle/parallel.vl	44	44
compiler/src/tools/fixvalues.vl	43	43
compiler/src/middle/inline.vl	42	42
compiler/src/front/own/infer.vl	39	39
compiler/src/front/effects/infer.vl	38	38
compiler/src/middle/loops.vl	38	38
(336 more; --all lists every one)

justification	sites	unjustified
missing both	5316	5316
justified	64	0
```

## std

```
sites: 1202 (975 blocks, 192 unsafe fns, 35 extern blocks); unjustified: 1194; unneeded: 13

class	sites	unjustified
ffi	718	715
raw-pointer	344	341
other	90	89
alloc	39	39
static-mut	6	5
transmute/cast	5	5

module	sites	unjustified
std::gpu	471	471
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
compiler/std/objc/mod.vl	27	27
compiler/std/gpu/hal/metal/mod.vl	26	26
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
justified	8	0
```
