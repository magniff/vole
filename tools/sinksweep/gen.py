#!/usr/bin/env python3
# Generates tests/run/own_assign_temp_sweep_{sink,inout,let,generic}.vl
# (0.25.2): a call whose argument holds an owned temporary lent to a let
# parameter (`size(leaf_of(gpa))`, a String, a nested call, an f-string, a
# closure, a struct literal, a receiver), with a receiver taken as `sink
# self`, `inout self` or `self` (method, free function, `Type::m(t, ..)`),
# in a reassignment `t = t.m(..)`, a `let`, an assignment to another
# place, a chain, a field, an element, a block's tail; and generic
# receivers. The bug it guards: `t = t.add(size(leaf_of(gpa)))` read
# garbage, the checker's lend of the temporary hoisted a second time when
# the assignment's desugaring was checked (check/temps.vl). Each case
# prints the result's sum and length (computed here); --check-alloc finds
# no leak, double free or use after free. tests/run.sh runs them at -O2
# (and -O0 with `-O 0`).
#
#   python3 tools/sinksweep/gen.py tests/run
#   target/volec fmt tests/run/own_assign_temp_sweep_*.vl
import sys

OUT = sys.argv[1]

PRELUDE = """\
struct Leaf { opts: Vec<i64> }

impl Leaf {
    fn count(self) -> i64 { self.opts.len() as i64 }
}

struct Tree { sizes: Vec<i64> }

impl Tree {
    fn add_s(sink self, n: i64) -> Tree { self.sizes.push(n); self }
    fn add_i(inout self, n: i64) -> Tree { self.sizes.push(n); Tree { sizes: self.sizes.clone() } }
    fn add_l(self, n: i64) -> Tree { var v = self.sizes.clone(); v.push(n); Tree { sizes: v } }
    fn sum(self) -> i64 {
        var s = 0;
        var i = 0;
        while i < self.sizes.len() as i64 { s += self.sizes[i]; i += 1; }
        s
    }
    fn show(self) { println(f"{self.sum()} {self.sizes.len()}"); }
}

struct Holder { t: Tree, tag: i64 }

fn fadd_s(t: sink Tree, n: i64) -> Tree { t.sizes.push(n); t }
fn fadd_i(t: inout Tree, n: i64) -> Tree { t.sizes.push(n); Tree { sizes: t.sizes.clone() } }
fn fadd_l(t: Tree, n: i64) -> Tree { var v = t.sizes.clone(); v.push(n); Tree { sizes: v } }

fn vec_of(gpa: Gpa, k: i64) -> Vec<i64> {
    var v: Vec<i64> = Vec::new_in(gpa);
    for i in 0..k { v.push(i); }
    v
}
fn leaf_of(gpa: Gpa, k: i64) -> Leaf { Leaf { opts: vec_of(gpa, k) } }
fn size(leaf: Leaf) -> i64 { leaf.opts.len() as i64 }
fn grow(l: Leaf, gpa: Gpa) -> Leaf { var v = l.opts.clone(); v.push(9); Leaf { opts: v } }
fn name_of(gpa: Gpa, k: i64) -> String {
    var s = String::new_in(gpa);
    for _ in 0..k { s.push_str("x"); }
    s
}
fn slen(s: String) -> i64 { s.len() as i64 }
fn glen<T>(v: Vec<T>) -> i64 { v.len() as i64 }
fn apply<F: Fn(i64) -> i64>(f: F, x: i64) -> i64 { f(x) }
fn tree_of(gpa: Gpa) -> Tree { Tree { sizes: vec_of(gpa, 1) } }
"""

# (text, value) of an argument holding owned temporaries; B: a second one
ARGS = [
    ("size(leaf_of(gpa, 1))", 1),
    ("slen(name_of(gpa, 3))", 3),
    ("size(grow(leaf_of(gpa, 2), gpa))", 3),
    ("size(leaf_of(gpa, 1)) + slen(name_of(gpa, 2))", 3),
    ("leaf_of(gpa, 4).count()", 4),
    ("glen(vec_of(gpa, 5))", 5),
    ('slen(to_string_in(f"ab{size(leaf_of(gpa, 2))}", gpa))', 3),
    ("apply(|x: i64| x + size(leaf_of(gpa, 2)), 4)", 6),
    ("Leaf { opts: vec_of(gpa, 2) }.count()", 2),
    ("slen(name_of(gpa, size(leaf_of(gpa, 2))))", 2),
    ("glen(vec_of(gpa, size(leaf_of(gpa, 3))))", 3),
]
B = ("size(leaf_of(gpa, 7))", 7)

# a receiver form: (name, call template over T (the receiver) and A)
RECV = {
    "sink": [("m", "{t}.add_s({a})"), ("f", "fadd_s({t}, {a})"), ("u", "Tree::add_s({t}, {a})")],
    "inout": [("m", "{t}.add_i({a})"), ("f", "fadd_i(&{t}, {a})")],
    "let": [("m", "{t}.add_l({a})"), ("f", "fadd_l({t}, {a})"), ("u", "Tree::add_l({t}, {a})")],
}

# tree_of: sizes [0] (sum 0, length 1)
def result(vals):
    return f"{sum(vals)} {1 + len(vals)}"


def stmts(mode, call):
    """(name, body, expected lines) of each statement form."""
    c = lambda t, a: call.format(t=t, a=a)
    out = []
    for ai, (a, av) in enumerate(ARGS):
        # t = t.m(A)
        out.append((f"re{ai}", f"var t = tree_of(gpa);\nt = {c('t', a)};\nt.show();",
                    [result([av])]))
        # let u = t.m(A)
        body = f"var t = tree_of(gpa);\nlet u = {c('t', a)};\nu.show();"
        exp = [result([av])]
        if mode != "sink":
            body += "\nt.show();"
            exp.append(result([av]) if mode == "inout" else result([]))
        out.append((f"let{ai}", body, exp))
        # u = t.m(A), u an owned place with a value to drop
        body = f"var t = tree_of(gpa);\nvar u = tree_of(gpa);\nu.show();\nu = {c('t', a)};\nu.show();"
        exp = [result([]), result([av])]
        out.append((f"other{ai}", body, exp))
        # h.t = h.t.m(A)
        if mode != "sink":
            body = (f"var h = Holder {{ t: tree_of(gpa), tag: 5 }};\nh.t = {c('h.t', a)};\n"
                    f"h.t.show();\nprintln(f\"{{h.tag}}\");")
            out.append((f"field{ai}", body, [result([av]), "5"]))
        # ts[0] = ts[0].m(A)
        if mode != "sink":
            body = (f"var ts: Vec<Tree> = Vec::new_in(gpa);\nts.push(tree_of(gpa));\n"
                    f"ts.push(tree_of(gpa));\nts[1] = {c('ts[1]', a)};\nts[1].show();\nts[0].show();")
            out.append((f"elem{ai}", body, [result([av]), result([])]))
        # a block's tail: `if k > 0 { t = t.m(A) }`
        body = f"var t = tree_of(gpa);\nlet k = 1;\nif k > 0 {{\n    t = {c('t', a)}\n}}\nt.show();"
        out.append((f"tail{ai}", body, [result([av])]))
        # t = t.m(A).m(B), t = t.m(B).m(A): a chain
        if mode != "inout":
            inner = c("t", a)
            body = f"var t = tree_of(gpa);\nt = {c(inner, B[0])};\nt.show();"
            out.append((f"chain{ai}", body, [result([av, B[1]])]))
            inner = c("t", B[0])
            body = f"var t = tree_of(gpa);\nt = {c(inner, a)};\nt.show();"
            out.append((f"chainb{ai}", body, [result([B[1], av])]))
    return out


def emit(path, header, items, cases):
    lines = [header, "// FLAGS: --check-alloc"]
    for _, _, exp in cases:
        for e in exp:
            lines.append(f"// EXPECT: {e}")
    src = "\n".join(lines) + "\n\n" + PRELUDE + items
    calls = []
    for name, body, _ in cases:
        ind = "\n".join("    " + l for l in body.split("\n"))
        src += f"\nfn case_{name}(gpa: Gpa) {{\n{ind}\n}}\n"
        calls.append(f"    case_{name}(gpa);")
    src += "\nfn main(gpa: Gpa) -> i32 {\n" + "\n".join(calls) + "\n    0\n}\n"
    with open(path, "w") as f:
        f.write(src)


HEAD = ("// Generated by tools/sinksweep/gen.py (0.25.2): owned temporaries in the\n"
        "// arguments of a call taking a receiver {what}, in an assignment's right\n"
        "// side, a let, a chain, a field, an element, a block's tail.")

for mode in ("sink", "inout", "let"):
    cases = []
    for rname, call in RECV[mode]:
        for name, body, exp in stmts(mode, call):
            cases.append((f"{rname}_{name}", body, exp))
    emit(f"{OUT}/own_assign_temp_sweep_{mode}.vl",
         HEAD.format(what={"sink": "by `sink self`", "inout": "by `inout self`",
                           "let": "by `self` (let)"}[mode]), "", cases)

# generic receivers: Bag<T>, the argument the value moved in or lent
GEN_ITEMS = """
struct Bag<T> { items: Vec<T>, n: i64 }

impl<T> Bag<T> {
    fn put_s(sink self, x: sink T, w: i64) -> Bag<T> { self.items.push(x); self.n += w; self }
    fn put_i(inout self, x: sink T, w: i64) -> i64 { self.items.push(x); self.n += w; self.n }
    fn show(self) { println(f"{self.items.len()} {self.n}"); }
}

fn bag_put<T>(b: sink Bag<T>, x: sink T, w: i64) -> Bag<T> { b.items.push(x); b.n += w; b }
"""
GEN = [
    ("Vec::<i64>::new_in(gpa)", "size(leaf_of(gpa, 2))", "size(leaf_of(gpa, 3))", 0),
    ("Vec::<String>::new_in(gpa)", "name_of(gpa, 2)", "slen(name_of(gpa, 3))", 0),
    ("Vec::<Leaf>::new_in(gpa)", "grow(leaf_of(gpa, 1), gpa)", "leaf_of(gpa, 3).count()", 0),
    ("Vec::<String>::new_in(gpa)", 'to_string_in(f"{size(leaf_of(gpa, 2))}", gpa)',
     "apply(|x: i64| x + slen(name_of(gpa, 1)), 2)", 0),
]
gcases = []
for gi, (new, x, w, _) in enumerate(GEN):
    wv = eval_w = None
    # w's value: the arguments above
    wv = {"size(leaf_of(gpa, 3))": 3, "slen(name_of(gpa, 3))": 3,
          "leaf_of(gpa, 3).count()": 3, "apply(|x: i64| x + slen(name_of(gpa, 1)), 2)": 3}[w]
    mk = f"var b = Bag {{ items: {new}, n: 0 }};"
    gcases.append((f"re{gi}", f"{mk}\nb = b.put_s({x}, {w});\nb.show();", [f"1 {wv}"]))
    gcases.append((f"fn{gi}", f"{mk}\nb = bag_put(b, {x}, {w});\nb.show();", [f"1 {wv}"]))
    gcases.append((f"chain{gi}", f"{mk}\nb = b.put_s({x}, {w}).put_s({x}, size(leaf_of(gpa, 1)));\nb.show();",
                   [f"2 {wv + 1}"]))
    gcases.append((f"let{gi}", f"{mk}\nlet c = b.put_s({x}, {w});\nc.show();", [f"1 {wv}"]))
    gcases.append((f"io{gi}", f"{mk}\nlet k = b.put_i({x}, {w});\nprintln(f\"{{k}}\");\nb.show();",
                   [f"{wv}", f"1 {wv}"]))
    gcases.append((f"other{gi}", f"{mk}\nvar c = Bag {{ items: {new}, n: 9 }};\nc = b.put_s({x}, {w});\nc.show();",
                   [f"1 {wv}"]))
emit(f"{OUT}/own_assign_temp_sweep_generic.vl",
     HEAD.format(what="of a generic type (`Bag<T>`, T an i64, a String, a Leaf)"),
     GEN_ITEMS, gcases)
