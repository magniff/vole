# Random programs for the parallel moves of the register allocator
# (0.30.1, RT-CG-5, RT-CG-6): values of every class and width (i64, i32,
# u8, bool, f64, f32, a Copy struct; with vectors=1 also 8-, 16- and
# 32-byte vectors) carried around a loop, rotated (each rotation is a
# cycle of phi moves), updated, branched over and kept live across calls
# under register pressure, so that the loop's edges move values between
# spill slots shared by values of other classes and widths. The output
# must be the same at every level (tests/fuzz/run.sh -M; -M -V for the
# vectors). From the generators of the review of RT-CG-5.
#
# (0.30.1, RT-CG-7) With pad=N, main first defines N f32 values, live to
# its end (summed and printed last): its spill slots then reach past 16 KB
# (N = 2100: 16800 bytes), where an AArch64 f32 slot's offset is no
# longer one ldr/str can encode, and the loop's moves go between such
# slots (tests/fuzz/run.sh -F). With types="T...", the values' types are
# drawn from that list (scalars only; -F: "i64 i32 f32 f32", where integer
# cycles and f32 slot moves meet on one edge more often: 13 of 100
# programs at pad=2100 failed on the build with RT-CG-7, against 1 of 100
# with every type).
#
# usage: awk -v seed=N [-v vectors=1] [-v pad=N] [-v types=T...] -f tests/fuzz/genmoves.awk

function rnd(n) { return int(rand() * n) }          # 0 .. n-1
function between(a, b) { return a + rnd(b - a + 1) } # a .. b

function init(ty, k) {
    if (ty in FV) return ty "::splat((g(" k ") as " FV[ty] ") * 0.5)"
    if (ty in IV) return ty "::splat((g(" k ") & 15) as " IV[ty] ")"
    if (ty == "i64") return "g(" (k + 11) ")"
    if (ty == "i32") return "(g(" (k + 3) ") as i32) & 1023"
    if (ty == "u8") return "(g(" k ") as u8) & 63"
    if (ty == "bool") return "(g(" k ") & 1) == 0"
    if (ty == "f64") return "(g(" (k + 2) ") as f64) * 0.375"
    if (ty == "f32") return "(g(" (k + 1) ") as f32) * 0.625"
    return "P { a: g(" k "), b: (g(" (k + 5) ") as f64) * 0.5 }"
}

# A variable of type ty other than v when there is one (else v).
function other(ty, v,    i, c, n) {
    n = 0
    for (i = 0; i < npool; i++) if (ptype[i] == ty) c[n++] = pname[i]
    return n ? c[rnd(n)] : v
}

function update(ty, v,    o, x) {
    o = other(ty, v)
    if (ty in FV) return v " = " v " * " ty "::splat(0.5) + " o " * " ty "::splat(0.25) + " ty "::splat((c as " FV[ty] ") * 0.125);"
    if (ty in IV) return v " = ((" v " ^ " ty "::splat((c & 7) as " IV[ty] ")) + (" o " & " ty "::splat(3))) & " ty "::splat(15);"
    if (ty == "i64") {
        x = other("f64", "")
        return v " = (((" v " ^ c) + (" o " & 65535))" (x != "" && rand() < 0.4 ? " + ((" x " as i64) & 255)" : "") ") & 4294967295;"
    }
    if (ty == "i32") return v " = ((" v " ^ (c as i32)) & 65535) + (" o " & 7);"
    if (ty == "u8") return v " = ((" v " ^ (c as u8)) & 127) + (" o " & 1);"
    if (ty == "bool") return v " = (!" v ") != (((c & 1) == 0) && " o ");"
    if (ty == "f64") {
        x = other("i32", "")
        return v " = " v " * 0.5 + (c as f64) * 0.25 + " o " * 0.125" (x != "" && rand() < 0.4 ? " + (" x " as f64)" : "") ";"
    }
    if (ty == "f32") return v " = " v " * 0.5 + (c as f32) * 0.25 + " o " * 0.125;"
    return v " = P { a: (" v ".a ^ c) & 65535, b: " v ".b * 0.5 + " o ".b * 0.25 };"
}

# A rotation of 2 or more of the variables of type ty: a cycle of moves.
function rotation(ty, ind,    i, n, c, k, j, t, out) {
    n = 0
    for (i = 0; i < npool; i++) if (ptype[i] == ty) c[n++] = pname[i]
    if (n < 2) return
    for (i = n - 1; i > 0; i--) { j = rnd(i + 1); t = c[i]; c[i] = c[j]; c[j] = t }
    k = between(2, n)
    out = "{ let tmp_r = " c[0] ";"
    for (i = 0; i + 1 < k; i++) out = out " " c[i] " = " c[i + 1] ";"
    out = out " " c[k - 1] " = tmp_r; }"
    print ind out
}

function block(ind,    s, steps, i) {
    steps = between(2, 8)
    for (s = 0; s < steps; s++) {
        if (rand() < 0.5) rotation(ptype[rnd(npool)], ind)
        else { i = rnd(npool); print ind update(ptype[i], pname[i]) }
        if (rand() < 0.2) print ind "s = s + g(t);"
    }
}

function fill(p, ind,    k) {
    for (k = 0; k < na; k++) if (rand() < p) print ind "s = s ^ (a" k " + t);"
    for (k = 0; k < nb; k++) if (rand() < p) print ind "sf = sf * 0.5 + b" k ";"
}

BEGIN {
    srand(seed)
    if (vectors) {
        FV["v2f64"] = "f64"; FV["v1f64"] = "f64"; FV["v4f64"] = "f64"; FV["v4f32"] = "f32"
        IV["v4i32"] = "i32"; IV["v8u8"] = "u8"; IV["v8i32"] = "i32"; IV["v2i64"] = "i64"
        ntypes = split("v2f64 v1f64 v4f64 v4f32 v4i32 v8u8 v8i32 v2i64 i64 f64", TYPES, " ")
    } else {
        ntypes = split(types != "" ? types : "i64 i32 u8 bool f64 f32 P", TYPES, " ")
    }
    npool = between(4, 12)
    for (i = 0; i < npool; i++) { pname[i] = "v" i; ptype[i] = TYPES[1 + rnd(ntypes)] }
    # two of a type at least, twice: rotations are possible
    for (k = 0; k < 2; k++) {
        ty = TYPES[1 + rnd(ntypes)]
        pname[npool] = "v" npool; ptype[npool] = ty; npool++
        pname[npool] = "v" npool; ptype[npool] = ty; npool++
    }
    na = between(0, 30); nb = between(0, 30)
    print "use std::sync::atomic::{AtomicI64, Ordering};"
    print "static K: AtomicI64 = AtomicI64::new(0);"
    if (!vectors) {
        print "#[derive(Clone, Copy)]"
        print "struct P {"
        print "    a: i64,"
        print "    b: f64,"
        print "}"
    }
    print "#[inline(never)]"
    print "fn g(a: i64) -> i64 {"
    print "    K.fetch_add(1, Ordering::Relaxed);"
    print "    a ^ 5"
    print "}"
    print "fn main() {"
    for (k = 0; k < pad; k++) printf "    let p%d = (g(%d) as f32) * 0.5;\n", k, k % 50
    print "    let lim = (g(7) & 15) + 3;"
    for (k = 0; k < na; k++) print "    let a" k " = g(" (k + 20) ");"
    for (k = 0; k < nb; k++) print "    let b" k " = (g(" (k + 40) ") as f64) * 0.5;"
    for (i = 0; i < npool; i++) print "    let mut " pname[i] ": " ptype[i] " = " init(ptype[i], i) ";"
    print "    let mut t: i64 = 0;"
    print "    let mut s: i64 = 0;"
    print "    let mut sf: f64 = 0.0;"
    print "    while t < lim {"
    fill(0.7, "        ")
    print "        let c = g(t);"
    block("        ")
    if (rand() < 0.7) {
        print "        if (c & 3) == 0 {"
        block("            ")
        print "        } else {"
        block("            ")
        print "        }"
    }
    fill(0.5, "        ")
    print "        let e = g(t + 1);"
    block("        ")
    print "        s = s + e;"
    print "        t += 1;"
    print "    }"
    for (i = 0; i < npool; i++) {
        ty = ptype[i]
        if (ty == "P") { print "    println(\"{} {}\", " pname[i] ".a, " pname[i] ".b);" }
        else if ((ty in FV) || (ty in IV)) print "    println(\"{}\", " pname[i] ".sum());"
        else print "    println(\"{}\", " pname[i] ");"
    }
    print "    println(\"{} {}\", s, sf);"
    if (pad > 0) {
        print "    let mut ps: f32 = 0.0;"
        for (k = 0; k < pad; k++) print "    ps += p" k ";"
        print "    println(\"{}\", ps);"
    }
    print "}"
}
