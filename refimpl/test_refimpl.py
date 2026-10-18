"""Property + golden tests for the Lattice layout reference implementation.
Run: python3 refimpl/test_refimpl.py   (or from this directory). No dependencies."""
import json, random, copy
from pathlib import Path

_ROOT = Path(__file__).resolve().parent

from lattice_layout import *
from goldens import all_cases, SCR, CFG

def rand_tree(rng, depth=0, cnt=[0]):
    if depth > 4 or (depth > 0 and rng.random() < 0.35):
        cnt[0] += 1
        return Window(f"w{cnt[0]}")
    n = rng.randint(2, 4)
    kids = [rand_tree(rng, depth + 1, cnt) for _ in range(n)]
    r = [rng.uniform(0.5, 2) for _ in range(n)]
    return Split(rng.choice("hv"), kids, [x / sum(r) for x in r])

def leaves(n):
    if isinstance(n, Window): return [n]
    if isinstance(n, Split): return [l for c in n.children for l in leaves(c)]
    return []

def test_goldens():
    want = json.load(open(_ROOT / "goldens.json"))
    got = json.loads(json.dumps(all_cases()))
    assert got == want, "golden mismatch"

def test_share_space():
    rng = random.Random(1)
    for _ in range(2000):
        n = rng.randint(1, 6)
        r = [rng.uniform(.01, 1) for _ in range(n)]; s = sum(r); r = [x / s for x in r]
        m = [rng.uniform(0, 300) for _ in range(n)]
        M = [rng.choice([INF, mi + rng.uniform(0, 500)]) for mi in m]
        T = sum(m) + rng.uniform(0, 1500)
        p = share_space(T, r, m, M)
        assert abs(sum(p) - T) < 1e-6
        assert all(pi >= mi - 1e-6 for pi, mi in zip(p, m))
        if sum(M) >= T:
            assert all(pi <= Mi + 1e-6 for pi, Mi in zip(p, M))

def test_gaps_and_shared_edges():
    rng = random.Random(2)
    for t in range(300):
        root = normalize(rand_tree(rng, cnt=[0]), CFG)
        res, ents = solve(root, CFG, SCR)
        live = [p.frame for p in res.values() if p.cls in ("live", "icon")]
        # no overlaps; every tile inside visible inset by outer gaps
        for i, a in enumerate(live):
            assert a[0] >= 10 and a[1] >= 35 and a[0] + a[2] <= 1430 and a[1] + a[3] <= 890, a
            for b in live[i + 1:]:
                ox = min(a[0] + a[2], b[0] + b[2]) - max(a[0], b[0])
                oy = min(a[1] + a[3], b[1] + b[3]) - max(a[1], b[1])
                assert not (ox > 0 and oy > 0), (a, b)
                # neighbours sharing a seam are exactly one inner gap apart
                if oy > 0 and b[0] - (a[0] + a[2]) > 0 and b[0] - (a[0] + a[2]) < 15:
                    assert b[0] - (a[0] + a[2]) == 10, (a, b)

def test_fit_check_every_node():
    rng = random.Random(3)
    for t in range(150):
        root = normalize(rand_tree(rng, cnt=[0]), CFG)
        C = content_edges(SCR, CFG)
        ents = solve_world(root, CFG, (C[2] - C[0], C[3] - C[1]))
        for k, en in ents.items():
            t2 = tile_of(en.world, en.world, C, CFG)
            assert t2 == (10, 35, 1420, 855), (k, t2)

def test_close_undoes_add_and_flatten():
    rng = random.Random(4)
    skipped = [0]
    for t in range(300):
        root = normalize(rand_tree(rng, cnt=[0]), CFG)
        before = solve(copy.deepcopy(root), CFG, SCR)[0]
        ls = leaves(root)
        tgt = rng.choice(ls).id
        edge = rng.choice(["left", "right", "top", "bottom"])
        _, p0, i0 = find(root, tgt)
        if isinstance(p0, Split) and p0.axis == EDGE_AXIS[edge] and \
                p0.ratios[i0] * min(CFG.insert_ratio, 1 - CFG.insert_ratio) < CFG.min_ratio:
            skipped[0] += 1     # halves would fall under min-ratio: the clamp borrows from the row,
            continue            # so the undo is only approximate (documented in ADDENDUM-3 §3)
        r2 = insert_at_edge(copy.deepcopy(root), tgt, edge, Window("new"), CFG)
        r3 = remove(r2, "new", CFG)
        after = solve(r3, CFG, SCR)[0]
        assert {k: v.frame for k, v in before.items()} == {k: v.frame for k, v in after.items()}
    assert skipped[0] < 100, skipped

def test_donor_fallback_keeps_invariants():
    rng = random.Random(5)
    for _ in range(300):
        root = normalize(rand_tree(rng, cnt=[0]), CFG)
        ls = leaves(root)
        tgt = rng.choice(ls).id
        r2 = insert_at_edge(root, tgt, rng.choice(["left", "right", "top", "bottom"]), Window("new"), CFG)
        if rng.random() < 0.5 and len(ls) > 1:
            r2 = remove(r2, tgt, CFG)          # donor gone -> row fallback
        r3 = remove(r2, "new", CFG)
        res, _ = solve(r3, CFG, SCR)
        assert "new" not in res
        def chk(n):
            if isinstance(n, Split):
                assert abs(sum(n.ratios) - 1) < 1e-9 and min(n.ratios) >= CFG.min_ratio - 1e-12
                assert all(not (isinstance(c, Split) and c.axis == n.axis) for c in n.children)
                for c in n.children: chk(c)
        chk(r3)

def test_insert_takes_half_of_target():
    rng = random.Random(6)
    for _ in range(200):
        root = normalize(rand_tree(rng, cnt=[0]), CFG)
        tgt = rng.choice(leaves(root))
        t0, p0, i0 = find(root, tgt.id)
        before = p0.ratios[i0] if p0 else 1.0
        axis = rng.choice("hv")
        edge = rng.choice(["left", "right"] if axis == "h" else ["top", "bottom"])
        r2 = insert_at_edge(copy.deepcopy(root), tgt.id, edge, Window("new"), CFG)
        _, pn, iN = find(r2, "new")
        _, pt, iT = find(r2, tgt.id)
        if pn is pt and p0 is not None and p0.axis == axis and before * 0.5 >= CFG.min_ratio:  # sibling case
            assert abs(pn.ratios[iN] - before * 0.5) < 1e-9 and abs(pt.ratios[iT] - before * 0.5) < 1e-9

def test_straddle_rule():
    root = H(Window("A"), Window("B"))
    for cam, want in (((0.004, 0, 0.504, 1), "live"), ((0.01, 0, 0.51, 1), "clipped")):
        res, _ = solve(copy.deepcopy(root), CFG, SCR, cam)
        assert res["A"].cls == want, (cam, res["A"])
    rng = random.Random(7)
    for _ in range(300):        # floats: nudged fully inside the visible desktop area, size kept
        x0, y0 = rng.uniform(-.3, .9), rng.uniform(-.3, .9)
        fr = (x0, y0, x0 + rng.uniform(.05, .6), y0 + rng.uniform(.05, .6))
        root = Desktop(floats=[FloatWin(Window("F"), fr)])
        res, _ = solve(root, CFG, SCR)
        p = res["F"]
        if p.cls == "float-nudged":
            area = intersect(res["desktop"].frame, SCR.visible)
            r = p.real
            assert r[2:] == p.frame[2:]
            for k in (0, 1):
                if r[k + 2] <= area[k + 2]:
                    assert area[k] <= r[k] and r[k] + r[k + 2] <= area[k] + area[k + 2], (r, area)

def test_seam_only_two_change():
    root = H(Window("a"), V(Window("b"), Window("c")), Window("d"), id="row")
    res, ents = solve(root, CFG, SCR)
    root = seam_resize(root, ents, "row", 1, -120, CFG)
    res2, _ = solve(root, CFG, SCR)
    changed = {k for k in res if res[k].frame != res2[k].frame}
    assert changed == {"b", "c", "d"}  # b/c are one node (the column); a stays put
    assert res2["d"].frame[0] + res2["d"].frame[2] == res["d"].frame[0] + res["d"].frame[2]

if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn(); print("ok", name)
