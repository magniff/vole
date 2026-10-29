# The unsafe baseline

Every unsafe site (an `unsafe { }` block, an `unsafe fn`, an `extern` block)
of the compiler and of std, made by `tests/unsafe_audit.sh -u` from

    volec query unsafe --summary --no-std     # compiler/src (the tree's root)
    volec query unsafe --summary std          # std

on Darwin arm64, 53804bcf. The gate's unsafe-audit row
(bootstrap/gate.sh, tests/unsafe_audit.sh) fails when either count of
unjustified sites (without `// UNSAFE:` and `// SAFETY:` right above them,
AGENTS.md) rises above its line below; a lower count asks for this file
to be made again. The classes and the comments' rule: `volec query unsafe
--help`, docs/query.md; `unneeded`: unsafe blocks with nothing unsafe
inside (statics are safe), removable as they are.

baseline compiler/src unjustified: 5315
baseline std unjustified: 0

## compiler/src

```
sites: 5408 (5357 blocks, 10 unsafe fns, 41 extern blocks); unjustified: 5315; unneeded: 938

class	sites	unjustified
static-mut	2480	2419
raw-pointer	1431	1412
other	946	946
ffi	302	294
alloc	134	134
transmute/cast	115	110

module	sites	unjustified
crate::front	1921	1886
crate::tools	1543	1497
crate::back	760	757
crate::middle	754	754
crate::gen0	211	211
crate::base	129	121
crate::arch	70	70
crate::guide	15	15
crate	4	4
crate::cli	1	0

file	sites	unjustified
compiler/src/front/own/drops.vl	86	85
compiler/src/tools/lsp/complete.vl	81	81
compiler/src/tools/lsp/answer.vl	66	64
compiler/src/back/codecache/mod.vl	65	65
compiler/src/gen0/x86_64.vl	65	65
compiler/src/gen0/arm64.vl	58	58
compiler/src/base/mod.vl	55	53
compiler/src/tools/fixconv.vl	54	54
compiler/src/front/own/views.vl	52	52
compiler/src/front/own/state.vl	49	49
compiler/src/base/diag.vl	48	46
compiler/src/front/types.vl	47	46
compiler/src/front/own/walk.vl	46	46
compiler/src/middle/gvn.vl	46	46
compiler/src/middle/parallel.vl	44	44
compiler/src/tools/fixvalues.vl	43	43
compiler/src/middle/inline.vl	42	42
compiler/src/front/own/infer.vl	39	39
compiler/src/front/own/moves.vl	39	33
compiler/src/front/effects/infer.vl	38	38
(340 more; --all lists every one)

justification	sites	unjustified
missing both	5315	5315
justified	93	0
```

## std

```
sites: 891 (669 blocks, 188 unsafe fns, 34 extern blocks); unjustified: 0; unneeded: 3

class	sites	unjustified
ffi	456	0
raw-pointer	317	0
other	72	0
alloc	38	0
transmute/cast	5	0
static-mut	3	0

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
std::str	7	0
std::iter	6	0
std::io	5	0
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
justified	891	0
```
