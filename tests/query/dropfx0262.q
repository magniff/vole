## The effects of a drop at a check (0.26.2, dropfx0262/): the places IR's
## drop edges, each a step by the value dropped (a local, a temporary);
## a value given back is not dropped, so 'keep' has none. The same
## drops are calls for refs and callees.
$ effects crate dropfx0262/main.vl
<crate::Loud as Drop>::drop	io panic
crate::quiet	io panic
crate::keep	none
crate::temp	io panic unsafe
crate::main	io panic
$ effects quiet --why io dropfx0262/main.vl
crate::quiet	io panic
  'l' at dropfx0262/main.vl:15:9 calls 'Loud::drop'
  'println("drop {}", self.n)' at dropfx0262/main.vl:9:9 calls 'std::fmt::println'
  'print_acquire()' at <std>:11804:5 calls 'std::fmt::print_acquire'
  'print_acquire_held()' at <std>:11714:9 calls 'std::fmt::print_acquire_held'
  (no source found)
$ effects temp --why io dropfx0262/main.vl
crate::temp	io panic unsafe
  'Loud { n: n }' at dropfx0262/main.vl:27:5 calls 'Loud::drop'
  'println("drop {}", self.n)' at dropfx0262/main.vl:9:9 calls 'std::fmt::println'
  'print_acquire()' at <std>:11804:5 calls 'std::fmt::print_acquire'
  'print_acquire_held()' at <std>:11714:9 calls 'std::fmt::print_acquire_held'
  (no source found)
$ refs 'Loud::drop' dropfx0262/main.vl
# dropfx0262/main.vl
8:8	def	fn drop(inout self) {
15:9	call	quiet	let l = Loud { n: n };
27:5	call	temp	Loud { n: n }.n
32:9	call	main	let k = keep(3);
$ callees quiet dropfx0262/main.vl
1	call	<Loud as Drop>::drop	dropfx0262/main.vl:8
