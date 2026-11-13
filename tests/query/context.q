## query context (0.15): an item's source with its section's title, the
## signatures of what it calls and of the types it uses, its callers; a
## module's items and its most used bodies; --budget cuts it, with a note
## and the commands that print the rest. --budget on any query.
$ context report
// crate::report	context/main.vl:9-15	section: Reports	effects: panic
// The total, after restocking the empty items.
fn report(items: &mut Vec<Item<'_>, Gpa>) -> i64 {
    for i in 0..items.len() {
        restock(items, i as i64, 5);
    }
    total(items)
}
// calls (3)
crate::stock::restock	context/stock.vl:10:8	fn	pub fn restock(items: &mut Vec<Item<'_>, Gpa>, i: i64, n: i64)
crate::stock::total	context/stock.vl:19:8	fn	pub fn total(items: &Vec<Item<'_>, Gpa>) -> i64
std::vec::Vec::len	<std>:4440:12	method	pub fn len(&self) -> usize
// types (3)
crate::stock::Item	context/stock.vl:4:35	struct	pub struct Item<'a> { pub name: &'a str, pub count: i64 }
std::alloc::Gpa	<std>:3219:12	struct	pub struct Gpa { sealed: (), }
std::vec::Vec	<std>:4323:12	struct	pub struct Vec<T, A: Allocator> { ptr: NonNull<T>, cap: usize, len: usize, alloc: A, }
// callers (2)
main	context/main.vl:21:13	let n = report(&mut items);
main	context/main.vl:24:13	let m = report(&mut items);
$ context restock total
// crate::stock::restock	context/stock.vl:9-16	effects: panic
// Sets item i's count to n when it is empty.
pub fn restock(items: &mut Vec<Item<'_>, Gpa>, i: i64, n: i64) {
    let mut it = items[i as usize];
    if it.count == 0 && n <= MAX {
        it.count = n;
        items[i as usize] = it;
    }
}
// calls (2)
std::vec::Vec::as_mut_slice	<std>:4697:12	method	pub fn as_mut_slice(&mut self) -> &mut [T]
std::vec::Vec::as_slice	<std>:4688:12	method	pub fn as_slice(&self) -> &[T]
// types (3)
crate::stock::Item	context/stock.vl:4:35	struct	pub struct Item<'a> { pub name: &'a str, pub count: i64 }
std::alloc::Gpa	<std>:3219:12	struct	pub struct Gpa { sealed: (), }
std::vec::Vec	<std>:4323:12	struct	pub struct Vec<T, A: Allocator> { ptr: NonNull<T>, cap: usize, len: usize, alloc: A, }
// uses (1)
crate::stock::MAX	context/stock.vl:7:11	const	pub const MAX: i64 = 100
// callers (1)
report	context/main.vl:12:9	restock(items, i as i64, 5);
// crate::stock::total	context/stock.vl:18-25	effects: panic
// The sum of the counts.
pub fn total(items: &Vec<Item<'_>, Gpa>) -> i64 {
    let mut t: i64 = 0;
    for i in 0..items.len() {
        t += items[i].count;
    }
    t
}
// calls (2)
std::vec::Vec::len	<std>:4440:12	method	pub fn len(&self) -> usize
std::vec::Vec::as_slice	<std>:4688:12	method	pub fn as_slice(&self) -> &[T]
// types (3)
crate::stock::Item	context/stock.vl:4:35	struct	pub struct Item<'a> { pub name: &'a str, pub count: i64 }
std::alloc::Gpa	<std>:3219:12	struct	pub struct Gpa { sealed: (), }
std::vec::Vec	<std>:4323:12	struct	pub struct Vec<T, A: Allocator> { ptr: NonNull<T>, cap: usize, len: usize, alloc: A, }
// callers (1)
report	context/main.vl:14:5	total(items)
$ context Item
// crate::stock::Item	context/stock.vl:3-4
// One kind of item.
#[derive(Clone, Copy)] pub struct Item<'a> { pub name: &'a str, pub count: i64 }
// used by (6)
report	context/main.vl:10:27	fn report(items: &mut Vec<Item<'_>, Gpa>) -> i64 {
main	context/main.vl:18:24	let mut items: Vec<Item<'_>, Gpa> = Vec::new_in(gpa);
main	context/main.vl:19:16	items.push(Item { name: "bolt", count: 0 });
main	context/main.vl:20:16	items.push(Item { name: "nut", count: 3 });
stock::restock	context/stock.vl:10:32	pub fn restock(items: &mut Vec<Item<'_>, Gpa>, i: i64, n: i64) {
stock::total	context/stock.vl:19:26	pub fn total(items: &Vec<Item<'_>, Gpa>) -> i64 {
$ context stock
# crate::stock	context/stock.vl
4	struct	pub struct Item<'a>
7	const	pub const MAX: i64 = 100
10	fn	pub fn restock(items: &mut Vec<Item<'_>, Gpa>, i: i64, n: i64)
19	fn	pub fn total(items: &Vec<Item<'_>, Gpa>) -> i64
// crate::stock::restock	context/stock.vl:9-16	used 0 times in the module, 1 outside
// Sets item i's count to n when it is empty.
pub fn restock(items: &mut Vec<Item<'_>, Gpa>, i: i64, n: i64) {
    let mut it = items[i as usize];
    if it.count == 0 && n <= MAX {
        it.count = n;
        items[i as usize] = it;
    }
}
// crate::stock::total	context/stock.vl:18-25	used 0 times in the module, 1 outside
// The sum of the counts.
pub fn total(items: &Vec<Item<'_>, Gpa>) -> i64 {
    let mut t: i64 = 0;
    for i in 0..items.len() {
        t += items[i].count;
    }
    t
}
$ context report --budget 120
// crate::report	context/main.vl:9-15	section: Reports	effects: panic
// The total, after restocking the empty items.
fn report(items: &mut Vec<Item<'_>, Gpa>) -> i64 {
    for i in 0..items.len() {
        restock(items, i as i64, 5);
    }
    total(items)
}
// calls (3)
crate::stock::restock	context/stock.vl:10:8	fn	pub fn restock(items: &mut Vec<Item<'_>, Gpa>, i: i64, n: i64)
crate::stock::total	context/stock.vl:19:8	fn	pub fn total(items: &Vec<Item<'_>, Gpa>) -> i64
note query.budget: over the budget of 120 tokens, left out: calls 1, types or uses 3, callers 2
try: volec query callers report
try: volec query context report --budget 360
$ context nothing_here
error query.no-match: no definition 'nothing_here'
try: volec query items
[exit 1]
$ show report --budget 40
// crate::report	context/main.vl:9-15	effects: panic
// The total, after restocking the empty items.
fn report(items: &mut Vec<Item<'_>, Gpa>) -> i64 {
note query.budget: cut at about 40 tokens: 3 of 8 lines (about 61 tokens in all)
try: volec query show report --budget 100
$ refs restock --budget 20
# context/main.vl
5:19	use	crate	use stock::{Item, restock, total};
note query.budget: cut at about 20 tokens: 2 of 5 lines (about 52 tokens in all)
try: volec query refs restock --budget 100
