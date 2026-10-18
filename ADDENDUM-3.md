# ADDENDUM-3: Lattice layout algorithm (exact, agent-ready specification)

Status: approved by Adrian, 2026-10-18. Reference implementation: `refimpl/` (Python, our own code). It is the **source of truth for every number in §3 and §8**; run `python3 refimpl/test_refimpl.py`.

**Precedence.** This addendum **supersedes PLAN §4–5 and any earlier addendum text (ADDENDUM A3/A4, ADDENDUM-2 B2/B3/B5/B6/B8/B9) on layout geometry**: coordinates, ratios, insertion and removal shares, normalisation, gaps, rounding, minimum sizes, icon/group tiles, parking, tab bar geometry and desktop-area sizing. Behaviour, commands, bindings and UI in those documents still apply where this file is silent. Where it changes an earlier acceptance test, it says so (search for "Changes").

## 0. Clean-room rules (read first)

1. **Describe behaviour only.** This file describes what Lattice does, in our own words. It reproduces no TrellisWM code, no disassembled logic, no site JavaScript and no TrellisWM internal names (types, functions, fields, settings keys).
2. **Our own constants.** Every tunable has a Lattice value chosen by us. Some are near observed TrellisWM behaviour, and none needs to equal it. Where a value equals what was observed, it's because it is the natural choice (for example 0.5 for "split in half"), and the text says so.
3. **Our own names.** Model types, functions, config keys and on-screen terms are Lattice's. In particular:
   - The small-window placeholder is an **icon tile**. It is ADDENDUM-2 B8's "cover", renamed.
   - A collapsed region is a **group tile**.
   - The tab strip is the **tab bar**.
   - Changes PLAN §4's model type names: `Split`, `WindowLeaf`, `TabGroup`, `DesktopArea`, `FloatWin` replace `SplitNode`/`PanelNode`/`TabNode`/`.desktop`. PLAN's `SplitNode` and `PanelNode` coincide with internal type names in the reference binary, so they are retired.
4. **Provenance markers.** Each rule is tagged:
   - **[Observed]**: behaviour seen in TrellisWM's binary (symbols, defaults file, user-facing settings text) or its public site. It is cited briefly, as Bin-text (a settings string), Bin-default (the shipped defaults file), Bin-static (a structure or constant inferred from static analysis, with medium confidence unless stated) or Site (site text or simulator).
   - **[Lattice choice]**: our decision, overridable by Adrian.
   - **[Unknown in reference]**: the reference didn't reveal it, so we chose.
5. Licence/terms: the TrellisWM binary and site JS are proprietary. Use them only as evidence of behaviour. Never paste, port or paraphrase their code into Lattice.

## 0a. Terms and model

- **Display frame** `D`: the full display rect, in global points (origin top-left, y down; the AX convention).
- **Visible frame** `V`: `D` minus the menu bar and Dock (from `NSScreen.visibleFrame`, flipped to top-left coordinates).
- **Points, not pixels.** All geometry is in points. Real windows get integral points.
- **Tree** (per workspace and display) [Lattice choice; supersedes PLAN §4 names]:
  - `Split(axis, children[], ratios[])`: `axis = h` lays children side by side (left to right), `axis = v` stacks them (top to bottom). `ratios` are stored preferences; they sum to 1 and each is ≥ `min-ratio`.
  - `WindowLeaf(id, appMin?, appMax?, natural?, donor?)`:
    - `appMin` comes from a `min-size` rule or is learned (§4).
    - `donor` is the id of the node whose space it took when it was docked (used by `close-gives-to = 'donor'`, O6).
  - `TabGroup(id, members[WindowLeaf], active)`.
  - `DesktopArea(floats[FloatWin])`: exactly one per workspace, possibly hidden (§7).
  - `FloatWin(window, frac)`: the frame as edge fractions `(x0, y0, x1, y1)` of the desktop area's **tile** (§2 S6).
- **Suspended windows** (minimised, full-screen, app hidden; PLAN §4) keep their leaf. `solve` runs on a copy with suspended leaves removed and then normalised, so they take no space and get their slot back on resume. [Lattice choice]

## 1. Coordinate model

**1.1 World.** [Lattice choice; Observed: Bin-static, the layout works in a unit rectangle]
- Each workspace has a **world**: the unit square `[0,1]²`.
- Every node has a **world rect**, stored as **edges** `(x0, y0, x1, y1)`, never as origin + size, so a shared edge is the same floating-point value on both sides.
- The root's world rect is the unit square.
- A split divides its own world rect along its axis at cumulative boundaries `b0 = 0 < b1 < … < bn = 1`. These are the **effective fractions** from the solve (§2 S4), not the stored ratios. Child `i` spans `[b_i, b_{i+1}]` of the parent along the axis and the parent's full extent across it. `b_n` is set to exactly 1.

**1.2 Content rect and home points.** [Lattice choice]
- With inner gaps `gx` (between left/right neighbours) and `gy` (between top/bottom neighbours), let `hl = floor(gx/2)`, `hr = ceil(gx/2)`, `ht = floor(gy/2)`, `hb = ceil(gy/2)`.
- With outer gaps `(oL, oT, oR, oB)`, the **content rect** `C` is:
  ```
  C.x0 = V.x0 + oL − hl     C.x1 = V.x1 − oR + hr
  C.y0 = V.y0 + oT − ht     C.y1 = V.y1 − oB + hb
  ```
  It is the visible frame grown back by half an inner gap, so that insetting every tile by half an inner gap (§2 S6) leaves exactly `outer` at the display edges and exactly `inner` between neighbours.
- **Home size** `(Cw, Ch) = (C.x1 − C.x0, C.y1 − C.y0)`. Example: a 1440×900 display with a 25 pt menu bar, Dock hidden and the default gaps 10/10 gives `V = (0, 25, 1440, 875)`, `C = (5,30)–(1435,895)` and a home size of 1430×865.
- All minimum sizes are compared in **home points**: one world unit = `Cw` points across and `Ch` points down at the home camera.

**1.3 Camera.** [Observed: Site sim and Bin-static, the camera is a rect in arrangement coordinates; the mapping is ours]
- The camera is a world rect `cam = (cx0, cy0, cx1, cy1)` with `0 ≤ cx0 < cx1 ≤ 1` and the same for y.
- The **home camera** is the unit square, which is also the furthest zoom-out ("everything"). The camera is never larger than the world.
- World → screen, per axis independently:
  ```
  X(x) = C.x0 + (x − cx0) · Cw / (cx1 − cx0)
  Y(y) = C.y0 + (y − cy0) · Ch / (cy1 − cy0)
  ```
- **Framing a node** (`zoom window`, `zoom desktop`, double-click, step in or out, pinch settle) sets `cam` to the node's world rect exactly. The node then fills `C`, and its tile is exactly `V` inset by the outer gaps. That is ADDENDUM A4's fit check, verified for every node of random trees by `test_fit_check_every_node`. The mapping may scale x and y differently. That is intended: a framed slot always fills the display.
- **Aspect-fit cameras** (frame-rect B4, and the continuous part of a pinch) keep equal zoom on both axes: `zoom = 1/(cx1 − cx0) = 1/(cy1 − cy0)`.
  - For frame-rect of a world rect `R`: `z = min(1/R.w, 1/R.h)`, the camera has side `1/z` and is centred on `R`. It is then shifted to lie inside the unit square, and becomes the home camera if `1/z ≥ 1`. The rectangle's longer side (in screen terms) then spans `C`, which is B4's AC.
  - A pinch scales the camera about the pointer by the gesture's factor with the same clamps. The minimum camera side is `1e-6` world units.

**1.4 Virtual canvas: how deep nesting stays usable (the fractal mechanism).** [Observed: Bin-static, the layout compares available space with summed child minimums and lays a group out on an enlarged virtual canvas with a recorded scale (medium confidence). The rule below is ours.]
- Every node has a **requirement** `req(n) = (w, h)` in points (§2 S2). The solve gives each node an **allocated size** `a(n)` in its own points (the root gets `(Cw, Ch)`).
- If `a.w < req.w` or `a.h < req.h`, the node gets a **virtual scale**:
  - `s = min(a.w/req.w, a.h/req.h)`, so `s < 1`;
  - it lays out its children inside a **virtual canvas** of `a/s` points;
  - its world rect does not change;
  - the **cumulative scale** `σ(n)` is the product of every `s` on the path from the root (1 if none).
- Inside the virtual canvas every requirement fits, so every leaf gets at least its minimum **in virtual points**.
- On screen, a leaf's size is roughly its virtual size × `σ` × camera zoom. Deep or crowded regions therefore appear small at home (icon tiles, §5), and zooming in by about `1/σ` brings their windows back to at least their minimum, as live real windows.
- G08/G09 show this: five windows needing 400 pt each in a 1430 pt row are icon tiles at home, and framing one makes it live at full size. G13/G13b show it with 14 levels of nesting.

## 2. Solve pipeline

`solve(tree, display, gaps, camera, framedNode?, previousIconTiles, previousGroupTiles) → [id: Placement]`. It is deterministic and pure; no AX calls. The steps are S0–S9 below. Each `Placement` has a class, the frame the user sees, and the frame written to the real window (or "park").

**S0 Prepare.** Copy the tree, remove suspended leaves and normalise it (S1).

**S1 Normalise** (also run after every operation). [Lattice choice; Observed: Bin-static, invalid ratios are repaired and nested same-axis splits are folded into the parent with multiplied ratios]
```
normalize(node):
  window leaf, desktop area        -> unchanged
  tab group: 0 members -> delete; 1 member -> that window leaf; clamp active index
  split:
    children <- normalize each child, dropping deleted ones (and their ratios)
    any ratio that is NaN, infinite or <= 0 -> min-ratio
    0 children -> delete;  1 child -> replace the split by that child
    for each child that is a split with the SAME axis as this split:
        splice its children in at its position, each with ratio
        (child's ratio) x (grandchild ratio) / (sum of the child's ratios)
    rescale ratios to sum 1; then repeatedly lift any ratio below min-ratio
    to min-ratio and rescale the others to fill the rest (at most n rounds;
    if n x min-ratio >= 1 use equal ratios)
```
- After normalisation no split has a same-axis child, no split has fewer than two children, and every ratio is in `[min-ratio, 1]` with a sum of 1.
- **Hierarchy stepping uses the normalised tree.** `zoom in`/`zoom out`, B7's one-level-per-command, `pan` and the menu "levels" all walk the tree after normalisation, which is the nesting the user sees. A row inside a row looks like one row, so it is one level. [Lattice choice]

**S2 Measure requirements, bottom-up.** [Lattice choice]
- Leaf: `req = distMin + (gx, gy)`. A tile is inset by half a gap on each side, so its slot needs the gap too.
  - `distMin = tile-floor` when `shrink-past-app-minimum = true` (default);
  - otherwise `max(tile-floor, appMin or fallback-min-size)` per axis.
- Tab group: width `max(member distMin.w) + gx`; height `max(member distMin.h) + tab-bar-height + gy`.
- Desktop area: `desktop-min-size + (gx, gy)`.
- Split along its axis: the sum of the children's requirements; across it, their maximum.
- Max along an axis: a leaf with `appMax` has `appMax + gap`; a same-axis split sums its children's maxes; everything else is unbounded.

**S3 Virtual scale.** Top-down: give the root `(Cw, Ch)` and apply §1.4 at every node before laying out its children.

**S4 Share space within each split** (exact algorithm). [Lattice choice; Observed: Bin-static, there is a space-sharing step that takes minimums into account]
- Inputs: the split's extent along its axis `T` (in its own, possibly virtual, points), the ratios `r_i`, and each child's requirement `m_i` and max `M_i` along the axis. After S3, `Σm ≤ T` always holds.
- Find the single level `L ≥ 0` with `Σ clamp(L·r_i, m_i, M_i) = T`.
- The left side is continuous and non-decreasing in `L`, so `L` is found exactly:
  - sort the breakpoints `{m_i/r_i} ∪ {M_i/r_i}`;
  - walk them to the first one where the sum reaches `T`;
  - on that segment the sum is `fixed + L·(Σ r of unclamped children)`, so solve for `L` directly.
- Size `p_i = clamp(L·r_i, m_i, M_i)`. Any floating-point remainder (≤ 1e-9) goes to the largest unclamped child.
- Special cases:
  - If `ΣM < T`, every child gets its max plus the remainder in proportion to its ratio, and the frame is clamped at placement (S7).
  - If `Σm = T` (within 1e-9), every child gets its minimum.
- Tolerance: 1e-9 throughout. Effective fractions: `f_i = p_i / T`, and boundaries are the cumulative sums (§1.1). Children get `(p_i, cross extent)` as their allocated size.
- Pseudocode:
  ```
  share(T, r, m, M):
    if sum(M) <= T: return [M_i + (T - sum M) * r_i / sum r]
    if sum(m) >= T: return m
    size(L) = [clamp(L*r_i, m_i, M_i)]
    for L in sorted({0} ∪ {m_i/r_i} ∪ {M_i/r_i finite}):
        if sum(size(L)) >= T: break; lo = L
    free = children unclamped just above lo
    L* = (T - sum of clamped sizes at lo) / sum(r_i for free)
    return size(L*)  (+ float dust to the largest free child)
  ```
- Example (G07): `H[A .5 (min 900), B .5]` with the shrink option off. A's slot is 910 pt (900 + gap), B gets the remaining 520, and the tiles are 900 and 510 wide.

**S5 Camera transform.** Map every node's world edges through §1.3, giving the **slot edges** in screen points (floating point).

**S6 Pixel rounding, then gaps.** [Lattice choice; Observed: Bin-static, rects are rounded by rounding their edges; Site sim, the gap is applied on screen after the camera]
- Round each slot **edge** with `round(v) = floor(v + 0.5)`. Never round widths.
- Because neighbours share the identical edge value, they share the identical rounded edge: no 1-pt gaps or overlaps, whatever the zoom.
- **Tile** = the rounded slot inset by `hl` (left), `ht` (top), `hr` (right) and `hb` (bottom). If the result has a negative width or height, it is clamped to 0.
- Result: neighbours are exactly `gx` (or `gy`) apart. Edges on the display boundary are exactly `outer` from `V` at the home camera or when framed. Gaps stay constant on screen at every zoom, because they are applied after the camera.
- Gaps must be integers. Non-integer config values are rounded at load, with a warning.
- `test_gaps_and_shared_edges` checks no overlaps and exact inner gaps on 300 random trees. G11 shows odd gaps (inner 11, outer 6/4/8/6).

**S7 Classify each window** (at rest). [Lattice choice; Observed: Site/Bin-text, too-small windows show their app's colour and icon and become real again when they fit; out-of-view windows are parked]
In this order, using the tile (for a tab group, the content rect below its tab bar):
1. A descendant of a **group tile** (§5.3) → `in-group-tile`. The real window is parked.
2. The tile doesn't intersect `V` (or has zero size) → `parked`.
3. Less than `live-visible-fraction` (default 0.99) of the tile's area lies inside `V` → `clipped`. It is drawn as an icon tile (or its still, §5), clipped to the display, and the real window is parked. A sliver over the edge (≤ 1 % of the area, G28) stays `live` and is left straddling; anything more is clipped (G29). [Unknown in reference for the exact partial-visibility rule; closest evidence: Bin-static, a per-window shown-on-screen flag, a parking routine, a hidden setting to park out-of-view windows at a small size (default off) and covers for windows that can't be shown live. Lattice choice for the threshold. See §2a.]
4. The tile is smaller than `liveMin` on either axis, with hysteresis → `icon`. The real window is parked at its learned minimum (B8).
   - `liveMin = max(tile-floor, appMin)` per axis, or `tile-floor` if there is no `appMin` yet.
   - Hysteresis: enter when the tile is below `liveMin − icon-tile-slack`; a window that was an icon tile leaves only once the tile is ≥ `liveMin`.
5. Otherwise → `live`. The real frame is the tile, except that a window with `appMax` smaller than the tile gets `min(tile, appMax)`, centred in the tile (G14).

**S8 Tab bar carve-out.** See §6. The tab bar is the top `tabBarPx` of the group's tile; the content rect is the rest. The active member is classified on the content rect (S7). The other members are `hidden-tab`, parked at the content size.

**S9 Floats.** For each `FloatWin`, the frame is the rounded edges of `desktopTile.origin + frac × desktopTile.size`, with no gap inset. Floats therefore move and scale with the camera, as in ADDENDUM-2 B2. Classification (§2a):
1. The frame doesn't intersect `V` → `float-parked`.
2. The desktop area is **not usable** on screen (the part of its tile inside `V` is smaller than `desktop-min-size` on either axis): a float that is ≥ `live-visible-fraction` on screen is `float-live`, otherwise `float-clipped` (icon tile, real window parked), so floats of a mostly off-screen desktop area are never dragged over the tiles (G31).
3. Otherwise, with `float-nudge-in = true` (default), the **real** frame is the frame slid per axis until it lies inside `U = desktopTile ∩ V`, centred on an axis where it is larger than `U`; its size never changes. If that moved it the class is `float-nudged`, else `float-live` (G30). The stored `frac` is not changed: the nudge is a placement, not an edit, so the float returns to its place when the camera comes back. With `float-nudge-in = false` the real frame is the frame (it may straddle).
4. `float-icon` applies as in S7 rule 4.

**§2a Windows straddling the display edge at rest.** [Unknown in reference, closest-evidenced behaviour; summary of what the static evidence shows]
- *Evidence (Bin-static, Bin-text, Bin-default; no execution):* each placement carries a shown-on-screen flag and a fits-live flag; there is a parking routine taking a size and an optional minimum; a setting to park out-of-view windows at a small size exists, defaults to off and is hidden in release settings; a diagnostic message reports windows that should be parked; and in the placement step, for one class of window, the real frame is clamped per axis into the visible area and centred when it is larger than it, after being raised to at least its minimum. The flag that selects that class could not be resolved statically; it is most plausibly the floating flag, because docked windows already have covers and parking.
- *Reading (confidence: high that wholly out-of-view windows are parked; medium that some windows are slid fully into the visible area rather than left straddling; low on which class and on any partial-visibility threshold):* the reference does not appear to leave real windows half off-screen at rest.
- *Lattice behaviour:* docked windows that are more than a sliver off-screen become `clipped` (S7 rule 3); floats are nudged in (S9). Values and the threshold are ours.

## 3. Operations

Every operation is pure: it returns a new tree, then normalises it (S1) and re-solves. The worked examples E1–E19 (with E8b, E8c) at the end of this section are refimpl output on a 1440×900 display with `V = (0,25,1440,875)`, gaps 10/10 and the home camera. Frames are `(x, y, w, h)`. Tree notation: `H[...]`/`V[...]` with each child's ratio after it.

**O1 Insert at an edge of a node** (drop on a node's edge band; `dock <dir>`). [Observed: Site "Dock them, and everything makes room"; Bin-static, edge docking inserts beside the target with a default share of one half, clamped to a band around it. The rules below are ours.]
- Let `axis` = `h` for the left/right edges and `v` for top/bottom. `before` is true for left/top.
- The target is the node under the pointer. A member of a tab group means the group.
- **Sibling case:** the target's parent split has the same `axis`. Insert the new window next to the target (before or after).
  - `insert-takes-from = 'target'` (default, Adrian's decision): the new child gets `ρ × r_target` and the target keeps `(1 − ρ) × r_target`; no other sibling moves (E1, G16).
  - `insert-takes-from = 'row'`: the new child gets `1/(n+1)`, where `n` is the number of existing siblings, and every existing ratio is multiplied by `n/(n+1)` (E2).
- **Wrap case:** otherwise, replace the target with `Split(axis, [new, target] or [target, new])`, with the new window's ratio `ρ` (E3).
- `ρ = clamp(insert-ratio, 0.15, 0.85)`. The default `insert-ratio = 0.5` is a natural default (an even split).
- The new leaf records `donor = target id` (the group's id for a tab-group target, the target subtree's id in the wrap case).
- If `ρ × r_target` or `(1 − ρ) × r_target` is below `min-ratio`, the S1 clamp lifts it and takes the difference from the row; such an insert can only be approximately undone (see O6).
- S4 then enforces minimums, so a new window never gets less than its requirement; the space comes from its siblings by the S4 rule.

**O2 Row-share insert mode** is kept as the option `insert-takes-from = 'row'`. [Observed: Bin-static, both a "half of the target" insert and a "share with the whole row" insert exist; drag-docking uses the half-of-target share.] The default is `'target'` (Adrian's decision, closer to the reference's drag-to-dock). Exact undo is kept by pairing it with `close-gives-to = 'donor'` (O6). Dock-all (O12) always uses row sharing.

**O3 Screen-edge dock** (screen-edge band; `dock <dir> --screen`). [Observed: Site/ADDENDUM-2 B3.]
- Apply O1 with the target = the **visible root**: the deepest node whose world rect contains the camera rect (the root at home).
- That root is normally wrapped (ADDENDUM A3), and normalisation folds a same-axis wrap into the root row, which is the same result as a sibling insert at index 0 or n.
- The new window always spans the full height (left/right) or full width (top/bottom) of the view (E4, E5; G22 is the first dock on a fresh workspace).

**O4 Insert into the desktop area** (drop over the desktop area's interior, or a new window: ADDENDUM-2 B1). This floats the window; it never docks it. The frame rule is in §7 (E6).

**O5 Tab onto the centre** (hold over a node's centre region; ADDENDUM-2 B5).
- A window leaf target becomes `TabGroup([target, new], active = new)` in the target's slot, with the ratio unchanged.
- A group target appends the new window and makes it active.
- Dropping a group onto a group appends all its members in order.
- See E7 and G06.

**O6 Remove** (window closed, `undock`, moved away). [Observed: Bin-text, a setting to share a leaving window's space with the whole row, whose help text says that this makes closing exactly undo adding and that otherwise the neighbour after it takes all the space; Bin-default, sharing on. Reading (medium confidence): in the reference the row-share option governs **both** adding and closing, so its exact-undo claim holds for row-share inserts; a half-of-target drag-dock followed by a row-share close is not an exact undo there, and with the option off the after-neighbour takes everything, which undoes a half-target insert only when that neighbour was the donor.]
- `close-gives-to = 'donor'` (default, Lattice choice): if the closed leaf's `donor` is (or is inside) the sibling directly before or after it in the same split, that sibling gets the whole freed ratio. **This exactly undoes a `'target'` insert** (E8, G18, `test_close_undoes_add_and_flatten` over 300 random trees, skipping only inserts where the S1 clamp intervened). Otherwise (the donor was closed, moved, or is no longer adjacent) fall back to `'row'` (E8b, G18b, `test_donor_fallback_keeps_invariants`).
- `close-gives-to = 'row'`: drop the child; normalisation rescales the remaining ratios proportionally (E8c). Pairs with `insert-takes-from = 'row'` for exact undo.
- `close-gives-to = 'neighbour'`: the freed ratio goes to the next sibling, otherwise to the previous one (E9).
- `donor` is kept across later edits (seam drags, other inserts); it is only a hint, so a stale donor simply falls back to `'row'`.
- Removing from a tab group: the group stays. If the removed member was active, the next member becomes active, else the previous one.
- Then normalise. A split left with one child collapses into it, so the remaining child takes the split's ratio.

**O7 Normalise.** As S1: collapse single-child splits, flatten same-axis children with multiplied ratios, repair invalid ratios, enforce `min-ratio` (E10, G20).

**O8 Seam resize** (drag the gap between two docked neighbours). [Observed: Site "Drag the gap between two windows to resize both at once. Everything else stays put."]
- After normalisation, every seam belongs to exactly one split, the lowest common ancestor of the two neighbours, between its children `i` and `i+1`.
- A drag of `δ` screen points along the axis becomes `δ / (σ × zoom)` points in that split's own (possibly virtual) space. Here `σ` is the split's cumulative scale including its own virtual scale (§1.4), and `zoom = 1/(cx1 − cx0)` (or the y equivalent).
- Pin every child of that split to its current **effective** size `p_k`.
- Set `p_i' = clamp(p_i + δ, lo_i, p_i + p_{i+1} − lo_{i+1})`, where `lo_k = max(req_k, min-ratio × T)`, and `p_{i+1}' = p_i + p_{i+1} − p_i'`.
- Write all ratios as `p_k'/T`. Only those two children change; all other frames stay put (E11, E12, G19, `test_seam_only_two_change`).
- Live during the drag: re-solve per frame for drawing (stills), and write AX frames on release (§5).

**O9 Split-direction toggle** (`split-direction <toggle|horizontal|vertical>`; ADDENDUM A3). [Lattice choice]
- Flip or set the axis of the focused window's parent split, keeping its children and ratios, then normalise.
- If the new axis equals the grandparent's, the split is flattened into it (E13).
- **Changes ADDENDUM A3's test** "toggle twice gives the identical tree". It now holds only when the toggled split's parent has a different axis from both values, or the split is the root. A toggle that flattens is a deliberate consequence of "a row inside a row is one row".

**O10 Undock** (drop over the desktop area, the green button, `layout floating`).
- Remove the leaf (O6), then add a `FloatWin` at the window's last on-screen frame, expressed in the new desktop tile.
- The frame is clamped inside the tile with `float-margin`, and shrunk only if it can't fit (E14).
- If the desktop area is hidden, show it first (O11).

**O11 Desktop area hide/show** (`desktop-area <show|hide|toggle>`). [Observed: Bin-static, hiding remembers the area's ratio and neighbours, and re-showing inserts it with a fixed share of about a third. The rules below are ours.]
- **Hide** (not possible when the desktop area is the whole workspace):
  - remember `(ratio, parent split id, axis, index, neighbour ids, floats)`;
  - remove it with row semantics;
  - park its floats.
- **Show:**
  1. If the old parent split still exists, re-insert at the old index with the remembered ratio, carving it proportionally from the siblings. This is the exact inverse of a hide (E15, G21: toggling twice restores identical frames, as in B2's AC).
  2. If the old parent collapsed into its single remembered neighbour, wrap that neighbour in a split of the remembered axis, with the desktop area on its old side and its remembered ratio (E15).
  3. Otherwise wrap the root: `H[root, DesktopArea]` with `desktop-reshow-ratio = 0.33` on the right (E16).
- Floats come back at their stored fractions, reflowed (§7).

**O12 Dock-all** (`dock-all`, the menu "Dock all windows"; ADDENDUM-2 B1).
- Order the manageable floats by current x, with ties broken by y. Dock each one in turn on the **left edge of the desktop area** (O1).
- These inserts always use row sharing, whatever `insert-takes-from` says, so the row ends with equal shares and the desktop area stays (E17). One layout motion covers the whole operation.

**O13 Unmanage-all** (`unmanage-all`, §R of ADDENDUM-2).
- Every docked window becomes a float at its current real frame (its tile if it isn't live), clamped inside the new desktop tile without a margin, so nothing that fits moves.
- The desktop area becomes the whole workspace.
- Z-order: existing floats keep their order, then the newly floated windows in tree order (depth-first, first child first), and the focused window is raised last (E18).

**O14 Move / re-dock.** This is O6 followed by O1/O3/O5 as one transaction with one motion. The old slot is kept reserved until the drop commits (ADDENDUM-2 B3).

**Worked examples** (generated by `refimpl/examples.py`; frames are `(x, y, w, h)`):
```
# E1 insert C at right edge of B, same axis, default insert-takes-from = 'target' (C takes half of B)
  before: H[A 0.6, B 0.4] 
          A=(10, 35, 848, 855); B=(868, 35, 562, 855)
  after:  H[A 0.6, B 0.2, C 0.2] 
          A=(10, 35, 848, 855); B=(868, 35, 276, 855); C=(1154, 35, 276, 855)
# E2 same, insert-takes-from = 'row' (C takes 1/(n+1) from the whole row)
  before: H[A 0.6, B 0.4] 
          A=(10, 35, 848, 855); B=(868, 35, 562, 855)
  after:  H[A 0.4, B 0.2667, C 0.3333] 
          A=(10, 35, 562, 855); B=(582, 35, 371, 855); C=(963, 35, 467, 855)
# E3 insert C at bottom edge of B (cross axis -> wrap B)
  before: H[A 0.6, B 0.4] 
          A=(10, 35, 848, 855); B=(868, 35, 562, 855)
  after:  H[A 0.6, V[B 0.5, C 0.5] 0.4] 
          A=(10, 35, 848, 855); B=(868, 35, 562, 423); C=(868, 468, 562, 422)
# E4 screen-edge dock D at left (root is H -> sibling at index 0)
  before: H[A 0.6, B 0.4] 
          A=(10, 35, 848, 855); B=(868, 35, 562, 855)
  after:  H[D 0.5, A 0.3, B 0.2] 
          A=(725, 35, 419, 855); B=(1154, 35, 276, 855); D=(10, 35, 705, 855)
# E5 screen-edge dock D at top (root is H -> wrap root)
  before: H[A 0.6, B 0.4] 
          A=(10, 35, 848, 855); B=(868, 35, 562, 855)
  after:  V[D 0.5, H[A 0.6, B 0.4] 0.5] 
          A=(10, 468, 848, 422); B=(868, 468, 562, 422); D=(10, 35, 1420, 423)
# E6 drop into the desktop area: F (900x700 natural) then G (400x300) twice-cascaded
  before: H[A 0.5, Desk 0.5] 
          A=(10, 35, 705, 855); desktop=(725, 35, 705, 855)
  after:  H[A 0.5, Desk{F,G} 0.5] 
          A=(10, 35, 705, 855); F=(831, 271, 493, 384); G=(902, 337, 400, 300); desktop=(725, 35, 705, 855)
# E7 tab C onto centre of B
  before: H[A 0.5, B 0.5] 
          A=(10, 35, 705, 855); B=(725, 35, 705, 855)
  after:  H[A 0.5, Tabs(B,C; active=C) 0.5] 
          A=(10, 35, 705, 855); B=(725, 63, 705, 827) hidden-tab; C=(725, 63, 705, 827)
# E8 close X right after docking it beside B: the donor B gets its space back (exact undo)
  before: H[A 0.5, B 0.2, C 0.3] 
          A=(10, 35, 705, 855); B=(725, 35, 276, 855); C=(1011, 35, 419, 855)
   (after docking X right of B: H[A 0.5, B 0.1, X 0.1, C 0.3] )
  after:  H[A 0.5, B 0.2, C 0.3] 
          A=(10, 35, 705, 855); B=(725, 35, 276, 855); C=(1011, 35, 419, 855)
# E8b donor no longer adjacent (B closed first): X's space is shared with the row
  before: H[A 0.5, B 0.2, C 0.3] 
          A=(10, 35, 705, 855); B=(725, 35, 276, 855); C=(1011, 35, 419, 855)
   (X docked beside B, then B closed: H[A 0.5556, X 0.1111, C 0.3333] )
  after:  H[A 0.625, C 0.375] 
          A=(10, 35, 884, 855); C=(904, 35, 526, 855)
# E8c remove B, close-gives-to = 'row'
  before: H[A 0.5, B 0.2, C 0.3] 
          A=(10, 35, 705, 855); B=(725, 35, 276, 855); C=(1011, 35, 419, 855)
  after:  H[A 0.625, C 0.375] 
          A=(10, 35, 884, 855); C=(904, 35, 526, 855)
# E9 remove B, close-gives-to = 'neighbour' (the next sibling C takes all)
  before: H[A 0.5, B 0.2, C 0.3] 
          A=(10, 35, 705, 855); B=(725, 35, 276, 855); C=(1011, 35, 419, 855)
  after:  H[A 0.5, C 0.5] 
          A=(10, 35, 705, 855); C=(725, 35, 705, 855)
# E10 normalize: single-child split, same-axis flatten, invalid ratio
  before: H[V[A 1] 0.3, H[B 1, C 3] 0.5, D nan] 
          (not solved: trees are always normalized before solving)
  after:  H[A 0.3659, B 0.1524, C 0.4573, D 0.02439] 
          A=(10, 35, 463, 855); B=(483, 35, 186, 855); C=(679, 35, 581, 855); D=(1270, 35, 160, 855)
# E11 seam drag +250 pt between A and the column (clamped by the column's min)
  before: H[A 0.4, V[B 0.5, C 0.5] 0.35, D 0.25] 
          A=(10, 35, 562, 855); B=(582, 35, 491, 423); C=(582, 468, 491, 422); D=(1083, 35, 347, 855)
  after:  H[A 0.5748, V[B 0.5, C 0.5] 0.1752, D 0.25] 
          A=(10, 35, 812, 855); B=(832, 35, 241, 423); C=(832, 468, 241, 422); D=(1083, 35, 347, 855)
# E12 seam drag +900 pt (clamped: B keeps its 170 pt slot minimum)
  before: H[A 0.5, B 0.5] 
          A=(10, 35, 705, 855); B=(725, 35, 705, 855)
  after:  H[A 0.8811, B 0.1189] 
          A=(10, 35, 1250, 855); B=(1270, 35, 160, 855)
# E13 toggle axis of inner column -> becomes H -> flattened into row
  before: H[A 0.6, V[B 0.5, C 0.5] 0.4] 
          A=(10, 35, 848, 855); B=(868, 35, 562, 423); C=(868, 468, 562, 422)
  after:  H[A 0.6, B 0.2, C 0.2] 
          A=(10, 35, 848, 855); B=(868, 35, 276, 855); C=(1154, 35, 276, 855)
# E14 undock B (keeps its frame, clamped into the desktop area)
  before: H[A 0.4, B 0.3, Desk 0.3] 
          A=(10, 35, 562, 855); B=(582, 35, 419, 855); desktop=(1011, 35, 419, 855)
  after:  H[A 0.5714, Desk{B} 0.4286] 
          A=(10, 35, 807, 855); B=(839, 47, 419, 831); desktop=(827, 35, 603, 855)
# E15 desktop hide then show (remembered ratio and slot)
  before: H[A 0.6, V[B 0.5, Desk 0.5] 0.4] 
          A=(10, 35, 848, 855); B=(868, 35, 562, 423); desktop=(868, 468, 562, 422)
   (hidden: H[A 0.6, B 0.4] )
  after:  H[A 0.6, V[B 0.5, Desk 0.5] 0.4] 
          A=(10, 35, 848, 855); B=(868, 35, 562, 423); desktop=(868, 468, 562, 422)
# E16 desktop re-show when its old parent is gone (re-show ratio 0.33 at right)
  before: H[A 0.6, V[B 0.5, Desk 0.5] 0.4] 
          A=(10, 35, 848, 855); B=(868, 35, 562, 423); desktop=(868, 468, 562, 422)
   (hidden, then B closed: A )
  after:  H[A 0.67, Desk 0.33] 
          A=(10, 35, 948, 855); desktop=(968, 35, 462, 855)
# E17 dock-all: floats A,B,C (x order) docked left of the desktop area, which stays
  before: H[P 0.5, Desk 0.5] 
          P=(10, 35, 705, 855); desktop=(725, 35, 705, 855)
  after:  H[P 0.2, A 0.2, B 0.2, C 0.2, Desk 0.2] 
          A=(296, 35, 276, 855); B=(582, 35, 276, 855); C=(868, 35, 276, 855); P=(10, 35, 276, 855); desktop=(1154, 35, 276, 855)
# E18 unmanage-all: every docked window floats where it is
  before: H[A 0.6, V[B 0.5, Desk 0.5] 0.4] 
          A=(10, 35, 848, 855); B=(868, 35, 562, 423); desktop=(868, 468, 562, 422)
  after:  Desk{A,B} 
          A=(10, 35, 848, 855); B=(868, 35, 562, 423); desktop=(10, 35, 1420, 855)
# E19 desktop area shrinks: float keeps its size, centre stays proportional, clamped
  before: H[A 0.3, Desk{F} 0.7] 
          A=(10, 35, 419, 855); F=(538, 206, 595, 428); desktop=(439, 35, 991, 855)
  after:  H[A 0.3, B 0.35, Desk{F} 0.35] 
          A=(10, 35, 419, 855); B=(439, 35, 490, 855); F=(951, 206, 467, 428); desktop=(939, 35, 491, 855)
```

## 4. Minimum sizes and the AX read-back loop

**4.1 Per-window limits.** [Observed: Bin-static, per-window minimum/maximum/natural sizes, a fixed fallback minimum (off by default), a floor size, and an option to let windows go below their app minimum that defaults on (Bin-text "Windows can be squeezed below their app's minimum").]
- `appMin`, `appMax`, `natural` (the size the app last chose while floating).
- Sources, in order of strength:
  1. a `min-size <w> <h>` rule (fixed, never changed automatically);
  2. the learned value (§4.3);
  3. none.
- macOS exposes no minimum-size attribute through AX, so minimums are learned from refusals.
- `fallback-min-size = [240, 160]` stands in for an unknown `appMin`, only when sharing space with `shrink-past-app-minimum = false`.
- `tile-floor = [160, 100]`: a tile below this is never live, whatever the app accepts. At home, minimums are guaranteed in virtual space.
- `shrink-past-app-minimum = true` (default): space is shared using `tile-floor` only, so a window can get a slot smaller than its app minimum and then shows as an icon tile (S7) instead of forcing deeper virtual scaling. With `false`, the app minimum takes part in sharing and virtual scaling (G07, G08).

**4.2 The write and read-back loop** (per window, per layout transaction with a generation number). [Observed: Bin-static, a bounded retry (a few attempts within a few seconds), a size tolerance for treating a window as having refused, a re-check delay, and lowering of a learned minimum. The values and the loop are ours.]
```
apply(window, target T):           # only for class 'live'
  for attempt in 1..ax-retries:                    # default 3
      write size(T); write position(T); write size(T)   # PLAN §6 order
      wait ax-readback-delay-ms                    # default 120
      A <- read position and size
      if |A.w-T.w| <= tol and |A.h-T.h| <= tol:    # tol = ax-size-tolerance, 16
          if |A.x-T.x| > 1 or |A.y-T.y| > 1: write position(T) once more
          return ok
      if elapsed > ax-retry-window-ms: break        # default 2000
      wait ax-retry-interval-ms                     # default 200
  refusal:
      if A.w > T.w + tol: learned.minW = A.w   (likewise for h)
      if A.w < T.w - tol: learned.maxW = A.w   (likewise for h)
      persist learned limits (key: bundle id + window kind)
      request re-solve (generation + 1)
```
- **Bounded:** at most `ax-max-resolves = 3` re-solves per user action or event. After that, the current state is accepted, and any window still larger than its tile is reclassified as an icon tile and parked, so nothing overlaps.
- **Grid-snapping apps** (terminals, editors) end up to `tol` smaller than their tile. That counts as success; the tile is not shrunk.
- **Lowering a learned minimum:** if a window is later seen at a size below its learned minimum minus `tol` (resized by the user while floating, or by the app), the learned minimum is lowered to that size. `clear-minimum-sizes` (PLAN §7a) clears every learned value. Rule minimums are never changed.
- **AX timeouts:** use the per-app messaging timeout and serial queue from PLAN §6. A timed-out write counts as an attempt.
- **What the user sees:**
  - During the loop the window stays behind its still (§5.1), with no visible jitter.
  - If it settles as an icon tile, the icon tile fades in.
  - If it ends larger than requested, neighbours re-flow once (one more motion) on the re-solve.
  - Nothing floats because of its minimum size (ADDENDUM-2 B8).

## 5. Zoom-out behaviour

**5.1 Motion uses stills, and resizing happens on settle.** [Observed: Bin-text "Otherwise they're covered until you let go, and resized once"; Site "Pictures, never recordings"; ADDENDUM-2 B12]
- During any camera or layout motion (pinch, zoom, dock, seam drag), every affected window is drawn as its still (one capture at the start of the motion, B12), or as an icon tile without Screen Recording.
- Real windows are **not** written per frame. At settle, Lattice writes final frames once, in this order:
  1. park the windows leaving the view;
  2. shrink the windows that get smaller;
  3. move or grow the rest.
  This order avoids transient overlaps and Mission Control clutter.
- Each still is removed when its window's read-back succeeds (§4.2), or after `still-timeout-ms = 600`.
- A click during a motion ends it (PLAN §5): it jumps to the settled state and writes immediately.

**5.2 Icon tiles.** Per S7 rule 4, an opaque tile in the app's colour with its icon centred (B8), with enter/exit hysteresis of `icon-tile-slack = 2` pt. Double-clicking frames the node (§1.3). G08, G13, G15.

**5.3 Group tiles** (collapsed regions). [Observed: Site "A group too small to see becomes one tile, lined with its splits"; Bin-static, a collapse threshold in points]
- At rest and per drawn frame, evaluate every split except the root and the framed node, using its tile (slot inset by half gaps):
  - if it was not a group tile and its shorter side is below `group-tile-below = 100` → group tile;
  - if it was a group tile and its shorter side is below `group-tile-above = 124` → it stays one (hysteresis).
- The outermost qualifying split wins. Its descendants are `in-group-tile` and parked.
- The tile is drawn with the split lines of its subtree scaled into it. Double-clicking frames that split.
- See G23 (becomes a group tile), G24 (stays one through hysteresis) and G25 (the same size without a prior group tile stays individual icon tiles).

**5.4 Parking.** [Observed: Bin-static and settings text, out-of-view windows are parked, with an option to park them small. The position rule is ours.]
- A parked real window is moved so that its top-left is at `(D.x1 − 1, D.y1 − 1)` of its display's full frame. This is the bottom-right corner, leaving one point on-screen, which macOS requires.
- With several displays, use the first of bottom-right, bottom-left, top-right, top-left whose outward neighbour area isn't covered by another display. For the left corners, the window's right edge goes at `D.x0 + 1`.
- Park size:
  - icon or clipped windows: the learned minimum (B8), or the tile floor;
  - hidden tabs: the group's content size, so switching tabs is a single move;
  - otherwise: the last live size (no resize).
- Parking is reversible, and safe quit (PLAN §7) restores everything on-screen.

**5.5 Pinch settle.** [Observed: ADDENDUM-2 B9]
- On release, among nodes whose world rect contains the pointer (world coordinates), choose the one whose area in home points differs least from the camera's. Ties go to the deeper node; tab-group members are not candidates.
- Animate the camera to frame it (§1.3). G26: the pinch camera `(.5,.45,.95,.95)` with the pointer over C settles on C (area difference 0.025 versus 0.175 for its column, in world units), and C is then framed live at `(10,35,1420,855)`.

## 6. Tabs

[Observed: Site, the bar sits over the group and scales with the zoom; Site sim, bar scale = the tile size relative to a reference size, clamped. Values ours.]
- **Bar height:** `tabBarPx = round(tab-bar-height × k)`, where `k = clamp(min(tile.w / ref.w, tile.h / ref.h), tab-bar-min-scale, 1)`.
  - Defaults: `tab-bar-height = 28`, `ref = tab-bar-ref-size = [400, 280]`, `tab-bar-min-scale = 0.35`.
  - The bar spans the full tile width at the tile's top. The content rect is the tile minus the bar.
- If `tabBarPx < tab-bar-hide-below` (12), the whole group shows as one icon tile (all members `icon`).
- **Requirement** includes the full bar height (S2).
- **Hidden tabs** [Lattice choice]: parked at the content size (§5.4). Switching tabs = move the new active window into the content rect, then park the old one. Both have the same size, so there is no resize.
- Native macOS window tabs inside one app are treated as a single window leaf; Lattice doesn't manage them. [Lattice choice]
- G06: `H[Tabs(A,B; B active) .5, C .5]` gives a bar at `(10,35,705,28)`, B live at `(10,63,705,827)` and A parked at `(1439,899)` with size 705×827.

## 7. Desktop area

[Observed: Site "One part of the screen is the Desktop, where windows float freely"; Bin-static, the area is re-shown with about a third of the space, has drop bands at its edges (a fraction, capped in points), new floats default to a sub-rect of the area, floats are capped at about two thirds of it with a margin, and there is a "sole float takes the desktop" option, default on (Bin-default). Values ours.]

| Item | Lattice rule | Default |
|---|---|---|
| Share when first docked beside | O1 wrap with `insert-ratio` (an even split, natural default) | 0.5 (G22) |
| Re-show share (no memory) | `desktop-reshow-ratio`, on the right | 0.33 |
| Minimum size | `desktop-min-size` (plus gaps) in S2 | 240×160 |
| Drop bands | on each edge, `min(desktop-drop-edge-fraction × extent, desktop-drop-edge-max)`. Edge band → dock beside the area (O1). Interior → float (O4). | 0.18, 60 pt |
| Node drop bands (other tiles) | `drop-edge-fraction × extent` per edge, corners to the nearest edge (A3). The rest is the centre (tab after the B5 hold). | 0.25 |
| Screen-edge band | `screen-edge-band` points at the display edge; wins over node bands (A3) | 8 pt |
| New float frame | Natural size, scaled down (keeping aspect) to at most `float-max-fraction` of the area tile per axis; centred; cascaded by `float-cascade` while an existing float has the same origin; clamped inside with `float-margin`. No natural size: 0.55 × 0.55 of the tile, centred. | 0.7, 24 pt, 12 pt |
| Float reflow when the area resizes | Each float keeps its point size, its centre keeps its relative position, then it is clamped inside with `float-margin`, shrinking only if it can't fit (refines B2's "moved or scaled proportionally") | E19, G27 |
| Only one float | `sole-float-fills`: if true, a sole float fills the area tile until another float appears. **Resolved (Adrian): a lone float does not fill the desktop area**; the key stays for users who want it | **false** |
| Hide | not possible while the area is the whole workspace | — |
| Floats partly off-screen | nudged fully into the visible part of the area tile (S9, §2a) | `float-nudge-in` true |

E6: in a 705×855 area tile, F (natural 900×700) becomes 493×384 centred at (831,271), and G (400×300) is cascaded to (902,337).

## 8. Golden tests

- Display `D = (0,0,1440,900)`, `V = (0,25,1440,875)` (25 pt menu bar, Dock hidden). Default gaps inner 10/10 and outer 10,10,10,10 unless stated. Shrink-past-app-minimum is on unless stated (G07–G09, G23–G25 turn it off).
- Classes: `live` (real frame = frame unless shown), `icon`, `parked`, `clipped`, `float-nudged` (real frame shown), `in-group-tile`, `group-tile`, `hidden-tab` (real = park frame), `tab-bar`, `desktop`, `float-*`.
- Generated by `refimpl/goldens.py` and frozen in `refimpl/goldens.json`. **The Swift `LayoutEngine` must reproduce them exactly** (port them as XCTest table data in P1/P2).
- Operation cases (G16–G22, G18b, G27) show frames after the operation. G28–G31 cover windows straddling the display edge (§2a).

| ID | Case and input tree (ratios) | Gaps inner x/y / outer L,T,R,B | Camera (x0,y0,x1,y1) | Expected: id class (x,y,w,h) [real frame if different] |
|---|---|---|---|---|
| G01 | single window: `A` | 10/10 / 10, 10, 10, 10 | (0, 0, 1, 1) | A live (10, 35, 1420, 855) |
| G02 | two columns: `H[A .5, B .5]` | 10/10 / 10, 10, 10, 10 | (0, 0, 1, 1) | A live (10, 35, 705, 855); B live (725, 35, 705, 855) |
| G03 | three columns unequal: `H[A .5, B .25, C .25]` | 10/10 / 10, 10, 10, 10 | (0, 0, 1, 1) | A live (10, 35, 705, 855); B live (725, 35, 348, 855); C live (1083, 35, 347, 855) |
| G04 | nested column: `H[A .6, V[B .5, C .5] .4]` | 10/10 / 10, 10, 10, 10 | (0, 0, 1, 1) | A live (10, 35, 848, 855); B live (868, 35, 562, 423); C live (868, 468, 562, 422) |
| G05 | window + desktop with float: `H[A .5, Desktop .5 {F at (.1,.1)-(.7,.6)}]` | 10/10 / 10, 10, 10, 10 | (0, 0, 1, 1) | A live (10, 35, 705, 855); F float-live (796, 121, 423, 427); desktop desktop (725, 35, 705, 855) |
| G06 | tab group + window: `H[Tabs(A,B active=B) .5, C .5]` | 10/10 / 10, 10, 10, 10 | (0, 0, 1, 1) | A hidden-tab (10, 63, 705, 827) [real (1439, 899, 705, 827)]; B live (10, 63, 705, 827); C live (725, 35, 705, 855); g1 tab-bar (10, 35, 705, 28) |
| G07 | min width honoured: `H[A .5 (min 900x300), B .5]` | 10/10 / 10, 10, 10, 10 | (0, 0, 1, 1) | A live (10, 35, 900, 855); B live (920, 35, 510, 855) |
| G08 | virtual scale at home (shrink off): `H[A..E equal, each min 400x300]` | 10/10 / 10, 10, 10, 10 | (0, 0, 1, 1) | A icon (10, 35, 276, 855); B icon (296, 35, 276, 855); C icon (582, 35, 276, 855); D icon (868, 35, 276, 855); E icon (1154, 35, 276, 855) |
| G09 | same tree, camera on C: `H[A..E equal, each min 400x300], cam = C's world rect` | 10/10 / 10, 10, 10, 10 | (0.4, 0, 0.6, 1) | A parked (-2850, 35, 1420, 855); B parked (-1420, 35, 1420, 855); C live (10, 35, 1420, 855); D parked (1440, 35, 1420, 855); E parked (2870, 35, 1420, 855) |
| G10 | frame nested node (fit check): `H[A .6, V[B .5, C .5] .4], cam = C's world rect` | 10/10 / 10, 10, 10, 10 | (0.6, 0.5, 1.0, 1.0) | A parked (-2135, -830, 2135, 1720); B parked (10, -830, 1420, 855); C live (10, 35, 1420, 855) |
| G11 | odd gaps, per-side outer: `H[A 1/3, B 1/3, C 1/3]` | 11/11 / 6, 4, 8, 6 | (0, 0, 1, 1) | A live (6, 29, 468, 865); B live (485, 29, 468, 865); C live (964, 29, 468, 865) |
| G12 | pinch camera: clipped and parked: `H[A, B, C, D equal], cam x 0.3..0.8` | 10/10 / 10, 10, 10, 10 | (0.3, 0, 0.8, 1) | A parked (-848, 35, 705, 855); B clipped (-133, 35, 705, 855); C live (582, 35, 705, 855); D clipped (1297, 35, 705, 855) |
| G13 | deep nesting: icon tiles: `H[W1, V[W2, H[W3, ... H[W14,W15]]]] all .5 (14 levels)` | 10/10 / 10, 10, 10, 10 | (0, 0, 1, 1) | W1 live (10, 35, 250, 855); W2 live (270, 35, 1160, 98); W3 icon (270, 143, 157, 747); W4 live (437, 143, 993, 98); W5 icon (437, 251, 157, 639); W6 live (604, 251, 826, 98); W7 live (604, 359, 158, 531); W8 live (772, 359, 658, 99); W9 icon (772, 468, 157, 422); W10 live (939, 468, 491, 98); W11 icon (939, 576, 157, 314); W12 live (1106, 576, 324, 98); W13 icon (1106, 684, 157, 206); W14 icon (1273, 684, 157, 98); W15 icon (1273, 792, 157, 98) |
| G13b | same tree, camera framed on group s10: `as G13, cam = world rect of s10` | 10/10 / 10, 10, 10, 10 | (0.649436, 0.5, 1.0, 1.0) | W1 parked (-2639, -830, 732, 1720); W2 parked (-1897, -830, 3327, 206); W3 parked (-1897, -614, 467, 1504); W4 parked (-1420, -614, 2850, 207); W5 parked (-1420, -397, 467, 1287); W6 parked (-943, -397, 2373, 206); W7 parked (-943, -181, 466, 1071); W8 parked (-467, -181, 1897, 206); W9 parked (-467, 35, 467, 855); W10 live (10, 35, 1420, 206); W11 live (10, 251, 467, 639); W12 live (487, 251, 943, 207); W13 live (487, 468, 466, 422); W14 live (963, 468, 467, 206); W15 live (963, 684, 467, 206) |
| G14 | max size centred: `H[A .5 (max 500x400), B .5]` | 10/10 / 10, 10, 10, 10 | (0, 0, 1, 1) | A live (10, 35, 500, 855) [real (10, 262, 500, 400)]; B live (520, 35, 910, 855) |
| G15 | icon tile: space below app minimum: `H[A .8, B .2 (min 400x200)]` | 10/10 / 10, 10, 10, 10 | (0, 0, 1, 1) | A live (10, 35, 1134, 855); B icon (1154, 35, 276, 855) |
| G16 | insert C right of B (half of the target): `H[A,B] + C@B.right -> H[A .5, B .25, C .25]` | 10/10 / 10, 10, 10, 10 | (0, 0, 1, 1) | A live (10, 35, 705, 855); B live (725, 35, 348, 855); C live (1083, 35, 347, 855) |
| G17 | insert C below B (wrap): `H[A,B] + C@B.bottom -> H[A, V[B .5, C .5]]` | 10/10 / 10, 10, 10, 10 | (0, 0, 1, 1) | A live (10, 35, 705, 855); B live (725, 35, 705, 423); C live (725, 468, 705, 422) |
| G18 | close undoes add (donor): `H[A .7,B .3] +C@A.right then close C -> H[A .7, B .3]` | 10/10 / 10, 10, 10, 10 | (0, 0, 1, 1) | A live (10, 35, 991, 855); B live (1011, 35, 419, 855) |
| G18b | donor gone: close shares with the row: `H[A .5,B .2,C .3] +X@B.right, close B, close X -> H[A .625, C .375]` | 10/10 / 10, 10, 10, 10 | (0, 0, 1, 1) | A live (10, 35, 884, 855); C live (904, 35, 526, 855) |
| G19 | seam drag +100 pt between A and B: `H[A,B,C] equal, seam 0 +100` | 10/10 / 10, 10, 10, 10 | (0, 0, 1, 1) | A live (10, 35, 567, 855); B live (587, 35, 366, 855); C live (963, 35, 467, 855) |
| G20 | flatten same axis: `H[A .6, H[B .25, C .75] .4] -> H[A .6, B .1, C .3]` | 10/10 / 10, 10, 10, 10 | (0, 0, 1, 1) | A live (10, 35, 830, 855); B live (850, 35, 160, 855); C live (1020, 35, 410, 855) |
| G21 | desktop hide then show restores: `H[A .4,B .3,Desk .3] hide->show` | 10/10 / 10, 10, 10, 10 | (0, 0, 1, 1) | A live (10, 35, 562, 855); B live (582, 35, 419, 855); desktop desktop (1011, 35, 419, 855) |
| G22 | first dock on fresh workspace: `Desk + A@screen.left -> H[A .5, Desk .5]` | 10/10 / 10, 10, 10, 10 | (0, 0, 1, 1) | A live (10, 35, 705, 855); desktop desktop (725, 35, 705, 855) |
| G23 | group becomes a group tile below threshold: `H[W1..W13, V[X,Y] id=grp] equal, all min 400x300, shrink off` | 10/10 / 10, 10, 10, 10 | (0, 0, 1, 1) | X in-group-tile (1338, 35, 92, 423); Y in-group-tile (1338, 468, 92, 422); W1 icon (10, 35, 92, 855); W13 icon (1236, 35, 92, 855); grp group-tile (1338, 35, 92, 855) |
| G24 | hysteresis: stays a group tile: `H[W1..W12, V[X,Y]] equal, shrink off, grp was a group tile before` | 10/10 / 10, 10, 10, 10 | (0, 0, 1, 1) | X in-group-tile (1330, 35, 100, 423); Y in-group-tile (1330, 468, 100, 422); W1 icon (10, 35, 100, 855); grp group-tile (1330, 35, 100, 855) |
| G25 | hysteresis: no group tile if it wasn't one: `as G24 without prior group tile` | 10/10 / 10, 10, 10, 10 | (0, 0, 1, 1) | X icon (1330, 35, 100, 423); Y icon (1330, 468, 100, 422); W1 icon (10, 35, 100, 855) |
| G26 | pinch release settles on best-fitting node: `H[A .6, V[B .5, C .5] .4], pinch cam (.5,.45,.95,.95), pointer (.8,.8) -> settles on 'C', framed` | 10/10 / 10, 10, 10, 10 | (0.6, 0.5, 1.0, 1.0) | A parked (-2135, -830, 2135, 1720); B parked (10, -830, 1420, 855); C live (10, 35, 1420, 855) |
| G27 | float reflow when the desktop area shrinks: `H[A .3, Desk .7 {F (.1,.2)-(.7,.7)}] + B@Desk.left` | 10/10 / 10, 10, 10, 10 | (0, 0, 1, 1) | A live (10, 35, 419, 855); B live (439, 35, 490, 855); F float-live (951, 206, 467, 428); desktop desktop (939, 35, 491, 855) |
| G28 | docked window 99.9% on-screen stays live: `H[A,B], camera nudged so A straddles the left edge by 1 pt` | 10/10 / 10, 10, 10, 10 | (0.004, 0, 0.504, 1) | A live (-1, 35, 1420, 855); B clipped (1429, 35, 1420, 855) |
| G29 | docked window 98.7% on-screen is clipped: `H[A,B], camera x 0.01..0.51` | 10/10 / 10, 10, 10, 10 | (0.01, 0, 0.51, 1) | A clipped (-19, 35, 1420, 855); B clipped (1411, 35, 1420, 855) |
| G30 | floating window straddling the edge is nudged in: `Desk {F (.6,.2)-(.95,.6)}, camera x 0.3..0.8` | 10/10 / 10, 10, 10, 10 | (0.3, 0, 0.8, 1) | F float-nudged (862, 206, 998, 342) [real (442, 206, 998, 342)]; desktop desktop (-848, 35, 2850, 855) |
| G31 | float straddling while the desktop area is mostly off-screen: `H[A .7, Desk .3 {F (.1,.1)-(.9,.6)}], camera x 0..0.75` | 10/10 / 10, 10, 10, 10 | (0, 0, 0.75, 1) | A live (10, 35, 1325, 855); F float-clipped (1401, 121, 450, 427); desktop desktop (1345, 35, 562, 855) |

Property tests that must also pass (ported from `refimpl/test_refimpl.py`):
- space sharing sums exactly and respects min/max;
- no tile overlaps, and neighbours are exactly one inner gap apart, on 300 random trees;
- the A4 fit check for **every** node of 150 random trees;
- close-undoes-add (donor rule) for random targets and edges, and invariants after the donor fallback;
- a `'target'` insert gives exactly half of the target's share to each;
- the straddle rule, and nudged floats lie inside the visible desktop area with their size unchanged;
- a seam drag changes only the two adjacent children.

## 9. Config keys

TOML, kebab-case, all optional. Dinky tables keep Dinky's names (PLAN §7a). The others are Lattice extensions, marked as such in the JSON Schema.

| Key | Type | Default | Meaning |
|---|---|---|---|
| `[gaps] inner` | int or `{horizontal, vertical}` | 10 | Gap between neighbours. `horizontal` = between left/right neighbours (`gx`), `vertical` = between top/bottom (`gy`). ≥ 10 per ADDENDUM-2 B3. |
| `[gaps] outer` | int or `{left, top, right, bottom}` | 10 | Gap to the visible frame. |
| `[display.<pattern>]` `inner`/`outer` | as above | — | Per-display override (PLAN §7a). |
| `[layout] insert-takes-from` | `'target'`/`'row'` | `'target'` | O1/O2 sibling share. |
| `[layout] insert-ratio` | float 0.15–0.85 | 0.5 | Share of the target given to the new node (wrap case and `'target'` mode); 0.5 is a natural default. |
| `[layout] close-gives-to` | `'donor'`/`'row'`/`'neighbour'` | `'donor'` | O6. |
| `[layout] live-visible-fraction` | float 0.5–1 | 0.99 | S7 rule 3, §2a: below this on-screen area fraction a window is `clipped`. |
| `[layout] min-ratio` | float 0.005–0.2 | 0.02 | Floor for stored ratios (S1). |
| `[layout] shrink-past-app-minimum` | bool | true | §4.1. |
| `[layout] tile-floor` | `[w, h]` | `[160, 100]` | Smallest live tile; sharing minimum (§4.1). |
| `[layout] fallback-min-size` | `[w, h]` | `[240, 160]` | Assumed app minimum when sharing with the shrink option off. |
| `[layout] drop-edge-fraction` | float 0.1–0.45 | 0.25 | Node edge bands (§7). |
| `[layout] screen-edge-band` | int pt | 8 | Screen-edge band (§7). |
| `[zoom] icon-tile-slack` | int pt | 2 | Icon-tile hysteresis (S7). |
| `[zoom] group-tile-below` | int pt | 100 | Enter group tile (§5.3). |
| `[zoom] group-tile-above` | int pt | 124 | Leave group tile (must be > `group-tile-below`). |
| `[zoom] still-timeout-ms` | int | 600 | Max still lifetime after settle (§5.1). |
| `[tabs] tab-bar-height` | int pt | 28 | §6. |
| `[tabs] tab-bar-ref-size` | `[w, h]` | `[400, 280]` | §6 scale reference. |
| `[tabs] tab-bar-min-scale` | float | 0.35 | §6. |
| `[tabs] tab-bar-hide-below` | int pt | 12 | §6. |
| `[desktop-area] min-size` | `[w, h]` | `[240, 160]` | §7 (`desktop-min-size` in the refimpl). |
| `[desktop-area] reshow-ratio` | float | 0.33 | O11 fallback share. |
| `[desktop-area] drop-edge-fraction` | float | 0.18 | §7. |
| `[desktop-area] drop-edge-max` | int pt | 60 | §7. |
| `[desktop-area] float-max-fraction` | float 0.3–1 | 0.7 | §7. |
| `[desktop-area] float-margin` | int pt | 12 | §7. |
| `[desktop-area] float-cascade` | int pt | 24 | §7. |
| `[desktop-area] sole-float-fills` | bool | false | §7 (resolved: off). |
| `[desktop-area] float-nudge-in` | bool | true | S9, §2a. |
| `[window-sizing] ax-retries` | int 1–5 | 3 | §4.2. |
| `[window-sizing] ax-readback-delay-ms` | int | 120 | §4.2. |
| `[window-sizing] ax-retry-interval-ms` | int | 200 | §4.2. |
| `[window-sizing] ax-retry-window-ms` | int | 2000 | §4.2. |
| `[window-sizing] ax-size-tolerance` | int pt | 16 | §4.2. |
| `[window-sizing] ax-max-resolves` | int 0–5 | 3 | §4.2. |
| `[window-sizing] learn-minimums` | bool | true | §4.2 learning and lowering. |
| `[animations] duration-ms` | int | 450 | Unchanged from ADDENDUM-2 B12, listed for completeness. |

## 10. Constants: observed vs chosen

| Concept | Observed in reference (approx.) | Lattice default | Note |
|---|---|---|---|
| Inner gap | 12 (Bin-default); 10 (Site sim) | 10 | ADDENDUM-2 B3 floor |
| Edge-insert share | 0.5 of the target, clamp 0.1–0.9 | 0.5 of the target (natural default), clamp 0.15–0.85 | default mode `'target'` |
| Row-share insert clamp | 0.05–0.9 | none needed (`1/(n+1)` ≥ `min-ratio` via S1) | |
| Removed-space sharing | whole row, on; else after-neighbour | `'donor'`, falling back to `'row'` | exact undo of half-target docks |
| Partly off-screen windows | parked when out of view; some windows clamped into the visible area (class unresolved) | docked: `clipped` below 0.99 visible; floats: nudged in | §2a |
| Invalid-ratio repair value | 0.001 | `min-ratio` 0.02 | |
| Smallest usable size / floor when shrinking past the app minimum | 200×120 / 120 | `tile-floor` 160×100 | |
| Fixed fallback minimum | 480×320 (off by default) | 240×160 (only with shrink off) | |
| Group collapse | 120 | 100 enter / 124 leave | hysteresis added |
| Desktop re-show share | 0.3 | 0.33 | |
| Desktop edge band | 0.2, max 64 | 0.18, max 60 | |
| Node edge band | 0.28 | 0.25 | |
| New float default rect | 0.6×0.6 at 0.1,0.1 | natural size; else 0.55×0.55 centred | |
| Float cap / margin | 2/3 / 16 | 0.7 / 12 | |
| Sole float fills desktop | on | **off** | resolved by Adrian |
| Tab bar | 28–34 high, scaled by tile/480×320 | 28, tile/400×280, min 0.35 | |
| AX retries / window | 3 within 3 s | 3 within 2 s | |
| Refusal tolerance | 24 pt | 16 pt | |
| Re-check delay | 0.25 s | 120 ms read-back, 200 ms retry interval | |
| Layout motion | ~0.46–0.5 s | 450 ms (ADDENDUM-2 B12) | unchanged |

## 11. Where this lands (phases) and what changes

- **P1 (LayoutModel):**
  - the tree types (§0a);
  - S1 normalise, S2 requirements, S4 space sharing;
  - O1–O14 as pure functions;
  - the G16–G22/G18b/G27 goldens and the property tests.
- **P2 (LayoutEngine):**
  - S3, S5–S9 and §5.3 classification;
  - the G01–G15 and G23–G26, G28–G31 goldens;
  - the A4 fit check on every node (replaces A4's "several sizes" sample tests with the every-node property).
- **P4/P5 (PlatformMac):** the §4.2 loop, the parking corners (§5.4), §7 bands in hit-testing, and the stills-then-settle write order (§5.1).
- **P7:** motion integration (per-frame drawing re-solve, a single AX write at settle).
- **Changes:**
  - PLAN §5's "overflow strategy: shrink siblings, else float" becomes §1.4 virtual scale plus icon tiles (already B8);
  - PLAN §4's type names are replaced (§0a);
  - ADDENDUM A3's toggle round-trip test changes (O9);
  - ADDENDUM-2 B2's "moved or scaled proportionally" is refined (§7);
  - ADDENDUM-2 B1's dock-all ordering is kept, and its placement is defined by O12.
- **Decisions (resolved by Adrian, 2026-10-18):**
  1. A lone floating window does **not** fill the desktop area: `sole-float-fills = false`, key kept.
  2. Docking takes half of the target (`insert-takes-from = 'target'`, `insert-ratio = 0.5`, clamp 0.15–0.85); close returns the space to the donor when it is still adjacent, else to the row (`close-gives-to = 'donor'`).
  3. Windows straddling the display edge follow the closest-evidenced reference behaviour (§2a): out of view → parked; docked and more than 1 % off-screen → `clipped`; floats → nudged in.
- **Open:** none on layout geometry.
