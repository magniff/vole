## 0.25.4: `volec run [DIR] [OPTIONS] [-- ARGS]` (cli/run.vl): DIR/main.vl
## built into volec's cache (never into DIR) when it changed, then run,
## with its stdin, stdout, stderr, arguments and exit status.
##
## No DIR: the current directory's main.vl. Off a terminal, only the
## program's own output (no `ok: built`).
$ run
hello from run254
## DIR, and the program's arguments after `--`: its exit status is
## volec's (this one's is the count of its arguments).
$ run . -- a b c
hello from run254
arg: a
arg: b
arg: c
[exit 3]
$ run -- --help --json
hello from run254
arg: --help
arg: --json
[exit 2]
## stdin is the program's.
$ run echo < notes.txt
stdin: notes
% echo piped | "$COMPILER" run echo
stdin: piped
## A signal ends it: 128 + N, as a shell says (SIGTERM: 143).
$ run signal
about to be terminated
[exit 143]
## A build's options: a C file of the link, -O0.
$ run c c/twice.c -O0
twice 21: 42
## A build error is the plain build's (status 1), and nothing runs.
$ run bad
bad/main.vl:2:18: error[type error] expected 'i32', got '[u8]'
[exit 1]
## Nothing was written into the program's folder; -o FILE keeps a copy.
% ls
bad
c
echo
lib
main.vl
notes.txt
signal
% "$COMPILER" run -o copy > /dev/null && ./copy x
hello from run254
arg: x
[exit 1]
## The second run builds nothing ($VOLE_CACHE_TRACE: `run fresh`); an
## edit builds again, and so does a newer C file of the link.
% VOLE_CACHE_TRACE=$PWD/trace "$COMPILER" run > /dev/null; cat trace
run fresh
% echo '// edited' >> main.vl; VOLE_CACHE_TRACE=$PWD/trace2 "$COMPILER" run > /dev/null; VOLE_CACHE_TRACE=$PWD/trace2 "$COMPILER" run > /dev/null; cat trace2
run build
run fresh
% VOLE_CACHE_TRACE=$PWD/trace3 "$COMPILER" run c c/twice.c -O0; touch c/twice.c; VOLE_CACHE_TRACE=$PWD/trace3 "$COMPILER" run c c/twice.c -O0; cat trace3
twice 21: 42
twice 21: 42
run fresh
run build
## On a terminal (--color=always here): the build's lines, then `Running
## NAME`; up to date, `Finished` alone.
% echo '// again' >> main.vl; "$COMPILER" --color=always run 2>&1 | cat -v | sed -e 's/in [0-9.]*s/in Ts/' -e 's/(-O2, [a-z0-9_-]*)/(-O2, TARGET)/'
    ^[[1;32mChecking^[[0m main.vl ... ^[[32mok^[[0m
   ^[[1;32mCompiling^[[0m main.vl (-O2, TARGET)
     ^[[1;32mLinking^[[0m run254
    ^[[1;32mFinished^[[0m run254 in Ts
     ^[[1;32mRunning^[[0m run254
hello from run254
% "$COMPILER" --color=always run 2>&1 | cat -v | sed 's/in [0-9.]*s/in Ts/'
    ^[[1;32mFinished^[[0m run254 in Ts
     ^[[1;32mRunning^[[0m run254
hello from run254
## run.no-main: a folder without main.vl, with the try: line when one of
## its folders has one or it holds one .vl file; a word that is no folder.
$ run lib
error run.no-main: 'lib' has no main.vl
help: `volec run DIR` builds and runs the program whose root is DIR/main.vl (DIR: the current directory when none is given)
try: volec lib/util.vl -o util && ./util
[exit 2]
% cd lib && "$COMPILER" run
error run.no-main: '.' has no main.vl
help: `volec run DIR` builds and runs the program whose root is DIR/main.vl (DIR: the current directory when none is given)
try: volec util.vl -o util && ./util
[exit 2]
% mkdir apps && cp -R echo apps/ && "$COMPILER" run apps
error run.no-main: 'apps' has no main.vl
help: `volec run DIR` builds and runs the program whose root is DIR/main.vl (DIR: the current directory when none is given)
try: volec run apps/echo
[exit 2]
$ run nosuch
error run.no-main: 'nosuch' is no folder
help: `volec run DIR` builds and runs the program whose root is DIR/main.vl (DIR: the current directory when none is given)
[exit 2]
## run.file: a file given for its folder.
$ run main.vl -- x
error run.file: 'main.vl' is a file: run takes the folder that holds main.vl
try: volec run -- x
[exit 2]
$ run main.vl a b
error run.file: 'main.vl' is a file: run takes the folder that holds main.vl
try: volec run -- a b
[exit 2]
$ run notes.txt
error run.file: 'notes.txt' is a file: run takes the folder that holds main.vl
try: volec run
[exit 2]
$ run lib/util.vl
error run.file: 'lib/util.vl' is a file: run takes the folder that holds main.vl
try: volec lib/util.vl -o util && ./util
[exit 2]
## run.args: a second folder, an argument without `--`.
$ run . echo
error run.args: 'echo' is a second folder, or the program's argument: run builds one program; its arguments go after --
try: volec run . -- echo
[exit 2]
## run.option: what makes no program to run here.
$ run -c
error run.option: -c makes no program to run
help: run builds a program for this machine and runs it; other outputs are a build's: `volec DIR/main.vl OPTIONS -o OUT`
[exit 2]
$ run --emit-ir
error run.option: --emit-ir makes no program to run
help: run builds a program for this machine and runs it; other outputs are a build's: `volec DIR/main.vl OPTIONS -o OUT`
[exit 2]
$ run --target x86_64-macos
error run.option: --target x86_64-macos: run runs the program here; a build makes it for another machine
help: run builds a program for this machine and runs it; other outputs are a build's: `volec DIR/main.vl OPTIONS -o OUT`
[exit 2]
## A build's own error for an option it cannot read.
$ run -O9
error: cannot read -O9
[exit 1]
## run's help; `exec` reads as run.
$ run --help
volec run [DIR] [OPTIONS] [-- ARGS...]   build DIR/main.vl (DIR: . when none), then run it
OPTIONS: a build's (-O0, -l NAME, -L DIR, x.c, x.o, -framework F, --check-alloc...; --target: the host's)
the program: stdin, stdout, stderr its own, ARGS its arguments, its exit status volec's (128+N: signal N)
kept in volec's cache (target/volec-cache, $VOLE_CACHE, else $TMPDIR/volec-cache: run/NAME-KEY/NAME), never in DIR;
built again only when a .vl file under DIR (or a C file, an object) changed; -o FILE: a copy at FILE too
on a terminal the build's lines, then `Running NAME`; elsewhere the program's output only
$ exec
error cli.not-a-command: 'exec' is not a volec command or a file; did you mean 'run'?
try: volec run
[exit 2]
