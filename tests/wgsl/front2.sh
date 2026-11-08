#!/bin/sh
# (0.27.6) std2's std::gpu::wgsl front against MVS's: every .wgsl file of
# the tree (tests/, examples/) checked by tools/wgslc (`wgslc check`, MVS
# std's shader compiler) and by tests/wgsl/front2 (std2's front and
# uniformity, the half `embed wgsl` checks with). Each file's verdict,
# `NAME: ok` or its error and help lines (the path as its name; wgslc's
# `try:` lines aside), must be the same.
#
# usage: tests/wgsl/front2.sh [-c COMPILER]
#
# Prints `pass NAME` or `FAIL NAME` (both outputs) for each, then
# `wgsl-front2: N files, D differ`; exits 1 if one differs.
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
COMPILER="$ROOT/target/volec"
if [ "$1" = "-c" ]; then
    COMPILER=$2
fi
WORK=$(mktemp -d "${TMPDIR:-/tmp}/wgsl-front2.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
if ! "$COMPILER" "$ROOT/tools/wgslc/main.vl" -o "$WORK/wgslc" >"$WORK/build.out" 2>&1; then
    echo "FAIL wgslc: does not build"
    cat "$WORK/build.out"
    exit 1
fi
if ! "$COMPILER" "$ROOT/tests/wgsl/front2/main.vl" -o "$WORK/front2" >"$WORK/build.out" 2>&1; then
    echo "FAIL front2: does not build"
    cat "$WORK/build.out"
    exit 1
fi
n=0
d=0
for f in $(cd "$ROOT" && find tests examples -name '*.wgsl' | sort); do
    b=$(basename "$f")
    n=$((n + 1))
    if "$WORK/wgslc" check "$ROOT/$f" >"$WORK/mvs" 2>&1; then
        echo "$b: ok" >"$WORK/mvs"
    else
        sed -e "s|^$ROOT/$f:|$b:|" -e '/^try: /d' "$WORK/mvs" >"$WORK/mvs2"
        mv "$WORK/mvs2" "$WORK/mvs"
    fi
    "$WORK/front2" "$ROOT/$f" >"$WORK/std2" 2>&1
    if cmp -s "$WORK/mvs" "$WORK/std2"; then
        echo "pass $f"
    else
        d=$((d + 1))
        echo "FAIL $f"
        echo "  mvs:"
        sed 's/^/    /' "$WORK/mvs"
        echo "  std2:"
        sed 's/^/    /' "$WORK/std2"
    fi
done
echo "wgsl-front2: $n files, $d differ"
[ "$d" -eq 0 ]
