## (0.17; 0.26.3: format literals, f-strings removed) A format literal
## passed to println, push_fmt or format_in is written in place (no
## closure, no Interp): its type is still shown as format_args', a name
## in a hole has its own type, the call is still a reference of println,
## push_fmt and format_in, and what its writes do is the call's.
$ type fstring017/main.vl:9:13
Interp<closure(*Fmt) -> () at fstring017/main.vl:9:13>	"n = {n}"
$ type fstring017/main.vl:10:10
Interp<closure(&mut Formatter) -> () at fstring017/main.vl:10:22>	format_args("n = {n}")
$ type fstring017/main.vl:9:19
i64	n
$ type fstring017/main.vl:12:29
Interp<closure(*Fmt) -> () at fstring017/main.vl:12:29>	"[{n}]"
$ refs println std::fmt::write format_in --in fstring017/main.vl
# fstring017/main.vl
4:5	call	show	->std::fmt::println	println("{}", x);
9:5	call	main	->std::fmt::println	println("n = {n}");
12:5	call	main	->std::fmt::write	std::fmt::write(&mut b, "[{n}]").unwrap();
13:17	call	main	->std::fmt::format_in	let mut t = format_in("{n}!", gpa);
14:5	call	main	->std::fmt::println	println("{}", str::from_utf8(t.as_bytes()).unwrap());
$ effects main --why io
crate::main	alloc(Gpa) io panic diverge
  'println("n = {n}")' at fstring017/main.vl:9:5 calls 'std::fmt::println'
  (no source found)
