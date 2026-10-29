#!/usr/bin/env python3
"""Every `unsafe` a change adds must carry its justification (AGENTS.md,
"unsafe must be justified"): an `// UNSAFE:` and a `// SAFETY:` comment
right above it. Used by tools/premerge.sh and tools/git-hooks/pre-commit.

usage: tools/unsafe-diff-check.py [--cached | REV] [--heuristic]
       (default: the work tree vs HEAD; --cached: the index; REV: REV...HEAD)

Looks at the .vl files the diff changes, outside tests/ (test cases are
about unsafe on purpose), evals/ and the generated
compiler/src/front/stdsrc.vl.

(0.25.3) The sites and their justification are the compiler's: `volec
query unsafe --json FILE...` lists every unsafe block, `unsafe fn` and
extern block of those files with whether the comments right above it hold
both words, the same notion `volec check`'s unsafe.unjustified uses. A
site is new when the diff adds its line. This script stays for what is
git's, not the compiler's: which lines a diff adds, which text a commit
holds, and the moved-sites rule below. The heuristic of 0.25.2 (a line
with the word `unsafe` or an `extern "C" {`, both words within the 12
lines above it) remains for a file the compiler cannot answer for: no
volec with `query unsafe` (one older than 0.25.3), a file whose text in
the work tree is not the one checked (staged with more changes after it,
or REV...HEAD with uncommitted changes), or a program that does not read;
--heuristic forces it.

A change that moves or narrows existing unsafe (splits a whole-function
block so that new code sits outside it, re-indents it) removes as many
`unsafe` lines in that file as it adds: those are not new unsafe, and are
listed as `moved` (legacy code, the 0.25.4 audit's), not counted. Only the
unjustified additions beyond the removals of the same file are violations.

Prints one line per site, `FILE:LINE: unsafe without UNSAFE:/SAFETY:
comments`, and exits 1 when there is one. Stdlib only.
"""
import json
import os
import re
import subprocess
import sys

WINDOW = 12
WORD = re.compile(r'\bunsafe\b|^\s*(pub\s+)?extern\s+"C"\s*\{')
SKIP = ("tests/", "evals/", "compiler/src/front/stdsrc.vl")


def git(*args):
    return subprocess.run(["git"] + list(args), capture_output=True, text=True).stdout


def code_part(line):
    """The line without a // comment or string literals (roughly)."""
    line = re.sub(r'"(\\.|[^"\\])*"', '""', line)
    return line.split("//", 1)[0]


def new_text(path, mode):
    if mode == "--cached":
        return git("show", ":" + path)
    if mode is None:
        try:
            with open(path, encoding="utf-8", errors="replace") as fh:
                return fh.read()
        except OSError:
            return ""
    return git("show", "HEAD:" + path)


def worktree_is_new_text(path, mode):
    """Whether the file in the work tree is the text the diff is about (the
    compiler reads the work tree)."""
    if mode is None:
        return True
    if mode == "--cached":
        return git("diff", "--name-only", "--", path).strip() == ""
    return git("diff", "--name-only", "HEAD", "--", path).strip() == ""


def find_volec():
    """A volec that answers `query unsafe` (0.25.3 on), or None."""
    cands = [os.environ.get("VOLEC", ""), "target/tools/volec", "target/volec"]
    for c in cands:
        if not c or not os.access(c, os.X_OK):
            continue
        r = subprocess.run([c, "query", "unsafe", "--help"], capture_output=True, text=True)
        if r.returncode == 0 and "unjustified" in r.stdout + r.stderr:
            return os.path.abspath(c)
    return None


def program_groups(paths):
    """The files grouped by the program a `query unsafe` reads them with:
    the compiler and std together (the default root reads both), any other
    file on its own (it names its own program)."""
    groups = {}
    for p in paths:
        key = "compiler" if p.startswith(("compiler/src/", "compiler/std/")) else p
        groups.setdefault(key, []).append(p)
    return list(groups.values())


def tool_sites(volec, paths):
    """{path: [(line, justified)]} from the compiler, or None for a group it
    could not answer for."""
    out = {}
    for group in program_groups(paths):
        r = subprocess.run([volec, "query", "unsafe", "--json"] + group,
                           capture_output=True, text=True)
        if r.returncode != 0:
            # (the program does not read: the heuristic for these files)
            continue
        for line in r.stdout.splitlines():
            try:
                d = json.loads(line)
            except ValueError:
                continue
            if isinstance(d, dict) and "file" in d and "justified" in d:
                out.setdefault(d["file"], []).append((d["line"], d["justified"]))
        for p in group:
            out.setdefault(p, [])
    return out


def heuristic_unjustified(path, mode, lines):
    text = new_text(path, mode).split("\n")
    bad = []
    for n in lines:
        above = text[max(0, n - 1 - WINDOW):n - 1] + [text[n - 1] if n - 1 < len(text) else ""]
        joined = "\n".join(above)
        if "UNSAFE:" not in joined or "SAFETY:" not in joined:
            bad.append(n)
    return bad


def main():
    args = [a for a in sys.argv[1:] if a != "--heuristic"]
    force_heuristic = "--heuristic" in sys.argv[1:]
    mode = args[0] if args else None
    if mode == "--cached":
        diff = git("diff", "--cached", "-U0", "--", "*.vl")
    elif mode:
        diff = git("diff", "-U0", mode + "...HEAD", "--", "*.vl")
    else:
        diff = git("diff", "-U0", "HEAD", "--", "*.vl")
    added_word = {}    # path -> lines added with the word (the heuristic's)
    added_lines = {}   # path -> every line added
    removed = {}
    path = None
    line_no = 0
    for raw in diff.splitlines():
        if raw.startswith("--- "):
            p = raw[4:]
            old = p[2:] if p.startswith("a/") else None
            continue
        if raw.startswith("+++ "):
            p = raw[4:]
            path = p[2:] if p.startswith("b/") else old
            continue
        m = re.match(r"@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@", raw)
        if m:
            line_no = int(m.group(1))
            continue
        if path is None or path.startswith(SKIP):
            continue
        if raw.startswith("-") and not raw.startswith("---"):
            if WORD.search(code_part(raw[1:])):
                removed[path] = removed.get(path, 0) + 1
            continue
        if raw.startswith("+") and not raw.startswith("+++"):
            added_lines.setdefault(path, set()).add(line_no)
            if WORD.search(code_part(raw[1:])):
                added_word.setdefault(path, []).append(line_no)
            line_no += 1
    # The compiler's answer for the files it can read as the diff has them.
    volec = None if force_heuristic else find_volec()
    by_tool = {}
    if volec:
        readable = [p for p in sorted(added_lines)
                    if os.path.exists(p) and worktree_is_new_text(p, mode)]
        if readable:
            by_tool = tool_sites(volec, readable)
    bad = []
    moved = 0
    heuristic_files = 0
    for path in sorted(set(added_lines) | set(added_word)):
        if path in by_tool:
            new = sorted(n for n, ok in by_tool[path] if n in added_lines.get(path, ()))
            unjustified = [n for n in new
                           if not dict((ln, ok) for ln, ok in by_tool[path]).get(n, False)]
        else:
            if path not in added_word:
                continue
            heuristic_files += 1
            unjustified = heuristic_unjustified(path, mode, added_word[path])
        excess = len(unjustified) - removed.get(path, 0)
        if excess <= 0:
            moved += len(unjustified)
            continue
        for n in unjustified:
            bad.append("%s:%d: unsafe without UNSAFE:/SAFETY: comments" % (path, n))
        if excess < len(unjustified):
            bad.append("%s: %d new unjustified (of %d listed: the file also removed %d unsafe lines)"
                       % (path, excess, len(unjustified), removed.get(path, 0)))
    for b in bad:
        print(b)
    if heuristic_files:
        why = ("--heuristic" if force_heuristic else
               "no volec with `query unsafe`" if not volec else
               "text not in the work tree, or the program does not read")
        print("unsafe-diff-check: %d file%s by the text heuristic (%s)"
              % (heuristic_files, "" if heuristic_files == 1 else "s", why))
    if moved:
        print("unsafe-diff-check: %d moved/narrowed legacy site%s (as many removed in the same file): not new"
              % (moved, "" if moved == 1 else "s"))
    if bad:
        print("unsafe-diff-check: %d unjustified site%s (AGENTS.md: why it cannot be safe, why it is sound)"
              % (len(bad), "" if len(bad) == 1 else "s"))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
