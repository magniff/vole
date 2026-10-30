## 0.26.2: format literals' errors (tests/refactor/format0262/): an
## expression in a hole is format.expr-hole, whose fix moves it to an
## argument; a brace of the text not doubled is format.syntax, whose fix
## doubles it; a spec that is not Rust's is format.spec; and their
## explanations, with format.args's.
$ check
main.vl:6:23: error[format.expr-hole] '{p.a}': a hole of a format string holds a name, not an expression | help: write '{}' and pass the expression after the format string, as Rust does: 'println("{} {x}", a.b)' | try: volec fix --suggested main.vl
main.vl:7:14: error[format.syntax] a hole of the format string is not closed: expected '}' | help: a '{' of the text is written '{{' | try: volec fix --suggested main.vl
main.vl:8:23: error[format.spec] invalid format spec ':q': unknown format trait 'q' | help: a spec is [[fill]align][+][#][0][width][.precision][type]: align < ^ >, width and precision N, N$ or name$ (precision also *), type ? x? X? x X o b e E p c: '{x:>8.2}', '{v:?}', '{n:#010x}', '{s:*^9}'
[exit 1]
$ fix --suggested --dry-run
--- a/main.vl
+++ b/main.vl
@@ -6,2 +6,2 @@
-    println("{x} and {p.a}");
-    println("{ text }");
+    println("{x} and {}", p.a);
+    println("{{ text }}");
$ explain format.syntax
format.syntax: error
(0.26.2) A format literal (a plain string literal that is the first argument of println, print, eprintln, eprint, format_in, format_args, push_fmt, Fmt::write, panic, the message of assert and debug_assert, or a contract's `else`) whose braces do not make holes: a `{` never closed, a `}` with no `{`. Its grammar is Rust's std::fmt: `{}`, `{0}`, `{name}`, each with an optional `:spec`, and `{{` and `}}` for a brace of the text. Before 0.26.2 a plain literal was printed as it is, braces and all (`warning[format]` said so).
fix: Double the braces of the text: `println("{{")` prints `{` (`volec fix --suggested` writes it; `volec fix --only fstring` doubles them in a whole program).
example:
    error[format.syntax] unmatched '}' in a format string | help: a '}' of the text is written '}}'
$ explain format.spec
format.spec: error
(0.26.2) A hole's spec, after its `:`, that is not Rust's: `[[fill]align][sign]['#']['0'][width]['.' precision][type]`, align `<` `^` `>`, sign `+`, width and precision an integer, `N$` or `name$` (precision also `*`), type `?` `x?` `X?` `x` `X` `o` `b` `e` `E` `p`, and vole's `c` (a u8 as its byte). `{:#?}`, Rust's Debug over several lines, is not in this release.
fix: Write the spec in Rust's order: `{x:>8.2}`, `{n:#010x}`, `{s:*^9}`, `{v:?}`; for `{:#?}`, `{:?}`.
example:
    error[format.spec] invalid format spec ':q': unknown format trait 'q' | help: a spec is [[fill]align][+][#][0][width][.precision][type]: align < ^ >, width and precision N, N$ or name$ (precision also *), type ? x? X? x X o b e E p c: '{x:>8.2}', '{v:?}', '{n:#010x}', '{s:*^9}'
$ explain format.args
format.args: error
(0.26.2) A format call's arguments do not match its literal's holes (Rust's "argument never used", "invalid reference"): an argument (positional or named, `name = expr`) that no hole takes, a hole (`{}`, `{N}`, `N$`, `.*`) with no argument for it; or arguments after a first argument that is not a literal (`println(s, x)`): a format string is a literal, a `const` or a variable is printed as a value.
fix: Give each hole its argument, after the literal and in order, or remove the argument; for a variable format, format the pieces apart (`print(s); println("{}", x)`) or build the value with `format_args("..", x)`.
example:
    error[format.args] this argument is never used: no hole of the format string takes it | help: write a hole for it, '{}', or remove it
$ explain format.expr-hole
format.expr-hole: error
(0.26.2) A hole of a format literal holding an expression, `{p.a}`, `{x + 1}`, `{v.len()}`: a hole names a local, a parameter, a `const` or a `static` (Rust 2021's inline captures), or takes the next argument. (An f-string's hole, `f"{p.a}"`, holds any expression, until f-strings go in 0.28.)
fix: Write `{}` and pass the expression after the literal: `println("{}", p.a)` (`volec fix --suggested` moves it).
example:
    error[format.expr-hole] '{p.a}': a hole of a format string holds a name, not an expression | help: write '{}' and pass the expression after the format string, as Rust does: 'println("{} {x}", a.b)'
