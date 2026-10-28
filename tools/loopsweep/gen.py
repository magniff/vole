#!/usr/bin/env python3
# Generates tests/run/opt_loop_trip_sweep_{len,types,steps}.vl (0.25.2):
# counted loops of constant trip counts over arrays (in structs through inout,
# locals) and Vec, with stores, reductions, non-zero starts, steps that are not
# powers of two and `!=` exits; each case checks its result against the value
# computed here, and tests/run.sh runs them at -O2 (and -O0 with `-O 0`).
#
#   python3 tools/loopsweep/gen.py tests/run
#   target/volec fmt tests/run/opt_loop_trip_sweep_{len,types,steps}.vl
import sys

OUT = sys.argv[1]

TYPES = {
    "u8": (lambda x: x % 256, "1"),
    "u16": (lambda x: x % 65536, "1"),
    "u32": (lambda x: x % 2**32, "1"),
    "u64": (lambda x: x % 2**64, "1"),
    "f32": (lambda x: x, "1.0"),
}
G = 12345


def val(t, i):
    return TYPES[t][0](i * 7 + 3)


def wrap_sum(t, xs):
    # a reduction in T's own arithmetic (f32: exact for these values)
    s = sum(xs)
    return TYPES[t][0](s) if t != "f32" else s


class Gen:
    def __init__(self):
        self.items = []
        self.calls = []
        self.n = 0

    def case(self, name, expect, items, call):
        self.n += 1
        self.items.append(items)
        self.calls.append(
            f"    c = {call};\n"
            f"    if c != {expect} {{ println(f\"bad {name}: {{c}} (want {expect})\"); bad += 1; }}\n")

    def st(self, t, n, start, inline):
        # an array in a struct, filled through an inout parameter
        k = f"st{'i' if inline else ''}_{t}_{n}_{start}"
        init = TYPES[t][1]
        attr = "" if inline else "#[inline(never)]\n"
        src = (f"struct S_{k} {{ g0: u64, a: [{t}; {n}], g1: u64 }}\n\n"
               f"{attr}fn fill_{k}(s: inout S_{k}) {{\n"
               f"    for i in {start}..{n} {{\n        s.a[i] = (i * 7 + 3) as {t};\n    }}\n}}\n\n"
               f"#[inline(never)]\nfn case_{k}() -> i64 {{\n"
               f"    var s = S_{k} {{ g0: {G}, a: [{init}; {n}], g1: {G} }};\n"
               f"    fill_{k}(&s);\n"
               f"    var c: i64 = (s.g0 + s.g1) as i64;\n"
               f"    for i in 0..{n} {{ c += s.a[i] as i64; }}\n    c\n}}\n")
        exp = 2 * G + start + sum(val(t, i) for i in range(start, n))
        self.case(k, exp, src, f"case_{k}()")

    def splat(self, t, n):
        # the original shape: one value stored to every element
        k = f"sp_{t}_{n}"
        init = TYPES[t][1]
        src = (f"struct S_{k} {{ cells: [{t}; {n}], shown: bool }}\n\n"
               f"fn fill_{k}(o: inout S_{k}) {{\n"
               f"    for i in 0..{n} {{\n        o.cells[i] = 32 as {t};\n    }}\n}}\n\n"
               f"#[inline(never)]\nfn case_{k}() -> i64 {{\n"
               f"    var o = S_{k} {{ cells: [{init}; {n}], shown: true }};\n"
               f"    fill_{k}(&o);\n"
               f"    var c: i64 = if o.shown {{ 1000000 }} else {{ 0 }};\n"
               f"    for i in 0..{n} {{ c += o.cells[i] as i64; }}\n    c\n}}\n")
        self.case(k, 1000000 + 32 * n, src, f"case_{k}()")

    def loc(self, t, n):
        # a local array between two others
        k = f"loc_{t}_{n}"
        init = TYPES[t][1]
        src = (f"#[inline(never)]\nfn case_{k}(z: i64) -> i64 {{\n"
               f"    var lo: [u64; 4] = [{G}; 4];\n"
               f"    var a: [{t}; {n}] = [{init}; {n}];\n"
               f"    var hi: [u64; 4] = [{G}; 4];\n"
               f"    for i in 0..{n} {{\n        a[i] = (i * 7 + 3 + z) as {t};\n    }}\n"
               f"    var c: i64 = 0;\n"
               f"    for i in 0..4 {{ c += (lo[i] + hi[i]) as i64; }}\n"
               f"    for i in 0..{n} {{ c += a[i] as i64; }}\n    c\n}}\n")
        exp = 8 * G + sum(val(t, i) for i in range(n))
        self.case(k, exp, src, f"case_{k}(zero)")

    def vec(self, t, n):
        # a Vec longer than the loop: the elements after it stay
        k = f"vec_{t}_{n}"
        init = TYPES[t][1]
        src = (f"#[inline(never)]\nfn fill_{k}(v: inout Vec<{t}>) {{\n"
               f"    for i in 0..{n} {{\n        v[i] = (i * 7 + 3) as {t};\n    }}\n}}\n\n"
               f"#[inline(never)]\nfn case_{k}(gpa: Gpa) -> i64 {{\n"
               f"    var v: Vec<{t}> = Vec::new_in(gpa);\n"
               f"    for _ in 0..{n + 8} {{ v.push({init}); }}\n"
               f"    fill_{k}(&v);\n"
               f"    var c: i64 = 0;\n"
               f"    for i in 0..v.len() {{ c += v[i] as i64; }}\n    c\n}}\n")
        exp = 8 + sum(val(t, i) for i in range(n))
        self.case(k, exp, src, f"case_{k}(gpa)")

    def red(self, t, n):
        # a reduction in T (several accumulators when unrolled)
        k = f"red_{t}_{n}"
        src = (f"struct R_{k} {{ a: [{t}; {n}], g: [{t}; 8] }}\n\n"
               f"#[inline(never)]\nfn sum_{k}(r: R_{k}) -> {t} {{\n"
               f"    var s: {t} = 0 as {t};\n"
               f"    for i in 0..{n} {{ s += r.a[i]; }}\n    s\n}}\n\n"
               f"#[inline(never)]\nfn case_{k}() -> i64 {{\n"
               f"    var r = R_{k} {{ a: [0 as {t}; {n}], g: [100 as {t}; 8] }};\n"
               f"    for i in 0..{n} {{ r.a[i] = (i * 7 + 3) as {t}; }}\n"
               f"    sum_{k}(r) as i64\n}}\n")
        exp = wrap_sum(t, [val(t, i) for i in range(n)])
        self.case(k, exp, src, f"case_{k}()")

    def step(self, t, n, s, ne):
        # a while loop stepping by s, exit `i < n` or `i != n`
        k = f"step{'ne' if ne else 'lt'}_{t}_{n}_{s}"
        init = TYPES[t][1]
        test = f"i != {n}" if ne else f"i < {n}"
        src = (f"struct S_{k} {{ g0: u64, a: [{t}; {n}], g1: u64 }}\n\n"
               f"#[inline(never)]\nfn fill_{k}(s: inout S_{k}) {{\n"
               f"    var i = 0;\n    while {test} {{\n        s.a[i] = (i * 7 + 3) as {t};\n        i += {s};\n    }}\n}}\n\n"
               f"#[inline(never)]\nfn case_{k}() -> i64 {{\n"
               f"    var s = S_{k} {{ g0: {G}, a: [{init}; {n}], g1: {G} }};\n"
               f"    fill_{k}(&s);\n"
               f"    var c: i64 = (s.g0 + s.g1) as i64;\n"
               f"    for i in 0..{n} {{ c += s.a[i] as i64; }}\n    c\n}}\n")
        idx = list(range(0, n, s))
        exp = 2 * G + (n - len(idx)) + sum(val(t, i) for i in idx)
        self.case(k, exp, src, f"case_{k}()")

    def write(self, path, header):
        with open(path, "w") as f:
            f.write(header)
            f.write(f"// EXPECT: {self.n} cases, 0 bad\n\n")
            f.write("\n".join(self.items))
            f.write("\nfn main(gpa: Gpa) -> i32 {\n    let zero = parse_int(\"0\").unwrap_or(0);\n"
                    "    var bad = 0;\n    var c: i64 = 0;\n")
            f.write("".join(self.calls))
            f.write(f"    println(f\"{self.n} cases, {{bad}} bad\");\n    0\n}}\n")


BIG = [488, 504, 510, 1000]
L1 = list(range(1, 131)) + BIG
L2 = [1, 3, 4, 7, 8, 11, 12, 13, 16, 17, 24, 25, 31, 33, 48, 64, 100, 120, 127, 130] + BIG

HDR = ("// generated by tools/loopsweep/gen.py (0.25.2): counted loops of constant\n"
       "// trip counts at -O2 against -O0. The vectorizer rounded the vector loop's trip\n"
       "// count down with `trips & -(u * vf)` while its cost model could pick u = 3:\n"
       "// 3 copies of 4 lanes rounded 510 to 500, and the `!=` exit was never met.\n")

a = Gen()
for n in L1:
    a.splat("u32", n)
    a.st("u32", n, 0, False)
a.write(OUT + "/opt_loop_trip_sweep_len.vl", HDR + "// Every length 1..130 and a few large ones: u32 stores into an inout struct.\n")

b = Gen()
for t in TYPES:
    for n in L2:
        b.st(t, n, 0, False)
        b.st(t, n, 3, True) if n > 3 else None
        b.loc(t, n)
        b.vec(t, n)
b.write(OUT + "/opt_loop_trip_sweep_types.vl", HDR + "// u8 u16 u32 u64 f32: an inout struct's array (from 0, from 3 inlined), a local, a Vec.\n")

c = Gen()
for t in TYPES:
    for n in L2:
        c.red(t, n)
for t in ["u8", "u32", "u64"]:
    for n in [12, 24, 30, 60, 120, 125, 488, 504, 510]:
        for s in [1, 2, 3, 5, 6, 7, 12]:
            c.step(t, n, s, False)
            if n % s == 0:
                c.step(t, n, s, True)
c.write(OUT + "/opt_loop_trip_sweep_steps.vl", HDR + "// Reductions in each type; while loops stepping by 1, 2, 3, 5, 6, 7, 12 exiting on `<` and `!=`.\n")
