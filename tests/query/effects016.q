## The effects inferred (0.16 T1; tests/query/effects016/): a source of
## each effect, C's table and declarations, unknown C and its callbacks,
## recursion, counted loops and in-bounds indexes, allocators (the
## encapsulation rule, instances with different A, a scope's discharge),
## closures and fn values (closed world).
$ effects putchar malloc labs qsort mystery ext_pure
crate::putchar	io
crate::malloc	alloc(extern)
crate::labs	none
crate::qsort	alloc(Gpa, ArenaScope<Gpa>, extern) io panic diverge
crate::mystery	io
crate::ext_pure	none
$ effects plus bump address at part whole color sum same spin forever fact even odd
crate::plus	none
crate::bump	none
Chunks::bump<Gpa>	alloc(Gpa) panic diverge unsafe
crate::address	none
crate::at	panic
crate::part	panic
crate::whole	none
std::window::script::whole	alloc(Gpa, ArenaScope<Gpa>) io panic diverge
crate::color	panic diverge
std::gpu::PassDesc::color	none
crate::sum	none
crate::same	panic diverge
crate::spin	diverge
crate::forever	diverge
crate::fact	diverge
crate::even	diverge
crate::odd	diverge
## effects: qsort is C the table does not know: it may call every
## address-taken `extern "C" fn` of the program, and std::window's callbacks
## (std is read whole by a query) allocate from Gpa and an arena.
$ effects deref raw_index trusted calls_c declared heap out by_c sorter main t0
crate::deref	unsafe
Vec<EntryPoint, Gpa>::deref	none
Vec<VertexInput, Gpa>::deref	none
Vec<[i64; 2], Gpa>::deref	none
Vec<Buffer, Gpa>::deref	none
crate::raw_index	unsafe
crate::trusted	unsafe
crate::calls_c	unsafe
crate::declared	io unsafe
crate::heap	alloc(extern) unsafe
crate::out	io unsafe
crate::by_c	none
crate::sorter	alloc(Gpa, ArenaScope<Gpa>, extern) io panic diverge unsafe
crate::main	alloc(Gpa, ArenaScope<Gpa>, extern) io panic diverge unsafe
crate::t0	none
$ effects Bump::allocate Bump::deallocate fill_one in_scope apply double shout hof allocators
<crate::Bump as Allocator>::allocate	unsafe
<crate::Bump as Allocator>::deallocate	unsafe
fill_one<Gpa>	alloc(Gpa) panic diverge
fill_one<Bump>	alloc(Bump) panic diverge
fill_one<A>	alloc io tls thread sync panic diverge (unknown)
crate::in_scope	alloc(Gpa) diverge
crate::apply	io
crate::double	none
crate::shout	io
hof<closure(i64) -> i64 at effects016/main.vl:134:9>	none
hof<closure(i64) -> i64 at effects016/main.vl:134:29>	io
hof<F>	io
crate::allocators	alloc(Gpa, Bump) io panic diverge
