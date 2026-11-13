#!/usr/bin/env python3
"""Cases for the commit hook's unsafe check (tools/git-hooks/pre-commit,
tools/unsafe-diff-check.py, 0.25.3): the sites and their justification
come from the compiler (`volec query unsafe --json`), the diff from git.
Each case is a commit in a fresh repository holding a copy of the hook and
the script, with target/volec the compiler under test
($VOLE_TEST_COMPILER, else target/volec of this tree). Run by tests/run.sh
(category "hooks").

usage: python3 -I tools/git-hooks/test-pre-commit.py
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
    e["GIT_AUTHOR_NAME"] = e["GIT_COMMITTER_NAME"] = "t"
    e["GIT_AUTHOR_EMAIL"] = e["GIT_COMMITTER_EMAIL"] = "t@t"
    return subprocess.run(args, cwd=cwd, capture_output=True, text=True, env=e)


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fh:
        fh.write(text)


compiler = os.environ.get("VOLE_TEST_COMPILER") or os.path.join(ROOT, "target", "volec")
if not os.access(compiler, os.X_OK):
    print("skip test-pre-commit: no compiler at " + compiler)
    sys.exit(0)
compiler = os.path.abspath(compiler)

BASE = """extern "C" {
    fn puts(s: *const u8) -> i32;
}

fn main() -> i32 {
    // UNSAFE: puts is C's.
    // SAFETY: a NUL-terminated literal.
    unsafe {
        puts(c"a");
    }
    0
}
"""

# A second block a few lines under the first: the 12-line heuristic took
# the first one's comments for it; the compiler does not.
BORROWED = BASE.replace("""    0
}""", """    unsafe {
        puts(c"b");
    }
    0
}""")

JUSTIFIED = BASE.replace("""    0
}""", """    // UNSAFE: puts is C's.
    // SAFETY: a NUL-terminated literal.
    unsafe {
        puts(c"b");
    }
    0
}""")

# The word in a string and in a comment: no site.
WORDS = BASE.replace("""    0
}""", """    let s = "an unsafe { block } in a string";
    // and unsafe { } in a comment
    s.len() as i32
}""")

tmp = os.path.realpath(tempfile.mkdtemp())
try:
    repo = os.path.join(tmp, "r")
    os.makedirs(os.path.join(repo, "tools", "git-hooks"))
    os.makedirs(os.path.join(repo, "target"))
    shutil.copy(os.path.join(ROOT, "tools", "unsafe-diff-check.py"), os.path.join(repo, "tools"))
    shutil.copy(os.path.join(ROOT, "tools", "git-hooks", "pre-commit"),
                os.path.join(repo, "tools", "git-hooks"))
    os.symlink(compiler, os.path.join(repo, "target", "volec"))
    write(os.path.join(repo, ".gitignore"), "target/\n")
    write(os.path.join(repo, "main.vl"), BASE)
    run(["git", "init", "-q"], repo)
    run(["git", "add", "-A"], repo)
    r = run(["git", "commit", "-q", "-m", "base"], repo)
    case("base commit", r.returncode == 0, r.stdout + r.stderr)

    def commit(text, name):
        write(os.path.join(repo, "main.vl"), text)
        run(["git", "add", "main.vl"], repo)
        r = run(["git", "-c", "core.hooksPath=tools/git-hooks", "commit", "-q", "-m", name], repo)
        out = r.stdout + r.stderr
        if r.returncode != 0:
            run(["git", "reset", "-q", "--hard", "HEAD"], repo)
        return r.returncode, out

    # the script alone, on what is staged
    write(os.path.join(repo, "main.vl"), BORROWED)
    run(["git", "add", "main.vl"], repo)
    r = run([sys.executable, "-I", "tools/unsafe-diff-check.py", "--cached"], repo)
    case("a block under another's comments: refused",
         r.returncode == 1 and "main.vl:11: unsafe without UNSAFE:/SAFETY: comments" in r.stdout,
         r.stdout + r.stderr)
    case("the compiler answered, not the heuristic", "text heuristic" not in r.stdout, r.stdout)
    r = run([sys.executable, "-I", "tools/unsafe-diff-check.py", "--cached", "--heuristic"], repo)
    case("--heuristic: the 12-line window takes the comments above (0.25.2)",
         r.returncode == 0 and "1 file by the text heuristic (--heuristic)" in r.stdout,
         r.stdout + r.stderr)
    run(["git", "reset", "-q", "--hard", "HEAD"], repo)

    # the hook, committing
    rc, out = commit(BORROWED, "borrowed")
    case("pre-commit refuses an unjustified block",
         rc != 0 and "unsafe without UNSAFE:/SAFETY: comments" in out and "pre-commit: refused" in out,
         out)
    rc, out = commit(JUSTIFIED, "justified")
    case("pre-commit takes a justified block", rc == 0, out)
    rc, out = commit(WORDS, "words")
    case("pre-commit: the word in a string or a comment is no site", rc == 0, out)

    # staged, then changed again in the work tree: the heuristic for it
    write(os.path.join(repo, "main.vl"), BORROWED)
    run(["git", "add", "main.vl"], repo)
    write(os.path.join(repo, "main.vl"), BORROWED + "// more\n")
    r = run([sys.executable, "-I", "tools/unsafe-diff-check.py", "--cached"], repo)
    case("staged text not in the work tree: the heuristic",
         "1 file by the text heuristic (text not in the work tree" in r.stdout, r.stdout + r.stderr)
    run(["git", "reset", "-q", "--hard", "HEAD"], repo)

    # (0.29) A merge is checked for what it adds itself, not for what a
    # side brings: a branch with an unjustified block (committed past the
    # hook, as legacy code is) merges without a conflict (pre-merge-commit)
    # and with one (pre-commit, MERGE_HEAD), while a block the resolution
    # itself adds is refused.
    shutil.copy(os.path.join(ROOT, "tools", "git-hooks", "pre-merge-commit"),
                os.path.join(repo, "tools", "git-hooks"))
    hooks = ["git", "-c", "core.hooksPath=tools/git-hooks"]
    main_branch = run(["git", "symbolic-ref", "--short", "HEAD"], repo).stdout.strip()

    def side(name, text, other="other.vl"):
        """A branch off HEAD whose commit (no hook) writes main.vl, and
        HEAD moved on by a commit to another file."""
        run(["git", "checkout", "-q", "-b", name], repo)
        write(os.path.join(repo, "main.vl"), text)
        run(["git", "commit", "-q", "-am", name], repo)
        run(["git", "checkout", "-q", main_branch], repo)
        write(os.path.join(repo, other), "// " + name + "\n")
        run(["git", "add", other], repo)
        run(["git", "commit", "-q", "-m", "main beside " + name], repo)

    legacy = WORDS.replace("""    s.len() as i32
}""", """    unsafe {
        puts(c"legacy");
    }
    s.len() as i32
}""")
    side("legacy", legacy)
    r = run(hooks + ["merge", "-q", "--no-ff", "-m", "merge legacy", "legacy"], repo)
    case("a merge without a conflict: the side's unsafe is not the merge's",
         r.returncode == 0 and len(run(["git", "rev-list", "--parents", "-n", "1", "HEAD"], repo).stdout.split()) == 3,
         r.stdout + r.stderr)
    r = run(hooks + ["commit", "-q", "--allow-empty", "-m", "after"], repo)
    case("and the commit after it passes", r.returncode == 0, r.stdout + r.stderr)

    # a conflict in main.vl: both sides change the same line; the side
    # also brings an unjustified block elsewhere in the file
    conflict_side = legacy.replace('puts(c"a");', 'puts(c"side");').replace(
        'puts(c"legacy");', 'puts(c"legacy");\n    }\n    unsafe {\n        puts(c"more");')
    run(["git", "checkout", "-q", "-b", "conflict"], repo)
    write(os.path.join(repo, "main.vl"), conflict_side)
    run(["git", "commit", "-q", "-am", "conflict"], repo)
    run(["git", "checkout", "-q", main_branch], repo)
    write(os.path.join(repo, "main.vl"), legacy.replace('puts(c"a");', 'puts(c"main");'))
    run(["git", "commit", "-q", "-am", "main's line"], repo)
    r = run(hooks + ["merge", "-q", "--no-ff", "-m", "merge conflict", "conflict"], repo)
    case("the merge conflicts", r.returncode != 0 and os.path.exists(os.path.join(repo, ".git", "MERGE_HEAD")),
         r.stdout + r.stderr)
    resolved = conflict_side.replace('puts(c"side");', 'puts(c"both");')
    write(os.path.join(repo, "main.vl"), resolved.replace("""    s.len() as i32
}""", """    unsafe {
        puts(c"the resolution's own");
    }
    s.len() as i32
}"""))
    run(["git", "add", "main.vl"], repo)
    r = run(hooks + ["commit", "-q", "-m", "merge conflict"], repo)
    out = r.stdout + r.stderr
    case("a resolution that adds an unjustified block: refused, for that block only",
         r.returncode != 0 and out.count("unsafe without UNSAFE:/SAFETY: comments") == 1
         and "pre-commit: refused" in out, out)
    write(os.path.join(repo, "main.vl"), resolved)
    run(["git", "add", "main.vl"], repo)
    r = run(hooks + ["commit", "-q", "-m", "merge conflict"], repo)
    case("a resolution that adds none: the side's unsafe is not the merge's",
         r.returncode == 0 and not os.path.exists(os.path.join(repo, ".git", "MERGE_HEAD")), r.stdout + r.stderr)
    # outside a merge the side's block is still refused (HEAD~1: main
    # before the merge, without the side's second block)
    run(["git", "checkout", "-q", "-b", "plain", "HEAD~1"], repo)
    rc, out = commit(resolved, "plain")
    case("the side's block in a plain commit: refused",
         rc != 0 and out.count("unsafe without UNSAFE:/SAFETY: comments") == 1, out)
finally:
    shutil.rmtree(tmp, ignore_errors=True)

print(f"test-pre-commit: {'ok' if FAILED == 0 else str(FAILED) + ' failed'}")
sys.exit(1 if FAILED else 0)
