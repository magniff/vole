#!/bin/sh
# XFAIL: RT-85: --emit-header writes `struct G<i64>` for a generic #[repr(C)] struct: the header it says it wrote is not C (0.30.2)
# RT-85: an extern "C" fn taking a generic #[repr(C)] struct by value
# (G<i64>, G2<f64>): --emit-header prints `ok: wrote` and the header
# names `struct G<i64>`, which no C compiler accepts. Passes when the
# header compiles with cc, or when --emit-header refuses with an error.
# Usage: rt_085_emit_header_generic.sh VOLEC (default volec).
V=${1:-volec}
case "$V" in */*) V=$(cd "$(dirname "$V")" && pwd)/$(basename "$V") ;; esac
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
cat > "$w/main.vl" <<'VL'
#[repr(C)]
pub struct G<T> {
    pub t: T,
}

#[repr(C)]
pub struct G2<T> {
    pub a: u8,
    pub t: T,
}

pub extern "C" fn fa(g: G<i64>, h: G2<f64>) -> i64 {
    g.t + h.a as i64 + h.t as i64
}

fn main() {
    println("{}", fa(G { t: 1 }, G2 { a: 2, t: 3.0 }));
}
VL
cd "$w" || exit 2
if ! "$V" --emit-header main.vl -o main.h > emit.out 2>&1; then
    grep -q 'error' emit.out && { echo "ok: --emit-header refuses: $(grep -m1 error emit.out)"; exit 0; }
    echo "FAIL: --emit-header failed without an error: $(head -1 emit.out)"; exit 1
fi
printf '#include "main.h"\nint main(void) { return 0; }\n' > u.c
if cc -c u.c -o u.o 2> cc.out; then echo "ok: the header compiles"; exit 0; fi
echo "FAIL: the header does not compile: $(grep -m1 error cc.out)"
exit 1
