## (0.28.0) `volec query unsafe` on a rust-edition program: a call
## through an `unsafe fn` pointer has no function to name (0.27.8 indexed
## the function table at -1 and stopped, on any rust-edition program with
## std2's sites); it is listed as `unsafe-call(fn pointer)`, class other.
## The pointer's type, `unsafe fn(i64) -> i64`, is no site (0.27.8 listed
## it as an `unsafe fn`, unjustified). Without std, and a FILE's (std read).
$ unsafe --no-std
unsafe0280/main.vl:3	unsafe fn	crate::twice	other	justified	none
unsafe0280/main.vl:11	block	crate::main	other	justified	unsafe-call(fn pointer)
sites: 2 (1 blocks, 1 unsafe fns, 0 extern blocks); unjustified: 0; unneeded: 0
$ unsafe unsafe0280/main.vl
unsafe0280/main.vl:3	unsafe fn	crate::twice	other	justified	none
unsafe0280/main.vl:11	block	crate::main	other	justified	unsafe-call(fn pointer)
sites: 2 (1 blocks, 1 unsafe fns, 0 extern blocks); unjustified: 0; unneeded: 0
