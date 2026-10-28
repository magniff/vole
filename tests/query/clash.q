## Names that clash (clash/): two modules with `helper`; a struct a::Point
## and a function geom::Point; `len` on two types (and std's); a trait's
## `add` and an inherent `add`; a local named `helper`; an alias import;
## std's Vec::push and a user Vec's push; c::printf and a user printf.
## (Nothing here prints a position in <C import>, whose line numbers
## depend on the host's headers.)
$ def helper
crate::a::helper	clash/a.vl:2:8	fn	pub fn helper() -> i64	effects: none
crate::b::helper	clash/b.vl:1:8	fn	pub fn helper() -> i64	effects: none
$ refs helper
# clash/a.vl
2:8	def	->a::helper	pub fn helper() -> i64 {
# clash/b.vl
1:8	def	->b::helper	pub fn helper() -> i64 {
# clash/main.vl
15:8	use	crate	->a::helper	use a::helper as a_helper;
32:13	call	main	->a::helper	let n = a_helper() + b::helper() + helper;
32:29	call	main	->b::helper	let n = a_helper() + b::helper() + helper;
$ refs a::helper
# clash/a.vl
2:8	def	pub fn helper() -> i64 {
# clash/main.vl
15:8	use	crate	use a::helper as a_helper;
32:13	call	main	let n = a_helper() + b::helper() + helper;
$ refs crate::b::helper --count
2
$ callers helper
# clash/main.vl
32:13	call	main	->a::helper	let n = a_helper() + b::helper() + helper;
32:29	call	main	->b::helper	let n = a_helper() + b::helper() + helper;
$ def --exact helper
error query.no-match: no definition 'helper'
try: volec query def crate::a::helper
try: volec query def crate::b::helper
try: volec query def std::gpu::wgsl::msl::helpers
[exit 1]
$ def --exact crate::a::helper
crate::a::helper	clash/a.vl:2:8	fn	pub fn helper() -> i64	effects: none
$ def Point
crate::a::Point	clash/a.vl:6:12	struct	pub struct Point
crate::geom::Point	clash/geom.vl:4:8	fn	pub fn Point(x: i64) -> i64	effects: none
std::window::objc::Point	../../compiler/std/window/objc.vl:25:12	struct	pub struct Point
$ refs Point
# clash/a.vl
6:12	def	->a::Point	pub struct Point {
# clash/geom.vl
4:8	def	->geom::Point	pub fn Point(x: i64) -> i64 {
# clash/main.vl
16:12	use	crate	->geom::Point	use geom::{Point, V2};
33:16	init	main	->a::Point	let p = a::Point { x: Point(n) };
33:27	call	main	->geom::Point	let p = a::Point { x: Point(n) };
# <std>
46505:16	use	std::window::cocoa	->std::window::objc::Point	NOT_FOUND, Point, Range, Rect, class, class_addIvar, class_addProtocol,
46562:61	type	std::window::cocoa::add_u_t	->std::window::objc::Point	fn add_u_t(c: *u8, s: *u8, imp: extern "C" fn(*u8, *u8, Point) -> u64, t: *u8) -> bool;
46697:25	init	std::window::cocoa::post_wake	->std::window::objc::Point	EV_APP_DEFINED, Point { x: 0.0, y: 0.0 }, 0, 0.0, 0, 0 as *u8, 0, WAKE, 0);
47061:54	type	std::window::cocoa::imp_char_index	->std::window::objc::Point	extern "C" fn imp_char_index(this: *u8, cmd: *u8, p: Point) -> u64 {
48447:12	def	->std::window::objc::Point	pub struct Point {
48533:53	type	std::window::objc::msg_p_utudipsii	->std::window::objc::Point	fn msg_p_utudipsii(o: *u8, s: *u8, ty: u64, at: Point, flags: u64, time: f64, win: i64,
48538:54	type	std::window::objc::msg_p_utudipppbh	->std::window::objc::Point	fn msg_p_utudipppbh(o: *u8, s: *u8, ty: u64, at: Point, flags: u64, time: f64, win: i64,
48543:53	type	std::window::objc::msg_p_utudipiif	->std::window::objc::Point	fn msg_p_utudipiif(o: *u8, s: *u8, ty: u64, at: Point, flags: u64, time: f64, win: i64,
48602:33	type	std::window::objc::msg_t	->std::window::objc::Point	fn msg_t(o: *u8, s: *u8) -> Point;
48614:36	type	std::window::objc::msg_t_tp	->std::window::objc::Point	fn msg_t_tp(o: *u8, s: *u8, a: Point, b: *u8) -> Point;
48614:54	type	std::window::objc::msg_t_tp	->std::window::objc::Point	fn msg_t_tp(o: *u8, s: *u8, a: Point, b: *u8) -> Point;
$ show a::Point
// crate::a::Point	clash/a.vl:6-8
pub struct Point {
    pub x: i64,
}
$ def len
crate::geom::V2::len	clash/geom.vl:15:12	method	pub fn len(self) -> i64	effects: none
crate::myvec::Vec::len	clash/myvec.vl:11:12	method	pub fn len(self) -> i64	effects: none
std::Vec::len	../../compiler/std/std.vl:205:12	method	pub fn len(self) -> i64
std::Buf::len	../../compiler/std/std.vl:507:12	method	pub fn len(self) -> i64
std::BinaryHeap::len	../../compiler/std/flat/collections.vl:192:12	method	pub fn len(self) -> i64
std::MinHeap::len	../../compiler/std/flat/collections.vl:288:12	method	pub fn len(self) -> i64
std::collections::hash_map::HashMap::len	../../compiler/std/collections/hash_map.vl:38:12	method	pub fn len(self) -> i64
std::collections::hash_set::HashSet::len	../../compiler/std/collections/hash_set.vl:36:12	method	pub fn len(self) -> i64
std::collections::raw_table::RawTable::len	../../compiler/std/collections/raw_table.vl:137:12	method	pub fn len(self) -> i64
std::collections::btree_node::BTreeRaw::len	../../compiler/std/collections/btree_node.vl:236:12	method	pub fn len(self) -> i64
std::collections::btree_map::BTreeMap::len	../../compiler/std/collections/btree_map.vl:26:12	method	pub fn len(self) -> i64
std::collections::btree_map::BTreeSet::len	../../compiler/std/collections/btree_map.vl:216:12	method	pub fn len(self) -> i64
str::len	../../compiler/std/string.vl:287:12	method	pub fn len(self) -> i64	effects: none
std::string::String::len	../../compiler/std/string.vl:1165:12	method	pub fn len(self) -> i64
Path::len	../../compiler/std/path.vl:49:12	method	pub fn len(self) -> i64	effects: none
std::fs::Metadata::len	../../compiler/std/fs.vl:205:12	method	pub fn len(self) -> i64	effects: none
std::env::Args::len	../../compiler/std/env.vl:70:12	method	pub fn len(self) -> i64	effects: none
$ refs V2::len
# clash/geom.vl
15:12	def	pub fn len(self) -> i64 {
# clash/main.vl
40:17	call	main	mine.push(v.len());
$ refs myvec::Vec::len
# clash/main.vl
47:74	call	main	let total = twice_generic(sq) + twice_generic(v) + sq.twice() + mine.len() + printf(r);
# clash/myvec.vl
11:12	def	pub fn len(self) -> i64 {
$ def V2::add
<crate::geom::V2 as Add>::add	clash/geom.vl:21:8	method	fn add(self, o: V2) -> V2	effects: none
$ def Vec::add
crate::myvec::Vec::add	clash/myvec.vl:15:12	method	pub fn add(inout self, k: i64)	effects: none
$ refs '<V2 as Add>::add'
# clash/geom.vl
21:8	def	fn add(self, o: V2) -> V2 {
# clash/main.vl
35:13	call	main	let v = V2 { x: 1, y: 2 } + V2 { x: 3, y: 4 };
$ refs '<crate::geom::V2 as Add>::add' --exact
# clash/geom.vl
21:8	def	fn add(self, o: V2) -> V2 {
# clash/main.vl
35:13	call	main	let v = V2 { x: 1, y: 2 } + V2 { x: 3, y: 4 };
$ refs V2::add
# clash/geom.vl
21:8	def	fn add(self, o: V2) -> V2 {
# clash/main.vl
35:13	call	main	let v = V2 { x: 1, y: 2 } + V2 { x: 3, y: 4 };
$ refs crate::myvec::Vec::add
# clash/main.vl
41:10	call	main	mine.add(1);
# clash/myvec.vl
15:12	def	pub fn add(inout self, k: i64) {
$ refs Area::area
# clash/geom.vl
27:8	def	-><geom::V2 as Area>::area	fn area(self) -> i64 {
# clash/main.vl
27:7	call	twice_generic	-><geom::V2 as Area>::area	x.area() + x.area()
27:7	call	twice_generic	-><shapes::Square as Area>::area	x.area() + x.area()
27:18	call	twice_generic	-><geom::V2 as Area>::area	x.area() + x.area()
27:18	call	twice_generic	-><shapes::Square as Area>::area	x.area() + x.area()
# clash/shapes.vl
2:8	def	->shapes::Area::area	fn area(self) -> i64;
5:14	call	shapes::Area::twice	-><geom::V2 as Area>::area	self.area() * 2
5:14	call	shapes::Area::twice	-><shapes::Square as Area>::area	self.area() * 2
14:8	def	-><shapes::Square as Area>::area	fn area(self) -> i64 {
$ refs Area::twice
# clash/main.vl
47:59	call	main	let total = twice_generic(sq) + twice_generic(v) + sq.twice() + mine.len() + printf(r);
# clash/shapes.vl
4:8	def	fn twice(self) -> i64 {
$ show '<Square as Area>::area'
// <crate::shapes::Square as Area>::area	clash/shapes.vl:14-16	effects: none
    fn area(self) -> i64 {
        self.side * self.side
    }
$ refs crate::shapes::Area
# clash/geom.vl
1:20	use	geom	use crate::shapes::Area;
26:6	type	geom	impl Area for V2 {
# clash/main.vl
17:14	use	crate	use shapes::{Area, Shape, Square};
26:21	type	twice_generic	fn twice_generic<T: Area>(x: T) -> i64 {
# clash/shapes.vl
1:11	def	pub trait Area {
13:6	type	shapes	impl Area for Square {
$ def push
crate::myvec::Vec::push	clash/myvec.vl:7:12	method	pub fn push(inout self, x: i64)	effects: none
std::Vec::push	../../compiler/std/std.vl:286:12	method	pub fn push(inout self, x: sink T)
std::Buf::push	../../compiler/std/std.vl:511:12	method	pub fn push(inout self, b: u8)
std::BinaryHeap::push	../../compiler/std/flat/collections.vl:202:12	method	pub fn push(inout self, x: sink T)
std::MinHeap::push	../../compiler/std/flat/collections.vl:298:12	method	pub fn push(inout self, x: sink T)
std::unicode::GraphemeState::push	../../compiler/std/unicode/mod.vl:167:12	method	pub fn push(inout self, cp: u32) -> bool	effects: panic
std::unicode::ClusterWidth::push	../../compiler/std/unicode/mod.vl:396:12	method	pub fn push(inout self, cp: u32, p: u16)	effects: none
std::objc::Pool::push	../../compiler/std/objc/mod.vl:216:12	method	pub fn push() -> Pool	effects: alloc(Gpa, extern) io global panic diverge unsafe
std::string::String::push	../../compiler/std/string.vl:1204:12	method	pub fn push(inout self, cp: u32)
std::path::PathBuf::push	../../compiler/std/path.vl:249:12	method	pub fn push(inout self, p: [u8])
std::window::cocoa::push	../../compiler/std/window/cocoa.vl:244:4	fn	fn push(e: Event)	effects: alloc(Gpa, extern) io global panic diverge unsafe
std::cli::Matches::push	../../compiler/std/cli.vl:1241:8	method	fn push(inout self, s: i64, text: str, at: i64)
$ refs Vec::push --count
2	crate::myvec::Vec::push
194	std::Vec::push
$ callers crate::myvec::Vec::push
# clash/main.vl
40:10	call	main	mine.push(v.len());
$ refs crate::myvec::Vec::push
# clash/main.vl
40:10	call	main	mine.push(v.len());
# clash/myvec.vl
7:12	def	pub fn push(inout self, x: i64) {
$ refs geom::V2
# clash/geom.vl
8:12	def	pub struct V2 {
13:6	type	geom	impl V2 {
15:16	type	geom::V2::len	pub fn len(self) -> i64 {
20:14	type	geom	impl Add for V2 {
21:12	type	<geom::V2 as Add>::add	fn add(self, o: V2) -> V2 {
21:21	type	<geom::V2 as Add>::add	fn add(self, o: V2) -> V2 {
21:28	type	<geom::V2 as Add>::add	fn add(self, o: V2) -> V2 {
22:9	init	<geom::V2 as Add>::add	V2 { x: self.x + o.x, y: self.y + o.y }
26:15	type	geom	impl Area for V2 {
27:13	type	<geom::V2 as Area>::area	fn area(self) -> i64 {
# clash/main.vl
16:19	use	crate	use geom::{Point, V2};
35:13	init	main	let v = V2 { x: 1, y: 2 } + V2 { x: 3, y: 4 };
35:33	init	main	let v = V2 { x: 1, y: 2 } + V2 { x: 3, y: 4 };
$ callers printf
# clash/main.vl
47:82	call	main	->printf	let total = twice_generic(sq) + twice_generic(v) + sq.twice() + mine.len() + printf(r);
49:12	call	main	->c::printf	c::printf(c"%d\n", total as i32);
$ refs crate::printf
# clash/main.vl
21:4	def	fn printf(x: i64) -> i64 {
47:82	call	main	let total = twice_generic(sq) + twice_generic(v) + sq.twice() + mine.len() + printf(r);
$ show crate::printf
// crate::printf	clash/main.vl:20-23	effects: none
/// The user's own printf (the C one is c::printf).
fn printf(x: i64) -> i64 {
    x + 1
}
$ callers c::printf --count
1
$ refs Point.x
# clash/a.vl
7:9	def	->a::Point.x	pub x: i64,
# clash/main.vl
33:24	init	main	->a::Point.x	let p = a::Point { x: Point(n) };
34:39	read	main	->a::Point.x	let s = sys::SockaddrIn { port: p.x };
# <std>
46697:33	init	std::window::cocoa::post_wake	->std::window::objc::Point.x	EV_APP_DEFINED, Point { x: 0.0, y: 0.0 }, 0, 0.0, 0, 0 as *u8, 0, WAKE, 0);
46882:18	read	std::window::cocoa::imp_mouse	->std::window::objc::Point.x	x: p.x * s,
48448:9	def	->std::window::objc::Point.x	pub x: f64,
$ refs .x --count
3	crate::a::Point.x
9	crate::geom::V2.x
3	std::gpu::hal::metal::bindings::MTLOrigin.x
3	std::gpu::hal::metal::bindings::MTLScissorRect.x
2	std::window::Mouse.x
3	std::window::objc::Point.x
5	std::window::objc::Rect.x
1	std::window::objc::MtlRegion.x
$ refs SockaddrIn.port
# clash/main.vl
10:33	def	pub struct SockaddrIn { pub port: i64 }
34:31	init	main	let s = sys::SockaddrIn { port: p.x };
38:20	read	main	std_vec.push(s.port);
$ show sys::SockaddrIn
// crate::sys::SockaddrIn	clash/main.vl:10-10
    pub struct SockaddrIn { pub port: i64 }
$ def Shape::Circle
crate::shapes::Shape::Circle	clash/shapes.vl:20:5	variant	Circle(i64)
$ refs Shape::Circle
# clash/main.vl
42:24	init	main	let shape = Shape::Circle(2);
44:16	pat	main	Shape::Circle(k) => k,
# clash/shapes.vl
20:5	def	Circle(i64),
$ refs Shape::Dot
# clash/main.vl
45:16	pat	main	Shape::Dot => 0,
# clash/shapes.vl
21:5	def	Dot,
$ refs crate::shapes::Shape
# clash/main.vl
17:20	use	crate	use shapes::{Area, Shape, Square};
42:17	type	main	let shape = Shape::Circle(2);
44:9	type	main	Shape::Circle(k) => k,
45:9	type	main	Shape::Dot => 0,
# clash/shapes.vl
19:10	def	pub enum Shape {
$ refs a
# clash/main.vl
3:5	def	mod a;
15:5	mod	crate	use a::helper as a_helper;
33:13	mod	main	let p = a::Point { x: Point(n) };
$ def twice_generic
crate::twice_generic	clash/main.vl:26:4	fn	fn twice_generic<T: Area>(x: T) -> i64
$ callers twice_generic
# clash/main.vl
47:17	call	main	let total = twice_generic(sq) + twice_generic(v) + sq.twice() + mine.len() + printf(r);
47:37	call	main	let total = twice_generic(sq) + twice_generic(v) + sq.twice() + mine.len() + printf(r);
$ def UNIT
crate::shapes::UNIT	clash/shapes.vl:24:11	const	pub const UNIT: i64 = 1
$ def COUNT
crate::shapes::COUNT	clash/shapes.vl:25:16	static	pub static var COUNT: i64 = 0
$ def Side
crate::shapes::Side	clash/shapes.vl:26:10	type	pub type Side = i64
$ def Area
crate::shapes::Area	clash/shapes.vl:1:11	trait	pub trait Area
$ items geom
# crate::geom	clash/geom.vl
4	fn	pub fn Point(x: i64) -> i64
8	struct	pub struct V2
13	impl	impl V2
15	method	pub fn len(self) -> i64
20	impl	impl Add for V2
21	method	fn add(self, o: V2) -> V2
26	impl	impl Area for V2
27	method	fn area(self) -> i64
$ items crate
# crate	clash/main.vl
3	mod	mod a
4	mod	mod b
5	mod	mod geom
6	mod	mod shapes
7	mod	mod myvec
9	mod	mod sys
21	fn	fn printf(x: i64) -> i64
26	fn	fn twice_generic<T: Area>(x: T) -> i64
30	fn	fn main(gpa: Gpa) -> i32
$ items sys
# crate::sys	clash/main.vl
10	struct	pub struct SockaddrIn
# std::sys	<std>
16046	const	pub const SYS_EPERM: i32 = 1
16047	const	pub const SYS_ENOENT: i32 = 2
16048	const	pub const SYS_ESRCH: i32 = 3
16049	const	pub const SYS_EINTR: i32 = 4
16050	const	pub const SYS_EIO: i32 = 5
16051	const	pub const SYS_EBADF: i32 = 9
16052	const	pub const SYS_ECHILD: i32 = 10
16053	const	pub const SYS_ENOMEM: i32 = 12
16054	const	pub const SYS_EACCES: i32 = 13
16055	const	pub const SYS_EEXIST: i32 = 17
16056	const	pub const SYS_EXDEV: i32 = 18
16057	const	pub const SYS_ENOTDIR: i32 = 20
16058	const	pub const SYS_EISDIR: i32 = 21
16059	const	pub const SYS_EINVAL: i32 = 22
16060	const	pub const SYS_ENOSPC: i32 = 28
16061	const	pub const SYS_EROFS: i32 = 30
16062	const	pub const SYS_EPIPE: i32 = 32
16067	enum	pub enum SysErrorKind
16088	fn	pub fn sys_errno() -> i32
16094	fn	pub fn sys_set_errno(e: i32)
16100	fn	pub fn sys_errno_kind(e: i32) -> SysErrorKind
16134	fn	pub fn sys_strerror_into(e: i32, out: inout [u8]) -> i64
16147	fn	pub unsafe fn sys_cstr_view(p: *u8) -> [u8]
16174	struct	pub struct SysPath
16182	fn	pub fn sys_cpath(path: [u8]) -> Result<SysPath, i32>
16268	const	pub const SYS_O_RDONLY: i32 = 0
16269	const	pub const SYS_O_WRONLY: i32 = 1
16270	const	pub const SYS_O_RDWR: i32 = 2
16271	const	pub const SYS_SEEK_SET: i32 = 0
16272	const	pub const SYS_SEEK_CUR: i32 = 1
16273	const	pub const SYS_SEEK_END: i32 = 2
16283	fn	pub fn sys_open(path: [u8], flags: i32, mode: i32) -> Result<i32, i32>
16290	fn	pub fn sys_close(fd: i32) -> Result<(), i32>
16295	fn	pub fn sys_read(fd: i32, buf: inout [u8]) -> Result<i64, i32>
16301	fn	pub fn sys_write(fd: i32, buf: [u8]) -> Result<i64, i32>
16307	fn	pub fn sys_pread(fd: i32, buf: inout [u8], off: i64) -> Result<i64, i32>
16313	fn	pub fn sys_pwrite(fd: i32, buf: [u8], off: i64) -> Result<i64, i32>
16319	fn	pub fn sys_lseek(fd: i32, off: i64, whence: i32) -> Result<i64, i32>
16323	fn	pub fn sys_ftruncate(fd: i32, len: i64) -> Result<(), i32>
16327	fn	pub fn sys_fsync(fd: i32) -> Result<(), i32>
16331	fn	pub fn sys_mkdir(path: [u8], mode: i32) -> Result<(), i32>
16336	fn	pub fn sys_rmdir(path: [u8]) -> Result<(), i32>
16341	fn	pub fn sys_unlink(path: [u8]) -> Result<(), i32>
16346	fn	pub fn sys_rename(from: [u8], to: [u8]) -> Result<(), i32>
16352	fn	pub fn sys_dup(fd: i32) -> Result<i32, i32>
16358	fn	pub fn sys_dup2(fd: i32, to: i32) -> Result<i32, i32>
16363	fn	pub fn sys_pipe() -> Result<(i32, i32), i32>
16373	fn	pub fn sys_set_nonblocking(fd: i32, on: bool) -> Result<(), i32>
16383	fn	pub fn sys_set_cloexec(fd: i32, on: bool) -> Result<(), i32>
16393	fn	pub fn sys_isatty(fd: i32) -> bool
16401	struct	pub struct FileStat
16420	const	pub const SYS_S_IFMT: u32 = 0xf000
16421	const	pub const SYS_S_IFDIR: u32 = 0x4000
16422	const	pub const SYS_S_IFREG: u32 = 0x8000
16423	const	pub const SYS_S_IFLNK: u32 = 0xa000
16425	impl	impl FileStat
16426	method	pub fn is_dir(self) -> bool
16430	method	pub fn is_file(self) -> bool
16434	method	pub fn is_symlink(self) -> bool
16439	method	pub fn permissions(self) -> u32
16446	struct	pub struct StatMacos
16473	struct	pub struct StatLinux
16547	fn	pub fn sys_fstat(fd: i32) -> Result<FileStat, i32>
16555	fn	pub fn sys_stat(path: [u8]) -> Result<FileStat, i32>
16564	fn	pub fn sys_lstat(path: [u8]) -> Result<FileStat, i32>
16594	struct	pub struct DirentMacos
16605	struct	pub struct DirentLinux
16614	struct	pub struct SysDir
16622	struct	pub struct SysDirEntry
16628	const	pub const SYS_DT_UNKNOWN: u8 = 0
16629	const	pub const SYS_DT_FIFO: u8 = 1
16630	const	pub const SYS_DT_CHR: u8 = 2
16631	const	pub const SYS_DT_DIR: u8 = 4
16632	const	pub const SYS_DT_BLK: u8 = 6
16633	const	pub const SYS_DT_REG: u8 = 8
16634	const	pub const SYS_DT_LNK: u8 = 10
16635	const	pub const SYS_DT_SOCK: u8 = 12
16637	fn	pub fn sys_opendir(path: [u8]) -> Result<SysDir, i32>
16648	fn	pub fn sys_readdir_into(dir: inout SysDir, name: inout [u8; 256]) -> Result<Option<SysDirEntry>, i32>
16688	fn	pub fn sys_closedir(dir: inout SysDir) -> Result<(), i32>
16700	fn	pub fn sys_getcwd_into(buf: inout [u8]) -> Result<i64, i32>
16716	fn	pub fn sys_chdir(path: [u8]) -> Result<(), i32>
16737	fn	pub fn sys_environ() -> **u8
16742	fn	pub fn sys_env_count() -> i64
16757	fn	pub fn sys_env_at(i: i64) -> [u8]
16767	fn	pub fn sys_getenv(name: [u8]) -> Option<[u8]>
16784	fn	pub unsafe fn sys_setenv(name: [u8], value: [u8]) -> Result<(), i32>
16791	fn	pub unsafe fn sys_unsetenv(name: [u8]) -> Result<(), i32>
16825	const	pub const SYS_SIGHUP: i32 = 1
16826	const	pub const SYS_SIGINT: i32 = 2
16827	const	pub const SYS_SIGKILL: i32 = 9
16828	const	pub const SYS_SIGTERM: i32 = 15
16833	struct	pub struct SysSpawnActions
16839	fn	pub fn sys_spawn_actions() -> Result<SysSpawnActions, i32>
16850	impl	impl SysSpawnActions
16852	method	pub fn dup2(inout self, fd: i32, to: i32) -> Result<(), i32>
16862	method	pub fn close(inout self, fd: i32) -> Result<(), i32>
16871	method	pub fn free(inout self)
16887	fn	pub unsafe fn sys_spawn(prog: *u8, argv: [*u8], envp: [*u8], actions: *SysSpawnActions) -> Result<i32, i32>
16911	fn	pub fn sys_waitpid(pid: i32, nohang: bool) -> Result<(i32, i32), i32>
16921	fn	pub fn sys_exit_code(status: i32) -> Option<i32>
16926	fn	pub fn sys_exit_signal(status: i32) -> Option<i32>
16931	fn	pub fn sys_kill(pid: i32, sig: i32) -> Result<(), i32>
16935	fn	pub fn sys_getpid() -> i32
16986	struct	pub struct SysWinsize
16995	struct	pub struct SysTermios
17002	struct	pub struct SysPollFd
17008	const	pub const SYS_POLLIN: i16 = 1
17009	const	pub const SYS_POLLPRI: i16 = 2
17010	const	pub const SYS_POLLOUT: i16 = 4
17011	const	pub const SYS_POLLERR: i16 = 8
17012	const	pub const SYS_POLLHUP: i16 = 16
17013	const	pub const SYS_POLLNVAL: i16 = 32
17019	fn	pub fn sys_openpty(size: SysWinsize) -> Result<(i32, i32), i32>
17059	fn	pub unsafe fn sys_fork_exec_pty(tty: i32, path: *u8, argv: [*u8], envp: [*u8]) -> Result<i32, i32>
17090	fn	pub fn sys_set_winsize(fd: i32, size: SysWinsize) -> Result<(), i32>
17097	fn	pub fn sys_get_winsize(fd: i32) -> Result<SysWinsize, i32>
17105	fn	pub fn sys_tcgetattr(fd: i32) -> Result<SysTermios, i32>
17113	fn	pub fn sys_tcsetattr(fd: i32, t: SysTermios) -> Result<(), i32>
17120	fn	pub fn sys_make_raw(t: inout SysTermios)
17127	fn	pub fn sys_poll(fds: [SysPollFd], timeout_ms: i32) -> Result<i64, i32>
17149	struct	pub struct SysTimespec
17154	const	pub const SYS_CLOCK_REALTIME: i32 = 0
17158	fn	pub fn sys_clock_gettime(clock: i32) -> (i64, i64)
17168	fn	pub fn sys_nanosleep(secs: i64, nanos: i64, left: inout SysTimespec) -> Result<(), i32>
17175	fn	pub fn sys_getentropy(buf: inout [u8]) -> Result<(), i32>
16006	use	pub use SYS_CLOCK_MONOTONIC = std::SYS_CLOCK_MONOTONIC (const)
16006	use	pub use SYS_EAGAIN = std::SYS_EAGAIN (const)
16006	use	pub use SYS_ELOOP = std::SYS_ELOOP (const)
16006	use	pub use SYS_ENAMETOOLONG = std::SYS_ENAMETOOLONG (const)
16006	use	pub use SYS_ENOSYS = std::SYS_ENOSYS (const)
16006	use	pub use SYS_ENOTEMPTY = std::SYS_ENOTEMPTY (const)
16006	use	pub use SYS_ENOTSUP = std::SYS_ENOTSUP (const)
16006	use	pub use SYS_ETIMEDOUT = std::SYS_ETIMEDOUT (const)
16006	use	pub use SYS_O_APPEND = std::SYS_O_APPEND (const)
16006	use	pub use SYS_O_CLOEXEC = std::SYS_O_CLOEXEC (const)
16006	use	pub use SYS_O_CREAT = std::SYS_O_CREAT (const)
16006	use	pub use SYS_O_DIRECTORY = std::SYS_O_DIRECTORY (const)
16006	use	pub use SYS_O_EXCL = std::SYS_O_EXCL (const)
16006	use	pub use SYS_O_NOCTTY = std::SYS_O_NOCTTY (const)
16006	use	pub use SYS_O_NONBLOCK = std::SYS_O_NONBLOCK (const)
16006	use	pub use SYS_O_TRUNC = std::SYS_O_TRUNC (const)
16006	use	pub use SYS_PATH_MAX = std::SYS_PATH_MAX (const)
16006	use	pub use SYS_SIGCHLD = std::SYS_SIGCHLD (const)
16006	use	pub use SYS_TIOCGWINSZ = std::SYS_TIOCGWINSZ (const)
16006	use	pub use SYS_TIOCSCTTY = std::SYS_TIOCSCTTY (const)
16006	use	pub use SYS_TIOCSWINSZ = std::SYS_TIOCSWINSZ (const)
16006	use	pub use TARGET_OS = std::TARGET_OS (const)
$ def helpr
error query.no-match: no definition 'helpr'
try: volec query def crate::a::helper
try: volec query def crate::b::helper
try: volec query def std::cli::Arg.help
[exit 1]
$ refs MyVec
# clash/main.vl
18:12	use	crate	use myvec::Vec as MyVec;
39:16	init	main	var mine = MyVec { n: 0 };
# clash/myvec.vl
2:12	def	pub struct Vec {
6:6	type	myvec	impl Vec {
7:23	type	myvec::Vec::push	pub fn push(inout self, x: i64) {
11:16	type	myvec::Vec::len	pub fn len(self) -> i64 {
15:22	type	myvec::Vec::add	pub fn add(inout self, k: i64) {
note query.alias: 'MyVec' is an import alias in crate, for crate::myvec::Vec
$ refs a_helper
# clash/a.vl
2:8	def	pub fn helper() -> i64 {
# clash/main.vl
15:8	use	crate	use a::helper as a_helper;
32:13	call	main	let n = a_helper() + b::helper() + helper;
note query.alias: 'a_helper' is an import alias in crate, for crate::a::helper
$ items nosuch
error query.no-match: no module 'nosuch'
try: volec query items
[exit 1]
