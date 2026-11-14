#!/usr/bin/env python3
# (0.27.2.1, docs/design/contracts-effects.md E3.6) Writes the effect
# declarations `volec fix --only effects-std` prints into compiler/std.
#
# std is built into the compiler (compiler/src/front/stdsrc.vl, made
# by compiler/std/embed.sh), so fix prints std's lines as
# `<std>:LINE<TAB>THE LINE TO INSERT`, LINE in the built-in text. This
# reads that text and its file map back from stdsrc.vl, takes the
# union of the declarations each input gives one line (a generic item's
# instances differ from program to program: the list is the union of
# theirs, E3.3a), and inserts each above its item's line in its file,
# unless the line above is already a declaration.
#
# usage: tools/std-effects.py FILE...   (FILEs: fix's printed lines;
# each program's run, e.g. one per tests/run/std_*.vl case)

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STDSRC = os.path.join(ROOT, "compiler/src/front/stdsrc.vl")
STD = os.path.join(ROOT, "compiler/std")
ORDER = ["io", "static", "tls", "thread", "sync", "panic", "diverge", "unsafe"]


def strings_of(fn, text):
    # The text a generated function writes: its buf_str literals.
    m = re.search(r"pub fn %s\(out: i64\) \{\n(.*?)\n\}" % fn, text, re.S)
    out = []
    for lit in re.findall(r'buf_str\(out, c"((?:[^"\\]|\\.)*)"\);', m.group(1)):
        out.append(re.sub(r"\\(.)", lambda x: "\n" if x.group(1) == "n" else x.group(1), lit))
    return "".join(out)


def file_map():
    src = open(STDSRC).read()
    # (bytes: the file map's offsets are wc -c's)
    text = strings_of("std_source", src).encode("utf-8")
    starts = []
    end = len(text)
    for line in strings_of("std_files", src).splitlines():
        parts = line.split(" ", 1)
        if len(parts) == 2:
            starts.append((int(parts[0]), parts[1]))
        elif parts[0].isdigit():
            end = int(parts[0])
    starts.append((end, None))
    # the byte offset of each line's start
    offsets = [0]
    for i, c in enumerate(text):
        if c == 10:
            offsets.append(i + 1)
    return text, starts, offsets


def locate(line, text, starts, offsets):
    # (None past std_source: the built-in tail, rt/gpa.vl and the
    # target's system, which keep no declarations)
    if line - 1 >= len(offsets) or offsets[line - 1] >= starts[-1][0]:
        return None
    at = offsets[line - 1]
    file = None
    for start, name in starts[:-1]:
        if start <= at:
            file = (start, name)
    start, name = file
    return name, text.count(b"\n", start, at) + 1


def parse(decl):
    m = re.match(r"(\s*)#\[effects\((.*)\)\]\s*$", decl)
    indent, body = m.group(1), m.group(2)
    allocs, bits, params = [], set(), []
    depth, cur, items = 0, "", []
    for c in body:
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
        if c == "," and depth == 0:
            items.append(cur.strip())
            cur = ""
        else:
            cur += c
    if cur.strip():
        items.append(cur.strip())
    for it in items:
        if it == "alloc":
            allocs.append("*")
        elif it.startswith("alloc("):
            allocs.extend(a.strip() for a in it[6:-1].split(","))
        elif it in ORDER:
            bits.add(it)
        else:
            params.append(it)
    return indent, allocs, bits, params


def render(indent, allocs, bits, params):
    items = []
    if "*" in allocs:
        items.append("alloc")
    elif allocs:
        items.append("alloc(%s)" % ", ".join(allocs))
    items.extend(b for b in ORDER if b in bits)
    items.extend(params)
    return "%s#[effects(%s)]" % (indent, ", ".join(items))


def main():
    text, starts, offsets = file_map()
    got = {}
    for path in sys.argv[1:]:
        for line in open(path):
            m = re.match(r"<std>:(\d+)\t(.*)$", line.rstrip("\n"))
            if not m:
                continue
            at = int(m.group(1))
            indent, allocs, bits, params = parse(m.group(2))
            if at not in got:
                got[at] = (indent, [], set(), [])
            g = got[at]
            g[1].extend(a for a in allocs if a not in g[1])
            g[2].update(bits)
            g[3].extend(p for p in params if p not in g[3])
    per_file = {}
    for at, g in got.items():
        place = locate(at, text, starts, offsets)
        if place is None:
            continue
        name, line = place
        per_file.setdefault(name, []).append((line, render(*g)))
    made = 0
    for name, edits in sorted(per_file.items()):
        path = os.path.join(STD, name)
        lines = open(path).read().split("\n")
        for line, decl in sorted(edits, reverse=True):
            # (already declared: a declaration among the item's attributes
            # and the comments above it, an unsafe item's `// UNSAFE:` and
            # `// SAFETY:` lines between them; 0.27.5: each run added one
            # more above those)
            k = line - 1
            declared = False
            while k > 0 and lines[k - 1].strip().startswith(("//", "#[")):
                k -= 1
                if lines[k].strip().startswith("#[effects("):
                    declared = True
                    break
            if declared:
                continue
            # (above an unsafe item's `// UNSAFE:` and `// SAFETY:` lines,
            # which stay right above it, and above its other attributes)
            at = line - 1
            k = at
            while k > 0 and lines[k - 1].strip().startswith(("//", "#[")):
                k -= 1
                if lines[k].strip().startswith("// UNSAFE:"):
                    at = k
                    break
            lines.insert(at, decl)
            made += 1
        open(path, "w").write("\n".join(lines))
    print("std-effects: %d declarations in %d files" % (made, len(per_file)))


main()
