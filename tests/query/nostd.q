## std from a program that does not use it (0.15): by path, by a name
## the program does not define, its source by `std`, grep in it, a
## show with the `use` line a program needs.
$ def std::mem::swap Vec::push
std::mem::swap	<std>:1395:8	fn	pub fn swap<T>(a: &mut T, b: &mut T)
std::vec::Vec::push	<std>:4548:12	method	pub fn push(&mut self, x: T) debug ensures self.len() == old(self.len()) + 1 debug ensures self.len() <= self.capacity()
$ def read_line twice
std::io::BufRead::read_line	<std>:19798:8	trait-method	fn read_line<A: Allocator>(&mut self, buf: &mut String<A>) -> Result<usize>
std::io::Stdin::read_line	<std>:20078:12	method	pub fn read_line<A: Allocator>(&self, buf: &mut String<A>) -> Result<usize>
crate::twice	nostd/main.vl:4:4	fn	fn twice(x: i64) -> i64	effects: none
$ show std::mem::swap
// std::mem::swap	<std>:1392-1406
// use std::mem::swap;
// Exchanges the values of two places (MVS: two inout parameters).
// std: changed: takes &mut T twice
#[effects(unsafe, T)]
pub fn swap<T>(a: &mut T, b: &mut T) {
    // UNSAFE: raw moves (an assignment would drop the old value).
    // SAFETY: a and b are two live &mut, so valid, aligned and distinct;
    // each value is read once and ends in exactly one place.
    unsafe {
        let pa = a as *mut T;
        let pb = b as *mut T;
        let t = crate::ptr::read(pa as *const T);
        crate::ptr::copy_nonoverlapping(pb as *const T, pa, 1);
        crate::ptr::write(pb, t);
    }
}
$ text std:1-2
// std:1-2
1	// The standard library (0.27; the one std from 0.28.0): Rust's API. In
2	// 0.27.0 it was a spec for the rust edition: every item's signature in
$ grep 'pub fn read_line' --in std
# <std>
20078:5	code	std::io	pub fn read_line<A: Allocator>(&self, buf: &mut String<A>) -> Result<usize> {
$ def no_such_name
error query.no-match: no definition 'no_such_name'
try: volec query items
[exit 1]
