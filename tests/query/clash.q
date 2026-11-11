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
try: volec query def std::cli::Arg.help
[exit 1]
$ def --exact crate::a::helper
crate::a::helper	clash/a.vl:2:8	fn	pub fn helper() -> i64	effects: none
$ def Point
crate::a::Point	clash/a.vl:6:35	struct	pub struct Point
crate::geom::Point	clash/geom.vl:4:8	fn	pub fn Point(x: i64) -> i64	effects: none
$ refs Point
# clash/a.vl
6:35	def	->a::Point	#[derive(Clone, Copy)] pub struct Point {
# clash/geom.vl
4:8	def	->geom::Point	pub fn Point(x: i64) -> i64 {
# clash/main.vl
16:12	use	crate	->geom::Point	use geom::{Point, V2};
33:16	init	main	->a::Point	let p = a::Point { x: Point(n) };
33:27	call	main	->geom::Point	let p = a::Point { x: Point(n) };
$ show a::Point
// crate::a::Point	clash/a.vl:6-8
#[derive(Clone, Copy)] pub struct Point {
    pub x: i64,
}
$ def len
crate::geom::V2::len	clash/geom.vl:15:12	method	pub fn len(self) -> i64	effects: none
crate::myvec::Vec::len	clash/myvec.vl:11:12	method	pub fn len(self) -> i64	effects: none
std::alloc::TypedArena::len	<std>:3793:12	method	pub fn len(&self) -> usize
std::vec::Vec::len	<std>:4440:12	method	pub fn len(&self) -> usize
[T]::len	<std>:5436:12	method	pub fn len(&self) -> usize
str::len	<std>:6975:12	method	pub fn len(&self) -> usize	effects: none
std::string::String::len	<std>:9535:12	method	pub fn len(&self) -> usize
std::collections::binary_heap::BinaryHeap::len	<std>:11791:12	method	pub fn len(&self) -> usize
std::collections::binary_heap::MinHeap::len	<std>:11895:12	method	pub fn len(&self) -> usize
std::collections::btree_map::BTreeMap::len	<std>:12246:12	method	pub fn len(&self) -> usize
std::collections::btree_map::BTreeSet::len	<std>:13295:12	method	pub fn len(&self) -> usize
std::collections::hash_map::HashMap::len	<std>:11147:12	method	pub fn len(&self) -> usize
std::collections::hash_set::HashSet::len	<std>:12083:12	method	pub fn len(&self) -> usize
std::iter::ExactSizeIterator::len	<std>:13093:8	trait-method	fn len(&self) -> usize
std::flt::Text::len	<std>:15764:8	method	fn len(&self) -> usize	effects: none
std::fs::Metadata::len	<std>:20701:12	method	pub fn len(&self) -> u64	effects: none
$ refs V2::len
# clash/geom.vl
15:12	def	pub fn len(self) -> i64 {
# clash/main.vl
40:17	call	main	mine.push(v.len());
$ refs myvec::Vec::len
# clash/main.vl
47:76	call	main	let total = twice_generic(&sq) + twice_generic(&v) + sq.twice() + mine.len() + printf(r);
# clash/myvec.vl
11:12	def	pub fn len(self) -> i64 {
$ def V2::add
<crate::geom::V2 as Add>::add	clash/geom.vl:21:8	method	fn add(self, o: V2) -> V2	effects: none
$ def Vec::add
crate::myvec::Vec::add	clash/myvec.vl:15:12	method	pub fn add(&mut self, k: i64)	effects: none
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
15:12	def	pub fn add(&mut self, k: i64) {
$ refs Area::area
# clash/geom.vl
27:8	def	-><geom::V2 as Area>::area	fn area(&self) -> i64 {
# clash/main.vl
27:7	call	twice_generic	-><geom::V2 as Area>::area	x.area() + x.area()
27:7	call	twice_generic	->shapes::Area::area	x.area() + x.area()
27:7	call	twice_generic	-><shapes::Square as Area>::area	x.area() + x.area()
27:18	call	twice_generic	-><geom::V2 as Area>::area	x.area() + x.area()
27:18	call	twice_generic	->shapes::Area::area	x.area() + x.area()
27:18	call	twice_generic	-><shapes::Square as Area>::area	x.area() + x.area()
# clash/shapes.vl
2:8	def	->shapes::Area::area	fn area(&self) -> i64;
5:14	call	shapes::Area::twice	-><geom::V2 as Area>::area	self.area() * 2
5:14	call	shapes::Area::twice	-><shapes::Square as Area>::area	self.area() * 2
14:8	def	-><shapes::Square as Area>::area	fn area(&self) -> i64 {
$ refs Area::twice
# clash/main.vl
47:61	call	main	let total = twice_generic(&sq) + twice_generic(&v) + sq.twice() + mine.len() + printf(r);
# clash/shapes.vl
4:8	def	fn twice(self) -> i64 {
$ show '<Square as Area>::area'
// <crate::shapes::Square as Area>::area	clash/shapes.vl:14-16	effects: none
    fn area(&self) -> i64 {
        self.side * self.side
    }
$ refs crate::shapes::Area
# clash/geom.vl
1:39	use	geom	use std::ops::Add; use crate::shapes::Area;
26:6	type	geom	impl Area for V2 {
# clash/main.vl
17:14	use	crate	use shapes::{Area, Shape, Square};
26:21	type	twice_generic	fn twice_generic<T: Area>(x: &T) -> i64 {
# clash/shapes.vl
1:11	def	pub trait Area {
13:6	type	shapes	impl Area for Square {
$ def push
crate::myvec::Vec::push	clash/myvec.vl:7:12	method	pub fn push(&mut self, x: i64)	effects: none
std::vec::Vec::push	<std>:4548:12	method	pub fn push(&mut self, x: T) debug ensures self.len() == old(self.len()) + 1 debug ensures self.len() <= self.capacity()
std::string::String::push	<std>:9623:12	method	pub fn push(&mut self, c: char) ensures self.len() > old(self.len())
std::collections::binary_heap::BinaryHeap::push	<std>:11802:12	method	pub fn push(&mut self, x: T)
std::collections::binary_heap::MinHeap::push	<std>:11905:12	method	pub fn push(&mut self, x: T)
std::flt::Text::push	<std>:15714:8	method	fn push(&mut self, b: u8)	effects: panic diverge
std::path::PathBuf::push	<std>:23132:12	method	pub fn push<P: AsRef<str>>(&mut self, p: P)
std::cli::Matches::push	<std>:22958:8	method	fn push(&mut self, s: i64, text: &'a str, at: i64)
$ refs Vec::push --count
2	crate::myvec::Vec::push
99	std::vec::Vec::push
$ callers crate::myvec::Vec::push
# clash/main.vl
40:10	call	main	mine.push(v.len());
$ refs crate::myvec::Vec::push
# clash/main.vl
40:10	call	main	mine.push(v.len());
# clash/myvec.vl
7:12	def	pub fn push(&mut self, x: i64) {
$ refs geom::V2
# clash/geom.vl
8:35	def	#[derive(Clone, Copy)] pub struct V2 {
13:6	type	geom	impl V2 {
15:16	type	geom::V2::len	pub fn len(self) -> i64 {
20:14	type	geom	impl Add for V2 { type Output = V2;
20:33	type	geom	impl Add for V2 { type Output = V2;
21:12	type	<geom::V2 as Add>::add	fn add(self, o: V2) -> V2 {
21:21	type	<geom::V2 as Add>::add	fn add(self, o: V2) -> V2 {
21:28	type	<geom::V2 as Add>::add	fn add(self, o: V2) -> V2 {
22:9	init	<geom::V2 as Add>::add	V2 { x: self.x + o.x, y: self.y + o.y }
26:15	type	geom	impl Area for V2 {
27:14	type	<geom::V2 as Area>::area	fn area(&self) -> i64 {
# clash/main.vl
16:19	use	crate	use geom::{Point, V2};
35:13	init	main	let v = V2 { x: 1, y: 2 } + V2 { x: 3, y: 4 };
35:33	init	main	let v = V2 { x: 1, y: 2 } + V2 { x: 3, y: 4 };
$ callers printf
# clash/main.vl
47:84	call	main	->printf	let total = twice_generic(&sq) + twice_generic(&v) + sq.twice() + mine.len() + printf(r);
49:12	call	main	->c::printf	c::printf(c"%d\n", total as i32);
$ refs crate::printf
# clash/main.vl
21:4	def	fn printf(x: i64) -> i64 {
47:84	call	main	let total = twice_generic(&sq) + twice_generic(&v) + sq.twice() + mine.len() + printf(r);
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
7:9	def	pub x: i64,
# clash/main.vl
33:24	init	main	let p = a::Point { x: Point(n) };
34:39	read	main	let s = sys::SockaddrIn { port: p.x };
$ refs .x --count
3	crate::a::Point.x
9	crate::geom::V2.x
$ refs SockaddrIn.port
# clash/main.vl
10:56	def	#[derive(Clone, Copy)] pub struct SockaddrIn { pub port: i64 }
34:31	init	main	let s = sys::SockaddrIn { port: p.x };
38:20	read	main	std_vec.push(s.port);
$ show sys::SockaddrIn
// crate::sys::SockaddrIn	clash/main.vl:10-10
    #[derive(Clone, Copy)] pub struct SockaddrIn { pub port: i64 }
$ def Shape::Circle
crate::shapes::Shape::Circle	clash/shapes.vl:20:5	variant	Circle(i64)
$ refs Shape::Circle
# clash/main.vl
42:24	init	main	let shape = Shape::Circle(2i64);
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
42:17	type	main	let shape = Shape::Circle(2i64);
44:9	type	main	Shape::Circle(k) => k,
45:9	type	main	Shape::Dot => 0,
# clash/shapes.vl
19:33	def	#[derive(Clone, Copy)] pub enum Shape {
$ refs a
# clash/main.vl
3:5	def	mod a;
15:5	mod	crate	use a::helper as a_helper;
33:13	mod	main	let p = a::Point { x: Point(n) };
$ def twice_generic
crate::twice_generic	clash/main.vl:26:4	fn	fn twice_generic<T: Area>(x: &T) -> i64
$ callers twice_generic
# clash/main.vl
47:17	call	main	let total = twice_generic(&sq) + twice_generic(&v) + sq.twice() + mine.len() + printf(r);
47:38	call	main	let total = twice_generic(&sq) + twice_generic(&v) + sq.twice() + mine.len() + printf(r);
$ def UNIT
crate::shapes::UNIT	clash/shapes.vl:24:11	const	pub const UNIT: i64 = 1
$ def COUNT
crate::shapes::COUNT	clash/shapes.vl:25:12	static	static mut COUNT: i64 = 0
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
27	method	fn area(&self) -> i64
$ items crate
# crate	clash/main.vl
3	mod	mod a
4	mod	mod b
5	mod	mod geom
6	mod	mod shapes
7	mod	mod myvec
9	mod	mod sys
21	fn	fn printf(x: i64) -> i64
26	fn	fn twice_generic<T: Area>(x: &T) -> i64
30	fn	fn main(gpa: Gpa) -> i32
$ items sys
# crate::sys	clash/main.vl
10	struct	pub struct SockaddrIn
# std::sys	<std>
23610	const	pub const SYS_CLOCK_MONOTONIC: i32 = crate::__sys::CLOCK_MONOTONIC
23611	const	pub const SYS_EAGAIN: i32 = crate::__sys::EAGAIN
23612	const	pub const SYS_ELOOP: i32 = crate::__sys::ELOOP
23613	const	pub const SYS_ENAMETOOLONG: i32 = crate::__sys::ENAMETOOLONG
23614	const	pub const SYS_ENOSYS: i32 = crate::__sys::ENOSYS
23615	const	pub const SYS_ENOTEMPTY: i32 = crate::__sys::ENOTEMPTY
23616	const	pub const SYS_ENOTSUP: i32 = crate::__sys::ENOTSUP
23617	const	pub const SYS_ETIMEDOUT: i32 = crate::__sys::ETIMEDOUT
23618	const	pub const SYS_O_APPEND: i32 = crate::__sys::O_APPEND
23619	const	pub const SYS_O_CLOEXEC: i32 = crate::__sys::O_CLOEXEC
23620	const	pub const SYS_O_CREAT: i32 = crate::__sys::O_CREAT
23621	const	pub const SYS_O_DIRECTORY: i32 = crate::__sys::O_DIRECTORY
23622	const	pub const SYS_O_EXCL: i32 = crate::__sys::O_EXCL
23623	const	pub const SYS_O_NOCTTY: i32 = crate::__sys::O_NOCTTY
23624	const	pub const SYS_O_NONBLOCK: i32 = crate::__sys::O_NONBLOCK
23625	const	pub const SYS_O_TRUNC: i32 = crate::__sys::O_TRUNC
23626	const	pub const SYS_SIGCHLD: i32 = crate::__sys::SIGCHLD
23627	const	pub const SYS_TIOCGWINSZ: u64 = crate::__sys::TIOCGWINSZ
23628	const	pub const SYS_TIOCSCTTY: u64 = crate::__sys::TIOCSCTTY
23629	const	pub const SYS_TIOCSWINSZ: u64 = crate::__sys::TIOCSWINSZ
23630	const	pub const TARGET_OS: i64 = crate::__sys::TARGET_OS
23631	const	pub const SYS_PATH_MAX: i64 = crate::__sys::PATH_MAX as i64
23662	const	pub const SYS_EPERM: i32 = 1
23663	const	pub const SYS_ENOENT: i32 = 2
23664	const	pub const SYS_ESRCH: i32 = 3
23665	const	pub const SYS_EINTR: i32 = 4
23666	const	pub const SYS_EIO: i32 = 5
23667	const	pub const SYS_EBADF: i32 = 9
23668	const	pub const SYS_ECHILD: i32 = 10
23669	const	pub const SYS_ENOMEM: i32 = 12
23670	const	pub const SYS_EACCES: i32 = 13
23671	const	pub const SYS_EEXIST: i32 = 17
23672	const	pub const SYS_EXDEV: i32 = 18
23673	const	pub const SYS_ENOTDIR: i32 = 20
23674	const	pub const SYS_EISDIR: i32 = 21
23675	const	pub const SYS_EINVAL: i32 = 22
23676	const	pub const SYS_ENOSPC: i32 = 28
23677	const	pub const SYS_EROFS: i32 = 30
23678	const	pub const SYS_EPIPE: i32 = 32
23683	enum	pub enum SysErrorKind
23705	fn	pub fn sys_errno() -> i32
23715	fn	pub fn sys_set_errno(e: i32)
23725	fn	pub fn sys_errno_kind(e: i32) -> SysErrorKind
23760	fn	pub fn sys_strerror_into(e: i32, out: &mut [u8]) -> i64
23787	fn	pub unsafe fn sys_cstr_view<'a>(p: *const u8) -> &'a [u8]
23816	struct	pub struct SysPath
23825	fn	pub fn sys_cpath<P: AsRef<[u8]>>(path: P) -> Result<SysPath, i32>
23917	const	pub const SYS_O_RDONLY: i32 = 0
23918	const	pub const SYS_O_WRONLY: i32 = 1
23919	const	pub const SYS_O_RDWR: i32 = 2
23920	const	pub const SYS_SEEK_SET: i32 = 0
23921	const	pub const SYS_SEEK_CUR: i32 = 1
23922	const	pub const SYS_SEEK_END: i32 = 2
23933	fn	pub fn sys_open<P: AsRef<[u8]>>(path: P, flags: i32, mode: i32) -> Result<i32, i32>
23944	fn	pub fn sys_close(fd: i32) -> Result<(), i32>
23953	fn	pub fn sys_read(fd: i32, buf: &mut [u8]) -> Result<i64, i32>
23962	fn	pub fn sys_write<B: AsRef<[u8]>>(fd: i32, buf: B) -> Result<i64, i32>
23972	fn	pub fn sys_pread(fd: i32, buf: &mut [u8], off: i64) -> Result<i64, i32>
23980	fn	pub fn sys_pwrite<B: AsRef<[u8]>>(fd: i32, buf: B, off: i64) -> Result<i64, i32>
23989	fn	pub fn sys_lseek(fd: i32, off: i64, whence: i32) -> Result<i64, i32>
23996	fn	pub fn sys_ftruncate(fd: i32, len: i64) -> Result<(), i32>
24003	fn	pub fn sys_fsync(fd: i32) -> Result<(), i32>
24010	fn	pub fn sys_mkdir<P: AsRef<[u8]>>(path: P, mode: i32) -> Result<(), i32>
24019	fn	pub fn sys_rmdir<P: AsRef<[u8]>>(path: P) -> Result<(), i32>
24028	fn	pub fn sys_unlink<P: AsRef<[u8]>>(path: P) -> Result<(), i32>
24037	fn	pub fn sys_rename<P: AsRef<[u8]>, Q: AsRef<[u8]>>(from: P, to: Q) -> Result<(), i32>
24048	fn	pub fn sys_dup(fd: i32) -> Result<i32, i32>
24057	fn	pub fn sys_dup2(fd: i32, to: i32) -> Result<i32, i32>
24065	fn	pub fn sys_pipe() -> Result<(i32, i32), i32>
24077	fn	pub fn sys_set_nonblocking(fd: i32, on: bool) -> Result<(), i32>
24092	fn	pub fn sys_set_cloexec(fd: i32, on: bool) -> Result<(), i32>
24107	fn	pub fn sys_isatty(fd: i32) -> bool
24117	struct	pub struct FileStat
24136	const	pub const SYS_S_IFMT: u32 = 0xf000
24137	const	pub const SYS_S_IFDIR: u32 = 0x4000
24138	const	pub const SYS_S_IFREG: u32 = 0x8000
24139	const	pub const SYS_S_IFLNK: u32 = 0xa000
24141	impl	impl FileStat
24143	method	pub fn is_dir(self) -> bool
24148	method	pub fn is_file(self) -> bool
24153	method	pub fn is_symlink(self) -> bool
24159	method	pub fn permissions(self) -> u32
24166	struct	pub struct StatMacos
24193	struct	pub struct StatLinux
24274	fn	pub fn sys_fstat(fd: i32) -> Result<FileStat, i32>
24285	fn	pub fn sys_stat<P: AsRef<[u8]>>(path: P) -> Result<FileStat, i32>
24298	fn	pub fn sys_lstat<P: AsRef<[u8]>>(path: P) -> Result<FileStat, i32>
24334	struct	pub struct DirentMacos
24345	struct	pub struct DirentLinux
24356	struct	pub struct SysDir
24360	impl	impl Drop for SysDir
24361	method	fn drop(&mut self)
24372	struct	pub struct SysDirEntry
24378	const	pub const SYS_DT_UNKNOWN: u8 = 0
24379	const	pub const SYS_DT_FIFO: u8 = 1
24380	const	pub const SYS_DT_CHR: u8 = 2
24381	const	pub const SYS_DT_DIR: u8 = 4
24382	const	pub const SYS_DT_BLK: u8 = 6
24383	const	pub const SYS_DT_REG: u8 = 8
24384	const	pub const SYS_DT_LNK: u8 = 10
24385	const	pub const SYS_DT_SOCK: u8 = 12
24388	fn	pub fn sys_opendir<P: AsRef<[u8]>>(path: P) -> Result<SysDir, i32>
24403	fn	pub fn sys_readdir_into(dir: &mut SysDir, name: &mut [u8; 256]) -> Result<Option<SysDirEntry>, i32>
24451	fn	pub fn sys_closedir(dir: &mut SysDir) -> Result<(), i32>
24466	fn	pub fn sys_getcwd_into(buf: &mut [u8]) -> Result<i64, i32>
24485	fn	pub fn sys_chdir<P: AsRef<[u8]>>(path: P) -> Result<(), i32>
24512	fn	pub fn sys_environ() -> *const *const u8
24518	fn	pub fn sys_env_count() -> i64
24537	fn	pub fn sys_env_at(i: i64) -> &'static [u8]
24551	fn	pub fn sys_getenv<P: AsRef<[u8]>>(name: P) -> Option<&'static [u8]>
24580	fn	pub unsafe fn sys_setenv<P: AsRef<[u8]>, Q: AsRef<[u8]>>(name: P, value: Q) -> Result<(), i32>
24592	fn	pub unsafe fn sys_unsetenv<P: AsRef<[u8]>>(name: P) -> Result<(), i32>
24656	const	pub const SYS_SIGHUP: i32 = 1
24657	const	pub const SYS_SIGINT: i32 = 2
24658	const	pub const SYS_SIGQUIT: i32 = 3
24659	const	pub const SYS_SIGKILL: i32 = 9
24660	const	pub const SYS_SIGTERM: i32 = 15
24666	struct	pub struct SysSpawnActions
24671	impl	impl Drop for SysSpawnActions
24672	method	fn drop(&mut self)
24679	fn	pub fn sys_spawn_actions() -> Result<SysSpawnActions, i32>
24693	impl	impl SysSpawnActions
24696	method	pub fn dup2(&mut self, fd: i32, to: i32) -> Result<(), i32>
24709	method	pub fn close(&mut self, fd: i32) -> Result<(), i32>
24720	method	pub fn free(&mut self)
24744	fn	pub unsafe fn sys_spawn(prog: *const u8, argv: &[*const u8], envp: &[*const u8], actions: *const SysSpawnActions) -> Result<i32, i32>
24754	fn	pub unsafe fn sys_spawn_attr(prog: *const u8, argv: &[*const u8], envp: &[*const u8], actions: *const SysSpawnActions, attr: *const SysSpawnAttr) -> Result<i32, i32>
24784	struct	pub struct SysSpawnAttr
24789	impl	impl Drop for SysSpawnAttr
24790	method	fn drop(&mut self)
24808	fn	pub fn sys_spawn_sigdefault(sigs: &[i32]) -> Result<SysSpawnAttr, i32>
24842	struct	pub struct SysSignalWas
24849	fn	pub fn sys_signal_ignore(sig: i32) -> SysSignalWas
24859	fn	pub fn sys_signal_restore(was: SysSignalWas)
24875	fn	pub fn sys_waitpid(pid: i32, nohang: bool) -> Result<(i32, i32), i32>
24888	fn	pub fn sys_exit_code(status: i32) -> Option<i32>
24894	fn	pub fn sys_exit_signal(status: i32) -> Option<i32>
24900	fn	pub fn sys_kill(pid: i32, sig: i32) -> Result<(), i32>
24907	fn	pub fn sys_getpid() -> i32
24965	struct	pub struct SysWinsize
24974	struct	pub struct SysTermios
24981	struct	pub struct SysPollFd
24987	const	pub const SYS_POLLIN: i16 = 1
24988	const	pub const SYS_POLLPRI: i16 = 2
24989	const	pub const SYS_POLLOUT: i16 = 4
24990	const	pub const SYS_POLLERR: i16 = 8
24991	const	pub const SYS_POLLHUP: i16 = 16
24992	const	pub const SYS_POLLNVAL: i16 = 32
24999	fn	pub fn sys_openpty(size: SysWinsize) -> Result<(i32, i32), i32>
25065	fn	pub unsafe fn sys_fork_exec_pty(tty: i32, path: *const u8, argv: &[*const u8], envp: &[*const u8]) -> Result<i32, i32>
25098	fn	pub fn sys_set_winsize(fd: i32, size: SysWinsize) -> Result<(), i32>
25108	fn	pub fn sys_get_winsize(fd: i32) -> Result<SysWinsize, i32>
25119	fn	pub fn sys_tcgetattr(fd: i32) -> Result<SysTermios, i32>
25130	fn	pub fn sys_tcsetattr(fd: i32, t: SysTermios) -> Result<(), i32>
25140	fn	pub fn sys_make_raw(t: &mut SysTermios)
25151	fn	pub fn sys_poll(fds: &mut [SysPollFd], timeout_ms: i32) -> Result<i64, i32>
25180	struct	pub struct SysTimespec
25185	const	pub const SYS_CLOCK_REALTIME: i32 = 0
25190	fn	pub fn sys_clock_gettime(clock: i32) -> (i64, i64)
25203	fn	pub fn sys_nanosleep(secs: i64, nanos: i64, left: &mut SysTimespec) -> Result<(), i32>
25213	fn	pub fn sys_getentropy(buf: &mut [u8]) -> Result<(), i32>
$ def helpr
error query.no-match: no definition 'helpr'
try: volec query def crate::a::helper
try: volec query def crate::b::helper
try: volec query def std::cli::Arg.help
[exit 1]
$ refs MyVec
# clash/main.vl
18:12	use	crate	use myvec::Vec as MyVec;
39:20	init	main	let mut mine = MyVec { n: 0 };
# clash/myvec.vl
2:35	def	#[derive(Clone, Copy)] pub struct Vec {
6:6	type	myvec	impl Vec {
7:22	type	myvec::Vec::push	pub fn push(&mut self, x: i64) {
11:16	type	myvec::Vec::len	pub fn len(self) -> i64 {
15:21	type	myvec::Vec::add	pub fn add(&mut self, k: i64) {
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
