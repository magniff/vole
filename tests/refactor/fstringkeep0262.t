## 0.26.2: `fix --only fstring --keep-braces`: the f-strings as without it,
## the plain literals left as they are (rule 4 off: they are format
## strings already, `{n}` a hole, `{{` a brace); what it prints is the same.
% volec main.vl -o before >/dev/null && ./before 2>&1
42 {braces} 43
42 {x}
f 42 43 {y}
ok: built before
$ fix --only fstring --keep-braces
fixed 1 f-string or format literal	main.vl	+1 -1 lines
% cat main.vl
// `fix --only fstring --keep-braces` (tests/refactor/fstringkeep0262.t):
// code already read as 0.26.2 reads it.
fn main() {
    let n = 42;
    println("{n} {{braces}} {}", n + 1);
    println("{n} {{x}}");
    println("f {n} {} {{y}}", n + 1);
}
% volec main.vl -o after >/dev/null && ./after 2>&1
42 {braces} 43
42 {x}
f 42 43 {y}
ok: built after
