## (0.17; 0.26.3: format literals, f-strings removed) A format literal
## passed to println, push_fmt or format_in is written in place (no
## closure, no Interp): its type is still shown as format_args', a name
## in a hole has its own type, the call is still a reference of println,
## push_fmt and format_in, and what its writes do is the call's.
$ type fstring017/main.vl:9:13
Interp<closure(*Fmt) -> () at fstring017/main.vl:9:13>	"n = {n}"
$ type fstring017/main.vl:10:10
Interp<closure(inout Fmt) -> () at fstring017/main.vl:10:22>	format_args("n = {n}")
$ type fstring017/main.vl:9:19
i64	n
$ type fstring017/main.vl:12:16
Interp<closure(inout Fmt) -> () at fstring017/main.vl:12:16>	"[{n}]"
$ refs println push_fmt format_in --in fstring017/main.vl
# fstring017/main.vl
1:30	use	crate	->std::fmt::format_in	use std::{Buf, Display, Gpa, format_in, println};
1:41	use	crate	->std::fmt::println	use std::{Buf, Display, Gpa, format_in, println};
4:5	call	show	->std::fmt::println	println(x);
9:5	call	main	->std::fmt::println	println("n = {n}");
12:7	call	main	->std::string::String::push_fmt	b.push_fmt("[{n}]");
13:13	call	main	->std::fmt::format_in	var t = format_in("{n}!", gpa);
14:5	call	main	->std::fmt::println	println(t.as_slice());
$ effects main --why io
crate::main	alloc(Gpa) io panic diverge
  'println("n = {n}")' at fstring017/main.vl:9:5 calls 'std::fmt::println'
  'print_acquire()' at <std>:10886:5 calls 'std::fmt::print_acquire'
  'print_acquire_held()' at <std>:10847:9 calls 'std::fmt::print_acquire_held'
  (no source found)
