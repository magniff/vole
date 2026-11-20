#!/bin/sh
# XFAIL: RT-429: `volec fmt /abs/path/x.vl` of a file outside the repository it runs in says it is journaled ("volec undo takes it back"), but `volec query diff` then shows the repository's previous edit and `volec undo` takes back that edit (a.vl, another file) instead of x.vl's (0.30.2)
# The agent hook check-after-edit.py fmt_new_file runs exactly this for
# every new .vl an agent writes outside the tree (cwd = the main checkout):
# its report "the hook rewrote FILE: the 50 changes above" lists the main
# checkout's last journaled edit (round 9 saw tests/run/rt_408's lines
# under a scratch file's name, twice), and its "volec undo takes it back"
# would revert that edit in the main checkout. v0.28.0 to v0.30.1 the same. This case
# formats a.vl in a git repo, then x.vl outside it, and wants `undo` to
# take back x.vl's change (or to refuse), leaving a.vl formatted.
V=${1:-volec}
case "$V" in */*) V=$(cd "$(dirname "$V")" && pwd)/$(basename "$V") ;; esac
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
mkdir "$w/repo" "$w/out"
printf 'fn main() {\n    println("{}",   4);\n}\n' > "$w/repo/a.vl"
printf 'fn main() {\n    println("{}",   9);\n}\n' > "$w/out/x.vl"
(cd "$w/repo" && git init -q . && git add a.vl \
    && git -c user.name=t -c user.email=t@t commit -qm a) || { echo "FAIL: git"; exit 1; }
(cd "$w/repo" && VOLE_CACHE=off "$V" fmt a.vl >/dev/null 2>&1)
(cd "$w/repo" && VOLE_CACHE=off "$V" fmt "$w/out/x.vl" >/dev/null 2>&1)
grep -q '"{}", 9)' "$w/out/x.vl" || { echo "FAIL: x.vl was not formatted"; exit 1; }
diff=$(cd "$w/repo" && VOLE_CACHE=off "$V" query diff 2>&1)
(cd "$w/repo" && VOLE_CACHE=off "$V" undo >/dev/null 2>&1)
if ! grep -q '"{}", 4)' "$w/repo/a.vl"; then
    echo "FAIL: undo after fmt of x.vl took back a.vl's earlier edit:"
    cat "$w/repo/a.vl"
    echo "(query diff showed: $(printf '%s\n' "$diff" | head -1))"
    exit 1
fi
echo "ok"
exit 0
