## (0.25.2.2) A missing `use` of a name std re-exports (`std::I64_MIN`,
## whose item is std::num's): fix chooses among the modules that have the
## name by the kind of the item the checker's help names. Its key was
## looked up in std's root module, where a re-export has none (-1), and
## the kind read SYM_FN[-1], before the table: a crash (SIGBUS) when that
## page was not mapped, rare unless the allocator places the table at the
## start of its region. Run with guard malloc where there is one (macOS:
## every allocation right after an unmapped page, so the read before it
## always faults); elsewhere plainly.
% if [ -r /usr/lib/libgmalloc.dylib ]; then export DYLD_INSERT_LIBRARIES=/usr/lib/libgmalloc.dylib MALLOC_PROTECT_BEFORE=1 MALLOC_ALLOW_LARGE_REQUESTS=1; fi; "$COMPILER" fix --dry-run 2>&1 | grep -v '^GuardMalloc'
--- a/main.vl
+++ b/main.vl
@@ -1 +1 @@
-use std::max;
+use std::{I64_MIN, max};
$ fix
fixed 1 missing import	main.vl	+1 -1 lines
$ check
ok: 0 errors in main.vl
