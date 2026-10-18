# ADDENDUM to PLAN.md: double-click gestures, menu-bar navigation, drag-to-rearrange, fit-to-display check

This file extends PLAN.md and does not replace it. Every PLAN.md rule still applies: clean-room (§0), the active-tap input rule and per-OS safety net (§6), the Dinky-compatible config (§7a), and the native look (§7). Section, phase, key and command names below are PLAN.md's.

## A1. Double-click gestures

**Behaviour**
- **Double-click on bare desktop** (the workspace's `.desktop` node, or wallpaper with no window under the pointer) frames the desktop node. A second double-click returns to the previous camera state (`history back`).
- **Double-click on a docked (tiled) window's title bar** frames that window (`zoom window`). A second double-click returns to the previous camera state.
- Floating and unmanaged windows are never affected.

**Model / engine (§5, P2)**
- New camera op `frameDesktop()`, next to `frameAlone(window)`. It pushes onto the navigation history like the other camera ops.
- New toggle semantics in the engine: `toggle(target)`. If the current camera already frames `target` and history has a back entry, it does `back()`; otherwise it frames `target`.

**Commands (§7a Commands, Lattice extensions)**
- Extend `zoom` to `zoom <in|out|all|window|desktop> [--toggle]`.
- `--toggle` applies the engine toggle above. Without it, behaviour is unchanged.

**Config: new Lattice extension table `[mouse]`** (kebab-case, a command string or list, or `'none'`)
- `double-click-desktop`, default `'zoom desktop --toggle'`.
- `double-click-title`, default `'zoom window --toggle'`.
- Validate through the shared command parser and add both keys to the JSON Schema, marked as extensions.

**Detection (§6 Input, inside the existing active tap)**
- On mouse-down with `kCGMouseEventClickState == 2`, classify with the pure tap classifier. The callback only classifies; the AX hit-test runs async.
- **Bare desktop:** our model says the point is in the `.desktop` node rect or in no node, and `CGWindowListCopyWindowInfo` shows no layer-0 window under the point (Finder's desktop window counts as bare). **Swallow** the mouse-down/up pair so Finder's icon selection and macOS's "click wallpaper to reveal desktop" don't fire.
- **Title bar:** `AXUIElementCopyElementAtPosition` resolves to a managed tiled window. The point must lie between the window's top edge and the bottom of its title-bar band. Measure the band from the AX frames of the window's close/zoom buttons, or the toolbar if present (public AX only). Clicks on title-bar controls (buttons, tabs, search fields) don't count.
- **Everything else** passes through untouched.

**Conflict with macOS's title-bar double-click** (`AppleActionOnDoubleClick` in NSGlobalDomain: Maximize/Fill, Minimize or None)
- Read it with `CFPreferencesCopyAppValue` and never write it. That is consistent with §7's rule on macOS settings.
- `double-click-title = 'none'` passes the double-click through, so the system action works as usual.
- With a command set and a system action other than None, Lattice swallows the second click's mouse-down/up for **managed tiled windows only**, so the system's zoom or minimise doesn't fight the layout. Floating and unmanaged windows keep the system action.
- Document in README and in the Settings help text that the default overrides the system action for managed windows only, and how to restore it (`'none'`).

**Safety net (amends §6 "Per-OS safety net")**
- Double-click gestures need swallowing, so they join the features disabled on a version that fails P5a. The menu notice lists them.

**Slots into**
- P2: `frameDesktop()`, toggle semantics, and their tests.
- P5: tap classification, the `[mouse]` config keys, and QA.
- P7: the camera wiring to the platform.

**Tests**
- Classifier tables: `clickState` 1/2/3, desktop/title/content/control hit results, managed/floating/unmanaged → pass, swallow or command.
- Toggle semantics: frame then back, an empty history, and a camera already on the target.
- `[mouse]` parsing (`'none'`, list, invalid command → error).

**Manual QA**
- Double-click on wallpaper frames the desktop; doing it again returns. Finder doesn't select icons or reveal the desktop.
- Title-bar double-click on a tiled Safari/Finder/Xcode/Electron window frames it; doing it again returns. With the system set to Minimize/Maximize, nothing minimises or zooms for tiled windows, while floating windows still do.
- `double-click-title = 'none'` restores the macOS action everywhere.
- Double-clicks in content, text fields and title-bar buttons reach the app normally.
- Triple-click text selection in title fields is unaffected.

## A2. Menu-bar navigation (status-item menu)

**Menu contents, top to bottom.** Each item dispatches the existing command through AppCore.
1. **Back** (`history back`) and **Forward** (`history forward`). Disabled when the focused display's workspace history has no entry in that direction.
2. **Overview** (`overview`) and **Desktop** (`zoom desktop`).
3. **Saved views ▸**: "Go to View 1…9" (`view <n>`), disabled when that slot is empty; and **Save Current View as ▸ 1…9** (`save-view <n>`), with a checkmark on occupied slots and an overwrite allowed.
4. **Workspaces**: `workspace <n>` for each configured workspace, a checkmark on the current one per display, and the display name shown when there is more than one display. Under `.currentSpaceOnly` (P6 safety net), these items are disabled and replaced by the existing **Spaces notice** ("Workspaces unavailable on this macOS build", with Details).
5. Existing items: the **input features toggle** ("Disable input features", §9; it also shows the P5a safety-net notice when that applies), **Settings…**, **Quit**.
- Show each item's binding from `[mode.main]` as its key equivalent when it can be expressed, and leave it blank otherwise.
- Use SF Symbols where Apple's own menus would. Rebuild in `menuNeedsUpdate(_:)` from AppCore state; state lives in AppCore, not in the menu.

**Slots into**
- P0: the status item exists.
- P8 (App tasks): add "Status-item navigation menu", since it depends on history (P2/P7), saved views (P8) and workspaces (P6).

**Tests**
- A pure `MenuModel` builder in AppCore takes state and returns the items with their enabled/checked states. It is unit-tested for: empty or partial history, empty and occupied view slots, 1 vs 3 workspaces on 1 vs 2 displays, `.currentSpaceOnly`, and the input safety net active.

**Manual QA**
- Back/Forward enable and disable correctly after zooms and history navigation.
- Saving to slot 3 and then going to slot 3 restores the camera.
- Workspace checkmarks follow Space switches made via Mission Control and Cmd-Tab.
- The menu works with every input feature disabled.
- VoiceOver reads every item.

## A3. Drag-to-rearrange (drop targets, undock, split direction)

**Drop targets** (extends §4 `DropTarget`). They are shown while a window is dragged by its title bar or by modifier-drag (§6), drawn with `[drag] placeholders`.
- `.edge(nodePath, Edge)`: **insert as a new row or column beside a node.**
  - If the node's parent split runs along that edge's axis, insert as a sibling (neighbours make room).
  - Otherwise wrap the node in a new split with the window on that side.
  - Hit zone: the outer band of the deepest node under the pointer (corners go to the nearest edge). An ancestor's edges can be picked in a thin band along that ancestor's outer edge.
- `.screenEdge(Edge)`: **a screen-spanning strip.** Wrap the visible root in a split so the window spans the full width (top/bottom) or full height (left/right). Hit zone: a thin band at the display edge. It takes precedence over node edges.
- `.center(nodePath)`: tab (unchanged; hold over the centre).
- **New `.undock(Rect)`:** dropping a **docked** window over the bare `.desktop` area, or outside every target, makes it floating at the drop frame.
- Pressing Esc during a drag cancels it and returns the window to its slot. Esc comes through the active tap and is swallowed only while a drag is active.

**Split direction**
- On hover, the existing seam overlay handle (P5 "Seam resize via our own overlay handles") shows a small **rotate-split** button (an SF Symbol). Clicking it toggles the axis of the split that owns the seam.
- New command (§7a Lattice extension): `split-direction <toggle|horizontal|vertical>`, which acts on the focused window's parent split. Don't confuse it with the existing `split <horizontal|vertical>`, which wraps the focused window for the next new window.
- Dropping a window onto the seam handle was considered and rejected as ambiguous; the rotate button plus the command cover it.

**Model ops** (§4 Operations, P1; add them if missing)
- `undock(window, frame:)`: remove the window from the tree (siblings absorb the space, following `remove` semantics) and add it to `floating` with that frame. Then `normalize()`.
- `setAxis(splitPath, Axis)` and `toggleAxis(splitPath)`: keep children and ratios, then re-solve.
- `insert(window, at: .edge/.screenEdge)` must implement the sibling-vs-wrap rule above.

**Slots into**
- P1: the ops and their tests.
- P5: drop-target hit-testing, the seam rotate button, Esc cancel, and the `split-direction` command.
- P7: the animated reflow on drop.

**Tests**
- `undock` keeps the invariants (each window appears at most once, ratios are valid, no empty splits) and keeps the `.desktop` node.
- `setAxis`/`toggleAxis` round-trips (toggle twice gives the identical tree).
- `.edge` insert: sibling case vs wrap case for all four edges.
- `.screenEdge` produces a full-span strip at depth 1.
- Hit-testing tables: node bands, ancestor bands, screen bands winning, centre with hold.
- Random op sequences that include `undock`/`toggleAxis` keep the invariants.

**Manual QA**
- Drag a window to each edge of a tiled window: a new row or column appears there.
- Drag to each screen edge: a full-width or full-height tile appears.
- Hold over the centre: a cross-app tab group forms.
- Drag a docked window onto the bare desktop: it floats where it was dropped, and its neighbours close the gap.
- Re-dock a floating window by dragging it onto an edge target.
- The rotate-split button and `split-direction toggle` flip a two-window row into a column and back.
- Esc mid-drag restores the window.
- All of the above work for Electron and Java windows.

## A4. Fit-to-display acceptance check

**Acceptance criterion**, added to P2 and P7. After any camera zoom onto a node, the targeted node's final frame equals the display's visible frame (menu bar and Dock excluded) inset by the `[gaps] outer` values, including `[display.<pattern>]` overrides, to within ±1 pt per edge. The triggers are:
- pinch step-in or step-out (existing §6 behaviour), once the gesture ends;
- double-click desktop or title (A1);
- `zoom window|desktop|in`;
- `view <n>` landing on a single-node view.
A window's own minimum size may make it larger than the target; that case is reported, not failed.

**P2 test**
- Golden tests on several display sizes, gap settings and nesting depths (up to 20): after `stepIn`/`frameAlone`/`frameDesktop`, `framesAt(camera)[target]` equals the inset visible rect to within ±1 pt.

**P7 manual QA and automated check**
- Compare the target window's real AX frame, read back after the animation settles (via `debug-state`), with the expected rect. Run on a laptop panel, an external display, and both at once.
- A small `qa-fit-check` debug command logs pass/fail per zoom. It is excluded from release builds (`#if DEBUG`, §7 release hygiene).
