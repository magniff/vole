#!/usr/bin/env python3
"""Every `unsafe` a change adds must carry its justification (AGENTS.md,
"unsafe must be justified"): an `// UNSAFE:` and a `// SAFETY:` comment
in the lines right above it. Until the compiler's own audit (0.25.3,
`volec check`'s unsafe.unjustified) this is the mechanical check, used by
tools/premerge.sh and tools/git-hooks/pre-commit.

usage: tools/unsafe-diff-check.py [--cached | REV]   (default: the work tree vs HEAD)

Looks at the .vl lines the diff adds (git diff -U0), outside tests/
(test cases are about unsafe on purpose) and the generated
compiler/src/front/stdsrc.vl. A line with the word `unsafe` (a block, an
`unsafe fn`, an `unsafe impl`) or an `extern` block needs both comments
within the 12 lines above it in the new file (the comment block may sit
above a `let x = unsafe {` or the item). Prints one line per site,
`FILE:LINE: unsafe without UNSAFE:/SAFETY: comments`, and exits 1 when
there is one. Stdlib only.

A change that moves or narrows existing unsafe (splits a whole-function
block so that new code sits outside it, re-indents it) removes as many
`unsafe` lines in that file as it adds: those are not new unsafe, and are
listed as `moved` (legacy code, the 0.25.4 audit's), not counted. Only the
unjustified additions beyond the removals of the same file are violations.
"""
import re
import subprocess
import sys

WINDOW = 12
WORD = re.compile(r'\bunsafe\b|^\s*(pub\s+)?extern\s+"C"\s*\{')
SKIP = ("tests/", "compiler/src/front/stdsrc.vl")


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


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else None
    if mode == "--cached":
        diff = git("diff", "--cached", "-U0", "--", "*.vl")
    elif mode:
        diff = git("diff", "-U0", mode + "...HEAD", "--", "*.vl")
    else:
        diff = git("diff", "-U0", "HEAD", "--", "*.vl")
    added = {}
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
            if WORD.search(code_part(raw[1:])):
                added.setdefault(path, []).append(line_no)
            line_no += 1
    bad = []
    moved = 0
    for path, lines in sorted(added.items()):
        text = new_text(path, mode).split("\n")
        unjustified = []
        for n in lines:
            above = text[max(0, n - 1 - WINDOW):n - 1] + [text[n - 1] if n - 1 < len(text) else ""]
            joined = "\n".join(above)
            if "UNSAFE:" not in joined or "SAFETY:" not in joined:
                unjustified.append(n)
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
