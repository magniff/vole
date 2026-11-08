## fix --edition rust (0.27.4, gate 3): an impl of MVS's Allocator is
## std2's: try_alloc is allocate, try_resize grow and also shrink, which
## calls it (MVS's try_resize keeps the first min(old, new) bytes, as
## realloc does, so a shrink through it keeps the elements: std2's own
## default shrink would allocate and copy instead), free deallocate. A
## `return E` in a body gives E's Result. Written, then (a shrink
## added) built and run in the rust edition: the Vec grows to 100, then
## shrinks to its 3 elements, kept.
$ fix --edition rust --list-left main.vl
fixed, 1 var to 'let mut', 1 integer annotated, 2 imports, 15 types, 1 copy type derived Clone, Copy	main.vl	+32 -11 lines
% sed -i '' 's|// shrink|v.shrink_to_fit(); println("cap {}", v.capacity());|' main.vl
% cat main.vl
// fix --edition rust (0.27.4, gate 3): an impl of MVS's Allocator is
// std2's. try_alloc is allocate, try_resize grow and shrink (realloc
// keeps the first min(old, new) bytes either way, so shrink calling grow
// is right), free deallocate; each body is kept, its parameters bound
// from the layouts. A Vec over it grows, then shrinks to its length.
use std::alloc::Layout; use std::ptr::NonNull; use std::alloc::AllocError; use std::alloc::Allocator; #[derive(Clone, Copy)] struct Heap {}

// UNSAFE: C's allocator, which Heap hands out.
// SAFETY: called with sizes checked non-negative, on blocks Heap allocated.
extern "C" {
    fn malloc(n: u64) -> *mut u8;
    fn realloc(p: *mut u8, n: u64) -> *mut u8;
    fn free(p: *mut u8);
}

// UNSAFE: an allocator built over C's (Allocator is an unsafe trait).
// SAFETY: its memory comes from C's malloc, realloc and free, aligned to 16.
unsafe impl Allocator for Heap {
    fn allocate(&self, __layout: Layout) -> Result<NonNull<u8>, AllocError> {
        let size = __layout.size() as i64;
        let align = __layout.align() as i64;
        NonNull::new({
        if size < 0 || align > 16 {
            return NonNull::new(0 as *mut u8).ok_or(AllocError);
        }
        // UNSAFE: C's allocator.
        // SAFETY: size is checked non-negative.
        unsafe { malloc(if size == 0 { 1 } else { size } as u64) }
    }).ok_or(AllocError) }

    // UNSAFE: the trait's unsafe method (p must be Heap's block).
    // SAFETY: the caller passes its own block.
    unsafe fn grow(&self, __p: NonNull<u8>, __old: Layout, __new: Layout) -> Result<NonNull<u8>, AllocError> {
        let p = __p.as_ptr();
        let old_size = __old.size() as i64;
        let new_size = __new.size() as i64;
        let align = __new.align() as i64;
        NonNull::new({
        realloc(p, if new_size <= 0 { 1 } else { new_size } as u64)
    }).ok_or(AllocError) }

    // UNSAFE: shrink is an unsafe fn of the unsafe trait Allocator
    // SAFETY: its caller keeps Allocator's contract for p, old and new
    unsafe fn shrink(&self, p: NonNull<u8>, old: Layout, new: Layout) -> Result<NonNull<u8>, AllocError> {
        // UNSAFE: grow is an unsafe fn of Allocator
        // SAFETY: the caller of shrink keeps the same contract, and
        // realloc makes a block smaller as it makes one larger
        unsafe { self.grow(p, old, new) }
    }

    // UNSAFE: the trait's unsafe method (p must be Heap's block).
    // SAFETY: the caller passes its own block, once.
    unsafe fn deallocate(&self, __p: NonNull<u8>, __layout: Layout) {
        let p = __p.as_ptr();
        let size = __layout.size() as i64;
        let align = __layout.align() as i64;
        free(p);
    }
}

fn main() {
    let mut v: Vec<i64, Heap> = Vec::new_in(Heap {});
    for i in 0..100 {
        v.push(i);
    }
    v.truncate(3usize);
    v.shrink_to_fit(); println("cap {}", v.capacity());
    println("{} {} {} {}", v.len(), v[0], v[1], v[2]);
}
// EDITION: rust
$ main.vl -o prog
ok: built prog
% ./prog
cap 3
3 0 1 2
