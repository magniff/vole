## `volec query unsafe` (0.25.3; tests/query/unsafe0253/): every kind of
## site (a block, an `unsafe fn`, an extern block), each class but
## intrinsic, the justification's rule (the comments right above the
## statement, inside it before the site, ending its line; not across a
## blank line), a block with nothing unsafe inside, a generic never
## instantiated (checked all the same), the word in a string.
$ unsafe --no-std
unsafe0253/main.vl:7	extern	crate::extern	ffi	justified	3 C functions
unsafe0253/main.vl:23	block	crate::main	alloc	justified	c-call(malloc)
unsafe0253/main.vl:24	block	crate::main	static-mut	missing both	static-index x3
unsafe0253/main.vl:31	block	crate::main	ffi	missing UNSAFE:	c-call(abs)
unsafe0253/main.vl:35	block	crate::main	raw-pointer	justified	unsafe-call(raw::first)
unsafe0253/main.vl:38	block	crate::main	raw-pointer	justified	unsafe-call(raw::sum)
unsafe0253/main.vl:40	block	crate::main	other	justified	union-field
unsafe0253/main.vl:44	block	crate::main	other	missing UNSAFE:	none (unneeded)
unsafe0253/main.vl:47	block	crate::main	transmute/cast	missing both	int-to-ptr
unsafe0253/main.vl:48	block	crate::main	alloc	missing both	c-call(free)
unsafe0253/raw.vl:5	unsafe fn	crate::raw::sum	raw-pointer	justified	index
unsafe0253/raw.vl:13	unsafe fn	crate::raw::first	raw-pointer	missing both	deref
unsafe0253/raw.vl:19	block	crate::raw::peek	raw-pointer	missing both	deref
sites: 13 (10 blocks, 2 unsafe fns, 1 extern blocks); unjustified: 7; unneeded: 1
## A FILE's sites; the unjustified ones.
$ unsafe unsafe0253/raw.vl
unsafe0253/raw.vl:5	unsafe fn	crate::raw::sum	raw-pointer	justified	index
unsafe0253/raw.vl:13	unsafe fn	crate::raw::first	raw-pointer	missing both	deref
unsafe0253/raw.vl:19	block	crate::raw::peek	raw-pointer	missing both	deref
sites: 3 (1 blocks, 2 unsafe fns, 0 extern blocks); unjustified: 2; unneeded: 0
$ unsafe --no-std --unjustified
unsafe0253/main.vl:24	block	crate::main	static-mut	missing both	static-index x3
unsafe0253/main.vl:31	block	crate::main	ffi	missing UNSAFE:	c-call(abs)
unsafe0253/main.vl:44	block	crate::main	other	missing UNSAFE:	none (unneeded)
unsafe0253/main.vl:47	block	crate::main	transmute/cast	missing both	int-to-ptr
unsafe0253/main.vl:48	block	crate::main	alloc	missing both	c-call(free)
unsafe0253/raw.vl:13	unsafe fn	crate::raw::first	raw-pointer	missing both	deref
unsafe0253/raw.vl:19	block	crate::raw::peek	raw-pointer	missing both	deref
sites: 7 (6 blocks, 1 unsafe fns, 0 extern blocks); unjustified: 7; unneeded: 1
## The counts.
$ unsafe --no-std --summary
sites: 13 (10 blocks, 2 unsafe fns, 1 extern blocks); unjustified: 7; unneeded: 1

class	sites	unjustified
raw-pointer	5	2
alloc	2	1
ffi	2	1
other	2	1
static-mut	1	1
transmute/cast	1	1

module	sites	unjustified
crate	10	5
crate::raw	3	2

file	sites	unjustified
unsafe0253/main.vl	10	5
unsafe0253/raw.vl	3	2

justification	sites	unjustified
justified	6	0
missing both	5	5
missing UNSAFE:	2	2
## One object a site.
$ unsafe unsafe0253/raw.vl --json
{"file":"unsafe0253/raw.vl","line":5,"kind":"unsafe fn","item":"crate::raw::sum","class":"raw-pointer","unsafe_comment":true,"safety_comment":true,"justified":true,"checked":true,"ops":"index"}
{"file":"unsafe0253/raw.vl","line":13,"kind":"unsafe fn","item":"crate::raw::first","class":"raw-pointer","unsafe_comment":false,"safety_comment":false,"justified":false,"checked":true,"ops":"deref"}
{"file":"unsafe0253/raw.vl","line":19,"kind":"block","item":"crate::raw::peek","class":"raw-pointer","unsafe_comment":false,"safety_comment":false,"justified":false,"checked":true,"ops":"deref"}
