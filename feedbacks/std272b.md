# std272b: std2 under --check-alloc, and gate 1's count

## Where it ended

- `--check-alloc` works on std2 (Z5). Gpa's implementation is the
  compiler's tail, `std::__gpa`: compiler/std2/rt/gpa.vl, or with the
  flag rt/alloc_check.vl, which is MVS's checking allocator in std2's
  spellings. The cases std2_alloc_check_{leak,clean,double_free,
  use_after_free} cover it; the sites (`file.vl:L:C`) show up as in MVS.
- The runner builds every `std2_` case with `--check-alloc` and fails a
  case that exits 0 with blocks of Gpa left (unless a STDERR line
  expects the list). The gate's `std2-tests` row prints the count.
- std2_: 458 of 1413 pass at -O0 and -O2 under --check-alloc (244 at
  the start); 955 XFAIL. Almost all of the rest are compiler gaps (the
  grouped list went to the integrator): Vec's slice methods through
  Deref (137), the HashMap/HashSet constructors on an instance with a
  default parameter (112), `&[T; N]` to `&[T]` (110), edition.std_by_value
  on std2 (64), arrays iterated by value (62). Those five are ~485 first
  errors.

## What helped

- `VOLE_TEST_XFAIL_WHY=FILE` (added to tests/run.sh): one run of the
  std2 cases writes each XFAIL case's first error, so the whole triage
  is a group-by over one file. Without it, 1,000 cases had to be rerun
  alone.
- Writing the checking allocator as a user program first, then moving
  it into the tail: the rust front took `static mut`, `extern "C" fn`
  handlers, `#[repr(C)]` and std's atomic intrinsics by name with no
  change.

## What got in the way

- The check-after-edit hook runs `volec check` on a std2 case after
  every edit, and reports 50 errors in `<std>` (unknown 'HashMap',
  own.readonly in min/max, ...) while the case builds clean: noise on
  every test edit (recorded with tools/agent-feedback).
- `volec fix --only unused` removes imports the file needs in Rust. One
  kind is a trait whose method the file calls through a blanket impl or
  a default method (BuildHasher::hash_one, Into::into, Read, Write).
  The other is `use std::io::{self}` while the file names `io::empty()`.
  This turned 130 valid cases into invalid ones until a trait-aware
  check reverted them; the cases that keep the import are XFAIL with the
  gap. Prelude traits (Into, TryFrom, ToStringIn, ...) are rightly
  unused. Also recorded.
- `git stash` around a script that rewrote hundreds of test files left
  the pop refusing ("would be overwritten"); a patch with `git apply
  --3way` after staging recovered it. Commit before mass rewrites.
- front272 fixed some of the same std2 bodies in parallel (Clone for
  `()`, Box::try_new_in's let), so the merge conflicted on them, and
  taking theirs dropped a fix of mine (Box's Debug through its trait).
  Rerun the std2 cases after every merge.
