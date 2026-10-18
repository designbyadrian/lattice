"""Worked examples for ADDENDUM-3 §3. Run: python3 examples.py"""
import copy
from lattice_layout import *
from goldens import SCR, CFG

def show(n):
    if isinstance(n, Window): return n.id
    if isinstance(n, Desktop): return "Desk" + (f"{{{','.join(f.win.id for f in n.floats)}}}" if n.floats else "")
    if isinstance(n, Tabs): return "Tabs(" + ",".join(w.id for w in n.members) + f"; active={n.members[n.active].id})"
    return ("H" if n.axis == "h" else "V") + "[" + ", ".join(f"{show(c)} {r:.4g}" for c, r in zip(n.children, n.ratios)) + "]"

def frames(root, cfg=CFG, **k):
    res, _ = solve(root, cfg, SCR, **k)
    return "; ".join(f"{i}={p.frame}{'' if p.cls in ('live','desktop','float-live') else ' '+p.cls}" for i, p in sorted(res.items()) if p.cls not in ("tab-bar",))

def ex(title, before, op, cfg=CFG, solve_before=True):
    print(f"## {title}")
    print("  before:", show(before), "\n         ", frames(copy.deepcopy(before), cfg) if solve_before else "(not solved: trees are always normalized before solving)")
    after = op(copy.deepcopy(before))
    print("  after: ", show(after), "\n         ", frames(copy.deepcopy(after), cfg))

W = Window
ex("E1 insert C at right edge of B, same axis, default insert-takes-from = 'target' (C takes half of B)", H(W("A"), W("B"), r=[.6, .4]),
   lambda r: insert_at_edge(r, "B", "right", W("C"), CFG))
tc = replace(CFG, insert_takes_from="row")
ex("E2 same, insert-takes-from = 'row' (C takes 1/(n+1) from the whole row)", H(W("A"), W("B"), r=[.6, .4]),
   lambda r: insert_at_edge(r, "B", "right", W("C"), tc), tc)
ex("E3 insert C at bottom edge of B (cross axis -> wrap B)", H(W("A"), W("B"), r=[.6, .4]),
   lambda r: insert_at_edge(r, "B", "bottom", W("C"), CFG))
ex("E4 screen-edge dock D at left (root is H -> sibling at index 0)", H(W("A"), W("B"), r=[.6, .4]),
   lambda r: insert_at_screen_edge(r, "left", W("D"), CFG))
ex("E5 screen-edge dock D at top (root is H -> wrap root)", H(W("A"), W("B"), r=[.6, .4]),
   lambda r: insert_at_screen_edge(r, "top", W("D"), CFG))
def float_into_desk(r):
    res, _ = solve(copy.deepcopy(r), CFG, SCR)
    frac, fr = new_float_frac(res["desktop"].frame, (900, 700), [], CFG)
    r.children[1].floats.append(FloatWin(W("F"), frac))
    frac2, fr2 = new_float_frac(res["desktop"].frame, (400, 300), [], CFG)
    frac3, _ = new_float_frac(res["desktop"].frame, (400, 300), [fr2], CFG)
    r.children[1].floats.append(FloatWin(W("G"), frac3))
    return r
ex("E6 drop into the desktop area: F (900x700 natural) then G (400x300) twice-cascaded", H(W("A"), Desktop()), float_into_desk)
ex("E7 tab C onto centre of B", H(W("A"), W("B")), lambda r: tab_onto(r, "B", W("C"), CFG))
def donor_undo(r):
    r = insert_at_edge(r, "B", "right", W("X"), CFG); print("   (after docking X right of B:", show(r), ")")
    return remove(r, "X", CFG)
ex("E8 close X right after docking it beside B: the donor B gets its space back (exact undo)", H(W("A"), W("B"), W("C"), r=[.5, .2, .3]), donor_undo)
def donor_gone(r):
    r = insert_at_edge(r, "B", "right", W("X"), CFG)
    r = remove(r, "B", CFG); print("   (X docked beside B, then B closed:", show(r), ")")
    return remove(r, "X", CFG)
ex("E8b donor no longer adjacent (B closed first): X's space is shared with the row", H(W("A"), W("B"), W("C"), r=[.5, .2, .3]), donor_gone)
rc = replace(CFG, close_gives_to="row")
ex("E8c remove B, close-gives-to = 'row'", H(W("A"), W("B"), W("C"), r=[.5, .2, .3]), lambda r: remove(r, "B", rc), rc)
nc = replace(CFG, close_gives_to="neighbour")
ex("E9 remove B, close-gives-to = 'neighbour' (the next sibling C takes all)", H(W("A"), W("B"), W("C"), r=[.5, .2, .3]),
   lambda r: remove(r, "B", nc), nc)
ex("E10 normalize: single-child split, same-axis flatten, invalid ratio", H(V(W("A"), r=[1]), H(W("B"), W("C"), r=[1, 3]), W("D"), r=[.3, .5, float('nan')]),
   lambda r: normalize(r, CFG), solve_before=False)
def seam(r):
    _, ents = solve(r, CFG, SCR); return seam_resize(r, ents, "row", 0, 250, CFG)
ex("E11 seam drag +250 pt between A and the column (clamped by the column's min)", H(W("A"), V(W("B"), W("C")), W("D"), r=[.4, .35, .25], id="row"), seam)
def seam2(r):
    _, ents = solve(r, CFG, SCR); return seam_resize(r, ents, "row", 0, 900, CFG)
ex("E12 seam drag +900 pt (clamped: B keeps its 170 pt slot minimum)", H(W("A"), W("B"), r=[.5, .5], id="row"), seam2)
ex("E13 toggle axis of inner column -> becomes H -> flattened into row", H(W("A"), V(W("B"), W("C"), id="col"), r=[.6, .4]),
   lambda r: set_axis(r, "col", "toggle", CFG))
ex("E14 undock B (keeps its frame, clamped into the desktop area)", H(W("A"), W("B"), Desktop(), r=[.4, .3, .3]), lambda r: undock(r, "B", CFG, SCR))
def hs(r):
    r, mem = desktop_area_hide(r, CFG); print("   (hidden:", show(r), ")"); return desktop_area_show(r, mem, CFG)
ex("E15 desktop hide then show (remembered ratio and slot)", H(W("A"), V(W("B"), Desktop()), r=[.6, .4]), hs)
def hs2(r):
    r, mem = desktop_area_hide(r, CFG); r = remove(r, "B", CFG); print("   (hidden, then B closed:", show(r), ")"); return desktop_area_show(r, None, CFG)
ex("E16 desktop re-show when its old parent is gone (re-show ratio 0.33 at right)", H(W("A"), V(W("B"), Desktop(), id="col"), r=[.6, .4]), hs2)
ex("E17 dock-all: floats A,B,C (x order) docked left of the desktop area, which stays", H(W("P"), Desktop(), r=[.5, .5]),
   lambda r: dock_all(r, [W("A"), W("B"), W("C")], CFG))
def unm(r):
    res, _ = solve(copy.deepcopy(r), CFG, SCR); return unmanage_all(r, res, SCR, CFG)
ex("E18 unmanage-all: every docked window floats where it is", H(W("A"), V(W("B"), Desktop()), r=[.6, .4]), unm)
def refl(r):
    res, _ = solve(copy.deepcopy(r), CFG, SCR); old = res["desktop"].frame
    r = insert_at_edge(r, "desktop", "left", W("B"), CFG)
    res2, _ = solve(copy.deepcopy(r), CFG, SCR); d = find(r, "desktop")[0]
    d.floats = reflow_floats(old, res2["desktop"].frame, d.floats, CFG); return r
ex("E19 desktop area shrinks: float keeps its size, centre stays proportional, clamped", H(W("A"), Desktop(floats=[FloatWin(W("F"), (.1, .2, .7, .7))]), r=[.3, .7]), refl)
