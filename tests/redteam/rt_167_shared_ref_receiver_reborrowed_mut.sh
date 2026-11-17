#!/bin/sh
# XFAIL: RT-167: `(&s).g()` with `impl T1 for &mut S { fn g(self) }` must be refused (rustc E0596 at the call): 0.30.1 and the release build never end, a chain_probe build takes `&mut s` and mutates s (0.30.2)
# RT-167 (R302D-13): the probe of `&S` reaches the `&mut S` autoref step only
# through `*(&s)`, a place behind a shared reference; rustc refuses it
# (E0596: cannot borrow data in a `&` reference as mutable). A shell case
# because the compiler may not end: it gets 60 s. Passes when the compiler
# ends within them and refuses the program with an error at line 16.
# Usage: rt_167_shared_ref_receiver_reborrowed_mut.sh VOLEC
V=$1
case "$V" in /*) ;; *) V="$PWD/$V" ;; esac
w=$(mktemp -d "${TMPDIR:-/tmp}/rt167.XXXXXX")
trap 'rm -rf "$w"' EXIT
cat > "$w/main.vl" <<'VL'
struct S {
    k: i64,
}

trait T1 {
    fn g(self) -> i64;
}

impl<'a> T1 for &'a mut S {
    fn g(self) -> i64 {
        self.k += 1;
        self.k
    }
}

fn main() {
    let mut s = S { k: 1 };
    println("{}", (&s).g());
    println("{}", s.k);
}
VL
VOLE_CACHE=off perl -e 'alarm 60; exec @ARGV' "$V" check "$w/main.vl" > "$w/out" 2>&1
rc=$?
if [ $rc -ge 128 ]; then echo "FAIL: the compiler did not end within 60 s"; exit 1; fi
if grep -q 'main.vl:16:[0-9]*: error' "$w/out"; then echo "ok: refused at line 16"; exit 0; fi
echo "FAIL: not refused at line 16 (rc $rc):"; head -5 "$w/out"; exit 1
