#!/bin/sh
# XFAIL: RT-375: the borrowck.move_out try for `for &s in v.iter()` (s a String) is `edit patch --old 'for &s in v.iter() {' --new 'for ref &s in v.iter() {'`, which does not parse: the edit is refused (edit.breaks: expected 'in', got '&') and its own try is the same edit with --no-check (0.30.2)
# rustc E0507 (cannot move out of a shared reference), with the help to
# remove the `&` (`for s in v.iter()`). vole's try writes `ref &s`, which
# neither vole nor Rust parses; following its --no-check try writes a file
# that does not parse. v0.28.0 to v0.30.1 the same (`--new 'for ref &s
# in v.iter() {'`). This case applies the check's try: as printed and
# wants the program to check clean after it.
V=${1:-volec}
case "$V" in */*) V=$(cd "$(dirname "$V")" && pwd)/$(basename "$V") ;; esac
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
cat > "$w/main.vl" <<'VL'
fn take3(v: &Vec<String<Gpa>, Gpa>) -> usize {
    for &s in v.iter() {
        return s.len();
    }
    0
}

fn main(gpa: Gpa) {
    let mut v: Vec<String<Gpa>, Gpa> = Vec::new_in(gpa);
    v.push(String::from_in("abc", gpa));
    println("{}", take3(&v));
}
VL
out=$(cd "$w" && VOLE_CACHE=off "$V" check main.vl 2>&1)
if ! printf '%s\n' "$out" | grep -q 'borrowck.move_out'; then
    echo "FAIL: no borrowck.move_out error at line 2"; exit 1
fi
new=$(printf '%s\n' "$out" | grep -o "\-\-new '[^']*'" | head -1 | sed "s/^--new '//; s/'\$//")
old=$(printf '%s\n' "$out" | grep -o "\-\-old '[^']*'" | head -1 | sed "s/^--old '//; s/'\$//")
if [ -z "$new" ]; then
    echo "FAIL: no try: with an edit patch"; exit 1
fi
res=$(cd "$w" && VOLE_CACHE=off "$V" edit patch --at main.vl:2 --old "$old" --new "$new" 2>&1)
st=$?
if [ $st -ne 0 ]; then
    echo "FAIL: the try's edit (--new '$new') is refused:"
    printf '%s\n' "$res" | head -3
    exit 1
fi
chk=$(cd "$w" && VOLE_CACHE=off "$V" check main.vl 2>&1)
case "$chk" in ok:*) echo ok; exit 0 ;; esac
echo "FAIL: after the try's edit the program does not check:"; printf '%s\n' "$chk" | head -3
exit 1
