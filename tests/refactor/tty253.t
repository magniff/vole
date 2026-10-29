## 0.25.3: the compiler's output for a person at a terminal (base/term.vl),
## main.missing and the link's errors (back/objfile/linkfail.vl), and a
## first word that reads as a command (cli/hint.vl).
##
## Off a terminal nothing changes: a pipe and --color=never give the same
## text, the one-line form of 0.25.2.
$ bad.vl -o bad
bad.vl:2:18: error[type error] expected 'i32', got '[u8]'
bad.vl:3:13: error[type error] undefined variable 'undefined_name'
[exit 1]
$ --color=never bad.vl -o bad
bad.vl:2:18: error[type error] expected 'i32', got '[u8]'
bad.vl:3:13: error[type error] undefined variable 'undefined_name'
[exit 1]
## --color=always gives a terminal's form anywhere: the phases, each
## diagnostic with its source line and a caret, the summary, in colour
## (cat -v shows the escapes; the time and the target vary).
% "$COMPILER" --color=always bad.vl -o bad 2>&1 | cat -v | sed 's/in [0-9.]*s/in Ts/'
^[[1;31merror[type error]^[[0m^[[1m: expected 'i32', got '[u8]'^[[0m
 ^[[1;34m-->^[[0m bad.vl:2:18
  ^[[1;34m|^[[0m
^[[1;34m2 |^[[0m     let x: i32 = "a";
  ^[[1;34m|^[[0m                  ^[[1;31m^^^^[[0m
^[[1;31merror[type error]^[[0m^[[1m: undefined variable 'undefined_name'^[[0m
 ^[[1;34m-->^[[0m bad.vl:3:13
  ^[[1;34m|^[[0m
^[[1;34m3 |^[[0m     let y = undefined_name + 1;
  ^[[1;34m|^[[0m             ^[[1;31m^^^^^^^^^^^^^^^[[0m
    ^[[1;32mChecking^[[0m bad.vl ... ^[[31m2 errors^[[0m
      ^[[1;31mFailed^[[0m bad: 2 errors in Ts
% "$COMPILER" --color=always main.vl -o prog 2>&1 | cat -v | sed -e 's/in [0-9.]*s/in Ts/' -e 's/(-O2, [a-z0-9_-]*)/(-O2, TARGET)/'
    ^[[1;32mChecking^[[0m main.vl ... ^[[32mok^[[0m
    ^[[1;32mChecking^[[0m util.vl ... ^[[32mok^[[0m
   ^[[1;32mCompiling^[[0m main.vl (-O2, TARGET)
     ^[[1;32mLinking^[[0m prog
    ^[[1;32mFinished^[[0m prog in Ts
% "$COMPILER" --color=always check bad.vl 2>&1 | cat -v | sed 's/in [0-9.]*s/in Ts/'
^[[1;31merror[type error]^[[0m^[[1m: expected 'i32', got '[u8]'^[[0m
 ^[[1;34m-->^[[0m bad.vl:2:18
  ^[[1;34m|^[[0m
^[[1;34m2 |^[[0m     let x: i32 = "a";
  ^[[1;34m|^[[0m                  ^[[1;31m^^^^[[0m
^[[1;31merror[type error]^[[0m^[[1m: undefined variable 'undefined_name'^[[0m
 ^[[1;34m-->^[[0m bad.vl:3:13
  ^[[1;34m|^[[0m
^[[1;34m3 |^[[0m     let y = undefined_name + 1;
  ^[[1;34m|^[[0m             ^[[1;31m^^^^^^^^^^^^^^^[[0m
    ^[[1;32mChecking^[[0m bad.vl ... ^[[31m2 errors^[[0m
      ^[[1;31mFailed^[[0m bad.vl: 2 errors in Ts
% "$COMPILER" --color=always check main.vl 2>&1 | cat -v | sed 's/in [0-9.]*s/in Ts/'
    ^[[1;32mChecking^[[0m main.vl ... ^[[32mok^[[0m
    ^[[1;32mChecking^[[0m util.vl ... ^[[32mok^[[0m
    ^[[1;32mFinished^[[0m main.vl: 0 errors in Ts
$ --color=sometimes bad.vl -o bad
error: unknown option (expected --color=auto, always or never): --color=sometimes
[exit 1]
## On a terminal (a pseudo-terminal, script(1)): colour by default; none
## with NO_COLOR; --color=never is the terminal's form of 0.25.2.
% sh tty.sh "$COMPILER" bad.vl -o bad | cat -v | sed 's/in [0-9.]*s/in Ts/'
^[[1;31merror[type error]^[[0m^[[1m: expected 'i32', got '[u8]'^[[0m
 ^[[1;34m-->^[[0m bad.vl:2:18
  ^[[1;34m|^[[0m
^[[1;34m2 |^[[0m     let x: i32 = "a";
  ^[[1;34m|^[[0m                  ^[[1;31m^^^^[[0m
^[[1;31merror[type error]^[[0m^[[1m: undefined variable 'undefined_name'^[[0m
 ^[[1;34m-->^[[0m bad.vl:3:13
  ^[[1;34m|^[[0m
^[[1;34m3 |^[[0m     let y = undefined_name + 1;
  ^[[1;34m|^[[0m             ^[[1;31m^^^^^^^^^^^^^^^[[0m
    ^[[1;32mChecking^[[0m bad.vl ... ^[[31m2 errors^[[0m
      ^[[1;31mFailed^[[0m bad: 2 errors in Ts
% NO_COLOR=1 sh tty.sh "$COMPILER" bad.vl -o bad | sed 's/in [0-9.]*s/in Ts/'
error[type error]: expected 'i32', got '[u8]'
 --> bad.vl:2:18
  |
2 |     let x: i32 = "a";
  |                  ^^^
error[type error]: undefined variable 'undefined_name'
 --> bad.vl:3:13
  |
3 |     let y = undefined_name + 1;
  |             ^^^^^^^^^^^^^^
    Checking bad.vl ... 2 errors
      Failed bad: 2 errors in Ts
% sh tty.sh "$COMPILER" --color=never bad.vl -o bad
error[type error]: expected 'i32', got '[u8]'
 --> bad.vl: line 2, column 18
error[type error]: undefined variable 'undefined_name'
 --> bad.vl: line 3, column 13
## main.missing: a program without fn main, before any code is made.
$ nomain.vl -o nomain
nomain.vl:1:1: error[main.missing] 'nomain.vl' has no fn main | help: a program starts at its fn main, and this one has none; an object (-c) needs none | try: printf '\nfn main() -> i32 {\n    0\n}\n' >> nomain.vl | try: volec -c -o nomain.o nomain.vl
[exit 1]
$ --diagnostics=human nomain.vl -o nomain
error[main.missing]: 'nomain.vl' has no fn main
 --> nomain.vl: line 1, column 1
  = help: a program starts at its fn main, and this one has none; an object (-c) needs none
  = try: printf '\nfn main() -> i32 {\n    0\n}\n' >> nomain.vl
  = try: volec -c -o nomain.o nomain.vl
[exit 1]
## With a C file that might define main, the link says it, as main.missing.
$ nomain.vl helper.c -o nomain
error[main.missing] 'nomain.vl' has no fn main | help: a program starts at its fn main, and this one has none; an object (-c) needs none | try: printf '\nfn main() -> i32 {\n    0\n}\n' >> nomain.vl | try: volec -c -o nomain.o nomain.vl
[exit 1]
## The link's errors, one vole error each, none of the linker's text:
## symbols nothing defines (at the declaration of the first),
$ undef.vl -o undef
undef.vl:2:5: error[link.undefined] undefined symbol 'vole_tty253_missing', and 1 more: 'vole_tty253_missing_too' | help: 'vole_tty253_missing' is declared in an extern block, and nothing the link is given defines it: name its library, #[link(lib = "NAME")] on the block or -l NAME on the command line (--verbose: the linker's text)
[exit 1]
## a library -l or #[link] names that is not there,
$ main.vl -o prog -l vole_tty253_nolib
error[link.no-library] library 'vole_tty253_nolib' not found | help: -l vole_tty253_nolib on the command line names it; the linker looked in its directories and the -L ones and found none: install it, or give the directory that has it with -L DIR
[exit 1]
$ linked.vl -o linked
linked.vl:3:5: error[link.no-library] library 'vole_tty253_nolib' not found | help: the #[link] of the extern block names it; the linker looked in its directories and the -L ones and found none: install it, or give the directory that has it with -L DIR
[exit 1]
## a symbol defined twice, a C file that does not compile,
$ main.vl dup.c -o prog
error[link.duplicate] symbol 'main' is defined more than once | help: the program's fn main and a C file, an object or a library of the command line both define main: keep one (--verbose: the linker's text)
[exit 1]
% "$COMPILER" main.vl broken.c -o prog 2>&1 | sed 's/ | cc: broken\.c:2:[0-9]*: error: .*/ | cc: broken.c:2: error: .../'
error[link.c-file] the C file 'broken.c' does not compile | help: the C files of the command line are compiled for the link; the C compiler's errors follow | cc: broken.c:2: error: ...
## an input of the link that is not there, a C compiler that is not.
$ main.vl nothere.o -o prog
error[link.no-input] cannot read 'nothere.o', an input of the link | help: the objects (.o), archives (.a), shared libraries (.so, .dylib) and C files (.c) of the command line go to the link: check the path
[exit 1]
% VOLE_CC=vole-tty253-no-cc "$COMPILER" main.vl -o prog
error[link.no-linker] cannot run 'vole-tty253-no-cc', the C compiler that links the program | help: $VOLE_CC names it: set it to a C compiler, or unset it
[exit 1]
## Any other failure: the linker's lines under one error.
% VOLE_CC=./fakecc "$COMPILER" main.vl -o prog
error[link.failed] the link failed (./fakecc exited with status 3) | help: the linker's text follows (--verbose: its command too) | linker: fakecc: the weather is wrong for linking | linker: fakecc: try again tomorrow
[exit 1]
## --verbose adds the link's command and the linker's whole text.
% "$COMPILER" --verbose undef.vl -o undef 2>&1 | grep -c '^note: the link: '
1
## A first word that is no file and reads as a command.
$ build main.vl -o x
error cli.not-a-command: 'build' is not a volec command or a file: a build names its files, with no command word
try: volec main.vl -o x
[exit 2]
$ build main.vl
error cli.not-a-command: 'build' is not a volec command or a file: a build names its files, with no command word
try: volec main.vl -o main
[exit 2]
$ compile
error cli.not-a-command: 'compile' is not a volec command or a file: a build names its files, with no command word
try: volec main.vl -o main
[exit 2]
## (0.25.4: run is a command, run.file: tests/refactor/run254.t)
$ run main.vl -O0 one two
error run.file: 'main.vl' is a file: run takes the folder that holds main.vl
try: volec run -O0 -- one two
[exit 2]
$ chek main.vl
error cli.not-a-command: 'chek' is not a volec command or a file; did you mean 'check'?
try: volec check main.vl
[exit 2]
$ version
error cli.not-a-command: 'version' is not a volec command or a file
try: volec --version
[exit 2]
$ frob main.vl
error cli.not-a-command: 'frob' is not a volec command or a file
try: volec --help
[exit 2]
