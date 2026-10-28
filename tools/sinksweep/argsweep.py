#!/usr/bin/env python3
# Generates tests/run/own_arg_temp_sweep_{let,sink,inout,view}{,_req}.vl
# (0.25.2.1; 0.25.2.2: _req, the callees have a requires clause, whose
# call is a block binding the arguments first,
# `dev.compute_pipeline(dev.shader_wgsl(SRC)?, "e")?`; view, the argument
# in a struct with a let field, made by a function or a literal):
# an owned argument whose expression may leave the function (`make()?`, a
# `match` or `if let` with an arm that returns, an `if` with a branch that
# returns, nested calls) given to a parameter taken `let`, `sink`, or `let`
# after an `inout` one, by a method, a free function or `Dev::f(dev, ..)`,
# in a call whose result is `?`'d, `let`, returned, a block's tail, or a
# `match` scrutinee; the value a struct holding a Vec or a String, and the
# second argument a constant or a `?` that may leave too. The bugs it
# guards: `dev.count(dev.make(7)?, 8)?` lent the argument by the address
# of a value nothing kept (its `?`'s `?v`, dropped before the call; a
# temporary of a plain call leaked) when the call's own result was `?`'d,
# and `count(match make() { Ok(s) => s, Err(e) => return Err(e) }, 8)`
# lent the arm's binding `s`, dropped with its arm, and `f(loc, g()?)`
# with loc taken sink leaked loc when g failed (front/own/drops.vl
# visit_temps, lend_branches, moved_local). Each case prints its result (computed
# here); --check-alloc finds no leak, double free or use after free.
#
#   python3 tools/sinksweep/argsweep.py tests/run         (writes the tests)
#   python3 tools/sinksweep/argsweep.py --one DIR         (one program per
#       case in DIR, with DIR/expected.txt: for bisecting)
import os
import sys

PRELUDE = """\
struct Sh { names: Vec<i64> }

struct Dev { gpa: Gpa, on: bool }

fn sh_of(gpa: Gpa, n: i64, k: i64) -> Sh {
    var v: Vec<i64> = Vec::new_in(gpa);
    for i in 0..k { v.push(n + i); }
    Sh { names: v }
}
fn str_of(gpa: Gpa, n: i64) -> String {
    var s = String::new_in(gpa);
    for _ in 0..n { s.push_str("x"); }
    s
}
fn dig(s: Sh) -> i64 { s.names.len() * 100 + s.names[s.names.len() - 1] }
fn digs(s: String) -> i64 { s.len() as i64 }

impl Dev {
    fn make(self, n: i64) -> Result<Sh, i64> {
        if n < 0 { return Err(n); }
        Ok(sh_of(self.gpa, n, 2))
    }
    fn makes(self, n: i64) -> Result<String, i64> {
        if n < 0 { return Err(n); }
        Ok(str_of(self.gpa, n))
    }
    fn opt(self, n: i64) -> Option<Sh> { if n < 0 { None } else { Some(sh_of(self.gpa, n, 2)) } }
    fn opts(self, n: i64) -> Option<String> { if n < 0 { None } else { Some(str_of(self.gpa, n)) } }
    fn mk(self, n: i64) -> Sh { sh_of(self.gpa, n, 2) }
    fn mks(self, n: i64) -> String { str_of(self.gpa, n) }
    fn num(self, n: i64) -> Result<i64, i64> { if n < 0 { Err(n) } else { Ok(n) } }
    // (nested: a value made from the argument, taken let or sink)
    fn grow(self, s: Sh) -> Result<Sh, i64> {
        var v = s.names.clone();
        v.push(s.names[s.names.len() - 1] + 1);
        Ok(Sh { names: v })
    }
    fn grows(self, s: String) -> Result<String, i64> {
        var t = s.clone();
        t.push_str("y");
        Ok(t)
    }
    fn grow_k(self, s: sink Sh) -> Result<Sh, i64> {
        s.names.push(s.names[s.names.len() - 1] + 1);
        Ok(s)
    }
    fn grows_k(self, s: sink String) -> Result<String, i64> {
        s.push_str("y");
        Ok(s)
    }
    fn c_let(self, s: Sh, w: i64) -> Result<i64, i64> { Ok(dig(s) + w) }
    fn cs_let(self, s: String, w: i64) -> Result<i64, i64> { Ok(digs(s) + w) }
    fn c_sink(self, s: sink Sh, w: i64) -> Result<i64, i64> { Ok(dig(s) + w) }
    fn cs_sink(self, s: sink String, w: i64) -> Result<i64, i64> { Ok(digs(s) + w) }
    fn c_inout(self, acc: inout Sh, s: Sh, w: i64) -> Result<i64, i64> {
        acc.names.push(w);
        Ok(dig(s) + w)
    }
    fn cs_inout(self, acc: inout Sh, s: String, w: i64) -> Result<i64, i64> {
        acc.names.push(w);
        Ok(digs(s) + w)
    }
}

fn f_c_let(s: Sh, w: i64) -> Result<i64, i64> { Ok(dig(s) + w) }
fn f_cs_let(s: String, w: i64) -> Result<i64, i64> { Ok(digs(s) + w) }
fn f_c_sink(s: sink Sh, w: i64) -> Result<i64, i64> { Ok(dig(s) + w) }
fn f_cs_sink(s: sink String, w: i64) -> Result<i64, i64> { Ok(digs(s) + w) }
fn f_c_inout(acc: inout Sh, s: Sh, w: i64) -> Result<i64, i64> {
    acc.names.push(w);
    Ok(dig(s) + w)
}
fn f_cs_inout(acc: inout Sh, s: String, w: i64) -> Result<i64, i64> {
    acc.names.push(w);
    Ok(digs(s) + w)
}

// (0.25.2.2) the same with a requires clause: a call of one is a block
// that binds the arguments first (contracts::desugar::requires_call)
impl Dev {
    fn grow_r(self, s: Sh) -> Result<Sh, i64> requires s.names.len() > 0 else "empty" {
        var v = s.names.clone();
        v.push(s.names[s.names.len() - 1] + 1);
        Ok(Sh { names: v })
    }
    fn grows_r(self, s: String) -> Result<String, i64> requires s.len() >= 0 else "len" {
        var t = s.clone();
        t.push_str("y");
        Ok(t)
    }
    fn grow_k_r(self, s: sink Sh) -> Result<Sh, i64> requires self.on else "off" {
        s.names.push(s.names[s.names.len() - 1] + 1);
        Ok(s)
    }
    fn grows_k_r(self, s: sink String) -> Result<String, i64> requires self.on else "off" {
        s.push_str("y");
        Ok(s)
    }
    fn c_let_r(self, s: Sh, w: i64) -> Result<i64, i64> requires self.on else "off" {
        Ok(dig(s) + w)
    }
    fn cs_let_r(self, s: String, w: i64) -> Result<i64, i64> requires self.on else "off" {
        Ok(digs(s) + w)
    }
    fn c_sink_r(self, s: sink Sh, w: i64) -> Result<i64, i64> requires self.on else "off" {
        Ok(dig(s) + w)
    }
    fn cs_sink_r(self, s: sink String, w: i64) -> Result<i64, i64> requires self.on else "off" {
        Ok(digs(s) + w)
    }
    fn c_inout_r(self, acc: inout Sh, s: Sh, w: i64) -> Result<i64, i64>
        requires self.on else "off" {
        acc.names.push(w);
        Ok(dig(s) + w)
    }
    fn cs_inout_r(self, acc: inout Sh, s: String, w: i64) -> Result<i64, i64>
        requires self.on else "off" {
        acc.names.push(w);
        Ok(digs(s) + w)
    }
}

// (0.25.2.2) a view of the argument, made by a function (as
// gpu::RenderDesc::new) or written as a struct literal with a let field
struct Desc { s: let Sh, n: i64 }
struct DescS { s: let String, n: i64 }
fn desc_of(s: Sh, n: i64) -> Desc { Desc { s: s, n: n } }
fn descs_of(s: String, n: i64) -> DescS { DescS { s: s, n: n } }
impl Dev {
    fn c_view(self, d: Desc, w: i64) -> Result<i64, i64> { Ok(dig(d.s) + d.n + w) }
    fn cs_view(self, d: DescS, w: i64) -> Result<i64, i64> { Ok(digs(d.s) + d.n + w) }
    fn c_view_r(self, d: Desc, w: i64) -> Result<i64, i64> requires d.n >= 0 else "n" {
        Ok(dig(d.s) + d.n + w)
    }
    fn cs_view_r(self, d: DescS, w: i64) -> Result<i64, i64> requires d.n >= 0 else "n" {
        Ok(digs(d.s) + d.n + w)
    }
}
fn f_c_view(d: Desc, w: i64) -> Result<i64, i64> { Ok(dig(d.s) + d.n + w) }
fn f_cs_view(d: DescS, w: i64) -> Result<i64, i64> { Ok(digs(d.s) + d.n + w) }
fn f_c_view_r(d: Desc, w: i64) -> Result<i64, i64> requires w >= 0 else "w" { Ok(dig(d.s) + d.n + w) }
fn f_cs_view_r(d: DescS, w: i64) -> Result<i64, i64> requires w >= 0 else "w" {
    Ok(digs(d.s) + d.n + w)
}

fn f_c_let_r(s: Sh, w: i64) -> Result<i64, i64> requires w >= 0 else "w" { Ok(dig(s) + w) }
fn f_cs_let_r(s: String, w: i64) -> Result<i64, i64> requires w >= 0 else "w" { Ok(digs(s) + w) }
fn f_c_sink_r(s: sink Sh, w: i64) -> Result<i64, i64> requires w >= 0 else "w" { Ok(dig(s) + w) }
fn f_cs_sink_r(s: sink String, w: i64) -> Result<i64, i64> requires w >= 0 else "w" {
    Ok(digs(s) + w)
}
fn f_c_inout_r(acc: inout Sh, s: Sh, w: i64) -> Result<i64, i64> requires w >= 0 else "w" {
    acc.names.push(w);
    Ok(dig(s) + w)
}
fn f_cs_inout_r(acc: inout Sh, s: String, w: i64) -> Result<i64, i64> requires w >= 0 else "w" {
    acc.names.push(w);
    Ok(digs(s) + w)
}
"""

# The value types: (key, its functions' suffix, model of a made value)
# A value is modelled as its digest: Sh [n, n+1] is 200 + n + 1; a String
# of n x's is n; grow adds an element (one more, the last plus one) or a "y".
TYPES = {
    "sh": dict(desc="Desc", desc_of="desc_of", make="make", opt="opt", mk="mk", grow="grow", grow_k="grow_k", c="c",
               val=lambda n: (2, n + 1), dig=lambda v: v[0] * 100 + v[1],
               grown=lambda v: (v[0] + 1, v[1] + 1)),
    "str": dict(desc="DescS", desc_of="descs_of", make="makes", opt="opts", mk="mks", grow="grows", grow_k="grows_k", c="cs",
                val=lambda n: n, dig=lambda v: v, grown=lambda v: v + 1),
}

# Argument forms: (name, template, outcome). Templates use {make} {opt}
# {mk} {grow} {grow_k} of the type; the outcome is ("ok", n, grows) or
# ("err", code). `k` is a local 1.
ARGS = [
    ("q", "dev.{make}(7)?", ("ok", 7, 0)),
    ("qerr", "dev.{make}(-1)?", ("err", -1)),
    ("qopt", "dev.{opt}(5).ok_or(-4)?", ("ok", 5, 0)),
    ("match", "match dev.{make}(7) {{ Ok(s) => s, Err(e) => return Err(e) }}", ("ok", 7, 0)),
    ("matcherr", "match dev.{make}(-1) {{ Ok(s) => s, Err(e) => return Err(e) }}", ("err", -1)),
    ("matchrev", "match dev.{make}(6) {{ Err(e) => return Err(e), Ok(s) => s }}", ("ok", 6, 0)),
    ("matchblk", "match dev.{make}(7) {{ Ok(s) => {{ let r = s; r }}, Err(e) => return Err(e) }}",
     ("ok", 7, 0)),
    ("matchopt", "match dev.{opt}(4) {{ Some(s) => s, None => return Err(-4) }}", ("ok", 4, 0)),
    ("matchnone", "match dev.{opt}(-1) {{ Some(s) => s, None => return Err(-4) }}", ("err", -4)),
    ("iflet", "if let Ok(s) = dev.{make}(3) {{ s }} else {{ return Err(-3) }}", ("ok", 3, 0)),
    ("ifleterr", "if let Ok(s) = dev.{make}(-1) {{ s }} else {{ return Err(-3) }}", ("err", -3)),
    ("ifq", "if k > 0 {{ dev.{make}(7)? }} else {{ return Err(-3) }}", ("ok", 7, 0)),
    ("ifmk", "if k > 0 {{ dev.{mk}(7) }} else {{ return Err(-3) }}", ("ok", 7, 0)),
    ("ifret", "if k < 0 {{ return Err(-3) }} else {{ dev.{mk}(8) }}", ("ok", 8, 0)),
    ("nest", "dev.{grow}(dev.{make}(7)?)?", ("ok", 7, 1)),
    ("nestk", "dev.{grow_k}(dev.{make}(7)?)?", ("ok", 7, 1)),
    ("nest2", "dev.{grow}(dev.{grow_k}(dev.{make}(2)?)?)?", ("ok", 2, 2)),
    ("nestmatch", "dev.{grow}(match dev.{make}(7) {{ Ok(s) => s, Err(e) => return Err(e) }})?",
     ("ok", 7, 1)),
    ("nesterr", "dev.{grow}(dev.{make}(-1)?)?", ("err", -1)),
    ("unwrap", "dev.{make}(7).unwrap()", ("ok", 7, 0)),
    ("plain", "dev.{mk}(9)", ("ok", 9, 0)),
    # (a local, moved to a sink parameter before a second argument that
    # leaves: held, and dropped when it does)
    ("local", "loc", ("ok", 7, 0)),
]

# Forms a let parameter rejects (a branch's value that is a new value, lent
# there: `error: expected 'let Sh', got 'Sh' .. name it first`), checked
# by the --one run; sound, and outside this sweep.
LET_REJECTS = {"ifmk", "ifret"}
# (and in a let field of a struct literal, a call's value)
LIT_REJECTS = {"unwrap", "plain"}

# The second argument: (name, text, outcome: value or ("err", code))
WS = [("w", "8", 8), ("wq", "dev.num(8)?", 8), ("wl", "dev.num(-2)?", ("err", -2))]

# Callee forms per convention: template over {c} (c or cs), A, W
CALLEES = {
    "let": [("m", "dev.{c}_let{r}({a}, {w})"), ("f", "f_{c}_let{r}({a}, {w})"),
            ("u", "Dev::{c}_let{r}(dev, {a}, {w})")],
    "sink": [("m", "dev.{c}_sink{r}({a}, {w})"), ("f", "f_{c}_sink{r}({a}, {w})"),
             ("u", "Dev::{c}_sink{r}(dev, {a}, {w})")],
    # (0.25.2.2: the argument in a view, by a function (f) or a literal (l))
    "view": [("mf", "dev.{c}_view{r}({desc_of}({a}, 0), {w})"),
             ("ml", "dev.{c}_view{r}({desc} {{ s: {a}, n: 0 }}, {w})"),
             ("ff", "f_{c}_view{r}({desc_of}({a}, 0), {w})"),
             ("fl", "f_{c}_view{r}({desc} {{ s: {a}, n: 0 }}, {w})"),
             ("ul", "Dev::{c}_view{r}(dev, {desc} {{ s: {a}, n: 0 }}, {w})")],
    "inout": [("m", "dev.{c}_inout{r}(&acc, {a}, {w})"), ("f", "f_{c}_inout{r}(&acc, {a}, {w})"),
              ("u", "Dev::{c}_inout{r}(dev, &acc, {a}, {w})")],
}

# Outer forms: (name, body over C, the call). Each case returns
# Result<i64, i64>.
OUTER = [
    ("q", "let a = {C}?;\nOk(a)"),
    ("noq", "let r = {C};\nmatch r {{\n    Ok(v) => Ok(v),\n    Err(e) => Err(e),\n}}"),
    ("ret", "return Ok({C}?);"),
    ("tail", "{C}"),
    ("scrq", "match {C}? {{\n    v => Ok(v),\n}}"),
    ("scr", "match {C} {{\n    Ok(v) => Ok(v),\n    Err(e) => Err(-100 + e),\n}}"),
    ("bin", "Ok({C}? + 0)"),
]


def outcome(ty, arg, w, outer):
    o = arg[2]
    if o[0] == "err":
        return f"err {o[1]}"
    if isinstance(w[2], tuple):
        # (the argument first, then the second one leaves)
        return f"err {w[2][1]}"
    t = TYPES[ty]
    v = t["val"](o[1])
    for _ in range(o[2]):
        v = t["grown"](v)
    return f"ok {t['dig'](v) + w[2]}"


def cases(conv, req=False):
    """The cases of a convention; req: the callees (the outer call's and
    the nested ones) have a requires clause (0.25.2.2)."""
    out = []
    r = "_r" if req else ""
    for ty in ("sh", "str"):
        t = dict(TYPES[ty])
        if req:
            t["grow"] += "_r"
            t["grow_k"] += "_r"
        for an, atext, ao in ARGS:
            if conv != "sink" and an in LET_REJECTS:
                continue
            a = atext.format(**t)
            for wi, w in enumerate(WS):
                for cn, ctext in CALLEES[conv]:
                    # (every second argument by the method; the others with 8)
                    if wi > 0 and cn not in ("m", "mf", "ml"):
                        continue
                    # (a let field is no let parameter: a new value there has
                    # no place, `error: expected 'let Sh', got 'Sh'`)
                    if conv == "view" and cn.endswith("l") and an in LIT_REJECTS:
                        continue
                    call = ctext.format(c=t["c"], a=a, w=w[1], r=r, desc=t["desc"],
                                        desc_of=t["desc_of"])
                    for on, otext in OUTER:
                        # (an error leaves the case from the argument
                        # itself: `scr`'s arm, -100 + e, is never taken)
                        exp = outcome(ty, (an, atext, ao), w, on)
                        pre = "let k = 1;\n"
                        if an == "local":
                            pre += f"let loc = dev.{t['mk']}(7);\n"
                        if conv == "inout":
                            pre += "var acc = dev.mk(1);\n"
                        body = pre + otext.format(C=call)
                        out.append((f"{ty}_{an}_{w[0]}_{cn}_{on}", body, exp))
    return out


def program(cs, header):
    lines = [header, "// FLAGS: --check-alloc"]
    for name, _, exp in cs:
        lines.append(f"// EXPECT: {name} {exp}")
    src = "\n".join(lines) + "\n\n" + PRELUDE
    calls = []
    for name, body, _ in cs:
        ind = "\n".join("    " + l for l in body.split("\n"))
        src += f"\nfn case_{name}(dev: Dev) -> Result<i64, i64> {{\n{ind}\n}}\n"
        calls.append(f"    show(\"{name}\", case_{name}(dev));")
    src += """
fn show(n: str, r: Result<i64, i64>) {
    match r {
        Ok(v) => println(f"{n} ok {v}"),
        Err(e) => println(f"{n} err {e}"),
    }
}
"""
    src += "\nfn main(gpa: Gpa) -> i32 {\n    let dev = Dev { gpa: gpa, on: true };\n" + "\n".join(
        calls) + "\n    0\n}\n"
    return src


HEAD = ("// Generated by tools/sinksweep/argsweep.py (0.25.2.1): an owned argument\n"
        "// whose expression may leave (`?`, a match or if with a return, nested\n"
        "// calls) given to a parameter taken {what}, the call's result `?`'d,\n"
        "// let, returned, a tail or matched.")
WHAT = {"let": "`let`", "sink": "`sink`", "inout": "`let` after an `inout` one",
        "view": "`let` in a view (a struct with a let field)"}

if __name__ == "__main__":
    # (0.25.2.2: each convention again with callees that have a requires
    # clause, own_arg_temp_sweep_*_req)
    if sys.argv[1] == "--one":
        d = sys.argv[2]
        os.makedirs(d, exist_ok=True)
        with open(f"{d}/expected.txt", "w") as ef:
            for conv in ("let", "sink", "inout", "view"):
                for req in (False, True):
                    for c in cases(conv, req):
                        name = f"{conv}{'_req' if req else ''}_{c[0]}"
                        with open(f"{d}/{name}.vl", "w") as f:
                            f.write(program([(name, c[1], c[2])], HEAD.format(what=WHAT[conv])))
                        ef.write(f"{name} {c[2]}\n")
    else:
        for conv in ("let", "sink", "inout", "view"):
            for req in (False, True):
                what = WHAT[conv] + (", by a function with a requires" if req else "")
                with open(f"{sys.argv[1]}/own_arg_temp_sweep_{conv}{'_req' if req else ''}.vl",
                          "w") as f:
                    f.write(program(cases(conv, req), HEAD.format(what=what)))
