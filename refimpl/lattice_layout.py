"""Lattice layout reference implementation (clean-room, our own code).

Source of truth for the golden numbers in ADDENDUM-3.md. Pure Python 3, no
dependencies. Coordinates are macOS global points, origin top-left, y down.
World rects are stored as EDGES (x0, y0, x1, y1) in the unit square, never as
origin+size, so shared edges stay bit-identical.
"""
from __future__ import annotations
from dataclasses import dataclass, field, replace
import math
import copy
import itertools

TOL = 1e-9
INF = float("inf")
_ids = itertools.count(1)


# ----------------------------------------------------------------- config
@dataclass(frozen=True)
class Config:
    gap_inner_x: int = 10          # [gaps] inner (between left/right neighbours)
    gap_inner_y: int = 10          # [gaps] inner (between top/bottom neighbours)
    gap_outer: tuple = (10, 10, 10, 10)  # left, top, right, bottom
    insert_takes_from: str = "target"   # 'target' (half of the target) | 'row'
    insert_ratio: float = 0.5      # share of the target given to the new node
    insert_ratio_min: float = 0.15
    insert_ratio_max: float = 0.85
    close_gives_to: str = "donor"    # 'donor' | 'row' | 'neighbour'
    min_ratio: float = 0.02
    shrink_past_app_minimum: bool = True
    tile_floor: tuple = (160, 100)
    fallback_min_size: tuple = (240, 160)
    desktop_min_size: tuple = (240, 160)
    desktop_reshow_ratio: float = 0.33
    float_max_fraction: float = 0.7
    float_margin: int = 12
    float_cascade: int = 24
    sole_float_fills_desktop: bool = False
    group_tile_below: int = 100
    group_tile_above: int = 124
    icon_tile_slack: int = 2
    tab_bar_height: int = 28
    tab_bar_ref_size: tuple = (400, 280)
    tab_bar_min_scale: float = 0.35
    tab_bar_hide_below: int = 12
    live_visible_fraction: float = 0.99   # docked: live only if this much is on-screen
    float_nudge_in: bool = True           # floats are slid fully into the visible desktop area


# ------------------------------------------------------------------ nodes
@dataclass
class Window:
    id: str
    min: tuple | None = None       # app/learned/rule minimum (points)
    max: tuple | None = None
    natural: tuple | None = None
    donor: str | None = None       # node whose space this window took when docked


@dataclass
class Tabs:
    id: str
    members: list                  # list[Window]
    active: int = 0


@dataclass
class FloatWin:
    win: Window
    frac: tuple                    # (x0, y0, x1, y1) fractions of desktop area


@dataclass
class Desktop:
    id: str = "desktop"
    floats: list = field(default_factory=list)


@dataclass
class Split:
    axis: str                      # 'h' = side by side (row), 'v' = stacked
    children: list
    ratios: list
    id: str = field(default_factory=lambda: f"s{next(_ids)}")


def H(*kids, r=None, id=None):
    s = Split("h", list(kids), list(r) if r else [1.0 / len(kids)] * len(kids))
    if id: s.id = id
    return s


def V(*kids, r=None, id=None):
    s = Split("v", list(kids), list(r) if r else [1.0 / len(kids)] * len(kids))
    if id: s.id = id
    return s


def nid(n):
    return n.id


# -------------------------------------------------------------- normalize
def _valid(r):
    return isinstance(r, (int, float)) and math.isfinite(r) and r > 0


def _renorm(ratios, floor):
    """Scale to sum 1, then lift anything below `floor` and rescale the rest."""
    n = len(ratios)
    if n == 0:
        return []
    s = sum(ratios)
    r = [x / s for x in ratios]
    if floor * n >= 1:
        return [1.0 / n] * n
    fixed = [False] * n
    for _ in range(n):
        low = [i for i in range(n) if not fixed[i] and r[i] < floor - TOL]
        if not low:
            break
        for i in low:
            fixed[i] = True
            r[i] = floor
        rest = 1 - floor * sum(fixed)
        free_sum = sum(r[i] for i in range(n) if not fixed[i])
        for i in range(n):
            if not fixed[i]:
                r[i] = r[i] * rest / free_sum
    return r


def normalize(node, cfg: Config):
    if isinstance(node, (Window, Desktop)):
        return node
    if isinstance(node, Tabs):
        if not node.members:
            return None
        if len(node.members) == 1:
            return node.members[0]
        node.active = max(0, min(node.active, len(node.members) - 1))
        return node
    kids, rats = [], []
    for c, r in zip(node.children, node.ratios):
        c2 = normalize(c, cfg)
        if c2 is None:
            continue
        kids.append(c2)
        rats.append(r if _valid(r) else cfg.min_ratio)
    if not kids:
        return None
    if len(kids) == 1:
        return kids[0]
    flat_k, flat_r = [], []
    for c, r in zip(kids, rats):
        if isinstance(c, Split) and c.axis == node.axis:
            g = sum(c.ratios)
            for gc, gr in zip(c.children, c.ratios):
                flat_k.append(gc)
                flat_r.append(r * gr / g)
        else:
            flat_k.append(c)
            flat_r.append(r)
    node.children = flat_k
    node.ratios = _renorm(flat_r, cfg.min_ratio)
    return node


# ---------------------------------------------------------- requirements
def live_min(w: Window, cfg):
    """Smallest on-screen size at which the real window is shown live."""
    f = cfg.tile_floor
    if w.min:
        return (max(f[0], w.min[0]), max(f[1], w.min[1]))
    return f


def dist_min(w: Window, cfg):
    """Minimum used when sharing space (see shrink-past-app-minimum)."""
    f = cfg.tile_floor
    if cfg.shrink_past_app_minimum:
        return f
    k = w.min if w.min else cfg.fallback_min_size
    return (max(f[0], k[0]), max(f[1], k[1]))


def requirement(node, cfg):
    gx, gy = cfg.gap_inner_x, cfg.gap_inner_y
    if isinstance(node, Window):
        m = dist_min(node, cfg)
        return (m[0] + gx, m[1] + gy)
    if isinstance(node, Tabs):
        ms = [dist_min(w, cfg) for w in node.members]
        return (max(m[0] for m in ms) + gx,
                max(m[1] for m in ms) + cfg.tab_bar_height + gy)
    if isinstance(node, Desktop):
        return (cfg.desktop_min_size[0] + gx, cfg.desktop_min_size[1] + gy)
    reqs = [requirement(c, cfg) for c in node.children]
    if node.axis == "h":
        return (sum(r[0] for r in reqs), max(r[1] for r in reqs))
    return (max(r[0] for r in reqs), sum(r[1] for r in reqs))


def max_along(node, axis, cfg):
    gx, gy = cfg.gap_inner_x, cfg.gap_inner_y
    if isinstance(node, Window) and node.max:
        return node.max[0] + gx if axis == "h" else node.max[1] + gy
    if isinstance(node, Split) and node.axis == axis:
        return sum(max_along(c, axis, cfg) for c in node.children)
    return INF


# ----------------------------------------------------------- share_space
def share_space(total, ratios, mins, maxes):
    """Share `total` by ratios under per-child [min, max] bounds.

    Finds the single level L such that sum(clamp(L * r_i, min_i, max_i)) == total
    (the sum is continuous and non-decreasing in L, so L is found exactly by
    walking the sorted breakpoints min_i/r_i and max_i/r_i). Caller guarantees
    sum(mins) <= total. If even sum(maxes) < total, every child gets its max and
    the remainder is spread by ratio (frames are then clamped at placement)."""
    n = len(ratios)
    if sum(maxes) <= total + TOL:
        rest = total - sum(maxes)
        s = sum(ratios)
        return [maxes[i] + rest * ratios[i] / s for i in range(n)]
    if sum(mins) >= total - TOL:
        return list(mins)

    def size_at(L):
        return [min(maxes[i], max(mins[i], L * ratios[i])) for i in range(n)]

    pts = sorted({0.0} | {mins[i] / ratios[i] for i in range(n)} |
                 {maxes[i] / ratios[i] for i in range(n) if maxes[i] < INF})
    lo = 0.0
    for L in pts:
        if sum(size_at(L)) >= total - TOL:
            break
        lo = L
    else:
        L = INF
    # on [lo, L] the sum is linear: fixed part + L * (ratio sum of unclamped)
    free = [i for i in range(n)
            if mins[i] <= lo * ratios[i] + TOL and (lo * ratios[i] < maxes[i] - TOL)]
    fixed = sum(size_at(lo)[i] for i in range(n) if i not in free)
    rs = sum(ratios[i] for i in free)
    Lx = (total - fixed) / rs if rs > 0 else lo
    out = size_at(Lx)
    err = total - sum(out)              # absorb float dust into the largest free child
    if free and abs(err) > 0:
        k = max(free, key=lambda i: out[i])
        out[k] += err
    return out


# ---------------------------------------------------------------- solve
@dataclass
class Slot:
    node: object
    world: tuple          # edges in unit square
    vsize: tuple          # size in the node's own (virtual) points
    scale: float          # cumulative virtual scale (1 = real size at home)
    depth: int
    parent: str | None


def solve_world(root, cfg, home_size):
    """World rects for every node. home_size = content size at home camera."""
    out = {}

    def rec(node, e, vs, cum, depth, parent):
        req = requirement(node, cfg)
        s = min(1.0, vs[0] / req[0], vs[1] / req[1])
        if s < 1 - TOL:
            vs = (vs[0] / s, vs[1] / s)
            cum *= s
        out[nid(node)] = Slot(node, e, vs, cum, depth, parent)
        if isinstance(node, Tabs):
            for w in node.members:
                out[w.id] = Slot(w, e, vs, cum, depth + 1, node.id)
        if not isinstance(node, Split):
            return
        ax = 0 if node.axis == "h" else 1
        T = vs[ax]
        mins = [requirement(c, cfg)[ax] for c in node.children]
        maxs = [max_along(c, node.axis, cfg) for c in node.children]
        p = share_space(T, node.ratios, mins, maxs)
        b = [0.0]
        for q in p[:-1]:
            b.append(b[-1] + q / T)
        b.append(1.0)
        x0, y0, x1, y1 = e
        for i, c in enumerate(node.children):
            if ax == 0:
                ce = (x0 + b[i] * (x1 - x0), y0, x0 + b[i + 1] * (x1 - x0), y1)
                cvs = (p[i], vs[1])
            else:
                ce = (x0, y0 + b[i] * (y1 - y0), x1, y0 + b[i + 1] * (y1 - y0))
                cvs = (vs[0], p[i])
            rec(c, ce, cvs, cum, depth + 1, node.id)

    rec(root, (0.0, 0.0, 1.0, 1.0), home_size, 1.0, 0, None)
    return out


def rnd(v):
    return math.floor(v + 0.5)


@dataclass
class Screen:
    visible: tuple        # (x, y, w, h) visible frame of the display
    frame: tuple          # full display frame (for parking)


def content_edges(scr: Screen, cfg):
    vx, vy, vw, vh = scr.visible
    ol, ot, orr, ob = cfg.gap_outer
    hl, hr = cfg.gap_inner_x // 2, cfg.gap_inner_x - cfg.gap_inner_x // 2
    ht, hb = cfg.gap_inner_y // 2, cfg.gap_inner_y - cfg.gap_inner_y // 2
    return (vx + ol - hl, vy + ot - ht, vx + vw - orr + hr, vy + vh - ob + hb)


def to_screen(e, cam, C):
    cx0, cy0, cx1, cy1 = cam
    X0, Y0, X1, Y1 = C
    sx = (X1 - X0) / (cx1 - cx0)
    sy = (Y1 - Y0) / (cy1 - cy0)
    return (X0 + (e[0] - cx0) * sx, Y0 + (e[1] - cy0) * sy,
            X0 + (e[2] - cx0) * sx, Y0 + (e[3] - cy0) * sy)


def tile_of(e, cam, C, cfg):
    s = to_screen(e, cam, C)
    x0, y0, x1, y1 = (rnd(v) for v in s)
    hl, hr = cfg.gap_inner_x // 2, cfg.gap_inner_x - cfg.gap_inner_x // 2
    ht, hb = cfg.gap_inner_y // 2, cfg.gap_inner_y - cfg.gap_inner_y // 2
    tx0, ty0, tx1, ty1 = x0 + hl, y0 + ht, x1 - hr, y1 - hb
    tx1, ty1 = max(tx1, tx0), max(ty1, ty0)
    return (tx0, ty0, tx1 - tx0, ty1 - ty0)


@dataclass
class Placement:
    id: str
    cls: str              # live | icon | parked | clipped | float-nudged | in-group-tile | hidden-tab | tab-bar | group-tile | desktop | float-*
    frame: tuple          # what the user sees (tile / content / tab bar)
    real: tuple | None    # frame written to the real window (None = parked)


def _disjoint(r, vis):
    x, y, w, h = r; vx, vy, vw, vh = vis
    return x + w <= vx or y + h <= vy or x >= vx + vw or y >= vy + vh or w <= 0 or h <= 0


def park_frame(scr, size):
    fx, fy, fw, fh = scr.frame
    return (fx + fw - 1, fy + fh - 1, size[0], size[1])


def solve(root, cfg, scr: Screen, cam=(0.0, 0.0, 1.0, 1.0), framed=None,
          prev_icons=frozenset(), prev_group_tiles=frozenset()):
    """Full pipeline: world -> camera -> gaps -> rounding -> classify -> tab bars."""
    C = content_edges(scr, cfg)
    home = (C[2] - C[0], C[3] - C[1])
    ents = solve_world(root, cfg, home)
    vis = scr.visible
    res = {}
    grouped = set()
    # group tiles (splits only; never the root or the framed node)
    for k, en in ents.items():
        if isinstance(en.node, Split) and en.parent is not None and k != framed:
            t = tile_of(en.world, cam, C, cfg)
            side = min(t[2], t[3])
            limit = cfg.group_tile_above if k in prev_group_tiles else cfg.group_tile_below
            if side < limit and not _disjoint(t, vis):
                grouped.add(k)
    def under_group_tile(k):
        p = ents[k].parent
        while p is not None:
            if p in grouped:
                return p
            p = ents[p].parent
        return None
    for k, en in ents.items():
        n = en.node
        if isinstance(n, Split):
            if k in grouped and under_group_tile(k) is None:
                res[k] = Placement(k, "group-tile", tile_of(en.world, cam, C, cfg), None)
            continue
        if en.parent and isinstance(ents[en.parent].node, Tabs):
            continue  # members handled with their group
        t = tile_of(en.world, cam, C, cfg)
        if under_group_tile(k):
            _emit_in_group_tile(n, t, scr, res)
            continue
        if isinstance(n, Desktop):
            res[k] = Placement(k, "desktop", t, None)
            for f in n.floats:
                _place_float(f, t, cfg, scr, vis, prev_icons, res)
            continue
        if isinstance(n, Tabs):
            _place_tabs(n, t, cfg, scr, vis, prev_icons, res)
            continue
        _place_window(n, t, cfg, scr, vis, prev_icons, res)
    return res, ents


def _emit_in_group_tile(n, t, scr, res):
    ws = n.members if isinstance(n, Tabs) else ([n] if isinstance(n, Window) else [])
    for w in ws:
        res[w.id] = Placement(w.id, "in-group-tile", t, None)


def visible_fraction(r, vis):
    x, y, w, h = r; vx, vy, vw, vh = vis
    if w <= 0 or h <= 0:
        return 0.0
    ix = max(0, min(x + w, vx + vw) - max(x, vx))
    iy = max(0, min(y + h, vy + vh) - max(y, vy))
    return ix * iy / (w * h)


def _classify(w, t, cfg, vis, prev_icons):
    """Docked windows. Wholly off-screen -> parked; partly off-screen beyond the
    tolerance -> clipped (icon tile, real window parked); too small -> icon."""
    f = visible_fraction(t, vis)
    if f <= 0:
        return "parked"
    if f < cfg.live_visible_fraction - TOL:
        return "clipped"
    m = live_min(w, cfg)
    slack = 0 if w.id in prev_icons else cfg.icon_tile_slack
    if t[2] < m[0] - slack or t[3] < m[1] - slack:
        return "icon"
    return "live"


def intersect(a, b):
    x0, y0 = max(a[0], b[0]), max(a[1], b[1])
    x1, y1 = min(a[0] + a[2], b[0] + b[2]), min(a[1] + a[3], b[1] + b[3])
    return (x0, y0, max(0, x1 - x0), max(0, y1 - y0))


def desktop_usable(desk_tile, vis, cfg):
    r = intersect(desk_tile, vis)
    return r[2] >= cfg.desktop_min_size[0] and r[3] >= cfg.desktop_min_size[1]


def nudge_into(r, area):
    """Slide r per axis until it lies inside area; centre it on an axis where it
    is larger than area. Size never changes."""
    out = list(r)
    for k in (0, 1):
        lo, size, alen = area[k], r[k + 2], area[k + 2]
        if size > alen:
            out[k] = lo + (alen - size) // 2
        else:
            out[k] = min(max(r[k], lo), lo + alen - size)
    return tuple(out)


def _real_frame(w, t):
    if w.max and (t[2] > w.max[0] or t[3] > w.max[1]):
        mw, mh = min(t[2], w.max[0]), min(t[3], w.max[1])
        x = t[0] + (t[2] - mw) // 2
        y = t[1] + (t[3] - mh) // 2
        return (x, y, mw, mh)
    return t


def _place_window(w, t, cfg, scr, vis, prev_icons, res):
    c = _classify(w, t, cfg, vis, prev_icons)
    real = _real_frame(w, t) if c == "live" else None
    res[w.id] = Placement(w.id, c, t, real)


def tab_bar_px(t, cfg):
    k = min(1.0, t[2] / cfg.tab_bar_ref_size[0], t[3] / cfg.tab_bar_ref_size[1])
    k = max(cfg.tab_bar_min_scale, k)
    return rnd(cfg.tab_bar_height * k)


def _place_tabs(g, t, cfg, scr, vis, prev_icons, res):
    sh = tab_bar_px(t, cfg)
    content = (t[0], t[1] + sh, t[2], max(0, t[3] - sh))
    act = g.members[g.active]
    if sh < cfg.tab_bar_hide_below:
        res[g.id] = Placement(g.id, "icon", t, None)
        for w in g.members:
            res[w.id] = Placement(w.id, "icon", t, None)
        return
    res[g.id] = Placement(g.id, "tab-bar", (t[0], t[1], t[2], sh), None)
    c = _classify(act, content, cfg, vis, prev_icons)
    res[act.id] = Placement(act.id, c, content, _real_frame(act, content) if c == "live" else None)
    for w in g.members:
        if w is not act:
            res[w.id] = Placement(w.id, "hidden-tab", content,
                                  park_frame(scr, (content[2], content[3])))


def _place_float(f, desk_tile, cfg, scr, vis, prev_icons, res):
    x, y, w, h = desk_tile
    fx0, fy0, fx1, fy1 = f.frac
    e = [rnd(x + fx0 * w), rnd(y + fy0 * h), rnd(x + fx1 * w), rnd(y + fy1 * h)]
    r = (e[0], e[1], e[2] - e[0], e[3] - e[1])
    if visible_fraction(r, vis) <= 0:
        res[f.win.id] = Placement(f.win.id, "float-parked", r, None)
        return
    if not desktop_usable(desk_tile, vis, cfg):
        # the desktop area is (mostly) off-screen: don't drag its floats over the tiles
        c = "live" if visible_fraction(r, vis) >= cfg.live_visible_fraction - TOL else "clipped"
        res[f.win.id] = Placement(f.win.id, "float-" + c, r, r if c == "live" else None)
        return
    real = nudge_into(r, intersect(desk_tile, vis)) if cfg.float_nudge_in else r
    c = "live" if real == r else "nudged"
    res[f.win.id] = Placement(f.win.id, "float-" + c, r, real)


# ------------------------------------------------------------ tree ops
def find(node, target, parent=None, idx=None):
    """Return (node, parent_split_or_tabs, index) for id `target`."""
    if nid(node) == target:
        return node, parent, idx
    if isinstance(node, Tabs):
        for i, w in enumerate(node.members):
            if w.id == target:
                return w, node, i
    if isinstance(node, Split):
        for i, c in enumerate(node.children):
            r = find(c, target, node, i)
            if r:
                return r
    return None


def _replace(root, old_id, new):
    if nid(root) == old_id:
        return new
    if isinstance(root, Split):
        root.children = [_replace(c, old_id, new) for c in root.children]
    return root


EDGE_AXIS = {"left": "h", "right": "h", "top": "v", "bottom": "v"}
EDGE_BEFORE = {"left": True, "top": True, "right": False, "bottom": False}


def clamp(v, lo, hi):
    return max(lo, min(hi, v))


def insert_at_edge(root, target_id, edge, new, cfg):
    """Dock `new` on `edge` of node `target_id`."""
    axis, before = EDGE_AXIS[edge], EDGE_BEFORE[edge]
    t, parent, i = find(root, target_id)
    if isinstance(parent, Tabs):          # docking beside a tab means beside the group
        t, parent, i = find(root, parent.id)
    if isinstance(new, Window):
        new.donor = nid(t)
    rho = clamp(cfg.insert_ratio, cfg.insert_ratio_min, cfg.insert_ratio_max)
    if isinstance(parent, Split) and parent.axis == axis:
        j = i if before else i + 1
        if cfg.insert_takes_from == "row":
            n = len(parent.children)
            parent.ratios = [r * n / (n + 1) for r in parent.ratios]
            parent.ratios.insert(j, 1.0 / (n + 1))
        else:
            rt = parent.ratios[i]
            parent.ratios[i] = rt * (1 - rho)
            parent.ratios.insert(j, rt * rho)
        parent.children.insert(j, new)
    else:
        kids = [new, t] if before else [t, new]
        rats = [rho, 1 - rho] if before else [1 - rho, rho]
        root = _replace(root, nid(t), Split(axis, kids, rats))
    return normalize(root, cfg)


def insert_at_screen_edge(root, edge, new, cfg):
    return insert_at_edge(root, nid(root), edge, new, cfg)


def tab_onto(root, target_id, win, cfg):
    t, parent, i = find(root, target_id)
    if isinstance(parent, Tabs):
        t = parent
    if isinstance(t, Tabs):
        t.members.append(win)
        t.active = len(t.members) - 1
        return root
    g = Tabs(f"g-{t.id}", [t, win], 1)
    return normalize(_replace(root, t.id, g), cfg)


def remove(root, wid, cfg):
    t, parent, i = find(root, wid)
    if parent is None:
        return None
    if isinstance(parent, Tabs):
        parent.members.pop(i)
        if i < parent.active:
            parent.active -= 1
        elif i == parent.active:
            parent.active = min(i, len(parent.members) - 1)  # next tab, else previous
        return normalize(root, cfg)
    r = parent.ratios.pop(i)
    parent.children.pop(i)
    if parent.children and cfg.close_gives_to == "donor":
        # the donor (or the sibling subtree that now contains it) gets the
        # space back, but only if it is still directly adjacent; else 'row'
        donor = getattr(t, "donor", None)
        for k in (i - 1, i):                       # old left / right neighbour
            if 0 <= k < len(parent.children) and donor and find(parent.children[k], donor):
                parent.ratios[k] += r
                break
    elif parent.children and cfg.close_gives_to == "neighbour":
        k = i if i < len(parent.children) else i - 1   # the one after, else before
        parent.ratios[k] += r
    # 'row': proportional renormalisation happens in normalize()
    return normalize(root, cfg)


def seam_resize(root, ents, split_id, i, delta, cfg):
    """Move the seam between children i and i+1 of `split_id` by `delta` points
    (in the split's own points). Only those two change; the rest stay put."""
    sp = find(root, split_id)[0]
    en = ents[split_id]
    ax = 0 if sp.axis == "h" else 1
    T = en.vsize[ax]
    p = [(ents[nid(c)].world[ax + 2] - ents[nid(c)].world[ax]) /
         (en.world[ax + 2] - en.world[ax]) * T for c in sp.children]
    lo = [max(requirement(c, cfg)[ax], cfg.min_ratio * T) for c in sp.children]
    pair = p[i] + p[i + 1]
    a = clamp(p[i] + delta, lo[i], pair - lo[i + 1])
    p[i], p[i + 1] = a, pair - a
    sp.ratios = [q / T for q in p]
    return root


def set_axis(root, split_id, axis, cfg):
    sp = find(root, split_id)[0]
    sp.axis = ("v" if sp.axis == "h" else "h") if axis == "toggle" else axis
    return normalize(root, cfg)


@dataclass
class DesktopMemory:
    ratio: float
    axis: str
    parent: str | None
    index: int
    neighbours: list
    desk: Desktop


def desktop_area_hide(root, cfg):
    d, parent, i = find(root, "desktop")
    if parent is None:
        return root, None      # desktop is the whole workspace: cannot hide
    mem = DesktopMemory(parent.ratios[i], parent.axis, parent.id, i,
                        [nid(c) for c in parent.children if c is not d], d)
    parent.children.pop(i)
    parent.ratios.pop(i)
    return normalize(root, cfg), mem


def desktop_area_show(root, mem, cfg, side="right"):
    """Re-show the desktop area. Order of preference:
    1. its old parent split still exists -> re-insert at the old index with the
       remembered ratio, carved proportionally from the siblings;
    2. the old parent collapsed into one remembered neighbour -> wrap that
       neighbour in a split of the remembered axis, desktop at its old side;
    3. otherwise wrap the root: desktop-reshow-ratio on `side`."""
    d = mem.desk if mem else Desktop()
    if mem and mem.parent and find(root, mem.parent):
        sp = find(root, mem.parent)[0]
        r = mem.ratio
        sp.ratios = [x * (1 - r) for x in sp.ratios]
        j = min(mem.index, len(sp.children))
        sp.children.insert(j, d)
        sp.ratios.insert(j, r)
        return normalize(root, cfg)
    if mem:
        alive = [n for n in mem.neighbours if find(root, n)]
        if len(mem.neighbours) == 1 and alive:
            nb = find(root, alive[0])[0]
            r = mem.ratio
            kids, rats = ([d, nb], [r, 1 - r]) if mem.index == 0 else ([nb, d], [1 - r, r])
            return normalize(_replace(root, nid(nb), Split(mem.axis, kids, rats)), cfg)
    r = cfg.desktop_reshow_ratio
    kids, rats = ([root, d], [1 - r, r]) if side == "right" else ([d, root], [r, 1 - r])
    return normalize(Split("h", kids, rats), cfg)


def undock(root, wid, cfg, scr, cam=(0.0, 0.0, 1.0, 1.0)):
    """Float a docked window where it is: remove it from the tree (remove-share
    applies), then store its last frame relative to the desktop tile, clamped
    inside it with float-padding. Shows the desktop first if hidden (caller)."""
    res, _ = solve(copy.deepcopy(root), cfg, scr, cam)
    w = find(root, wid)[0]
    fb = res[wid].frame
    root = remove(root, wid, cfg)
    res2, _ = solve(copy.deepcopy(root), cfg, scr, cam)
    d = res2["desktop"].frame
    pad = cfg.float_margin
    ww, hh = min(fb[2], d[2] - 2 * pad), min(fb[3], d[3] - 2 * pad)
    x0 = clamp(fb[0], d[0] + pad, d[0] + d[2] - pad - ww)
    y0 = clamp(fb[1], d[1] + pad, d[1] + d[3] - pad - hh)
    find(root, "desktop")[0].floats.append(FloatWin(w, (
        (x0 - d[0]) / d[2], (y0 - d[1]) / d[3], (x0 + ww - d[0]) / d[2], (y0 + hh - d[1]) / d[3])))
    return root


def new_float_frac(desk_tile, size, existing, cfg):
    """Default frame for a new floating window, as fractions of the desktop tile."""
    x, y, w, h = desk_tile
    pad = cfg.float_margin
    cw, ch = cfg.float_max_fraction * w, cfg.float_max_fraction * h
    if size is None:                      # no natural size: 0.55 x 0.55 of the tile
        size = (0.55 * w, 0.55 * h)
    sw, sh = size
    k = min(1.0, cw / sw, ch / sh)
    sw, sh = rnd(sw * k), rnd(sh * k)
    fx, fy = x + (w - sw) / 2, y + (h - sh) / 2
    taken = {(rnd(f[0]), rnd(f[1])) for f in existing}
    while (rnd(fx), rnd(fy)) in taken:
        fx += cfg.float_cascade; fy += cfg.float_cascade
    fx = clamp(fx, x + pad, x + w - pad - sw)
    fy = clamp(fy, y + pad, y + h - pad - sh)
    fx, fy = rnd(fx), rnd(fy)
    return ((fx - x) / w, (fy - y) / h, (fx + sw - x) / w, (fy + sh - y) / h), (fx, fy, sw, sh)


def dock_all(root, floats_in_x_order, cfg):
    """dock-all: dock each floating window immediately left of the desktop area,
    in order of current x (ties: y), always with row sharing, so the row ends up
    with equal shares whatever insert-takes-from says. The desktop area stays."""
    row = replace(cfg, insert_takes_from="row")   # dock-all always shares equally
    for w in floats_in_x_order:
        root = insert_at_edge(root, "desktop", "left", w, row)
    return root


def unmanage_all(root, res, scr, cfg):
    """Float every docked window at its current on-screen frame; the desktop area
    becomes the whole workspace. Frames are clamped inside the new desktop tile
    (no margin, so nothing moves that already fits). Z-order: existing floats
    first, then docked windows in tree order (depth-first, first child first);
    the caller raises the focused window last."""
    old = find(root, "desktop")
    d = Desktop(floats=list(old[0].floats) if old else [])
    tile = solve(Desktop(), cfg, scr)[0]["desktop"].frame
    tx, ty, tw, th = tile
    def leaves(n):
        if isinstance(n, Window): return [n]
        if isinstance(n, Tabs): return list(n.members)
        if isinstance(n, Split): return [l for c in n.children for l in leaves(c)]
        return []
    for w in leaves(root):
        p = res[w.id]
        x, y, ww, hh = p.real if p.real and p.cls == "live" else p.frame
        ww, hh = min(ww, tw), min(hh, th)
        x, y = clamp(x, tx, tx + tw - ww), clamp(y, ty, ty + th - hh)
        d.floats.append(FloatWin(w, ((x - tx) / tw, (y - ty) / th, (x + ww - tx) / tw, (y + hh - ty) / th)))
    return d


def reflow_floats(old_tile, new_tile, floats, cfg):
    """After a layout change resizes the desktop area: each float keeps its point
    size, its centre keeps its relative position, then it is clamped inside the
    new tile with float-margin (shrunk only if it cannot fit)."""
    ox, oy, ow, oh = old_tile
    nx, ny, nw, nh = new_tile
    m = cfg.float_margin
    out = []
    for f in floats:
        x0, y0, x1, y1 = f.frac
        ex0, ey0 = rnd(ox + x0 * ow), rnd(oy + y0 * oh)   # the float as it was shown
        ex1, ey1 = rnd(ox + x1 * ow), rnd(oy + y1 * oh)
        w, h = ex1 - ex0, ey1 - ey0
        cx, cy = ((ex0 + ex1) / 2 - ox) / ow, ((ey0 + ey1) / 2 - oy) / oh
        w, h = min(w, nw - 2 * m), min(h, nh - 2 * m)
        x = clamp(nx + cx * nw - w / 2, nx + m, nx + nw - m - w)
        y = clamp(ny + cy * nh - h / 2, ny + m, ny + nh - m - h)
        x, y, w, h = rnd(x), rnd(y), rnd(w), rnd(h)
        out.append(FloatWin(f.win, ((x - nx) / nw, (y - ny) / nh, (x + w - nx) / nw, (y + h - ny) / nh)))
    return out


def settle_target(ents, cam, pointer, home_size):
    """Pinch release: among nodes whose world rect contains the pointer (world
    coords), pick the one whose area (in home points) differs least from the
    camera's; ties go to the deeper node. The root is always a candidate."""
    Cw, Ch = home_size
    area = lambda e: (e[2] - e[0]) * Cw * (e[3] - e[1]) * Ch
    ca = area(cam)
    best = None
    for k, en in ents.items():
        if isinstance(en.node, Window) and en.parent and isinstance(ents[en.parent].node, Tabs):
            continue
        e = en.world
        if not (e[0] <= pointer[0] <= e[2] and e[1] <= pointer[1] <= e[3]):
            continue
        key = (abs(area(e) - ca), -en.depth)
        if best is None or key < best[0]:
            best = (key, k)
    return best[1]
