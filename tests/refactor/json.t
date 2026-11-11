## --json (0.15, tests/refactor/json/): every diagnostic, and every line of
## output, one JSON object per line, for a harness rather than a reader
## (the check hook, the agent eval); the try: lines as the agent would run
## them, without --json.
$ check --json
$ query def add --json
crate::add	main.vl:3:4	fn	fn add(a: i64, b: i64) -> i64	effects: none
std::ops::Add::add	<std>:239:8	trait-method	fn add(self, rhs: Rhs) -> Self::Output
std::ptr::NonNull::add	<std>:1600:19	method	pub unsafe fn add(self, count: usize) -> NonNull<T>
*const T::add	<std>:1717:19	method	pub unsafe fn add(self, count: usize) -> *mut T
std::alloc::Chunks::add	<std>:3301:8	method	fn add<P: Allocator>(&self, parent: &P, bytes: usize) -> Result<(), AllocError>
<std::intconv::Wrapping as Add>::add	<std>:10531:8	method	fn add(self, rhs: Wrapping<T>) -> Wrapping<T>
<std::string::String as Add>::add	<std>:9945:8	method	fn add(self, other: &'b str) -> String<A>
std::flt::Big::add	<std>:15411:8	method	fn add(&mut self, o: &Big)	effects: panic diverge
<std::time::Duration as Add>::add	<std>:32055:8	method	fn add(self, rhs: Duration) -> Duration	effects: panic
<std::time::Instant as Add>::add	<std>:32336:8	method	fn add(self, d: Duration) -> Instant	effects: panic
<std::time::SystemTime as Add>::add	<std>:32429:8	method	fn add(self, d: Duration) -> SystemTime	effects: panic
std::gpu::Unwritten::add	<std>:32833:8	method	fn add(&mut self, o: Unwritten, group: i64)	effects: panic
## (quotes and tabs escaped)
$ query grep bad --json
# main.vl
9:18	string	main	println("bad");
$ query show nosuch --json
{"kind":"diagnostic","severity":"error","code":"query.no-match","file":null,"line":null,"col":null,"message":"no definition 'nosuch'","help":[],"notes":[],"try":["volec query items"]}
[exit 1]
## An edit's new errors, its refusal, its summary.
$ edit patch add --old 'a + b' --new 'a + q' --json
{"kind":"diagnostic","severity":"error","code":"type error","file":"main.vl","line":4,"col":9,"message":"undefined variable 'q'  [edited: crate::add]","help":[],"notes":[],"try":[]}
{"kind":"diagnostic","severity":"error","code":"edit.breaks","file":null,"line":null,"col":null,"message":"1 new error; nothing written; the error: main.vl:4:9: undefined variable 'q'","help":[],"notes":[],"try":[]}
{"kind":"diagnostic","severity":"note","code":"edit.together","file":null,"line":null,"col":null,"message":"several steps are one call, checked at its end: `edit patch NAME --old A --new B --old C --new D` (`--in OTHER` before another item's pairs), `edit apply FILE`; or this step alone with --no-check","help":[],"notes":[],"try":["volec edit patch add --old 'a + b' --new 'a + q' --no-check"]}
[exit 1]
$ edit patch add --old 'a + b' --new 'b + a' --json
{"kind":"output","fields":["patched crate::add","main.vl","+1 -1 lines"]}
$ undo --json
{"kind":"output","fields":["undid patched crate::add","main.vl","+1 -1 lines"]}
## A compiler error with help and its position; --json anywhere on the line.
% printf '// Two errors.\nfn main() {\n    let x: i64 = "s\\t";\n    prinln("{}", x);\n}\n// EDITION: rust\n' > bad.vl
$ --json check bad.vl
{"kind":"diagnostic","severity":"error","code":"type error","file":"bad.vl","line":3,"col":18,"message":"expected 'i64', got '&str'","help":[],"notes":[],"try":[]}
{"kind":"diagnostic","severity":"error","code":"type error","file":"bad.vl","line":4,"col":5,"message":"undefined variable 'prinln'","help":["did you mean 'println'?"],"notes":[],"try":["volec fix --suggested bad.vl"]}
[exit 1]
$ bad.vl -o prog --json
{"kind":"diagnostic","severity":"error","code":"type error","file":"bad.vl","line":3,"col":18,"message":"expected 'i64', got '&str'","help":[],"notes":[],"try":[]}
{"kind":"diagnostic","severity":"error","code":"type error","file":"bad.vl","line":4,"col":5,"message":"undefined variable 'prinln'","help":["did you mean 'println'?"],"notes":[],"try":["volec fix --suggested bad.vl"]}
[exit 1]
## A build whose stderr is not a terminal (here, a file) prints check's
## one-line form; --diagnostics=human the human form.
$ bad.vl -o prog
bad.vl:3:18: error[type error] expected 'i64', got '&str'
bad.vl:4:5: error[type error] undefined variable 'prinln' | help: did you mean 'println'? | try: volec fix --suggested bad.vl
[exit 1]
$ --diagnostics=human bad.vl -o prog
error[type error]: expected 'i64', got '&str'
 --> bad.vl: line 3, column 18
error[type error]: undefined variable 'prinln'
 --> bad.vl: line 4, column 5
  = help: did you mean 'println'?
  = try: volec fix --suggested bad.vl
[exit 1]
