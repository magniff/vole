## XFAIL: RT-84: query refs NAME, for a program's `use .. as NAME` alias, answers about a private std item of that name and not the alias (0.30.2)
## (a tests/refactor transcript: tests/query has no XFAIL.) `use a::helper as h2;` and `h2()` in main. With the alias named hz,
## `query refs hz` lists a::helper's definition, the use and the call (the
## lines below). Named h2, it lists std::collections::hash_map's private
## `fn h2(hash: u64) -> u8` and its two calls in RawTable::put and
## HashMap::find, and nothing of the program: the program's own name is
## passed over for std's (`len` as the alias: 959 refs in std).
$ query refs h2
# a.vl
1:8	def	pub fn helper() -> i64 {
# main.vl
3:8	use	crate	use a::helper as h2;
6:19	call	main	println("{}", h2());
