#!/usr/bin/env python3
# A model of pm_plan (compiler/src/back/emit/operands.vl), line for line,
# run over random edges (0.30.1, RT-CG-6): the moves of one gap or edge,
# each from a value's location to a phi's, of the widths the back end
# moves (8-byte integers and floats, 16-byte vectors, x86-64's 32-byte
# ones), in registers and in 8-byte spill cells, shared sources included.
# Each plan is checked by simulating its steps cell by cell: every
# destination must hold its value. A plan that dies ("cycle register in
# use", "two values", "waits for no move"), a wrong plan, or more than two
# saves pending at once (plan_break's comment) fails the run. From the
# second review of RT-CG-6, whose model of the previous pm_plan died on 133
# of 200,000 x86-64 edges.
#
# usage: tests/fuzz/pm_model.py [-n EDGES] [-s SEED] [-t aarch64|x86|both]
#   -n EDGES   edges per target (default 100000), half of them dense
#   -s SEED    the first seed (default 1)
#   -t TARGET  aarch64, x86 or both (default)
# Exit status: 0 when every edge is planned right; 1 otherwise.
# Keep it in step with pm_plan, plan_break, plan_save_frees and
# plan_save_progresses.
import random
import sys

SIZE = {'i': 8, 'f': 8, 'v': 16, 'y': 32}
FREG = {'i': False, 'f': True, 'v': True, 'y': True}
SAVED = 1 << 40


class Die(Exception):
    pass


def cells(loc, ty):  # loc_cells
    if loc >= 0:
        return 1
    s = SIZE[ty]
    return (s + 7) // 8 if s > 8 else 1


def overlap(a, ta, b, tb):  # locs_overlap
    if a >= 0 or b >= 0:
        return a == b
    sa, sb = -a - 1, -b - 1
    if sa < sb:
        return sb < sa + cells(a, ta)
    if sb < sa:
        return sa < sb + cells(b, tb)
    return True


def plan(moves, spill_count, spill_vectors, x86, stats):
    n = len(moves)
    dst = [d for d, s, t in moves]
    ty = [t for d, s, t in moves]
    if sum(1 for d, s, t in moves if d != s) <= 1:
        return [m for m in moves if m[0] != m[1]]
    src = [s for d, s, t in moves]
    done = [d == s for d, s, t in moves]

    def reader(src, done, loc, t, exc):  # plan_reader
        for j in range(n):
            if j != exc and not done[j] and overlap(src[j], ty[j], loc, t):
                return j
        return -1

    def frees(c):  # plan_save_frees
        s = src[c]
        src2 = [SAVED if (not done[j] and src[j] == s) else src[j] for j in range(n)]
        done2 = done[:]
        progress = True
        while progress:
            progress = False
            for i in range(n):
                if done2[i]:
                    continue
                if reader(src2, done2, dst[i], ty[i], i) < 0:
                    done2[i] = True
                    progress = True
        return all(done2[j] for j in range(n) if not done[j] and src[j] == s)

    def progresses(c):  # plan_save_progresses
        s = src[c]
        src2 = [SAVED if (not done[j] and src[j] == s) else src[j] for j in range(n)]
        return any(not done[i] and reader(src2, done, dst[i], ty[i], i) < 0 for i in range(n))

    def brk():  # plan_break
        c, cw = -1, -1
        for j in range(n):
            if done[j]:
                continue
            s = src[j]
            first = not any(not done[k] and src[k] == s for k in range(j))
            waited = any(not done[i] and overlap(dst[i], ty[i], s, ty[j]) for i in range(n))
            w = SIZE[ty[j]]
            if first and waited and w > cw and frees(j):
                c, cw = j, w
        if c >= 0:
            return c
        # the widest value whose save makes a move ready
        for j in range(n):
            if done[j]:
                continue
            s = src[j]
            first = not any(not done[k] and src[k] == s for k in range(j))
            waited = any(not done[i] and overlap(dst[i], ty[i], s, ty[j]) for i in range(n))
            w = SIZE[ty[j]]
            if first and waited and w > cw and progresses(j):
                c, cw = j, w
        if c >= 0:
            return c
        m = -1
        for i in range(n):
            if not done[i] and (m < 0 or SIZE[ty[i]] < SIZE[ty[m]]):
                m = i
        c = reader(src, done, dst[m], ty[m], m)
        if c < 0:
            raise Die("waits for no move")
        return c

    steps = []
    while True:
        pending = progress = False
        for i in range(n):
            if done[i]:
                continue
            pending = True
            if reader(src, done, dst[i], ty[i], i) < 0:
                steps.append((dst[i], src[i], ty[i]))
                done[i] = True
                progress = True
        if not pending:
            break
        if progress:
            continue
        c = brk()
        s, t = src[c], ty[c]
        for j in range(n):
            if done[j] or not overlap(src[j], ty[j], s, t):
                continue
            if src[j] != s or FREG[ty[j]] != FREG[t] or SIZE[ty[j]] != SIZE[t]:
                raise Die("two values")
        temp = (47 if x86 else 63) if FREG[t] else (10 if x86 else 17)
        if reader(src, done, temp, t, -1) >= 0:
            temp = -(1 + (spill_count - 4))
            if not spill_vectors or reader(src, done, temp, t, -1) >= 0:
                raise Die("cycle register in use")
        steps.append((temp, s, t))
        for j in range(n):
            if not done[j] and src[j] == s:
                src[j] = temp
        temps = ((47 if x86 else 63), (10 if x86 else 17), -(1 + (spill_count - 4)))
        live = len({src[j] for j in range(n) if not done[j] and src[j] in temps})
        stats['max_pending'] = max(stats.get('max_pending', 0), live)
    return steps


def simulate(moves, steps):
    st = {}

    def read(loc, t):
        if loc >= 0:
            return st.get(('r', loc), (('undef', loc),))
        k = -loc - 1
        return tuple(st.get(('s', k + i), ('undef', k + i)) for i in range(cells(loc, t)))

    def write(loc, t, v):
        if loc >= 0:
            st[('r', loc)] = v
            return
        k = -loc - 1
        if len(v) != cells(loc, t):
            raise Die("a save of another width")
        for i in range(cells(loc, t)):
            st[('s', k + i)] = v[i]
    for d, s, t in moves:
        if s >= 0:
            st[('r', s)] = tuple(('val', s, i) for i in range(SIZE[t] // 8 or 1))
        else:
            for i in range(cells(s, t)):
                st[('s', -s - 1 + i)] = ('val', s, i)
    want = [read(s, t) for d, s, t in moves]
    for d, s, t in steps:
        write(d, t, read(s, t))
    return [k for k, (d, s, t) in enumerate(moves) if read(d, t) != want[k]]


def alloc_loc(r, t, used_regs, used_cells, nslots, x86, prefer_slot):
    if prefer_slot or r.random() < 0.6:
        step = cells(-1, t)
        cands = [k for k in range(0, nslots - step + 1, step)
                 if all((k + i) not in used_cells for i in range(step))]
        if cands:
            k = r.choice(cands)
            for i in range(step):
                used_cells.add(k + i)
            return -(k + 1)
    if FREG[t]:
        pool = [x for x in range(32, 46 if x86 else 62) if x not in used_regs]
    else:
        regs = list(range(0, 10)) + [12, 13, 14, 15] if x86 else range(0, 16)
        pool = [x for x in regs if x not in used_regs]
    if not pool:
        return None
    x = r.choice(pool)
    used_regs.add(x)
    return x


# An edge: the values in disjoint locations, the phis in disjoint
# locations (which may overlap the values'), each phi taking one value
# (a value may go to several). Dense edges: few cells, many wide values.
def edge(r, x86, dense):
    types = ['i', 'f', 'v'] + (['y'] if x86 else [])
    if dense:
        types = ['i', 'f', 'v', 'v'] + (['y', 'y'] if x86 else [])
    nslots = r.choice([4, 8, 8, 12] if dense else [4, 8, 12, 16])
    vals, ur, uc = [], set(), set()
    for _ in range(r.randint(3, 14) if dense else r.randint(2, 10)):
        t = r.choice(types)
        loc = alloc_loc(r, t, ur, uc, nslots, x86, dense and r.random() < 0.8)
        if loc is not None:
            vals.append((loc, t))
    ur2, uc2, moves = set(), set(), []
    for (loc, t) in vals:
        for _ in range(r.choice([1, 1, 2, 3] if dense else [1, 1, 1, 2])):
            p = (0.85 if dense else 0.8)
            d = alloc_loc(r, t, ur2, uc2, nslots, x86, loc < 0 and r.random() < p)
            if d is not None:
                moves.append((d, loc, t))
    r.shuffle(moves)
    vec = any(loc < 0 and t in 'vy' for (d, s, t) in moves for loc in (d, s))
    sc = nslots
    if vec:
        while sc % 4:
            sc += 1
        sc += 4
    return moves, sc, vec


def main():
    n, seed, targets = 100000, 1, ['aarch64', 'x86']
    a = sys.argv[1:]
    while a:
        if a[0] == '-n':
            n = int(a[1])
        elif a[0] == '-s':
            seed = int(a[1])
        elif a[0] == '-t':
            targets = ['aarch64', 'x86'] if a[1] == 'both' else [a[1]]
        else:
            print('usage: tests/fuzz/pm_model.py [-n EDGES] [-s SEED] [-t aarch64|x86|both]',
                  file=sys.stderr)
            sys.exit(2)
        a = a[2:]
    bad = 0
    for tg in targets:
        x86 = tg == 'x86'
        r = random.Random(seed * 2 + x86)
        stats, counts, first = {}, {}, {}
        for it in range(n):
            moves, sc, sv = edge(r, x86, it % 2 == 1)
            try:
                k = 'wrong' if simulate(moves, plan(moves, sc, sv, x86, stats)) else 'ok'
            except Die as e:
                k = 'died: ' + str(e)
            counts[k] = counts.get(k, 0) + 1
            if k != 'ok' and k not in first:
                first[k] = (moves, sc, sv)
        mp = stats.get('max_pending', 0)
        ok = counts.get('ok', 0) == n and mp <= 2
        print('pm_model: %s: %d edges, %d planned right, at most %d saves pending%s' % (
            tg, n, counts.get('ok', 0), mp, '' if ok else ': FAIL'))
        for k, v in first.items():
            print('  %s (%d): %s' % (k, counts[k], v))
        bad += not ok
    sys.exit(1 if bad else 0)


main()
