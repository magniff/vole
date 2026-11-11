## The effects of a drop at a check (0.26.2, dropfx0262/): the places IR's
## drop edges, each a step by the value dropped (a local, a temporary);
## a value given back is not dropped, so 'keep' has none. The same
## drops are calls for refs and callees.
## effects: carries alloc(Gpa, ArenaScope<Gpa>) from every fmt::Write impl
## instance in std (gap: dyn Write's join is over all instances, gated modules
## included); to be re-recorded when the join is limited to reachable instances.
$ effects crate dropfx0262/main.vl
<crate::Loud as Drop>::drop	alloc(Gpa, ArenaScope<Gpa>) io panic diverge
crate::quiet	alloc(Gpa, ArenaScope<Gpa>) io panic diverge
crate::keep	none
crate::temp	alloc(Gpa, ArenaScope<Gpa>) io panic diverge unsafe
crate::main	alloc(Gpa, ArenaScope<Gpa>) io panic diverge
## effects: carries alloc(Gpa, ArenaScope<Gpa>) from every fmt::Write impl
## instance in std (gap: dyn Write's join is over all instances, gated modules
## included); to be re-recorded when the join is limited to reachable instances.
$ effects quiet --why io dropfx0262/main.vl
crate::quiet	alloc(Gpa, ArenaScope<Gpa>) io panic diverge
  'l' at dropfx0262/main.vl:15:9 calls 'Loud::drop'
  'println("drop {}", self.n)' at dropfx0262/main.vl:9:9 calls 'std::fmt::println'
  (no source found)
std::test::quiet	io unsafe
  'test_c_open("/dev/null\0".as_ptr(), 1)' at <std>:34283:20 calls C's 'open'
## effects: carries alloc(Gpa, ArenaScope<Gpa>) from every fmt::Write impl
## instance in std (gap: dyn Write's join is over all instances, gated modules
## included); to be re-recorded when the join is limited to reachable instances.
$ effects temp --why io dropfx0262/main.vl
crate::temp	alloc(Gpa, ArenaScope<Gpa>) io panic diverge unsafe
  'Loud { n: n }' at dropfx0262/main.vl:27:5 calls 'Loud::drop'
  'println("drop {}", self.n)' at dropfx0262/main.vl:9:9 calls 'std::fmt::println'
  (no source found)
$ refs 'Loud::drop' dropfx0262/main.vl
# dropfx0262/main.vl
8:8	def	fn drop(&mut self) {
15:9	call	quiet	let l = Loud { n: n };
27:5	call	temp	Loud { n: n }.n
32:9	call	main	let k = keep(3);
$ callees quiet dropfx0262/main.vl
1	call	<Loud as Drop>::drop	dropfx0262/main.vl:8
1	call	std::test::test_c_close	<std>:33908
1	call	std::test::test_c_dup2	<std>:33906
1	call	std::test::test_c_open	<std>:33910
1	call	str::as_ptr	<std>:7002
