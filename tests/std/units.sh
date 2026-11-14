#!/bin/sh
# std lexed by its units (0.27.5, front-rust.md Z5.2): the index embed.sh
# writes (stdsrc.vl: std_units) is the one the compiler makes of
# the tree's std (embed.sh -c with this compiler), and a
# build that reads it keeps the tokens the build that lexes std whole
# keeps (VOLE_STD_INDEX=0): the same, in the same order, on a set of
# programs. Each build must pass without the eager rerun (a lazy build
# with errors is made again whole, which would hide a wrong index), and
# its program prints what the other's prints.
#
# usage: tests/std/units.sh [-c COMPILER]
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
C="$ROOT/target/volec"
[ "${1:-}" = "-c" ] && C=$2
case "$C" in /*) ;; *) C="$(pwd)/$C" ;; esac
[ -x "$C" ] || { echo "std-units: no compiler at $C"; exit 2; }
T=$(mktemp -d "${TMPDIR:-/tmp}/stdunits.XXXXXX")
trap 'rm -rf "$T"' EXIT
fail=0

# The index is this compiler's (when it can make one: else embed.sh -c
# compares the rest, and the builds below read no index).
if ! (cd "$ROOT" && VOLE_EMBED_VOLEC="$C" sh compiler/std/embed.sh -c); then
    echo "FAIL std-units: stdsrc.vl's std_units is stale (compiler/std/embed.sh)"
    fail=1
fi
if ! "$C" __std-index /dev/null 2>/dev/null | grep -q '^std-units '; then
    echo "std-units: $C makes no index (before 0.27.5): the token comparison skipped"
    exit $fail
fi

# A program of two files, a module file and an inline module, for the
# order of the modules.
mkdir -p "$T/multi"
cat > "$T/multi/main.vl" <<'EOF'
mod util;

mod inner {
    pub fn twice(x: i64) -> i64 {
        x * 2
    }
}

fn main(gpa: Gpa) {
    let v = Vec::from_in([3i64, 1, 2], gpa);
    println("{} {}", util::total(v.as_slice()), inner::twice(4));
}
EOF
cat > "$T/multi/util.vl" <<'EOF'
pub fn total(v: &[i64]) -> i64 {
    v.iter().sum()
}
EOF
cat > "$T/hello.vl" <<'EOF'
fn main() {
    println("hello");
}
EOF

n=0
for p in "$T/hello.vl" "$T/multi/main.vl" "$ROOT/tests/cost/std_heavy.vl" \
    "$ROOT/tests/run/rust_f_f19_use_self_ok.vl" \
    "$ROOT/tests/run/rust_f_f24_crate_ok.vl" "$ROOT/tests/run/std_alloc_arena.vl"; do
    [ -f "$p" ] || { echo "FAIL std-units: no program $p"; fail=1; continue; }
    name=$(basename "$(dirname "$p")")_$(basename "$p" .vl)
    for way in index tokens; do
        off=1
        [ "$way" = tokens ] && off=0
        if ! VOLE_CACHE=off VOLE_STD_NORERUN=1 VOLE_STD_INDEX=$off VOLE_STD_DUMP="$T/$name.$way" \
            "$C" "$p" -o "$T/$name.$way.bin" > "$T/$name.$way.out" 2>&1; then
            echo "FAIL std-units: $name ($way) does not build: $(head -3 "$T/$name.$way.out")"
            fail=1
            continue 2
        fi
        "$T/$name.$way.bin" > "$T/$name.$way.run" 2>&1 < /dev/null
    done
    if [ "$(head -1 "$T/$name.index")" != by-index ] || [ "$(head -1 "$T/$name.tokens")" != by-tokens ]; then
        echo "FAIL std-units: $name: the builds read std as $(head -1 "$T/$name.index") and $(head -1 "$T/$name.tokens") (by-index and by-tokens expected: with by-tokens first, stdsrc.vl's std_units is empty or stale; try: compiler/std/embed.sh, with target/volec of 0.27.5 or later)"
        fail=1
        continue
    fi
    sed 1d "$T/$name.index" > "$T/$name.index.body"
    sed 1d "$T/$name.tokens" > "$T/$name.tokens.body"
    if ! cmp -s "$T/$name.index.body" "$T/$name.tokens.body"; then
        echo "FAIL std-units: $name: the tokens kept differ by the index and whole (first difference, kind start end joint [value]):"
        diff "$T/$name.index.body" "$T/$name.tokens.body" | head -6
        fail=1
        continue
    fi
    if ! cmp -s "$T/$name.index.run" "$T/$name.tokens.run"; then
        echo "FAIL std-units: $name prints differently built by the index"
        fail=1
        continue
    fi
    n=$((n + 1))
done
[ $fail = 0 ] && echo "std-units: ok ($n programs: the same tokens by the index as whole)"
exit $fail
