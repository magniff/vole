#!/usr/bin/env python3
"""Cases for compiler/src/front/stdsrc_rust.vl as git keeps it (0.25.3):
the commit hook makes it from the staged compiler/std (tools/git-hooks/
pre-commit), and the merge driver (tools/git-hooks/merge-stdsrc,
.gitattributes) makes it from the merged compiler/std, so that two
branches that both change std merge without a conflict on it. Each case
runs in a fresh repository with a small std (small_std below)
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
SRC = "compiler/src/front/stdsrc_rust.vl"
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


def small_std(repo):
    """A small std in repo: this tree's embed.sh, a root with one module,
    and the files embed.sh reads beside them (Gpa's, the systems')."""
    write(os.path.join(repo, "compiler/std/std.vl"),
          "// EDITION: rust\n// A small std.\npub mod io;\n\npub fn zero() -> i64 {\n    0\n}\n")
    write(os.path.join(repo, "compiler/std/io.vl"),
          "// Text.\npub fn bump(n: i64) -> i64 {\n    let mut a = n;\n    a += 1;\n    a\n}\n")
    for f in ("gpa", "alloc_check", "sys_linux", "sys_macos"):
        write(os.path.join(repo, "compiler/std/rt", f + ".vl"), "pub fn " + f + "() {}\n")
    os.makedirs(os.path.join(repo, "compiler/std"), exist_ok=True)
    shutil.copy(os.path.join(ROOT, "compiler/std/embed.sh"), os.path.join(repo, "compiler/std/embed.sh"))


def embedded(repo, rev):
    """What embed.sh makes of the std at rev (a commit, or ":" for the
    index), next to what the commit (or index) holds as stdsrc_rust.vl."""
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
        # (run there: no compiler of this tree makes the index)
        subprocess.run(["sh", "compiler/std/embed.sh"], cwd=t, capture_output=True)
        return read(os.path.join(t, SRC)), held
    finally:
        shutil.rmtree(t)


def git(repo, *args, **env):
    return run(["git", *args], repo, **env)


def main():
    work = tempfile.mkdtemp(prefix="vole-stdsrc.")
    repo = os.path.join(work, "repo")
    try:
        small_std(repo)
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
        io = os.path.join(repo, "compiler/std/io.vl")
        std = os.path.join(repo, "compiler/std/std.vl")
        base_io = read(io)
        base_std = read(std)

        # A std change committed alone: the hook makes and stages stdsrc.vl.
        git(repo, "checkout", "-q", "-b", "a")
        write(io, base_io + "\n// a's line\npub fn from_a() -> i64 {\n    1\n}\n")
        git(repo, "add", "compiler/std/io.vl")
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
             r.returncode != 0 and "merge-stdsrc: compiler/src/front/stdsrc_rust.vl not merged (compiler/std conflicts" in out
             and "compiler/std/embed.sh" in out, out)
        write(io, base_io.replace("a += 1;", "a += 3;"))
        git(repo, "add", "compiler/std/io.vl", SRC)
        r = git(repo, "commit", "-q", "--no-edit")
        made, held = embedded(repo, "HEAD")
        case("merge resolved: the commit makes stdsrc.vl of the resolved std",
             r.returncode == 0 and made == held and "a += 3;" in held, r.stdout + r.stderr)

        # A commit of named paths has a temporary index: refused, with what to run.
        write(io, base_io + "\n// e\n")
        r = git(repo, "commit", "-q", "-m", "e", "compiler/std/io.vl")
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
             r.returncode != 0 and "stdsrc_rust.vl" in r.stdout + r.stderr, r.stdout + r.stderr)
    finally:
        shutil.rmtree(work)


def std2_case():
    """(0.27.5, Z5.2) stdsrc_rust.vl's index of std2's units, std2_units, is
    made by a compiler: a commit of a std2 change in a tree whose compilers
    cannot make it (0.27.4's, as every worktree's target/tools/volec is
    until the release) keeps the index the file has, never an empty one."""
    compiler = os.environ.get("VOLE_TEST_COMPILER") or os.path.join(ROOT, "target/volec")
    probe = subprocess.run([compiler, "--edition", "rust", "__std2-index", "/dev/null"],
                           capture_output=True, text=True) if os.path.exists(compiler) else None
    if probe is None or not probe.stdout.startswith("std2-units "):
        print("skip std2 index: no compiler of 0.27.5 or later")
        return
    rsrc = "compiler/src/front/stdsrc_rust.vl"
    work = tempfile.mkdtemp(prefix="vole-stdsrc2.")
    repo = os.path.join(work, "repo")
    try:
        small_std(repo)
        os.remove(os.path.join(repo, "compiler/std/io.vl"))
        std2 = os.path.join(repo, "compiler/std/std.vl")
        write(std2, "// EDITION: rust\npub fn one() -> i64 {\n    1\n}\n")
        for f in ("gpa", "alloc_check", "sys_linux", "sys_macos"):
            write(os.path.join(repo, "compiler/std/rt", f + ".vl"), "// EDITION: rust\npub fn " + f + "() {}\n")
        write(os.path.join(repo, ".gitignore"), "target/\n")
        os.makedirs(os.path.join(repo, "tools/git-hooks"))
        for f in ("pre-commit", "merge-stdsrc", "setup.sh"):
            shutil.copy(os.path.join(HERE, f), os.path.join(repo, "tools/git-hooks", f))
        write(os.path.join(repo, "tools/unsafe-diff-check.py"), "import sys\nsys.exit(0)\n")
        shutil.copy(os.path.join(ROOT, ".gitattributes"), os.path.join(repo, ".gitattributes"))
        os.makedirs(os.path.join(repo, "compiler/src/front"), exist_ok=True)
        os.makedirs(os.path.join(repo, "target"))
        volec = os.path.join(repo, "target/volec")
        os.symlink(compiler, volec)
        git(repo, "init", "-q", "-b", "main")
        run(["sh", "tools/git-hooks/setup.sh"], repo)
        for f in ["compiler/std/std.vl"] + ["compiler/std/rt/%s.vl" % f for f in ("gpa", "alloc_check", "sys_linux", "sys_macos")]:
            run([compiler, "fmt", f], repo)
        git(repo, "add", "-A")
        r = git(repo, "commit", "-q", "-m", "base", VOLE_EMBED_VOLEC="")
        held = git(repo, "show", "HEAD:" + rsrc).stdout
        case("std2: a commit with a compiler that makes the index: stdsrc_rust.vl has it",
             r.returncode == 0 and "std2-units 1 " in held, r.stdout + r.stderr)
        # the tree's compiler now one that cannot (0.27.4's: no
        # __std2-index, the rest as the compiler's)
        os.remove(volec)
        write(volec, "#!/bin/sh\nfor a in \"$@\"; do\n    if [ \"$a\" = __std2-index ]; then\n"
              "        echo \"error cli.not-a-command: '__std2-index' is not a volec command or a file\" >&2\n"
              "        exit 1\n    fi\ndone\nexec '%s' \"$@\"\n" % compiler)
        os.chmod(volec, 0o755)
        write(std2, read(std2) + "\npub fn two() -> i64 {\n    2\n}\n")
        git(repo, "add", "compiler/std/std.vl")
        r = git(repo, "commit", "-q", "-m", "two", VOLE_EMBED_VOLEC="")
        after = git(repo, "show", "HEAD:" + rsrc).stdout
        out = r.stdout + r.stderr
        case("std2: a commit with no compiler that makes the index keeps the one the file has",
             r.returncode == 0 and "std2-units 1 " in after and "two" in after
             and after.split("pub fn std2_units")[1].split("\n}\n")[0]
             == held.split("pub fn std2_units")[1].split("\n}\n")[0], out)
        case("std2: and says so", "std2_units kept as it was" in out, out)
        case("std2: the work tree's file is the committed one",
             git(repo, "status", "--porcelain").stdout == "", git(repo, "status", "--porcelain").stdout)
        # a compiler that can: the kept index is stale (it was made for the old text)
        r = run(["sh", "compiler/std/embed.sh", "-c"], repo, VOLE_EMBED_VOLEC=compiler)
        case("std2: embed.sh -c with a compiler that can make it says the kept index is stale",
             r.returncode != 0 and "stale" in r.stderr, r.stdout + r.stderr)
        r = run(["sh", "compiler/std/embed.sh", "-c"], repo, VOLE_EMBED_VOLEC="")
        case("std2: embed.sh -c with none compares the rest", r.returncode == 0, r.stdout + r.stderr)
    finally:
        shutil.rmtree(work)


if not shutil.which("git"):
    print("skip test-stdsrc: no git")
    sys.exit(0)
main()
std2_case()
sys.exit(1 if FAILED else 0)
