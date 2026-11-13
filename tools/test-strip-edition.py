#!/usr/bin/env python3
"""The tests of tools/strip-edition.py: a small tree in a temporary git
repository, stripped, then compared file by file; a second run changes
nothing.

usage: python3 tools/test-strip-edition.py   (prints `ok: N checks`, or
what differs and exits 1)
"""
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
E = "// EDITION: rust\n"

# path: (before, after)
TREE = {
    # a case: the line first; every form of position after it
    "tests/run/err_a.vl": (
        E + "// ERROR: line 5, column 9\n// ERROR: err_a.vl:6:3: error[type error] x\n"
        "// ERROR: the '{' at line 7 is the last left open\n// ERROR: moved at 8:20 (on some paths)\n"
        "// XFAIL: gap 2: errors at other places: MVS type error@9:11; rust type error@10:10\n"
        "// XFAIL: gap 9: output: line 4: expected 'a', got 'b'\n"
        "// EXPECT: move 3 4; line 1 2 to 5 6\n// STDERR: err_a.vl:12 main\n"
        "// EXPECT: probe expr=[f.vl:3]\nfn main() {}\n",
        "// ERROR: line 4, column 9\n// ERROR: err_a.vl:5:3: error[type error] x\n"
        "// ERROR: the '{' at line 6 is the last left open\n// ERROR: moved at 7:20 (on some paths)\n"
        "// XFAIL: gap 2: errors at other places: MVS type error@9:11; rust type error@9:10\n"
        "// XFAIL: gap 9: output: line 4: expected 'a', got 'b'\n"
        "// EXPECT: move 3 4; line 1 2 to 5 6\n// STDERR: err_a.vl:11 main\n"
        "// EXPECT: probe expr=[f.vl:3]\nfn main() {}\n"),
    # the line last: nothing moves
    "tests/run/last.vl": (
        "// STDERR: last.vl:2:5: boom\nfn main() {}\n" + E,
        "// STDERR: last.vl:2:5: boom\nfn main() {}\n"),
    # two lines, one in the middle: a position after both moves by two
    "tests/run/two.vl": (
        E + "// STDERR: two.vl:3:1: a\nfn a() {}\n" + E + "// STDERR: two.vl:6:1: b\nfn main() {}\n",
        "// STDERR: two.vl:2:1: a\nfn a() {}\n// STDERR: two.vl:4:1: b\nfn main() {}\n"),
    # a directory case names a module's file, one directory up
    "tests/run/dir/main.vl": (
        E + "// ERROR: dir/b.vl: line 2\n// ERROR: main.vl: line 5, column 1\nmod b;\nfn main() {}\n",
        "// ERROR: dir/b.vl: line 2\n// ERROR: main.vl: line 4, column 1\nmod b;\nfn main() {}\n"),
    "tests/run/dir/b.vl": ("fn b() {}\n", "fn b() {}\n"),
    # a transcript and its program: positions, a range, the text shown
    "tests/query/prog/main.vl": (E + "fn main() {}\n", "fn main() {}\n"),
    "tests/query/prog.q": (
        "$ show main\n// main\tprog/main.vl:2-2\nfn main() {}\n$ refs main\nprog/main.vl:2:4\tdef\n<std>:10:2\tx\n",
        "$ show main\n// main\tprog/main.vl:1-1\nfn main() {}\n$ refs main\nprog/main.vl:1:4\tdef\n<std>:10:2\tx\n"),
    # a transcript that writes over its program: positions below are the new text's
    "tests/query/prog2/main.vl": (E + "fn main() {}\n", "fn main() {}\n"),
    "tests/query/prog2.t": (
        "$ check\nmain.vl:2:4: a\n% printf 'fn main() {\\n    x\\n}\\n' > main.vl\n$ check\nmain.vl:2:5: b\n",
        "$ check\nmain.vl:1:4: a\n% printf 'fn main() {\\n    x\\n}\\n' > main.vl\n$ check\nmain.vl:2:5: b\n"),
    "tests/refactor/p.t": (
        "% printf 'fn main() {}\\n// EDITION: rust\\n' > main.vl\n% cat main.vl\nfn main() {}\n" + E,
        "% printf 'fn main() {}\\n' > main.vl\n% cat main.vl\nfn main() {}\n"),
    # an example's case: the program is its SOURCE
    "examples/x/main.vl": (E + "fn main() {}\n", "fn main() {}\n"),
    "tests/examples/x.test": (
        "// SOURCE: examples/x/main.vl\n// STDERR: allocated at main.vl:20:5\n",
        "// SOURCE: examples/x/main.vl\n// STDERR: allocated at main.vl:19:5\n"),
    "examples/x/README.md": (
        "```console\n$ volec check old.vl\nold.vl:2:1: before it is written\n$ cat > old.vl <<'EOF'\n> // EDITION: rust\n"
        "> fn main() {}\n> EOF\n$ volec check main.vl old.vl\nmain.vl:3:1: x\nold.vl:2:4: y\n```\n",
        "```console\n$ volec check old.vl\nold.vl:2:1: before it is written\n$ cat > old.vl <<'EOF'\n"
        "> fn main() {}\n> EOF\n$ volec check main.vl old.vl\nmain.vl:2:1: x\nold.vl:1:4: y\n```\n"),
    # a transcript that writes its program with printf: the line first, then last
    "tests/refactor/w.t": (
        "% printf '// EDITION: rust\\nfn main() {\\n}\\n' > w.vl\n$ check w.vl\nw.vl:2:1: x\n"
        "% printf 'fn f() {}\\n// EDITION: rust\\n' > v.vl\n$ check v.vl\nv.vl:1:4: y\n"
        "% printf 'fn main() {\\n    x\\n}\\n// EDITION: rust\\n' > w.vl\n$ check w.vl\nw.vl:2:5: z\n",
        "% printf 'fn main() {\\n}\\n' > w.vl\n$ check w.vl\nw.vl:1:1: x\n"
        "% printf 'fn f() {}\\n' > v.vl\n$ check v.vl\nv.vl:1:4: y\n"
        "% printf 'fn main() {\\n    x\\n}\\n' > w.vl\n$ check w.vl\nw.vl:2:5: z\n"),
    # scripts: a here-document, a string, awk's print; a test of the line stays
    "tests/gen.sh": (
        "cat > p.vl <<'EOF'\n" + E + "fn main() {}\nEOF\nprintf '// EDITION: rust\\r\\nfn main() {}\\r\\n' > q.vl\n"
        "grep -q '^// EDITION: rust' p.vl\n",
        "cat > p.vl <<'EOF'\nfn main() {}\nEOF\nprintf 'fn main() {}\\r\\n' > q.vl\n"
        "grep -q '^// EDITION: rust' p.vl\n"),
    "tests/gen.awk": (
        'BEGIN {\n    print "// EDITION: rust"\n    print "// EDITION: rust\\nfn main() {}"\n    if (x) print "// EDITION: rust" > f\n}\n',
        'BEGIN {\n    print "fn main() {}"\n    if (x) print "// EDITION: rust" > f\n}\n'),
    # a grammar snapshot: the line and its scopes
    "editors/vscode/test/snapshots/a.vl.snap": (
        ">// SYNTAX TEST\n#^^ comment\n>// EDITION: rust\n#^^ comment\n#  ^^^ comment\n>fn main() {}\n#^^ keyword\n",
        ">// SYNTAX TEST\n#^^ comment\n>fn main() {}\n#^^ keyword\n"),
    # kept: the previous release reads them; history
    "compiler/src/main.vl": ("fn main() {}\n" + E, "fn main() {}\n" + E),
    "tests/cost/std_heavy.vl": (E + "fn main() {}\n", E + "fn main() {}\n"),
    "docs/releases.md": ("```\n" + E + "```\n", "```\n" + E + "```\n"),
    # CRLF is kept
    "tests/run/crlf.vl": ("// EDITION: rust\r\nfn main() {}\r\n", "fn main() {}\r\n"),
}


def main():
    tmp = tempfile.mkdtemp(prefix="strip-edition-test.")
    failed = 0
    checks = 0
    try:
        os.makedirs(os.path.join(tmp, "tools"))
        shutil.copy(os.path.join(HERE, "strip-edition.py"), os.path.join(tmp, "tools", "strip-edition.py"))
        for p, (before, _) in TREE.items():
            full = os.path.join(tmp, p)
            os.makedirs(os.path.dirname(full), exist_ok=True)
            with open(full, "w", encoding="utf-8", newline="") as f:
                f.write(before)
        git = ["git", "-c", "user.name=t", "-c", "user.email=t@example.com", "-c", "core.hooksPath=/dev/null"]
        subprocess.run(git + ["init", "-q"], cwd=tmp, check=True)
        subprocess.run(git + ["add", "-A"], cwd=tmp, check=True)
        subprocess.run(git + ["commit", "-q", "-m", "tree"], cwd=tmp, check=True)
        tool = [sys.executable, os.path.join(tmp, "tools", "strip-edition.py")]

        def snapshot():
            out = {}
            for p in TREE:
                with open(os.path.join(tmp, p), encoding="utf-8", newline="") as f:
                    out[p] = f.read()
            return out

        dry = subprocess.run(tool + ["--dry-run"], cwd=tmp, capture_output=True, text=True)
        checks += 1
        if dry.returncode != 0 or any(snapshot()[p] != TREE[p][0] for p in TREE):
            print("FAIL --dry-run changed the tree or failed:\n" + dry.stdout + dry.stderr)
            failed += 1
        first = subprocess.run(tool, cwd=tmp, capture_output=True, text=True)
        got = snapshot()
        for p in sorted(TREE):
            checks += 1
            if got[p] != TREE[p][1]:
                print("FAIL %s:\n--- expected\n%s--- got\n%s" % (p, TREE[p][1], got[p]))
                failed += 1
        for want in ("tests/gen.sh:5:", "tests/gen.awk:3:", "compiler/src/main.vl", "tests/cost/std_heavy.vl",
                     "tests/query/prog.q", "tests/refactor/p.t"):
            checks += 1
            if want not in first.stdout:
                print("FAIL the report does not name %s:\n%s" % (want, first.stdout))
                failed += 1
        second = subprocess.run(tool, cwd=tmp, capture_output=True, text=True)
        checks += 1
        if snapshot() != got or " 0 files changed" not in second.stdout:
            print("FAIL a second run changed the tree:\n" + second.stdout + second.stderr)
            failed += 1
        # --check-rerecord: numbers and edition lines are no difference; a word is
        with open(os.path.join(tmp, "tests/query/prog.q"), "a", encoding="utf-8") as f:
            f.write("$ items\n7\tfn\n")
        r = subprocess.run(tool + ["--check-rerecord"], cwd=tmp, capture_output=True, text=True)
        checks += 1
        if r.returncode != 1 or "tests/query/prog.q" not in r.stdout or "tests/refactor/p.t" in r.stdout.split("check-rerecord:")[0]:
            print("FAIL --check-rerecord:\n" + r.stdout + r.stderr)
            failed += 1
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    if failed:
        print("test-strip-edition: %d of %d checks failed" % (failed, checks))
        return 1
    print("ok: %d checks" % checks)
    return 0


if __name__ == "__main__":
    sys.exit(main())
