## XFAIL: RT-218: query show's `// use ...;` line for an item of std's prelude names a path that does not resolve: `// use std::DefaultIn;` (0.30.2)
## `query show DefaultIn` prints `// use std::DefaultIn;` under its header,
## and `use std::DefaultIn;` in a program is `error[type error] unresolved
## import 'std::DefaultIn'`. FromIteratorIn (`// use std::FromIteratorIn;`),
## FixedState and Extend the same; each is in the prelude (`use
## std::default::DefaultIn;` is `use.redundant`), and an item outside it
## gets a path that resolves (`// use std::ops::RangeBounds;`). Below, the
## line says the prelude gives it; the exact text is the fixer's.
## v0.30.1 the same.
$ query show DefaultIn
// std::default::DefaultIn	<std>:1647-1652
// in the prelude (no use needed)
// A type's empty value, made with an allocator: `Vec::new_in(a)`,
// `String::new_in(a)`, or Default's for a type that holds none
// (`#[derive(DefaultIn)]` for a struct of DefaultIn fields).
pub trait DefaultIn<A>: Sized {
    fn default_in(a: A) -> Self;
}
