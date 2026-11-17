#!/bin/sh
# RULE: C4 (0.30.2, the re-review 3 of g302holes, CAUSED) Types that share
# and refer back, `struct Ni<'a> { r: Option<&'a N0<'a>>, a: Ni+1<'a>, b:
# Ni+1<'a> }`, 40 deep, read from a static and matched: what each type may
# hold (effects/provenance.vl holds_ptr, refs=false) was walked 2^depth
# times, as no answer that met a type the walk was in was kept (28 deep
# 33 s, 30 deep over 60 s; v0.30.1 0.1 s). Now each type is walked once
# (holds_in, Tarjan's components). A shell case because the compiler may
# not end: it gets 60 s, and the program must build and print n. (The same
# types printed, or read from a union's field, are slow in
# effects/infer.vl holds_formatter, on v0.30.1 too: another walk, its own
# finding.)
# Usage: rt_038k_holds_back_edges_compile_time.sh VOLEC
V=$1
case "$V" in /*) ;; *) V="$PWD/$V" ;; esac
w=$(mktemp -d "${TMPDIR:-/tmp}/rt038k.XXXXXX")
trap 'rm -rf "$w"' EXIT
d=40
{
    i=0
    while [ $i -lt $d ]; do
        echo "struct N$i<'a> { r: Option<&'a N0<'a>>, a: N$((i + 1))<'a>, b: N$((i + 1))<'a> }"
        i=$((i + 1))
    done
    echo "struct N$d<'a> { r: Option<&'a N0<'a>>, v: i64 }"
    echo "static S: Option<&'static N0<'static>> = None;"
    echo 'fn main() { let x = S; match x { None => { println("n"); } Some(_) => {} } }'
} > "$w/main.vl"
VOLE_CACHE=off perl -e 'alarm 60; exec @ARGV' "$V" "$w/main.vl" -o "$w/main" > "$w/out" 2>&1
rc=$?
if [ $rc -ge 128 ]; then echo "FAIL: the compiler did not end within 60 s"; exit 1; fi
if [ $rc -ne 0 ]; then echo "FAIL: not built (rc $rc):"; head -5 "$w/out"; exit 1; fi
out=$("$w/main")
if [ "$out" = "n" ]; then echo "ok: built and printed n"; exit 0; fi
echo "FAIL: printed '$out', not n"; exit 1
