#!/bin/sh
# RULE: C3.4 (0.30.2, the re-review 2 of g302holes, CAUSED) An i64 nested in
# 40 Options, no contract of its own: std's Option::unwrap has one, whose
# check asks what each type may hold (effects/provenance.vl holds_ptr).
# That walk went into an enum's type arguments and its variants' fields,
# the same types, with no answer kept inside it: 2^depth (26 deep took
# 6.4 s, 40 never ended; v0.30.1 0.05 s). A shell case because the
# compiler may not end: it gets 60 s, and the program must build and print 1.
# Usage: rt_038j_option_nest40_compile_time.sh VOLEC
V=$1
case "$V" in /*) ;; *) V="$PWD/$V" ;; esac
w=$(mktemp -d "${TMPDIR:-/tmp}/rt038j.XXXXXX")
trap 'rm -rf "$w"' EXIT
d=40
some=""
close=""
unwraps=""
i=0
while [ $i -lt $d ]; do
    some="${some}Some("
    close="${close})"
    unwraps="${unwraps}.unwrap()"
    i=$((i + 1))
done
cat > "$w/main.vl" <<VL
fn main() {
    let o = ${some}1i64${close};
    let v = o${unwraps};
    println("{}", v);
}
VL
VOLE_CACHE=off perl -e 'alarm 60; exec @ARGV' "$V" "$w/main.vl" -o "$w/main" > "$w/out" 2>&1
rc=$?
if [ $rc -ge 128 ]; then echo "FAIL: the compiler did not end within 60 s"; exit 1; fi
if [ $rc -ne 0 ]; then echo "FAIL: not built (rc $rc):"; head -5 "$w/out"; exit 1; fi
out=$("$w/main")
if [ "$out" = "1" ]; then echo "ok: built and printed 1"; exit 0; fi
echo "FAIL: printed '$out', not 1"; exit 1
