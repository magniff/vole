## `query effects` (0.16 T5): a module's functions, --has, --why, the
## effects column of def, show and context (left out for a set the front
## end could not infer: front/effects/ infers them, 0.16 T1), and the
## errors. (On syntax016/'s program.)
$ effects crate syntax016/main.vl
crate::out_write	io
crate::labs	none
<crate::Square as Shape>::area	none
apply<closure(i64) -> i64 at syntax016/main.vl:47:32>	none
crate::grow_by_one	alloc(Gpa) panic diverge
crate::main	alloc(Gpa) io panic diverge unsafe
$ effects crate --has io syntax016/main.vl
crate::out_write	io
crate::main	alloc(Gpa) io panic diverge unsafe
$ effects grow_by_one --why alloc syntax016/main.vl
crate::grow_by_one	alloc(Gpa) panic diverge
  'v.push(1)' at syntax016/main.vl:39:5 grows a Vec<i64, Gpa>
  'self.grow_one()' at <std>:5064:13 calls 'Vec::grow_one'
  'self.reserve(1)' at <std>:5083:9 grows a Vec<i64, Gpa>
  'the body, after its contract' at <std>:5026:9 grows a Vec<i64, Gpa>
  'self.try_reserve(extra)' at <std>:4978:33 grows a Vec<i64, Gpa>
  'self.grow_to(new_cap)' at <std>:5010:9 calls 'Vec::grow_to'
  'self.alloc.allocate(new_layout)' at <std>:4933:13 allocates from Gpa (an Allocator method)
$ effects grow_by_one --why 'alloc(Arena)' syntax016/main.vl
crate::grow_by_one	alloc(Gpa) panic diverge
  (not: alloc(Arena))
$ effects grow_by_one --has allocates syntax016/main.vl
error query.usage: unknown effect 'allocates' (effects: alloc, alloc(T), io, static, panic, diverge, unsafe, none)
[exit 2]
$ effects Pair syntax016/main.vl
note query.empty: no function among the names
[exit 1]
$ def grow_by_one syntax016/main.vl
crate::grow_by_one	syntax016/main.vl:38:4	fn	fn grow_by_one(v: &mut Vec<i64, Gpa>)	effects: alloc(Gpa) panic diverge
