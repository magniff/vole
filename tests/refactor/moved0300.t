## 0.30: an error an edit only moves is not new. The program has a
## borrow error whose message names a place (`mutably borrowed at
## main.vl:11:10`); an edit above it moves both a line down. (0.29: `fix`
## was refused with `edit.breaks: 1 new error`, the program's old one,
## moved by the `use` line the fix added.)
$ check
main.vl:11:18: error[borrowck.mut_twice] cannot borrow 'n' as mutable more than once at a time (mutably borrowed at main.vl:11:10) | help: finish the first borrow's uses before the second, or reborrow once and pass it on
[exit 1]
$ edit patch main.vl:6 --old '' --new '// doubled'
patched crate::twice	main.vl	+1 -0 lines
$ check
main.vl:12:18: error[borrowck.mut_twice] cannot borrow 'n' as mutable more than once at a time (mutably borrowed at main.vl:12:10) | help: finish the first borrow's uses before the second, or reborrow once and pass it on
[exit 1]
## An error the edit adds is still new, the old one beside it or not.
$ edit patch twice --old 'x * 2' --new 'x * y'
main.vl:7:9: error[type error] undefined variable 'y'  [edited: crate::twice]
error edit.breaks: 1 new error; nothing written; the error: main.vl:7:9: undefined variable 'y'
note edit.together: several steps are one call, checked at its end: `edit patch NAME --old A --new B --old C --new D` (`--in OTHER` before another item's pairs), `edit apply FILE`; or this step alone with --no-check
try: volec edit patch twice --old 'x * 2' --new 'x * y' --no-check
[exit 1]
