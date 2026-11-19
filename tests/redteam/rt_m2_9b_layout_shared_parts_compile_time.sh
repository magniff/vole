#!/bin/sh
# (0.30.2, from RT-M2-9's fix) The size of a type whose parts are shared,
# asked by the checker of every tuple, array, struct, enum and instance it
# makes (check::too_big_begin): a type not laid out yet was laid out as a
# tree, each part again for each path to it, 2^depth parts (30 nested
# pairs: 41 s of `volec check`). Each part is laid out once per question
# now (front::types::LayoutMemo). Each program must be checked or built
# within 10 s, and print the sizes the layout rules give (by formula: a
# level holds two of the next):
# - 40 nested pairs of values, with a type error (check only);
# - 29 levels of `([T; 3], T)`, with a type error (check only);
# - 40 levels of structs, Rust's order and #[repr(C)], `{ a: N, c: u8, b: N }`:
#   12 * 2^40 - 4 bytes;
# - 40 levels of a Rust enum and a #[repr(C)] one, `A(E, u8, E), B(E), C`:
#   4 * 2^40 - 2 and 16 * 2^40 - 8 bytes;
# - 30 levels of #[repr(wgsl)] structs (their fields' WGSL alignment):
#   16 * 2^30 bytes.
# Usage: rt_m2_9b_layout_shared_parts_compile_time.sh VOLEC
V=${1:-volec}
case "$V" in */*) V=$(cd "$(dirname "$V")" && pwd)/$(basename "$V") ;; esac
w=$(mktemp -d "${TMPDIR:-/tmp}/rtm29b.XXXXXX")
trap 'rm -rf "$w"' EXIT
cd "$w" || exit 1
fail=0

# $1 name, $2 the levels, $3 the form: writes $1.vl
gen() {
    d=$2
    case $3 in
    pairs | arrays)
        echo 'fn main() {'
        echo '    let a0 = (1u8, 2u16);'
        i=1
        while [ $i -le $d ]; do
            p=a$((i - 1))
            if [ $3 = pairs ]; then echo "    let a$i = ($p, $p);"; else echo "    let a$i = ([$p; 3], $p);"; fi
            i=$((i + 1))
        done
        echo "    let x = a$d.1;"
        echo '    let z: bool = 1u8;'
        echo '}'
        ;;
    structs)
        for r in '' '#[repr(C)] '; do
            k=${r:+C}
            i=0
            while [ $i -lt $d ]; do
                echo "${r}struct N$k$i { a: N$k$((i + 1)), c: u8, b: N$k$((i + 1)) }"
                i=$((i + 1))
            done
            echo "${r}struct N$k$d { v: u8, w: u32 }"
        done
        echo 'fn main() {'
        echo '    println("{} {}", std::mem::size_of::<N0>(), std::mem::align_of::<N0>());'
        echo '    println("{} {}", std::mem::size_of::<NC0>(), std::mem::align_of::<NC0>());'
        echo '}'
        ;;
    enums)
        for r in '' '#[repr(C)] '; do
            k=${r:+C}
            i=0
            while [ $i -lt $d ]; do
                echo "${r}enum E$k$i { A(E$k$((i + 1)), u8, E$k$((i + 1))), B(E$k$((i + 1))), C }"
                i=$((i + 1))
            done
            echo "${r}enum E$k$d { X(u8), Y }"
        done
        echo 'fn main() {'
        echo '    println("{} {}", std::mem::size_of::<E0>(), std::mem::align_of::<E0>());'
        echo '    println("{} {}", std::mem::size_of::<EC0>(), std::mem::align_of::<EC0>());'
        echo '}'
        ;;
    wgsl)
        i=0
        while [ $i -lt $d ]; do
            echo "#[repr(wgsl)] struct N$i { a: N$((i + 1)), b: N$((i + 1)) }"
            i=$((i + 1))
        done
        echo "#[repr(wgsl)] struct N$d { v: [f32; 3], w: f32 }"
        echo 'fn main() { println("{} {}", std::mem::size_of::<N0>(), std::mem::align_of::<N0>()); }'
        ;;
    esac > "$1.vl"
}

# $1 name: `volec check` must end within 10 s with the bool error
check_err() {
    VOLE_CACHE=off perl -e 'alarm 10; exec @ARGV' "$V" check "$1.vl" > "$1.out" 2>&1
    rc=$?
    if [ $rc -ne 1 ]; then echo "FAIL $1: check did not end within 10 s with an error (rc $rc)"; tail -3 "$1.out" | cut -c1-200; fail=1; return; fi
    if ! grep -q "expected 'bool', got 'u8'" "$1.out"; then echo "FAIL $1: not the bool error:"; tail -3 "$1.out" | cut -c1-200; fail=1; fi
}

# $1 name, $2 the output expected: built at -O0 within 10 s, run
build_run() {
    VOLE_CACHE=off perl -e 'alarm 10; exec @ARGV' "$V" "$1.vl" -O0 -o "$1" > "$1.out" 2>&1
    rc=$?
    if [ $rc -ne 0 ]; then echo "FAIL $1: not built within 10 s (rc $rc)"; tail -3 "$1.out" | cut -c1-200; fail=1; return; fi
    out=$("./$1" | tr '\n' ' ')
    if [ "$out" != "$2" ]; then echo "FAIL $1: printed '$out', not '$2'"; fail=1; fi
}

gen pairs 40 pairs
check_err pairs
gen arrays 29 arrays
check_err arrays
gen structs 40 structs
build_run structs "13194139533308 4 13194139533308 4 "
gen enums 40 enums
build_run enums "4398046511102 1 17592186044408 4 "
gen wgsl 30 wgsl
build_run wgsl "17179869184 16 "
[ $fail -eq 0 ] && echo "ok: every program in time, the sizes right"
exit $fail
