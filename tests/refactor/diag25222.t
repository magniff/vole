## 0.25.2.2 diagnostics (eval 0.25.2.1: qwen35, deferred, terrain;
## tests/refactor/diag25222/). A module file checked alone, its root not
## yet naming it: the `unknown module` of its sibling says so, and the
## try: checks the root.
$ check tok.vl
tok.vl:1:5: error[type error] unknown module 'st' | help: tok.vl was checked as a program of its own (no `mod tok;` in main.vl names it), so st.vl beside it is not its module: a module is checked through its program's root, once the root has `mod tok;` | try: volec check main.vl
[exit 1]
## Once main.vl names it, checking the module checks its program.
% printf 'mod st;\nmod tok;\n\nfn main() {\n    let n = st::one() + tok::two();\n}\n' > main.vl
$ check tok.vl
ok: 0 errors in main.vl
## `volec test a.vl b.vl`: test takes the program's root, which pulls in
## the rest.
$ test main.vl tok.vl
error test.usage: one ROOT at most; a second 'tok.vl': test takes the program's root, whose `mod` lines pull in its other files and their #[test] fns
try: volec test main.vl
[exit 2]
