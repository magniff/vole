#!/bin/sh
# (0.30.2, the re-review of the qualified paths) `volec fmt` prints each
# qualified path as written and keeps the indentation of the lines after
# it: a self type that is not a name (`<&S as T1>::h`, `<[i64] as Z>::z`,
# `<W<i64> as Conv<bool>>::c`), a turbofish or type arguments that open
# with one (`id::<<<S as A>::Out as B>::E>(5)`, `Option<<<S as A>::Out as
# B>::E>`, `id::< <S as A>::Out>()`), one after a `,` written spaced (`f(a,
# < <S as A>::Out as B>::make())`), and shifts beside them. The branch
# before the fix printed `< &S as T1 >::h`, `< W<i64> as Conv<bool >>::c`
# (and indented every later line of the block 4 more) and `id::<< <S`.
# The program parses (fmt is never run here on one that does not: RT-276);
# formatted, it is unchanged, and it builds and prints rustc's line.
V=${1:-volec}
case "$V" in */*) V=$(cd "$(dirname "$V")" && pwd)/$(basename "$V") ;; esac
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
cat > "$w/main.vl" <<'VL'
trait T1 {
    fn h(&self) -> i64;
}

trait Z {
    fn z(&self) -> i64;
}

trait A {
    type Out;
    const C: i64;
}

trait B {
    type E;
    fn make() -> i64;
}

trait Conv<T> {
    fn c(x: u8) -> Self;
}

struct S;

struct O;

struct W<U> {
    u: i64,
    p: Option<U>,
}

impl T1 for S {
    fn h(&self) -> i64 {
        1
    }
}

impl<'a> T1 for &'a S {
    fn h(&self) -> i64 {
        2
    }
}

impl Z for [i64] {
    fn z(&self) -> i64 {
        self.len() as i64
    }
}

impl A for S {
    type Out = O;
    const C: i64 = 3;
}

impl B for O {
    type E = i64;

    fn make() -> i64 {
        40
    }
}

impl<U> Conv<i64> for W<U> {
    fn c(x: u8) -> W<U> {
        W { u: 1, p: None }
    }
}

impl<U> Conv<bool> for W<U> {
    fn c(x: u8) -> W<U> {
        W { u: 2, p: None }
    }
}

fn id<T>(t: T) -> T {
    t
}

fn sz<T>() -> i64 {
    7
}

fn f(a: i64, b: i64) -> i64 {
    a + b
}

fn main() {
    let s = S;
    let v: [i64; 2] = [1, 2];
    let h = <&S as T1>::h(&&s) * 10 + <S as T1>::h(&s);
    let z = <[i64] as Z>::z(&v[..]);
    let a: W<i64> = <W<i64> as Conv<bool>>::c(1u8);
    let b: W<i64> = <W<i64> as Conv<i64>>::c(1u8);
    let e = id::<<<S as A>::Out as B>::E>(5);
    let o: Option<<<S as A>::Out as B>::E> = Some(e << 1);
    let n = sz::< <S as A>::Out>();
    let m = f(1, < <S as A>::Out as B>::make());
    let k = <S as A>::C << 2;
    println("{} {} {} {} {} {:?} {} {} {}", h, z, a.u, b.u, e, o, n, m, k);
}
VL
cd "$w" || exit 1
cp main.vl orig.vl
VOLE_CACHE=off perl -e 'alarm 20; exec @ARGV' "$V" check main.vl > check.txt 2>&1 || { echo "the program does not check:"; cat check.txt; exit 1; }
perl -e 'alarm 20; exec @ARGV' "$V" fmt main.vl > fmt.txt 2>&1 || { echo "fmt failed:"; cat fmt.txt; exit 1; }
if ! cmp -s orig.vl main.vl; then echo "fmt changed what was written:"; diff orig.vl main.vl; exit 1; fi
VOLE_CACHE=off perl -e 'alarm 20; exec @ARGV' "$V" main.vl -o prog > build.txt 2>&1 || { echo "the program does not build:"; cat build.txt; exit 1; }
out=$(./prog)
want="21 2 2 1 5 Some(10) 7 41 12"
if [ "$out" != "$want" ]; then echo "printed '$out', rustc prints '$want'"; exit 1; fi
exit 0
