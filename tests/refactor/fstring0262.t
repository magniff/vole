## 0.26.2: `fix --only fstring` (tests/refactor/fstring0262/): an
## f-string at a format position loses its `f`, a name hole stays and the
## other holes' expressions become arguments in order (a Display impl's
## f.write, a contract's `else`, format_in before its allocator, a text
## block, a call in a generic function never instantiated); one anywhere
## else becomes format_args; 0.17's `b.push_str(f"..")` becomes push_fmt;
## a plain literal at a format position gets its braces doubled (it
## printed them before 0.26.2). The program prints what it printed but
## for that literal, which prints as 0.26.1 printed it.
% volec main.vl -o before >/dev/null && ./before 2>&1
n = 42,    42 2 lit {brace}
text 42 {
no holes
42-1
42 P(1, "x")
2a
[1]
block 42
and 1
1
ok: built before
$ fix --only fstring
fixed 13 f-strings and format literals	main.vl	+15 -15 lines
% cat main.vl
struct P { a: i64, b: [u8] }

impl Display for P {
    fn fmt(self, f: inout Fmt) {
        f.write("P({}, {:?})", self.a, self.b);
    }
}

fn first(v: [i64]) -> i64
    requires v.len() > 0 else "empty: {} items", v.len()
{
    v[0]
}

fn show<T: Display>(x: T) {
    println(x);
}

fn never<T: Display>(x: T) {
    println("never {x} {}", 1 + 1);
}

fn main(gpa: Gpa) {
    let n = 42;
    let p = P { a: 1, b: "x" };
    println("n = {n}, {n:>5} {} {} {{brace}}", p.a + 1, "lit");
    println("text {{n}} {{{{");
    print("no holes\n");
    let s = format_in("{n}-{}", p.a, gpa);
    eprintln("{}", s.as_slice());
    let line = format_args("{n} {p}");
    show(line);
    show(format_args("{n:x}"));
    var b = String::new_in(gpa);
    b.push_fmt("[{}]", p.a);
    println(b.as_str());
    println("""
        block {n}
        and {}
        """, p.a);
    println("{}", first([1]));
}
$ check
ok: 0 errors in main.vl
% volec main.vl -o after >/dev/null && ./after 2>&1
n = 42,    42 2 lit {brace}
text {n} {{
no holes
42-1
42 P(1, "x")
2a
[1]
block 42
and 1
1
ok: built after
