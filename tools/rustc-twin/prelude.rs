// The rustc twin's prelude (0.27.3, plan-0271 §2.2): the part of
// `allocator_api` that rustc stable lacks, as extension traits over one
// global allocator, `Gpa`. A rust-edition vole program keeps its `_in`
// calls (`Vec::new_in(gpa)`, `x.to_string_in(gpa)`, `it.collect_in(gpa)`)
// and they resolve here to std's (`Vec::new()`, `x.to_string()`,
// `it.collect()`); its types lose their allocator argument
// (`Vec<T, Gpa>` -> `Vec<T>`, `String<Gpa>` -> `String`), which
// tools/rustc-twin/twin.py drops in the text. Prepended to every program
// the twin builds; `#[allow]`ed: the unstable_name_collisions warnings are
// std's own `new_in` (nightly) against these.
#[allow(dead_code)]
mod vole_twin_prelude {
    use std::collections::{BTreeMap, BTreeSet, BinaryHeap, HashMap, HashSet, LinkedList, VecDeque};
    use std::hash::BuildHasher;

    /// vole's general-purpose allocator: Rust's global one.
    #[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
    pub struct Gpa;

    /// What vole's `A: Allocator` bounds: here, only Gpa.
    pub trait Allocator: Copy {}
    impl Allocator for Gpa {}

    // `T::new_in(a)`: std's `T::new()`
    pub trait NewIn: Sized {
        fn new_in(a: Gpa) -> Self;
    }
    macro_rules! new_in {
        ($($t:ty => [$($g:tt)*] $(where $($w:tt)*)?;)*) => {
            $(impl<$($g)*> NewIn for $t $(where $($w)*)? {
                fn new_in(_: Gpa) -> Self { <$t>::new() }
            })*
        };
    }
    new_in! {
        Vec<T> => [T];
        String => [];
        VecDeque<T> => [T];
        LinkedList<T> => [T];
        HashMap<K, V> => [K, V];
        HashSet<T> => [T];
        BTreeMap<K, V> => [K: Ord, V];
        BTreeSet<T> => [T: Ord];
        BinaryHeap<T> => [T: Ord];
    }

    // `T::with_capacity_in(n, a)`: `T::with_capacity(n)`
    pub trait WithCapacityIn: Sized {
        fn with_capacity_in(n: usize, a: Gpa) -> Self;
    }
    macro_rules! with_capacity_in {
        ($($t:ty => [$($g:tt)*];)*) => {
            $(impl<$($g)*> WithCapacityIn for $t {
                fn with_capacity_in(n: usize, _: Gpa) -> Self { <$t>::with_capacity(n) }
            })*
        };
    }
    with_capacity_in! {
        Vec<T> => [T];
        String => [];
        VecDeque<T> => [T];
        HashMap<K, V> => [K, V];
        HashSet<T> => [T];
        BinaryHeap<T> => [T: Ord];
    }

    // `T::with_hasher_in(h, a)`, `T::with_capacity_and_hasher_in(n, h, a)`
    pub trait WithHasherIn<S>: Sized {
        fn with_hasher_in(h: S, a: Gpa) -> Self;
        fn with_capacity_and_hasher_in(n: usize, h: S, a: Gpa) -> Self;
    }
    impl<K, V, S: BuildHasher> WithHasherIn<S> for HashMap<K, V, S> {
        fn with_hasher_in(h: S, _: Gpa) -> Self { HashMap::with_hasher(h) }
        fn with_capacity_and_hasher_in(n: usize, h: S, _: Gpa) -> Self { HashMap::with_capacity_and_hasher(n, h) }
    }
    impl<T, S: BuildHasher> WithHasherIn<S> for HashSet<T, S> {
        fn with_hasher_in(h: S, _: Gpa) -> Self { HashSet::with_hasher(h) }
        fn with_capacity_and_hasher_in(n: usize, h: S, _: Gpa) -> Self { HashSet::with_capacity_and_hasher(n, h) }
    }

    // `T::from_in(x, a)`: `T::from(x)`
    pub trait FromIn<X>: Sized {
        fn from_in(x: X, a: Gpa) -> Self;
    }
    impl<X, T: From<X>> FromIn<X> for T {
        fn from_in(x: X, _: Gpa) -> Self { T::from(x) }
    }

    // `Box::new_in(x, a)`: `Box::new(x)`
    pub trait BoxNewIn<T> {
        fn new_in(x: T, a: Gpa) -> Self;
    }
    impl<T> BoxNewIn<T> for Box<T> {
        fn new_in(x: T, _: Gpa) -> Self { Box::new(x) }
    }

    // `T::default_in(a)`: `T::default()`
    pub trait DefaultIn: Sized {
        fn default_in(a: Gpa) -> Self;
    }
    impl<T: Default> DefaultIn for T {
        fn default_in(_: Gpa) -> Self { T::default() }
    }

    // `B::from_iter_in(it, a)`: `B::from_iter(it)`
    pub trait FromIteratorIn<T>: Sized {
        fn from_iter_in<I: IntoIterator<Item = T>>(it: I, a: Gpa) -> Self;
    }
    impl<T, B: FromIterator<T>> FromIteratorIn<T> for B {
        fn from_iter_in<I: IntoIterator<Item = T>>(it: I, _: Gpa) -> Self { B::from_iter(it) }
    }

    // `x.to_string_in(a)`: `x.to_string()`
    pub trait ToStringIn {
        fn to_string_in(&self, a: Gpa) -> String;
    }
    impl<T: std::fmt::Display + ?Sized> ToStringIn for T {
        fn to_string_in(&self, _: Gpa) -> String { self.to_string() }
    }

    // `x.clone_in(a)`: `x.clone()`
    pub trait CloneIn: Sized {
        fn clone_in(&self, a: Gpa) -> Self;
    }
    impl<T: Clone> CloneIn for T {
        fn clone_in(&self, _: Gpa) -> Self { self.clone() }
    }

    // `x.to_owned_in(a)`: `x.to_owned()`
    pub trait ToOwnedIn {
        type Owned;
        fn to_owned_in(&self, a: Gpa) -> Self::Owned;
    }
    impl<T: ToOwned + ?Sized> ToOwnedIn for T {
        type Owned = T::Owned;
        fn to_owned_in(&self, _: Gpa) -> T::Owned { self.to_owned() }
    }

    // `it.collect_in(a)`, `it.unzip_in(a)`, `it.partition_in(f, a)`
    pub trait CollectIn: Iterator + Sized {
        fn collect_in<B: FromIterator<Self::Item>>(self, _: Gpa) -> B { self.collect() }
        fn unzip_in<X, Y, FX: Default + Extend<X>, FY: Default + Extend<Y>>(self, _: Gpa) -> (FX, FY)
        where
            Self: Iterator<Item = (X, Y)>,
        {
            self.unzip()
        }
        fn partition_in<B: Default + Extend<Self::Item>, F: FnMut(&Self::Item) -> bool>(self, f: F, _: Gpa) -> (B, B) {
            self.partition(f)
        }
    }
    impl<I: Iterator> CollectIn for I {}

    // a slice's: `to_vec_in`, `repeat_in`, `sort_in`, `sort_by_in`, `sort_by_key_in`
    pub trait SliceIn<T> {
        fn to_vec_in(&self, a: Gpa) -> Vec<T> where T: Clone;
        fn repeat_in(&self, n: usize, a: Gpa) -> Vec<T> where T: Copy;
        fn sort_in(&mut self, a: Gpa) where T: Ord;
        fn sort_by_in<F: FnMut(&T, &T) -> std::cmp::Ordering>(&mut self, f: F, a: Gpa);
        fn sort_by_key_in<K: Ord, F: FnMut(&T) -> K>(&mut self, f: F, a: Gpa);
    }
    impl<T> SliceIn<T> for [T] {
        fn to_vec_in(&self, _: Gpa) -> Vec<T> where T: Clone { self.to_vec() }
        fn repeat_in(&self, n: usize, _: Gpa) -> Vec<T> where T: Copy { self.repeat(n) }
        fn sort_in(&mut self, _: Gpa) where T: Ord { self.sort() }
        fn sort_by_in<F: FnMut(&T, &T) -> std::cmp::Ordering>(&mut self, f: F, _: Gpa) { self.sort_by(f) }
        fn sort_by_key_in<K: Ord, F: FnMut(&T) -> K>(&mut self, f: F, _: Gpa) { self.sort_by_key(f) }
    }

    // a str's
    pub trait StrIn {
        fn repeat_in(&self, n: usize, a: Gpa) -> String;
        fn to_uppercase_in(&self, a: Gpa) -> String;
        fn to_lowercase_in(&self, a: Gpa) -> String;
        fn to_ascii_uppercase_in(&self, a: Gpa) -> String;
        fn to_ascii_lowercase_in(&self, a: Gpa) -> String;
        fn replace_in(&self, from: &str, to: &str, a: Gpa) -> String;
        fn replacen_in(&self, from: &str, to: &str, n: usize, a: Gpa) -> String;
    }
    impl StrIn for str {
        fn repeat_in(&self, n: usize, _: Gpa) -> String { self.repeat(n) }
        fn to_uppercase_in(&self, _: Gpa) -> String { self.to_uppercase() }
        fn to_lowercase_in(&self, _: Gpa) -> String { self.to_lowercase() }
        fn to_ascii_uppercase_in(&self, _: Gpa) -> String { self.to_ascii_uppercase() }
        fn to_ascii_lowercase_in(&self, _: Gpa) -> String { self.to_ascii_lowercase() }
        fn replace_in(&self, from: &str, to: &str, _: Gpa) -> String { self.replace(from, to) }
        fn replacen_in(&self, from: &str, to: &str, n: usize, _: Gpa) -> String { self.replacen(from, to, n) }
    }

    // a reader's `lines_in(a)`
    pub trait LinesIn: std::io::BufRead + Sized {
        fn lines_in(self, _: Gpa) -> std::io::Lines<Self> { self.lines() }
    }
    impl<R: std::io::BufRead> LinesIn for R {}
    pub trait StdinLinesIn {
        fn lines_in(self, a: Gpa) -> std::io::Lines<std::io::StdinLock<'static>>;
    }
    impl StdinLinesIn for std::io::Stdin {
        fn lines_in(self, _: Gpa) -> std::io::Lines<std::io::StdinLock<'static>> { self.lines() }
    }

    // `Command::new_in(p, a)`: std's `Command::new(p)` (std2's Command
    // keeps its strings on a)
    pub trait CommandNewIn {
        fn new_in<S: AsRef<std::ffi::OsStr>>(program: S, a: Gpa) -> Self;
    }
    impl CommandNewIn for std::process::Command {
        fn new_in<S: AsRef<std::ffi::OsStr>>(program: S, _: Gpa) -> Self { std::process::Command::new(program) }
    }
}
#[allow(unused_imports)]
use vole_twin_prelude::*;
// (vole's `write(s, ..)` into a String: fmt::Write's, which Rust imports)
#[allow(unused_imports)]
use std::fmt::Write as _;
// (0.27.6: into a Vec<u8, A>, `write(&mut buf, ..)` of a Buf's push_fmt:
// io::Write's)
#[allow(unused_imports)]
use std::io::Write as _;
