## Queries with closures (0.14; tests/query/closures/): references and
## calls inside a closure's body are the enclosing function's; a closure's
## type; a captured use typed as the local; a closure's function and
## environment are no items.
$ refs double
# closures/main.vl
5:4	def	fn double(x: i64) -> i64 {
15:24	call	main	let add = |x: i64| double(x) + k;
16:42	call	main	let n = apply(add, 1i64) + apply(|y| double(y), 2i64);
$ callers double --count
2
$ type closures/main.vl:15:15
closure(i64) -> i64 at closures/main.vl:15:15	|x: i64| double(x) + k
$ type closures/main.vl:15:36
i64	k
$ type closures/main.vl:16:49
i64	y
$ items
crate	closures/main.vl	3
std	<std>	87
$ unused
note query.empty: nothing unused
