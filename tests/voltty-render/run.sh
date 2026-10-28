#!/bin/sh
# voltty's renderer's headless tests (0.23, terminal.md §4.1): the
# Core Text atlas (metrics, the 95 ASCII glyphs and their time, fallback,
# colour emoji, coverage against ref/*.pgm), and a grid rendered to a
# texture through Metal, compared with the CPU reference renderer
# (cpu.vl) and with ref/golden-block.ppm; damage tracking (rows rebuilt
# and copied, images equal to a full redraw); the bench (prints, and its
# encode budget). main.vl is built at -O2 at every suite level (std links
# its frameworks; the budgets are -O2's) and run
# from the root. macOS only: elsewhere every check is skipped (the Linux
# renderer, FreeType and Vulkan, is another task).
#
# usage: tests/voltty-render/run.sh [-c COMPILER] [-v]
#   -v   print the bench lines too
#
# Prints `pass NAME` or `FAIL NAME` (and why) for each check, or `skip
# NAME: why` (0.25.2: no GPU; a time budget missed on a loaded machine,
# tests/budget.sh: the glyphs' raster time, the full redraw's encode;
# on an idle machine that is a FAIL). Exits 1 if one failed.

set -u
LC_ALL=C
export LC_ALL

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
COMPILER="$ROOT/target/volec"
VERBOSE=0
while [ $# -gt 0 ]; do
    case "$1" in
        -c) [ $# -ge 2 ] || exit 2; COMPILER=$2; shift 2 ;;
        -v) VERBOSE=1; shift ;;
        *) echo "usage: tests/voltty-render/run.sh [-c COMPILER] [-v]" >&2; exit 2 ;;
    esac
done
case "$COMPILER" in
    /*) ;;
    *) COMPILER="$(pwd)/$COMPILER" ;;
esac

if [ "$(uname -s)" != Darwin ]; then
    echo "pass voltty_render (skipped: macOS only)"
    exit 0
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/vole-voltty-render.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
trap 'exit 130' INT TERM

# render/cells.vl is render/cells.wgsl's text (render/embed.sh)
if "$ROOT/examples/voltty/render/embed.sh" --check; then
    echo "pass voltty_render_cells_embedded"
else
    echo "FAIL voltty_render_cells_embedded: run examples/voltty/render/embed.sh"
fi

if ! (cd "$ROOT" && "$COMPILER" -O2 tests/voltty-render/main.vl -o "$WORK/prog") \
        >"$WORK/build.out" 2>&1; then
    echo "FAIL voltty_render_build:"
    head -20 "$WORK/build.out" | sed 's/^/    /'
    exit 1
fi
(cd "$ROOT" && "$WORK/prog") >"$WORK/run.out" 2>&1
status=$?
[ "$VERBOSE" = 1 ] && grep '^bench' "$WORK/run.out"
awk '
    /^ok / { print "pass voltty_render_" $2; next }
    /^FAIL / { sub(/^FAIL /, ""); print "FAIL voltty_render_" $0; bad = 1; next }
    /^skip / { sub(/^skip /, ""); print "skip voltty_render_" $0; next }
' "$WORK/run.out"
# (0.25.2) the time budgets missed: FAIL when idle, SKIP when loaded
sh "$ROOT/tests/budget.sh" voltty_render_ "$WORK/run.out" || status=1
if [ $status -ne 0 ] && ! grep -q -e '^FAIL' -e '^slow' "$WORK/run.out"; then
    echo "FAIL voltty_render_run: exit $status"
    tail -5 "$WORK/run.out" | sed 's/^/    /'
    exit 1
fi
[ $status -eq 0 ]
