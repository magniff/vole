#!/usr/bin/env python3
"""Compares two logs of the inliner's decisions (VOLE_INLINE_LOG=FILE volec
--no-cache -j1 ...; compiler/src/middle/inline.vl, inline_log_start).

usage: tools/inline-log-diff.py A.log B.log [-n COUNT] [-f CALLER]

A line of a log: caller, callee, callee's size, rule, loop depth, caller's
size, level, program size, budget (tab separated). Prints:
  - each log's totals: decisions, calls inlined, by rule; the level and the
    program size at which the budget was first found spent;
  - by level: calls inlined and refused for the budget, in A and in B;
  - the callees whose number of inlined calls differs most (-n, default 20);
  - the callers whose decisions differ most;
  - with -f CALLER: that caller's decisions that differ, callee by callee.
"""
import sys
from collections import Counter, defaultdict


def read(path):
    rows = []
    for line in open(path, encoding="utf-8", errors="replace"):
        p = line.rstrip("\n").split("\t")
        if len(p) != 9:
            continue
        rows.append((p[0], p[1], int(p[2]), p[3], int(p[4]), int(p[5]), int(p[6]), int(p[7]),
                     int(p[8])))
    return rows


def inlined(rule):
    return not rule.startswith("no:")


def totals(name, rows):
    rules = Counter(r[3] for r in rows)
    n = sum(1 for r in rows if inlined(r[3]))
    print(f"{name}: {len(rows)} decisions, {n} inlined, budget {rows[0][8] if rows else 0}")
    for rule, c in sorted(rules.items(), key=lambda x: (-x[1], x[0])):
        print(f"    {c:8} {rule}")
    spent = [r for r in rows if r[3] == "no:budget"]
    if spent:
        first = min(spent, key=lambda r: r[6])
        print(f"    budget first spent at level {first[6]} (program size {first[7]}),"
              f" {len(spent)} calls refused for it")
    else:
        print("    budget never spent")


def main():
    args = sys.argv[1:]
    count, only = 20, None
    files = []
    i = 0
    while i < len(args):
        if args[i] == "-n":
            count = int(args[i + 1]); i += 2
        elif args[i] == "-f":
            only = args[i + 1]; i += 2
        else:
            files.append(args[i]); i += 1
    if len(files) != 2:
        sys.exit(__doc__)
    a, b = read(files[0]), read(files[1])
    totals("A", a)
    totals("B", b)

    if only is not None:
        for name, rows in (("A", a), ("B", b)):
            print(f"{name}: {only}")
            for r in rows:
                if r[0] == only:
                    print(f"    {r[3]:20} {r[1]} (size {r[2]}, depth {r[4]}, caller {r[5]},"
                          f" level {r[6]}, program {r[7]})")
        return

    print("by level (inlined A / B, refused for the budget A / B):")
    lv = defaultdict(lambda: [0, 0, 0, 0])
    for k, rows in ((0, a), (1, b)):
        for r in rows:
            if inlined(r[3]):
                lv[r[6]][k] += 1
            elif r[3] == "no:budget":
                lv[r[6]][2 + k] += 1
    for level in sorted(lv):
        x = lv[level]
        if x[0] != x[1] or x[2] != x[3]:
            print(f"    level {level:3}: {x[0]:6} / {x[1]:6}   {x[2]:6} / {x[3]:6}")

    ca = Counter(r[1] for r in a if inlined(r[3]))
    cb = Counter(r[1] for r in b if inlined(r[3]))
    d = sorted(((cb[k] - ca[k], k) for k in set(ca) | set(cb) if ca[k] != cb[k]),
               key=lambda x: (-abs(x[0]), x[1]))
    print(f"callees inlined a different number of times: {len(d)} (B - A, callee, A, B):")
    for diff, k in d[:count]:
        print(f"    {diff:+6} {k}  {ca[k]} {cb[k]}")

    da = defaultdict(Counter)
    db = defaultdict(Counter)
    for rows, dd in ((a, da), (b, db)):
        for r in rows:
            dd[r[0]][(r[1], inlined(r[3]))] += 1
    callers = []
    for k in set(da) | set(db):
        diff = sum(((da[k] - db[k]) + (db[k] - da[k])).values())
        if diff:
            ia = sum(c for (g, y), c in da[k].items() if y)
            ib = sum(c for (g, y), c in db[k].items() if y)
            callers.append((diff, k, ia, ib))
    callers.sort(key=lambda x: (-x[0], x[1]))
    print(f"callers whose decisions differ: {len(callers)} of {len(set(da) | set(db))}"
          " (decisions that differ, caller, inlined in A, in B):")
    for diff, k, ia, ib in callers[:count]:
        print(f"    {diff:6} {k}  {ia} {ib}")


main()
