#!/usr/bin/env python3
"""Cases for compiler/src/front/stdsrc.vl as git keeps it (0.25.3): the
commit hook makes it from the staged compiler/std (tools/git-hooks/
pre-commit), and the merge driver (tools/git-hooks/merge-stdsrc,
.gitattributes) makes it from the merged compiler/std, so that two
branches that both change std merge without a conflict on it. Each case
runs in a fresh repository with a small std (tests/refactor/stdedit's)
and this tree's embed.sh, hook and driver, set up as
tools/git-hooks/setup.sh does. Run by tests/run.sh (category "hooks").

usage: python3 -I tools/git-hooks/test-stdsrc.py
"""
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SRC = "compiler/src/front/stdsrc.vl"
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
    for k in list(e):
        if k.startswith("GITHEAD_") or k in ("GIT_DIR", "GIT_INDEX_FILE", "GIT_WORK_TREE"):
            del e[k]
    e["GIT_AUTHOR_NAME"] = e["GIT_COMMITTER_NAME"] = "t"
    e["GIT_AUTHOR_EMAIL"] = e["GIT_COMMITTER_EMAIL"] = "t@t"
    e["GIT_CONFIG_NOSYSTEM"] = "1"
    e["HOME"] = cwd
    return subprocess.run(args, cwd=cwd, capture_output=True, text=True, env=e)


def read(path):
    with open(path) as fh:
        return fh.read()


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fh:
        fh.write(text)


def embedded(repo, rev):
    """What embed.sh makes of compiler/std at rev (a commit, or ":" for
    the index), next to what the commit (or index) holds as stdsrc.vl."""
    t = tempfile.mkdtemp(prefix="vole-stdsrc-case.")
    try:
        if rev == ":":
            files = run(["git", "ls-files", "compiler/std"], repo).stdout.split()
            for f in files:
                write(os.path.join(t, f), run(["git", "show", ":" + f], repo).stdout)
            held = run(["git", "show", ":" + SRC], repo).stdout
        else:
            arc = subprocess.run(["git", "archive", rev, "compiler/std"], cwd=repo, capture_output=True)
            subprocess.run(["tar", "-xf", "-", "-C", t], input=arc.stdout, check=True)
            held = run(["git", "show", f"{rev}:{SRC}"], repo).stdout
        os.makedirs(os.path.join(t, "compiler/src/front"), exist_ok=True)
        subprocess.run(["sh", os.path.join(t, "compiler/std/embed.sh")], capture_output=True)
        return read(os.path.join(t, SRC)), held
    finally:
        shutil.rmtree(t)


def git(repo, *args):
    return run(["git", *args], repo)


def main():
    work = tempfile.mkdtemp(prefix="vole-stdsrc.")
    repo = os.path.join(work, "repo")
    try:
        shutil.copytree(os.path.join(ROOT, "tests/refactor/stdedit/compiler/std"), os.path.join(repo, "compiler/std"))
        for f in ("embed.sh", "index.awk"):
            shutil.copy(os.path.join(ROOT, "compiler/std", f), os.path.join(repo, "compiler/std", f))
        # (the systems' tails, of one length)
        write(os.path.join(repo, "compiler/std/sys/macos.vl"), "pub const TARGET_OS: i64 = 1;\n")
        write(os.path.join(repo, "compiler/std/sys/linux.vl"), "pub const TARGET_OS: i64 = 2;\n")
        os.makedirs(os.path.join(repo, "tools/git-hooks"))
        for f in ("pre-commit", "merge-stdsrc", "setup.sh"):
            shutil.copy(os.path.join(HERE, f), os.path.join(repo, "tools/git-hooks", f))
        # (the unsafe check is test-pre-commit.py's: a stand-in here)
        write(os.path.join(repo, "tools/unsafe-diff-check.py"), "import sys\nsys.exit(0)\n")
        shutil.copy(os.path.join(ROOT, ".gitattributes"), os.path.join(repo, ".gitattributes"))
        os.makedirs(os.path.join(repo, "compiler/src/front"), exist_ok=True)
        subprocess.run(["sh", "compiler/std/embed.sh"], cwd=repo, capture_output=True)
        git(repo, "init", "-q", "-b", "main")
        r = run(["sh", "tools/git-hooks/setup.sh"], repo)
        case("setup.sh", r.returncode == 0 and git(repo, "config", "merge.stdsrc.driver").stdout.strip()
             == "sh tools/git-hooks/merge-stdsrc %O %A %B %P", r.stdout + r.stderr)
        git(repo, "add", "-A")
        r = git(repo, "commit", "-q", "-m", "base")
        case("base commit", r.returncode == 0, r.stdout + r.stderr)
        io = os.path.join(repo, "compiler/std/flat/io.vl")
        std = os.path.join(repo, "compiler/std/std.vl")
        base_io = read(io)
        base_std = read(std)

        # A std change committed alone: the hook makes and stages stdsrc.vl.
        git(repo, "checkout", "-q", "-b", "a")
        write(io, base_io + "\n// a's line\npub fn from_a() -> i64 {\n    1\n}\n")
        git(repo, "add", "compiler/std/flat/io.vl")
        r = git(repo, "commit", "-q", "-m", "a")
        made, held = embedded(repo, "HEAD")
        case("pre-commit: stdsrc.vl made and staged with a std change",
             r.returncode == 0 and "made from the staged compiler/std" in r.stdout + r.stderr
             and made == held and "from_a" in held, r.stdout + r.stderr)
        case("pre-commit: the work tree's stdsrc.vl is the committed one",
             git(repo, "status", "--porcelain").stdout == "", git(repo, "status", "--porcelain").stdout)

        # The other branch changes another std file.
        git(repo, "checkout", "-q", "-b", "b", "main")
        write(std, base_std + "\n// b's line\npub fn from_b() -> i64 {\n    2\n}\n")
        r = git(repo, "commit", "-q", "-am", "b")
        case("pre-commit: with -a too", r.returncode == 0 and embedded(repo, "HEAD")[0] == embedded(repo, "HEAD")[1],
             r.stdout + r.stderr)

        # Merged: no conflict, and stdsrc.vl is the merged std's.
        r = git(repo, "merge", "-q", "--no-edit", "a")
        made, held = embedded(repo, "HEAD")
        case("merge: two std changes, no conflict on stdsrc.vl", r.returncode == 0, r.stdout + r.stderr)
        case("merge: stdsrc.vl is what embed.sh makes of the merged std",
             made == held and "from_a" in held and "from_b" in held,
             "from_a %s, from_b %s, same %s" % ("from_a" in held, "from_b" in held, made == held))
        case("merge: the driver said so", "made from the merged compiler/std" in r.stdout + r.stderr, r.stdout + r.stderr)

        # Both change the same std line: std conflicts, stdsrc.vl says what
        # to run; resolved, the commit makes stdsrc.vl.
        git(repo, "checkout", "-q", "-b", "c", "main")
        write(io, base_io.replace("a += 1;", "a = a + 1;"))
        git(repo, "commit", "-q", "-am", "c")
        git(repo, "checkout", "-q", "-b", "d", "main")
        write(io, base_io.replace("a += 1;", "a += 2;"))
        git(repo, "commit", "-q", "-am", "d")
        r = git(repo, "merge", "-q", "--no-edit", "c")
        out = r.stdout + r.stderr
        case("merge: std itself conflicts, stdsrc.vl's driver says what to run",
             r.returncode != 0 and "merge-stdsrc: compiler/src/front/stdsrc.vl not merged (compiler/std conflicts" in out
             and "compiler/std/embed.sh" in out, out)
        write(io, base_io.replace("a += 1;", "a += 3;"))
        git(repo, "add", "compiler/std/flat/io.vl", SRC)
        r = git(repo, "commit", "-q", "--no-edit")
        made, held = embedded(repo, "HEAD")
        case("merge resolved: the commit makes stdsrc.vl of the resolved std",
             r.returncode == 0 and made == held and "a += 3;" in held, r.stdout + r.stderr)

        # A commit of named paths has a temporary index: refused, with what to run.
        write(io, base_io + "\n// e\n")
        r = git(repo, "commit", "-q", "-m", "e", "compiler/std/flat/io.vl")
        case("pre-commit: `git commit FILE` with a stale stdsrc.vl is refused",
             r.returncode != 0 and "is not what compiler/std/embed.sh makes" in r.stdout + r.stderr, r.stdout + r.stderr)
        git(repo, "checkout", "-q", "--", ".")

        # A cherry-pick names no merged commit: a conflict, with what to run.
        git(repo, "checkout", "-q", "-b", "f", "main")
        write(std, base_std + "\n// f\n")
        git(repo, "commit", "-q", "-am", "f")
        r = git(repo, "cherry-pick", "a")
        out = r.stdout + r.stderr
        case("cherry-pick: stdsrc.vl not merged, with what to run",
             r.returncode != 0 and "a rebase or cherry-pick" in out, out)
        git(repo, "cherry-pick", "--abort")

        # Without the driver (a clone not set up): the old text conflict.
        git(repo, "checkout", "-q", "b~1")
        git(repo, "checkout", "-q", "-b", "g")
        git(repo, "config", "--remove-section", "merge.stdsrc")
        r = git(repo, "merge", "-q", "--no-edit", "a")
        case("no driver set up: stdsrc.vl conflicts as text (setup.sh is needed)",
             r.returncode != 0 and "stdsrc.vl" in r.stdout + r.stderr, r.stdout + r.stderr)
    finally:
        shutil.rmtree(work)


if not shutil.which("git"):
    print("skip test-stdsrc: no git")
    sys.exit(0)
main()
sys.exit(1 if FAILED else 0)
