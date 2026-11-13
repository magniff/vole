## alloc.default inside an item generic over an allocator (0.28.0;
## tests/refactor/allocgeneric0280/): the fix writes the item's allocator
## parameter (the impl's `A`, the function's `B`), not `Gpa`; with two
## allocator parameters there is no fix and the help says what to write;
## outside a generic item the fix is `Gpa`. The errors after an impl's
## alloc.default keep their own kind (`type error`, not `alloc.default`).
$ check
main.vl:5:12: error[alloc.default] 'Vec' names no allocator: its 'A' is written, last | help: this item is generic over the allocator 'A': write it (`, A`, the fix), or `Gpa` | try: volec fix --only alloc main.vl | try: volec fix --suggested main.vl
main.vl:9:15: error[alloc.default] 'Ring' names no allocator: its 'A' is the impl's parameter too | help: an impl block writes every type argument: 'impl<T, A: Allocator> Ring<T, A>' | try: volec fix --only alloc main.vl | try: volec fix --suggested main.vl
main.vl:20:51: error[alloc.default] 'Vec' names no allocator: its 'A' is written, last | help: this item is generic over the allocator 'B': write it (`, B`, the fix), or `Gpa` | try: volec fix --only alloc main.vl | try: volec fix --suggested main.vl
main.vl:24:65: error[alloc.default] 'Vec' names no allocator: its 'A' is written, last | help: this item is generic over the allocators 'B' and 'C': write the one this 'Vec' allocates from as its last type argument (`, B`); no fix chooses between them
main.vl:28:23: error[alloc.default] 'Vec' names no allocator: its 'A' is written, last | help: the allocator is part of the type: `Gpa` (the type of main's `gpa`), or a generic `A: Allocator` | try: volec fix --only alloc main.vl | try: volec fix --suggested main.vl
main.vl:35:13: error[type error] no method 'all' on type 'Ring<i64, Gpa>' | try: volec query items Ring main.vl
main.vl:36:13: error[type error] no method 'count' on type 'Ring<i64, Gpa>' | try: volec query items Ring main.vl
main.vl:37:13: error[type.infer] cannot infer type parameter 'T' of 'same' | help: nothing here says what it is: give the variable a type (`let x: TYPE = ...`), or write the type arguments (try:, with the parameter's type for its name) | try: same::<T, B>(...)
main.vl:38:13: error[type.infer] cannot infer type parameter 'T' of 'both' | help: nothing here says what it is: give the variable a type (`let x: TYPE = ...`), or write the type arguments (try:, with the parameter's type for its name) | try: both::<T, B, C>(...)
main.vl:40:22: error[type error] expected 'bool', got 'i32' | help: a condition is a bool: compare (`x != 0`); bitwise not is `!x` | try: 3 != 0 | try: volec fix --suggested main.vl
[exit 1]
$ fix --only alloc
fixed 7 suggested fixes	main.vl	+7 -7 lines
main.vl:24:65: error[alloc.default] 'Vec' names no allocator: its 'A' is written, last | help: this item is generic over the allocators 'B' and 'C': write the one this 'Vec' allocates from as its last type argument (`, B`); no fix chooses between them
main.vl:38:13: error[type.infer] cannot infer type parameter 'C' of 'both' | help: nothing here says what it is: give the variable a type (`let x: TYPE = ...`), or write the type arguments (try:, with the parameter's type for its name) | try: both::<i64, Gpa, C>(...)
main.vl:40:22: error[type error] expected 'bool', got 'i32' | help: a condition is a bool: compare (`x != 0`); bitwise not is `!x` | try: 3 != 0 | try: volec fix --suggested main.vl
note fix.left: 3 errors left (above)
% cat main.vl
use std::alloc::Allocator;

struct Ring<T, A: Allocator> {
    items: Vec<T, A>,
    spare: Vec<T, A>,
    head: usize,
}

impl<T: Copy, A: Allocator> Ring<T, A> {
    fn all(&self) -> &Vec<T, A> {
        let v: &Vec<T, A> = &self.items;
        v
    }

    fn count(&self, other: &Vec<T, A>) -> usize {
        other.len() + self.head + self.spare.len()
    }
}

fn same<T: Copy, B: Allocator>(v: &Vec<T, B>) -> &Vec<T, B> {
    v
}

fn both<T: Copy, B: Allocator, C: Allocator>(v: &Vec<T, B>, w: &Vec<T>) -> usize {
    v.len() + w.len()
}

fn plain(gpa: Gpa) -> Vec<i32, Gpa> {
    Vec::new_in(gpa)
}

fn main(gpa: Gpa) {
    let mut r: Ring<i64, Gpa> = Ring { items: Vec::new_in(gpa), spare: Vec::new_in(gpa), head: 0 };
    r.items.push(1);
    let a = r.all();
    let n = r.count(a);
    let b = same(a);
    let c = both(a, b);
    let d = plain(gpa);
    let done: bool = 3;
    println("{n} {c} {} {done}", d.len());
}
$ check
main.vl:24:65: error[alloc.default] 'Vec' names no allocator: its 'A' is written, last | help: this item is generic over the allocators 'B' and 'C': write the one this 'Vec' allocates from as its last type argument (`, B`); no fix chooses between them
main.vl:38:13: error[type.infer] cannot infer type parameter 'C' of 'both' | help: nothing here says what it is: give the variable a type (`let x: TYPE = ...`), or write the type arguments (try:, with the parameter's type for its name) | try: both::<i64, Gpa, C>(...)
main.vl:40:22: error[type error] expected 'bool', got 'i32' | help: a condition is a bool: compare (`x != 0`); bitwise not is `!x` | try: 3 != 0 | try: volec fix --suggested main.vl
[exit 1]
