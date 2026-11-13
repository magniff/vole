## The syntax of 0.16 parses and checks (phase 0: declarations are
## accepted, effects not inferred yet): items, the parts shown, the
## minimal `query effects`.
$ items
crate	syntax016/main.vl	10
std	<std>	607
$ show apply grow_by_one
// crate::apply	syntax016/main.vl:31-35
#[no_alloc]
#[no_io]
fn apply<F: Fn(i64) -> i64 + effects(panic)>(f: F, x: i64) -> i64 {
    f(x)
}
// crate::grow_by_one	syntax016/main.vl:37-40	effects: alloc(Gpa) panic diverge
#[effects(alloc(Gpa), panic, diverge)]
fn grow_by_one(v: &mut Vec<i64, Gpa>) {
    v.push(1);
}
$ show crate::Pair
// crate::Pair	syntax016/main.vl:29-29
struct Pair<T, U = i64> { a: T, b: U }
$ refs Pair
# syntax016/main.vl
29:8	def	struct Pair<T, U = i64> { a: T, b: U }
44:12	type	main	let p: Pair<i64> = Pair { a: s.area(), b: unsafe { labs(-2) } };
44:24	init	main	let p: Pair<i64> = Pair { a: s.area(), b: unsafe { labs(-2) } };
$ effects apply grow_by_one main
apply<closure(i64) -> i64 at syntax016/main.vl:47:32>	none
crate::grow_by_one	alloc(Gpa) panic diverge
crate::main	alloc(Gpa) io static panic diverge unsafe
$ def Vec::new_in
std::vec::Vec::new_in	<std>:4854:12	method	pub fn new_in(a: A) -> Vec<T, A>
