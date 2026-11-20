#!/bin/sh
# XFAIL: RT-307: "cannot infer the type of closure parameter 'z'" always helps with "write its type: '|z: i64| ...'", for a parameter the later call makes a T, a W or a &str (0.30.2)
# rustc E0282 at each closure (type annotations needed), with the help
# `|z: /* Type */|`. vole's help is a fixed text: infer_param_error
# (front/closures/mod.vl) writes `: i64|` (and `|_: i64|`, `|(a, b): (i64,
# i64)|` for the pattern forms) whatever the parameter is, so the try
# leads to a second type error. v0.28.0 to v0.30.1 the same.
V=${1:-volec}
case "$V" in */*) V=$(cd "$(dirname "$V")" && pwd)/$(basename "$V") ;; esac
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
cat > "$w/main.vl" <<'VL'
trait Tag {
    fn tag(&self) -> i64;
}

#[derive(Clone, Copy)]
struct W {
    k: i64,
}

impl Tag for W {
    fn tag(&self) -> i64 {
        self.k
    }
}

fn d<T: Tag + Copy>(x: T) -> i64 {
    let f = |z| z.tag();
    f(x)
}

fn e(x: W) -> i64 {
    let f = |z| z.tag();
    f(x)
}

fn g(x: &str) -> usize {
    let f = |z| z.len();
    f(x)
}

fn h(x: (W, W)) -> i64 {
    let f = |(a, b)| a.tag() + b.tag();
    f(x)
}

fn main() {
    let w = W { k: 3 };
    println("{} {} {} {}", d(w), e(w), g("ab"), h((w, w)));
}
VL
out=$(cd "$w" && VOLE_CACHE=off "$V" check main.vl 2>&1)
st=0
n=$(printf '%s\n' "$out" | grep -c 'cannot infer the type of')
if [ "$n" -ne 4 ]; then
    echo "FAIL: $n 'cannot infer the type of' errors, want 4 (lines 17, 22, 27, 32)"
    st=1
fi
if printf '%s\n' "$out" | grep -q 'i64)\{0,1\}| \.\.\.'; then
    echo "FAIL: the help names i64 for parameters that are T, W, &str and (W, W):"
    printf '%s\n' "$out" | grep -o "help: write its type: '[^']*'"
    st=1
fi
[ $st -eq 0 ] && echo ok
exit $st
