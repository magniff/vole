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
std::flt::Text::push	<std>:15714:8	method	fn push(&mut self, b: u8)	effects: panic diverge
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
