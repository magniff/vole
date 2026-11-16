#!/bin/sh
# The test suite of this release, run with a vole compiler (no cargo
# needed): every tests/run/*.vl, tests/run/*/main.vl (a program of
# several modules, 0.5) and tests/examples/*.test case (examples/NAME/,
# 0.15) is compiled, assembled and linked with the C compiler, run, checked;
# alongside them, tests/query/run.sh (`volec query`, 0.11),
# tests/refactor/run.sh (the refactoring tools, 0.11), tests/guide/run.sh
# (`volec guide`, 0.13), tests/fmt/run.sh (`volec fmt --check`
# of the tree, and formatting changes no program, 0.13) and
# tests/voltty/run.sh (the terminal's core against its oracle, 0.23),
# tests/walkthrough/run.sh (the sessions of examples/tools/*/README.md,
# 0.15, and of every examples/GROUP/NAME/README.md with one, 0.16) and
# tests/borrowck-try/run.sh (the borrow checker's try: lines run, 0.27.1) and
# tests/lsp/run.sh (`volec lsp`'s sessions, 0.24) and tests/book/run.sh
# (the book's examples and sessions, 0.25) and tests/link/run.sh
# (the link without cc, 0.25) and tests/perf/run.sh (--time-passes=instructions
# and --vec-stats=FN, 0.25.5) and tests/gpu/run.sh (std::gpu on Metal, 0.22, skipped off macOS)
# and tests/runner/run.sh (the runner's own pieces, 0.25.2) and
# tests/embed/run.sh (text blocks in a CRLF file, the caches and embedded
# files, 0.25.3) and tests/stdpos/run.sh (std's positions in the
# transcripts, compared normalized, 0.25.3) and tests/cachediff/run.sh
# --sample (the tools' answers from their cache the same as without it,
# 0.25.3) and tests/stdtools.sh (std inside the tools, 0.30). POSIX sh and awk only, so it runs the same on macOS and Linux.
#
# usage: tests/run.sh [-c COMPILER] [-t TARGET] [-O LEVEL] [-j JOBS] [-a] [-k LINKER] [-d FORMAT] [-f FILE] [-l] [--cases-only] [--bless] [-n NAME] [FILTER...]
#
# The options come before the FILTERs: one after a FILTER is an error
# that says where to put it (0.30: before, it was a FILTER, and `-O 2
# -j 2` after a name ran every case with a 2 in its name).
# The first line printed is the plan, before anything runs (0.30): `plan:
# N cases, M suites (NAMES), -j JOBS ...`; then a line for each suite as
# it ends (`suite NAME: P pass, F FAIL, exit RC, T s`), then the
# failures and the table.
#
#   -c COMPILER   the volec binary to test (default: target/volec,
#                 as left by bootstrap/bootstrap.sh)
#   -t TARGET     aarch64-macos, aarch64-linux, x86_64-linux or x86_64-macos
#                 (default: the host; x86_64-macos runs under Rosetta on
#                 Apple silicon)
#   -O LEVEL      the optimization level (0, 1 or 2, also as -O0; default:
#                 the compiler's default)
#   -j JOBS       cases run at once (default: the number of CPUs, or the
#                 slots of $VOLE_JOBSERVER); the report is the same for
#                 every JOBS
#   -a            programs go through assembly (volec -S, then cc), as
#                 before 0.7, instead of the compiler's own objects
#   -k LINKER     (0.25) the compiler links each case without C files
#                 itself (`volec --linker=LINKER -o prog`; system, cc or
#                 internal) instead of the C compiler linking its object
#   -d FORMAT     the compiler's diagnostics: human (the default) or short
#                 (--diagnostics=short, 0.11); the ERROR and WARNING
#                 directives are written for human and hold for both
#   -f FILE       (0.25.2) more FILTERs, one per line (# comments)
#   -l            (0.25.2) list what the FILTERs select, `case NAME` and
#                 `suite NAME` (`leveled`: it takes -O), and run nothing
#   --cases-only  (0.30) no suite or check, only cases: `tests/run.sh
#                 --cases-only fmt` is the cases with fmt in their name,
#                 not also the fmt suite's minutes
#   --bless       (0.30) `tests/run.sh --bless NAME...`: the selected
#                 cases are run (no suite), and one that fails only
#                 because its errors moved gets its `// ERROR:` directives
#                 rewritten in its file: every directive's text, its
#                 `line L, column C` aside, is still in the compiler's
#                 output, in order (the same errors: kind and message),
#                 and only the positions differ; they are written as the
#                 compiler prints them now, the case is run again, and
#                 `blessed NAME: ...` lists what changed (read the diff).
#                 Nothing else is blessed: a message that changed, an
#                 error that is gone or new (ERROR-COUNT), an XFAIL case,
#                 a case that fails otherwise stay as they are, each with
#                 a `not blessed NAME: why` line, and fail
#   -n NAME       (0.25.5) only the case, suite or check named NAME exactly
#                 (repeatable)
#   FILTER...     run only the cases (and the suites and checks below)
#                 whose name contains a FILTER (`tests/run.sh pathtrace`:
#                 every case of the path tracer); several of them, -n
#                 and -f select the union. (0.30) A FILTER of digits
#                 only gets a warning (an option's value put after a
#                 name?); selecting nothing is an error, `no case matches`
#   SUITE:FILTER  (0.30) the suite query, refactor, lsp or fmt, and of it
#                 only the transcripts, sessions and checks whose name
#                 contains FILTER (`tests/run.sh -j 2 refactor:rename
#                 query:=clash`; `=NAME`: NAME exactly; the suite's own
#                 runner lists them: tests/refactor/run.sh -l). With -j
#                 given, the query and refactor suites run JOBS of their
#                 transcripts at once (each; two at most beside cases)
#
# Environment: CC is the linker (and the assembler with -a; default cc).
# VOLE_JOBSERVER (0.11), when -j is not given, names a FIFO holding
# one line per free slot, shared by every runner bootstrap/gate.sh starts
# (tests/run.sh, tests/fuzz/run.sh, tests/abi/run.sh, tests/objcheck.sh):
# a case takes a line before it starts and puts it back when done.
#
# Directives, in `//` comments of the case file:
#   // ARGS: a b c       command-line arguments (whitespace separated; 0.20:
#                        @ROOT@ stands for the root of the tree)
#   // STDIN: text       stdin, one directive per line, joined with '\n'
#   // ENV: NAME=VALUE   (0.25.4) a variable of the program's environment,
#                        one directive each; @ROOT@ in VALUE is the root
#                        (`// ENV: VOLE_WINDOW_SCRIPT=frames 2; key q`)
#   // EXPECT: text      expected stdout, one directive per line; (0.25.2)
#                        holes for what changes from run to run: {num} a
#                        number (12, -3, 0.25, 1.5e-3), {int} an integer,
#                        {..} any text within the line (tests/expect.awk):
#                        `// EXPECT: a step: {num} ms`; a line with holes
#                        still matches one line of the output
#   // EXPECT-PPM: OUT REF [region X,Y,W,H] [tolerance N] [allow P%]
#                        (0.25.2) after the run, the PPM image OUT (written
#                        by the program, relative to its directory) is the
#                        image REF (a P6 or P3 file, relative to the root,
#                        tests/golden/ by convention): only its region when
#                        one is given (REF is then the region's size), a
#                        pixel the same when no channel differs by more
#                        than N (default 0), up to P% of the pixels allowed
#                        to differ (default 0). A failure says how many
#                        differ, the worst one, and where the actual image
#                        (cropped like REF) was kept: target/test-shots/
#                        CASE.ppm, the file to copy over REF when the change
#                        is wanted (tests/ppmdiff.sh compares by hand).
#                        One directive per image
#   // EXIT: 3           expected exit code (default 0)
#   // STDERR: text      stderr contains text, one directive per line
#   // ERROR: text       compilation must fail (exit code 1) with an error
#                        containing this text; one directive per message,
#                        in the order they are reported
#   // ERROR-COUNT: n    exactly n errors are reported
#   // XFAIL: reason     a known bug: the case is expected to fail, and
#                        reported as a failure (XPASS) once it passes
#   // XFAIL(T): reason  the same, only for target T
#   // SOURCE: path      (.test files) the program, relative to the root
#   // CHEADER: name.h    the program's C header (--emit-header), made for
#                        its C sources to include
#   // CSOURCE: path     a C file to compile and link with the program,
#                        relative to the root (one directive per file)
#   // BUILD: reason     (.test files) only compile and link it
#   // CHECK: text       the optimized IR (--emit-ir) has a line containing
#                        text, after the previous CHECK's line
#   // CHECK-NOT: text   no line containing text between the neighbouring
#                        CHECKs' lines (or the start and end)
#   // CHECK-OPT: n      the level for the CHECKs (default 2)
#   // PLACES: text     (0.26.0) the elaborated places IR (`volec check
#                        --emit-places --places-diff`) has a line containing
#                        text, after the previous PLACES's line; no
#                        `places.diff:` difference may be listed. It runs
#                        after a plain `check` made the tools' cache in a
#                        directory of the case's: the places options must
#                        not be answered from it
#   // PLACES-NOT: text  no line containing text between the neighbouring
#                        PLACES's lines
#   // ASM(T): text      the assembly for target T (at the CHECK-OPT level)
#                        has a line containing text, after the previous
#                        ASM(T)'s line; checked only when testing T
#   // ASM-NOT(T): text  no line containing text between the neighbouring
#                        ASM(T)s' lines
#   // TIMEOUT: n why   (0.22) the case may run n times the time limit (a
#                        long one at -O0, under the gate's load)
#   // CROSS: T...       (0.19) the case is also compiled for target T (at the
#                        suite's level, to an object: the compiler's own
#                        assembler; then -S at the CHECK-OPT level, matched
#                        against its ASM(T) and ASM-NOT(T) lines), nothing of
#                        it run: x86-64's intrinsics are checked so on an arm
#                        host. Skipped when T is the target tested. (0.28.0)
#                        Several targets: each in turn (std's effect lists
#                        are checked for the target of the build).
#   // FIXIMPORTS: why   (0.8) a copy of the case (its directory, for a
#                        main.vl) is rewritten by volec --fix-imports,
#                        which must then find nothing more to do; the copy
#                        is what the other directives check
#   // FIXED: text       the rewritten copy has a line (not a comment)
#                        containing text, one directive per line
#   // FIXUNSAFE: why    (0.9) the same with volec --fix-unsafe
#   // FLAGS: flags      (0.9) more compiler options for the case (0.10:
#                        @ROOT@ stands for the root of the tree)
#   // WARNING: text     (0.9) the case compiles with a warning containing
#                        this text, one directive per message, in order
#   // LINK: why         (0.16) volec links the case itself: its CSOURCE
#                        files (with -I for its CHEADER) and FLAGS on its
#                        command line, `-o prog`; no -lm added (volec
#                        links libm when the program calls into it)
#   // REQUIRES: clang    (0.18) the case runs only where the C compiler
#                        ($CC, which C imports read) is clang: what it
#                        tests is clang's (`_Nonnull`); elsewhere it is
#                        skipped, counted apart
#   // REQUIRES: metal    (0.22) the case runs only on aarch64-macos (std::gpu
#                        on Metal); elsewhere it is skipped, counted apart
#   // REQUIRES: macos    (0.30.1) the case runs only on macOS (what it
#                        tests is macOS's: a signal's number, an exit
#                        code); elsewhere it is skipped, counted apart
#   // NO-EXTRA-FLAGS: why (0.16) the case is built without
#                        $VOLE_TEST_FLAGS (its output differs by design
#                        with them)
#   // PROFILE: why      (0.10) at -O1 and -O2, the case is first compiled
#                        with --profile-generate, run and checked; the
#                        other directives then check it compiled with
#                        --profile-use of that profile
# Every case is compiled with --deny-warnings, except the ones with WARNING
# directives (0.9's unsafe warnings are errors from 0.10; there are no
# warnings at the moment).
# Stdout is compared after removing trailing whitespace. Each program may
# run for 20 seconds ($VOLE_TEST_TIMEOUT: another limit), extended while
# the machine is loaded (0.25.2, tests/watchdog.sh: by the limit again, up
# to 8 times, while the load average is above the CPUs); a program killed
# at its limit fails with "timed out: killed after N s ...". $VOLE_TEST_FLAGS (0.16): more compiler options for every
# case but those with NO-EXTRA-FLAGS (the gate's examples-checkalloc
# step: --check-alloc). Every other case is built with --verify-places
# (0.26.2; $VOLE_VERIFY_EVERY=N: every N-th, 0: none), but those with
# NO-EXTRA-FLAGS.
# (0.27.2) std's cases (std_*) are built with --check-alloc, and fail
# when blocks of Gpa are left at exit (and it exits 0) unless a STDERR
# line expects the list (0.30: and so does any case whose FLAGS have
# --check-alloc) ($VOLE_TEST_STD_PLAIN=1: without it); $VOLE_TEST_XFAIL_WHY=FILE
# gets each XFAIL case's name and the start of its failure, for a triage;
# (0.27.2.1) $VOLE_TEST_RESULTS=FILE each case's name, status and borrowck
# errors at std's positions (the gate's std rows read the suite's).

set -u
LC_ALL=C
export LC_ALL
# (0.30.1) The files this run's caller gives it are this run's: taken
# here and out of the environment, so that no tests/run.sh started below
# (the runner suite's own runs, on a compiler that fails on purpose)
# writes its records into this one's (the gate's suite rows judge every
# case by its one record) or its XFAIL triage. The same for the note of
# lazy std's reruns, below.
RESULTS_FILE=${VOLE_TEST_RESULTS:-}
XFAIL_WHY_FILE=${VOLE_TEST_XFAIL_WHY:-}
unset VOLE_TEST_RESULTS VOLE_TEST_XFAIL_WHY
# (0.18.1) Without the code cache (back::codecache), unless the caller
# says (gate.sh's suite-O2 row): its programs are small, and a cache per
# program and compiler would fill target/volec-cache.
VOLE_CODE_CACHE=${VOLE_CODE_CACHE:-off}
export VOLE_CODE_CACHE
# (0.28) And without the tools' cache (tools::query::cache), unless the
# caller says: `check FILE` writes about 12 MB per program, which nothing
# removes, and a whole suite left over 80 GB in target/volec-cache. The
# cases about the cache name their own directory.
VOLE_CACHE=${VOLE_CACHE:-off}
export VOLE_CACHE

ROOT=$(cd "$(dirname "$0")/.." && pwd)
COMPILER="$ROOT/target/volec"
CC=${CC:-cc}
# (0.18) Whether the C compiler is clang, for `// REQUIRES: clang`.
CC_IS_CLANG=0
"$CC" --version 2>/dev/null | grep -qi clang && CC_IS_CLANG=1
TARGET=""
OPT=""
TIMEOUT=${VOLE_TEST_TIMEOUT:-20}
VERIFY_EVERY=${VOLE_VERIFY_EVERY:-2}
JOBS=""
OUT=prog.o
DIAG=human
LINKER=""
FILTERS=""
LIST=0
CASES_ONLY=0
BLESS=0

usage() {
    sed -n '2,/^# Environment:/p' "$0" | sed '$d; s/^# \{0,1\}//' >&2
    exit 2
}

all_args="$*"
while [ $# -gt 0 ]; do
    case "$1" in
        -c) [ $# -ge 2 ] || usage; COMPILER=$2; shift 2 ;;
        -t) [ $# -ge 2 ] || usage; TARGET=$2; shift 2 ;;
        -O) [ $# -ge 2 ] || usage; OPT="-O$2"; shift 2 ;;
        -O[0-2]) OPT=$1; shift ;;
        -j) [ $# -ge 2 ] || usage; JOBS=$2; shift 2 ;;
        -a) OUT=prog.s; shift ;;
        -k) [ $# -ge 2 ] || usage; LINKER=$2; shift 2 ;;
        -d) [ $# -ge 2 ] || usage; DIAG=$2; shift 2 ;;
        -f)
            [ $# -ge 2 ] || usage
            [ -f "$2" ] || { echo "tests/run.sh: no filter file $2" >&2; exit 2; }
            # (one filter per line; blank lines and # comments skipped)
            FILTERS="$FILTERS$(sed 's/#.*//; s/^[[:space:]]*//; s/[[:space:]]*$//; /^$/d' "$2")
"
            shift 2 ;;
        -l) LIST=1; shift ;;
        --cases-only) CASES_ONLY=1; shift ;;
        --bless) BLESS=1; CASES_ONLY=1; shift ;;
        # (0.25.5) -n NAME: only NAME, as =NAME, in a form zsh does not
        # expand (its `=word` is a path: `=NAME` unquoted runs nothing)
        -n)
            [ $# -ge 2 ] || usage
            FILTERS="$FILTERS=$2
"
            shift 2 ;;
        -h|--help) usage ;;
        -*)
            # (0.25.2: one line, not the whole usage)
            echo "tests/run.sh: unknown option '$1' (options: -c COMPILER -t TARGET -O LEVEL or -O0 -j JOBS -a -k LINKER -d FORMAT -f FILE -l --cases-only --bless -n NAME; tests/run.sh -h for more)" >&2
            exit 2 ;;
        *) break ;;
    esac
done
# (0.25.2) Several FILTERs, and -f files of them, select the union.
# (0.30) An option after a FILTER is an error, not a FILTER: `pathtrace
# -O 2 -j 2` selected every name holding `-O`, `2` or `-j`, at the
# default -j.
first_filter=""
before=""
# (the options given in their place, for the try: line)
lead=${all_args%"$*"}
for f in "$@"; do
    case "$f" in
        -*)
            if [ -n "$first_filter" ]; then
                rest=$(printf '%s ' "$@" | sed 's/ $//')
                rest=${rest#"$before"}
                echo "tests/run.sh: the option '$f' comes after the FILTER '$first_filter': options go before the FILTERs" >&2
                echo "try: tests/run.sh $lead$rest $(printf '%s' "$before" | sed 's/ $//')" >&2
                exit 2
            fi ;;
    esac
    [ -n "$first_filter" ] || first_filter=$f
    before="$before$f "
    FILTERS="$FILTERS$f
"
done
# (0.30) SUITE:FILTER, for the suites that take names (query, refactor,
# lsp, fmt): the suite, and FILTER given to its runner (the transcripts,
# sessions and checks of it whose name contains FILTER; `=NAME`: NAME
# exactly). Several for one suite select the union.
SUB_query=""
SUB_refactor=""
SUB_lsp=""
SUB_fmt=""
ALLF=$FILTERS
FILTERS=""
while IFS= read -r f; do
    case "$f" in
        query:?*) SUB_query="$SUB_query ${f#*:}"; f="=query" ;;
        refactor:?*) SUB_refactor="$SUB_refactor ${f#*:}"; f="=refactor" ;;
        lsp:?*) SUB_lsp="$SUB_lsp ${f#*:}"; f="=lsp" ;;
        fmt:?*) SUB_fmt="$SUB_fmt ${f#*:}"; f="=fmt" ;;
        "") continue ;;
        # (a FILTER that selects the suite itself: all of it, whatever
        # names another gives)
        =query|=refactor|=lsp|=fmt) eval "WHOLE_${f#=}=1" ;;
        =*) ;;
        *)
            for s in query refactor lsp fmt; do
                case "$s" in *"$f"*) eval "WHOLE_$s=1" ;; esac
            done ;;
    esac
    FILTERS="$FILTERS$f
"
done <<EOF
$ALLF
EOF
[ -z "${WHOLE_query:-}" ] || SUB_query=""
[ -z "${WHOLE_refactor:-}" ] || SUB_refactor=""
[ -z "${WHOLE_lsp:-}" ] || SUB_lsp=""
[ -z "${WHOLE_fmt:-}" ] || SUB_fmt=""
FILTER=$(printf '%s' "$ALLF" | tr '\n' ' ' | sed 's/ $//')
if [ "$BLESS" = 1 ] && { [ -z "$FILTERS" ] || [ "$DIAG" != human ]; }; then
    echo "tests/run.sh: --bless takes the cases to bless, and the human diagnostics: tests/run.sh --bless NAME... (tests/run.sh -h says what it rewrites)" >&2
    exit 2
fi
VOLE_RUN_FILTERS=$FILTERS
export VOLE_RUN_FILTERS

# The cases, `NAME FILE` per line, in order: every tests/run/*.vl,
# tests/run/*/main.vl (a program of several modules, 0.5) and
# tests/examples/*.test (example_NAME).
all_cases() {
    for file in "$ROOT"/tests/run/*.vl "$ROOT"/tests/run/*/main.vl "$ROOT"/tests/examples/*.test; do
        [ -f "$file" ] || continue
        base=${file##*/}
        name=${base%.*}
        case "$file" in
            *.test) name="example_$name" ;;
            */main.vl) name=${file%/main.vl}; name=${name##*/} ;;
        esac
        echo "$name $file"
    done
}
# The lines of stdin whose first word the filters select (all of them
# without a filter): a FILTER selects the names containing it, =NAME
# only NAME.
select_names() {
    if [ -z "$VOLE_RUN_FILTERS" ]; then
        cat
        return
    fi
    awk 'BEGIN {
            nf = split(ENVIRON["VOLE_RUN_FILTERS"], f, "\n")
            for (i = 1; i <= nf; i++)
                if (f[i] ~ /^=/) exact[substr(f[i], 2)] = 1
                else if (f[i] != "") part[++np] = f[i]
        }
        $1 in exact { print; next }
        { for (i = 1; i <= np; i++) if (index($1, part[i])) { print; next } }'
}
# `y` when the filters select the suite or check named $1 (0.30: none
# with --cases-only).
want() {
    [ "$CASES_ONLY" = 1 ] && return
    [ -n "$(echo "$1" | select_names)" ] && echo y
}
# The suites and checks besides the cases, each run where `case $(want
# NAME)` is below (tests/runner/run.sh checks the two agree): what -l
# lists. LEVELED: the ones that take -O (the others are the same at
# every level).
SUITES="query refactor guide book fmt walkthrough wgsl voltty borrowck-try runner embed-checks stdpos stdtools cachediff lsp link gpu hooks arch-gen arch-enc voltty_render window example_layout example_build readme_sync perf"
LEVELED="gpu arch-gen"
# (0.30) A FILTER of digits only is warned about: an option's value put
# after a name was one before 0.30 (`NAME -j 2`).
for f in $(printf '%s' "$FILTERS"); do
    case "$f" in
        *[!0-9]*) ;;
        *) echo "tests/run.sh: warning: the FILTER '$f' is only digits: it selects every name containing '$f' ($(all_cases | awk -v f="$f" 'index($1, f) { n++ } END { print n + 0 }') cases); an option's value goes with its option, before the FILTERs (-O $f, -j $f)" >&2 ;;
    esac
done
if [ "$LIST" = 1 ]; then
    all_cases | select_names | awk '{ print "case " $1 }'
    for s in $SUITES; do
        [ -z "$(want "$s")" ] && continue
        # (0.30: a suite given names, `suite refactor only NAME...`)
        eval "sub=\${SUB_$(echo "$s" | tr - _):-}"
        case " $LEVELED " in *" $s "*) echo "suite $s leveled" ;; *) echo "suite $s${sub:+ only$sub}" ;; esac
    done
    exit 0
fi
case "$DIAG" in
    # (0.15: a compiler whose stderr is not a terminal prints the short
    # form unless told otherwise)
    human) DIAG_FLAG="--diagnostics=human" ;;
    short) DIAG_FLAG="--diagnostics=short" ;;
    *) usage ;;
esac

case "$COMPILER" in
    /*) ;;
    *) COMPILER="$(pwd)/$COMPILER" ;;
esac
[ -x "$COMPILER" ] || { echo "run.sh: no compiler at $COMPILER (use -c)" >&2; exit 2; }
command -v "$CC" >/dev/null 2>&1 || { echo "run.sh: '$CC' not found (set CC)" >&2; exit 2; }

if [ -z "$TARGET" ]; then
    case "$(uname -s)-$(uname -m)" in
        Darwin-arm64) TARGET=aarch64-macos ;;
        Darwin-x86_64) TARGET=x86_64-macos ;;
        Linux-x86_64) TARGET=x86_64-linux ;;
        Linux-aarch64) TARGET=aarch64-linux ;;
        *) echo "run.sh: no vole target for this host ($(uname -s) $(uname -m)); use -t" >&2; exit 2 ;;
    esac
fi
# How the C compiler assembles and links for the target.
case "$TARGET" in
    aarch64-macos) LINK_FLAGS="-arch arm64" ;;
    x86_64-macos) LINK_FLAGS="-arch x86_64" ;;
    x86_64-linux|aarch64-linux) LINK_FLAGS="" ;;
    *) echo "run.sh: unknown target '$TARGET'" >&2; exit 2 ;;
esac

WORK=$(mktemp -d "${TMPDIR:-/tmp}/vole-tests.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
trap 'exit 130' INT TERM
FAILURES="$WORK/failures"
TALLY="$WORK/tally"
# (0.28.0) A build whose lazy read of std failed and whose whole read passed
# (a rerun: three or four times the work) says so on stderr and is listed
# here (front/modules/stdlazy.vl: rerun_note); the summary counts them.
# (0.30.1) This run's own file, always: a file named by the environment
# is an outer tests/run.sh's (no one else sets it), whose summary would
# count this run's reruns. Only `1` (the note on stderr, no file) is kept.
RERUNS="$WORK/reruns"
[ "${VOLE_STD_RERUN_NOTE:-}" = 1 ] && RERUNS=1
export VOLE_STD_RERUN_NOTE="$RERUNS"
# (0.25.2) The skipped checks that say why (a `skip NAME: why` line of a
# runner below, like the window tests' without a display giving frames):
# printed before the summary, `SKIP NAME: why`, and counted apart.
SKIPS="$WORK/skips"
: >"$FAILURES"
: >"$TALLY"
: >"$SKIPS"

# A skipped check of category $1, `NAME: why` (or `NAME (why)`) in $2.
skipped() {
    echo "$1 skip" >>"$TALLY"
    echo "SKIP $2" >>"$SKIPS"
}

# The C compiler, once more when it crashed (a signal, or gcc's "internal
# compiler error"): an emulated toolchain (x86-64 Linux under Rosetta)
# now and then does, and a crash of cc is not vole's. Its output (and
# the crash's, if any) on stdout.
cc_run() {
    cr_out=$("$CC" "$@" 2>&1)
    cr_rc=$?
    if [ $cr_rc -ne 0 ]; then
        case "$cr_rc:$cr_out" in
            1[3-9][0-9]:*|2[0-9][0-9]:*|*"internal compiler error"*|*"Segmentation fault"*|*"Bus error"*)
                printf '%s\n(%s crashed, exit %d: run again)\n' "$cr_out" "$CC" "$cr_rc"
                cr_out=$("$CC" "$@" 2>&1)
                cr_rc=$? ;;
        esac
    fi
    [ -z "$cr_out" ] || printf '%s\n' "$cr_out"
    return $cr_rc
}

# The first message of directives file $1 (ERROR or WARNING texts) that
# the compiler's output $2 lacks, each after the one before it; nothing
# when all are there. With -d short a diagnostic is one line
# (`file:line:col: error[kind] message | help: ...`): a directive
# `line L, column C` is looked for as `:L:C:` in the line of the message
# before it, `error[kind]: ` as `error[kind] `, and the next directive may
# be later in the same line.
missing_message() {
    awk -v out="$2" -v short="$( [ "$DIAG" = short ] && echo 1 || echo 0)" '
        BEGIN { while ((getline line < out) > 0) text[++n] = line; at = 0; col = 0 }
        {
            want = $0
            from_start = 0
            if (short) {
                if (match(want, /^line [0-9]+, column [0-9]+$/)) {
                    split(want, f, /[ ,]+/)
                    want = ":" f[2] ":" f[4] ":"
                    from_start = 1
                }
                while ((k = index(want, "]: ")) > 0) want = substr(want, 1, k) " " substr(want, k + 3)
            }
            if (!short) {
                while (at < n && index(text[at + 1], want) == 0) at++
                if (at >= n) { print $0; exit }
                at++
                next
            }
            # (short: from the previous match on, within its line first)
            if (at > 0) {
                rest = from_start ? text[at] : substr(text[at], col + 1)
                k = index(rest, want)
                if (k > 0) {
                    col = (from_start ? 0 : col) + k + length(want) - 1
                    next
                }
            }
            while (at < n && index(text[at + 1], want) == 0) at++
            if (at >= n) { print $0; exit }
            at++
            col = index(text[at], want) + length(want) - 1
        }' "$1"
}

# Writes the directives of case file $1 into directory $2: one file per
# directive (args, stdin, expect, exit, errors, xfail, source, build).
read_directives() {
    awk -v dir="$2" -v target="$TARGET" -f "$ROOT/tests/directives.awk" "$1"
}

# The file's content without trailing whitespace.
trimmed() {
    awk '{ text = text $0 "\n" } END { sub(/[ \t\r\n]+$/, "", text); printf "%s", text }' "$1"
}

# Whether $1/actual (the program's stdout, trimmed) matches $1/wanted (its
# EXPECT lines): equal, or line by line with the holes {num}, {int} and
# {..} filled (tests/expect.awk, 0.25.2); the first line that differs is
# then in $1/expect.out.
stdout_matches() {
    : >"$1/expect.out"
    cmp -s "$1/actual" "$1/wanted" && return 0
    awk -v want="$1/wanted" -f "$ROOT/tests/expect.awk" "$1/actual" >"$1/expect.out"
}

# EXPECT-PPM (0.25.2): each image case directory $1's program wrote (OUT,
# relative to the directory it ran in) against its reference (REF,
# relative to the root), through tests/ppmdiff.sh. The actual image,
# cropped like the reference, is kept as target/test-shots/CASE.ppm (a
# second directive's as CASE-2.ppm) for a failure to point at.
check_ppms() {
    pd=$1
    pn=${pd##*/}
    k=0
    while read -r pout pref prest; do
        [ -n "$pout" ] || continue
        k=$((k + 1))
        popts=""
        pwhat=""
        # shellcheck disable=SC2086
        set -- $prest
        while [ $# -gt 0 ]; do
            if [ $# -lt 2 ]; then
                echo "EXPECT-PPM $pout: '$1' without a value (region X,Y,W,H, tolerance N, allow P%)" >"$pd/why"
                return 1
            fi
            case "$1" in
                region) popts="$popts -r $2" ;;
                tolerance) popts="$popts -t $2" ;;
                allow) popts="$popts -p ${2%\%}" ;;
                *)
                    echo "EXPECT-PPM $pout: unknown '$1' (region X,Y,W,H, tolerance N, allow P%)" >"$pd/why"
                    return 1 ;;
            esac
            pwhat="$pwhat${pwhat:+, }$1 $2"
            shift 2
        done
        if [ -z "$pref" ]; then
            echo "EXPECT-PPM $pout: no reference (EXPECT-PPM: OUT REF [region X,Y,W,H] [tolerance N] [allow P%])" >"$pd/why"
            return 1
        fi
        if [ ! -f "$pd/$pout" ]; then
            { echo "EXPECT-PPM: the program wrote no $pout"; echo "--- stdout"; cat "$pd/stdout"; echo "--- stderr"; cat "$pd/stderr"; } >"$pd/why"
            return 1
        fi
        mkdir -p "$ROOT/target/test-shots"
        pshot="target/test-shots/$pn$([ $k -gt 1 ] && echo "-$k").ppm"
        # shellcheck disable=SC2086
        sh "$ROOT/tests/ppmdiff.sh" $popts -o "$pd/shot.$k.ppm" "$pd/$pout" "$ROOT/$pref" >"$pd/ppm.out" 2>&1
        prc=$?
        [ -f "$pd/shot.$k.ppm" ] && mv -f "$pd/shot.$k.ppm" "$ROOT/$pshot"
        [ $prc -eq 0 ] && continue
        {
            echo "EXPECT-PPM $pout against $pref${pwhat:+ ($pwhat)}: $(cat "$pd/ppm.out")"
            echo "the actual image: $pshot"
            [ $prc -eq 1 ] || [ $prc -eq 3 ] && echo "try: cp $pshot $pref   (when the new image is the right one)"
        } >"$pd/why"
        return 1
    done <"$pd/ppms"
    return 0
}

# Runs $dir/prog with a timeout; sets RC.
run_program() {
    dir=$1
    (
        cd "$dir" || exit 1
        # (0.25.4: the case's ENV directives)
        if [ -s env ]; then
            while IFS= read -r kv; do
                [ -n "$kv" ] && export "$(printf '%s' "$kv" | sed "s|@ROOT@|$ROOT|g")"
            done <env
        fi
        # (0.19: RUN_ENV, a variable for the run: VOLE_ARCH_DISABLE)
        if [ -n "${RUN_ENV:-}" ]; then
            # shellcheck disable=SC2046
            exec env "$RUN_ENV" ./prog $(cat args) <stdin >stdout 2>stderr
        fi
        # shellcheck disable=SC2046
        exec ./prog $(sed "s|@ROOT@|$ROOT|g" args) <stdin >stdout 2>stderr
    ) &
    pid=$!
    # (0.22: a case's TIMEOUT directive multiplies the limit; 0.25.2: the
    # limit is extended while the machine is loaded, tests/watchdog.sh,
    # and a program killed by it is a failure that says so: $dir/timedout)
    limit=$((TIMEOUT * $(cat "$dir/timeout" 2>/dev/null || echo 1)))
    rm -f "$dir/timedout"
    sh "$ROOT/tests/watchdog.sh" "$limit" "$pid" "$dir/timedout" >/dev/null 2>&1 &
    watchdog=$!
    wait "$pid" 2>/dev/null
    RC=$?
    kill "$watchdog" 2>/dev/null
    wait "$watchdog" 2>/dev/null
}

# After run_program: when the watchdog killed the program, the reason
# (and what it printed) in $1/why; returns 1 then.
timed_out() {
    [ -s "$1/timedout" ] || return 1
    {
        echo "timed out: $(cat "$1/timedout")"
        echo "--- stdout so far"; cat "$1/stdout" 2>/dev/null; echo
        echo "--- stderr so far"; cat "$1/stderr" 2>/dev/null
    } >"$1/why"
    return 0
}

# Runs one case; prints nothing, returns 0 on success, and leaves the
# reason for a failure in $dir/why.
check_case() {
    file=$1
    dir=$2
    source=$(cat "$dir/source")
    if [ -n "$source" ]; then
        source="$ROOT/$source"
    else
        source=$file
    fi
    case "$(cat "$dir/fiximports")" in
        1) fix_case "$source" "$dir" --fix-imports || return 1 ;;
        2) fix_case "$source" "$dir" --fix-unsafe || return 1 ;;
    esac
    # The compiler's options for the case (0.9).
    FLAGS="--deny-warnings $DIAG_FLAG $(sed "s|@ROOT@|$ROOT|g" "$dir/flags")"
    # (--check-unsafe needs the IR: such a case runs at -O1 when -O0 is
    # asked for, 0.10.)
    if [ "$OPT" = -O0 ] && grep -q -- --check-unsafe "$dir/flags"; then
        OPT=-O1
    fi
    # (A profile's warnings come at -O1 and -O2 only: -O0 reads none.)
    if [ "$OPT" = -O0 ] && grep -q -- --profile-use "$dir/flags"; then
        : >"$dir/warnings"
    fi
    [ -s "$dir/warnings" ] && FLAGS="$DIAG_FLAG $(sed "s|@ROOT@|$ROOT|g" "$dir/flags")"
    # (0.16: options for every case, from the environment)
    if [ -n "${VOLE_TEST_FLAGS:-}" ] && [ "$(cat "$dir/noextra")" != 1 ]; then
        FLAGS="$FLAGS $VOLE_TEST_FLAGS"
    fi
    # (0.27.2) std's cases (gate 1's std-tests row) are built with
    # --check-alloc, std's checking Gpa, and one fails when blocks of Gpa
    # are left at exit, unless a STDERR line expects the list
    # (VOLE_TEST_STD_PLAIN=1: built without it)
    STD_LEAKS=0
    case "${file##*/}" in
        std_*)
            if [ "${VOLE_TEST_STD_PLAIN:-0}" != 1 ] && [ "$(cat "$dir/noextra")" != 1 ]; then
                STD_LEAKS=1
                case " $FLAGS " in *" --check-alloc "*) ;; *) FLAGS="$FLAGS --check-alloc" ;; esac
            fi ;;
    esac
    # (0.30) and so is any case whose own FLAGS have --check-alloc,
    # whatever its name: before, an own_ case built so passed while
    # leaking (not $VOLE_TEST_FLAGS's, the gate's examples-checkalloc row,
    # which looks for a use after a free)
    case " $(cat "$dir/flags") " in *" --check-alloc "*) STD_LEAKS=1 ;; esac
    # (0.26.2: --verify-places on every VERIFY_EVERY-th case, chosen by its
    # name's cksum: the places IR's form checked where the suite builds
    # it, now that both code generators read it and -O0 is no independent
    # lowering; every case would add 8% to the cases' time, every other
    # one 4%; 0.27.2: the cksum of the file's name, not its path, so that
    # every worktree and the gate check the same cases)
    if [ "$VERIFY_EVERY" -gt 0 ] && [ "$(cat "$dir/noextra")" != 1 ] \
        && [ $(($(printf '%s' "${file##*/}" | cksum | cut -d' ' -f1) % VERIFY_EVERY)) = 0 ]; then
        FLAGS="$FLAGS --verify-places"
    fi
    if [ -s "$dir/errors" ]; then
        # shellcheck disable=SC2086
        "$COMPILER" --target "$TARGET" $OPT $FLAGS "$source" -o "$dir/prog.s" >"$dir/compile.out" 2>&1
        rc=$?
        echo "$rc" >"$dir/compile.rc"
        if [ $rc -ne 1 ]; then
            { echo "expected a compile error (exit code 1), got exit code $rc:"; cat "$dir/compile.out"; } >"$dir/why"
            return 1
        fi
        # Each message, in order (several errors are reported at once).
        missing=$(missing_message "$dir/errors" "$dir/compile.out")
        if [ -n "$missing" ]; then
            { echo "expected an error containing '$missing' (after the ones before it), got:"; cat "$dir/compile.out"; } >"$dir/why"
            return 1
        fi
        if [ -s "$dir/errcount" ]; then
            got=$(grep -c -E '^error\[|^[^ ]*: error\[' "$dir/compile.out")
            if [ "$got" -ne "$(cat "$dir/errcount")" ]; then
                { echo "expected $(cat "$dir/errcount") errors, got $got:"; cat "$dir/compile.out"; } >"$dir/why"
                return 1
            fi
        fi
        return 0
    fi
    PFLAGS=""
    if [ "$(cat "$dir/profile")" = 1 ] && ! profile_case "$source" "$dir"; then
        return 1
    fi
    if [ -s "$dir/asms" ] && ! check_asm "$source" "$dir"; then
        return 1
    fi
    if [ -s "$dir/cross" ] && ! check_cross "$source" "$dir"; then
        return 1
    fi
    if [ -s "$dir/checks" ] && ! check_ir "$source" "$dir"; then
        return 1
    fi
    if [ -s "$dir/places" ] && ! check_places "$source" "$dir"; then
        return 1
    fi
    # shellcheck disable=SC2086
    [ "$OPT" = -O0 ] && PFLAGS=""
    csources=""
    for c in $(cat "$dir/csources"); do
        csources="$csources $ROOT/$c"
    done
    # The program's C header, for its C sources.
    if [ -s "$dir/cheader" ]; then
        # shellcheck disable=SC2086
        if ! "$COMPILER" --target "$TARGET" $FLAGS --emit-header "$source" -o "$dir/$(cat "$dir/cheader")" >"$dir/header.out" 2>&1; then
            { echo "--emit-header failed:"; cat "$dir/header.out"; } >"$dir/why"
            return 1
        fi
        csources="-I $dir $csources"
    fi
    if [ "$(cat "$dir/link")" = 1 ]; then
        # (0.16) volec compiles the C files and links, as `cc` would
        # shellcheck disable=SC2086
        if ! VOLE_CC="$CC" "$COMPILER" --target "$TARGET" $OPT $FLAGS $PFLAGS "$source" $csources -o "$dir/prog" >"$dir/compile.out" 2>&1; then
            framework_hint "$dir/compile.out" >"$dir/why" \
                || { echo "compile and link failed:"; cat "$dir/compile.out"; } >"$dir/why"
            return 1
        fi
    elif [ -n "$LINKER" ] && [ -z "$csources" ] && [ "$OUT" = prog.o ]; then
        # (0.25, -k) the compiler links
        # shellcheck disable=SC2086
        if ! "$COMPILER" --target "$TARGET" --linker="$LINKER" $OPT $FLAGS $PFLAGS "$source" -o "$dir/prog" >"$dir/compile.out" 2>&1; then
            framework_hint "$dir/compile.out" >"$dir/why" \
                || { echo "compile and link failed:"; cat "$dir/compile.out"; } >"$dir/why"
            return 1
        fi
    else
        # shellcheck disable=SC2086
        if ! "$COMPILER" --target "$TARGET" $OPT $FLAGS $PFLAGS "$source" -o "$dir/$OUT" >"$dir/compile.out" 2>&1; then
            { echo "compile failed:"; cat "$dir/compile.out"; } >"$dir/why"
            return 1
        fi
        # shellcheck disable=SC2086
        if ! cc_run $LINK_FLAGS -o "$dir/prog" "$dir/$OUT" $csources -lm >"$dir/link.out" 2>&1; then
            framework_hint "$dir/link.out" >"$dir/why" \
                || { echo "$CC failed:"; cat "$dir/link.out"; } >"$dir/why"
            return 1
        fi
    fi
    if [ -s "$dir/warnings" ]; then
        missing=$(missing_message "$dir/warnings" "$dir/compile.out")
        if [ -n "$missing" ]; then
            { echo "expected a warning containing '$missing' (after the ones before it), got:"; cat "$dir/compile.out"; } >"$dir/why"
            return 1
        fi
    fi
    [ "$(cat "$dir/build")" = 1 ] && return 0
    run_program "$dir"
    timed_out "$dir" && return 1
    expected_exit=$(cat "$dir/exit")
    trimmed "$dir/stdout" >"$dir/actual"
    trimmed "$dir/expect" >"$dir/wanted"
    if ! stdout_matches "$dir"; then
        {
            echo "stdout mismatch ($(cat "$dir/expect.out"))"
            echo "--- expected"; cat "$dir/wanted"; echo
            echo "--- actual"; cat "$dir/actual"; echo
        } >"$dir/why"
        return 1
    fi
    if [ "$RC" -ne "$expected_exit" ]; then
        { echo "exit code: expected $expected_exit, got $RC"; cat "$dir/stderr"; } >"$dir/why"
        return 1
    fi
    while IFS= read -r message; do
        if ! grep -qF -- "$message" "$dir/stderr"; then
            { echo "expected stderr containing '$message', got:"; cat "$dir/stderr"; } >"$dir/why"
            return 1
        fi
    done <"$dir/stderrs"
    # (a case that panics, EXIT: 101, ends with its blocks: no unwinding)
    if [ $STD_LEAKS = 1 ] && [ "$expected_exit" = 0 ] \
        && grep -q '^check-alloc: .* of Gpa not freed' "$dir/stderr" \
        && ! grep -q 'not freed' "$dir/stderrs"; then
        { echo "blocks of Gpa left at exit (--check-alloc):"; cat "$dir/stderr"; } >"$dir/why"
        return 1
    fi
    if [ -s "$dir/ppms" ] && ! check_ppms "$dir"; then
        return 1
    fi
    # (0.19) A program that may test the CPU at run time (std::arch::detect,
    # #[multiversion]) runs again with every optional feature disabled:
    # its fallback paths must print the same (docs/design/arch.md §2.5).
    if grep -q -E 'detect\(|#\[multiversion' "$source"; then
        RUN_ENV=VOLE_ARCH_DISABLE=all
        run_program "$dir"
        RUN_ENV=
        timed_out "$dir" && return 1
        trimmed "$dir/stdout" >"$dir/actual"
        if ! stdout_matches "$dir" || [ "$RC" -ne "$expected_exit" ]; then
            {
                echo "with VOLE_ARCH_DISABLE=all (the fallback paths): exit code $RC, stdout"
                echo "--- expected"; cat "$dir/wanted"; echo
                echo "--- actual"; cat "$dir/actual"; echo
            } >"$dir/why"
            return 1
        fi
    fi
    return 0
}

# (0.25.2) A link that failed for the symbols of Apple's frameworks
# (std::window, std::gpu: Metal, Cocoa, the Objective-C runtime): one line
# naming the directives that link them, instead of the linker's list.
# Fails (prints nothing) for any other link error. (0.25.3: the
# linker's list, or volec's link.undefined, which names the symbol
# without macOS's `_`.)
framework_hint() {
    sym=$(awk '/^Undefined symbols/ { u = 1; next } u && /^  "/ { s = $1; gsub(/[",]/, "", s); print s; exit }
        index($0, "error[link.undefined] undefined symbol ") { split($0, p, sprintf("%c", 39)); print "_" p[2]; exit }' "$1")
    case "$sym" in
        _objc_*|_OBJC_*|_CF*|_NS*|_MTL*|_CA*|_CG*|_kCF*|_IOSurface*|_dispatch_*) ;;
        *) return 1 ;;
    esac
    echo "link failed: undefined framework symbols (first: $sym): the program imports std::window or std::gpu; add the directives '// LINK: std::gpu and std::window name the frameworks they link' and '// REQUIRES: metal' to its case (as tests/examples/nes.test has)"
}

# FIXIMPORTS, FIXUNSAFE: a copy of case $1 (in $2/fix/run, next to a link
# to tests/c, which cases include from) is rewritten by option $3
# (--fix-imports or --fix-unsafe); `source` becomes the copy.
fix_case() {
    fixdir="$2/fix"
    mkdir -p "$fixdir/run"
    ln -s "$ROOT/tests/c" "$fixdir/c"
    case "$1" in
        */main.vl)
            cp -R "$(dirname "$1")" "$fixdir/run/"
            source="$fixdir/run/$(basename "$(dirname "$1")")/main.vl" ;;
        *)
            cp "$1" "$fixdir/run/"
            source="$fixdir/run/$(basename "$1")" ;;
    esac
    if ! "$COMPILER" --target "$TARGET" "$3" "$source" >"$2/fix.out" 2>&1; then
        { echo "$3 failed:"; cat "$2/fix.out"; } >"$2/why"
        return 1
    fi
    if ! "$COMPILER" --target "$TARGET" "$3" "$source" >"$2/fix2.out" 2>&1 || [ -s "$2/fix2.out" ]; then
        { echo "a second $3 did not leave the program as it was:"; cat "$2/fix2.out"; } >"$2/why"
        return 1
    fi
    find "$fixdir/run" -name '*.vl' -exec cat {} + | grep -v '^[[:space:]]*//' >"$2/fixed.txt"
    while IFS= read -r text; do
        if ! grep -qF -- "$text" "$2/fixed.txt"; then
            { echo "the rewritten program has no line containing '$text':"; cat "$2/fixed.txt"; } >"$2/why"
            return 1
        fi
    done <"$2/fixed"
    return 0
}

# PROFILE: case $1 compiled with --profile-generate, run and checked; then
# FLAGS use the profile it wrote.
profile_case() {
    # (At the CHECK level: -O0 takes no profile.)
    # shellcheck disable=SC2086
    if ! "$COMPILER" --target "$TARGET" "-O$(cat "$2/checkopt")" $FLAGS --profile-generate "$2/profile.data" "$1" -o "$2/$OUT" >"$2/compile.out" 2>&1; then
        { echo "--profile-generate failed:"; cat "$2/compile.out"; } >"$2/why"
        return 1
    fi
    # shellcheck disable=SC2086
    if ! cc_run $LINK_FLAGS -o "$2/prog" "$2/$OUT" -lm >"$2/link.out" 2>&1; then
        { echo "link failed (instrumented):"; cat "$2/link.out"; } >"$2/why"
        return 1
    fi
    run_program "$2"
    timed_out "$2" && return 1
    trimmed "$2/stdout" >"$2/actual"
    trimmed "$2/expect" >"$2/wanted"
    if [ "$RC" -ne "$(cat "$2/exit")" ] || ! stdout_matches "$2"; then
        { echo "the instrumented program (exit $RC) printed:"; cat "$2/stdout"; } >"$2/why"
        return 1
    fi
    if [ ! -s "$2/profile.data" ]; then
        echo "the instrumented program wrote no profile" >"$2/why"
        return 1
    fi
    PFLAGS="--profile-use $2/profile.data"
    return 0
}

# Matches the CHECK directives against the optimized IR of $1.
check_ir() {
    # shellcheck disable=SC2086
    if ! "$COMPILER" --target "$TARGET" "-O$(cat "$2/checkopt")" $FLAGS $PFLAGS --verify-ir --emit-ir "$1" -o "$2/ir.txt" >"$2/compile.out" 2>&1; then
        { echo "--emit-ir failed:"; cat "$2/compile.out"; } >"$2/why"
        return 1
    fi
    match_checks "$2/ir.txt" "$2/checks" "$2/check.out" && return 0
    { cat "$2/check.out"; echo "--- IR:"; cat "$2/ir.txt"; } >"$2/why"
    return 1
}

# PLACES (0.26.0): the elaborated places IR of $1 (`check --emit-places
# --places-diff`) matched against the PLACES lines, with no difference
# listed; first a plain `check` makes the tools' cache in $2/pcache, which
# the places options must not answer from (tools/query/cache.vl).
check_places() {
    rm -rf "$2/pcache"
    # (FLAGS but a build's own: --check-alloc)
    cflags=$(printf '%s\n' $FLAGS | grep -v -e '^--check-alloc$' | tr '\n' ' ')
    # shellcheck disable=SC2086
    VOLE_CACHE="$2/pcache" VOLE_CACHE_TRACE="$2/ptrace" "$COMPILER" check $cflags "$1" >/dev/null 2>&1
    # shellcheck disable=SC2086
    if ! VOLE_CACHE="$2/pcache" "$COMPILER" check $cflags --emit-places --places-diff "$1" >"$2/places.txt" 2>"$2/places.err"; then
        { echo "check --emit-places failed:"; cat "$2/places.err"; } >"$2/why"
        return 1
    fi
    if grep -q '^places\.diff: .*: ' "$2/places.err"; then
        { echo "--places-diff lists differences:"; grep '^places\.diff' "$2/places.err"; } >"$2/why"
        return 1
    fi
    match_checks "$2/places.txt" "$2/places" "$2/check.out" && return 0
    { cat "$2/check.out"; echo "--- places IR:"; cat "$2/places.txt"; } >"$2/why"
    return 1
}

# Matches the ASM directives against the assembly of $1 for the target.
check_asm() {
    # shellcheck disable=SC2086
    if ! "$COMPILER" --target "$TARGET" "-O$(cat "$2/checkopt")" $FLAGS $PFLAGS "$1" -o "$2/check.s" >"$2/compile.out" 2>&1; then
        { echo "compile failed:"; cat "$2/compile.out"; } >"$2/why"
        return 1
    fi
    match_checks "$2/check.s" "$2/asms" "$2/check.out" && return 0
    { cat "$2/check.out"; echo "--- assembly:"; cat "$2/check.s"; } >"$2/why"
    return 1
}

# CROSS (0.19): case $1 compiled for the CROSS target, to an object at the
# suite's level and to assembly at the CHECK level, the assembly matched
# against its ASM lines for that target; nothing run.
check_cross() {
    # (0.28.0) one target or several, each in turn
    for cross in $(cat "$2/cross"); do
        # shellcheck disable=SC2086
        if ! "$COMPILER" --target "$cross" $OPT $FLAGS "$1" -c -o "$2/cross.o" >"$2/compile.out" 2>&1; then
            { echo "compile for $cross failed:"; cat "$2/compile.out"; } >"$2/why"
            return 1
        fi
        # shellcheck disable=SC2086
        if ! "$COMPILER" --target "$cross" "-O$(cat "$2/checkopt")" $FLAGS "$1" -S -o "$2/cross.s" >"$2/compile.out" 2>&1; then
            { echo "compile for $cross (-S) failed:"; cat "$2/compile.out"; } >"$2/why"
            return 1
        fi
        [ -s "$2/crossasms.$cross" ] || continue
        match_checks "$2/cross.s" "$2/crossasms.$cross" "$2/check.out" && continue
        { cat "$2/check.out"; echo "--- assembly for $cross:"; cat "$2/cross.s"; } >"$2/why"
        return 1
    done
    return 0
}

# Matches the checks in file $2 (+text: a line containing text, after the
# previous one; -text: none until the next) against the lines of $1;
# writes what failed to $3.
match_checks() {
    awk -v checks="$2" '
        { line[NR] = $0 }
        END {
            n = 0
            while ((getline c < checks) > 0) { kind[n] = substr(c, 1, 1); text[n] = substr(c, 2); n++ }
            pos = 0
            nots = 0
            for (i = 0; i < n; i++) {
                if (kind[i] == "-") { pending[nots++] = text[i]; continue }
                found = 0
                for (j = pos + 1; j <= NR; j++) if (index(line[j], text[i])) { found = j; break }
                if (!found) { print "CHECK not found after line " pos ": " text[i]; exit 1 }
                for (k = 0; k < nots; k++)
                    for (j = pos + 1; j < found; j++)
                        if (index(line[j], pending[k])) { print "CHECK-NOT found at line " j ": " pending[k]; exit 1 }
                nots = 0
                pos = found
            }
            for (k = 0; k < nots; k++)
                for (j = pos + 1; j <= NR; j++)
                    if (index(line[j], pending[k])) { print "CHECK-NOT found at line " j ": " pending[k]; exit 1 }
        }
    ' "$1" >"$3" 2>&1
}

# (0.30, --bless) Case $1 (file $2, run in directory $3, failed): when
# its ERROR directives are the errors the compiler reports but for their
# positions, the directives are rewritten in the file with the positions
# of now and the case is run again; says `blessed NAME: ...` or `not
# blessed NAME: why` (the file then as it was).
bless_case() {
    if [ ! -s "$3/errors" ]; then
        echo "not blessed $1: it has no ERROR directive (only those are rewritten)"
        return 1
    fi
    if [ -s "$3/xfail" ]; then
        echo "not blessed $1: it is XFAIL ($(cat "$3/xfail"))"
        return 1
    fi
    if [ "$(cat "$3/compile.rc" 2>/dev/null)" != 1 ]; then
        echo "not blessed $1: the compiler reports no error now (exit code $(cat "$3/compile.rc" 2>/dev/null))"
        return 1
    fi
    # The directives with the positions of the output: each one's text,
    # every `line L, column C` in it aside, in a line of the output after
    # the line of the one before it; that line's positions are written.
    if ! awk -v out="$3/compile.out" '
        function norm(s,   r) {
            r = ""
            while (match(s, /line [0-9]+, column [0-9]+/)) {
                r = r substr(s, 1, RSTART - 1) M
                s = substr(s, RSTART + RLENGTH)
            }
            return r s
        }
        BEGIN { M = sprintf("%c", 1); while ((getline l < out) > 0) text[++n] = l; at = 0 }
        {
            d = $0
            nd = norm(d)
            j = at + 1
            while (j <= n && index(norm(text[j]), nd) == 0) j++
            if (j > n) {
                printf "the compiler does not report %s%s%s%s, positions aside (a changed message is not blessed: read it, then edit the directive)\n", \
                    sprintf("%c", 39), d, sprintf("%c", 39), (NR > 1 ? " after the errors before it" : "") | "cat 1>&2"
                exit 1
            }
            # (the positions of that line the directive names: the ones
            # after those before its text)
            t = norm(text[j])
            pre = substr(t, 1, index(t, nd) - 1)
            q = 0
            for (i = 1; i <= length(pre); i++) if (substr(pre, i, 1) == M) q++
            np = 0
            s = text[j]
            while (match(s, /line [0-9]+, column [0-9]+/)) {
                p[++np] = substr(s, RSTART, RLENGTH)
                s = substr(s, RSTART + RLENGTH)
            }
            r = ""
            s = d
            while (match(s, /line [0-9]+, column [0-9]+/)) {
                r = r substr(s, 1, RSTART - 1) p[++q]
                s = substr(s, RSTART + RLENGTH)
            }
            print r s
            at = j
        }' "$3/errors" >"$3/bless.new" 2>"$3/bless.why"; then
        echo "not blessed $1: $(head -1 "$3/bless.why")"
        return 1
    fi
    if cmp -s "$3/errors" "$3/bless.new"; then
        echo "not blessed $1: its ERROR directives hold as they are; it fails otherwise: $(head -1 "$3/why")"
        return 1
    fi
    cp "$2" "$3/bless.orig"
    # (the k-th ERROR directive of the file, as tests/directives.awk reads
    # them, gets the k-th text)
    awk -v new="$3/bless.new" '
        BEGIN { while ((getline l < new) > 0) text[++n] = l }
        {
            line = $0
            sub(/\r$/, "", line)
            sub(/^[ \t]+/, "", line)
            if (substr(line, 1, 2) == "//") {
                c = substr(line, 3)
                if (substr(c, 1, 1) == " ") c = substr(c, 2)
                if (substr(c, 1, 6) == "ERROR:") {
                    k++
                    print substr($0, 1, index($0, "ERROR:") + 5) " " text[k]
                    next
                }
            }
            print
        }' "$3/bless.orig" >"$3/bless.file" && cp "$3/bless.file" "$2"
    bless_changes=$(awk -v new="$3/bless.new" '
        { getline t < new; if (t != $0) { n++; if (n <= 3) list = list (n > 1 ? "; " : "") $0 " -> " t } }
        END { printf "%d directive%s: %s%s", n, (n == 1 ? "" : "s"), list, (n > 3 ? "; ..." : "") }' "$3/errors")
    rm -f "$3/status"
    read_directives "$2" "$3"
    run_case "$2" "$3" </dev/null
    if [ "$(cat "$3/status" 2>/dev/null)" != pass ]; then
        cp "$3/bless.orig" "$2"
        echo "not blessed $1: with the positions of now it still fails (the file is as it was): $(head -1 "$3/why")"
        echo fail >"$3/status"
        return 1
    fi
    echo "blessed $1: $bless_changes"
}

# The number of CPUs, for -j.
cpu_count() {
    n=$(sysctl -n hw.ncpu 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 4)
    case "$n" in
        ''|*[!0-9]*) echo 4 ;;
        *) echo "$n" ;;
    esac
}

# Runs case $1 in directory $2: its outcome in $2/status.
run_case() {
    file=$1
    dir=$2
    # (0.30.1: what a skip needed, for its record: requires:WORD)
    if grep -qw clang "$dir/requires" && [ $CC_IS_CLANG -eq 0 ]; then
        echo skip >"$dir/status"
        echo requires:clang >"$dir/skipwhy"
        return
    fi
    if grep -qw metal "$dir/requires" && [ "$TARGET" != aarch64-macos ]; then
        echo skip >"$dir/status"
        echo requires:metal >"$dir/skipwhy"
        return
    fi
    if grep -qw macos "$dir/requires"; then
        case "$TARGET" in *-macos) ;; *) echo skip >"$dir/status"; echo requires:macos >"$dir/skipwhy"; return ;; esac
    fi
    if check_case "$file" "$dir"; then
        if [ -s "$dir/xfail" ]; then echo xpass; else echo pass; fi
    elif [ -s "$dir/xfail" ]; then
        echo xfail
    else
        echo fail
    fi >"$dir/status"
}

# (0.30) The plan, the first line, before anything runs: how many cases,
# which suites (a suite given names: `refactor: NAME`). Nothing selected
# is an error here, not after the checks below.
CASES="$WORK/cases"
all_cases | select_names >"$CASES"
plan_suites=""
nsuites=0
for s in $SUITES; do
    [ -z "$(want "$s")" ] && continue
    case "$TARGET:$s" in
        aarch64-macos:*) ;;
        *:voltty_render|*:window) continue ;;
    esac
    eval "sub=\${SUB_$(echo "$s" | tr - _):-}"
    plan_suites="$plan_suites${plan_suites:+, }$s${sub:+:$sub}"
    nsuites=$((nsuites + 1))
done
ncases=$(wc -l <"$CASES" | tr -d ' ')
# (one FILTER of several that selects nothing: said, the others run)
{
    all_cases
    [ "$CASES_ONLY" = 1 ] || printf '%s\n' $SUITES
} | awk 'BEGIN { nf = split(ENVIRON["VOLE_RUN_FILTERS"], f, "\n") }
    {
        for (i = 1; i <= nf; i++)
            if (!(i in hit) && f[i] != "" && (f[i] ~ /^=/ ? $1 == substr(f[i], 2) : index($1, f[i]) > 0)) hit[i] = 1
    }
    END { for (i = 1; i <= nf; i++) if (f[i] != "" && !(i in hit)) print f[i] }' >"$WORK/nomatch"
if [ -s "$WORK/nomatch" ] && { [ "$ncases" != 0 ] || [ -n "$plan_suites" ]; }; then
    echo "tests/run.sh: warning: no case matches $(sed "s/^=//; s/.*/'&'/" "$WORK/nomatch" | tr '\n' ' ' | sed 's/ $//') (the other FILTERs select the plan below)" >&2
fi
if [ "$ncases" = 0 ] && [ -z "$plan_suites" ]; then
    echo "tests/run.sh: no case matches '$FILTER'$([ "$CASES_ONLY" = 1 ] && echo " (--cases-only: no suite is run)") (tests/run.sh -l FILTER lists what a FILTER selects)" >&2
    exit 2
fi
if [ -n "$JOBS" ]; then
    plan_jobs="-j $JOBS"
elif [ -n "${VOLE_JOBSERVER:-}" ] && [ -p "$VOLE_JOBSERVER" ]; then
    plan_jobs="the jobserver's slots"
else
    plan_jobs="-j $(cpu_count) (the CPUs; -j JOBS for fewer)"
fi
echo "plan: $ncases case$([ "$ncases" = 1 ] || echo s), $nsuites suite$([ "$nsuites" = 1 ] || echo s)${plan_suites:+ ($plan_suites)}, $plan_jobs${OPT:+, $OPT}, $TARGET"

# A suite, in the background: `$@` run, its output in $WORK/$1.out; when
# it ends, one line (0.30): its pass and FAIL lines counted, its exit
# status, the seconds it took.
run_suite() {
    rs_name=$1
    shift
    (
        rs_start=$(date +%s)
        "$@" >"$WORK/$rs_name.out" 2>&1
        rs_rc=$?
        echo "suite $rs_name: $(grep -c '^pass' "$WORK/$rs_name.out") pass, $(grep -c '^FAIL' "$WORK/$rs_name.out") FAIL, exit $rs_rc, $(($(date +%s) - rs_start)) s"
    ) &
}

# The standard library built into the compiler must be its source's (0.5;
# 0.27.5: its index of units, std_units, made by the compiler tested).
if [ -x "$ROOT/compiler/std/embed.sh" ] && ! VOLE_EMBED_VOLEC="$COMPILER" "$ROOT/compiler/std/embed.sh" -c; then
    exit 1
fi
# (0.19) The intrinsic tables, compiler/arch/*.def, as tables.vl has them.
if [ -x "$ROOT/compiler/arch/embed.sh" ] && ! "$ROOT/compiler/arch/embed.sh" -c; then
    exit 1
fi

# (0.21) Every VOLE_X the compiler reads (a c"VOLE_X" literal) is
# also read as VOLE_X, the name from 0.24: it is in base::ENV_NAMES.
for v in $(grep -rhoE --exclude-dir=.volec 'c"VOLE_[A-Z0-9_]+"' "$ROOT/compiler/src" | sed 's/^c"VOLE_//; s/"$//' | sort -u); do
    if ! grep -q "c\"$v\"" "$ROOT/compiler/src/base/mod.vl"; then
        echo "error: VOLE_$v is read by the compiler but not as VOLE_$v: add \"$v\" to ENV_NAMES (compiler/src/base/mod.vl)" >&2
        exit 1
    fi
done

# The optimizer's rewrite rules, on random values (0.9).
if "$COMPILER" --check-rules >"$WORK/rules.out" 2>&1; then :; else
    grep -q 'rewrite rules' "$WORK/rules.out" && { cat "$WORK/rules.out"; exit 1; }
fi

# The cases ($CASES, above), in order; up to JOBS at once (a FIFO holds
# the free slots).

# The tools' suites (below) run alongside the cases: they are serial.
# (0.30) With -j given, the query and refactor suites run their
# transcripts and checks some at once (each): JOBS when the filters
# select no case, two at most beside the cases (the refactor suite, 16
# minutes one by one, was what a plan waited for). Without -j (the
# gate's rows, on the jobserver's slots): one by one, as before.
TJOBS=1
if [ -n "$JOBS" ]; then
    TJOBS=$JOBS
    [ ! -s "$CASES" ] || [ "$JOBS" -le 2 ] || TJOBS=2
fi
case $(want query) in
    y) run_suite query "$ROOT/tests/query/run.sh" -c "$COMPILER" -j "$TJOBS" $SUB_query ;;
esac
case $(want refactor) in
    y) run_suite refactor "$ROOT/tests/refactor/run.sh" -c "$COMPILER" -j "$TJOBS" $SUB_refactor ;;
esac
case $(want guide) in
    y) run_suite guide "$ROOT/tests/guide/run.sh" -c "$COMPILER" ;;
esac
# (0.25) The book's blocks and sessions (tests/book/run.sh): category "book".
case $(want book) in
    y) run_suite book "$ROOT/tests/book/run.sh" -c "$COMPILER" ;;
esac
case $(want fmt) in
    y) run_suite fmt "$ROOT/tests/fmt/run.sh" -c "$COMPILER" -j 1 $SUB_fmt ;;
esac
case $(want walkthrough) in
    y) run_suite walkthrough "$ROOT/tests/walkthrough/run.sh" -c "$COMPILER" ;;
esac
case $(want wgsl) in
    y) run_suite wgsl "$ROOT/tests/wgsl/run.sh" -c "$COMPILER" ;;
esac
case $(want voltty) in
    y) run_suite voltty "$ROOT/tests/voltty/run.sh" -c "$COMPILER" -n 20 ;;
esac
# (0.27.1) the borrow checker's try: lines (tests/borrowck-try/run.sh)
case $(want borrowck-try) in
    y) run_suite borrowck-try sh "$ROOT/tests/borrowck-try/run.sh" -c "$COMPILER" ;;
esac
# (0.25.3) Text blocks in a CRLF file and the caches seeing an embedded
# file change (tests/embed/run.sh): category "embed-checks".
case $(want embed-checks) in
    y) run_suite embed-checks sh "$ROOT/tests/embed/run.sh" -c "$COMPILER" ;;
esac
# (0.25.3) std's positions in the transcripts, compared normalized: a std
# change moves none of them (tests/stdpos/run.sh): category "stdpos".
case $(want stdpos) in
    y) run_suite stdpos sh "$ROOT/tests/stdpos/run.sh" -c "$COMPILER" -j "$TJOBS" ;;
esac
# (0.30) std inside the tools: std's files named in errors, queries,
# edits and fixes, and `check --std`, in a copy of compiler/std
# (tests/stdtools.sh): category "stdtools".
case $(want stdtools) in
    y) run_suite stdtools sh "$ROOT/tests/stdtools.sh" -c "$COMPILER" ;;
esac
# (0.25.3) The tools' answers from their cache the same as without it, on
# a sample of the transcripts (tests/cachediff/run.sh --sample; all of
# them: the gate's cachediff step): category "cachediff".
case $(want cachediff) in
    y) run_suite cachediff sh "$ROOT/tests/cachediff/run.sh" -c "$COMPILER" --sample ;;
esac
# (0.25.2) The runner's own pieces (tests/runner/run.sh: the EXPECT holes,
# the golden-image comparison, the directives): category "runner".
case $(want runner) in
    y) run_suite runner env VOLE_TEST_COMPILER="$COMPILER" sh "$ROOT/tests/runner/run.sh" ;;
esac
# (0.24) The language server's sessions (tests/lsp/run.sh): category "lsp".
case $(want lsp) in
    y) run_suite lsp "$ROOT/tests/lsp/run.sh" -c "$COMPILER" $SUB_lsp ;;
esac
# (0.25) The link without cc, and its template (tests/link/run.sh):
# category "link". (macOS and Linux hosts; the target's own)
case $(want link) in
    y) run_suite link "$ROOT/tests/link/run.sh" -c "$COMPILER" ;;
esac
# (0.25.5) The build's measuring options (tests/perf/run.sh:
# --time-passes=instructions, --vec-stats=FN): category "perf".
case $(want perf) in
    y) run_suite perf "$ROOT/tests/perf/run.sh" -c "$COMPILER" ;;
esac
# (0.22) std::gpu and std::objc: tests/gpu/run.sh, Metal on macOS/arm64
# (skipped elsewhere); category "gpu".
case $(want gpu) in
    y)
        GPU_OPT=""
        [ -n "$OPT" ] && GPU_OPT="-O ${OPT#-O}"
        run_suite gpu "$ROOT/tests/gpu/run.sh" -c "$COMPILER" $GPU_OPT ;;
esac
# (0.18.1) The agent hooks' cases (tools/agent-hooks/test-*.py, Python;
# skipped without python3): category "hooks"; (0.25.3) and the commit
# hook's (tools/git-hooks/test-*.py).
case $(want hooks) in
    y)
        if command -v python3 >/dev/null 2>&1; then
            # (0.25.2.1) the compiler under test, not target/volec, for the
            # cases that run a real one; (0.30) TJOBS files at once (the
            # query suite's rule, above), their reports in the files' order
            hooks_cases() {
                hd="$WORK/hooks.d"
                mkdir -p "$hd"
                mkfifo "$hd/slots"
                exec 5<>"$hd/slots"
                hi=0
                while [ "$hi" -lt "$TJOBS" ]; do echo >&5; hi=$((hi + 1)); done
                hi=0
                for t in "$ROOT"/tools/agent-hooks/test-*.py "$ROOT"/tools/git-hooks/test-*.py; do
                    hi=$((hi + 1))
                    read -r _ <&5
                    ( trap 'echo >&5' EXIT; VOLE_HOOKS_JOBS=$TJOBS VOLE_TEST_COMPILER="$COMPILER" python3 -I "$t" >"$hd/$hi.out" 2>&1 ) &
                done
                wait
                exec 5>&-
                hi=0
                for t in "$ROOT"/tools/agent-hooks/test-*.py "$ROOT"/tools/git-hooks/test-*.py; do
                    hi=$((hi + 1))
                    cat "$hd/$hi.out"
                done
                ! cat "$hd"/*.out | grep -q '^FAIL'
            }
            run_suite hooks hooks_cases
        else
            : >"$WORK/hooks.out"
        fi ;;
esac
# (0.19) std::arch's generated programs (tests/arch/gen.sh): every
# intrinsic against its reference, at run time and folded, at this
# level (without -O: at -O0 and -O2).
case $(want arch-gen) in
    y)
        arch_levels=${OPT#-O}
        [ -n "$arch_levels" ] || arch_levels=0,2
        run_suite arch-gen "$ROOT/tests/arch/gen.sh" -c "$COMPILER" -o "$WORK/arch-gen" -O "$arch_levels" --check ;;
esac
# (0.19 T5) The x86-64 encoder against cc's assembler, byte for byte
# (tests/arch/enc.sh: every instruction of insn_x86.def, extreme registers,
# both widths, memory forms).
case $(want arch-enc) in
    y)
        run_suite arch-enc "$ROOT/tests/arch/enc.sh" -c "$COMPILER" -o "$WORK/arch-enc" ;;
esac
# The window library and the terminal's renderer (0.23): macOS hosts,
# for the host's own target only.
case "$TARGET" in
    aarch64-macos)
        case $(want voltty_render) in
            y) run_suite voltty_render "$ROOT/tests/voltty-render/run.sh" -c "$COMPILER" ;;
        esac
        case $(want window) in
            y) run_suite window "$ROOT/tests/window/run.sh" -c "$COMPILER" ;;
        esac ;;
    *) : >"$WORK/voltty_render.out"; : >"$WORK/window.out" ;;
esac

# The slots: JOBS of them in a FIFO of our own, or the shared ones of
# $VOLE_JOBSERVER (see above).
if [ -z "$JOBS" ] && [ -n "${VOLE_JOBSERVER:-}" ] && [ -p "$VOLE_JOBSERVER" ]; then
    exec 3<>"$VOLE_JOBSERVER"
else
    [ -n "$JOBS" ] || JOBS=$(cpu_count)
    mkfifo "$WORK/slots"
    exec 3<>"$WORK/slots"
    i=0
    while [ "$i" -lt "$JOBS" ]; do
        echo >&3
        i=$((i + 1))
    done
fi
while read -r name file; do
    dir="$WORK/$name"
    mkdir -p "$dir"
    read_directives "$file" "$dir"
    read -r _ <&3
    # (0.25.2) The job gives its slot back however it ends (a trap: its
    # end, an exit in it, a signal), as every runner's jobs do: a slot
    # lost with a killed job left a release gate waiting for 2.5 hours.
    # (A job killed with -9 still loses it; the gate reports the stall.)
    ( trap 'echo >&3' EXIT; trap 'exit 1' HUP INT TERM; run_case "$file" "$dir" ) &
done <"$CASES"
wait
exec 3>&-

# (0.30, --bless) The cases that failed: their ERROR directives' positions.
if [ "$BLESS" = 1 ]; then
    while read -r name file; do
        [ "$(cat "$WORK/$name/status" 2>/dev/null)" = fail ] || continue
        bless_case "$name" "$file" "$WORK/$name" </dev/null
    done <"$CASES"
fi

count=0
: >"$WORK/casetally"
: >"$WORK/records"
: >"$WORK/caseskips"
: >"$WORK/casenames"
while read -r name file; do
    dir="$WORK/$name"
    category=${name%%_*}
    [ -s "$dir/errors" ] && category=error
    status=fail
    [ -f "$dir/status" ] && read -r status <"$dir/status"
    # (0.30.1) the cases' own outcomes, apart from the suites' (the
    # `cases:` line, which the gate's floors read)
    case "$status" in pass|xfail|skip) echo "$status" ;; *) echo fail ;; esac >>"$WORK/casetally"
    echo "$name" >>"$WORK/casenames"
    # (each skipped case by name, with what it requires, for the floors)
    [ "$status" = skip ] && echo "skip case $name: REQUIRES$(cat "$dir/requires" 2>/dev/null)" >>"$WORK/caseskips"
    if [ "$status" = xpass ]; then
        echo "$category fail" >>"$TALLY"
        echo "XPASS $name: passes but is marked XFAIL ($(cat "$dir/xfail")); remove the directive" >>"$FAILURES"
    elif [ "$status" = fail ]; then
        echo "$category fail" >>"$TALLY"
        { echo "FAIL $name:"; sed 's/^/    /' "$dir/why"; echo; } >>"$FAILURES"
        echo "$name" >>"$WORK/failed-cases"
    else
        echo "$category $status" >>"$TALLY"
        # (0.27.2) VOLE_TEST_XFAIL_WHY=FILE: each XFAIL case's failure,
        # its name, the first line of why and its first error, for a triage
        if [ "$status" = xfail ] && [ -n "$XFAIL_WHY_FILE" ]; then
            printf '%s\t%s\t%s\n' "$name" "$(head -1 "$dir/why" 2>/dev/null | tr '\t' ' ')" \
                "$(grep -m1 'error' "$dir/why" 2>/dev/null | tr '\t' ' ')" >>"$XFAIL_WHY_FILE"
        fi
    fi
    # (0.27.2.1) VOLE_TEST_RESULTS=FILE: each case's name, its status
    # (pass, xfail, fail, xpass, skip) and how many borrowck errors its
    # compilation had at std's positions (`<std>:L:C`), one line each: the
    # gate's std-tests and std-check rows read the suite rows' builds of
    # std's cases from it instead of building them again. (0.30.1) Each
    # record also has why a skipped case was skipped (`requires:WORD`, the
    # REQUIRES that does not hold; `-` for the others) and whether cc is
    # clang (`cc:clang`, `cc:other`): the gate's floors judge the suite
    # rows from these records, every case by name, and from nothing else.
    bck=0
    [ -f "$dir/compile.out" ] && bck=$(grep -c '^<std>:[0-9]*:[0-9]*: error\[borrowck' "$dir/compile.out")
    why=-
    [ "$status" = skip ] && [ -s "$dir/skipwhy" ] && why=$(cat "$dir/skipwhy")
    record="$name $status $bck $why cc:$([ $CC_IS_CLANG -eq 1 ] && echo clang || echo other)"
    echo "$record" >>"$WORK/records"
    [ -z "$RESULTS_FILE" ] || echo "$record" >>"$RESULTS_FILE"
    count=$((count + 1))
done <"$CASES"

# `volec query` (0.11): tests/query/run.sh (run above), its transcripts
# and its checks on the compiler's own source; category "query".
case $(want query) in
    y)
        while read -r status _; do
            case "$status" in
                pass) echo "query pass" >>"$TALLY"; count=$((count + 1)) ;;
                FAIL) echo "query fail" >>"$TALLY"; count=$((count + 1)) ;;
            esac
        done <"$WORK/query.out"
        if ! grep -q '^pass' "$WORK/query.out"; then
            echo "query fail" >>"$TALLY"
            count=$((count + 1))
            { echo "FAIL query: tests/query/run.sh reported nothing:"; sed 's/^/    /' "$WORK/query.out" | head -20; echo; } >>"$FAILURES"
        fi
        awk '/^FAIL/ { p = 1 } /^(pass|query:)/ { p = 0 } p' "$WORK/query.out" >>"$FAILURES"
        ;;
esac

# `volec lsp` (0.24): tests/lsp/run.sh (run above), its sessions and
# its check on the compiler's own source; category "lsp".
case $(want lsp) in
    y)
        while read -r status _; do
            case "$status" in
                pass) echo "lsp pass" >>"$TALLY"; count=$((count + 1)) ;;
                FAIL) echo "lsp fail" >>"$TALLY"; count=$((count + 1)) ;;
            esac
        done <"$WORK/lsp.out"
        if ! grep -q '^pass' "$WORK/lsp.out"; then
            echo "lsp fail" >>"$TALLY"
            count=$((count + 1))
            { echo "FAIL lsp: tests/lsp/run.sh reported nothing:"; sed 's/^/    /' "$WORK/lsp.out" | head -20; echo; } >>"$FAILURES"
        fi
        awk '/^FAIL/ { p = 1 } /^pass/ { p = 0 } p' "$WORK/lsp.out" >>"$FAILURES"
        ;;
esac

# The runner's own checks (0.25.2, run above); category "runner".
case $(want runner) in
    y)
        while read -r status _; do
            case "$status" in
                pass) echo "runner pass" >>"$TALLY"; count=$((count + 1)) ;;
                FAIL) echo "runner fail" >>"$TALLY"; count=$((count + 1)) ;;
            esac
        done <"$WORK/runner.out"
        if ! grep -q '^pass' "$WORK/runner.out"; then
            echo "runner fail" >>"$TALLY"
            count=$((count + 1))
            { echo "FAIL runner: tests/runner/run.sh reported nothing:"; sed 's/^/    /' "$WORK/runner.out" | head -20; echo; } >>"$FAILURES"
        fi
        grep '^FAIL' "$WORK/runner.out" >>"$FAILURES"
        ;;
esac

# Text blocks and embedded files (0.25.3, run above); category
# "embed-checks".
case $(want embed-checks) in
    y)
        while read -r status _; do
            case "$status" in
                pass) echo "embed-checks pass" >>"$TALLY"; count=$((count + 1)) ;;
                FAIL) echo "embed-checks fail" >>"$TALLY"; count=$((count + 1)) ;;
            esac
        done <"$WORK/embed-checks.out"
        if ! grep -q '^pass' "$WORK/embed-checks.out"; then
            echo "embed-checks fail" >>"$TALLY"
            count=$((count + 1))
            { echo "FAIL embed-checks: tests/embed/run.sh reported nothing:"; sed 's/^/    /' "$WORK/embed-checks.out" | head -20; echo; } >>"$FAILURES"
        fi
        awk '/^FAIL/ { p = 1 } /^pass/ { p = 0 } p' "$WORK/embed-checks.out" >>"$FAILURES"
        ;;
esac

# std's positions in the transcripts (0.25.3, run above); category
# "stdpos".
case $(want stdpos) in
    y)
        while read -r status _; do
            case "$status" in
                pass) echo "stdpos pass" >>"$TALLY"; count=$((count + 1)) ;;
                FAIL) echo "stdpos fail" >>"$TALLY"; count=$((count + 1)) ;;
            esac
        done <"$WORK/stdpos.out"
        if ! grep -q '^pass' "$WORK/stdpos.out"; then
            echo "stdpos fail" >>"$TALLY"
            count=$((count + 1))
            { echo "FAIL stdpos: tests/stdpos/run.sh reported nothing:"; sed 's/^/    /' "$WORK/stdpos.out" | head -20; echo; } >>"$FAILURES"
        fi
        awk '/^FAIL/ { p = 1 } /^pass/ { p = 0 } p' "$WORK/stdpos.out" >>"$FAILURES"
        ;;
esac

# std inside the tools (0.30, run above); category "stdtools".
case $(want stdtools) in
    y)
        while read -r status _; do
            case "$status" in
                pass) echo "stdtools pass" >>"$TALLY"; count=$((count + 1)) ;;
                FAIL) echo "stdtools fail" >>"$TALLY"; count=$((count + 1)) ;;
            esac
        done <"$WORK/stdtools.out"
        if ! grep -q '^pass' "$WORK/stdtools.out"; then
            echo "stdtools fail" >>"$TALLY"
            count=$((count + 1))
            { echo "FAIL stdtools: tests/stdtools.sh reported nothing:"; sed 's/^/    /' "$WORK/stdtools.out" | head -20; echo; } >>"$FAILURES"
        fi
        awk '/^FAIL/ { p = 1 } /^pass/ { p = 0 } p' "$WORK/stdtools.out" >>"$FAILURES"
        ;;
esac

# The tools' cache (0.25.3): tests/cachediff/run.sh --sample (run above);
# category "cachediff".
case $(want cachediff) in
    y)
        while read -r status _; do
            case "$status" in
                pass) echo "cachediff pass" >>"$TALLY"; count=$((count + 1)) ;;
                FAIL) echo "cachediff fail" >>"$TALLY"; count=$((count + 1)) ;;
            esac
        done <"$WORK/cachediff.out"
        if ! grep -q '^pass' "$WORK/cachediff.out"; then
            echo "cachediff fail" >>"$TALLY"
            count=$((count + 1))
            { echo "FAIL cachediff: tests/cachediff/run.sh reported nothing:"; sed 's/^/    /' "$WORK/cachediff.out" | head -20; echo; } >>"$FAILURES"
        fi
        awk '/^FAIL/ { p = 1 } /^(pass|cachediff:)/ { p = 0 } p' "$WORK/cachediff.out" >>"$FAILURES"
        ;;
esac

# The link (0.25): tests/link/run.sh (run above); category "link".
case $(want link) in
    y)
        while read -r status _; do
            case "$status" in
                pass) echo "link pass" >>"$TALLY"; count=$((count + 1)) ;;
                FAIL) echo "link fail" >>"$TALLY"; count=$((count + 1)) ;;
            esac
        done <"$WORK/link.out"
        if ! grep -q '^pass' "$WORK/link.out"; then
            echo "link fail" >>"$TALLY"
            count=$((count + 1))
        fi
        awk '/^FAIL/ { p = 1 } /^pass/ { p = 0 } p' "$WORK/link.out" >>"$FAILURES"
        ;;
esac

# The measuring options (0.25.5): tests/perf/run.sh (run above); category
# "perf".
case $(want perf) in
    y)
        while read -r status _; do
            case "$status" in
                pass) echo "perf pass" >>"$TALLY"; count=$((count + 1)) ;;
                FAIL) echo "perf fail" >>"$TALLY"; count=$((count + 1)) ;;
            esac
        done <"$WORK/perf.out"
        if ! grep -q '^pass' "$WORK/perf.out"; then
            echo "perf fail" >>"$TALLY"
            count=$((count + 1))
        fi
        awk '/^FAIL/ { p = 1 } /^pass/ { p = 0 } p' "$WORK/perf.out" >>"$FAILURES"
        ;;
esac

# The refactoring tools (0.11: edit, undo, check, fix, lint, same-output,
# the planning queries): tests/refactor/run.sh (run above); category
# "refactor".
case $(want refactor) in
    y)
        while read -r status _; do
            case "$status" in
                pass) echo "refactor pass" >>"$TALLY"; count=$((count + 1)) ;;
                FAIL) echo "refactor fail" >>"$TALLY"; count=$((count + 1)) ;;
                xfail) echo "refactor xfail" >>"$TALLY"; count=$((count + 1)) ;;
            esac
        done <"$WORK/refactor.out"
        if ! grep -q '^pass' "$WORK/refactor.out"; then
            echo "refactor fail" >>"$TALLY"
            count=$((count + 1))
            { echo "FAIL refactor: tests/refactor/run.sh reported nothing:"; sed 's/^/    /' "$WORK/refactor.out" | head -20; echo; } >>"$FAILURES"
        fi
        awk '/^FAIL/ { p = 1 } /^(pass|xfail|refactor:)/ { p = 0 } p' "$WORK/refactor.out" >>"$FAILURES"
        ;;
esac

# `volec guide` (0.13): tests/guide/run.sh (run above), the guide's
# examples compiled and run, its std section, its budget; category
# "guide".
case $(want guide) in
    y)
        while read -r status _; do
            case "$status" in
                pass) echo "guide pass" >>"$TALLY"; count=$((count + 1)) ;;
                FAIL) echo "guide fail" >>"$TALLY"; count=$((count + 1)) ;;
            esac
        done <"$WORK/guide.out"
        if ! grep -q '^pass' "$WORK/guide.out"; then
            echo "guide fail" >>"$TALLY"
            count=$((count + 1))
        fi
        awk '/^FAIL/ { p = 1 } /^pass/ { p = 0 } p' "$WORK/guide.out" >>"$FAILURES"
        ;;
esac

# The book (0.25): tests/book/run.sh (run above), every vole block of
# book/*.md compiled, its outputs, errors and shell sessions as printed;
# category "book".
case $(want book) in
    y)
        while read -r status _; do
            case "$status" in
                pass) echo "book pass" >>"$TALLY"; count=$((count + 1)) ;;
                FAIL) echo "book fail" >>"$TALLY"; count=$((count + 1)) ;;
            esac
        done <"$WORK/book.out"
        if ! grep -q '^pass' "$WORK/book.out"; then
            echo "book fail" >>"$TALLY"
            count=$((count + 1))
        fi
        awk '/^FAIL/ { p = 1 } /^pass/ { p = 0 } p' "$WORK/book.out" >>"$FAILURES"
        ;;
esac

# The formatter (0.13): tests/fmt/run.sh (run above): the tree is
# formatted (`fmt --all --check`), and formatting changes no program;
# category "fmt".
case $(want fmt) in
    y)
        while read -r status _; do
            case "$status" in
                pass) echo "fmt pass" >>"$TALLY"; count=$((count + 1)) ;;
                FAIL) echo "fmt fail" >>"$TALLY"; count=$((count + 1)) ;;
            esac
        done <"$WORK/fmt.out"
        if ! grep -q '^pass' "$WORK/fmt.out"; then
            echo "fmt fail" >>"$TALLY"
            count=$((count + 1))
            { echo "FAIL fmt: tests/fmt/run.sh reported nothing:"; sed 's/^/    /' "$WORK/fmt.out" | head -20; echo; } >>"$FAILURES"
        fi
        awk '/^FAIL/ { p = 1 } /^pass/ { p = 0 } p' "$WORK/fmt.out" >>"$FAILURES"
        ;;
esac

# category "hooks": the agent hooks' cases, a pass or FAIL line each
case $(want hooks) in
    y)
        while read -r status _; do
            case "$status" in
                pass) echo "hooks pass" >>"$TALLY"; count=$((count + 1)) ;;
                FAIL) echo "hooks fail" >>"$TALLY"; count=$((count + 1)) ;;
            esac
        done <"$WORK/hooks.out"
        awk '/^FAIL/ { p = 1 } /^pass/ { p = 0 } p' "$WORK/hooks.out" >>"$FAILURES"
        ;;
esac

# The examples (0.15: one folder each, examples/NAME/, or a group of them,
# examples/GROUP/NAME/ under a README.md): each has a main.vl, a
# README.md and a case in tests/examples (a .test whose SOURCE is its
# main.vl); category "example". examples/tools/ (walkthroughs of the
# tools, some failing to compile on purpose) has its own runner.
case $(want example_layout) in
    y)
        for d in "$ROOT"/examples/*/ "$ROOT"/examples/*/*/; do
            [ -d "$d" ] || continue
            ex=${d%/}
            ex=${ex#"$ROOT"/examples/}
            case "$ex" in tools | tools/*) continue ;; esac
            # (0.23: examples/voltty is assembled from parallel tasks, the
            # renderer's modules first; until its main.vl lands, its
            # folders are modules, not examples)
            case "$ex" in voltty | voltty/*) [ -f "$ROOT/examples/voltty/main.vl" ] || continue ;; esac
            why=""
            case "$ex" in
                */*) ;;
                # a group: its README; its folders are the examples
                *) [ -f "$d/main.vl" ] || { [ -f "$d/README.md" ] && continue; } ;;
            esac
            # (a folder of a program's modules, not an example)
            case "$ex" in */*) [ -f "${d%/}/../main.vl" ] && continue ;; esac
            [ -f "$d/main.vl" ] || why="no main.vl"
            [ -f "$d/README.md" ] || why="$why${why:+; }no README.md"
            grep -qx "// SOURCE: examples/$ex/main.vl" "$ROOT"/tests/examples/*.test \
                || why="$why${why:+; }no tests/examples/*.test with '// SOURCE: examples/$ex/main.vl'"
            if [ -n "$why" ]; then
                echo "example fail" >>"$TALLY"
                printf 'FAIL example_layout %s:\n    %s\n\n' "$ex" "$why" >>"$FAILURES"
            else
                echo "example pass" >>"$TALLY"
            fi
            count=$((count + 1))
        done
        # (0.25.2) and every tests/examples case names files that exist: its
        # SOURCE and CSOURCE (an example moved without its case fails here,
        # by name, rather than as a compile error)
        for t in "$ROOT"/tests/examples/*.test; do
            [ -f "$t" ] || continue
            missing=$(sed -n 's|^// \(C\{0,1\}SOURCE\): *||p' "$t" | while read -r p; do
                [ -e "$ROOT/$p" ] || printf '%s ' "$p"
            done)
            if [ -n "$missing" ]; then
                echo "example fail" >>"$TALLY"
                printf 'FAIL example_layout %s:\n    names files that do not exist: %s(moved? update its SOURCE line)\n\n' \
                    "tests/examples/${t##*/}" "$missing" >>"$FAILURES"
                count=$((count + 1))
            fi
        done
        ;;
esac

# (0.25.1) Every example builds the way a reader would build it: the one
# command `volec examples/.../main.vl -o NAME`, no extra files or flags.
# Exceptions are only the examples whose point needs more (named with the
# reason below). Category "example_build"; host target only (it links).
case $(want example_build) in
    y)
        case "$(uname -s)-$(uname -m)" in
            Darwin-arm64) eb_host=aarch64-macos ;;
            Darwin-x86_64) eb_host=x86_64-macos ;;
            Linux-x86_64) eb_host=x86_64-linux ;;
            Linux-aarch64) eb_host=aarch64-linux ;;
            *) eb_host="" ;;
        esac
        if [ "$TARGET" = "$eb_host" ]; then
            # (0.25.2) Off macOS, the examples on std::gpu, std::window or
            # std::objc (Metal, Cocoa, libobjc) are skipped, with why: the
            # ones naming them in code (not a comment), or whose case says
            # `// REQUIRES: metal`.
            for m in "$ROOT"/examples/*/main.vl "$ROOT"/examples/*/*/main.vl; do
                [ -f "$m" ] || continue
                ex=${m%/main.vl}
                ex=${ex#"$ROOT"/examples/}
                case "$ex" in
                    tools | tools/*) continue ;;   # walkthroughs; some fail on purpose
                    c-mixed-build) continue ;;     # its point is linking C sources
                esac
                # (a folder of a program's modules, not an example)
                [ -f "${m%/main.vl}/../main.vl" ] && case "$ex" in */*) continue ;; esac
                case "$TARGET" in
                    *-macos) ;;
                    *)
                        if find "${m%/main.vl}" -name '*.vl' -exec cat {} + | grep -vE '^[[:space:]]*//' \
                                | grep -qE 'std::(gpu|window|objc)|use std::\{[^}]*(gpu|window|objc)::' \
                                || grep -lxF "// SOURCE: examples/$ex/main.vl" "$ROOT"/tests/examples/*.test 2>/dev/null \
                                    | xargs grep -qx '// REQUIRES: metal' 2>/dev/null; then
                            skipped example_build "example_build $ex: std::gpu and std::window need macOS (Metal, Cocoa)"
                            count=$((count + 1))
                            continue
                        fi ;;
                esac
                if "$COMPILER" "$m" -o "$WORK/example_build.bin" >"$WORK/example_build.out" 2>&1; then
                    echo "example_build pass" >>"$TALLY"
                else
                    echo "example_build fail" >>"$TALLY"
                    printf 'FAIL example_build %s:\n    `volec examples/%s/main.vl -o x` does not build:\n%s\n\n' \
                        "$ex" "$ex" "$(tail -3 "$WORK/example_build.out" | sed 's/^/    /')" >>"$FAILURES"
                fi
                count=$((count + 1))
            done
        fi
        ;;
esac

# (0.25.1) The README's example: its first code block under "## An
# example" is tests/run/readme_example.vl after its header (compiled and
# run as a case there); category "readme".
case $(want readme_sync) in
    y)
        readme_block=$(awk '/^## An example/ { s = 1; next } s && /^```/ { if (c) exit; c = 1; next } c' "$ROOT/README.md")
        readme_case=$(awk 'h { print; next } /^$/ { h = 1 }' "$ROOT/tests/run/readme_example.vl")
        if [ -n "$readme_block" ] && [ "$readme_block" = "$readme_case" ]; then
            echo "readme pass" >>"$TALLY"
        else
            echo "readme fail" >>"$TALLY"
            printf 'FAIL readme_sync:\n    README.md "An example" differs from tests/run/readme_example.vl (after its header)\n\n' >>"$FAILURES"
        fi
        count=$((count + 1))
        ;;
esac

# The examples' sessions (0.15): tests/walkthrough/run.sh (run above),
# each examples/tools/NAME/README.md (0.16: and each other
# examples/GROUP/NAME/README.md with a console block) run as a
# transcript; category "walkthrough".
case $(want walkthrough) in
    y)
        while read -r status rest; do
            case "$status" in
                pass) echo "walkthrough pass" >>"$TALLY"; count=$((count + 1)) ;;
                FAIL) echo "walkthrough fail" >>"$TALLY"; count=$((count + 1)) ;;
                skip) skipped walkthrough "walkthrough $rest"; count=$((count + 1)) ;;
            esac
        done <"$WORK/walkthrough.out"
        if ! grep -qE '^(pass|skip)' "$WORK/walkthrough.out"; then
            echo "walkthrough fail" >>"$TALLY"
            count=$((count + 1))
        fi
        awk '/^FAIL/ { p = 1 } /^(pass|skip)/ { p = 0 } p' "$WORK/walkthrough.out" >>"$FAILURES"
        ;;
esac

# The borrow checker's try: lines (0.27.1, run above): each
# tests/borrowck-try/NAME/ checked and each try: of its first error run;
# category "borrowck-try".
case $(want borrowck-try) in
    y)
        while read -r status _; do
            case "$status" in
                pass) echo "borrowck-try pass" >>"$TALLY"; count=$((count + 1)) ;;
                xfail) echo "borrowck-try xfail" >>"$TALLY"; count=$((count + 1)) ;;
                FAIL) echo "borrowck-try fail" >>"$TALLY"; count=$((count + 1)) ;;
            esac
        done <"$WORK/borrowck-try.out"
        if ! grep -q '^pass\|^xfail' "$WORK/borrowck-try.out"; then
            echo "borrowck-try fail" >>"$TALLY"
            count=$((count + 1))
        fi
        grep '^FAIL' "$WORK/borrowck-try.out" >>"$FAILURES"
        ;;
esac

# std::arch's generated programs (0.19): tests/arch/gen.sh (run above);
# category "arch-gen".
case $(want arch-gen) in
    y)
        wait
        if grep -q '^gen: ok' "$WORK/arch-gen.out"; then
            echo "arch-gen pass" >>"$TALLY"
        else
            echo "arch-gen fail" >>"$TALLY"
            { echo "FAIL arch-gen:"; sed 's/^/    /' "$WORK/arch-gen.out"; } >>"$FAILURES"
        fi
        count=$((count + 1))
        ;;
esac

# The x86-64 encodings (0.19 T5): tests/arch/enc.sh (run above); category
# "arch-enc".
case $(want arch-enc) in
    y)
        wait
        if grep -q '^enc: ok' "$WORK/arch-enc.out"; then
            echo "arch-enc pass" >>"$TALLY"
        else
            echo "arch-enc fail" >>"$TALLY"
            { echo "FAIL arch-enc:"; sed 's/^/    /' "$WORK/arch-enc.out"; } >>"$FAILURES"
        fi
        count=$((count + 1))
        ;;
esac

# The shader compiler (0.22, std::gpu::wgsl): tests/wgsl/run.sh (run
# above), its cases on the interpreter, on Metal (macOS) and through
# spirv-val where it is installed; category "wgsl".
case $(want wgsl) in
    y)
        while read -r status rest; do
            case "$status" in
                pass) echo "wgsl pass" >>"$TALLY"; count=$((count + 1)) ;;
                FAIL) echo "wgsl fail" >>"$TALLY"; count=$((count + 1)) ;;
                skip) skipped wgsl "$rest"; count=$((count + 1)) ;;
            esac
        done <"$WORK/wgsl.out"
        if ! grep -q '^pass' "$WORK/wgsl.out"; then
            echo "wgsl fail" >>"$TALLY"
            count=$((count + 1))
        fi
        awk '/^FAIL/ { p = 1 } /^(pass|skip)/ { p = 0 } p' "$WORK/wgsl.out" >>"$FAILURES"
        ;;
esac
# std::gpu's suite (run above); category "gpu".
case $(want gpu) in
    y)
        while read -r status rest; do
            case "$status" in
                pass) echo "gpu pass" >>"$TALLY"; count=$((count + 1)) ;;
                FAIL) echo "gpu fail" >>"$TALLY"; count=$((count + 1)) ;;
                skip) skipped gpu "$rest"; count=$((count + 1)) ;;
            esac
        done <"$WORK/gpu.out"
        if ! grep -q -E '^(pass|skip)' "$WORK/gpu.out"; then
            echo "gpu fail" >>"$TALLY"
            count=$((count + 1))
            { echo "FAIL gpu: tests/gpu/run.sh reported nothing:"; sed 's/^/    /' "$WORK/gpu.out" | head -20; echo; } >>"$FAILURES"
        fi
        awk '/^FAIL/ { p = 1 } /^(pass|skip|gpu:)/ { p = 0 } p' "$WORK/gpu.out" >>"$FAILURES"
        ;;
esac

# The terminal's renderer (0.23): tests/voltty-render/run.sh (run above, on
# aarch64-macos), the Core Text atlas and Metal images against the CPU
# reference; category "voltty_render".
case "$TARGET" in
    aarch64-macos)
        case $(want voltty_render) in
            y)
                while read -r status rest; do
                    case "$status" in
                        pass) echo "voltty_render pass" >>"$TALLY"; count=$((count + 1)) ;;
                        FAIL) echo "voltty_render fail" >>"$TALLY"; count=$((count + 1)) ;;
                        skip) skipped voltty_render "$rest"; count=$((count + 1)) ;;
                    esac
                done <"$WORK/voltty_render.out"
                if ! grep -q '^pass' "$WORK/voltty_render.out"; then
                    echo "voltty_render fail" >>"$TALLY"
                    count=$((count + 1))
                fi
                awk '/^FAIL/ { p = 1 } /^pass/ { p = 0 } p' "$WORK/voltty_render.out" >>"$FAILURES"
                ;;
        esac ;;
esac

# The window library (0.23): tests/window/run.sh (run above, on
# aarch64-macos), Cocoa windows and events (with a display); category
# "window".
case "$TARGET" in
    aarch64-macos)
        case $(want window) in
            y)
                while read -r status rest; do
                    case "$status" in
                        pass) echo "window pass" >>"$TALLY"; count=$((count + 1)) ;;
                        FAIL) echo "window fail" >>"$TALLY"; count=$((count + 1)) ;;
                        skip) skipped window "$rest"; count=$((count + 1)) ;;
                    esac
                done <"$WORK/window.out"
                if ! grep -q '^pass' "$WORK/window.out"; then
                    echo "window fail" >>"$TALLY"
                    count=$((count + 1))
                fi
                awk '/^FAIL/ { p = 1 } /^pass/ { p = 0 } p' "$WORK/window.out" >>"$FAILURES"
                ;;
        esac ;;
esac


# voltty, the terminal's core (0.23): tests/voltty/run.sh (run above), its
# reduced cases and seeds against the oracle's recorded dumps, and 20
# scripts of the differential fuzzer when cargo can build the oracle;
# category "voltty".
case $(want voltty) in
    y)
        while read -r status _; do
            case "$status" in
                pass) echo "voltty pass" >>"$TALLY"; count=$((count + 1)) ;;
                FAIL) echo "voltty fail" >>"$TALLY"; count=$((count + 1)) ;;
            esac
        done <"$WORK/voltty.out"
        if ! grep -q '^pass' "$WORK/voltty.out"; then
            echo "voltty fail" >>"$TALLY"
            count=$((count + 1))
        fi
        awk '/^FAIL/ { p = 1 } /^pass/ { p = 0 } p' "$WORK/voltty.out" >>"$FAILURES"
        ;;
esac

[ $count -gt 0 ] || { echo "run.sh: no cases match '$FILTER'" >&2; exit 2; }
cat "$FAILURES"
# The cases whose REQUIRES does not hold, in one line; then the skips with
# their reasons.
nreq=$(grep -c ' skip$' "$TALLY")
nwhy=$(wc -l <"$SKIPS" | tr -d ' ')
[ "$((nreq - nwhy))" -gt 0 ] && echo "SKIP $((nreq - nwhy)) cases: their REQUIRES does not hold here"
cat "$SKIPS"
echo "tests for $TARGET with $("$COMPILER" --version 2>/dev/null || echo "$COMPILER"):"
awk '
    { n[$1, $2]++; cats[$1] = 1; total[$2]++ }
    END {
        printf "  %-10s %5s %6s %5s %5s\n", "category", "pass", "xfail", "fail", "skip"
        for (c in cats) list = list c "\n"
        count = split(list, sorted, "\n")
        # Insertion sort, for awks without asort.
        for (i = 2; i < count; i++)
            for (j = i; j > 1 && sorted[j - 1] > sorted[j]; j--) {
                t = sorted[j]; sorted[j] = sorted[j - 1]; sorted[j - 1] = t
            }
        for (i = 1; i < count; i++) {
            c = sorted[i]
            printf "  %-10s %5d %6d %5d %5d\n", c, n[c, "pass"], n[c, "xfail"], n[c, "fail"], n[c, "skip"]
        }
        printf "  %-10s %5d %6d %5d %5d\n", "total", total["pass"], total["xfail"], total["fail"], total["skip"]
        if (total["skip"] > 0)
            printf "  (%d skipped, not passed: the SKIP lines above say why)\n", total["skip"]
    }
' "$TALLY"
# (0.30.1) Whether `// REQUIRES: clang` held, for the floors.
[ $CC_IS_CLANG -eq 1 ] && echo "cc: clang" || echo "cc: not clang"
# (0.30.1) The cases alone (the table's rows count the suites' checks too),
# and the names run, as a digest (`names CRC-LENGTH`: cksum of the sorted
# names, each on its line; the floors compare it with tests/run.sh -l's).
[ -f "$WORK/casetally" ] && awk -v names="$(sort "$WORK/casenames" 2>/dev/null | cksum | tr ' ' -)" '{ n[$1]++ } END {
    printf "cases: %d passed, %d xfail, %d failed, %d skipped of %d, names %s\n", n["pass"], n["xfail"], n["fail"], n["skip"], NR, names }' "$WORK/casetally"
[ -f "$WORK/caseskips" ] && cat "$WORK/caseskips"
# (0.25.5) The failing cases alone, in the form zsh leaves as it is
# (`=NAME` is its path expansion; '=NAME' quoted works too).
if [ -s "$WORK/failed-cases" ]; then
    n=$(wc -l <"$WORK/failed-cases" | tr -d ' ')
    echo "try: tests/run.sh $(head -5 "$WORK/failed-cases" | sed 's/^/-n /' | tr '\n' ' ' | sed 's/ $//')   (the failing case$( [ "$n" -gt 1 ] && echo s) alone$( [ "$n" -gt 5 ] && echo ", the first 5 of $n"))"
fi
if [ "$RERUNS" != 1 ] && [ -s "$RERUNS" ]; then
    n=$(wc -l <"$RERUNS" | tr -d ' ')
    # (0.28.0) the programs, each once: a program is built by its case and,
    # in the whole suite, twice more by the fmt suite (as it is and
    # formatted), so two programs made again on purpose
    # (rust_f_f15_prim_impl_bound_ok, _unnamed_ok) are six builds
    progs=$(grep -o '[^ ]*\.vl' "$RERUNS" | sed 's|.*/||' | sort -u)
    echo "lazy std: $n build(s) of $(echo "$progs" | wc -l | tr -d ' ') program(s) were made again with std whole (VOLE_STD_NORERUN=1 shows why; a word or a seed is missing in front/modules/stdlazy.vl); the first: $(echo "$progs" | head -8 | tr '\n' ' ' | sed 's/ $//')"
fi
if grep -q ' fail$' "$TALLY"; then
    exit 1
fi
exit 0
