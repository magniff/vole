#!/usr/bin/env python3
"""Cases for the check hook (check-after-edit.py): when it runs, which root
and compiler it picks, what it tells the agent, and the shared volec
recogniser (volec_cmd.py). A fake compiler stands in for volec; one
case runs target/volec when it has --json. Development tooling only.

usage: python3 -I tools/agent-hooks/test-check-after-edit.py
"""
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import types

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))


def load(name, file):
    mod = types.ModuleType(name)
    mod.__file__ = os.path.join(HERE, file)
    with open(mod.__file__) as fh:
        exec(compile(fh.read(), mod.__file__, "exec"), mod.__dict__)
    return mod


hook = load("check_after_edit", "check-after-edit.py")
tc = hook.tc
FAILED = 0


def case(name, got, want):
    global FAILED
    if got == want:
        print(f"pass {name}")
    else:
        FAILED += 1
        print(f"FAIL {name}:\n    want {want!r}\n    got  {got!r}")


def write(path, text=""):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fh:
        fh.write(text)


def diag(file, line, msg, sev="error", code="type error", help=()):
    return {"kind": "diagnostic", "severity": sev, "code": code, "file": file, "line": line, "col": 5,
            "message": msg, "help": list(help), "notes": [], "try": []}


# The recogniser: volec by name, copy, variable.
case("calls: plain", [c[0] for c in tc.calls("volec query show f; volec main.vl -o p")],
     ["query", "build"])
case("calls: variable and copy", [(c[0], c[2]) for c in tc.calls("T=target/tc0; $T edit patch f; target/tools/volec check")],
     [("edit", "target/tc0"), ("check", "target/tools/volec")])
case("calls: export, braces, quotes", [(c[0], c[2]) for c in tc.calls('export TC=./volec-old && "${TC}" fix --only imports')],
     [("fix", "./volec-old")])
case("calls: not volec", tc.calls("tclsh run.tcl; tcpdump -i en0; $EDITOR x; echo volec query"), [])
case("calls: unassigned variable", [c[0] for c in tc.calls("$T refactor rename a b")], ["refactor"])
case("calls: in a heredoc body, no", tc.calls("cat > x.sh <<'EOF'\nvolec query show f\nEOF"), [])
case("program_name", [tc.program_name(s, a) for a in [{}] for s in ("T=bin/tc1", "$T query x", "ls -l")],
     ["", "volec", "ls"])

# When it runs.
tmp = tempfile.mkdtemp()
try:
    prog = os.path.join(tmp, "prog")
    write(os.path.join(prog, "main.vl"), "mod util;\nfn main() {}\n")
    write(os.path.join(prog, "util.vl"), "pub fn f() {}\n")
    write(os.path.join(prog, "notes.md"))
    t = hook.trigger({"tool_name": "Write", "tool_input": {"file_path": os.path.join(prog, "util.vl")}})[:3]
    case("Write of a module: its main.vl", t, (os.path.join(prog, "util.vl"), os.path.join(prog, "main.vl"), None))
    case("Write of a doc: nothing", hook.trigger({"tool_name": "Write", "tool_input": {"file_path": os.path.join(prog, "notes.md")}}), None)
    case("Read: nothing", hook.trigger({"tool_name": "Read", "tool_input": {"file_path": os.path.join(prog, "main.vl")}}), None)

    def bash(command, stdout):
        t = hook.trigger({"tool_name": "Bash", "tool_input": {"command": command},
                          "tool_response": {"stdout": stdout, "stderr": ""}})
        return t[:3] if t else t
    case("edit that wrote", bash("volec edit patch f --old a --new b", "patched crate::f\tmain.vl\t+1 -1 lines\n"),
         (None, None, "volec"))
    case("edit through $T, with a root", bash("T=../tc0; $T refactor rename f g --root p/main.vl",
                                              "renamed crate::f\tmain.vl\t+1 -1 lines\n"), (None, "p/main.vl", "../tc0"))
    case("edit refused: nothing", bash("volec edit patch f --old a --new q", ""), None)
    case("dry run: nothing", bash("volec edit patch f --old a --new b --dry-run", "--- a/main.vl\n"), None)
    case("a query: nothing", bash("volec query show f", "fn f() {}\n"), None)
    case("stdin from a .vl file is not the root", bash("volec edit replace f < /tmp/x/new.vl",
                                                         "replaced crate::f\tmain.vl\t+1 -1 lines\n"), (None, None, "volec"))
    case("stdin without a space is not the root", bash("volec edit insert --after f <new.vl",
                                                        "inserted crate::g\tmain.vl\t+3 -0 lines\n"), (None, None, "volec"))
    case("a root before a redirect still counts", bash("volec fix --only imports t/main.vl > log.txt",
                                                       "fixed imports\tt/main.vl\t+1 -0 lines\n")[1], "t/main.vl")
    case("last .vl operand is the root", bash("volec fix --only imports t/main.vl", "fixed imports\tt/main.vl\t+1 -0 lines\n")[1],
         "t/main.vl")

    # The root.
    top = os.path.join(tmp, "repo")
    os.makedirs(os.path.join(top, ".git"))
    write(os.path.join(top, "compiler", "src", "main.vl"))
    write(os.path.join(top, "compiler", "src", "front", "x.vl"))
    write(os.path.join(top, "compiler", "std", "std.vl"))
    write(os.path.join(top, "compiler", "std", "iter.vl"))
    write(os.path.join(top, "tests", "run", "loop.vl"), "fn main() {\n}\n")
    write(os.path.join(top, "tests", "run", "frag.vl"), "fn helper() {}\n")
    write(os.path.join(top, "tests", "run", "multi", "main.vl"))
    write(os.path.join(top, "tests", "run", "multi", "a", "b.vl"))
    case("root: compiler source", hook.root_of(os.path.join(top, "compiler", "src", "front", "x.vl")),
         os.path.join(top, "compiler", "src", "main.vl"))
    case("root: std, through the compiler's root", hook.root_of(os.path.join(top, "compiler", "std", "iter.vl")),
         os.path.join(top, "compiler", "src", "main.vl"))
    case("root: a one-file program", hook.root_of(os.path.join(top, "tests", "run", "loop.vl")),
         os.path.join(top, "tests", "run", "loop.vl"))
    case("root: a fragment, none", hook.root_of(os.path.join(top, "tests", "run", "frag.vl")), None)
    case("root: two levels up", hook.root_of(os.path.join(top, "tests", "run", "multi", "a", "b.vl")),
         os.path.join(top, "tests", "run", "multi", "main.vl"))

    # The compiler: the tools binary first, then the build.
    os.makedirs(os.path.join(top, "target", "tools"))
    for rel in ("target/volec", "target/tools/volec"):
        write(os.path.join(top, rel), "#!/bin/sh\n")
        os.chmod(os.path.join(top, rel), 0o755)
    saved = os.environ.pop("VOLE_CHECK_COMPILER", None)
    case("compiler: target/tools first", hook.compiler_for(os.path.join(top, "compiler", "src")),
         os.path.join(top, "target", "tools", "volec"))
    case("compiler: the one the agent ran", hook.compiler_for(top, "target/volec"),
         os.path.join(top, "target", "volec"))
    # (0.17) A program's check: target/volec when newer (just rebuilt);
    # the compiler's own source: still the tools binary.
    t = time.time()
    os.utime(os.path.join(top, "target", "tools", "volec"), (t - 100, t - 100))
    os.utime(os.path.join(top, "target", "volec"), (t, t))
    case("compiler: a newer build for a test program",
         hook.compiler_for(os.path.join(top, "tests", "run"), None, os.path.join(top, "tests", "run", "loop.vl")),
         os.path.join(top, "target", "volec"))
    case("compiler: the tools binary for the compiler's source",
         hook.compiler_for(os.path.join(top, "compiler", "src"), None, os.path.join(top, "compiler", "src", "main.vl")),
         os.path.join(top, "target", "tools", "volec"))
    os.utime(os.path.join(top, "target", "volec"), (t - 200, t - 200))
    case("compiler: an older build is not taken",
         hook.compiler_for(os.path.join(top, "tests", "run"), None, os.path.join(top, "tests", "run", "loop.vl")),
         os.path.join(top, "target", "tools", "volec"))

    # The report: errors only, the edited file's first, at most 10.
    many = [diag("other.vl", i, f"e{i}") for i in range(1, 12)] + [diag("util.vl", 3, "mine", help=["did you mean 'g'?"])]
    text = hook.report(many, "main.vl", os.path.join(prog, "util.vl"))
    lines = text.split("\n")
    case("report: head", lines[0], "volec check main.vl: 12 errors")
    case("report: edited file first", lines[1], "util.vl:3:5: error[type error] mine | help: did you mean 'g'?")
    case("report: capped", (len(lines), lines[-1]), (12, "(2 more: volec check main.vl)"))
    case("report: clean is silent", hook.report([diag("a.vl", 1, "w", sev="warning")], "main.vl", None), "")
    # (0.17) One `fix` command for the errors it answers, after the head.
    u = [dict(diag("main.vl", i, "calling a C function is unsafe", code="unsafe"),
              **{"try": ["volec fix --only unsafe main.vl"]}) for i in (2, 5)]
    a = dict(diag("main.vl", 7, "allocation is explicit: pass an allocator (try: Vec::new_in(gpa))"),
             **{"try": ["volec fix --only alloc016 main.vl"]})
    lines = hook.report(u + [a, diag("main.vl", 9, "bad")], "main.vl", None).split("\n")
    case("report: fix commands after the head", lines[:3],
         ["volec check main.vl: 4 errors",
          "try: volec fix --only unsafe main.vl   (2 of the errors)",
          "try: volec fix --only alloc016 main.vl   (1 of the errors)"])
    case("report: one fix for all", hook.report(u, "main.vl", None).split("\n")[1],
         "try: volec fix --only unsafe main.vl   (all of them)")
    # (0.18) `fix --suggested` first, named once, never run by the hook
    sg = [dict(diag("main.vl", i, "undefined variable 'totl'"),
               **{"try": ["volec fix --suggested main.vl"]}) for i in (3, 8)]
    lines = hook.report(u + sg + [diag("main.vl", 9, "bad")], "main.vl", None).split("\n")
    case("report: fix --suggested first", lines[:3],
         ["volec check main.vl: 5 errors",
          "try: volec fix --suggested main.vl   (2 of the errors: their exact fixes, one checked edit)",
          "try: volec fix --only unsafe main.vl   (2 of the errors)"])
    case("report: fix --suggested not on its errors", lines[5],
         "main.vl:3:5: error[type error] undefined variable 'totl'")
    case("report: other try lines stay on their error", hook.fix_commands(
        [dict(diag("m.vl", 1, "x"), **{"try": ["use std::HashMap;", "target/tools/volec fix --only imports m.vl"]})]),
         [("target/tools/volec fix --only imports m.vl", 1)])
    case("typed name: under cwd", hook.typed_name(os.path.join(tmp, "bin", "volec"), tmp),
         os.path.join("bin", "volec"))
    case("short line parsed", hook.parse_short("m.vl:2:7: error[type error] bad | help: try x"),
         {"severity": "error", "code": "type error", "file": "m.vl", "line": 2, "col": 7, "message": "bad",
          "help": ["try x"], "notes": [], "try": []})


    # End to end, with a fake compiler printing check --json's lines.
    fake = os.path.join(tmp, "fake-volec")
    write(fake + ".out", json.dumps(diag("util.vl", 1, "undefined variable 'q'")) + "\n")
    write(fake, "#!/bin/sh\ncat '%s.out' >&2\nexit 1\n" % fake)
    os.chmod(fake, 0o755)
    old = os.path.join(tmp, "old-volec")
    write(old, "#!/bin/sh\nfor a; do [ \"$a\" = --json ] && { echo \"error check.usage: unknown option '--json'\" >&2; exit 2; }; done\n"
               "echo \"util.vl:1:5: error[type error] undefined variable 'q'\" >&2\nexit 1\n")
    os.chmod(old, 0o755)
    log = os.path.join(tmp, "hook.jsonl")

    def run(event, compiler, state=None):
        """The hook on event: (exit status, stdout); a state directory of
        its own unless one is given (no earlier check to compare with)."""
        env = dict(os.environ, VOLE_CHECK_COMPILER=compiler, VOLE_CHECK_HOOK_LOG=log,
                   VOLE_HOOK_STATE=state or tempfile.mkdtemp(dir=tmp))
        r = subprocess.run([sys.executable, "-I", os.path.join(HERE, "check-after-edit.py")],
                           input=json.dumps(event), capture_output=True, text=True, env=env)
        return r.returncode, r.stdout
    ev = {"hook_event_name": "PostToolUse", "tool_name": "Edit", "cwd": prog,
          "tool_input": {"file_path": os.path.join(prog, "util.vl")}}
    st, out = run(ev, fake)
    ctx = json.loads(out)["hookSpecificOutput"]["additionalContext"] if out else ""
    case("end to end: context", (st, ctx),
         (0, "volec check main.vl: 1 error\nutil.vl:1:5: error[type error] undefined variable 'q'"))
    st, out2 = run(ev, old)
    case("end to end: a compiler without --json", json.loads(out2)["hookSpecificOutput"]["additionalContext"] if out2 else "", ctx)
    with open(log) as fh:
        recs = [json.loads(x) for x in fh]
    case("logged", [(r["kind"], r["errors"], r["codes"]) for r in recs],
         [("check-hook", 1, ["type error"])] * 2)
    # (0.25.2) The end of every call this hook sees, for agent-tool-usage.py --calls.
    end = hook.call_end({"tool_name": "Bash", "tool_use_id": "toolu_0123456789abcdefXYZ",
                         "tool_response": {"stdout": "ok\n", "stderr": "", "interrupted": False}})
    case("call-end record", (end["kind"], end["tool"], end["id"], end["out_bytes"], "exit" in end,
                             isinstance(end["t"], float)),
         ("call-end", "Bash", "3456789abcdefXYZ", 3, False, True))
    st, out = run(dict(ev, hook_event_name="PreToolUse"), fake)
    case("PreToolUse: nothing", (st, out), (0, ""))
    env_off = dict(os.environ, VOLE_CHECK_HOOK="0", VOLE_CHECK_COMPILER=fake)
    r = subprocess.run([sys.executable, "-I", os.path.join(HERE, "check-after-edit.py")], input=json.dumps(ev),
                       capture_output=True, text=True, env=env_off)
    case("VOLE_CHECK_HOOK=0: off", r.stdout, "")

    # (0.17) The directory a Bash call runs in follows its cds; a shell
    # command writing a .vl file is a change too.
    elsewhere = os.path.join(tmp, "elsewhere")
    os.makedirs(elsewhere)

    def bash_at(cwd, command, stdout=""):
        return hook.trigger({"tool_name": "Bash", "cwd": cwd, "tool_input": {"command": command},
                             "tool_response": {"stdout": stdout, "stderr": ""}})
    wrote = "patched crate::f\tmain.vl\t+1 -1 lines\n"
    case("cd then edit: the edit's directory", bash_at(elsewhere, f"cd {prog} && volec edit patch f --old a --new b", wrote),
         (None, None, "volec", prog))
    case("cd through a variable", bash_at(elsewhere, f"W={prog}; cd $W && target/volec edit delete f", wrote),
         (None, None, "target/volec", prog))
    case("cd relative, then a root", bash_at(tmp, "cd prog && volec fix --root main.vl", "fixed imports\tmain.vl\t+1 -0 lines\n"),
         (None, "main.vl", "volec", prog))
    case("cd to an unknown place: where it was", bash_at(elsewhere, "cd $X && volec edit delete f", wrote)[3], elsewhere)
    case("heredoc write of a .vl", bash_at(prog, "cat > util.vl <<'EOF'\npub fn f() {}\nEOF"),
         (os.path.join(prog, "util.vl"), os.path.join(prog, "main.vl"), None, prog))
    case("cp onto a .vl", bash_at(elsewhere, f"cd {prog}; cp /x/u.vl util.vl")[:2],
         (os.path.join(prog, "util.vl"), os.path.join(prog, "main.vl")))
    case("a .vl read is not a write", bash_at(prog, "cat util.vl > /dev/null"), None)
    # (0.25.2.2) The 0.25.2.1 eval's agents edited with sed -i, perl -pi and
    # Python; the hook did not check after them (27 of 30 `changed on disk`
    # notices followed such an edit).
    case("sed -i of a .vl", bash_at(prog, "sed -i '' 's/f/g/' util.vl && grep g util.vl")[:2],
         (os.path.join(prog, "util.vl"), os.path.join(prog, "main.vl")))
    case("perl -0pi of a .vl", bash_at(prog, "perl -0pi -e 's/f/g/' util.vl")[:2],
         (os.path.join(prog, "util.vl"), os.path.join(prog, "main.vl")))
    case("python heredoc writing a .vl", bash_at(elsewhere, f"cd {prog} && python3 - <<'EOF'\np = 'util.vl'\n"
                                                 "s = open(p).read()\nopen(p, 'w').write(s)\nEOF")[:2],
         (os.path.join(prog, "util.vl"), os.path.join(prog, "main.vl")))
    case("python -c writing a .vl", bash_at(prog, "python3 -c \"open('util.vl', 'w').write('x')\"")[:2],
         (os.path.join(prog, "util.vl"), os.path.join(prog, "main.vl")))
    case("python reading a .vl is not a write", bash_at(prog, "python3 - <<'EOF'\nprint(open('util.vl').read())\nEOF"),
         None)
    case("sed -n is not a write", bash_at(prog, "sed -n 1,3p util.vl"), None)

    # (0.17) The delta: what changed since this session's last check of the
    # root; the tests when the program has them; the hint.
    fdir = os.path.join(tmp, "fake2")
    os.makedirs(fdir)
    fake2 = os.path.join(fdir, "volec")
    write(fake2, "#!/bin/sh\nif [ \"$1\" = test ]; then cat '%s/test.out'; exit $(cat '%s/test.rc'); fi\n"
                 "cat '%s/check.out' >&2\n[ -s '%s/check.out' ] && exit 1\nexit 0\n" % (fdir, fdir, fdir, fdir))
    os.chmod(fake2, 0o755)

    def fake_says(check=(), test=None, rc=0):
        write(os.path.join(fdir, "check.out"), "".join(json.dumps(d) + "\n" for d in check))
        write(os.path.join(fdir, "test.out"), test or "")
        write(os.path.join(fdir, "test.rc"), str(rc))
    state = tempfile.mkdtemp(dir=tmp)
    ev = {"hook_event_name": "PostToolUse", "tool_name": "Edit", "cwd": prog, "session_id": "delta",
          "tool_input": {"file_path": os.path.join(prog, "main.vl")}}
    write(os.path.join(prog, "main.vl"), "mod util;\nfn main() {}\n")

    def ctx_of(out):
        return json.loads(out)["hookSpecificOutput"]["additionalContext"] if out else ""
    a = diag("main.vl", 3, "undefined variable 'q'")
    b = diag("main.vl", 7, "expected 'i64', got '[u8]'")
    fake_says([a])
    case("delta: the first check lists all", ctx_of(run(ev, fake2, state)[1]),
         "volec check main.vl: 1 error\nmain.vl:3:5: error[type error] undefined variable 'q'")
    fake_says([dict(a, line=4), b])
    case("delta: only the new one listed", ctx_of(run(ev, fake2, state)[1]),
         "volec check main.vl: 2 errors (1 new, 1 as before)\nmain.vl:7:5: error[type error] expected 'i64', got '[u8]'")
    fake_says([b])
    case("delta: one fixed", ctx_of(run(ev, fake2, state)[1]), "volec check main.vl: 1 error (1 fixed, 1 as before)")
    fake_says([])
    case("delta: clean again", ctx_of(run(ev, fake2, state)[1]), "volec check main.vl: 0 errors (1 fixed)")
    case("delta: clean and clean is silent", run(ev, fake2, state)[1], "")
    fake_says([b])
    got = ctx_of(run(ev, fake2, state)[1])
    case("hint: the same mistake twice", got.split("\n")[-1],
         hook.hs.hint("unfamiliar-construct", VOLEC=fake2))
    fake_says([])
    run(ev, fake2, state)
    fake_says([b])
    case("hint: once a session", "guide --find" in ctx_of(run(ev, fake2, state)[1]), False)
    # (E3) VOLE_HINTS=0: the same mistake twice, no hint
    off = dict(ev, session_id="delta-nohints")
    os.environ["VOLE_HINTS"] = "0"
    for says in ([b], [], [b]):
        fake_says(says)
        got = ctx_of(run(off, fake2, state)[1])
    del os.environ["VOLE_HINTS"]
    case("hint: off with VOLE_HINTS=0", (got.startswith("volec check main.vl: 1 error"),
                                             "guide --find" in got), (True, False))

    # (0.18.1) The exact fixes, applied: errors whose try: names `fix
    # --suggested` make the hook run it (a fake: `fix` writes fixed.out's
    # lines and a mark; `fix --dry-run` writes dry.out's; check then
    # prints after.out), check again, and say what it fixed before what
    # is left. (0.25.2.1) Only the mechanical classes (conv.marker,
    # conv.rust), each change shown `FILE:LINE: OLD -> NEW`; the other
    # exact fixes (a did-you-mean, a `use`) are shown, not made.
    fdir3 = os.path.join(tmp, "fake3")
    os.makedirs(fdir3)
    fake3 = os.path.join(fdir3, "volec")
    write(fake3, "#!/bin/sh\nd='%s'\nif [ \"$1\" = fix ]; then echo \"$@\" >>\"$d/fix.calls\"; "
                 "case \" $* \" in *' --dry-run '*) cat \"$d/dry.out\"; exit 0;; esac; cat \"$d/fixed.out\"; "
                 "[ -s \"$d/fixed.out\" ] && : >\"$d/mark\"; exit 0; fi\n"
                 "if [ -f \"$d/mark\" ]; then cat \"$d/after.out\" >&2; [ -s \"$d/after.out\" ] && exit 1; exit 0; fi\n"
                 "cat \"$d/check.out\" >&2\n[ -s \"$d/check.out\" ] && exit 1\nexit 0\n" % fdir3)
    os.chmod(fake3, 0o755)
    sug = "volec fix --suggested main.vl"
    marker = dict(diag("main.vl", 2, "'ui' is lent inout here (the callee may change it): mark it '&ui'",
                       code="conv.marker"), **{"try": [sug]})
    spell = dict(diag("main.vl", 3, "'let mut' is Rust's spelling; a mutable binding is 'var x'", code="conv.rust"),
                 **{"try": [sug]})
    typo = dict(diag("main.vl", 4, "undefined variable 'prinln'", help=["did you mean 'println'?"]), **{"try": [sug]})
    other = diag("main.vl", 5, "expected '[u8]', got 'i64'")

    def out_lines(*fields):
        return [list(f) for f in fields]

    def fake3_says(check, fixed, after, dry=()):
        for f in ("mark", "fix.calls"):
            if os.path.exists(os.path.join(fdir3, f)):
                os.remove(os.path.join(fdir3, f))
        write(os.path.join(fdir3, "check.out"), "".join(json.dumps(d) + "\n" for d in check))
        write(os.path.join(fdir3, "fixed.out"), "".join(json.dumps({"kind": "output", "fields": f}) + "\n" for f in fixed))
        write(os.path.join(fdir3, "after.out"), "".join(json.dumps(d) + "\n" for d in after))
        write(os.path.join(fdir3, "dry.out"), "".join(json.dumps(d if isinstance(d, dict) else
                                                                 {"kind": "output", "fields": d}) + "\n" for d in dry))

    def fix_calls():
        p = os.path.join(fdir3, "fix.calls")
        return open(p).read().strip().split("\n") if os.path.exists(p) else []
    head = ("volec fix main.vl, run by the hook (only mechanical fixes: a call's `&`, Rust's spellings, an import "
            "unused at two checks; volec undo takes it back; positions as before it):")
    # (0.25.2.2) each file the hook rewrote, once, after its changes
    tail1 = "\nthe hook rewrote main.vl: the change above, nothing else (read it again before an Edit)"
    tail2 = "\nthe hook rewrote main.vl: the 2 changes above, nothing else (read it again before an Edit)"
    shown = ("suggested, not applied (check each: a name, a conversion or an import can change what the code "
             "means; " + fake3 + " fix --suggested main.vl makes the changes, not the refused):")
    diff = [["--- a/main.vl"], ["+++ b/main.vl"], ["@@ -2,2 +2,2 @@"], ["-    bump(ui);"], ["-    let mut u = 0;"],
            ["+    bump(&ui);"], ["+    var u = 0;"]]
    fake3_says([marker, spell, typo, other], [["fixed 2 suggested fixes", "main.vl", "+2 -2 lines"]] + diff,
               [dict(typo, line=4), dict(other, line=6)],
               [["--- a/main.vl"], ["+++ b/main.vl"], ["@@ -4 +4 @@"], ["-    prinln(\"x\");"], ["+    println(\"x\");"]])
    got = ctx_of(run(ev, fake3)[1])
    case("hook fix: the mechanical ones applied, each change shown; the others shown, not made",
         (fix_calls(), got),
         (["fix --suggested --codes conv.marker,conv.marker_extra,conv.rust --diff main.vl --json",
           "fix --suggested --dry-run main.vl --json"],
          head + "\nchanged main.vl:2: bump(ui); -> bump(&ui);\nchanged main.vl:3: let mut u = 0; -> var u = 0;"
          "\nfixed main.vl:2:5: 'ui' is lent inout here (the callee may change it): mark it '&ui' | its exact fix"
          "\nfixed main.vl:3:5: 'let mut' is Rust's spelling; a mutable binding is 'var x' | its exact fix"
          + tail2 + "\nvolec check main.vl: 2 errors\ntry: volec fix --suggested main.vl   (1 of the errors: their exact "
          "fixes, one checked edit)\nmain.vl:4:5: error[type error] undefined variable 'prinln' | help: did you "
          "mean 'println'?\nmain.vl:6:5: error[type error] expected '[u8]', got 'i64'\n"
          + shown + "\n  main.vl:4: prinln(\"x\"); -> println(\"x\");"))
    fake3_says([marker], [["fixed 1 suggested fix", "main.vl", "+1 -1 lines"]] + diff[:4] + [diff[5]], [])
    case("hook fix: all fixed, clean", ctx_of(run(ev, fake3)[1]),
         head + "\nchanged main.vl:2: bump(ui); -> bump(&ui);"
         "\nfixed main.vl:2:5: 'ui' is lent inout here (the callee may change it): mark it '&ui' | its exact fix"
         + tail1 + "\nvolec check main.vl: 0 errors")
    # (0.25.2.2) Repeats of one fix in one line, not a line each (the
    # 0.25.2.1 eval's sdftext: about 20 `&mut` lines).
    rust = [dict(diag("main.vl", 10 + k, "'&mut %s' is Rust's spelling; an inout argument (the callee may change "
                      "it) is marked '&x'" % v, code="conv.rust"),
                 **{"try": ["volec edit patch main.vl:%d --old '&mut %s' --new '&%s'" % (10 + k, v, v), sug]})
            for k, v in enumerate("abc")]
    rdiff = [["--- a/main.vl"], ["+++ b/main.vl"], ["@@ -10,3 +10,3 @@"]] + \
        [["-    f(&mut %s);" % v] for v in "abc"] + [["+    f(&%s);" % v] for v in "abc"]
    fake3_says(rust + [spell], [["fixed 4 suggested fixes", "main.vl", "+4 -4 lines"]] + rdiff +
               [["@@ -3 +3 @@"], ["-    let mut u = 0;"], ["+    var u = 0;"]], [])
    case("hook fix: repeats in one line, each file once", ctx_of(run(ev, fake3)[1]),
         head + "\nchanged main.vl:3: let mut u = 0; -> var u = 0;"
         "\nfixed main.vl:3:5: 'let mut' is Rust's spelling; a mutable binding is 'var x' | its exact fix"
         "\nfixed 3 '&mut x' to '&x' (conv.rust) in main.vl: lines 10, 11, 12"
         "\nthe hook rewrote main.vl: the 4 changes above, nothing else (read it again before an Edit)"
         "\nvolec check main.vl: 0 errors")
    case("fix pattern: a lent argument", hook.fix_pattern(dict(marker, **{"try": [
        "volec edit patch main.vl:2 --old '(ui' --new '(&ui'"]})), ("x", "&x"))
    case("fix pattern: a spelling", hook.fix_pattern(dict(spell, **{"try": [
        "volec edit patch main.vl:3 --old 'let mut' --new 'var'"]})), ("let mut", "var"))
    case("fix pattern: from the message", hook.fix_pattern(rust[0] | {"try": []}), ("&mut x", "&x"))
    # (0.25.2.1) a did-you-mean is not made (the gpu2521 agent's
    # `readback` made `read_back`, the function the call was in); the
    # compiler's refusal is shown with the rest
    refusal = {"kind": "diagnostic", "severity": "note", "code": "fix.refused", "file": None, "line": None,
               "col": None, "message": "main.vl:4:5: not applied: `read_back`: the name it puts there is the "
               "function the call is in: the call would call itself", "help": [], "notes": [], "try": []}
    rec = dict(typo, message="undefined variable 'readback'", help=["did you mean 'read_back'?"])
    fake3_says([rec], [["fixed 1 suggested fix", "main.vl", "+1 -1 lines"]], [], [refusal])
    got = ctx_of(run(ev, fake3)[1])
    case("hook fix: a did-you-mean not made, its refusal shown", (fix_calls(), got.split("\n")[-2:]),
         (["fix --suggested --dry-run main.vl --json"],
          [shown, "  refused: main.vl:4:5: not applied: `read_back`: the name it puts there is the function the "
                  "call is in: the call would call itself"]))
    fake3_says([other], [["fixed 1 suggested fix", "main.vl", "+1 -1 lines"]], [])
    case("hook fix: not without an exact fix", (ctx_of(run(ev, fake3)[1]), fix_calls()),
         ("volec check main.vl: 1 error\nmain.vl:5:5: error[type error] expected '[u8]', got 'i64'", []))
    fake3_says([marker], [], [])
    case("hook fix: refused or nothing done, named as before", ctx_of(run(ev, fake3)[1]),
         "volec check main.vl: 1 error\ntry: volec fix --suggested main.vl   (the error: their exact fixes, "
         "one checked edit)\nmain.vl:2:5: error[conv.marker] 'ui' is lent inout here (the callee may change it): "
         "mark it '&ui'")
    fake3_says([marker], [["fixed 1 suggested fix", "main.vl", "+1 -1 lines"]], [])
    os.environ["VOLE_HOOK_FIX"] = "0"
    got = ctx_of(run(ev, fake3)[1])
    del os.environ["VOLE_HOOK_FIX"]
    case("hook fix: VOLE_HOOK_FIX=0 applies nothing", (fix_calls(), got.split("\n")[1]),
         ([], "try: volec fix --suggested main.vl   (the error: their exact fixes, one checked edit)"))
    # (0.19) A test case meant to fail (`// ERROR:` lines) is left as it
    # is: its fixes are named, not applied.
    write(os.path.join(prog, "main.vl"), "// ERROR: undefined variable 'prinln'\nfn main() {}\n")
    fake3_says([marker], [["fixed 1 suggested fix", "main.vl", "+1 -1 lines"]], [])
    got = ctx_of(run(ev, fake3)[1])
    write(os.path.join(prog, "main.vl"), "mod util;\nfn main() {}\n")
    case("hook fix: not in an ERROR test case", (fix_calls(), got.split("\n")[1]),
         ([], "try: volec fix --suggested main.vl   (the error: their exact fixes, one checked edit)"))
    # (0.25.2.1) An unused import is removed only when it was unused at
    # the last check too (not one the agent has just written).
    unused = diag("main.vl", 1, "unused import 'I64_MAX': nothing in this file names it", sev="warning",
                  code="use.unused")
    ustate = tempfile.mkdtemp(dir=tmp)
    uev = dict(ev, session_id="unused")
    fake3_says([unused], [["fixed 1 unused import", "main.vl", "+0 -1 lines"], ["--- a/main.vl"], ["+++ b/main.vl"],
                          ["@@ -1 +0,0 @@"], ["-use std::I64_MAX;"]], [])
    first = (run(uev, fake3, ustate)[1], fix_calls())
    case("hook fix: an import just unused is kept", first, ("", []))
    got = ctx_of(run(uev, fake3, ustate)[1])
    case("hook fix: an import unused at two checks is removed", (fix_calls(), got),
         (["fix --only unused --in main.vl --diff main.vl --json"],
          head + "\nchanged main.vl:1: - use std::I64_MAX;" + tail1 + "\nvolec check main.vl: 0 errors"))
    case("diff changes: replaced, added, removed",
         hook.diff_changes(["--- a/x.vl", "+++ b/x.vl", "@@ -3,2 +3,3 @@", "-a", "-b", "+A", "+B", "+C",
                            "@@ -9 +10,0 @@", "-z"]),
         ["x.vl:3: a -> A", "x.vl:4: b -> B", "x.vl:4: + C", "x.vl:9: - z"])
    with open(log) as fh:
        recs = [json.loads(x) for x in fh if x.strip()]
    case("hook fix: logged", [r.get("hook_fixed") for r in recs if "hook_fixed" in r][:2], [2, 1])

    # (0.17) A worktree's file edited from a session in the main checkout:
    # the worktree's root and compiler, check run in the worktree (check
    # reads compiler/std from the directory it runs in), its paths from
    # there, said with `(in DIR)`.
    main = os.path.join(tmp, "main")
    os.makedirs(os.path.join(main, ".git"))
    wt = os.path.join(main, ".claude", "worktrees", "w")
    for t in (main, wt):
        write(os.path.join(t, "compiler", "src", "main.vl"), "fn main() {}\n")
        write(os.path.join(t, "compiler", "std", "io.vl"), "pub fn f() {}\n")
    write(os.path.join(wt, ".git"), "gitdir: " + os.path.join(main, ".git", "worktrees", "w") + "\n")
    for t, who in ((main, "main"), (wt, "worktree")):
        c = os.path.join(t, "target", "tools", "volec")
        write(c, "#!/bin/sh\nprintf '{\"kind\":\"diagnostic\",\"severity\":\"error\",\"code\":\"type error\","
                 "\"file\":\"compiler/std/io.vl\",\"line\":1,\"col\":5,\"message\":\"%s compiler in %%s\","
                 "\"help\":[],\"notes\":[],\"try\":[]}\\n' \"$(pwd -P)\" >&2\nexit 1\n" % who)
        os.chmod(c, 0o755)
    saved_cc = os.environ.pop("VOLE_CHECK_COMPILER", None)
    for t, other, name in ((wt, main, "worktree edited from the main checkout"),
                           (main, wt, "main checkout edited from a worktree")):
        xev = {"hook_event_name": "PostToolUse", "tool_name": "Edit", "cwd": other, "session_id": "xtree",
              "tool_input": {"file_path": os.path.join(t, "compiler", "std", "io.vl")}}
        env = dict(os.environ, VOLE_CHECK_HOOK_LOG=log, VOLE_HOOK_STATE=tempfile.mkdtemp(dir=tmp))
        r = subprocess.run([sys.executable, "-I", os.path.join(HERE, "check-after-edit.py")],
                           input=json.dumps(xev), capture_output=True, text=True, env=env)
        where = os.path.relpath(t, other) if t.startswith(other + os.sep) else t
        who = "worktree" if t == wt else "main"
        case(name, ctx_of(r.stdout),
             f"volec check compiler/src/main.vl (in {where}): 1 error\n"
             f"compiler/std/io.vl:1:5: error[type error] {who} compiler in {os.path.realpath(t)}")
    case("same checkout: runs in cwd", hook.run_dir_for(os.path.join(wt, "compiler", "src", "main.vl"),
                                                        os.path.join(wt, "compiler")), os.path.join(wt, "compiler"))
    if saved_cc is not None:
        os.environ["VOLE_CHECK_COMPILER"] = saved_cc

    # Tests: run after a clean check when tests/ has cases, the new
    # failures shown, not again within the debounce.
    write(os.path.join(prog, "tests", "a.in"), "1\n")
    write(os.path.join(prog, "tests", "a.out"), "1\n")
    state = tempfile.mkdtemp(dir=tmp)
    fake_says([], "test main.vl: 2 passed (tests/, 0.02 s)\n")
    case("tests: after a clean check", ctx_of(run(ev, fake2, state)[1]), "volec test main.vl: 2 passed")
    fail_b = ("test main.vl: 1 passed, 1 failed (tests/, 0.02 s)\nFAIL b: stdout differs at line 1 (1 line expected, "
              "1 printed)\n  - 2\n  + 3\n(outputs: /tmp/x/NAME.got, NAME.err)\n")
    fake_says([], fail_b, 1)
    write(os.path.join(prog, "main.vl"), "mod util;\nfn main() { }\n")
    case("tests: not again within the debounce", run(ev, fake2, state)[1], "")
    os.environ["VOLE_TEST_DEBOUNCE"] = "0"
    write(os.path.join(prog, "main.vl"), "mod util;\nfn main() {  }\n")
    case("tests: a new failure, its difference", ctx_of(run(ev, fake2, state)[1]),
         "volec test main.vl: 1 passed, 1 failed (1 newly failing)\nFAIL b: stdout differs at line 1 "
         "(1 line expected, 1 printed)\n  - 2\n  + 3")
    write(os.path.join(prog, "main.vl"), "mod util;\nfn main() {   }\n")
    case("tests: as before, one line", ctx_of(run(ev, fake2, state)[1]),
         "volec test main.vl: 1 passed, 1 failed (failing as before: b)")
    case("tests: sources unchanged, not rerun", run(ev, fake2, state)[1], "")
    write(os.path.join(prog, "main.vl"), "mod util;\nfn main() {    }\n")
    fake_says([], "test main.vl: 2 passed (tests/, 0.02 s)\n")
    case("tests: fixed", ctx_of(run(ev, fake2, state)[1]), "volec test main.vl: 2 passed (1 fixed: b)")
    write(os.path.join(prog, "main.vl"), "mod util;\nfn main() {     }\n")
    os.environ["VOLE_CHECK_TESTS"] = "0"
    case("tests: VOLE_CHECK_TESTS=0", run(ev, fake2, state)[1], "")
    del os.environ["VOLE_CHECK_TESTS"]
    del os.environ["VOLE_TEST_DEBOUNCE"]
    shutil.rmtree(os.path.join(prog, "tests"))

    # The real compiler, when it has --json (0.15): a clean program is
    # silent, an error is reported; and the latency on a cache hit.
    # (0.25.2.1) The compiler under test when tests/run.sh says which
    # (VOLE_TEST_COMPILER): target/volec may be an older build then.
    real = os.environ.get("VOLE_TEST_COMPILER") or os.path.join(REPO, "target", "volec")
    probe = subprocess.run([real, "check", "--json", "/nonexistent.vl"], capture_output=True, text=True) \
        if os.access(real, os.X_OK) else None
    if probe is not None and "unknown option" not in probe.stderr:
        write(os.path.join(prog, "main.vl"), "fn main() {\n    let x: i64 = 1;\n    let y = x + 1;\n}\n")
        os.remove(os.path.join(prog, "util.vl"))
        ev2 = dict(ev, tool_input={"file_path": os.path.join(prog, "main.vl")})
        case("real: clean is silent", run(ev2, real), (0, ""))
        write(os.path.join(prog, "main.vl"), "fn main() {\n    let x: i64 = q;\n}\n")
        st, out = run(ev2, real)
        case("real: the error", json.loads(out)["hookSpecificOutput"]["additionalContext"] if out else "",
             "volec check main.vl: 1 error\nmain.vl:2:18: error[type error] undefined variable 'q'")
        # (0.18.1) the hook applies the exact fix: the file is changed;
        # (0.25.2.1) a mechanical one only: a did-you-mean is shown
        write(os.path.join(prog, "main.vl"), "fn main() {\n    prinln(\"x\");\n    let mut y = 1 + \"a\";\n}\n")
        got = ctx_of(run(ev2, real)[1])
        with open(os.path.join(prog, "main.vl")) as fh:
            now = fh.read()
        lines = got.split("\n")
        case("real: the hook's exact fix", ([x for x in lines if x.startswith(("changed", "fixed", "  main"))],
                                            "var y" in now, "println(\"x\")" in now),
             (["changed main.vl:3: let mut y = 1 + \"a\"; -> var y = 1 + \"a\";",
               "fixed main.vl:3:5: 'let mut' is Rust's spelling; a mutable binding is 'var x' | its exact fix",
               "  main.vl:2: prinln(\"x\"); -> println(\"x\");"], True, False))
        # (0.25.2.2) A file the call left unformatted: said once, until
        # it is formatted; the hook formats nothing.
        write(os.path.join(prog, "main.vl"), "fn main() {\n    let x: i64 =   1;\n    let y = x + 1;\n}\n")
        fst = tempfile.mkdtemp(dir=tmp)
        got = ctx_of(run(ev2, real, fst)[1])
        case("real: not formatted, said", got.startswith("main.vl is not formatted: ") and " fmt main.vl " in got,
             True)
        case("real: not formatted, said once", run(ev2, real, fst)[1], "")
        os.environ["VOLE_HOOK_FMT"] = "0"
        case("real: VOLE_HOOK_FMT=0, no note", run(ev2, real)[1], "")
        del os.environ["VOLE_HOOK_FMT"]
        subprocess.run([real, "fmt", "main.vl"], cwd=prog, capture_output=True)
        case("real: formatted, silent", run(ev2, real, fst)[1], "")
        write(os.path.join(prog, "main.vl"), "fn main() {\n    let x: i64 = q;\n}\n")
        ms = []
        for _ in range(5):
            t0 = time.time()
            run(ev2, real)
            ms.append((time.time() - t0) * 1000)
        print(f"note: the hook on a cache hit takes {sorted(ms)[2]:.0f} ms (median of 5, Python's start included)")
        # (0.17) With tests: the real `volec test` after a clean check.
        if "volec test" in subprocess.run([real, "test", "--help"], capture_output=True, text=True).stdout:
            write(os.path.join(prog, "main.vl"), "use std::println;\n\nfn main() {\n    println(\"1\");\n}\n")
            write(os.path.join(prog, "tests", "one.out"), "1\n")
            write(os.path.join(prog, "tests", "two.in"), "x\n")
            write(os.path.join(prog, "tests", "two.out"), "2\n")
            os.environ["VOLE_TEST_DEBOUNCE"] = "0"
            st, out = run(ev2, real)
            case("real: the tests' summary", json.loads(out)["hookSpecificOutput"]["additionalContext"] if out else "",
                 "volec test main.vl: 1 passed, 1 failed\nFAIL two: stdout differs at line 1 (1 line expected, "
                 "1 printed)\n  - 2\n  + 1")
            ms = []
            for k in range(5):
                write(os.path.join(prog, "main.vl"), "use std::println;\n\nfn main() {\n    println(\"1\");\n}\n" + "\n" * k)
                t0 = time.time()
                run(ev2, real)
                ms.append((time.time() - t0) * 1000)
            print(f"note: the hook with check, build and 2 tests takes {sorted(ms)[2]:.0f} ms (median of 5)")
            del os.environ["VOLE_TEST_DEBOUNCE"]
        else:
            print("skip real tests: target/volec has no test command")
    else:
        print("skip real: target/volec has no --json")
    if saved is not None:
        os.environ["VOLE_CHECK_COMPILER"] = saved
finally:
    shutil.rmtree(tmp, ignore_errors=True)

print("total", "ok" if FAILED == 0 else f"{FAILED} failed")
sys.exit(1 if FAILED else 0)
