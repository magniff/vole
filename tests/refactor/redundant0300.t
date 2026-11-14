## 0.30: `use.redundant`, an import of an item the prelude gives every
## module anyway (`Vec`, `Option`, `Gpa`, `FixedState`). The name is used,
## so `use.unused` never saw it, and `volec fix` removed none of them in
## 340 files (0.29). An import of another item of a prelude name
## (`std::fmt::Result`) is not one; a brace list keeps its other names.
$ check
main.vl:1:29: warning[use.redundant] redundant import 'Gpa': the prelude gives it to every module | help: remove it (`volec fix` removes every redundant import) | try: volec fix --only redundant main.vl
main.vl:4:16: warning[use.redundant] redundant import 'FixedState': the prelude gives it to every module | help: remove it (`volec fix` removes every redundant import) | try: volec fix --only redundant main.vl
main.vl:5:18: warning[use.redundant] redundant import 'Option': the prelude gives it to every module | help: remove it (`volec fix` removes every redundant import) | try: volec fix --only redundant main.vl
main.vl:6:15: warning[use.redundant] redundant import 'Vec': the prelude gives it to every module | help: remove it (`volec fix` removes every redundant import) | try: volec fix --only redundant main.vl
ok: 0 errors, 4 warnings in main.vl (2 files, 0 shaders)
$ fix --dry-run
--- a/main.vl
+++ b/main.vl
@@ -1 +1 @@
-use std::alloc::{Allocator, Gpa};
+use std::alloc::Allocator;
@@ -4,3 +3,0 @@
-use std::hash::FixedState;
-use std::option::Option;
-use std::vec::Vec;
$ fix
fixed 4 redundant imports	main.vl	+1 -4 lines
% sed -n 1,5p main.vl
use std::alloc::Allocator;
use std::collections::HashMap;
use std::fmt::{Display, Formatter, Result};

mod shapes;
$ check
ok: 0 errors in main.vl (2 files, 0 shaders)
## --only unused leaves them (the check hook runs it by itself); --only
## redundant takes them alone; `query unused` lists none of them.
% git checkout -q .
$ fix --only unused
note fix.none: nothing to fix
$ query unused
note query.empty: nothing unused
$ fix --only redundant
fixed 4 redundant imports	main.vl	+1 -4 lines
## A build does not lint: its warnings are of what it compiles.
% git checkout -q .
% volec main.vl -c -o /dev/null --deny-warnings 2>&1 | tail -1
ok: wrote /dev/null
$ explain use.redundant
use.redundant: warning (compiler)
(0.30) An import of an item the prelude already gives every module (`use std::vec::Vec;`, `Gpa` in `use std::alloc::{Allocator, Gpa};`): the name is used, so it is no `use.unused`, and the import adds nothing. An import of another item of a prelude name (`use std::fmt::Result;`), a renamed one (`as`) and a `pub use` are not reported. `volec check` and the tools report it; a build does not lint.
fix: Remove it: `volec fix --only redundant ROOT` (the try: line) removes every one, a name of a brace list too, and `volec fix` does with the other fixes.
example:
    main.vl:4:16: warning[use.redundant] redundant import 'FixedState': the prelude gives it to every module | help: remove it (`volec fix` removes every redundant import) | try: volec fix --only redundant main.vl
