#!/usr/bin/env python3
"""Writes tests/run/num_int_ops_rust.vl (0.26.3): std's wrapping_*,
checked_*, overflowing_*, saturating_* and Wrapping<T> for every integer
type, called on each type's edge values, with EXPECT lines that are
rustc's output for the same calls (its Rust twin, compiled and run here).

usage: tools/intops/twin.py   (needs rustc; writes the case, then volec fmt it)
"""
import os
import subprocess
import sys
import tempfile

TYPES = [("i8", 8, True), ("i16", 16, True), ("i32", 32, True), ("i64", 64, True),
         ("isize", 64, True), ("u8", 8, False), ("u16", 16, False), ("u32", 32, False),
         ("u64", 64, False), ("usize", 64, False)]


def vals(bits, signed):
    if signed:
        mx = (1 << (bits - 1)) - 1
        mn = -(1 << (bits - 1))
        return [(mx, 1), (mn, -1), (mn, 2), (mx, mx), (-7, 3), (5, 0), (mn, 0), (3, 4)]
    mx = (1 << bits) - 1
    return [(mx, 1), (0, 1), (mx, mx), (7, 3), (5, 0), (mx // 2 + 1, 2), (3, 4)]


def ops_of(signed, b):
    ops = []
    for op in ["add", "sub", "mul"]:
        ops += [f"a.wrapping_{op}(b)", f"a.checked_{op}(b)", f"a.overflowing_{op}(b)",
                f"a.saturating_{op}(b)"]
    ops += ["a.wrapping_neg()", "a.checked_neg()", "a.overflowing_neg()"]
    for op in ["shl", "shr"]:
        ops += [f"a.wrapping_{op}(b as u32)", f"a.checked_{op}(b as u32)",
                f"a.overflowing_{op}(b as u32)"]
    ops += ["a.checked_div(b)", "a.checked_rem(b)", "a.checked_pow(b as u32 & 7)",
            "a.wrapping_pow(b as u32 & 7)", "a.overflowing_pow(b as u32 & 7)",
            "a.saturating_pow(b as u32 & 7)"]
    if b != 0:
        ops += ["a.wrapping_div(b)", "a.wrapping_rem(b)", "a.overflowing_div(b)",
                "a.overflowing_rem(b)", "a.saturating_div(b)"]
    if signed:
        ops += ["a.wrapping_abs()", "a.checked_abs()", "a.overflowing_abs()",
                "a.saturating_abs()", "a.saturating_neg()"]
    # (vole's tuples have no Debug: an overflowing pair is printed by fields)
    return [x for o in ops for x in ((o + ".0", o + ".1") if "overflowing" in o else (o,))]


def main():
    rs = ["#![allow(overflowing_literals)]", "use std::num::Wrapping;", "fn main() {"]
    vl = []
    for t, bits, signed in TYPES:
        for i, (a, b) in enumerate(vals(bits, signed)):
            rs.append(f"    let a: {t} = {a}; let b: {t} = {b};")
            f = "id" if signed else "idu"
            vl.append(f"    let a: {t} = {f}({a}) as {t};")
            vl.append(f"    let b: {t} = {f}({b}) as {t};")
            ops = ops_of(signed, b)
            fmt = " ".join(["{:?}"] * len(ops))
            rs.append(f'    println!("{t}#{i}: {fmt}", {", ".join(ops)});')
            vl.append(f'    println("{t}#{i}: {fmt}", {", ".join(ops)});')
    # Wrapping<T>: + - * / and unary -, whatever the overflow checks
    for t, a, b in [("u8", 250, 10), ("i32", 2147483647, 2), ("u64", 0, 1), ("i64", -9223372036854775808, -1)]:
        f = "id" if t[0] == "i" else "idu"
        rs.append(f"    let x = Wrapping({a} as {t}); let y = Wrapping({b} as {t});")
        vl.append(f"    let x = Wrapping({f}({a}) as {t});")
        vl.append(f"    let y = Wrapping({f}({b}) as {t});")
        ops = ["(x + y).0", "(x - y).0", "(x * y).0", "(-x).0"] + (["(x / y).0"] if b != 0 else [])
        rs.append(f'    println!("Wrapping<{t}>: {" ".join(["{}"] * len(ops))}", {", ".join(ops)});')
        vops = [o.replace(".0", ".value") for o in ops]
        vl.append(f'    println("Wrapping<{t}>: {" ".join(["{}"] * len(vops))}", {", ".join(vops)});')
    rs.append("}")
    d = tempfile.mkdtemp()
    src = os.path.join(d, "twin.rs")
    with open(src, "w") as fh:
        fh.write("\n".join(rs) + "\n")
    subprocess.run(["rustc", "-O", "-o", os.path.join(d, "twin"), src], check=True)
    out = subprocess.run([os.path.join(d, "twin")], check=True, capture_output=True,
                         text=True).stdout
    head = ["// (0.26.3) std's integer API for every integer type, against Rust:",
            "// wrapping_*, checked_*, overflowing_* and saturating_* (+ - *, unary -,",
            "// the shifts, / % and pow, abs) on each type's edge values, and",
            "// Wrapping<T>'s operators. The EXPECT lines are rustc's output for the",
            "// same calls (tools/intops/twin.py writes this case from its Rust twin).",
            "// The methods never check, so the case passes at every level."]
    head += ["// EXPECT: " + l for l in out.splitlines()]
    prog = ["use std::num::Wrapping;", "", "#[inline(never)]", "fn id(x: i64) -> i64 {", "    x",
            "}", "", "#[inline(never)]", "fn idu(x: u64) -> u64 {", "    x", "}", "",
            "fn main() {"] + vl + ["}"]
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    with open(os.path.join(root, "tests/run/num_int_ops_rust.vl"), "w") as fh:
        fh.write("\n".join(head + prog) + "\n")


main()
