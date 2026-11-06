#!/bin/sh
# The borrow checker's verdict cache (0.27.2, borrowck.md Z7): a std
# body's clean verdict kept in the tools' cache directory. A rust program
# on std2 is checked twice with $VOLE_CACHE set to a new directory: the
# first run writes a bck-*.bin file, the second reads it, and both print
# the same diagnostics; a program with a borrowck error in its own body
# reports it on the second run too (only clean verdicts are kept, and
# only std's).
#
# usage: tests/std2/cache.sh [-c COMPILER]
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
C="$ROOT/target/volec"
[ "${1:-}" = "-c" ] && C=$2
case "$C" in /*) ;; *) C="$(pwd)/$C" ;; esac
[ -x "$C" ] || { echo "std2-cache: no compiler at $C"; exit 2; }
T=$(mktemp -d "${TMPDIR:-/tmp}/std2cache.XXXXXX")
trap 'rm -rf "$T"' EXIT
fail=0
cat > "$T/ok.vl" <<'EOF'
// EDITION: rust
fn main(gpa: Gpa) {
    let v = Vec::from_in([3i64, 1, 2], gpa);
    let s = String::from_in("abc", gpa);
    println("{:?} {} {:?}", v.iter().max(), s.len(), v.iter().last());
}
EOF
cat > "$T/err.vl" <<'EOF'
// EDITION: rust
fn main(gpa: Gpa) {
    let mut v = Vec::from_in([3i64, 1, 2], gpa);
    let r = &v[0];
    v.push(4);
    println("{}", r);
}
EOF
for p in ok err; do
    (cd "$T" && VOLE_CACHE="$T/cache" "$C" check "$p.vl" > "$T/$p.1" 2>&1)
    (cd "$T" && VOLE_CACHE="$T/cache" "$C" check "$p.vl" > "$T/$p.2" 2>&1)
    if ! cmp -s "$T/$p.1" "$T/$p.2"; then
        echo "std2-cache: FAIL: $p.vl's diagnostics differ on the cached run"
        diff "$T/$p.1" "$T/$p.2" | head -10
        fail=1
    fi
done
if ! ls "$T/cache"/bck-*.bin > /dev/null 2>&1; then
    echo "std2-cache: FAIL: no verdict cache file written"
    fail=1
fi
grep -q 'error\[borrowck.conflict\]' "$T/err.2" || {
    echo "std2-cache: FAIL: err.vl's borrowck.conflict missing on the cached run"
    fail=1
}
grep -q '^ok: ' "$T/ok.2" || { echo "std2-cache: FAIL: ok.vl does not check clean"; cat "$T/ok.2" | head -5; fail=1; }
[ $fail -eq 0 ] && echo "std2-cache: ok"
exit $fail
