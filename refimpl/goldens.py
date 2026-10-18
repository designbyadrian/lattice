"""Golden cases for ADDENDUM-3 §8. Run: python3 goldens.py [--md|--json|--check]"""
import json, sys, copy
from lattice_layout import *

SCR = Screen(visible=(0, 25, 1440, 875), frame=(0, 0, 1440, 900))
CFG = Config()
W = lambda i, **k: Window(i, **k)


def frames(res, ids=None):
    out = {}
    for k, p in res.items():
        if ids and k not in ids:
            continue
        out[k] = {"class": p.cls, "frame": list(p.frame),
                  "real": list(p.real) if p.real else None}
    return out


def case(name, tree_desc, build, cfg=CFG, cam=(0, 0, 1, 1), framed=None, ids=None, note="",
         prev_icons=frozenset(), prev_group_tiles=frozenset()):
    root = build()
    if cam is None:   # frame the named node: camera = its world rect
        C0 = content_edges(SCR, cfg)
        ents0 = solve_world(root, cfg, (C0[2] - C0[0], C0[3] - C0[1]))
        cam = tuple(round(v, 6) for v in ents0[framed].world)
    res, ents = solve(root, cfg, SCR, cam, framed, prev_icons, prev_group_tiles)
    return {"name": name, "tree": tree_desc, "gaps": f"inner {cfg.gap_inner_x}/{cfg.gap_inner_y}, outer {list(cfg.gap_outer)}",
            "camera": list(cam), "note": note, "expect": frames(res, ids)}


def deep(levels=14):
    # alternating halvings: H[W1, V[W2, H[W3, ... H[W9, W10]]]], every ratio .5
    names = [f"W{i}" for i in range(1, levels + 2)]
    node = W(names[-1])
    for i in range(levels - 1, -1, -1):
        mk = H if i % 2 == 0 else V
        node = mk(W(names[i]), node, id=f"s{i+1}")
    return node


def all_cases():
    C = []
    C.append(case("G01 single window", "A", lambda: W("A")))
    C.append(case("G02 two columns", "H[A .5, B .5]", lambda: H(W("A"), W("B"))))
    C.append(case("G03 three columns unequal", "H[A .5, B .25, C .25]",
                  lambda: H(W("A"), W("B"), W("C"), r=[.5, .25, .25])))
    C.append(case("G04 nested column", "H[A .6, V[B .5, C .5] .4]",
                  lambda: H(W("A"), V(W("B"), W("C")), r=[.6, .4])))
    C.append(case("G05 window + desktop with float", "H[A .5, Desktop .5 {F at (.1,.1)-(.7,.6)}]",
                  lambda: H(W("A"), Desktop(floats=[FloatWin(W("F"), (.1, .1, .7, .6))]))))
    C.append(case("G06 tab group + window", "H[Tabs(A,B active=B) .5, C .5]",
                  lambda: H(Tabs("g1", [W("A"), W("B")], 1), W("C"))))
    C.append(case("G07 min width honoured", "H[A .5 (min 900x300), B .5]",
                  lambda: H(W("A", min=(900, 300)), W("B")),
                  cfg=replace(CFG, shrink_past_app_minimum=False)))
    C.append(case("G08 virtual scale at home (shrink off)", "H[A..E equal, each min 400x300]",
                  lambda: H(*[W(x, min=(400, 300)) for x in "ABCDE"], id="row"),
                  cfg=replace(CFG, shrink_past_app_minimum=False)))
    C.append(case("G09 same tree, camera on C", "H[A..E equal, each min 400x300], cam = C's world rect",
                  lambda: H(*[W(x, min=(400, 300)) for x in "ABCDE"], id="row"),
                  cfg=replace(CFG, shrink_past_app_minimum=False), cam=(0.4, 0, 0.6, 1), framed="C"))
    C.append(case("G10 frame nested node (fit check)", "H[A .6, V[B .5, C .5] .4], cam = C's world rect",
                  lambda: H(W("A"), V(W("B"), W("C")), r=[.6, .4]), cam=(0.6, 0.5, 1.0, 1.0), framed="C"))
    C.append(case("G11 odd gaps, per-side outer", "H[A 1/3, B 1/3, C 1/3]",
                  lambda: H(W("A"), W("B"), W("C")),
                  cfg=replace(CFG, gap_inner_x=11, gap_inner_y=11, gap_outer=(6, 4, 8, 6))))
    C.append(case("G12 pinch camera: clipped and parked", "H[A, B, C, D equal], cam x 0.3..0.8",
                  lambda: H(W("A"), W("B"), W("C"), W("D")), cam=(0.3, 0, 0.8, 1)))
    C.append(case("G13 deep nesting: icon tiles", "H[W1, V[W2, H[W3, ... H[W14,W15]]]] all .5 (14 levels)",
                  deep))
    C.append(case("G13b same tree, camera framed on group s10", "as G13, cam = world rect of s10",
                  deep, cam=None, framed="s10"))
    C.append(case("G14 max size centred", "H[A .5 (max 500x400), B .5]",
                  lambda: H(W("A", max=(500, 400)), W("B"))))
    C.append(case("G15 icon tile: space below app minimum", "H[A .8, B .2 (min 400x200)]",
                  lambda: H(W("A"), W("B", min=(400, 200)), r=[.8, .2])))
    # operations ------------------------------------------------------
    def op_insert_row():
        r = H(W("A"), W("B"))
        return insert_at_edge(r, "B", "right", W("C"), CFG)
    C.append(case("G16 insert C right of B (half of the target)", "H[A,B] + C@B.right -> H[A .5, B .25, C .25]", op_insert_row))
    def op_insert_wrap():
        r = H(W("A"), W("B"))
        return insert_at_edge(r, "B", "bottom", W("C"), CFG)
    C.append(case("G17 insert C below B (wrap)", "H[A,B] + C@B.bottom -> H[A, V[B .5, C .5]]", op_insert_wrap))
    def op_close_undo():
        r = H(W("A"), W("B"), r=[.7, .3])
        r = insert_at_edge(r, "A", "right", W("C"), CFG)
        return remove(r, "C", CFG)
    C.append(case("G18 close undoes add (donor)", "H[A .7,B .3] +C@A.right then close C -> H[A .7, B .3]", op_close_undo))
    def op_donor_gone():
        r = H(W("A"), W("B"), W("C"), r=[.5, .2, .3])
        r = insert_at_edge(r, "B", "right", W("X"), CFG)   # H[A .5, B .1, X .1, C .3]
        r = remove(r, "B", CFG)                             # donor gone
        return remove(r, "X", CFG)                          # -> shared with the row
    C.append(case("G18b donor gone: close shares with the row", "H[A .5,B .2,C .3] +X@B.right, close B, close X -> H[A .625, C .375]", op_donor_gone))
    def op_seam():
        r = H(W("A"), W("B"), W("C"), id="row")
        res, ents = solve(r, CFG, SCR)
        return seam_resize(r, ents, "row", 0, 100, CFG)
    C.append(case("G19 seam drag +100 pt between A and B", "H[A,B,C] equal, seam 0 +100", op_seam))
    def op_flatten():
        return normalize(H(W("A"), H(W("B"), W("C"), r=[.25, .75]), r=[.6, .4]), CFG)
    C.append(case("G20 flatten same axis", "H[A .6, H[B .25, C .75] .4] -> H[A .6, B .1, C .3]", op_flatten))
    def op_desktop_cycle():
        r = H(W("A"), W("B"), Desktop(), r=[.4, .3, .3])
        r, mem = desktop_area_hide(r, CFG)
        return desktop_area_show(r, mem, CFG)
    C.append(case("G21 desktop hide then show restores", "H[A .4,B .3,Desk .3] hide->show", op_desktop_cycle))
    def op_first_dock():
        return insert_at_screen_edge(Desktop(), "left", W("A"), CFG)
    C.append(case("G22 first dock on fresh workspace", "Desk + A@screen.left -> H[A .5, Desk .5]", op_first_dock))
    def many(n):
        def b():
            kids = [W(f"W{i}", min=(400, 300)) for i in range(1, n)]
            kids.append(V(W("X", min=(400, 300)), W("Y", min=(400, 300)), id="grp"))
            return H(*kids, id="row")
        return b
    nosq = replace(CFG, shrink_past_app_minimum=False)
    C.append(case("G23 group becomes a group tile below threshold", "H[W1..W13, V[X,Y] id=grp] equal, all min 400x300, shrink off",
                  many(14), cfg=nosq, ids={"grp", "X", "Y", "W1", "W13"}))
    C.append(case("G24 hysteresis: stays a group tile", "H[W1..W12, V[X,Y]] equal, shrink off, grp was a group tile before",
                  many(13), cfg=nosq, ids={"grp", "X", "Y", "W1"}, prev_group_tiles=frozenset({"grp"})))
    C.append(case("G25 hysteresis: no group tile if it wasn't one", "as G24 without prior group tile",
                  many(13), cfg=nosq, ids={"grp", "X", "Y", "W1"}))
    def pinch_settle():
        r = H(W("A"), V(W("B"), W("C"), id="col"), r=[.6, .4], id="root")
        C0 = content_edges(SCR, CFG); home = (C0[2] - C0[0], C0[3] - C0[1])
        ents = solve_world(r, CFG, home)
        # camera after a pinch-in around a pointer over C: 0.5 x 0.6 of the world
        k = settle_target(ents, (0.5, 0.45, 0.95, 0.95), (0.8, 0.8), home)
        return r, k
    r, k = pinch_settle()
    c = case("G26 pinch release settles on best-fitting node", "H[A .6, V[B .5, C .5] .4], pinch cam (.5,.45,.95,.95), pointer (.8,.8) -> settles on '" + k + "', framed",
             lambda: H(W("A"), V(W("B"), W("C"), id="col"), r=[.6, .4], id="root"), cam=None, framed=k)
    C.append(c)
    def reflowed():
        r = H(W("A"), Desktop(floats=[FloatWin(W("F", natural=(600, 400)), (.1, .2, .7, .7))]), r=[.3, .7])
        res, _ = solve(copy.deepcopy(r), CFG, SCR); old = res["desktop"].frame
        r = insert_at_edge(r, "desktop", "left", W("B"), CFG)
        res2, _ = solve(copy.deepcopy(r), CFG, SCR); d = find(r, "desktop")[0]
        d.floats = reflow_floats(old, res2["desktop"].frame, d.floats, CFG)
        return r
    C.append(case("G27 float reflow when the desktop area shrinks", "H[A .3, Desk .7 {F (.1,.2)-(.7,.7)}] + B@Desk.left", reflowed))
    C.append(case("G28 docked window 99.9% on-screen stays live", "H[A,B], camera nudged so A straddles the left edge by 1 pt",
                  lambda: H(W("A"), W("B")), cam=(0.004, 0, 0.504, 1)))
    C.append(case("G29 docked window 98.7% on-screen is clipped", "H[A,B], camera x 0.01..0.51",
                  lambda: H(W("A"), W("B")), cam=(0.01, 0, 0.51, 1)))
    C.append(case("G30 floating window straddling the edge is nudged in", "Desk {F (.6,.2)-(.95,.6)}, camera x 0.3..0.8",
                  lambda: Desktop(floats=[FloatWin(W("F"), (.6, .2, .95, .6))]), cam=(0.3, 0, 0.8, 1)))
    C.append(case("G31 float straddling while the desktop area is mostly off-screen", "H[A .7, Desk .3 {F (.1,.1)-(.9,.6)}], camera x 0..0.75",
                  lambda: H(W("A"), Desktop(floats=[FloatWin(W("F"), (.1, .1, .9, .6))]), r=[.7, .3]), cam=(0, 0, 0.75, 1)))
    return C


if __name__ == "__main__":
    cs = all_cases()
    if "--json" in sys.argv:
        print(json.dumps(cs, indent=1))
    else:
        for c in cs:
            print(f"### {c['name']}  tree={c['tree']}  cam={c['camera']}  gaps={c['gaps']}")
            for k, v in sorted(c["expect"].items()):
                print(f"   {k:8s} {v['class']:11s} frame={tuple(v['frame'])} real={tuple(v['real']) if v['real'] else None}")
