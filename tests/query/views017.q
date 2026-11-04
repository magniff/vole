## View summaries (0.17 T3; tests/query/views017/): declared ones with
## the type filter, std's generic results (parametric: by their type),
## stores, a module's functions with --why, and `views:` in def and show.
## (0.25.5) The program's items and std's by their paths, not every item
## of a name: a std item of the same name does not change the transcript.
$ views crate::first_word crate::pick crate::text_of crate::intern crate::count std::gpu::wgsl::ir::Module::intern std::string::Chars::count
crate::first_word	views(s) declared
crate::pick	views(toks, counts) declared
crate::text_of	views(*toks) declared
crate::intern	views() stores(word) declared
crate::count	views()
std::gpu::wgsl::ir::Module::intern	views() inferred
<std::string::Chars as Iterator>::count	views()
$ views Vec::get Vec::as_slice Vec::push
Vec<Tok, Gpa>::get	views(*self) parametric
Vec<u64, Gpa>::get	views()
Vec<Vec<u64, Gpa>, Gpa>::get	views()
Vec<Function<ScopedArena>, ScopedArena>::get	views(*self) parametric
Vec<JobBuffer<ScopedArena>, ScopedArena>::get	views(*self) parametric
Vec<JobTexture<ScopedArena>, ScopedArena>::get	views(*self) parametric
Vec<Vec<u32, ScopedArena>, ScopedArena>::get	views(*self) parametric
Vec<Tok, Gpa>::as_slice	views(self) declared
Vec<u64, Gpa>::as_slice	views(self) declared
Vec<[i64; 2], Gpa>::as_slice	views(self) declared
Vec<Binding, Gpa>::as_slice	views(self) declared
Vec<VertexInput, Gpa>::as_slice	views(self) declared
Vec<ShaderEntry<Gpa>, Gpa>::as_slice	views(self) declared
Vec<u8, Gpa>::as_slice	views(self) declared
Vec<EntryPoint, Gpa>::as_slice	views(self) declared
Vec<EntryInfo<Gpa>, Gpa>::as_slice	views(self) declared
Vec<BindingInfo, Gpa>::as_slice	views(self) declared
Vec<InputInfo, Gpa>::as_slice	views(self) declared
Vec<i64, Gpa>::as_slice	views(self) declared
Vec<Seg, Gpa>::as_slice	views(self) declared
Vec<Stamp, Gpa>::as_slice	views(self) declared
Vec<Type, ScopedArena>::as_slice	views(self) declared
Vec<StructMember, ScopedArena>::as_slice	views(self) declared
Vec<i64, ScopedArena>::as_slice	views(self) declared
Vec<Block, ScopedArena>::as_slice	views(self) declared
Vec<Param, ScopedArena>::as_slice	views(self) declared
Vec<u8, ScopedArena>::as_slice	views(self) declared
Vec<[u8], ScopedArena>::as_slice	views(self) declared
Vec<Global, ScopedArena>::as_slice	views(self) declared
Vec<Decl, ScopedArena>::as_slice	views(self) declared
Vec<Expr, ScopedArena>::as_slice	views(self) declared
Vec<Entry, ScopedArena>::as_slice	views(self) declared
Vec<Stmt, ScopedArena>::as_slice	views(self) declared
Vec<Case, ScopedArena>::as_slice	views(self) declared
Vec<Function<ScopedArena>, ScopedArena>::as_slice	views(self) declared
Vec<ScopeEntry, ScopedArena>::as_slice	views(self) declared
Vec<Val, ScopedArena>::as_slice	views(self) declared
Vec<Local, ScopedArena>::as_slice	views(self) declared
Vec<Fact, ScopedArena>::as_slice	views(self) declared
Vec<Vec<bool, ScopedArena>, ScopedArena>::as_slice	views(self) declared
Vec<bool, ScopedArena>::as_slice	views(self) declared
Vec<Nm, ScopedArena>::as_slice	views(self) declared
Vec<u32, ScopedArena>::as_slice	views(self) declared
Vec<FnInfo<ScopedArena>, ScopedArena>::as_slice	views(self) declared
Vec<Vec<u32, ScopedArena>, ScopedArena>::as_slice	views(self) declared
Vec<Frame, ScopedArena>::as_slice	views(self) declared
Vec<Inv<ScopedArena>, ScopedArena>::as_slice	views(self) declared
Vec<Ctl, ScopedArena>::as_slice	views(self) declared
Vec<SourceLine, Gpa>::as_slice	views(self) declared
Vec<[u8], Gpa>::as_slice	views(self) declared
Vec<*u8, Gpa>::as_slice	views(self) declared
Vec<Watch, Gpa>::as_slice	views(self) declared
Vec<Event, Gpa>::as_slice	views(self) declared
Vec<Req, Gpa>::as_slice	views(self) declared
Vec<State<Gpa>, Gpa>::as_slice	views(self) declared
Vec<Step<Gpa>, Gpa>::as_slice	views(self) declared
Vec<str, Gpa>::as_slice	views(self) declared
Vec<Buffer, Gpa>::as_slice	views(self) declared
Vec<Vec<u64, Gpa>, Gpa>::as_slice	views(self) declared
Vec<Adapter, ScopedArena>::as_slice	views(self) declared
Vec<JobBuffer<ScopedArena>, ScopedArena>::as_slice	views(self) declared
Vec<JobTexture<ScopedArena>, ScopedArena>::as_slice	views(self) declared
Vec<[u8], Gpa>::push	views() stores(x) declared
Vec<Tok, Gpa>::push	views() stores(x) declared
Vec<u8, Gpa>::push	views()
Vec<u64, Gpa>::push	views()
Vec<Vec<u64, Gpa>, Gpa>::push	views()
Vec<Adapter<Gpa>, Gpa>::push	views()
Vec<ShaderEntry<Gpa>, Gpa>::push	views()
Vec<Buffer, Gpa>::push	views()
Vec<[i64; 2], Gpa>::push	views()
Vec<EntryPoint, Gpa>::push	views() stores(x) declared
Vec<Binding, Gpa>::push	views()
Vec<VertexInput, Gpa>::push	views()
Vec<Seg, Gpa>::push	views()
Vec<Stamp, Gpa>::push	views()
Vec<Type, ScopedArena>::push	views() stores(x) declared
Vec<Expr, ScopedArena>::push	views() stores(x) declared
Vec<[u8], ScopedArena>::push	views() stores(x) declared
Vec<Stmt, ScopedArena>::push	views() stores(x) declared
Vec<i64, ScopedArena>::push	views() stores(x) declared
Vec<Block, ScopedArena>::push	views() stores(x) declared
Vec<u8, ScopedArena>::push	views() stores(x) declared
Vec<Decl, ScopedArena>::push	views() stores(x) declared
Vec<Function<ScopedArena>, ScopedArena>::push	views() stores(x) declared
Vec<StructMember, ScopedArena>::push	views() stores(x) declared
Vec<Global, ScopedArena>::push	views() stores(x) declared
Vec<Param, ScopedArena>::push	views() stores(x) declared
Vec<Entry, ScopedArena>::push	views() stores(x) declared
Vec<ScopeEntry, ScopedArena>::push	views() stores(x) declared
Vec<Local, ScopedArena>::push	views() stores(x) declared
Vec<Case, ScopedArena>::push	views() stores(x) declared
Vec<Val, ScopedArena>::push	views() stores(x) declared
Vec<Fact, ScopedArena>::push	views() stores(x) declared
Vec<Nm, ScopedArena>::push	views() stores(x) declared
Vec<Vec<bool, ScopedArena>, ScopedArena>::push	views() stores(x) declared
Vec<SourceLine, Gpa>::push	views()
Vec<bool, ScopedArena>::push	views() stores(x) declared
Vec<FnInfo<ScopedArena>, ScopedArena>::push	views() stores(x) declared
Vec<Vec<u32, ScopedArena>, ScopedArena>::push	views() stores(x) declared
Vec<u32, ScopedArena>::push	views() stores(x) declared
Vec<Frame, ScopedArena>::push	views() stores(x) declared
Vec<Ctl, ScopedArena>::push	views() stores(x) declared
Vec<Inv<ScopedArena>, ScopedArena>::push	views() stores(x) declared
Vec<JobTexture<ScopedArena>, ScopedArena>::push	views() stores(x) declared
Vec<JobBuffer<ScopedArena>, ScopedArena>::push	views() stores(x) declared
Vec<EntryInfo<Gpa>, Gpa>::push	views()
Vec<InputInfo, Gpa>::push	views()
Vec<i64, Gpa>::push	views()
Vec<BindingInfo, Gpa>::push	views()
Vec<u32, Gpa>::push	views()
Vec<*u8, Gpa>::push	views()
Vec<Event, Gpa>::push	views()
Vec<State<Gpa>, Gpa>::push	views()
Vec<Watch, Gpa>::push	views()
Vec<Req, Gpa>::push	views()
Vec<Step<Gpa>, Gpa>::push	views()
Vec<str, Gpa>::push	views() stores(x) declared
Vec<Adapter, ScopedArena>::push	views() stores(x) declared
$ views crate --why
crate::first_word	views(s) declared
  why: declared (#[views], #[stores]): callers use the declaration, and the body is checked against it
crate::pick	views(toks, counts) declared
  why: declared (#[views], #[stores]): callers use the declaration, and the body is checked against it
crate::text_of	views(*toks) declared
  why: declared (#[views], #[stores]): callers use the declaration, and the body is checked against it
crate::intern	views() stores(word) declared
  why: declared (#[views], #[stores]): callers use the declaration, and the body is checked against it
$ def crate::pick crate::intern crate::count std::iter::Iterator::count std::string::Chars::count
crate::pick	views017/main.vl:17:4	fn	fn pick(toks: Vec<Tok, Gpa>, counts: Vec<i64, Gpa>) -> [Tok]	effects: none	views: views(toks, counts) declared
crate::intern	views017/main.vl:28:4	fn	fn intern(names: inout Vec<[u8], Gpa>, word: [u8])	effects: alloc(Gpa) panic	views: views() stores(word) declared
crate::count	views017/main.vl:32:4	fn	fn count(toks: Vec<Tok, Gpa>) -> i64	effects: none
std::iter::Iterator::count	../../compiler/std/iter.vl:83:8	trait-method	fn count(sink self) -> usize
<std::string::Chars as Iterator>::count	../../compiler/std/string.vl:757:8	method	fn count(sink self) -> usize	effects: panic diverge
$ views nothing_here
error query.no-match: no definition 'nothing_here'
try: volec query items
[exit 1]
