#!/bin/sh
# (0.30.2, the second re-review of the qualified paths) `volec fmt` reads
# a `<` or `<<` after a `}` by Rust's rule: after a block-like
# expression that is an operand (`let c = unsafe { a } < b as i64`, a
# `match`, an `if .. else`, a block, a closure's body) it compares or
# shifts; after one that is a whole statement (`if t { .. } <S as
# A>::g();`, `unsafe`, `while`, `for`, `loop`, an `if` whose head holds
# a block, an `else`) it opens a qualified path. A comment between an
# operand and the `<` changes nothing. The branch before the fix took
# every `}` for no operand: it printed `unsafe { a } <b as i64` and
# indented every later line of the block one level deeper; v0.30.1's fmt
# kept these as written. The program is formatted: fmt leaves it as it
# is, and the same text with every line's indentation removed comes back
# byte for byte; it builds and prints rustc's lines.
V=${1:-volec}
case "$V" in */*) V=$(cd "$(dirname "$V")" && pwd)/$(basename "$V") ;; esac
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
cat > "$w/main.vl" <<'VL'
trait A {
    const C: i64;
    fn g() -> i64;
}

struct S;

impl A for S {
    const C: i64 = 3;

    fn g() -> i64 {
        4
    }
}

fn f() -> i64 {
    1
}

fn main() {
    let a: i64 = 5;
    let b: u32 = 2;
    let t = true;
    let o: Option<i64> = Some(1);
    let c1 = unsafe { a } < b as i64;
    let c2 = unsafe { a } << b as i64;
    let c3 = match a {
        5 => 1,
        _ => 2,
    } < b as i64;
    let c4 = if t { 1 } else { 9 } < b as i64;
    let c5 = { a } < b as i64;
    let c6 = if let Some(v) = o { v } else { 0 } < b as i64;
    let c8 = a /* note */ < b as i64;
    let c9 = a // note
        < b as i64;
    let k = || { a } < b as i64;
    println("{} {} {} {} {} {} {} {} {}", c1, c2, c3, c4, c5, c6, c8, c9, k());
    if t {
        f();
    } <S as A>::g();
    unsafe {
        f();
    } <S as A>::g();
    let mut i = 0;
    while i < 2 {
        i += 1;
    } <S as A>::g();
    if unsafe { t } {
        f();
    } <S as A>::g();
    for _ in 0..1 {
        f();
    } <S as A>::g();
    loop {
        break;
    } <S as A>::g();
    if t {
        f();
    } else {
        f();
    } <S as A>::g();
    let n = { <S as A>::C } + <S as A>::C;
    println("{}", n);
}
VL
cd "$w" || exit 1
cp main.vl orig.vl
VOLE_CACHE=off perl -e 'alarm 20; exec @ARGV' "$V" check main.vl > check.txt 2>&1 || { echo "the program does not check:"; cat check.txt; exit 1; }
perl -e 'alarm 20; exec @ARGV' "$V" fmt main.vl > fmt.txt 2>&1 || { echo "fmt failed:"; cat fmt.txt; exit 1; }
if ! cmp -s orig.vl main.vl; then echo "fmt changed what was written:"; diff orig.vl main.vl; exit 1; fi
sed 's/^ *//' orig.vl > flat.vl
perl -e 'alarm 20; exec @ARGV' "$V" fmt flat.vl > fmt2.txt 2>&1 || { echo "fmt of the unindented copy failed:"; cat fmt2.txt; exit 1; }
if ! cmp -s orig.vl flat.vl; then echo "the unindented copy formats to other text:"; diff orig.vl flat.vl; exit 1; fi
VOLE_CACHE=off perl -e 'alarm 20; exec @ARGV' "$V" main.vl -o prog > build.txt 2>&1 || { echo "the program does not build:"; cat build.txt; exit 1; }
out=$(./prog | tr '\n' '|')
want="false 20 true true false true false false false|6|"
if [ "$out" != "$want" ]; then echo "printed '$out', rustc prints '$want'"; exit 1; fi
exit 0
