## exact-std: std's positions as the tools print them, compared exactly
## (0.25.3; every other transcript compares them as `<std>:L:C`, so that
## a std change does not break it). std.vl is the start of std's text,
## so an item of std.vl is at the same line in `<std>` (grep, effects)
## and in compiler/std/std.vl (def, in the repository): the two forms
## agree. Only a change to std.vl's first 130 lines moves them.
$ def Option::unwrap
std::Option::unwrap	../../compiler/std/std.vl:134:12	method	pub fn unwrap(sink self) -> T requires self.is_some() else "called unwrap on None"
$ grep 'pub fn unwrap(sink self) -> T' --in std
# <std>
134:5	code	std	pub fn unwrap(sink self) -> T
166:5	code	std	pub fn unwrap(sink self) -> T
$ effects pick --why panic
crate::pick	panic
  'o.unwrap()' at stdpos0253/main.vl:2:5 calls 'Option::unwrap$pre'
  'self.is_some()' at <std>:135:18 is a requires check, which may fail
