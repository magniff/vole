## (0.28.0, gap 88) `query effects MODULE` lists a generic function by its
## instances only: the body's own check, with the type parameters as
## types of their own, is the template, not an instance. `--why` names
## every step: the call of the body a contract wraps has a text.
$ effects crate::count
add_words<Gpa>	alloc(Gpa) panic diverge
$ effects add_words --why alloc
add_words<Gpa>	alloc(Gpa) panic diverge
  'out.push(w.len())' at generic0280/count.vl:5:9 grows a Vec<usize, Gpa>
  'self.grow_one()' at <std>:4901:13 calls 'Vec::grow_one'
  'self.reserve(1)' at <std>:4919:9 grows a Vec<usize, Gpa>
  'the body, after its contract' at <std>:4817:9 grows a Vec<usize, Gpa>
  'self.try_reserve(extra)' at <std>:4820:33 grows a Vec<usize, Gpa>
  'self.grow_to(new_cap)' at <std>:4850:9 calls 'Vec::grow_to'
  'self.alloc.allocate(new_layout)' at <std>:4780:13 allocates from Gpa (an Allocator method)
$ effects add_words --why io
add_words<Gpa>	alloc(Gpa) panic diverge
  (not: io)
