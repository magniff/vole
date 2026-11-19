## (0.30.2) `check`'s ` (N files, M shaders)` is the same answered from
## the tools' cache as without it. The shaders are counted from the front
## end's blocks (pcx.block_node), nodes the cache does not keep: a check
## answered from the cache said `0 shaders` for the blocks, and counted
## only the `.wgsl` files (0.29.0 to 0.30.1; the gate's cachediff row found
## it on rt_tl_003_rename_embed). The cache now keeps the two counts as
## the front end made them (tools::edit::cli::read_counts).
## main.vl has a block (TRACE), gfx/mod.vl a block (CLEAR) and a file
## (FILL, gfx/fill.wgsl). Each `%` check below has the cache of .git/qc,
## written before it ends (VOLE_CACHE_TRACE), and prints its trace: a
## `hit` is an answer from the cache, which must be the line before it.
$ check
ok: 0 errors in main.vl (2 files, 3 shaders)
% VOLE_CACHE=$PWD/.git/qc VOLE_CACHE_TRACE=$PWD/.git/tr volec check 2>&1; cat .git/tr; rm .git/tr
ok: 0 errors in main.vl (2 files, 3 shaders)
miss
save
% VOLE_CACHE=$PWD/.git/qc VOLE_CACHE_TRACE=$PWD/.git/tr volec check 2>&1; cat .git/tr; rm .git/tr
ok: 0 errors in main.vl (2 files, 3 shaders)
hit
## the shader's file edited: a miss (its hash), the same count
% printf '// one more line\n' >>gfx/fill.wgsl; VOLE_CACHE=$PWD/.git/qc VOLE_CACHE_TRACE=$PWD/.git/tr volec check 2>&1; cat .git/tr; rm .git/tr
ok: 0 errors in main.vl (2 files, 3 shaders)
miss
save
% VOLE_CACHE=$PWD/.git/qc VOLE_CACHE_TRACE=$PWD/.git/tr volec check 2>&1; cat .git/tr; rm .git/tr
ok: 0 errors in main.vl (2 files, 3 shaders)
hit
## a block added
% printf '\nembed wgsl EXTRA {\n    @compute @workgroup_size(1) fn extra() {}\n}\n' >>main.vl; VOLE_CACHE=$PWD/.git/qc VOLE_CACHE_TRACE=$PWD/.git/tr volec check 2>&1; cat .git/tr; rm .git/tr
ok: 0 errors in main.vl (2 files, 4 shaders)
miss
save
% VOLE_CACHE=$PWD/.git/qc VOLE_CACHE_TRACE=$PWD/.git/tr volec check 2>&1; cat .git/tr; rm .git/tr
ok: 0 errors in main.vl (2 files, 4 shaders)
hit
$ check
ok: 0 errors in main.vl (2 files, 4 shaders)
## a block taken away (CLEAR, gfx/mod.vl's last item)
% sed -i.bak '/^pub embed wgsl CLEAR/,$d' gfx/mod.vl; rm gfx/mod.vl.bak; VOLE_CACHE=$PWD/.git/qc VOLE_CACHE_TRACE=$PWD/.git/tr volec check 2>&1; cat .git/tr; rm .git/tr
ok: 0 errors in main.vl (2 files, 3 shaders)
miss
save
% VOLE_CACHE=$PWD/.git/qc VOLE_CACHE_TRACE=$PWD/.git/tr volec check 2>&1; cat .git/tr; rm .git/tr
ok: 0 errors in main.vl (2 files, 3 shaders)
hit
## with a warning (an unsafe block without its comments): the warning and
## the counts, both from the cache
% printf '\nfn peek() -> i64 {\n    let a: i64 = 1;\n    let p = &raw const a;\n    unsafe { *p }\n}\n' >>main.vl; VOLE_CACHE=$PWD/.git/qc VOLE_CACHE_TRACE=$PWD/.git/tr volec check 2>&1; cat .git/tr; rm .git/tr
main.vl:23:5: warning[unsafe.unjustified] unsafe block without `// UNSAFE:` and `// SAFETY:` comments | help: say right above it why it cannot be safe (`// UNSAFE: ...`) and why it is sound (`// SAFETY: ...`); the try: line lists the file's sites and what each does | try: volec query unsafe main.vl
ok: 0 errors, 1 warning in main.vl (2 files, 3 shaders)
miss
save
% VOLE_CACHE=$PWD/.git/qc VOLE_CACHE_TRACE=$PWD/.git/tr volec check 2>&1; cat .git/tr; rm .git/tr
main.vl:23:5: warning[unsafe.unjustified] unsafe block without `// UNSAFE:` and `// SAFETY:` comments | help: say right above it why it cannot be safe (`// UNSAFE: ...`) and why it is sound (`// SAFETY: ...`); the try: line lists the file's sites and what each does | try: volec query unsafe main.vl
ok: 0 errors, 1 warning in main.vl (2 files, 3 shaders)
hit
## an edit (a rename of peek, beside the blocks): the check after it is
## answered from the cache of the program the edit wrote (q-KEY.next.bin).
## (A rename of TRACE itself is refused, RT-TL-3: rt_tl_003_rename_embed.)
% VOLE_CACHE=$PWD/.git/qc VOLE_CACHE_TRACE=$PWD/.git/tr volec refactor rename peek peek2 2>&1; cat .git/tr; rm .git/tr
renamed crate::peek to peek2	main.vl	+1 -1 lines
miss
save
% VOLE_CACHE=$PWD/.git/qc VOLE_CACHE_TRACE=$PWD/.git/tr volec check 2>&1; cat .git/tr; rm .git/tr
main.vl:23:5: warning[unsafe.unjustified] unsafe block without `// UNSAFE:` and `// SAFETY:` comments | help: say right above it why it cannot be safe (`// UNSAFE: ...`) and why it is sound (`// SAFETY: ...`); the try: line lists the file's sites and what each does | try: volec query unsafe main.vl
ok: 0 errors, 1 warning in main.vl (2 files, 3 shaders)
hit
$ check
main.vl:23:5: warning[unsafe.unjustified] unsafe block without `// UNSAFE:` and `// SAFETY:` comments | help: say right above it why it cannot be safe (`// UNSAFE: ...`) and why it is sound (`// SAFETY: ...`); the try: line lists the file's sites and what each does | try: volec query unsafe main.vl
ok: 0 errors, 1 warning in main.vl (2 files, 3 shaders)
