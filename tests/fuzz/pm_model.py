#!/usr/bin/env python3
# A model of the moves' plan (compiler/src/back/emit/operands.vl:
# pm_plan, plan_break, plan_save_frees, plan_save_progresses, plan_width,
# plan_save_cell, reserve_save_cells), line for line, run over random edges
# (0.30.1, RT-CG-6): the moves of one gap or edge, each from a value's
# location to a phi's, of every width the back end moves (8-byte integers,
# spilled as u64; f32, 4 bytes; f64; 16-byte vectors; x86-64's 32-byte
# ones), in registers and in 8-byte spill cells, shared sources included.
#
# Each edge is planned as the compiler plans it: first as
# reserve_save_cells does, with save cells after the slots that have no
# end, then again with exactly the cells that used, as the emitter does.
# The second plan must not die and must be the first's; its steps are
# simulated cell by cell, and every destination must hold its value. Any
# death (no cells, "two values", "waits for no move") or wrong plan fails
# the run. Half the edges are dense: single-class float and vector edges,
# full tilings of the cells by sources and destinations both, from the
# third review's generator. E1 and E2, the third review's edges (a third
# save at once on x86-64; a death on aarch64 with the fixed 4 cells of
# round 3), are planned first.
#
# usage: tests/fuzz/pm_model.py [-n EDGES] [-s SEED] [-t aarch64|x86|both]
#   -n EDGES   edges per target (default 100000), half of them dense
#   -s SEED    the first seed (default 1)
#   -t TARGET  aarch64, x86 or both (default)
# Exit status: 0 when every edge is planned right; 1 otherwise.
import random
import sys

SIZE = {'i': 8, 's': 4, 'f': 8, 'v': 16, 'y': 32}
FREG = {'i': False, 's': True, 'f': True, 'v': True, 'y': True}
SAVED = 1 << 40


class Die(Exception):
    pass


def spill_size(t):  # type_size(spill_type(t)): an integer is spilled as u64
    return SIZE[t] if FREG[t] else 8


def cells(loc, t):  # loc_cells
    if loc >= 0:
        return 1
    s = spill_size(t)
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


class Reserve:  # cx.pm_save_base, pm_save_cells, pm_save_need
    def __init__(self, base, ncells):
        self.base, self.cells, self.need = base, ncells, 0


def plan(moves, x86, rv, stats):
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

    def width(i):  # plan_width
        return spill_size(ty[i])

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
        for rule in (0, 1):
            c, cw = -1, -1
            for j in range(n):
                if done[j]:
                    continue
                s = src[j]
                first = not any(not done[k] and src[k] == s for k in range(j))
                waited = any(not done[i] and overlap(dst[i], ty[i], s, ty[j]) for i in range(n))
                w = width(j)
                if first and waited and w > cw and (frees(j) if rule == 0 else progresses(j)):
                    c, cw = j, w
            if c >= 0:
                return c
        m = -1
        for i in range(n):
            if not done[i] and (m < 0 or width(i) < width(m)):
                m = i
        c = reader(src, done, dst[m], ty[m], m)
        if c < 0:
            raise Die("waits for no move")
        return c

    def save_cell(t):  # plan_save_cell
        k = cells(-1, t)
        off = 0
        while True:
            if rv.cells >= 0 and off + k > rv.cells:
                raise Die("a save has no cells")
            loc = -(1 + rv.base + off)
            if reader(src, done, loc, t, -1) < 0:
                rv.need = max(rv.need, off + k)
                return loc
            off += k

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
            if (src[j] != s or FREG[ty[j]] != FREG[t] or cells(s, ty[j]) != cells(s, t)
                    or spill_size(ty[j]) != spill_size(t)):
                raise Die("two values")
        temp = (47 if x86 else 63) if FREG[t] else (10 if x86 else 17)
        if reader(src, done, temp, t, -1) >= 0:
            temp = save_cell(t)
        steps.append((temp, s, t))
        for j in range(n):
            if not done[j] and src[j] == s:
                src[j] = temp
        live = len({src[j] for j in range(n) if not done[j] and (src[j] in (47, 63, 10, 17)
                                                               or src[j] <= -(1 + rv.base))})
        stats['pending'] = max(stats.get('pending', 0), live)
    return steps


def plan_edge(moves, nslots, x86, stats):
    # reserve_save_cells, then the emitter's plan with that many cells
    base = nslots
    while base % 4:
        base += 1
    # without a wide value in a slot (the code: no vector on the stack in
    # the whole function) no dry run, and no cells: one save at a time
    # must do
    if not any(loc < 0 and cells(loc, t) > 1 for (d, s, t) in moves for loc in (d, s)):
        return plan(moves, x86, Reserve(base, 0), stats)
    dry = Reserve(base, -1)
    first = plan(moves, x86, dry, stats)
    stats['cells'] = max(stats.get('cells', 0), dry.need)
    steps = plan(moves, x86, Reserve(base, dry.need), {})
    if steps != first:
        raise Die("the emitter's plan is not the dry run's")
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
            st[('r', s)] = tuple(('val', s, i) for i in range(cells(-1, t)))
        else:
            for i in range(cells(s, t)):
                st[('s', -s - 1 + i)] = ('val', s, i)
    want = [read(s, t) for d, s, t in moves]
    for d, s, t in steps:
        write(d, t, read(s, t))
    return [k for k, (d, s, t) in enumerate(moves) if read(d, t) != want[k]]


def fregs(x86):
    return list(range(32, 46 if x86 else 62))


def iregs(x86):
    return list(range(0, 10)) + [12, 13, 14, 15] if x86 else list(range(0, 16))


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
    pool = [x for x in (fregs(x86) if FREG[t] else iregs(x86)) if x not in used_regs]
    if not pool:
        return None
    x = r.choice(pool)
    used_regs.add(x)
    return x


# Every cell of 0 .. nslots - 1 taken, aligned, and a few registers.
def tiling(r, nslots, types, x86, nregs):
    out, k = [], 0
    while k < nslots:
        t = r.choice(types)
        c = cells(-1, t)
        if k % c or k + c > nslots:
            t = r.choice([x for x in types if cells(-1, x) == 1])
            c = 1
        out.append((-(k + 1), t))
        k += c
    for _ in range(nregs):
        t = r.choice(types)
        out.append((r.choice((fregs(x86) if FREG[t] else iregs(x86))[:3]), t))
    seen, res = set(), []
    for loc, t in out:
        if loc >= 0 and loc in seen:
            continue
        seen.add(loc)
        res.append((loc, t))
    return res


# An edge: the values in disjoint locations, the phis in disjoint
# locations (which may overlap the values'), each phi taking a value of
# its type (a value may go to several). mode: plain (review 2's), dense
# (few cells, many wide values), tile (sources and destinations tiling
# the cells), vec (floats and vectors, tiled half the time).
def edge(r, x86, mode):
    if mode in ('tile', 'vec'):
        types = ['v', 'v', 'v', 's', 'f', 'i'] + (['y', 'y', 'y'] if x86 else [])
        if mode == 'vec' and r.random() < 0.5:
            types = ['v', 'v', 's', 'f'] + (['y', 'y'] if x86 else [])
    else:
        types = ['i', 'f', 's', 'v'] + (['y'] if x86 else [])
    if mode == 'tile' or (mode == 'vec' and r.random() < 0.5):
        nslots = r.choice([4, 8, 8, 12, 16])
        vals = tiling(r, nslots, types, x86, r.randint(0, 3))
        dsts = tiling(r, nslots, types, x86, r.randint(0, 3))
        bytype = {}
        for loc, t in vals:
            bytype.setdefault(t, []).append(loc)
        moves = [(d, r.choice(bytype[t]), t) for d, t in dsts if t in bytype and r.random() < 0.9]
    else:
        dense = mode in ('dense', 'vec')
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
                p = 0.85 if dense else 0.8
                d = alloc_loc(r, t, ur2, uc2, nslots, x86, loc < 0 and r.random() < p)
                if d is not None:
                    moves.append((d, loc, t))
    r.shuffle(moves)
    return moves, nslots


# The third review's edges: E1 (x86-64, 24 cells of slots) needs three
# saves at once; E2 (aarch64, 16 cells) died with round 3's fixed cells.
E1 = [(-1, -9, 'y'), (-5, -17, 'y'), (-9, -17, 'y'), (-13, -21, 'y'), (-19, -8, 'f'),
      (-20, -15, 'f'), (-22, -4, 's'), (-23, -16, 'f'), (-24, -7, 'f')]
E2 = [(-1, -16, 's'), (-2, 32, 'f'), (-5, 34, 'v'), (-7, -5, 'v'), (-9, -11, 'v'),
      (-11, -16, 's'), (-12, -9, 's'), (-13, -10, 'f'), (-14, -7, 's'), (-15, -1, 'v'),
      (32, -13, 'v')]


def one(moves, nslots, x86, stats):
    try:
        return 'wrong' if simulate(moves, plan_edge(moves, nslots, x86, stats)) else 'ok'
    except Die as e:
        return 'died: ' + str(e)


def main():
    n, seed, targets = 100000, 1, ['aarch64', 'x86']
    a = sys.argv[1:]
    while a:
        if a[0] == '-n' and len(a) > 1:
            n = int(a[1])
        elif a[0] == '-s' and len(a) > 1:
            seed = int(a[1])
        elif a[0] == '-t' and len(a) > 1:
            targets = ['aarch64', 'x86'] if a[1] == 'both' else [a[1]]
        else:
            print('usage: tests/fuzz/pm_model.py [-n EDGES] [-s SEED] [-t aarch64|x86|both]',
                  file=sys.stderr)
            sys.exit(2)
        a = a[2:]
    bad = 0
    for name, moves, nslots, x86 in (('E1', E1, 24, True), ('E2', E2, 16, False)):
        st = {}
        k = one(moves, nslots, x86, st)
        print('pm_model: %s: %s, %d saves pending at most, %d cells' % (
            name, k, st.get('pending', 0), st.get('cells', 0)))
        bad += k != 'ok'
    for tg in targets:
        x86 = tg == 'x86'
        r = random.Random(seed * 2 + x86)
        stats, counts, first, dense = {}, {}, {}, 0
        for it in range(n):
            mode = 'plain' if it % 2 == 0 else r.choice(['dense', 'tile', 'vec'])
            dense += mode != 'plain'
            moves, nslots = edge(r, x86, mode)
            k = one(moves, nslots, x86, stats)
            counts[k] = counts.get(k, 0) + 1
            if k != 'ok' and k not in first:
                first[k] = (moves, nslots)
        ok = counts.get('ok', 0) == n
        print('pm_model: %s: %d edges (%d dense), %d planned right; at most %d saves pending, '
              '%d cells%s' % (tg, n, dense, counts.get('ok', 0), stats.get('pending', 0),
                              stats.get('cells', 0), '' if ok else ': FAIL'))
        for k, v in first.items():
            print('  %s (%d): %s' % (k, counts[k], v))
        bad += not ok
    sys.exit(1 if bad else 0)


main()
