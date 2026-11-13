# Writes a random vole program of loops the vectorizer takes (0.10):
# reductions (+ - * & | ^ on integers; + on floats, which stay scalar),
# maps over slices (lanewise + - * / & | ^ and negation of loads,
# invariants and constants, at offsets of -1, 0 or 1), stencils, and
# explicit vector code (loads, arithmetic, sums, stores); called on slices
# of random lengths and starting points (so every alignment and remainder
# shows), on overlapping slices of one array at random distances (0.28:
# through a kernel's twin of raw pointers, see raw_view), and now
# and then on a slice too short for the loop (the bounds check stops the
# program with 101 part way, alike at every level). Everything it does is
# defined, so every optimization level must print the same.
#
# usage: awk -v seed=N -f genvec.awk

function rnd(n) { return int(rand() * n) }

function is_float(t) { return substr(t, 1, 1) == "f" }

function bits(t) { return substr(t, 2) + 0 }

function lanes(t) { return 128 / bits(t) }

function vec_type(t,    b) {
    b = bits(t)
    return "v" (128 / b) (is_float(t) ? "f" : "i") b
}

function literal(t) {
    if (is_float(t)) return (rnd(2) ? "-" : "") rnd(50) "." rnd(10)
    if (substr(t, 1, 1) == "u") return rnd(200) ""
    return (rnd(3) == 0 ? "-" : "") rnd(100)
}

# An expression of element type t over the loads `loads` (a list of
# expressions separated by |) and the invariant `k`.
function elem_expr(t, depth, nload, load,    k, ops, n) {
    if (depth <= 0) {
        k = rnd(6)
        if (k <= 3) return load[1 + rnd(nload)]
        if (k == 4) return "k"
        return "(" literal(t) " as " t ")"
    }
    k = rnd(10)
    if (is_float(t)) {
        n = split("+ - * /", ops, " ")
    } else {
        n = split("+ - * & | ^", ops, " ")
    }
    if (k <= 6) return "(" elem_expr(t, depth - 1, nload, load) " " ops[1 + rnd(n)] " " elem_expr(t, depth - 1, nload, load) ")"
    if (k == 7 && substr(t, 1, 1) != "u") return "(-" elem_expr(t, depth - 1, nload, load) ")"
    return elem_expr(t, depth - 1, nload, load)
}

function pick_type() { return TYPES[1 + rnd(NT)] }

function reduction_kernel(id, t,    op, init, ops, n, load) {
    if (is_float(t)) {
        op = "+"
    } else {
        n = split("+ - * & | ^", ops, " ")
        op = ops[1 + rnd(n)]
    }
    init = literal(t)
    load[1] = "s[i as usize]"
    print "#[inline(never)]"
    print "fn k" id "(s: &[" t "], k: " t ") -> " t " {"
    print "    let mut acc: " t " = " init " as " t ";"
    print "    for i in 0..s.len() as i64 {"
    print "        acc " op "= " elem_expr(t, rnd(3), 1, load) ";"
    print "    }"
    print "    acc"
    print "}"
    KIND[id] = "reduce"
}

function map_kernel(id, t,    load, oa, ob, oo, lo, st) {
    oa = rnd(3) - 1
    ob = rnd(3) - 1
    oo = rnd(2) ? 0 : rnd(3) - 1
    lo = (oa < 0 || ob < 0 || oo < 0) ? 1 : 0
    load[1] = "a[(i" (oa < 0 ? " - 1" : oa > 0 ? " + 1" : "") ") as usize]"
    load[2] = "b[(i" (ob < 0 ? " - 1" : ob > 0 ? " + 1" : "") ") as usize]"
    print "#[inline(never)]"
    print "fn k" id "(a: &[" t "], b: &[" t "], out: &mut [" t "], n: i64, k: " t ") {"
    st = "out[(i" (oo < 0 ? " - 1" : oo > 0 ? " + 1" : "") ") as usize] = " elem_expr(t, 1 + rnd(3), 2, load) ";"
    print "    for i in " lo "..n {"
    print "        " st
    print "    }"
    print "}"
    print "#[inline(never)]"
    print "unsafe fn k" id "p(a: *const " t ", b: *const " t ", out: *mut " t ", n: i64, k: " t ") {"
    print "    for i in " lo "..n {"
    print "        " raw_form(st)
    print "    }"
    print "}"
    KIND[id] = "map"
    TWIN[id] = 1
}

function stencil_kernel(id, t,    load, st) {
    load[1] = "a[(i - 1) as usize]"
    load[2] = "a[i as usize]"
    load[3] = "a[(i + 1) as usize]"
    print "#[inline(never)]"
    print "fn k" id "(a: &[" t "], out: &mut [" t "], n: i64, k: " t ") {"
    st = "out[i as usize] = " elem_expr(t, 2 + rnd(2), 3, load) ";"
    print "    for i in 1..n - 1 {"
    print "        " st
    print "    }"
    print "}"
    print "#[inline(never)]"
    print "unsafe fn k" id "p(a: *const " t ", out: *mut " t ", n: i64, k: " t ") {"
    print "    for i in 1..n - 1 {"
    print "        " raw_form(st)
    print "    }"
    print "}"
    KIND[id] = "stencil"
    TWIN[id] = 1
}

# Explicit vectors: a sum and a lanewise map, a vector at a time, then
# the rest one by one.
function explicit_kernel(id, t,    vt, l, op, ops, n) {
    vt = vec_type(t)
    l = lanes(t)
    if (is_float(t)) {
        n = split("+ - * /", ops, " ")
    } else {
        n = split("+ - * & | ^", ops, " ")
    }
    op = ops[1 + rnd(n)]
    print "#[inline(never)]"
    print "fn k" id "(a: &[" t "], b: &[" t "], out: &mut [" t "], n: i64, k: " t ") {"
    print "    let mut i: i64 = 0;"
    print "    let kv = " vt "::splat(k);"
    print "    while i + " l " <= n {"
    print "        let x = " vt "::load(a, i);"
    print "        let y = " vt "::load(b, i);"
    print "        let m = x " (is_float(t) ? "<" : ">") " y;"
    print "        let r = m.select(x " op " kv, y " op " x);"
    print "        r.store(out, i);"
    print "        i += " l ";"
    print "    }"
    print "    while i < n {"
    print "        out[i as usize] = a[i as usize] " op " b[i as usize];"
    print "        i += 1;"
    print "    }"
    print "}"
    KIND[id] = "map"
}

# An outer loop over j around an inner loop over q (a constant count):
# acc[j] built over q from a[q * W + j] and b[q] (raw pointers into
# arrays sized for it), stored to out[j].
function nested_kernel(id, t,    load, op, ops, n) {
    if (is_float(t)) {
        n = split("+ - *", ops, " ")
    } else {
        n = split("+ - * & | ^", ops, " ")
    }
    op = ops[1 + rnd(n)]
    Q[id] = 2 + rnd(30)
    W[id] = 8 + rnd(40)
    load[1] = "*a.add((q * " W[id] " + j) as usize)"
    load[2] = "*b.add(q as usize)"
    print "#[inline(never)]"
    print "unsafe fn k" id "(a: *const " t ", b: *const " t ", out: *mut " t ", n: i64, k: " t ") {"
    print "    for j in 0..n {"
    print "        let mut acc: " t " = k;"
    print "        for q in 0.." Q[id] " {"
    print "            acc = acc " op " " elem_expr(t, 1 + rnd(2), 2, load) ";"
    print "        }"
    print "        *out.add(j as usize) = acc;"
    print "    }"
    print "}"
    KIND[id] = "nested"
}

function fill(name, t, len,    s) {
    s = rnd(1000)
    print "    let mut " name ": [" t "; " len "] = [0 as " t "; " len "];"
    print "    for i in 0.." len " {"
    if (is_float(t)) {
        print "        " name "[i as usize] = ((i * " (7 + rnd(90)) " + " s ") % 97) as " t " * 0.25 - 3.0;"
    } else {
        print "        " name "[i as usize] = ((i * " (7 + rnd(9000)) " + " s ") % 100003 - 50000) as " t ";"
    }
    print "    }"
}

function show(name, t, len) {
    print "    for i in 0.." len " {"
    if (is_float(t)) {
        print "        unsafe { printf(c\"%.17g,\", " name "[i as usize] as f64); }"
    } else {
        print "        unsafe { printf(c\"%lld,\", " name "[i as usize] as i64); }"
    }
    print "    }"
    print "    unsafe { printf(c\"\\n\"); }"
}

# The range `z + lo .. hi` of a slice expression (z: 0 at run time).
function range(lo, hi) { return "(z + " lo ") as usize.." hi }

# Overlapping slices of one array, one of them written (0.28). The
# borrow checker refuses `k(&a[..], &mut a[..])`, and a kernel of
# `&[T]` and `&mut [T]` parameters is compiled knowing them apart (its
# run-time overlap tests are dropped), so the overlapping calls go to
# the kernel's twin of raw pointers (kNp: the same statement through
# `*a.add(i)`), where the vectorizer's run-time tests stay. Each slice
# is still taken as before (its bounds check runs, in the same order;
# raw_view prints that) and its pointer is passed. Explicit vector code
# reads slices only: its overlapping call is gone.
function raw_view(i, name, r, mut) {
    print "        let p" i " = " (mut ? "(&mut " : "(&") name "[" r "])" (mut ? ".as_mut_ptr();" : ".as_ptr();")
}

# The statement st over slices a, b, out as one over raw pointers.
function raw_form(st) {
    gsub(/a\[/, "*a.add(", st)
    gsub(/b\[/, "*b.add(", st)
    sub(/^out\[/, "*out.add(", st)
    gsub(/\]/, ")", st)
    return st
}

function max3(a, b, c) { return a > b ? (a > c ? a : c) : (b > c ? b : c) }

BEGIN {
    srand(seed)
    NT = split("i8 i16 i32 i64 u8 u16 u32 u64 f32 f64", TYPES, " ")
    print "// Generated by tests/fuzz/genvec.awk, seed " seed "."
    print "extern \"C\" {"
    print "    fn printf(f: *const u8, ...) -> i32;"
    print "}"
    print ""
    # Z: 0, but not known to the compiler (bounds stay run-time values).
    print "static mut Z: i64 = 0;"
    print ""
    nk = 3 + rnd(4)
    for (id = 0; id < nk; id++) {
        T[id] = TYPES[1 + rnd(NT)]
        k = rnd(10)
        if (k <= 1) reduction_kernel(id, T[id])
        else if (k == 2) nested_kernel(id, T[id])
        else if (k <= 5) map_kernel(id, T[id])
        else if (k <= 7) stencil_kernel(id, T[id])
        else {
            # (Vector types have signed lanes.)
            if (substr(T[id], 1, 1) == "u") T[id] = "i" substr(T[id], 2)
            explicit_kernel(id, T[id])
        }
        print ""
    }
    print "fn main() -> i32 {"
    print "    unsafe { Z = printf(c\"\") as i64; }"
    print "    let z = unsafe { Z };"
    for (id = 0; id < nk; id++) {
        t = T[id]
        len = 1 + rnd(70)
        if (KIND[id] == "nested") len = Q[id] * W[id] + W[id]
        LEN[id] = len
        fill("a" id, t, len)
        fill("b" id, t, len)
        fill("c" id, t, len)
    }
    # The last call may stop with a failed bounds check.
    for (id = 0; id < nk; id++) {
        t = T[id]
        len = LEN[id]
        kv = "(" literal(t) " as " t ")"
        short = id == nk - 1 && rnd(4) == 0
        la = rnd(4); lb = rnd(4); lc = rnd(4)
        if (la > len) la = len
        if (lb > len) lb = len
        if (lc > len) lc = len
        minlen = len - max3(la, lb, lc)
        if (KIND[id] == "nested") {
            # out: c, or (now and then) a itself at an offset; n up to W.
            n = rnd(W[id] + 1)
            o = rnd(3) == 0 ? "a" id ".as_mut_ptr().add(" rnd(W[id]) ")" : "c" id ".as_mut_ptr()"
            print "    unsafe { k" id "(a" id ".as_ptr(), b" id ".as_ptr(), " o ", z + " n ", " kv "); }"
            show("a" id, t, W[id])
            show("c" id, t, W[id])
        } else if (KIND[id] == "reduce") {
            hi = len - rnd(3)
            if (hi < la) hi = la
            print "    unsafe { printf(c\"k" id " %lld\\n\", k" id "(&a" id "[" range(la, "(z + " hi ") as usize") "], " kv ") as i64); }"
            if (is_float(t)) {
                print "    unsafe { printf(c\"k" id "f %.17g\\n\", k" id "(&b" id "[" range(la, "(z + " hi ") as usize") "], " kv ") as f64); }"
            }
        } else if (KIND[id] == "map") {
            n = short ? minlen + 2 : minlen - 1 - rnd(3)
            if (n < 0) n = 0
            print "    k" id "(&a" id "[" range(la, len) "], &b" id "[" range(lb, len) "], &mut c" id "[" range(lc, len) "], z + " n ", " kv ");"
            d = rnd(3); e = rnd(3)
            n = len - (d > e ? d : e) - 2
            if (n < 0) n = 0
            if (!short && TWIN[id]) {
                print "    {"
                raw_view(0, "a" id, range(0, "(z + " len ") as usize"), 0)
                raw_view(1, "a" id, range(d, len), 0)
                raw_view(2, "a" id, range(e, len), 1)
                print "        unsafe { k" id "p(p0, p1, p2, z + " n ", " kv "); }"
                print "    }"
            }
            show("a" id, t, len)
            show("c" id, t, len)
        } else {
            n = short ? minlen + 2 : minlen - rnd(2)
            if (n < 0) n = 0
            print "    k" id "(&a" id "[" range(la, len) "], &mut c" id "[" range(lc, len) "], z + " n ", " kv ");"
            d = rnd(3)
            if (!short && len > d) {
                print "    {"
                raw_view(0, "c" id, range(0, "(z + " len ") as usize"), 0)
                raw_view(1, "c" id, range(d, len), 1)
                print "        unsafe { k" id "p(p0, p1, z + " len - d ", " kv "); }"
                print "    }"
            }
            show("c" id, t, len)
        }
    }
    print "    0"
    print "}"
}
