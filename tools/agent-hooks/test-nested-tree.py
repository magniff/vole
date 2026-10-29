#!/usr/bin/env python3
"""(0.25.3) The hooks' cases pass in a copy of the tree that lies inside
another checkout's target/ (as bootstrap.sh extracts every release's tree
under the main checkout's target/bootstrap/HOST/TAG/tree, where the chain
runs that release's suite) and in one under /private/tmp (or /tmp): the
hooks judge a path by where it is inside the vole tree that holds it
(the nearest directory with compiler/src/main.vl and tools/agent-hooks),
not by a target/ or tmp/ in its absolute path nor by the outer checkout.
Each copy holds the tree's files (git ls-files, the untracked ones too;
in a tree with no .git, its files but target/);
its tools/agent-hooks/test-*.py run there, this file aside. Run by
tests/run.sh (category "hooks").

usage: python3 -I tools/agent-hooks/test-nested-tree.py
"""
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SELF = os.path.basename(__file__)
FAILED = 0


def case(name, ok, detail=""):
    global FAILED
    if ok:
        print(f"pass {name}")
    else:
        FAILED += 1
        print(f"FAIL {name}: {detail}")


def copy_tree(dest):
    if not os.path.exists(os.path.join(ROOT, ".git")) or not shutil.which("git"):
        # (a tree extracted from git, with no .git of its own: its files
        # but target/)
        shutil.copytree(ROOT, dest, symlinks=True,
                        ignore=lambda d, names: ["target"] if os.path.samefile(d, ROOT) else [])
        return
    files = subprocess.run(["git", "ls-files", "-z", "-c", "-o", "--exclude-standard"],
                           cwd=ROOT, capture_output=True).stdout
    tar = subprocess.run(["tar", "--null", "-T", "-", "-cf", "-"], cwd=ROOT, input=files, capture_output=True)
    os.makedirs(dest)
    subprocess.run(["tar", "-xf", "-", "-C", dest], input=tar.stdout, check=True)


def run_in(where, tree, compiler):
    env = dict(os.environ)
    env["VOLE_NESTED_TREE"] = "1"
    if compiler:
        env["VOLE_TEST_COMPILER"] = compiler
    for t in sorted(os.listdir(os.path.join(tree, "tools", "agent-hooks"))):
        if not (t.startswith("test-") and t.endswith(".py")) or t == SELF:
            continue
        r = subprocess.run([sys.executable, "-I", os.path.join("tools", "agent-hooks", t)],
                           cwd=tree, capture_output=True, text=True, env=env, timeout=600)
        out = r.stdout + r.stderr
        fails = [ln for ln in out.splitlines() if ln.startswith("FAIL")]
        case(f"{where}: {t}", r.returncode == 0 and not fails and "Traceback" not in out,
             "\n    ".join((fails or out.splitlines()[-8:])[:12]))


def main():
    if os.environ.get("VOLE_NESTED_TREE") == "1":
        print("pass nested-tree (inside a copy: not again)")
        return
    compiler = os.environ.get("VOLE_TEST_COMPILER") or os.path.join(ROOT, "target", "volec")
    compiler = os.path.abspath(compiler) if os.access(compiler, os.X_OK) else ""
    # inside this checkout, under its target/ (a release's tree in the
    # bootstrap cache is there)
    os.makedirs(os.path.join(ROOT, "target"), exist_ok=True)
    inner = tempfile.mkdtemp(prefix="nested-hooks.", dir=os.path.join(ROOT, "target"))
    # outside any checkout, under /private/tmp (macOS's /tmp), or /tmp
    tmp = "/private/tmp" if os.path.isdir("/private/tmp") else "/tmp"
    outer = tempfile.mkdtemp(prefix="vole-nested-hooks.", dir=tmp)
    try:
        for where, base in (("under target/", inner), ("under " + tmp, outer)):
            tree = os.path.join(base, "x", "tree")
            copy_tree(tree)
            run_in(where, tree, compiler)
    finally:
        shutil.rmtree(inner, ignore_errors=True)
        shutil.rmtree(outer, ignore_errors=True)


main()
sys.exit(1 if FAILED else 0)
