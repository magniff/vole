## `check --changed` (0.29, tools/changed.vl): every program a file changed
## since the base belongs to is checked, and its changed .vl files compared
## with their layout: the one command for a harness without hooks, and
## premerge's check row. tests/refactor/changed0290/ holds a program with
## a module and a shader it embeds, a second program, a program of one
## file, and a file of no program.
## `check` says what it read: the program's files and its shaders.
$ check
ok: 0 errors in main.vl (2 files, 1 shader)
## nothing changed: said, not passed over
$ check --changed --since HEAD
ok: no program to check since HEAD (0 changed files)
## a shader alone: its program is checked (the nearest main.vl above)
% printf '// more\n' >> shade.wgsl
$ check --changed --since HEAD
ok: 0 errors in main.vl (2 files, 1 shader)
ok: 1 program checked, 0 changed .vl files formatted, since HEAD (1 changed file)
## and its error is the program's, at the shader's own line
% sed -i.bak 's/let level = 0.5;/let level = 0.5 + nosuchname;/' shade.wgsl && rm shade.wgsl.bak
$ check --changed --since HEAD
shade.wgsl:3:23: error[wgsl.name] unknown name 'nosuchname'
error check.changed: 1 of 1 program has errors, since HEAD (1 changed file)
[exit 1]
## a README beside a main.vl, a file of no program, a program of one
## file that is not formatted, a new file git does not track yet
% git checkout -q shade.wgsl && printf 'more\n' >> notes.md && printf 'more\n' >> second/README.md && printf '\n\n\nfn  extra( ) {}\n' >> alone/one.vl && printf 'pub fn thrice(x: i64) -> i64 {\n    x * 3\n}\n' > extra.vl
$ check --changed --since HEAD
alone/one.vl
ok: 0 errors in alone/one.vl (1 file, 0 shaders)
ok: 0 errors in main.vl (2 files, 1 shader)
ok: 0 errors in second/main.vl (1 file, 0 shaders)
error fmt.unformatted: 1 of 1 file is not formatted
try: volec fmt --dry-run alone/one.vl
try: volec fmt alone/one.vl
error check.changed: changed .vl files are not formatted, since HEAD (4 changed files; 1 of no program)
[exit 1]
## files under tests/ are their tests'
% volec fmt alone/one.vl && mkdir tests && cp alone/one.vl tests/case.vl
formatted	alone/one.vl	+1 -3 lines
$ check --changed --since HEAD
ok: 0 errors in alone/one.vl (1 file, 0 shaders)
ok: 0 errors in main.vl (2 files, 1 shader)
ok: 0 errors in second/main.vl (1 file, 0 shaders)
ok: 3 programs checked, 1 changed .vl file formatted, since HEAD (5 changed files; 1 under tests/, which their tests run; 1 of no program)
## with no --since: the base is the nearest release-*, main or master
## branch's merge base with HEAD (here the one commit)
% volec check --changed 2>&1 | sed 's/since [0-9a-f]* /since COMMIT /'
ok: 0 errors in alone/one.vl (1 file, 0 shaders)
ok: 0 errors in main.vl (2 files, 1 shader)
ok: 0 errors in second/main.vl (1 file, 0 shaders)
ok: 3 programs checked, 1 changed .vl file formatted, since COMMIT (5 changed files; 1 under tests/, which their tests run; 1 of no program)
## a program broken on purpose says so in its root
% printf '// premerge: broken on purpose (the transcript)\nfn broken() -> i32 { nosuch }\n' >> second/main.vl
$ check --changed --since HEAD
ok: 0 errors in alone/one.vl (1 file, 0 shaders)
ok: 0 errors in main.vl (2 files, 1 shader)
ok: 2 programs checked, 1 changed .vl file formatted, since HEAD (6 changed files; 1 under tests/, which their tests run; 1 of no program; 1 program broken on purpose)
## the command line
$ check --changed main.vl
error check.usage: --changed finds the programs itself: no ROOT 'main.vl'
[exit 2]
$ check --since nosuchrev
error check.no-git: git cannot tell which files changed since nosuchrev: no checkout here, or no such revision
[exit 2]
$ explain check.changed
check.changed: error, exit 1
(0.29) `check --changed`: a program that a file changed since the base belongs to has errors (they are printed above, as `check ROOT` prints them), or a changed .vl file of such a program is not in the standard layout (`fmt --check` named it above). The line counts what was looked at: the changed files, the ones under tests/ (their tests run them) and the ones of no program.
fix: Fix the errors shown; `volec fmt FILE` for a file that is not formatted.
example:
    error check.changed: 1 of 2 programs has errors, since 1a2b3c4d5 (3 changed files)
