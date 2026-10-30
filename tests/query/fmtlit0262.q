## 0.26.2: a format literal's holes are seen as an f-string's: the type
## of a name in a hole (and of a width's `name$`), and refs of a local
## and of a const find their uses in the literal's text; a plain literal
## that is no format string (`s`) has no reference.
$ type fmtlit0262/main.vl:6:15
i64	count
$ type fmtlit0262/main.vl:6:37
i64	width
$ type fmtlit0262/main.vl:6:13
Interp<closure(*Fmt) -> () at fmtlit0262/main.vl:6:13>	"{count} items, {count:>width$} of {LIMIT}"
$ refs fmtlit0262/main.vl:4:9
# fmtlit0262/main.vl
4:9	def	let count = 3;
6:15	read	main	println("{count} items, {count:>width$} of {LIMIT}");
6:30	read	main	println("{count} items, {count:>width$} of {LIMIT}");
7:19	read	main	println("{}", count);
$ refs fmtlit0262/main.vl:5:9
# fmtlit0262/main.vl
5:9	def	let width = 6;
6:37	read	main	println("{count} items, {count:>width$} of {LIMIT}");
$ refs LIMIT --in fmtlit0262/main.vl
# fmtlit0262/main.vl
1:7	def	const LIMIT: i64 = 9;
6:49	read	main	println("{count} items, {count:>width$} of {LIMIT}");
