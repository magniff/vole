#!/bin/sh
# The aarch64-linux host (0.11). The bootstrap chain cannot run there (the
# Rust seed and the releases before 0.11 have no aarch64-linux backend), so
# the compiler for it is cross-built and then checked natively:
#
#   1. here (aarch64-macos, x86_64-macos or x86_64-linux):
#      bootstrap/bootstrap.sh --host aarch64-linux runs the chain and
#      cross-compiles HEAD's compiler for aarch64-linux, an object (or a
#      compiler already built and tested here, --compiler, cross-compiles
#      the tree's source; bootstrap/gate.sh does that);
#   2. in a linux/arm64 container (bootstrap/ci/linux-aarch64.Dockerfile;
#      native on Apple silicon, e.g. with colima): that object is linked,
#      the compiler builds itself, which must give the same object again
#      (its output does not depend on the host), and again (the fixpoint);
#      then its test suite runs, with the checks asked for below, at once
#      (bootstrap/gate.sh --inside), with one table at the end.
#
# usage: bootstrap/aarch64-linux-check.sh [--worktree] [checks] [bootstrap options]
#
#   --worktree     check the working tree (tracked and untracked files, not
#                  ignored ones) instead of HEAD; combine with --dev before
#                  the release tags exist
#   --compiler C   cross-compile the tree's compiler with C (a compiler of
#                  this host, built from the same tree) instead of running
#                  the chain
#   --all-levels   run the test suite at -O0, -O1 and -O2 (else at the
#                  default level)
#   --levels=L,L   run the test suite at these levels (bootstrap/gate.sh:
#                  0,2; 0.25.2: -O1 is left to macOS, the optimizer being
#                  the same for every target)
#   --smoke        (0.25.2) only the smoke-* checks of bootstrap/gate.sh
#                  (its --quick's linux-smoke row): the runner's own
#                  checks, the language server, the examples' builds,
#                  every case at -O2, the walkthroughs and the book; a
#                  few minutes
#   --fuzz=N       also run N random programs in each mode of the
#                  generator (tests/fuzz/run.sh)
#   --abi=N        also run N C interoperability programs (tests/abi/run.sh),
#                  plain, through import and through --emit-header, and
#                  check the layout of imported system headers
#   --objcheck     also check the compiler's objects against cc -c
#                  (tests/objcheck.sh)
#   --debugger     also check debug information with gdb (tests/debug.sh)
#   --valgrind     also run the compiler under valgrind's memcheck
#                  (tests/valgrind.sh, 0.18.1)
#   --only STEPS   run these checks of bootstrap/gate.sh instead (after
#                  the fixpoint), e.g. --only valgrind
#   --slice "FILTER..."  (0.25.2) run only these tests/run.sh filters
#                  instead of the checks, at each of --slice-levels
#                  "0 2" (the default): tests/affected.sh --linux
#   --cpus N       the container's CPUs (default 8, at most docker's)
#   --rebuild-image  rebuild the image even if its recipe is unchanged
#
# Other options go to bootstrap.sh, e.g. --dev.

set -eu
LC_ALL=C
export LC_ALL

ROOT=$(cd "$(dirname "$0")/.." && pwd)
IMAGE=vole-check:linux-aarch64
PLATFORM=linux/arm64
WORKTREE=0
ALL_LEVELS=0
LEVELS=""
SMOKE=0
FUZZ=0
ABI=0
OBJCHECK=0
DEBUGGER=0
VALGRIND=0
ONLY=""
SLICE=""
SLICE_LEVELS="0 2"
CPUS=8
COMPILER=""
REBUILD_IMAGE=0

die() {
    echo "aarch64-linux-check: error: $*" >&2
    exit 1
}
. "$ROOT/bootstrap/ci/common.sh"

quote() {
    printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}
rest=""
want=""
for arg in "$@"; do
    case "$want" in
        cpus) CPUS=$arg; want=""; continue ;;
        compiler) COMPILER=$arg; want=""; continue ;;
        only) ONLY=$arg; want=""; continue ;;
        slice) SLICE=$arg; want=""; continue ;;
        slice_levels) SLICE_LEVELS=$arg; want=""; continue ;;
    esac
    case "$arg" in
        --worktree) WORKTREE=1; rest="$rest --worktree" ;;
        --dev) WORKTREE=1; rest="$rest --dev" ;;
        --all-levels) ALL_LEVELS=1 ;;
        --levels=*) LEVELS=${arg#--levels=} ;;
        --smoke) SMOKE=1 ;;
        --fuzz=*) FUZZ=${arg#--fuzz=} ;;
        --abi=*) ABI=${arg#--abi=} ;;
        --objcheck) OBJCHECK=1 ;;
        --debugger) DEBUGGER=1 ;;
        --valgrind) VALGRIND=1 ;;
        --only) want=only ;;
        --only=*) ONLY=${arg#--only=} ;;
        --slice) want=slice ;;
        --slice-levels) want=slice_levels ;;
        --cpus) want=cpus ;;
        --cpus=*) CPUS=${arg#--cpus=} ;;
        --compiler) want=compiler ;;
        --compiler=*) COMPILER=${arg#--compiler=} ;;
        --rebuild-image) REBUILD_IMAGE=1 ;;
        -h|--help) awk 'NR > 1 && !/^#/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$0"; exit 0 ;;
        *) rest="$rest $(quote "$arg")" ;;
    esac
done
eval "set -- $rest"
case "$CPUS" in ''|*[!0-9]*|0) die "--cpus needs a number" ;; esac
case "$LEVELS" in *[!0-2,]*) die "--levels takes levels 0, 1 and 2, comma-separated" ;; esac
[ "$SMOKE" = 0 ] || ONLY='smoke-*'

command -v docker >/dev/null 2>&1 || die "docker not found"
command -v git >/dev/null 2>&1 || die "git not found"
docker info >/dev/null 2>&1 || die "docker is not running (with colima: colima start)"
clamp_cpus

SNAP=$(mktemp -d "${TMPDIR:-/tmp}/vole-aarch64-linux-check.XXXXXX")
trap 'stop_container; rm -rf "$SNAP"' EXIT
trap 'exit 130' INT TERM

# The tree the object is built from: HEAD, or the working tree.
snapshot "$SNAP" 0

if [ -n "$COMPILER" ]; then
    [ -x "$COMPILER" ] || die "no compiler at $COMPILER"
    echo "==> cross-compiling the compiler for aarch64-linux with $COMPILER" >&2
    "$COMPILER" --target aarch64-linux "$SNAP/src/compiler/src/main.vl" -o "$SNAP/volec.o" \
        || die "the cross-compilation failed"
else
    echo "==> the chain here, and the compiler cross-built for aarch64-linux" >&2
    sh "$ROOT/bootstrap/bootstrap.sh" --host aarch64-linux "$@"
    OBJECT="$ROOT/target/aarch64-linux/volec.o"
    [ -f "$OBJECT" ] || die "bootstrap.sh left no $OBJECT"
    cp "$OBJECT" "$SNAP/volec.o"
fi

ensure_image "$IMAGE" "$PLATFORM" "$ROOT/bootstrap/ci/linux-aarch64.Dockerfile"

echo "==> on aarch64-linux, in the container ($CPUS CPUs)" >&2
tar -C "$SNAP" -c -f - src volec.o | docker run --rm -i --name "$CONTAINER" --cpus "$CPUS" --platform "$PLATFORM" \
    -e CPUS="$CPUS" -e ALL_LEVELS="$ALL_LEVELS" -e LEVELS="$LEVELS" -e FUZZ="$FUZZ" -e ABI="$ABI" -e OBJCHECK="$OBJCHECK" \
    -e DEBUGGER="$DEBUGGER" -e VALGRIND="$VALGRIND" -e ONLY="$ONLY" \
    -e SLICE="$SLICE" -e SLICE_LEVELS="$SLICE_LEVELS" "$IMAGE" sh -c '
    set -eu
    mkdir /work
    tar -x --no-same-owner -f - -C /work
    cd /work/src
    echo "==> on $(uname -s) $(uname -m): $(cc --version | head -1)" >&2
    # A row of the table bootstrap/gate.sh prints: step, result, seconds, note.
    row() { printf "gate-row\t%s\t%s\t%s\t%s\n" "$@"; }
    fail() { # <step> <start> <why>
        row "$1" FAIL $(( $(date +%s) - $2 )) "$3"
        echo "--- $1: FAIL: $3" >&2
        exit 1
    }
    start=$(date +%s)
    mkdir -p target/native
    n=target/native
    cc -o $n/cross /work/volec.o -lm || fail fixpoint "$start" "linking the cross-built compiler failed"
    echo "cross-built compiler: $($n/cross --version)"
    # Built by itself here: the same object as the cross-compilation, and
    # a fixpoint.
    $n/cross compiler/src/main.vl -o $n/build2.o || fail fixpoint "$start" "the cross-built compiler failed to build itself"
    cmp -s /work/volec.o $n/build2.o \
        || fail fixpoint "$start" "the compiler built here differs from the cross-built one"
    cc -o $n/build2 $n/build2.o -lm
    $n/build2 compiler/src/main.vl -o $n/build3.o || fail fixpoint "$start" "the compiler built here failed to build itself"
    cmp -s $n/build2.o $n/build3.o || fail fixpoint "$start" "no fixpoint on aarch64-linux"
    cp $n/build2 target/volec
    echo "fixpoint: the cross-built compiler, its build here and that one'"'"'s build emit the same object"
    row fixpoint pass $(( $(date +%s) - start )) "cross-built = built here = built by that"
    start=$(date +%s)
    head -c 3000000 /dev/urandom >/tmp/random
    ./target/volec examples/md5/main.vl -o /tmp/md5
    got=$(/tmp/md5 </tmp/random)
    want=$(md5sum </tmp/random | cut -d" " -f1)
    [ "$got" = "$want" ] || fail md5 "$start" "vole $got, md5sum $want"
    echo "md5 example: $got, same as md5sum"
    row md5 pass $(( $(date +%s) - start )) "the md5 example agrees with md5sum"
    # (0.25.2) a slice of the suite instead of the checks
    if [ -n "$SLICE" ]; then
        bad=0
        for l in $SLICE_LEVELS; do
            start=$(date +%s)
            if sh tests/run.sh -c target/volec -j "$CPUS" -O "$l" $SLICE; then
                row "slice-O$l" pass $(( $(date +%s) - start )) "tests/run.sh -O$l on the slice"
            else
                row "slice-O$l" FAIL $(( $(date +%s) - start )) "tests/run.sh -O$l on the slice"
                bad=1
            fi
        done
        exit $bad
    fi
    # The checks, at once.
    steps=suite-O2
    [ "$ALL_LEVELS" = 1 ] && steps="suite-O*"
    [ -z "$LEVELS" ] || steps=$(echo "$LEVELS" | tr "," "\n" | sed "s/^/suite-O/" | paste -s -d, -)
    # (no seed here: it has no aarch64-linux backend)
    [ "$FUZZ" != 0 ] && steps="$steps,fuzz-plain,fuzz-loops,fuzz-generics,fuzz-pressure,fuzz-calls,fuzz-lang06,fuzz-vector,fuzz-div,fuzz-range,fuzz-arch"
    [ "$ABI" != 0 ] && steps="$steps,abi-*,layout"
    [ "$OBJCHECK" = 1 ] && steps="$steps,objcheck"
    [ "$DEBUGGER" = 1 ] && steps="$steps,debug"
    [ "$VALGRIND" = 1 ] && steps="$steps,valgrind"
    [ -z "$ONLY" ] || steps=$ONLY
    echo "==> the checks: $(echo "$steps" | tr "," " ")" >&2
    exec sh bootstrap/gate.sh --inside -c target/volec -j "$CPUS" --only "$steps" \
        --fuzz "$([ "$FUZZ" = 0 ] && echo 1 || echo "$FUZZ")" --abi "$([ "$ABI" = 0 ] && echo 1 || echo "$ABI")"
'
