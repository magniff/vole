#!/usr/bin/env python3
"""Writes compiler/std/num/wrapping.vl (0.26.3): Rust's integer arithmetic
that does not check, for every integer type: wrapping_*, checked_*,
overflowing_*, saturating_*. Its module's arithmetic is never checked (the
places builder's rule, places/build.vl), so `self + rhs` there is the
wrapping add whatever the overflow checks of the build.

usage: tools/intops/gen.py > compiler/std/num/wrapping.vl && volec fmt compiler/std/num/wrapping.vl
"""

TYPES = [("i8", 8, True), ("i16", 16, True), ("i32", 32, True), ("i64", 64, True),
         ("isize", 64, True), ("u8", 8, False), ("u16", 16, False), ("u32", 32, False),
         ("u64", 64, False), ("usize", 64, False)]

HEADER = """// std::num::wrapping (0.26.3): made by tools/intops/gen.py.

use std::num::mul_hi;

// ---- Integer arithmetic: the traits (0.26.3) ----

// (decision 6) Rust's integer arithmetic that does not check, as each
// integer type's methods: `x.wrapping_add(y)`, `x.checked_mul(y)` (an
// Option), `x.overflowing_sub(y)` (the wrapped value and whether it
// overflowed), `x.saturating_add(y)`, with no `use`. This module's
// arithmetic never checks overflow (places/build.vl: std_wraps), whatever
// --overflow-checks says: `self + rhs` here is Rust's wrapping_add. `/`
// and `%` by zero panic here too, as Rust's wrapping_div does. Edit the
// generator, not this file.
//
// Every integer type's: `+ - *`, unary `-`, the shifts (by a u32 amount),
// `/`, `%` and pow, wrapping, checked (None when Rust's operator would
// panic), overflowing (the wrapped value, and whether it overflowed) and
// saturating (at the type's bounds).
pub trait IntOverflow {
"""

COMMON = [
    ("wrapping_add", "rhs: Self", "Self"), ("wrapping_sub", "rhs: Self", "Self"),
    ("wrapping_mul", "rhs: Self", "Self"), ("wrapping_neg", "", "Self"),
    ("wrapping_shl", "rhs: u32", "Self"), ("wrapping_shr", "rhs: u32", "Self"),
    ("wrapping_div", "rhs: Self", "Self"), ("wrapping_rem", "rhs: Self", "Self"),
    ("wrapping_pow", "exp: u32", "Self"),
    ("checked_add", "rhs: Self", "Option<Self>"), ("checked_sub", "rhs: Self", "Option<Self>"),
    ("checked_mul", "rhs: Self", "Option<Self>"), ("checked_neg", "", "Option<Self>"),
    ("checked_shl", "rhs: u32", "Option<Self>"), ("checked_shr", "rhs: u32", "Option<Self>"),
    ("checked_div", "rhs: Self", "Option<Self>"), ("checked_rem", "rhs: Self", "Option<Self>"),
    ("checked_pow", "exp: u32", "Option<Self>"),
    ("overflowing_add", "rhs: Self", "(Self, bool)"), ("overflowing_sub", "rhs: Self", "(Self, bool)"),
    ("overflowing_mul", "rhs: Self", "(Self, bool)"), ("overflowing_neg", "", "(Self, bool)"),
    ("overflowing_shl", "rhs: u32", "(Self, bool)"), ("overflowing_shr", "rhs: u32", "(Self, bool)"),
    ("overflowing_div", "rhs: Self", "(Self, bool)"), ("overflowing_rem", "rhs: Self", "(Self, bool)"),
    ("overflowing_pow", "exp: u32", "(Self, bool)"),
    ("saturating_add", "rhs: Self", "Self"), ("saturating_sub", "rhs: Self", "Self"),
    ("saturating_mul", "rhs: Self", "Self"), ("saturating_div", "rhs: Self", "Self"),
    ("saturating_pow", "exp: u32", "Self"),
]

SIGNED = [
    ("wrapping_abs", "", "Self"), ("checked_abs", "", "Option<Self>"),
    ("overflowing_abs", "", "(Self, bool)"), ("saturating_abs", "", "Self"),
    ("saturating_neg", "", "Self"),
]


def sig(name, params, ret, ty=None):
    p = "self" + (", " + params if params else "")
    r = ret
    if ty:
        p = p.replace("Self", ty)
        r = r.replace("Self", ty)
    return f"fn {name}({p}) -> {r}"


def some(e):
    return f"Option::Some({e})"


def body(name, t, bits, signed):
    wide = "i64" if signed else "u64"
    m = bits - 1
    narrow = bits < 64
    b = {}
    b["wrapping_add"] = "self + rhs"
    b["wrapping_sub"] = "self - rhs"
    b["wrapping_mul"] = "self * rhs"
    b["wrapping_neg"] = "0 - self"
    b["wrapping_shl"] = f"self << (rhs & {m})"
    b["wrapping_shr"] = f"self >> (rhs & {m})"
    if signed:
        b["wrapping_div"] = "if rhs == -1 { 0 - self } else { self / rhs }"
        b["wrapping_rem"] = "if rhs == -1 { 0 } else { self % rhs }"
    else:
        b["wrapping_div"] = "self / rhs"
        b["wrapping_rem"] = "self % rhs"
    b["wrapping_pow"] = POW.format(t=t, mul="out = out * base;", sq="base = base * base;",
                                   pre="", post="out")
    for op in ("add", "sub", "mul", "neg", "shl", "shr", "div", "rem", "pow"):
        b[f"checked_{op}"] = None
    if narrow:
        for op, sym in (("add", "+"), ("sub", "-"), ("mul", "*")):
            b[f"overflowing_{op}"] = (f"let w = self as {wide} {sym} rhs as {wide};\n"
                                      f"let r = w as {t};\n(r, r as {wide} != w)")
    else:
        if signed:
            b["overflowing_add"] = "let r = self + rhs;\n(r, (self ^ r) & (rhs ^ r) < 0)"
            b["overflowing_sub"] = "let r = self - rhs;\n(r, (self ^ rhs) & (self ^ r) < 0)"
            b["overflowing_mul"] = (
                "let lo = self * rhs;\n"
                "// (the signed high half from the unsigned one)\n"
                "var hi = mul_hi(self as u64, rhs as u64) as i64;\n"
                "if self < 0 {\n    hi = hi - rhs as i64;\n}\n"
                "if rhs < 0 {\n    hi = hi - self as i64;\n}\n"
                "(lo, hi != (lo as i64) >> 63)")
        else:
            b["overflowing_add"] = "let r = self + rhs;\n(r, r < self)"
            b["overflowing_sub"] = "(self - rhs, self < rhs)"
            b["overflowing_mul"] = "(self * rhs, mul_hi(self as u64, rhs as u64) != 0)"
    b["overflowing_neg"] = f"(0 - self, self == {t}::MIN)" if signed else "(0 - self, self != 0)"
    b["overflowing_shl"] = f"(self << (rhs & {m}), rhs > {m})"
    b["overflowing_shr"] = f"(self >> (rhs & {m}), rhs > {m})"
    if signed:
        b["overflowing_div"] = (f"if self == {t}::MIN && rhs == -1 {{ (self, true) }} "
                                "else { (self / rhs, false) }")
        b["overflowing_rem"] = (f"if self == {t}::MIN && rhs == -1 {{ (0, true) }} "
                                "else { (self % rhs, false) }")
    else:
        b["overflowing_div"] = "(self / rhs, false)"
        b["overflowing_rem"] = "(self % rhs, false)"
    b["overflowing_pow"] = POW.format(
        t=t, pre="var ovf = false;\n",
        mul="let (r, o) = out.overflowing_mul(base);\n        out = r;\n        ovf = ovf || o;",
        sq="let (r, o) = base.overflowing_mul(base);\n        base = r;\n        ovf = ovf || o;",
        post="(out, ovf)")
    for op in ("add", "sub", "mul", "neg", "pow"):
        arg = "" if op == "neg" else ("exp" if op == "pow" else "rhs")
        b[f"checked_{op}"] = (f"let (r, o) = self.overflowing_{op}({arg});\n"
                              f"if o {{ Option::None }} else {{ {some('r')} }}")
    b["checked_shl"] = f"if rhs > {m} {{ Option::None }} else {{ {some('self << rhs')} }}"
    b["checked_shr"] = f"if rhs > {m} {{ Option::None }} else {{ {some('self >> rhs')} }}"
    for op, sym in (("div", "/"), ("rem", "%")):
        cond = f"rhs == 0 || self == {t}::MIN && rhs == -1" if signed else "rhs == 0"
        b[f"checked_{op}"] = f"if {cond} {{ Option::None }} else {{ {some('self ' + sym + ' rhs')} }}"
    if signed:
        b["saturating_add"] = (f"let (r, o) = self.overflowing_add(rhs);\n"
                               f"if !o {{ r }} else if rhs < 0 {{ {t}::MIN }} else {{ {t}::MAX }}")
        b["saturating_sub"] = (f"let (r, o) = self.overflowing_sub(rhs);\n"
                               f"if !o {{ r }} else if rhs > 0 {{ {t}::MIN }} else {{ {t}::MAX }}")
        b["saturating_mul"] = (f"let (r, o) = self.overflowing_mul(rhs);\n"
                               f"if !o {{ r }} else if (self < 0) != (rhs < 0) {{ {t}::MIN }} "
                               f"else {{ {t}::MAX }}")
        b["saturating_div"] = (f"if self == {t}::MIN && rhs == -1 {{ {t}::MAX }} else {{ self / rhs }}")
        b["saturating_pow"] = (f"let (r, o) = self.overflowing_pow(exp);\n"
                               f"if !o {{ r }} else if self < 0 && exp % 2 == 1 {{ {t}::MIN }} "
                               f"else {{ {t}::MAX }}")
        b["wrapping_abs"] = "if self < 0 { 0 - self } else { self }"
        b["checked_abs"] = (f"if self == {t}::MIN {{ Option::None }} "
                            f"else {{ {some('self.wrapping_abs()')} }}")
        b["overflowing_abs"] = f"(self.wrapping_abs(), self == {t}::MIN)"
        b["saturating_abs"] = f"if self == {t}::MIN {{ {t}::MAX }} else {{ self.wrapping_abs() }}"
        b["saturating_neg"] = f"if self == {t}::MIN {{ {t}::MAX }} else {{ 0 - self }}"
    else:
        b["saturating_add"] = f"let (r, o) = self.overflowing_add(rhs);\nif o {{ {t}::MAX }} else {{ r }}"
        b["saturating_sub"] = "let (r, o) = self.overflowing_sub(rhs);\nif o { 0 } else { r }"
        b["saturating_mul"] = f"let (r, o) = self.overflowing_mul(rhs);\nif o {{ {t}::MAX }} else {{ r }}"
        b["saturating_div"] = "self / rhs"
        b["saturating_pow"] = f"let (r, o) = self.overflowing_pow(exp);\nif o {{ {t}::MAX }} else {{ r }}"
    return b[name]


POW = """{pre}var base = self;
var e = exp;
var out: {t} = 1;
while e > 0 {{
    if e & 1 != 0 {{
        {mul}
    }}
    e = e >> 1;
    if e > 0 {{
        {sq}
    }}
}}
{post}"""


def indent(text, n):
    pad = " " * n
    return "\n".join(pad + l if l else l for l in text.split("\n"))


def main():
    out = [HEADER]
    for name, params, ret in COMMON:
        out.append(f"    {sig(name, params, ret)};\n")
    out.append("}\n\n// The signed types' too: |x| and -x wrapping, checked, overflowing or\n"
               "// saturating.\npub trait SignedOverflow {\n")
    for name, params, ret in SIGNED:
        out.append(f"    {sig(name, params, ret)};\n")
    out.append("}\n")
    for t, bits, signed in TYPES:
        out.append(f"\n// ---- Integer arithmetic: {t} (0.26.3) ----\n\n")
        out.append(f"impl IntOverflow for {t} {{\n")
        first = True
        for name, params, ret in COMMON:
            if not first:
                out.append("\n")
            first = False
            out.append(f"    {sig(name, params, ret, t)} {{\n")
            out.append(indent(body(name, t, bits, signed), 8) + "\n    }\n")
        out.append("}\n")
        if signed:
            out.append(f"\nimpl SignedOverflow for {t} {{\n")
            first = True
            for name, params, ret in SIGNED:
                if not first:
                    out.append("\n")
                first = False
                out.append(f"    {sig(name, params, ret, t)} {{\n")
                out.append(indent(body(name, t, bits, signed), 8) + "\n    }\n")
            out.append("}\n")
    print("".join(out), end="")


main()
