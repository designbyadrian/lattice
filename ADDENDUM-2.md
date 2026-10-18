# ADDENDUM-2: behaviour audit against the public site (supersedes parts of PLAN.md and ADDENDUM.md)

**Sources.** I read the public site in full on 2026-10-18; the raw files are in `site/`.
- `site/index.txt` is the home page, cited as **[Home/Hero]**, **[Home/Features]**, **[Home/Hands]** (the shortcuts strip), **[Home/Built]** and **[Home/FAQ]**.
- `site/how-it-works.txt` is cited as **[HIW/1–5]**.
- `site/docs.txt` is the single docs page; its sections are cited as **[Docs/<section>]**. It has no subpages, and `/film`, `/support` and `/trellisUI` return 404.
- `site/raw/*.js` is the page's own in-browser desktop simulation, cited as **[Sim]**. It shows motion only: how the camera, drags and pinches animate.
- **[Bin]** is an inference from REPORT.md (the static teardown), used only where the site is silent and labelled as such.

**Precedence.** Where a spec below says **SUPERSEDES**, it replaces the named PLAN.md or ADDENDUM.md text, and the rest of those files still applies.

**Clean-room.** Everything here is behaviour, written in our own words. The command and key names are Lattice's own, and the plan's §0 rules apply.

**Adrian's decisions** (earlier ones plus the §D resolutions of 2026-10-18; all are binding):
- Pinch stays with the app unless Option is held; pinch on bare desktop or in the zoomed-out view navigates.
- Dinky TOML config and rules format; the TOML file is the source of truth.
- Native look.
- No shipping or distribution (D10).
- The earlier open questions (§Q) are all resolved in **§D**, and the specs below already follow them.

---

## 0. Likely causes of the odd results (plan defects)

1. **Everything was tiled on launch.** PLAN P4 "auto-insert new windows" plus `default-tiling = true` tiles every existing window immediately, Dinky/AeroSpace style. The site says the opposite: after setup "your windows stay just where they are; nothing moves until you dock a window yourself" [Docs/Set up]. See B1 and D1.
2. **Zoom treated as an overlay, not a camera on real windows.** PLAN §5, P7 and the `overview` command describe a separate overview panel with previews, like Mission Control. On the site, "show everything" *is* the camera zoomed out on the real arrangement [Home/Hero; Docs/Zoom], and windows too small to use get an app-colour and icon cover [Home/Features "Small, but still clear"]. See B6–B8.
3. **Motion driven by AX every frame, plus a Dinky default of 150 ms.** PLAN §7 says "drive window frames via AX at display refresh", with proxies only as an option. The site draws all motion from still pictures, with one ~half-second layout motion [Home/Hands "460 ms…"; Home/Built "Pictures, never recordings"]. Because of Dinky's `[animations] duration-ms = 150` default, motion probably came out snappy and jittery. See B12.
4. **The desktop region and floating windows are modelled separately.** PLAN §4 keeps `floating` as a separate list "over" `.desktop`. On the site the Desktop is a *region inside the arrangement* where floating windows live, and it moves and scales with the camera [Docs/The idea; Sim]. See B2.
5. **Drops only applied on mouse-up.** PLAN §6 says "show drop overlays and act on mouse-up". The site opens a space *while you hover* ("A space opens for it"), then the window slides in on release [Docs/Dock a window; Sim preview]. See B3.
6. **Windows below their minimum size float.** PLAN §5 says "shrink siblings, else float". On the site the window stays docked and is covered by its app colour and icon until there's room [Docs/Dock a window]. See B8.
7. **Pinch as discrete steps.** PLAN §6 and ADDENDUM item 3 assumed one stepIn/stepOut per gesture. The site's pinch zooms continuously around the pointer, then *settles on the space that fits best* [Home/Features "Everything, at a pinch"; HIW/5; Sim]. See B9.
8. **"Space" means two different things.** The site's "spaces" are *nested regions of the arrangement*, and "neighbouring space" pans the camera [Docs/All shortcuts]. The plan uses "Space" for macOS Spaces. An agent could easily have mapped "neighbouring space" to macOS Space switching. See B10. From here on this file says **region** for a tree node and **macOS Space** for the OS feature.
9. **Wrong default shortcuts.** PLAN §7a writes a first-run config but never specifies default bindings, so an agent would copy Dinky's (alt-h/j/k/l, alt-1…9 = workspaces), which match none of the site's shortcuts. See B11 and D3.
10. **An invented modifier-drag "move".** The plan has alt-drag to move/dock. On the site the only modifier-drag is a rectangle that the camera zooms to fit [Docs/Focus; HIW/4]. See B4 and D4.
11. **A single menu instead of menu-bar controls.** ADDENDUM A2 puts navigation inside one dropdown. The site has clickable controls *in the menu bar itself* (back, forward, saved-view numbers, Desktop, everything), with the current one filled in, and the menu holds the rest [Home/Features "Lives in your menu bar"; Docs/The menu bar]. See B13.
12. **Underspecified tabs.** P8 just says "tab strip overlay". The site specifies the hold-to-tab drop, cross-app groups, click to switch, drag out to tear off, a right-click menu, and moving the whole group [HIW/1; Docs/Tab groups]. See B5.
13. **Clean-room naming.** Some plan command names match the vendor's URL commands (`view`, `save-view`, `float-all`), which PLAN §0 forbids. They are renamed in **§R**.

---

## B. Behaviour specs

Each item gives its source, what it amends or supersedes, and its acceptance criteria. "Docked" means a window that is part of the tree.

### B1. First launch and new windows [Docs/Set up; Docs/The idea; Docs/The menu bar "arranging all your windows at once"]
**SUPERSEDES** PLAN §7a `default-tiling = true` (Lattice's default becomes **`false`**), PLAN P4's "auto-insert new windows" and its QA line "New window tiles", and ADDENDUM-2's earlier B1 proposal (D1).
- **Given** Lattice starts, first launch or any later one with no saved arrangement, with 6 windows open. **When** onboarding finishes or Lattice is running. **Then** no window moves or resizes, all 6 are floating in the desktop region, and the region fills the display.
- **Given** any workspace. **When** an app opens a new window. **Then** it floats in the desktop region at the frame the app chose, clamped inside the region. Nothing docked moves.
- **Docking is manual:** dragging (B3), the green button (B15), or the commands `dock <left|down|up|right> [--screen]` and `dock-all`.
- **"Dock all windows"** (menu item and the new command `dock-all`): every manageable floating window in the current workspace is docked in one animated layout motion. Windows are ordered left to right by their current x position into a single row, and the desktop region stays (B2).
- **Rules still apply.** A `[[rules]]` entry with `run = 'layout tiling'` docks a matching new window beside the focused docked window (or at the left screen edge if nothing is docked). `layout floating` is then the default and needs no rule.
- **Per workspace:** `[workspace.<n>] tiling = true` turns on auto-docking new windows for that workspace only, using the same rule as `layout tiling`. Dinky's key keeps its meaning; only the default changes.
- **AC:**
  - Launching changes no window frame (AX before and after, within 1 pt).
  - A new Safari window appears floating, and no docked frame changes.
  - `dock-all` is a single motion, and the desktop region is still present afterwards.

### B2. The desktop region [Docs/The idea; Home/Hero "The Desktop stays between"; Docs/All shortcuts "Hide or show the Desktop"; Sim]
**SUPERSEDES** PLAN §4 `Workspace.floating` as a separate list: floating windows belong to the `.desktop` node.
- Each workspace has one desktop region: a node of the tree, where floating windows live with frames **relative to the region**.
- **Given** a workspace with only the desktop region. **When** a window is docked to the left screen edge. **Then** the window takes a left column, the desktop region shrinks to the remaining width, and floating windows stay inside it. Each is moved or scaled proportionally so that none overlaps a docked window.
- **When** a second window is docked to the right edge. **Then** the desktop region sits *between* the two columns.
- **Given** the camera zooms out (B6). **Then** floating windows move and scale with their region, like docked ones.
- **Hide or show the desktop region** (new command `desktop-area <show|hide|toggle>`, §R; menu item with a checkmark "Desktop in this workspace"). Hiding removes the region from the layout: docked windows take its space and floating windows are parked. Showing restores the region at its previous size, with the floats back in their relative positions.
- **AC:** no floating window ever overlaps a docked window after any dock, undock or resize; toggling the region twice restores identical frames.

### B3. Dragging to dock, with live make-room [Docs/Dock a window; Home/Features "Dock anywhere"; HIW/2; Sim]
**SUPERSEDES** PLAN §6 "act on mouse-up" and refines ADDENDUM A3's targets.
- **Given** a window dragged by its title bar (or a tab group dragged by its strip). **When** the pointer enters an edge band of another docked window or region. **Then** within about 150 ms the neighbours animate apart to open a gap the size of the would-be slot, and an accent-tinted ghost shows where the window will land.
- **When** the pointer leaves that band. **Then** the gap closes again.
- **When** the user releases over an open gap. **Then** the window slides into it with the layout motion, and its neighbours settle.
- **Targets.**
  - **Edge of a window or region:** dock beside it, using ADDENDUM A3's sibling-or-wrap rule.
  - **Screen edge:** dock beside *everything currently in view*, i.e. the camera's visible root, not the whole tree.
  - **Centre held:** tab (B5).
  - **Over the desktop region:** float there (undock).
  - **Elsewhere:** cancel, and the window returns to its slot.
- **Re-dragging a docked window** moves it: its old slot closes with the layout motion only when the drop commits. Until then, the old slot stays reserved and shown as an empty ghost.
- **Resizing at a seam:** dragging the gap between two docked windows resizes only those two. Everything else stays put, and the gap must be at least 10 pt wide so it's easy to grab (`[gaps] inner` default ≥ 10 instead of Dinky's 8).
- **ADDENDUM A3's rotate-split button** stays optional and is not a site behaviour. The split direction normally comes from *which edge* the window is dropped on.
- **AC:** the gap opens before release; releasing without a target restores the original layout exactly; a seam drag changes exactly two frames.

### B4. Zoom to a rectangle [Docs/Focus; HIW/4]
**SUPERSEDES** PLAN §6 "Modifier-drag over app windows → move/dock", PLAN P5's "Modifier-drag over app windows (swallowed) → move/dock/`frame-rect`", and PLAN §7a's `[modifiers] drag-modifier` key. The alt-drag move/dock behaviour is **removed** (D4); moving and docking are title-bar drags only (B3).
- **New key:** `[modifiers] frame-modifier = 'cmd-shift'` replaces `drag-modifier`. Lattice extension, key names as in bindings.
- **Given** any view. **When** the user holds `frame-modifier` and presses the mouse anywhere, over app windows or desktop. **Then** the press is swallowed (the app gets no click), a translucent accent rectangle follows the pointer, and on release the camera animates so the rectangle's contents fit the display (aspect-fit, centred).
- Esc cancels with no camera change. The zoom is pushed onto history, so Back returns.
- `frame-rect` (command) opens the same rectangle overlay without a modifier.
- **P5a-gated:** where the input check fails, ⌘⇧-drag passes through to apps; `frame-rect` via a binding or the menu still works.
- **AC:** the regions fully inside the rectangle are all visible afterwards, and the rectangle's longer side spans the display within the outer gaps; no app receives the ⌘⇧ press.

### B5. Tab groups [HIW/1; Home/Features "Tab groups"; Docs/Tab groups; Sim; Bin "windowButtonsActOnGroup", inferred]
Replaces P8's "Tab groups with a tab strip overlay".
- **Given** a window dragged over the *middle* of another window. **When** the pointer rests there for about 400 ms. **Then** the target shows a tab-strip ghost. **When** released, **then** both become tabs of one group in the target's slot, whatever their apps.
- The strip is our own native overlay across the top of the group. The active window sits below the strip, sized to the slot minus the strip height, and inactive tab windows are parked out of view.
- **Click a tab:** that window takes the slot, and the previous one is parked.
- **Drag a tab out:** it tears off and behaves as a normal window drag (B3).
- **Right-click a tab:** a menu with "Close" and "Move out of group".
- **Drag the strip:** moves the whole group (B3).
- **When zoomed out:** the strip scales with the camera.
- Inferred, needs QA: the close and minimise buttons on the active window act on the whole group.
- **AC:** a cross-app group (Safari + Terminal) works; tearing off restores a normal docked window; only one tab window is ever visible.

### B6. The camera works on the real arrangement [Home/Hero; Docs/The idea; Docs/Zoom out and in; Sim; Bin "parkOutOfViewSmall", inferred]
Clarifies PLAN §5, P7 and ADDENDUM A4. **SUPERSEDES** any reading of the zoom as a separate overlay or overview panel.
- The camera is a rectangle in arrangement coordinates. **At rest, every docked and floating window in view is set (AX) to its projected frame**, so zoomed out, the real windows are physically smaller.
- Windows outside the view are parked off-screen.
- Windows whose projected frame is smaller than the app allows get a cover (B8).
- **"Show everything" (`zoom all`):** the camera fits the whole arrangement, including the desktop region.
- **Step out (`zoom out`):** the camera moves to the parent region of the current one.
- **Step in (`zoom in`):** the camera moves one level down, into the child region under the pointer, or into the focused window's branch if the pointer is outside the view.
- **Frame a window alone (`zoom window --toggle`):** the camera fits that window's slot to the display. Run again, it goes back.
- **Frame the desktop region (`zoom desktop --toggle`):** the same for the desktop region.
- **There is no separate overview** (D6). PLAN's `overview` command, P7's "zoom-out overview" and ADDENDUM A2's "Overview" menu item are removed. "Everything" means `zoom all`.
- Every camera change is pushed onto history (B10).
- **AC:** ADDENDUM A4's fit check, plus: at rest after `zoom all`, the windows' real AX frames equal their projected frames within 1 pt, or the window is covered (B8).

### B7. Deep nesting [Home/Features "Dock anywhere"; HIW/2; Home/Hands "∞"]
Clarifies PLAN §4.
- Docking onto the edge of a window that is itself inside a region creates a sub-region at that depth. There's no depth limit.
- **AC:** at depth 6, step in and step out traverse exactly one level per command.

### B8. Small windows and collapsed groups [Home/Features "Small, but still clear"; Docs/Dock a window]
**SUPERSEDES** PLAN §5's "overflow → float" for docked windows.
- **Given** a docked window whose slot, or its projected frame when zoomed out, is smaller than the app's minimum size (learned from AX clamping). **Then** the window stays docked, is set to its minimum size and clipped by parking, and an opaque cover in the app's colour, with the app icon centred, fills the slot. This applies at any zoom level.
- **Given** zoomed out so that a whole region's projected size falls below a legibility threshold. **Then** it renders as one tile showing its split lines.
- **When** the user double-clicks a cover or tile. **Then** the camera steps into it (`zoom` to that node).
- When the window has room again (after a resize or zoom-in), the cover fades out.
- **AC:** no docked window floats because of its minimum size; double-clicking a cover fits its node to the display (A4).

### B9. Pinch: continuous zoom, then settle [Home/Features "Everything, at a pinch"; HIW/5; Docs/Zoom; Sim]
**SUPERSEDES** the stepIn/stepOut-per-gesture pinch in PLAN §6/P5, and PLAN §7a's `pinch-modifier` default (`'ctrl-alt'` becomes **`'alt'`**, D5).
- **Where it applies:** pinch on bare desktop, in the zoomed-out view, or anywhere with Option (`pinch-modifier = 'alt'`) held. Otherwise the pinch goes to the app.
- **P5a-gated:** where the input check fails, Option-pinch over apps is disabled; bare-desktop pinch (an observe-only global magnify monitor) and the shortcuts still work.
- **During the gesture**, the camera scales continuously about the pointer, following the fingers. Windows are drawn as pictures or covers while it moves (B12).
- **On release**, the camera animates to the region whose rect best fits the current view. That's the node minimising the area difference with the view, preferring the node under the pointer.
- **AC:** pinching in over a window settles with that window, or its smallest containing region, filling the display (A4); pinching out then in over the desktop region settles on the desktop region; no app receives a pinch that Lattice handled.

### B10. Navigation: history, neighbours, saved views [Docs/Zoom; Docs/Saved views; Docs/All shortcuts; Home/Hands; Home/Features "Saved views"; Home/Hands "9 saved views on every display"]
Adds to PLAN §5/§7a commands.
- **Back and Forward** (`history back|forward`) walk camera states like a browser. A new camera move after going back clears the forward entries.
- **Pan to a neighbour** (new command `pan <left|right|up|down>`): the camera moves to the sibling region adjacent in that direction at the *same depth*, keeping the zoom level. At the edge of the arrangement it does nothing (with a soft bump animation). This is **not** a macOS Space switch.
- **Saved views** (`store-view <n>`, `recall-view <n>`; see §R): save the current camera into slot 1–9 *per display*, and recall it from anywhere. Recalling animates there and pushes onto history. Recalling an empty slot does nothing (HUD "Empty").
- **AC:** back/forward round-trip to identical camera rects; `pan right` from the leftmost of three sibling columns lands on the middle one.

### B11. Default shortcuts [Docs/All shortcuts; Home/Hands]
**SUPERSEDES** the unspecified first-run `[mode.main]` in PLAN §7a/P5. Dinky's default bindings are **not** used (D3). The key choices are behaviour; the command names are ours (§R). The first-run config writes exactly this, in Dinky binding syntax:

| Keys (Dinky syntax) | Command | Behaviour |
|---|---|---|
| `ctrl-alt-space` | `zoom all` | Show everything |
| `ctrl-alt-up` | `zoom out` | Step out one level |
| `ctrl-alt-down` | `zoom in` | Step in one level, toward the pointer |
| `ctrl-alt-left` / `ctrl-alt-right` | `pan left` / `pan right` | Neighbouring region left / right (B10) |
| `ctrl-alt-shift-up` / `ctrl-alt-shift-down` | `pan up` / `pan down` | Neighbouring region above / below |
| `ctrl-alt-left-bracket` / `ctrl-alt-right-bracket` | `history back` / `history forward` | Back / forward |
| `ctrl-alt-enter` | `zoom window --toggle` | Focused window on its own; again to return |
| `ctrl-alt-d` | `desktop-area toggle` | Hide or show the desktop region in this workspace |
| `ctrl-alt-n` | `split-new com.apple.finder` | New Finder window docked beside the focused window, split along its longer side |
| `ctrl-alt-shift-1` … `9` | `store-view 1` … `9` | Save the current view in slot n (this display) |
| `ctrl-alt-1` … `9` | `recall-view 1` … `9` | Go to saved view n |
| `ctrl-alt-cmd-1` … `9` | `workspace 1` … `9` | Numbered macOS-Space workspace n (P6) |
| `ctrl-alt-cmd-shift-1` … `9` | `move-window-to-workspace 1` … `9` | Send the focused window to workspace n |
| mouse: `frame-modifier` (`cmd-shift`) + drag | `frame-rect` | Zoom to a rectangle (B4) |
| trackpad: `pinch-modifier` (`alt`) + pinch | camera pinch | Zoom anywhere (B9) |

- **Why `ctrl-alt-cmd` for workspaces:**
  - `ctrl-alt-shift-1…9` is already taken by `store-view`.
  - Adding ⌘ keeps workspaces in the same Control-Option family, one modifier deeper, because they're used less than saved views.
  - It doesn't collide with macOS's own Control-1…9 desktop shortcuts.
  - With the default `workspaces = 1`, numbers above the configured count show a HUD ("Workspace n isn't set up") instead of an error, so the bindings are harmless until more workspaces are configured.
- `[mouse] double-click-desktop` / `double-click-title` keep ADDENDUM A1's defaults (`zoom desktop --toggle` / `zoom window --toggle`).
- **AC:** a fresh config contains exactly these bindings; every one works on a fresh install; the shortcut recorder (B19) shows them.

### B12. Motion [Home/Hands "One layout motion for every split, dock and close" (~0.5 s); Home/Built "Pictures, never recordings"; Docs/Set up (optional Screen Recording); Docs/If something's not right "coloured boxes with an icon"; Sim spring camera]
**SUPERSEDES** PLAN §7 "drive window frames via AX at display refresh" and the default `[animations] duration-ms`.
- Every layout or camera animation is drawn with **proxies**: per-window still captures (one capture at the start, not a stream), or app-colour and icon boxes without Screen Recording. The proxies go in our overlay window, the real windows are parked during the motion, and each real window gets **one** AX frame set at the end, revealed as its proxy fades.
- Layout motion (dock, split, close, tab) uses one shared curve of about 450 ms, ease-out, no overshoot. Camera motion uses a smooth spring that settles within about 450 ms, also without visible overshoot.
- `[animations] duration-ms` defaults to **450** in Lattice (Dinky's is 150). Reduce Motion turns animations into a crossfade.
- A click during an animation ends it at its target.
- **Captures (D6):** ScreenCaptureKit is used **only** for one still `SCScreenshotManager` capture per visible window at the start of each motion (and to refresh a cover's picture where that's used). Nothing streams.
- **Removed:** PLAN §6's live `SCStream` previews, the `overview-previews` key, and the desktop-vs-laptop power-source detection with its P7 tests and QA. A single capture per motion doesn't need a refresh policy, so the detection has no remaining use.
- **AC:** no window shows intermediate AX frames during an animation (screen recording frame-by-frame); without Screen Recording, proxies are coloured boxes with icons.

### B13. Menu bar [Home/Features "Lives in your menu bar"; Docs/The menu bar; Docs/Saved views "show as numbers in the menu bar"; Docs/If something's not right]
**SUPERSEDES** ADDENDUM A2's layout. A2's items stay; they move into controls and the menu.
- **Controls in the menu bar:** Back, Forward, the saved-view numbers that are in use, Desktop, and Everything, each a separate native status button with an SF Symbol or number.
  - The button for the current state is drawn filled; that's the native "on" state.
  - Back and Forward are disabled at the ends of the history.
  - Right-clicking any control opens the Lattice menu.
  - Which controls show, and their order, is the Lattice extension key `menu-bar-controls = ['back', 'forward', 'views', 'desktop', 'everything']` (any subset, in order), editable in Settings ▸ Menu Bar (B19). Lattice's own icon is always present.
- ADDENDUM A2's "Overview" item is **removed** (D6); "Everything" (`zoom all`) replaces it.
- **Lattice menu** (click the icon): Saved views ▸ (go/store), "Desktop in this workspace" ✓ (`desktop-area toggle`), "Dock all windows" (`dock-all`), "Float every window" (`unmanage-all`), "Leave <frontmost app> alone" (adds a `[[rules]]` `ignore` entry via ADDENDUM's append helper), the workspaces list and the Spaces notice (PLAN P6), the input-features toggle, Settings…, Quit.
- **AC:** the filled state follows camera changes made by keyboard, pinch and double-click; all actions work with the input features disabled.

### B14. Double-click [HIW/3; Docs/Focus; Docs/Zoom]
Confirms ADDENDUM A1 (docked windows only), with:
- **Docked windows only** (D7), at any zoom level, including covers and collapsed tiles (B8). Title-bar double-clicks on **floating** windows always pass through to macOS (its `AppleActionOnDoubleClick` behaviour). This supersedes the earlier B14 draft that extended it to every visible window.
- A second double-click returns via `history back` only when nothing else changed the camera in between; otherwise it frames the target again.

### B15. Green button: dock or float [Docs/Float a window]
New behaviour (D8). It is **added to the P5a-gated feature list** (PLAN §6 "Per-OS safety net", extended by ADDENDUM A1). Where the P5a check fails, the green button keeps normal macOS behaviour.
- **Given** a docked window. **When** the user clicks its green button. **Then** the click is swallowed and the window floats in the desktop region, centred at its previous size, clamped to the region.
- **Given** a floating, managed window. **When** the user clicks its green button. **Then** the click is swallowed and the window docks beside the focused docked window (or at the left screen edge if nothing is docked), with the layout motion.
- **Option-click** passes through to macOS's own Option-click behaviour (zoom/fill rather than full screen). This matches the site ("Hold ⌥ as you click for the green button's usual zoom", [Docs/Float a window]).
- Unmanaged apps ("Leave <app> alone", rules with `ignore`) are never intercepted.
- **Detection:** mouse-down in the active tap, then an async AX hit-test finds the window's full-screen button. The callback only classifies (PLAN §6 budget); it swallows mouse-down/up only when the cached button frame matches.
- **AC:** without Option, the green button never full-screens or zooms a managed window; docking then floating then docking returns the window to a docked slot; on a version that fails P5a, the green button behaves exactly like stock macOS.

### B16. Floating, opting out, restoring [Docs/Float a window; Docs/If something's not right; Home/Features "Your Mac, your rules"; Home/FAQ "What happens when I quit?"; Docs/Uninstall]
Confirms PLAN P4/§7, with:
- Dragging onto the desktop region floats a window (B3).
- `unmanage-all` (§R; it was `float-all`) floats every window in place, so you're back to a normal Mac. The arrangement is left empty but saved.
- "Leave <app> alone" stops managing that app's windows immediately, and they keep their frames.
- On quit, every window gets a fully on-screen frame, and the arrangement per display is restored on the next launch.
- Minimising: neighbours take the space; restoring returns the window to the same slot (PLAN §4 suspension, confirmed).
- Sheets and dialogs stay attached and are never managed. Full-screen apps are left to macOS (PLAN P4 full-screen handling).
- **macOS Spaces deliberately differ from the site (D9).** The site leaves other macOS desktops to macOS [Home/FAQ "Mission Control"], but Lattice keeps numbered workspaces on macOS Spaces as a core feature (PLAN P6), as Adrian decided. Camera regions (B10 `pan`) and macOS Spaces stay separate concepts.

### B17. Multi-display [Home/Features "One arrangement per display"; Home/Hands; Home/FAQ "quit"]
Confirms PLAN §4:
- Each display has its own arrangement, camera, history and 9 saved views.
- Dragging a window to another display drops it into that display's arrangement using the B3 targets there.
- **AC:** zooming on display A never moves display B's windows.

### B18. Onboarding and getting started [Docs/Set up; Docs/Uninstall]
Amends PLAN §7's permissions onboarding.
1. Accessibility (required).
2. Screen Recording (optional, explained as "pictures of windows while they move", then the relaunch prompt).
3. "Turn off what conflicts": one button that switches off macOS edge tiling, click-wallpaper-to-reveal-desktop and Stage Manager, using the PLAN §7 backup/restore rules. Settings has a "Turn back on" button.
4. A **getting-started card** anchored under the menu-bar icon. It shows one move at a time (dock a window, resize at a seam, zoom out, zoom in, double-click to focus, make a tab group) and advances by itself when the user actually performs each move (detected from model events). It can be skipped and restarted from Settings.
- **AC:** the card advances only on the real action; skipping hides it permanently until restarted.

### B19. Settings window [Docs/All shortcuts "change any of these in Settings"; Docs/The menu bar; Docs/Set up]
**SUPERSEDES** PLAN §7 "Settings: … The Settings window shows the config, has an 'Open config' button" (viewer only) and PLAN P8's "Settings UI (config viewer …)" (D2).
- **Native AppKit Settings window** (toolbar-style tabs, standard controls, PLAN §7 native look). Panes, named our own way:
  - **General:** permission status, start at login, conflicting macOS features off/back on (B18), restart getting started.
  - **Layout:** gaps, animation duration, Reduce Motion note, desktop region per workspace.
  - **Mouse & Trackpad:** `pinch-modifier`, `frame-modifier`, `[mouse]` double-click actions, `[focus-follows-mouse]`.
  - **Menu Bar:** `menu-bar-controls` (checkboxes plus a drag-to-reorder list), `[borders]`.
  - **Apps & Rules:** the `[[rules]]` list, with add/edit/remove and "Leave <app> alone".
  - **Shortcuts:** a recorder for `[mode.main]`, plus `[modifiers]` sides.
  - **Workspaces:** `workspaces`, `[workspace-to-display]`.
- **Shortcut recorder:** records in our own window via a local `NSEvent` monitor (no tap needed), shows conflicts with other bindings and known system shortcuts, and writes the Dinky key syntax (`ctrl-alt-…`). "Restore default" writes the B11 binding.
- **Writes go to the TOML file; the TOML stays the source of truth.**
  - Use a **format-preserving TOML editor** (a concrete-syntax-tree layer for the subset we write) that edits a key's value in place, inserts missing keys into the right table, and appends tables or `[[rules]]` entries, keeping every comment, blank line and key order.
  - Each edit re-reads the file, applies one minimal patch, validates the result with the config loader, then writes atomically. If validation fails, nothing is written and the pane shows the error.
  - If the file is currently invalid (an external edit), Settings becomes read-only, shows the key-path error and offers "Open config".
- **Reload reflects in the UI:** the existing file watch reloads the config, and every open pane re-renders from the new config within 1 s. External edits win; there is no UI-side cache.
- **Tests:** CST editor golden tests (comments preserved, inline tables, arrays of tables, CRLF), round-trip of the default config, conflict detection, validation-blocked writes.
- **AC:** after changing any setting in the UI, `diff` shows only the edited line(s); hand-editing the TOML while Settings is open updates the pane; a recorded shortcut works immediately.

---

## D. Resolved decisions (Adrian, 2026-10-18)

Each decision lists what it supersedes. PLAN.md and ADDENDUM.md are unchanged on disk; this file takes precedence where stated.

- **D1. Launch and new windows: follow the site.** Nothing moves at launch, new windows float in the desktop region, docking is manual, and there's a "Dock all windows" item (B1).
  - Supersedes PLAN §7a `default-tiling = true` (now `false`), PLAN P4 "auto-insert new windows" and its QA "New window tiles; closing reflows" (closing still reflows docked neighbours).
- **D2. Settings window, writing the TOML** (B19).
  - Supersedes PLAN §7's viewer-only Settings and P8's "config viewer".
  - The ADDENDUM's "append-rule helper" becomes part of the editor.
- **D3. Default shortcuts: the site's Control-Option set** (B11 table). Workspaces use `ctrl-alt-cmd-1…9` and `ctrl-alt-cmd-shift-1…9`.
  - Supersedes the unspecified first-run `[mode.main]`. Dinky's default bindings are not used.
- **D4. Modifier-drag is frame-rect only:** `frame-modifier = 'cmd-shift'` (B4).
  - Supersedes PLAN §6/P5 modifier-drag move/dock and PLAN §7a `drag-modifier`, which are removed.
- **D5. `pinch-modifier = 'alt'`** (B9).
  - Supersedes PLAN §7a's default `'ctrl-alt'`.
- **D6. No separate overview.** "Everything" is the camera over real windows (B6), and ScreenCaptureKit takes only one still per window per motion (B12).
  - Supersedes PLAN §6 "Previews" (live `SCStream`), §7a `overview-previews`, P7's "zoom-out overview", "`overview-previews` (auto power-source detection…)", the power-source tests and the desktop-vs-laptop QA, and the `overview` command.
  - Also supersedes ADDENDUM A2's "Overview" item.
- **D7. Title-bar double-click applies to docked windows only** (B14).
  - Supersedes ADDENDUM-2's earlier B14 draft. ADDENDUM A1 already matches.
- **D8. Green button toggles dock/float, swallowing the click; Option-click keeps macOS behaviour** (consistent with the site), and it is P5a-gated with stock-macOS fallback (B15).
  - Extends the safety-net list in PLAN §6 (with ADDENDUM A1). The full gated list is: ⌘⇧-drag frame-rect over apps, Option-pinch over apps, `[modifiers]` left/right sides, double-click gestures, and the green button.
- **D9. macOS Spaces: numbered workspaces stay core** (PLAN P6), deliberately unlike the site, which leaves Spaces to macOS (B16).
- **D10. No shipping at all.**
  - **Removed from scope:**
    - Everything in PLAN §2 "Distribution" except the open-source repo.
    - The Sparkle dependency (§2), §7 "Updates", and the Sparkle menu and settings items.
    - P9's notarization, hardened-runtime release signing, DMG, GitHub Releases, appcast generation and signing, the release workflow, and the EdDSA and notarization secrets.
    - P9's AC about installing from GitHub Releases and updating N-1 → N.
  - **Replacement: local builds only.**
    - Sign every build with **one stable identity**: an "Apple Development" certificate from a free Apple ID, or a self-signed code-signing certificate created once in Keychain Access, kept outside the repo and referenced by name in `scripts/build-local.sh`.
    - Keep the bundle id `com.designbyadrian.lattice` and the designated requirement fixed, so Accessibility and Screen Recording grants persist across rebuilds. Ad-hoc signing changes the code identity every build, which resets the grants.
    - Document `tccutil reset Accessibility com.designbyadrian.lattice` for recovery.
  - **Kept:**
    - The **build hygiene check**, formerly the "release strings check": it guards against debug leftovers (`localhost`, `/Users/`, debug menus), so it now runs on every local Release-configuration build and in CI.
    - P9's onboarding and native-look tasks.
    - Public CI (build and test only), LICENSE (MIT) and CONTRIBUTING (PLAN P0).

## R. Clean-room command renames (supersede PLAN §7a and ADDENDUM names)

Our names must not match the vendor's URL command names (from [Docs/Commands by URL]: everything, zoom-out, zoom-in, back, forward, neighbour, frame-window, frame-desktop, toggle-desktop, view, save-view, split-finder, arrange, float-all, settings).

| Old (PLAN/ADDENDUM/ADDENDUM-2 draft) | New | Note |
|---|---|---|
| `view <n>` | `recall-view <n>` | PLAN §7a |
| `save-view <n>` | `store-view <n>` | PLAN §7a |
| `float-all` | `unmanage-all` | PLAN §4 `floatAll` op → `unmanageAll`; ADDENDUM-2 draft `float-everything` also replaced |
| `overview` | removed | D6; use `zoom all` |
| `desktop toggle` (ADDENDUM-2 draft) | `desktop-area <show\|hide\|toggle>` | avoids the vendor's toggle-desktop / frame-desktop forms |
| `split-new <app>` | unchanged | ours; not the vendor's split-finder |
| `dock-all` | unchanged | ours; the vendor's command is "arrange" |
| `zoom <in\|out\|all\|window\|desktop>`, `history <back\|forward>`, `pan <dir>` | unchanged | verb + argument form, distinct from the vendor's hyphenated single-word URLs |

URL scheme (PLAN §7): `lattice://run?cmd=<command>` uses these names. No vendor names appear in commands, keys, menu titles or strings.
