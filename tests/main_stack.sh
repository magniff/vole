#!/bin/sh
# (0.30.1, RT-28) The compilation runs on a thread of its own with a 1 GiB
# stack (main.vl main, middle::threads::run_on_thread). When the system
# makes no such thread, pthread_attr_setstacksize or pthread_create
# refusing, main compiles on the process's first thread and says so,
# once, on stderr. This plants both refusals with a shim interposed on
# them (tests/main_stack/shim.c, macOS's DYLD_INSERT_LIBRARIES; SKIP
# elsewhere): the check must still pass, with the warning once; without
# the shim there is no warning, and an 8000-term chain checks
# (rt_028_long_operator_chain.vl, which the first thread's 8 MB does not
# take). (0.30.1, the review's) The warning, thread.main-stack, is said
# once in a build that fails too (a lazy std's build with errors is made
# again: the run made again does not say it), JSON under --json, and not
# by --version or explain, which compile nothing; with every stack size refused (nosize: the workers' 64 MB
# too), a -j 4 build at -O2 builds, on fewer threads, and its program
# runs. (0.30.1, the third review's) The warning is said on stderr the
# moment a command starts to read a program (base::diag::say_main_stack),
# not with the other diagnostics after the front end: a chain deep enough
# to overflow the first thread's stack (30000 terms) must crash `check`,
# a build and `--json check` with the warning already on stderr (the
# compiler before said nothing, exit 139). Every command that reads a
# program says it, once, on stderr (query, fmt, fix, test, try: the
# volecs a command starts write theirs to VOLEC_MAIN_STACK_FILE, so try's answer
# is still its type and value), and guide, --version and explain do not.
#
# usage: tests/main_stack.sh [-c COMPILER]
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
C="$ROOT/target/volec"
if [ "${1:-}" = -c ]; then
    C=$2
fi
cd "$ROOT" || exit 2
if [ "$(uname -s)" != Darwin ]; then
    echo "main-stack: SKIP: the shim is macOS's (DYLD_INSERT_LIBRARIES)"
    exit 0
fi
T=$(mktemp -d "${TMPDIR:-/tmp}/mainstack.XXXXXX")
trap 'rm -rf "$T"' EXIT
if ! cc -dynamiclib -o "$T/shim.dylib" tests/main_stack/shim.c 2> "$T/cc.txt"; then
    echo "main-stack: FAIL: the shim does not build:"; cat "$T/cc.txt"; exit 1
fi
cat > "$T/ok.vl" <<'VL'
fn main() {
    println("{}", 1 + 2);
}
VL
W="no thread with a 1 GiB stack could be made"
bad=0
VOLE_CACHE=off "$C" check "$T/ok.vl" > "$T/o" 2> "$T/e"
s=$?
if [ $s -ne 0 ] || grep -q "$W" "$T/e"; then
    echo "main-stack: FAIL: without the shim: exit $s"; cat "$T/e"; bad=1
fi
VOLE_CACHE=off "$C" check tests/run/rt_028_long_operator_chain.vl > "$T/o" 2> "$T/e"
s=$?
if [ $s -ne 0 ]; then
    echo "main-stack: FAIL: an 8000-term chain: exit $s"; bad=1
fi
cat > "$T/bad.vl" <<'VL'
fn main() {
    let x: u64 = "s";
}
VL
# (each: the shim's mode, the exit status wanted, the command line)
while read -r mode want args; do
    # shellcheck disable=SC2086
    SHIM_MODE=$mode DYLD_INSERT_LIBRARIES="$T/shim.dylib" VOLE_CACHE=off "$C" $args \
        > "$T/o" 2> "$T/e"
    s=$?
    n=$(cat "$T/o" "$T/e" | grep -c "$W")
    if [ $s -ne "$want" ] || [ "$n" -ne 1 ]; then
        echo "main-stack: FAIL: SHIM_MODE=$mode volec $args: exit $s ($want wanted), the warning $n times (1 wanted):"
        cat "$T/o" "$T/e"; bad=1
    fi
done <<LINES
nosize 0 check $T/ok.vl
nobig 0 check $T/ok.vl
nobig 1 $T/bad.vl -o $T/bad
nosize 0 -O2 -j 4 $T/ok.vl -o $T/ok4
LINES
if [ ! -x "$T/ok4" ] || [ "$("$T/ok4")" != 3 ]; then
    echo "main-stack: FAIL: the -j 4 build on no worker's stack did not run"; bad=1
fi
SHIM_MODE=nobig DYLD_INSERT_LIBRARIES="$T/shim.dylib" VOLE_CACHE=off "$C" --json check "$T/ok.vl" \
    > "$T/o" 2> "$T/e"
if ! head -1 "$T/e" | grep -q '^{"kind":"diagnostic","severity":"warning","code":"thread.main-stack"'; then
    echo "main-stack: FAIL: --json: the warning is not a JSON diagnostic on stderr:"; cat "$T/o" "$T/e"; bad=1
fi
# (the overflow the warning is for: said before the crash, on stderr; the
# loop's stderr is the shell's line on each signal)
awk 'BEGIN { printf "fn main() {\n    let x: u64 = 1"; for (i = 1; i < 30000; i++) printf " + 1"; print ";\n    println(\"{}\", x);\n}" }' \
    > "$T/deep.vl"
while read -r mode args; do
    # shellcheck disable=SC2086
    SHIM_MODE=$mode DYLD_INSERT_LIBRARIES="$T/shim.dylib" VOLE_CACHE=off "$C" $args \
        > "$T/o" 2> "$T/e"
    s=$?
    if [ $s -le 128 ]; then
        echo "main-stack: FAIL: SHIM_MODE=$mode volec $args: exit $s, not the overflow this case is for (a deeper chain is needed)"; bad=1
    elif ! head -1 "$T/e" | grep -q "^warning thread.main-stack: $W\|^{\"kind\":\"diagnostic\",\"severity\":\"warning\",\"code\":\"thread.main-stack\""; then
        echo "main-stack: FAIL: SHIM_MODE=$mode volec $args: the overflow (exit $s) came with no warning first on stderr:"
        head -c 400 "$T/e"; bad=1
    fi
done 2> /dev/null <<LINES
nobig check $T/deep.vl
nosize check $T/deep.vl
nobig $T/deep.vl -o $T/deep
nosize --json check $T/deep.vl
LINES
VOLE_CACHE=off "$C" check "$T/deep.vl" > "$T/o" 2> "$T/e"
s=$?
if [ $s -ne 0 ]; then
    echo "main-stack: FAIL: the 30000-term chain does not check on the compiler's own thread: exit $s"; bad=1
fi
# (every command that reads a program says it once on stderr, none on
# stdout; try's answer is untouched by the volecs it starts)
cat > "$T/t.vl" <<'VL'
fn f() -> i64 { 1 }
#[test]
fn t() { assert_eq(f(), 1); }
fn main() {
    println("{}", f());
}
VL
# (0.30.1, the fourth review's) and when only a volec another starts
# falls back (childnobig: try's, test's and probe's checks and builds),
# or only a lazy std's build made again (eagernobig), the warning is
# still said once on stderr, by the first volec, after the child ends
# (the child writes it to VOLEC_MAIN_STACK_FILE, out of band:
# tools::proc::say_children_main_stack), and never inside its output:
# try's answer stays its type and value. A check or a build starts no
# volec, and there none falls back: no warning.
while read -r mode want args; do
    # (test's own builds kept, .volec: none made, no volec started)
    rm -rf "$T/.volec"
    # shellcheck disable=SC2086
    (cd "$T" && SHIM_MODE=$mode DYLD_INSERT_LIBRARIES="$T/shim.dylib" VOLE_CACHE=off "$C" $args \
        > "$T/o" 2> "$T/e")
    ne=$(grep -c "$W" "$T/e")
    no=$(grep -c "$W" "$T/o")
    if [ "$ne" -ne "$want" ] || [ "$no" -ne 0 ]; then
        echo "main-stack: FAIL: SHIM_MODE=$mode volec $args: the warning $ne times on stderr, $no on stdout ($want and 0 wanted)"
        cat "$T/o" "$T/e"; bad=1
    fi
    case "$args" in
        try*)
            if [ "$(cat "$T/o")" != "i32 = 3" ]; then
                echo "main-stack: FAIL: SHIM_MODE=$mode volec $args: try's answer is not its type and value: $(cat "$T/o")"; bad=1
            fi ;;
    esac
done <<LINES
nobig 1 query show main t.vl
nobig 1 query context f t.vl
nobig 1 query effects main t.vl
nobig 1 fmt --check t.vl
nobig 1 fix --suggested --dry-run bad.vl
nobig 1 check --each bad.vl
nobig 1 test t.vl
nobig 1 try 1+2
nobig 1 probe t.vl:5 f()
nosize 1 test t.vl
nosize 1 try 1+2
nosize 1 probe t.vl:5 f()
nosize 1 bad.vl -o bad
childnobig 1 try 1+2
childnobig 1 --json try 1+2
childnobig 1 test t.vl
childnobig 1 probe t.vl:5 f()
childnobig 0 check t.vl
childnobig 0 t.vl -o t
childnobig 0 bad.vl -o bad
eagernobig 1 bad.vl -o bad
eagernobig 0 check t.vl
LINES
# (0.30.1, the fourth review's) a user's program gets none of the
# variables volec sets for itself (VOLEC_NESTED, VOLEC_EDIT_TAG,
# VOLEC_MAIN_STACK_FILE, tools::proc::exec_program), under run, test,
# probe and try alike, with the fallback and without
mkdir -p "$T/leak"
cat > "$T/leak/main.vl" <<'VL'
fn leaks(gpa: Gpa) -> i64 {
    let mut n: i64 = 0;
    for name in ["VOLEC_NESTED", "VOLEC_EDIT_TAG", "VOLEC_MAIN_STACK_FILE"] {
        if std::env::var_in(name, gpa).is_ok() {
            n += 1;
        }
    }
    n
}

#[test]
fn t(gpa: Gpa) {
    assert_eq(leaks(gpa), 0);
}

fn main(gpa: Gpa) {
    let n = leaks(gpa);
    println("leaks {}", n);
}
VL
L='let mut n = 0; for v in ["VOLEC_NESTED", "VOLEC_EDIT_TAG", "VOLEC_MAIN_STACK_FILE"] { if std::env::var_in(v, gpa).is_ok() { n += 1; } } n'
for mode in nobig none; do
    (cd "$T" && SHIM_MODE=$mode DYLD_INSERT_LIBRARIES="$T/shim.dylib" VOLE_CACHE=off "$C" run leak > "$T/o" 2> "$T/e")
    grep -qx "leaks 0" "$T/o" || { echo "main-stack: FAIL: SHIM_MODE=$mode volec run: the program sees volec's variables: $(cat "$T/o")"; bad=1; }
    (cd "$T" && SHIM_MODE=$mode DYLD_INSERT_LIBRARIES="$T/shim.dylib" VOLE_CACHE=off "$C" test leak/main.vl > "$T/o" 2> "$T/e")
    grep -q "1 passed" "$T/o" || { echo "main-stack: FAIL: SHIM_MODE=$mode volec test: the test sees volec's variables:"; cat "$T/o"; bad=1; }
    (cd "$T" && SHIM_MODE=$mode DYLD_INSERT_LIBRARIES="$T/shim.dylib" VOLE_CACHE=off "$C" probe leak/main.vl:18 n > "$T/o" 2> "$T/e")
    grep -q "#1  n = 0" "$T/o" || { echo "main-stack: FAIL: SHIM_MODE=$mode volec probe: the program sees volec's variables:"; cat "$T/o"; bad=1; }
    (cd "$T" && SHIM_MODE=$mode DYLD_INSERT_LIBRARIES="$T/shim.dylib" VOLE_CACHE=off "$C" try "$L" > "$T/o" 2> "$T/e")
    [ "$(cat "$T/o")" = "i32 = 0" ] || { echo "main-stack: FAIL: SHIM_MODE=$mode volec try: the snippet sees volec's variables: $(cat "$T/o")"; bad=1; }
done
# (0.30.1, the fifth review's) the same for test --input and reduce
# --until (testrun::run_case, reduce::run_limited), and the program is
# run as it is named, its environment the parent's but for those
# variables (no env(1) between: proc::exec_program): a path with `=`, a
# TMPDIR with `=`, DYLD_* passed on, PATH empty or with an `env` of
# its own first
echo x > "$T/in.txt"
for mode in nobig none; do
    (cd "$T" && SHIM_MODE=$mode DYLD_INSERT_LIBRARIES="$T/shim.dylib" VOLE_CACHE=off "$C" test leak/main.vl --input in.txt > "$T/o" 2> "$T/e")
    grep -qx "leaks 0" "$T/o" || { echo "main-stack: FAIL: SHIM_MODE=$mode volec test --input: the program sees volec's variables:"; cat "$T/o"; bad=1; }
    printf 'a\nb\n' > "$T/r.txt"; rm -f "$T/seen"
    (cd "$T" && SHIM_MODE=$mode DYLD_INSERT_LIBRARIES="$T/shim.dylib" VOLE_CACHE=off "$C" reduce r.txt --until 'n=0; for v in VOLEC_NESTED VOLEC_EDIT_TAG VOLEC_MAIN_STACK_FILE; do eval "x=\${$v+set}"; [ -n "$x" ] && n=$((n+1)); done; echo $n >> seen' > "$T/o" 2> "$T/e")
    if [ ! -s "$T/seen" ] || grep -qvx 0 "$T/seen"; then
        echo "main-stack: FAIL: SHIM_MODE=$mode volec reduce --until: the command sees volec's variables: $(cat "$T/seen" "$T/o" "$T/e")"; bad=1
    fi
done
mkdir -p "$T/a=b" "$T/tmp=x" "$T/fakebin"
printf '#!/bin/sh\necho FAKE-ENV "$@"\n' > "$T/fakebin/env"; chmod +x "$T/fakebin/env"
cat > "$T/a=b/main.vl" <<'VL'
fn main(gpa: Gpa) -> i32 {
    let mut n: i64 = 0;
    for name in ["VOLEC_NESTED", "VOLEC_EDIT_TAG", "VOLEC_MAIN_STACK_FILE"] {
        if std::env::var_in(name, gpa).is_ok() {
            n += 1;
        }
    }
    println("leaks {}", n);
    let mut code = 0;
    let mut i: i64 = 0;
    for a in std::env::args() {
        if i > 0 {
            println("arg {}", a);
            if a == "exit3" {
                code = 3;
            }
        }
        i += 1;
    }
    match std::env::var_in("DYLD_LIBRARY_PATH", gpa) {
        Ok(x) => println("dyld {}", x),
        Err(_) => println("dyld unset"),
    }
    code
}

#[test]
fn t() {
    assert_eq(1 + 2, 3);
}
VL
envrun() { # NAME VALUE ARGS...: volec ARGS in a=b, NAME=VALUE
    n=$1; v=$2; shift 2
    (cd "$T/a=b" && env "$n=$v" VOLE_CACHE=off "$C" "$@" > "$T/o" 2> "$T/e"); echo $? > "$T/rc"
}
for nv in "FOO=bar" "TMPDIR=$T/tmp=x" "DYLD_LIBRARY_PATH=/opt/x" "PATH=" "PATH=$T/fakebin:$PATH"; do
    n=${nv%%=*}; v=${nv#*=}
    envrun "$n" "$v" run . -- one exit3
    want="leaks 0
arg one
arg exit3
dyld $([ "$n" = DYLD_LIBRARY_PATH ] && echo /opt/x || echo unset)"
    if [ "$(cat "$T/o")" != "$want" ] || [ "$(cat "$T/rc")" != 3 ]; then
        echo "main-stack: FAIL: $n=$v volec run in a=b: not the program's argv, environment or exit (rc $(cat "$T/rc")):"; cat "$T/o" "$T/e"; bad=1
    fi
    if [ "$nv" != "PATH=" ]; then # (test and probe link with cc, found on PATH)
        envrun "$n" "$v" test main.vl
        grep -q "1 passed" "$T/o" || { echo "main-stack: FAIL: $n=$v volec test in a=b:"; cat "$T/o" "$T/e"; bad=1; }
        envrun "$n" "$v" probe main.vl:8 n
        grep -q "#1  n = 0" "$T/o" || { echo "main-stack: FAIL: $n=$v volec probe in a=b:"; cat "$T/o" "$T/e"; bad=1; }
    fi
    envrun "$n" "$v" try '1 + 2'
    [ "$(cat "$T/o")" = "i32 = 3" ] || { echo "main-stack: FAIL: $n=$v volec try: $(cat "$T/o" "$T/e")"; bad=1; }
done
# (0.30.1, the fifth review's) nothing is read out of any output: a
# snippet that prints the warning's own line, and a JSON object of its
# keys, prints them as they are, and no warning is said that did not
# happen (none; childnobig: the one that did)
cat > "$T/warnlines.sh" <<'SH'
printf '%s\n' 'println("warning thread.main-stack: no thread with a 1 GiB stack could be made: compiling on the main thread'"'"'s stack, which a deeply nested expression may overflow"); println("{{\"kind\":\"diagnostic\",\"severity\":\"warning\",\"code\":\"thread.main-stack\",\"mine\":1}}"); println("after"); 1 + 2'
SH
S=$(sh "$T/warnlines.sh")
for mode in none childnobig; do
    (cd "$T" && SHIM_MODE=$mode DYLD_INSERT_LIBRARIES="$T/shim.dylib" VOLE_CACHE=off "$C" try "$S" > "$T/o" 2> "$T/e")
    want=0; [ $mode = childnobig ] && want=1
    if [ "$(sed -n 1p "$T/o")" != "warning thread.main-stack: $W: compiling on the main thread's stack, which a deeply nested expression may overflow" ] \
        || ! sed -n 2p "$T/o" | grep -q '"mine":1' || [ "$(sed -n 3,4p "$T/o")" != "after
i32 = 3" ] || [ "$(grep -c "$W" "$T/e")" -ne $want ]; then
        echo "main-stack: FAIL: SHIM_MODE=$mode volec try: a snippet's own lines changed, or a warning said $(grep -c "$W" "$T/e") times ($want wanted):"
        cat "$T/o" "$T/e"; bad=1
    fi
done
# (0.30.1, the sixth review's) VOLEC_MAIN_STACK_FILE is made by mkstemp
# and removed at exit, and a child appends to it without following a
# link or making it (tools::proc::make_main_stack_file,
# append_main_stack_file): a link planted at the old, predictable name
# in a TMPDIR volec cannot write is not written through, and the
# warning, made in /tmp then, is said once; a file the variable names
# that is a link is not written through either (the warning goes to
# stderr); an unwritable or missing TMPDIR loses no warning; and the
# file is gone after the command.
mkdir -p "$T/sy/tmpd" "$T/sy/tmpw" "$T/sy/ro"
printf 'fn f() -> i64 { 1 }\n#[test]\nfn t() { assert_eq(f(), 1); }\nfn main() {\n    println("{}", f());\n}\n' > "$T/sy/t.vl"
echo "precious data" > "$T/sy/victim.txt"
(cd "$T/sy" && sh -c 'ln -s "$1/victim.txt" "$1/tmpd/volec-main-stack.$$"; chmod 555 "$1/tmpd"; exec env TMPDIR="$1/tmpd" SHIM_MODE=childnobig DYLD_INSERT_LIBRARIES="$2" VOLE_CACHE=off "$3" test t.vl' sh "$T/sy" "$T/shim.dylib" "$C" > "$T/o" 2> "$T/e")
chmod 755 "$T/sy/tmpd"
if [ "$(cat "$T/sy/victim.txt")" != "precious data" ] || [ "$(grep -c "$W" "$T/e")" -ne 1 ] || grep -q "$W" "$T/o"; then
    echo "main-stack: FAIL: a link planted at volec-main-stack.PID: victim '$(cat "$T/sy/victim.txt")', the warning $(grep -c "$W" "$T/e") times on stderr (1 wanted)"; cat "$T/o" "$T/e"; bad=1
fi
echo "precious data" > "$T/sy/victim.txt"; ln -s "$T/sy/victim.txt" "$T/sy/link"
(cd "$T/sy" && VOLEC_MAIN_STACK_FILE="$T/sy/link" SHIM_MODE=nobig DYLD_INSERT_LIBRARIES="$T/shim.dylib" VOLE_CACHE=off "$C" check t.vl > "$T/o" 2> "$T/e")
if [ "$(cat "$T/sy/victim.txt")" != "precious data" ] || [ "$(grep -c "$W" "$T/e")" -ne 1 ]; then
    echo "main-stack: FAIL: VOLEC_MAIN_STACK_FILE a link: victim '$(cat "$T/sy/victim.txt")', the warning $(grep -c "$W" "$T/e") times on stderr (1 wanted)"; bad=1
fi
chmod 555 "$T/sy/ro"
for td in "$T/sy/ro" "$T/sy/none" "$T/sy/tmpw"; do
    rm -rf "$T/sy/.volec"
    (cd "$T/sy" && TMPDIR="$td" SHIM_MODE=childnobig DYLD_INSERT_LIBRARIES="$T/shim.dylib" VOLE_CACHE=off "$C" test t.vl > "$T/o" 2> "$T/e")
    if [ "$(grep -c "$W" "$T/e")" -ne 1 ] || grep -q "$W" "$T/o" || ! grep -q "1 passed" "$T/o"; then
        echo "main-stack: FAIL: TMPDIR=$td volec test: the warning $(grep -c "$W" "$T/e") times on stderr (1 wanted):"; cat "$T/o" "$T/e"; bad=1
    fi
done
chmod 755 "$T/sy/ro"
if ls "$T/sy/tmpw" | grep -q volec-main-stack; then
    echo "main-stack: FAIL: VOLEC_MAIN_STACK_FILE left after the command: $(ls "$T/sy/tmpw")"; bad=1
fi
# (0.30.1, the sixth review's) a copy fork made of the first volec (a
# batch's steps, same-output's and samebuild's workers: fork_worker) is
# not the file's owner (MAIN_STACK_OWNER is a pid): a step's nested
# volec that falls back is said once, on stderr, not once a step inside
# the batch's answer
printf 'try 1+2\ntry 2+3\ncheck t.vl\n' > "$T/sy/cmds"
(cd "$T/sy" && SHIM_MODE=childnobig DYLD_INSERT_LIBRARIES="$T/shim.dylib" VOLE_CACHE=off "$C" batch < cmds > "$T/o" 2> "$T/e")
if [ "$(grep -c "$W" "$T/e")" -ne 1 ] || grep -q "$W" "$T/o"; then
    echo "main-stack: FAIL: SHIM_MODE=childnobig volec batch: the warning $(grep -c "$W" "$T/e") times on stderr (1 wanted), $(grep -c "$W" "$T/o") in its answer (0 wanted)"; bad=1
fi
for args in "--version" "explain lex.utf8" "explain thread.main-stack" "guide --list"; do
    # shellcheck disable=SC2086
    SHIM_MODE=nobig DYLD_INSERT_LIBRARIES="$T/shim.dylib" VOLE_CACHE=off "$C" $args > "$T/o" 2> "$T/e"
    if grep -q "$W" "$T/e"; then
        echo "main-stack: FAIL: volec $args, which compiles nothing, said the warning"; bad=1
    fi
done
if [ $bad -ne 0 ]; then
    exit 1
fi
echo "main-stack: ok: the compiler's own thread, and its planted refusals said once on stderr, before an overflow, by every command that reads a program and by no other, whichever volec fell back; no worker's stack, a -j 4 build still builds; a user's program gets none of volec's own variables"
