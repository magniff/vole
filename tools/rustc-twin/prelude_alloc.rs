// The rustc twin's prelude with Rust's real allocator_api (0.27.3,
// `--alloc-api`): rustc stable run as nightly (RUSTC_BOOTSTRAP=1,
// `-Zcrate-attr=feature(allocator_api)`), so that `Vec<T, A>`, `Box<T, A>`
// and `VecDeque<T, A>` are std's own, and an allocator held by reference
// (`b.allocator()`, an `&A`) is borrowed as rustc borrows it. What std
// lacks even there is here: `String<A>` (a Vec<u8, A> of UTF-8, with its
// Drop), `HashMap<K, V, A>` and `HashSet<T, A>` (std's, holding the
// allocator; their Drop keeps it live, as hashbrown's does), and the
// `_in` functions std has no allocator form of. Not the stable twin:
// tools/rustc-twin.sh says `rustc (allocator_api, RUSTC_BOOTSTRAP)` in its
// summary when this prelude is used.
#[allow(dead_code)]
mod vole_twin_prelude {
    pub use std::alloc::{Allocator, Global};
    use std::alloc::{AllocError, Layout};
    use std::fmt;
    use std::hash::Hash;
    use std::ptr::NonNull;

    /// vole's general-purpose allocator: Rust's global one.
    #[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
    pub struct Gpa;

    // SAFETY: every call is Global's, whose contract is Allocator's.
    unsafe impl Allocator for Gpa {
        fn allocate(&self, l: Layout) -> Result<NonNull<[u8]>, AllocError> {
            Global.allocate(l)
        }
        // SAFETY: p was allocated by Global with l (allocate above).
        unsafe fn deallocate(&self, p: NonNull<u8>, l: Layout) {
            unsafe { Global.deallocate(p, l) }
        }
    }

    /// std2's String<A>: UTF-8 in a Vec<u8, A>.
    pub struct String<A: Allocator = Gpa> {
        v: Vec<u8, A>,
    }

    impl<A: Allocator> String<A> {
        pub fn new_in(a: A) -> Self {
            String { v: Vec::new_in(a) }
        }
        pub fn with_capacity_in(n: usize, a: A) -> Self {
            String { v: Vec::with_capacity_in(n, a) }
        }
        pub fn from_in(s: &str, a: A) -> Self {
            let mut r = String::new_in(a);
            r.push_str(s);
            r
        }
        pub fn push_str(&mut self, s: &str) {
            self.v.extend_from_slice(s.as_bytes())
        }
        pub fn push(&mut self, c: char) {
            let mut b = [0u8; 4];
            self.push_str(c.encode_utf8(&mut b))
        }
        pub fn pop(&mut self) -> Option<char> {
            let c = self.as_str().chars().next_back()?;
            let n = self.v.len() - c.len_utf8();
            self.v.truncate(n);
            Some(c)
        }
        pub fn clear(&mut self) {
            self.v.clear()
        }
        pub fn truncate(&mut self, n: usize) {
            assert!(self.as_str().is_char_boundary(n));
            self.v.truncate(n)
        }
        pub fn insert_str(&mut self, i: usize, s: &str) {
            assert!(self.as_str().is_char_boundary(i));
            let tail: std::vec::Vec<u8> = self.v[i..].to_vec();
            self.v.truncate(i);
            self.v.extend_from_slice(s.as_bytes());
            self.v.extend_from_slice(&tail);
        }
        pub fn insert(&mut self, i: usize, c: char) {
            let mut b = [0u8; 4];
            self.insert_str(i, c.encode_utf8(&mut b))
        }
        pub fn as_str(&self) -> &str {
            // SAFETY: v holds UTF-8 only: every write above appends a str's
            // bytes, and truncate cuts at a char boundary.
            unsafe { std::str::from_utf8_unchecked(&self.v) }
        }
        pub fn as_mut_str(&mut self) -> &mut str {
            // SAFETY: as as_str's; a &mut str keeps it UTF-8.
            unsafe { std::str::from_utf8_unchecked_mut(&mut self.v) }
        }
        pub fn into_bytes(self) -> Vec<u8, A> {
            self.v
        }
        pub fn capacity(&self) -> usize {
            self.v.capacity()
        }
        pub fn reserve(&mut self, n: usize) {
            self.v.reserve(n)
        }
        pub fn allocator(&self) -> &A {
            self.v.allocator()
        }
    }

    impl<A: Allocator> std::ops::Deref for String<A> {
        type Target = str;
        fn deref(&self) -> &str {
            self.as_str()
        }
    }
    impl<A: Allocator> std::ops::DerefMut for String<A> {
        fn deref_mut(&mut self) -> &mut str {
            self.as_mut_str()
        }
    }
    impl<A: Allocator> fmt::Display for String<A> {
        fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
            fmt::Display::fmt(self.as_str(), f)
        }
    }
    impl<A: Allocator> fmt::Debug for String<A> {
        fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
            fmt::Debug::fmt(self.as_str(), f)
        }
    }
    impl<A: Allocator> fmt::Write for String<A> {
        fn write_str(&mut self, s: &str) -> fmt::Result {
            self.push_str(s);
            Ok(())
        }
    }
    impl<A: Allocator + Clone> Clone for String<A> {
        fn clone(&self) -> Self {
            String { v: self.v.clone() }
        }
    }
    impl<A: Allocator, B: Allocator> PartialEq<String<B>> for String<A> {
        fn eq(&self, o: &String<B>) -> bool {
            self.as_str() == o.as_str()
        }
    }
    impl<A: Allocator> Eq for String<A> {}
    impl<A: Allocator> PartialEq<str> for String<A> {
        fn eq(&self, o: &str) -> bool {
            self.as_str() == o
        }
    }
    impl<'b, A: Allocator> PartialEq<&'b str> for String<A> {
        fn eq(&self, o: &&'b str) -> bool {
            self.as_str() == *o
        }
    }
    impl<A: Allocator> PartialOrd for String<A> {
        fn partial_cmp(&self, o: &Self) -> Option<std::cmp::Ordering> {
            Some(self.as_str().cmp(o.as_str()))
        }
    }
    impl<A: Allocator> Ord for String<A> {
        fn cmp(&self, o: &Self) -> std::cmp::Ordering {
            self.as_str().cmp(o.as_str())
        }
    }
    impl<A: Allocator> Hash for String<A> {
        fn hash<H: std::hash::Hasher>(&self, h: &mut H) {
            self.as_str().hash(h)
        }
    }
    impl<A: Allocator> std::borrow::Borrow<str> for String<A> {
        fn borrow(&self) -> &str {
            self.as_str()
        }
    }
    impl<A: Allocator> AsRef<str> for String<A> {
        fn as_ref(&self) -> &str {
            self.as_str()
        }
    }
    impl<A: Allocator> Extend<char> for String<A> {
        fn extend<I: IntoIterator<Item = char>>(&mut self, it: I) {
            for c in it {
                self.push(c)
            }
        }
    }
    impl<'b, A: Allocator> Extend<&'b str> for String<A> {
        fn extend<I: IntoIterator<Item = &'b str>>(&mut self, it: I) {
            for s in it {
                self.push_str(s)
            }
        }
    }

    /// std's HashMap holding vole's allocator (hashbrown's A): its Drop
    /// keeps the allocator live, as hashbrown's RawTable does.
    pub struct HashMap<K, V, A: Allocator = Gpa> {
        m: std::collections::HashMap<K, V>,
        a: A,
    }
    impl<K, V, A: Allocator> Drop for HashMap<K, V, A> {
        fn drop(&mut self) {}
    }
    impl<K: Eq + Hash, V, A: Allocator> HashMap<K, V, A> {
        pub fn new_in(a: A) -> Self {
            HashMap { m: std::collections::HashMap::new(), a }
        }
        pub fn with_capacity_in(n: usize, a: A) -> Self {
            HashMap { m: std::collections::HashMap::with_capacity(n), a }
        }
        pub fn allocator(&self) -> &A {
            &self.a
        }
    }
    impl<K, V, A: Allocator> std::ops::Deref for HashMap<K, V, A> {
        type Target = std::collections::HashMap<K, V>;
        fn deref(&self) -> &Self::Target {
            &self.m
        }
    }
    impl<K, V, A: Allocator> std::ops::DerefMut for HashMap<K, V, A> {
        fn deref_mut(&mut self) -> &mut Self::Target {
            &mut self.m
        }
    }
    impl<'m, K, V, A: Allocator> IntoIterator for &'m HashMap<K, V, A> {
        type Item = (&'m K, &'m V);
        type IntoIter = std::collections::hash_map::Iter<'m, K, V>;
        fn into_iter(self) -> Self::IntoIter {
            self.m.iter()
        }
    }
    impl<'m, K, V, A: Allocator> IntoIterator for &'m mut HashMap<K, V, A> {
        type Item = (&'m K, &'m mut V);
        type IntoIter = std::collections::hash_map::IterMut<'m, K, V>;
        fn into_iter(self) -> Self::IntoIter {
            self.m.iter_mut()
        }
    }
    impl<K, V, A: Allocator> IntoIterator for HashMap<K, V, A> {
        type Item = (K, V);
        type IntoIter = std::collections::hash_map::IntoIter<K, V>;
        fn into_iter(mut self) -> Self::IntoIter {
            std::mem::take(&mut self.m).into_iter()
        }
    }
    impl<K: fmt::Debug, V: fmt::Debug, A: Allocator> fmt::Debug for HashMap<K, V, A> {
        fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
            fmt::Debug::fmt(&self.m, f)
        }
    }
    impl<K: Eq + Hash, V: PartialEq, A: Allocator> PartialEq for HashMap<K, V, A> {
        fn eq(&self, o: &Self) -> bool {
            self.m == o.m
        }
    }

    /// std's HashSet holding vole's allocator, as HashMap.
    pub struct HashSet<T, A: Allocator = Gpa> {
        m: std::collections::HashSet<T>,
        a: A,
    }
    impl<T, A: Allocator> Drop for HashSet<T, A> {
        fn drop(&mut self) {}
    }
    impl<T: Eq + Hash, A: Allocator> HashSet<T, A> {
        pub fn new_in(a: A) -> Self {
            HashSet { m: std::collections::HashSet::new(), a }
        }
        pub fn with_capacity_in(n: usize, a: A) -> Self {
            HashSet { m: std::collections::HashSet::with_capacity(n), a }
        }
        pub fn allocator(&self) -> &A {
            &self.a
        }
    }
    impl<T, A: Allocator> std::ops::Deref for HashSet<T, A> {
        type Target = std::collections::HashSet<T>;
        fn deref(&self) -> &Self::Target {
            &self.m
        }
    }
    impl<T, A: Allocator> std::ops::DerefMut for HashSet<T, A> {
        fn deref_mut(&mut self) -> &mut Self::Target {
            &mut self.m
        }
    }
    impl<'m, T, A: Allocator> IntoIterator for &'m HashSet<T, A> {
        type Item = &'m T;
        type IntoIter = std::collections::hash_set::Iter<'m, T>;
        fn into_iter(self) -> Self::IntoIter {
            self.m.iter()
        }
    }
    impl<T, A: Allocator> IntoIterator for HashSet<T, A> {
        type Item = T;
        type IntoIter = std::collections::hash_set::IntoIter<T>;
        fn into_iter(mut self) -> Self::IntoIter {
            std::mem::take(&mut self.m).into_iter()
        }
    }
    impl<T: fmt::Debug, A: Allocator> fmt::Debug for HashSet<T, A> {
        fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
            fmt::Debug::fmt(&self.m, f)
        }
    }

    // `x.to_string_in(a)`
    pub trait ToStringIn {
        fn to_string_in<A: Allocator>(&self, a: A) -> String<A>;
    }
    impl<T: fmt::Display + ?Sized> ToStringIn for T {
        fn to_string_in<A: Allocator>(&self, a: A) -> String<A> {
            let mut s = String::new_in(a);
            let _ = fmt::Write::write_fmt(&mut s, format_args!("{}", self));
            s
        }
    }
    /// `format_in(.., a)`: the text's `vole_format_in(a, format_args!(..))`.
    pub fn vole_format_in<A: Allocator>(a: A, x: fmt::Arguments<'_>) -> String<A> {
        let mut s = String::new_in(a);
        let _ = fmt::Write::write_fmt(&mut s, x);
        s
    }

    // `T::from_in(x, a)`
    pub trait FromIn<X, A: Allocator>: Sized {
        fn from_in(x: X, a: A) -> Self;
    }
    impl<T, A: Allocator, const N: usize> FromIn<[T; N], A> for Vec<T, A> {
        fn from_in(x: [T; N], a: A) -> Self {
            let mut v = Vec::with_capacity_in(N, a);
            v.extend(x);
            v
        }
    }
    impl<T: Clone, A: Allocator> FromIn<&[T], A> for Vec<T, A> {
        fn from_in(x: &[T], a: A) -> Self {
            let mut v = Vec::with_capacity_in(x.len(), a);
            v.extend_from_slice(x);
            v
        }
    }
    impl<A: Allocator> FromIn<&str, A> for Vec<u8, A> {
        fn from_in(x: &str, a: A) -> Self {
            Vec::from_in(x.as_bytes(), a)
        }
    }
    impl<T, A: Allocator> FromIn<T, A> for Box<T, A> {
        fn from_in(x: T, a: A) -> Self {
            Box::new_in(x, a)
        }
    }

    // `x.clone_in(a)`, `x.to_vec_in(a)`, `x.to_owned_in(a)`
    pub trait CloneIn<A: Allocator> {
        type Out;
        fn clone_in(&self, a: A) -> Self::Out;
    }
    impl<T: Clone, B: Allocator, A: Allocator> CloneIn<A> for Vec<T, B> {
        type Out = Vec<T, A>;
        fn clone_in(&self, a: A) -> Vec<T, A> {
            let mut v = Vec::with_capacity_in(self.len(), a);
            v.extend_from_slice(self);
            v
        }
    }
    impl<B: Allocator, A: Allocator> CloneIn<A> for String<B> {
        type Out = String<A>;
        fn clone_in(&self, a: A) -> String<A> {
            String::from_in(self.as_str(), a)
        }
    }
    pub trait StrIn {
        fn to_owned_in<A: Allocator>(&self, a: A) -> String<A>;
        fn to_uppercase_in<A: Allocator>(&self, a: A) -> String<A>;
        fn to_lowercase_in<A: Allocator>(&self, a: A) -> String<A>;
        fn repeat_in<A: Allocator>(&self, n: usize, a: A) -> String<A>;
        fn replace_in<A: Allocator>(&self, from: &str, to: &str, a: A) -> String<A>;
    }
    impl StrIn for str {
        fn to_owned_in<A: Allocator>(&self, a: A) -> String<A> {
            String::from_in(self, a)
        }
        fn to_uppercase_in<A: Allocator>(&self, a: A) -> String<A> {
            String::from_in(&self.to_uppercase(), a)
        }
        fn to_lowercase_in<A: Allocator>(&self, a: A) -> String<A> {
            String::from_in(&self.to_lowercase(), a)
        }
        fn repeat_in<A: Allocator>(&self, n: usize, a: A) -> String<A> {
            String::from_in(&self.repeat(n), a)
        }
        fn replace_in<A: Allocator>(&self, from: &str, to: &str, a: A) -> String<A> {
            String::from_in(&self.replace(from, to), a)
        }
    }
    pub trait SliceIn<T> {
        fn sort_in<A: Allocator>(&mut self, a: A) where T: Ord;
        fn sort_by_in<A: Allocator, F: FnMut(&T, &T) -> std::cmp::Ordering>(&mut self, f: F, a: A);
        fn sort_by_key_in<A: Allocator, K: Ord, F: FnMut(&T) -> K>(&mut self, f: F, a: A);
    }
    impl<T> SliceIn<T> for [T] {
        fn sort_in<A: Allocator>(&mut self, _: A) where T: Ord {
            self.sort()
        }
        fn sort_by_in<A: Allocator, F: FnMut(&T, &T) -> std::cmp::Ordering>(&mut self, f: F, _: A) {
            self.sort_by(f)
        }
        fn sort_by_key_in<A: Allocator, K: Ord, F: FnMut(&T) -> K>(&mut self, f: F, _: A) {
            self.sort_by_key(f)
        }
    }

    // `it.collect_in(a)`: into a collection made in a
    pub trait FromIteratorIn<T, A: Allocator>: Sized {
        fn from_iter_in<I: IntoIterator<Item = T>>(it: I, a: A) -> Self;
    }
    impl<T, A: Allocator> FromIteratorIn<T, A> for Vec<T, A> {
        fn from_iter_in<I: IntoIterator<Item = T>>(it: I, a: A) -> Self {
            let mut v = Vec::new_in(a);
            v.extend(it);
            v
        }
    }
    impl<A: Allocator> FromIteratorIn<char, A> for String<A> {
        fn from_iter_in<I: IntoIterator<Item = char>>(it: I, a: A) -> Self {
            let mut s = String::new_in(a);
            s.extend(it);
            s
        }
    }
    impl<'b, A: Allocator> FromIteratorIn<&'b str, A> for String<A> {
        fn from_iter_in<I: IntoIterator<Item = &'b str>>(it: I, a: A) -> Self {
            let mut s = String::new_in(a);
            s.extend(it);
            s
        }
    }
    impl<K: Eq + Hash, V, A: Allocator> FromIteratorIn<(K, V), A> for HashMap<K, V, A> {
        fn from_iter_in<I: IntoIterator<Item = (K, V)>>(it: I, a: A) -> Self {
            let mut m = HashMap::new_in(a);
            m.extend(it);
            m
        }
    }
    impl<T: Eq + Hash, A: Allocator> FromIteratorIn<T, A> for HashSet<T, A> {
        fn from_iter_in<I: IntoIterator<Item = T>>(it: I, a: A) -> Self {
            let mut m = HashSet::new_in(a);
            m.extend(it);
            m
        }
    }
    pub trait CollectIn: Iterator + Sized {
        fn collect_in<B: FromIteratorIn<Self::Item, A>, A: Allocator>(self, a: A) -> B {
            B::from_iter_in(self, a)
        }
    }
    impl<I: Iterator> CollectIn for I {}

    // `T::default_in(a)`
    pub trait DefaultIn<A: Allocator>: Sized {
        fn default_in(a: A) -> Self;
    }
    impl<T, A: Allocator> DefaultIn<A> for Vec<T, A> {
        fn default_in(a: A) -> Self {
            Vec::new_in(a)
        }
    }
    impl<A: Allocator> DefaultIn<A> for String<A> {
        fn default_in(a: A) -> Self {
            String::new_in(a)
        }
    }
}
#[allow(unused_imports)]
use vole_twin_prelude::*;
#[allow(unused_imports)]
use std::fmt::Write as _;
// (0.27.6: into a Vec<u8, A>, `write(&mut buf, ..)` of a Buf's push_fmt:
// io::Write's)
#[allow(unused_imports)]
use std::io::Write as _;
