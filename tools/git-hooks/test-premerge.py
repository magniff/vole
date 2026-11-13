#!/usr/bin/env python3
"""Cases for tools/premerge.sh's check row (0.29): it checks every program
a changed file belongs to (a .vl, a shader the program embeds, a file
beside its main.vl) and never passes on no program. Before, only a
changed .vl counted, so a change to an example's shader alone got `check
PASS 0 program(s) check clean` with the shader broken.

Each case is a change on a branch of a fresh repository (a base branch
release-0.0, a copy of premerge.sh and of the unsafe check), with
target/volec the compiler under test ($VOLE_TEST_COMPILER, else
target/volec of this tree). Run by tests/run.sh (category "hooks").

usage: python3 -I tools/git-hooks/test-premerge.py
"""
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
FAILED = 0


def case(name, ok, detail=""):
    global FAILED
    if ok:
        print(f"pass {name}")
    else:
        FAILED += 1
        print(f"FAIL {name}: {detail}")


def run(args, cwd, **env):
    e = dict(os.environ)
    e.update(env)
    e.pop("VOLEC", None)
    e.pop("VOLE_ROOT", None)
    e["VOLE_CACHE"] = "off"
    e["GIT_AUTHOR_NAME"] = e["GIT_COMMITTER_NAME"] = "t"
    e["GIT_AUTHOR_EMAIL"] = e["GIT_COMMITTER_EMAIL"] = "t@t"
    return subprocess.run(args, cwd=cwd, capture_output=True, text=True, env=e)


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fh:
        fh.write(text)


compiler = os.environ.get("VOLE_TEST_COMPILER") or os.path.join(ROOT, "target", "volec")
if not os.access(compiler, os.X_OK):
    print("skip test-premerge: no compiler at " + compiler)
    sys.exit(0)
compiler = os.path.abspath(compiler)

MAIN = """embed wgsl SHADE from b"shade.wgsl";

fn main() -> i32 {
    println("{}", SHADE.fs.len());
    0
}
"""

SHADER = """@fragment
fn fs() -> @location(0) vec4<f32> {
    let level = 0.5;
    return vec4<f32>(level, level, level, 1.0);
}
"""

BROKEN = SHADER.replace("let level = 0.5;", "let level = 0.5 + nosuchname;")

ALONE = """fn main() -> i32 {
    println("alone");
    0
}
"""

tmp = os.path.realpath(tempfile.mkdtemp())
try:
    repo = os.path.join(tmp, "r")
    os.makedirs(os.path.join(repo, "tools"))
    os.makedirs(os.path.join(repo, "target"))
    for f in ("premerge.sh", "unsafe-diff-check.py"):
        shutil.copy(os.path.join(ROOT, "tools", f), os.path.join(repo, "tools"))
    os.symlink(compiler, os.path.join(repo, "target", "volec"))
    write(os.path.join(repo, ".gitignore"), "target/\n")
    write(os.path.join(repo, "examples", "shade", "main.vl"), MAIN)
    write(os.path.join(repo, "examples", "shade", "shade.wgsl"), SHADER)
    write(os.path.join(repo, "examples", "shade", "README.md"), "# shade\n")
    write(os.path.join(repo, "examples", "alone.vl"), ALONE)
    write(os.path.join(repo, "docs", "notes.md"), "notes\n")
    write(os.path.join(repo, "tests", "examples", "shade.test"), "// SOURCE: examples/shade/main.vl\n")
    write(os.path.join(repo, "tests", "run", "err_x.vl"), "// ERROR: unknown name\nfn main() -> i32 { y }\n")
    run(["git", "init", "-q", "-b", "release-0.0"], repo)
    run(["git", "add", "-A"], repo)
    r = run(["git", "commit", "-q", "-m", "base"], repo)
    case("base commit", r.returncode == 0, r.stdout + r.stderr)
    run(["git", "checkout", "-q", "-b", "work"], repo)

    def premerge(changes):
        """The check row and the whole output, with `changes` (path:
        text) in the work tree; the tree is put back after."""
        for path, text in changes.items():
            write(os.path.join(repo, path), text)
        r = run(["sh", "tools/premerge.sh"], repo)
        out = r.stdout + r.stderr
        run(["git", "checkout", "-q", "--", "."], repo)
        run(["git", "clean", "-q", "-fd"], repo)
        rows = [line.split(None, 2) for line in out.splitlines() if line.startswith("  check ")]
        row = rows[0] if rows else ["check", "?", ""]
        return r.returncode, row[1], row[2] if len(row) > 2 else "", out

    rc, verdict, text, out = premerge({})
    case("nothing changed: SKIP, not PASS", rc == 0 and verdict == "SKIP", out)

    rc, verdict, text, out = premerge({"examples/shade/shade.wgsl": BROKEN})
    case("a broken shader alone: FAIL", rc == 1 and verdict == "FAIL", out)
    case("the shader's error is shown at its own line",
         "shade.wgsl:3:23" in out and "unknown name 'nosuchname'" in out, out)

    rc, verdict, text, out = premerge({"examples/shade/shade.wgsl": SHADER + "// a comment\n"})
    case("a sound shader change: its program is checked",
         rc == 0 and verdict == "PASS" and "1 program" in text and "examples/shade/main.vl" in text, out)

    rc, verdict, text, out = premerge({"examples/shade/README.md": "# shade\n\nmore\n"})
    case("a README beside a main.vl: its program is checked",
         rc == 0 and verdict == "PASS" and "1 program" in text, out)

    rc, verdict, text, out = premerge({"docs/notes.md": "other notes\n"})
    case("docs only: SKIP with the reason", rc == 0 and verdict == "SKIP" and "no program" in text, out)

    rc, verdict, text, out = premerge({"examples/alone.vl": ALONE.replace("alone", "still alone")})
    case("a program of one file is checked alone",
         rc == 0 and verdict == "PASS" and "examples/alone.vl" in text, out)

    rc, verdict, text, out = premerge({"examples/alone.vl": ALONE.replace("    0\n", "    nosuch\n")})
    case("and its error fails the row", rc == 1 and verdict == "FAIL" and "alone.vl" in out, out)

    rc, verdict, text, out = premerge({"tests/run/err_x.vl": "// ERROR: unknown name\nfn main() -> i32 { z }\n"})
    case("a test alone: SKIP, the tests are affected.sh's",
         rc == 0 and verdict == "SKIP" and "tests/" in text, out)

    rc, verdict, text, out = premerge({
        "examples/shade/main.vl": MAIN.replace("fn main", "// premerge: broken on purpose (a case)\nfn main"),
        "examples/shade/shade.wgsl": BROKEN,
    })
    case("a program broken on purpose is not counted as checked",
         rc == 0 and verdict == "SKIP" and "on purpose" in text, out)
finally:
    shutil.rmtree(tmp, ignore_errors=True)

sys.exit(1 if FAILED else 0)
