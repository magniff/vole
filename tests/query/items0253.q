## (0.25.3) `query show TYPE`: its source, then its methods, a line each
## (a trait impl's marked, a contract cut to its keyword)
$ show Shape
// crate::Shape	items0253/main.vl:3-6
pub struct Shape {
    pub w: f64,
    pub h: f64,
}
// 3 methods (with their lines and whole contracts: query items crate::Shape)
pub fn area(self) -> f64
pub fn scaled(self, k: f64) -> Shape requires ...
fn fmt(self, f: inout Fmt)  // impl Display for Shape
## an enum without methods: its source alone
$ show Unit
// crate::Unit	items0253/main.vl:24-27
pub enum Unit {
    Metre,
    Foot,
}
## `query items` filters: --find WORD (at a word's start of the name; any
## case when WORD is lowercase), --kind KIND,..., --names (kind and path)
$ items --find area
# crate	items0253/main.vl
8	impl	impl Shape
9	method	pub fn area(self) -> f64
29	const	const UNIT_AREA: f64 = 1.0
31	fn	fn total_area(a: Shape, b: Shape) -> f64
$ items crate --kind fn,const --names
# crate	items0253/main.vl
const	crate::UNIT_AREA
fn	crate::total_area
fn	crate::main
$ items Shape --kind method --names
# crate::Shape	items0253/main.vl:3:12
method	crate::Shape::area
method	crate::Shape::scaled
method	<crate::Shape as Display>::fmt
## std's numeric helpers: methods of the primitive types, and the
## constants the language gives them
$ items std --find is_finite --names
# std::math	<std>
method	<f64 as Float>::is_finite
method	<f32 as Float>::is_finite
fn	std::math::is_finite
$ items std --find FRAC_PI_2 --kind const --names
# std::math	<std>
const	std::math::FRAC_PI_2
# the primitive types' constants	<built in>
const	f64::consts::FRAC_PI_2
const	f32::consts::FRAC_PI_2
$ items --kind function
error query.usage: --kind of items takes fn, method, struct, enum, trait, trait-method, const, static, type, mod; not 'function'
try: volec query items --kind fn,method
[exit 2]
$ items --find zzz
note query.empty: no item whose name holds 'zzz' here
try: volec query grep zzz
