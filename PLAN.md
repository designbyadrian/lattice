# PLAN: Lattice, a clean-room, open-source macOS tiling window manager

## 0. Clean-room rules (read first)
- Same rule for reference projects (e.g. mikker/Dinky, MIT, at /workspace/dinky). Read them for approach only and re-derive from Apple headers and public reverse-engineering notes. Never paste code or constants tables; if a constant must match, cite its origin in a comment.
- **Exception: the config file format deliberately matches Dinky's TOML format** (§7a). Matching a file format/interface is fine. Implement our own parser and validation, and credit it in README/About: "Config format compatible with Dinky by Mikkel Malmberg (MIT)". Don't copy Dinky's source, docs prose or default-config comments verbatim.
- Do NOT copy code, assets, icons, names, UI strings, settings keys, or URL commands from TrellisWM. **Layout behaviour** (§4–5) is recreated from TrellisWM's *observed* behaviour (REPORT.md, its public site): a nested tree, docking, a zoom camera, history and motion. Implement it independently with our own names, numbers and wording. Write code from public Apple docs and general knowledge only.
- Dinky's layouts (tiles/dwindle/accordion/fixed/scrolling) are **not** used. We take only Dinky's config format, rules, workspaces model and command grammar.
- Bundle id `com.designbyadrian.lattice`, URL scheme `lattice://`; use our own terminology and visual design.

## 1. Goal / non-goals
**Goal:** a native, menu-bar macOS 14+ window manager. It arranges real windows into a nestable layout tree (splits, tabs, floating), with numbered workspaces backed by native macOS Spaces, smooth animated transitions, keyboard and drag control, a zoom-out overview, per-display persistence, URL scripting and auto-updates. Free and open source.

**Non-goals (v1):** Mac App Store build, Intel Macs, tiling windows inside full-screen Spaces (they are detected and left alone, see P4), disabling SIP or injecting into Dock, **any permission beyond Accessibility (+ optional Screen Recording). The goal is that Input Monitoring is never requested (UNVERIFIED, see the P5 spike)**, licensing/paid tiers/window limits, Windows/Linux ports, plugins, cloud sync, telemetry, accounts.

## 2. Tech stack
- Swift 6 with strict concurrency, SwiftPM (an Xcode project only for the app target, signing and archiving), **AppKit throughout**, including the Settings window (standard AppKit controls/`NSGridView`/`NSTabViewController` toolbar-style Settings).
- macOS 14+, arm64 only (Apple silicon).
- Dependencies: Sparkle 2 (updates) and a TOML decoder (e.g. dduan/TOMLDecoder, or another maintained MIT/Apache TOML 1.0 library; pin the exact version). Nothing else in v1.
- Testing: XCTest or Swift Testing. Pure model/engine tests run on CI (`swift test`) without a GUI.
- Distribution: open source on GitHub. Releases are Developer ID signed, hardened runtime, notarized and stapled DMGs on **GitHub Releases**, with Sparkle updates from an EdDSA-signed appcast (hosted on GitHub Pages or as a release asset).
- Licence: **MIT** (confirmed), matching Dinky. Credit Dinky (MIT) for the config format in README/About/NOTICE.

## 3. Module layout (SwiftPM)
```
Packages/
  LayoutModel/    pure Swift, no AppKit. Geometry types, layout tree, operations, Codable. 100% unit-tested.
  LayoutEngine/   pure Swift. Solves tree -> frames, camera/zoom, navigation history, animation timing curves (math only).
  Platform/       protocols only: WindowServerProtocol, WindowRef, DisplayRef, InputEvents, Permissions.
  PlatformMac/    AppKit/AX/CG/SCK implementations of Platform. Private-API shims live in PlatformMac/Private (SkyLight Spaces: core, runtime-checked) and PlatformMac/Experimental (flagged extras).
  Config/         pure Swift: TOML → typed Config (Dinky-compatible schema §7a), validation errors with key paths, command-string parser.
  AppCore/        coordinator: wires engine <-> platform, settings, persistence, URL commands. Testable with a FakePlatform.
App/              menu-bar app target: AppDelegate, status item, settings UI, onboarding, Sparkle.
Tests/            unit tests per package + FakePlatform integration tests.
```
Rule: LayoutModel, LayoutEngine and Config import Foundation (+ the TOML decoder) only. AppCore depends on the Platform protocols, never on PlatformMac directly.

## 4. Data model (LayoutModel)
- `Rect`, `Size`, `Point`, `Edge {left,right,top,bottom}`, `Axis {horizontal,vertical}`.
- `WindowID` (stable app-level id): CGWindowID when available, plus a pid/bundle-id/title fingerprint for re-matching after relaunch.
- `indirect enum Node: Codable`:
  - `.split(SplitNode)`: axis, children `[Node]`, ratios `[Double]` (sum 1, each ≥ minRatio).
  - `.panel(PanelNode)`: one window.
  - `.tabs(TabNode)`: ordered windows plus selected index.
  - `.desktop`: the free area of the arrangement. A fresh workspace is just `.desktop`. Docking a window to a screen edge splits it off beside the desktop area, which shrinks but stays (at most one per workspace; it can be hidden per workspace). Floating windows sit over it.
- `Workspace`: `root: Node`, `floating: [FloatingWindow(id, frame)]`, `excludedApps: Set<BundleID>`, `camera: Camera(focusPath, zoom)`.
- `DisplayLayout`: keyed by **display UUID** (`CGDisplayCreateUUIDFromDisplayID` string). Contains its workspaces' trees, schemaVersion, savedViews[1…9]. A workspace's tree moves with the workspace when it changes display.
- Operations (pure, return new value + diff): `insert(window, at: DropTarget)` (neighbours make room), `remove(window)` (siblings absorb the space; option: share it across the whole row), `move`, `swap`, `resize(divider, delta)` (resizing at a seam changes only the two neighbours), min-size clamping, `tab(window, onto:)`, `untab`, `float`, `dock`, `floatAll`, `normalize()` (collapse single-child splits, drop empty nodes). Nesting depth is unlimited.
- `DropTarget`: `.edge(nodePath, Edge)` (dock beside a window or group), `.center(nodePath)` (hold to make a tab group), `.screenEdge(Edge)` (dock beside everything in view).
- Suspension: `WindowState {active, minimized, fullscreen, hidden}`. A suspended window keeps its tree slot but takes no space in `solve`; on resume it gets its old slot back.
- **Rules:** `WindowRule { appId?, appName?, title?, kind?, run: [Command] }` exactly as in the config (§7a). `WindowFacts { bundleID, appName, title, kind, resizable, fullscreenButtonEnabled, closeButtonEnabled }`. `RuleEngine.classify(facts, rules, config) -> (floating: Bool, commands: [Command])` is pure, following the semantics in §7a.
- **Workspaces:** `WorkspacePlan` (count, workspace→display patterns), `binding: [Int: SpaceID]`, `ownedSpaces: Set<SpaceID>` (Spaces Lattice created). There is one `Workspace` (tree + camera + history) per number, and each display shows the workspace bound to its current Space. A window dragged to another display joins that display's current workspace.
- No plan or limit types. Every feature is available to everyone.
- Invariants (asserted in tests): every window appears at most once; ratios are valid; no empty splits after normalize; the tree round-trips through Codable.

## 5. Engine (LayoutEngine)
- `solve(workspace, displayRect, gaps, minSizes) -> [WindowID: Rect]`. Deterministic, integral pixel rounding, respects per-window min sizes (overflow strategy: shrink siblings, else float).
- Camera: a path into the tree plus zoom. Zoomed in, the focused node fills the display; zoomed all the way out, the whole tree is in view. Operations: `stepIn(towardPoint)`, `stepOut()` (one nesting level at a time), `frameAlone(window)`, `showAll()`, `frameRect(rect)` (zoom to fit a dragged rectangle). `framesAt(camera)` maps tree frames through a scale/translate. Windows outside the view are parked just off-screen; this is reversible.
- Collapse: when zoomed out, a window below a legibility threshold renders as an app-colour + icon tile, and a group below the threshold becomes one tile drawn with its split lines. Activating the tile steps in.
- Navigation: back/forward stack of camera states per workspace, plus saved views 1–9 per display.
- Animation math: one shared layout motion (our own curve and duration, tuned in P7) for split, dock, close and zoom. Interpolates frame maps and is interruptible (retarget mid-flight; a click during an animation ends it).

## 6. Platform layer (PlatformMac)
- **Window control (AX):** `AXUIElementCreateApplication`, kAXWindowsAttribute, set kAXPosition/kAXSize (size→position→size order), `AXObserver` for created/destroyed/moved/resized/minimized/focused/title. Use a per-app AX timeout (`AXUIElementSetMessagingTimeout` ~0.25 s) and a serial queue per app so one slow app can't stall the rest.
- **Window id:** public route first (match AX window to `CGWindowListCopyWindowInfo` by pid + frame + title). `_AXUIElementGetWindow` is only allowed behind the `experimental.axWindowID` flag, with that fallback.
- **Discovery:** `CGWindowListCopyWindowInfo(.optionOnScreenOnly)` with layer 0 filtering. Filter AX subrole (`AXStandardWindow`), ignore sheets/dialogs/popovers.
- **Observers:** NSWorkspace launch/terminate/activate/hide/unhide, activeSpaceDidChange, didWake, screen-parameter changes (rebuild displays, re-key by UUID).
- **Input:**
  - **Input rule:** use **one active event tap** (`kCGEventTapOptionDefault`, `.cgSessionEventTap`, head insert) from the Accessibility-trusted process. Its mask covers mouse down/up/dragged/moved, scroll, gesture/magnify, `flagsChanged`, and keyDown/keyUp when key bindings need it. **Never create a listen-only keyboard tap**, because listen-only keyboard taps are what trigger Input Monitoring. The goal remains **no Input Monitoring prompt**. The claim that an active tap from an AX-trusted process needs no Input Monitoring (precedent: yabai's mouse tap, skhd) is **UNVERIFIED** until the P5a spike passes.
  - **Callback budget:** the tap callback only classifies the event and returns it (pass through) or nil (swallow) within about 1 ms. All real work goes async to the main or engine queue. No AX calls, I/O or locks in the callback.
  - **Timeouts:** on `kCGEventTapDisabledByTimeout`/`…ByUserInput`, re-enable immediately with `CGEventTapEnable`, count the occurrences, and log them. If it repeats more than N times a minute, show a menu warning.
  - **Key bindings:** `[mode.<name>]` bindings are matched in the tap. That lets them tell left and right modifiers apart (device-dependent flag bits) to honour Dinky's `[modifiers]`, and they swallow only bound keys. Fallback: Carbon `RegisterEventHotKey` (no side distinction) when the tap is unavailable.
  - **Modifier-drag over app windows:** with the configured modifier held, mouse-down/drag over any window is swallowed (the app gets no click) and drives move/dock or `frame-rect`. Without the modifier, everything passes through untouched.
  - **Pinch over app windows:** with the configured modifier held, magnify gestures over any window are swallowed and drive the zoom camera. Without the modifier, pinch works on bare desktop and in our overview, and passes through elsewhere.
  - **Window drags (title bar, no modifier):** AX moved notifications plus mouse events, passed through. The real window moves normally; we show drop overlays and act on mouse-up.
  - **Our own overlays:** transparent non-activating panels for seam resize handles and the overview.
  - **Focus-follows-mouse:** mouse-moved from the same tap (pass-through), then AX focus after the delay (§7a).
  - **Per-OS safety net:** if tap creation fails or Input Monitoring is prompted on a macOS version (the P5a matrix), Lattice disables **only** these three features there: modifier-drag swallowing, pinch over app windows, and left/right modifier distinction. Bindings fall back to Carbon hotkeys, focus-follows-mouse falls back to an `NSEvent` global mouse-moved monitor, and the menu shows a notice. Nothing else is affected.
  - Raw multitouch only behind the `experimental.multitouch` flag.
- **Spaces (core, P6):** SkyLight queries and bridged operations in `PlatformMac/Private/Spaces`. Load everything via `dlsym`/`objc_getClass` with nil checks, never hard-link. A capability probe at launch decides between `SpacesBackend.native` and `.currentSpaceOnly` (the safety net; see P6).
- **Previews (optional, need Screen Recording):** config `overview-previews = 'auto' | 'live' | 'snapshots' | 'off'` (default `'auto'`).
  - `auto`: detect the machine type with `IOPSCopyPowerSourcesInfo`/`IOPSCopyPowerSourcesList`. **No internal battery (a source with `kIOPSTypeKey == kIOPSInternalBatteryType`) means a desktop**, which gets live `SCStream`s per visible window. A laptop gets periodic `SCScreenshotManager` snapshots: on overview open, then about every 1–2 s while it stays open.
  - Laptop on mains: **guess, defaults to snapshots** (no switching on power-source changes in v1; revisit after measuring).
  - `off`, or Screen Recording denied: app-colour + icon tiles.
  - Previews are captured only while animating or during the overview. Never write frames to disk.
- **Overlays:** borderless non-activating `NSPanel`s at an appropriate level for drop indicators, the overview and tab strips.
- **Borders (optional, off by default):** our own borderless, click-through (`ignoresMouseEvents`), non-activating overlay windows. Each tracks its managed window's frame (AX moved/resized and the animation frame stream), sits just below or above it per `order`, and is hidden for floating-excluded apps, full-screen windows and the overview. Public APIs only.

## 7. Cross-cutting
- **Permissions onboarding:**
  1. Welcome.
  2. Accessibility: `AXIsProcessTrustedWithOptions(prompt)`, deep-link to the Settings pane, poll until granted and auto-advance.
  3. A note that no Input Monitoring is needed (if the P5a spike shows a prompt on this OS, explain the reduced features instead).
  4. Optional Screen Recording: `CGPreflightScreenCaptureAccess`/`CGRequestScreenCaptureAccess`, explaining the relaunch is required. Relaunch via `NSWorkspace.openApplication` from a tiny helper or `open -n` spawned with argv (no `sh -c` string building).
  5. Quick tutorial (native views, bundled; no web server).
  Re-check on wake/launch and show a menu warning if revoked.
- **Visual design: native macOS.**
  - Materials: system materials (`NSVisualEffectView`: `.hudWindow`/`.popover`/`.sidebar`/`.menu`) for overlays, the overview, HUDs and tab strips.
  - Colour and type: the system accent colour (`NSColor.controlAccentColor`) for focus, drop targets and selection; SF Symbols for all icons, including the menu-bar icon (a template image); standard AppKit controls and fonts.
  - Appearance: follows light/dark automatically.
  - Accessibility settings:
    - **Reduce Motion** turns animations into fades or jumps.
    - **Reduce Transparency** swaps materials for opaque `windowBackgroundColor`.
    - **Increase Contrast** draws thicker, higher-contrast outlines and drop targets.
  - No custom-themed chrome.
- **Animation:** drive window frames via AX at display refresh (CVDisplayLink/`NSScreen.displayLink` on 14+), capped and coalesced per window. Optionally hide the real windows behind snapshot proxies during big moves and set final frames at the end. Target ≤ 300–450 ms, interruptible.
- **Settings:** the TOML config file (§7a) is the single source of truth for behaviour: workspaces, rules, bindings, gaps, animations. `UserDefaults` holds only app/UI state: onboarding done, update-check preference, window positions of our own panels, cosmetic Settings-UI prefs. The Settings window shows the config, has an "Open config" button, and "Add rule for <frontmost app>" **appends** a `[[rules]]` block (it never rewrites the file, so comments survive) and then reloads.

### 7a. Config file (Dinky-compatible)
- **Location:** `~/.config/lattice/lattice.toml` (Dinky uses `~/.config/dinky/dinky.toml`). It is written with commented defaults on first run and reloaded on save (file watch).
- **Validation:** every key is optional; a missing key keeps its default. Keys are kebab-case. **Unknown keys are errors.** A broken config doesn't load: the previous config stays and the error, with its key path (e.g. `rules[0].app-id`), shows in the menu.
- **Schema and tooling:** ship a JSON Schema and put a Taplo `#:schema <url>` line at the top for editor completion. `lattice doctor [--config <path>]` (CLI, P8) checks the config.
- **Top-level keys (Dinky names, our defaults):**
  - `start-at-login = true`
  - `workspaces = 1` (Dinky's default is 5): the number of workspaces across all displays, one native Space each.
  - `default-tiling = true`
  - `follow-app-activation = true`
  - `float-windows-without-fullscreen = true`
  - Lattice extension: `overview-previews = 'auto'` (§6).
  - Dinky's `default-layout` is **not supported**; using it gives a clear error ("Lattice has a single tree layout").
- **Other Dinky tables:**
  - `[workspace.<n>]`: `tiling` only. Dinky's `layout`/`columns`/`rows`/`expand` are not supported.
  - `[workspace-to-display]`: `<n> = 'main' | 'secondary' | '<display-name substring>'`, or a list tried in order. Unlisted workspaces, and listed ones whose display isn't connected, live on the main display. Numbers must be in 1…`workspaces`.
  - `[gaps]`: `inner`, `outer`, each a number or a per-side table.
  - `[display.<pattern>]`: per-display gaps. Name patterns beat `main`/`secondary`, and longer beats shorter.
  - `[animations]`: `enabled`, `duration-ms`; off under Reduce Motion.
  - `[drag]`: `placeholders` (show drop overlays).
  - `[modifiers]`: `alt`, `ctrl`, `cmd`, `shift`, each `'both' | 'left' | 'right'` (default `'both'`). This decides which physical key counts as that modifier in bindings, so the other side keeps typing special characters. It needs the active tap and is ignored, with a notice, under the safety net.
  - Lattice extension in the same table: `drag-modifier` and `pinch-modifier` (key names as in bindings, e.g. `'alt'`, `'ctrl-alt'`). They default to `'alt'` and `'ctrl-alt'` respectively; final values are picked in P5 to avoid common app conflicts.
  - `[hooks]`: `startup`, `workspace-changing`, `workspace-changed`, `focus-changed`, `mode-changed`.
  - `[mode.<name>]`: bindings in the form `alt-shift-h = 'command'` or a list. US-layout key names, starting in mode `main`.
  - `[focus-follows-mouse]` (Dinky keys): `enabled` (default `false`, same as Dinky), `delay-ms` (default `100`, how long the pointer must rest), `accordion-edges` (accepted for compatibility; no effect, since Lattice has no accordion). Same behaviour as Dinky: it only focuses managed windows; it is ignored while a mouse button is down or a menu is open, and after Cmd-Tab or a Space change until the pointer moves to another window. Dinky has **no per-app exception key**, so Lattice adds the extension `exclude-apps = ['<bundle id>', …]` in the same style as `[borders] exclude-apps`. It is implemented via the tap's mouse-moved events → hit-test our model → AX raise/focus after the delay.
  - `[borders]` (Dinky key names): `enabled` (Lattice default **`false`**; Dinky defaults to `true`), `width` (`4` points, may be fractional), `active-color` (focused window; default `'accent'`), `inactive-color` (default `'#494d64'`, Dinky's default), `order` (`'below'` | `'above'`, where above is a click-through ring), `exclude-apps` (bundle IDs). Colours are `'#rrggbb'` or `'#rrggbbaa'`; Lattice adds the extension value `'accent'` (system accent colour, live-updating). Under Increase Contrast the width becomes at least 2 points larger.
- **Dinky tables not supported:** `[scrolling]` and `[accordion]` (never; no Dinky layouts). They are reported as "not supported", not as unknown-key typos.
- **Rules: `[[rules]]`** (Dinky semantics, matched exactly):
  - Fields: `app-id` (bundle ID, exact, case-sensitive); `app-name` and `title` (case-insensitive regex, NSRegularExpression, matched anywhere); `kind` (`'normal'|'dialog'|'sheet'|'panel'`); `run` (**required**: a command string or a list).
  - Every rule whose set conditions all match a **new** window runs, **in file order**. An invalid regex or a missing `run` is a load error. Commands that fail to parse are skipped.
  - A rule command that is exactly `layout floating` or `layout tiling` decides before placement, and the last one wins. Every other command runs on the window after it is placed.
  - `kind` comes from the AX subrole: AXStandardWindow→normal, AXDialog/AXSystemDialog→dialog, AXSheet→sheet, anything else→panel.
  - Dialogs, sheets, panels and non-resizable windows always float.
  - With `float-windows-without-fullscreen`, a normal window whose full-screen button is missing or disabled floats unless a `layout tiling` rule says otherwise (AeroSpace heuristic). Keep our own small exemption list for apps whose title bar can be hidden (terminals/editors), each with a comment explaining why.
  - New windows open on the focused display unless a rule moves them.
  - Example:
    ```toml
    [[rules]]
    app-id = 'com.apple.Music'
    run = ['layout floating', 'move-window-to-workspace 2']
    ```
- **Earlier rule actions mapped to this format:**
  | Earlier action | Dinky equivalent | Status |
  |---|---|---|
  | float | `run = 'layout floating'` | native |
  | force tile | `run = 'layout tiling'` | native |
  | default workspace | `run = 'move-window-to-workspace <n>'` | native |
  | match by subrole | `kind = …` | native (coarser) |
  | match by app name | `app-name = '<regex>'` | native (new to us) |
  | never manage | `run = 'ignore'` | **extension** (Lattice command; pre-placement, like `layout floating`, but never tracked) |
  | tile into edge | `run = 'dock <left\|down\|up\|right>'` | **extension** (post-placement, inserts at that screen edge) |
  | tile into named slot | none | **dropped** (edge docking covers it) |
  | min size | `run = 'min-size <w> <h>'` | **extension**. Also learn min sizes automatically from AX clamping, like Dinky (`clear-minimum-sizes`) |
  | open as tab | `run = 'tab-with <focused\|app-id>'` | **extension**. `join-with <dir>` is accepted and makes a split container with the neighbour |
  | priority/specificity | file order, all matches run, last float/tile wins | **dropped** (Dinky semantics) |
- **Lattice-only keys/commands:** extension commands in `run`/bindings are flagged as such in the schema description. Lattice-only tables (e.g. `[overview]`, `[tabs]`) live under their own names and are documented as extensions. A Dinky config's `[[rules]]`, `workspaces`, `[workspace-to-display]`, `[gaps]` and `[mode.*]` sections must parse unchanged, apart from commands we haven't implemented, which are reported clearly.
- **Commands:** one command grammar (Dinky's string syntax: `verb arg… --flag`; a list of values toggles or cycles), shared by bindings, rules, hooks, the URL scheme and the CLI.
  - From Dinky, kept: `workspace <n|prev|next>`, `workspace-back-and-forth`, `move-window-to-workspace <n|prev|next> [--follow]`, `move-window-to-display <next|prev> [--follow]`, `focus <left|down|up|right>`, `move <dir>`, `join-with <dir>`, `resize <smart|width|height> <±n>`, `balance-sizes`, `flatten-workspace-tree`, `retile`, `clear-minimum-sizes`, `mode <name>`, `reload-config`, `enable <on|off|toggle>`, `list-*`, `exec-and-forget` (not via URL).
  - `layout` keeps only `floating|tiling` (e.g. `layout floating tiling` toggles). Dinky's layout names give a "not supported" error.
  - Lattice tree commands (extensions):
    - `split <horizontal|vertical>`: wrap the focused window in a split with the next new window.
    - `dock <left|down|up|right> [--screen]`: dock beside the neighbouring node, or at the screen edge.
    - `tab-with <dir|focused|app-id>`, `untab`, `tab <next|prev>`.
    - `zoom <in|out|all|window>` (Dinky's `fullscreen` = alias of `zoom window`), `frame-rect` (opens the overlay to drag a rectangle; a modifier-drag on empty space does the same).
    - `history <back|forward>`, `view <1-9>`, `save-view <1-9>`.
    - `overview`, `float-all`, `ignore`, `min-size <w> <h>`.
- **Persistence:** `~/Library/Application Support/<bundle-id>/layouts/<displayUUID>.json`, atomic writes, schemaVersion + migrations, debounced saves. Use `FileManager.temporaryDirectory`/`NSTemporaryDirectory()` only, **never fixed /tmp paths**.
- **macOS settings changes (e.g. disabling native edge tiling):**
  - Opt-in only, with an explicit prompt.
  - Record originals in `Application Support/.../system-prefs-backup.json` before writing.
  - Restore on quit (`applicationWillTerminate`), on "Disable", on crash-next-launch (backup exists but app not running cleanly → offer restore), and via a menu "Restore macOS settings & quit" (the uninstall path). Document it in the README.
- **Safe quit:** on quit or crash recovery, move all managed windows to visible on-screen frames.
- **URL scheme `lattice://`:** `lattice://run?cmd=<url-encoded command string>` (e.g. `workspace%202`), plus short aliases for common commands (`lattice://workspace/2`). Parse into the same `Command` enum as bindings and rules. `exec-and-forget` is **not** allowed via URL (it would let any web page run shell commands). Reject unknown params.
- **Logging:** `os.Logger` with subsystems, no PII in logs. "Report a problem" builds a zip in a temp dir and opens a mail draft; nothing is uploaded.
- **Release hygiene:** `#if DEBUG` gates all dev URLs/menus. A CI script fails the release build if `strings` finds `localhost`, `127.0.0.1`, `/Users/` or debug flags (strip `-debug-prefix-map`/`-file-prefix-map` to remove build paths).
- **Updates:** Sparkle 2, EdDSA-signed appcast over HTTPS from GitHub. The EdDSA private key and the notarization credentials are GitHub Actions secrets (backed up in 1Password), never in the repo. The user can turn off automatic checks.

## 8. Phases (each ends green on CI)

**P0 Skeleton**
- Tasks:
  - SwiftPM packages per §3; app target (LSUIElement, status item, Quit); DEBUG/RELEASE configs; release-strings check script.
  - Public GitHub repo hygiene: `LICENSE` (MIT), `NOTICE`/README credit to Dinky (MIT) for the config format, `CONTRIBUTING.md` (clean-room rule, no TrellisWM material, tests required, code style), issue/PR templates, `SECURITY.md`.
  - Public CI on GitHub Actions (`swift build`, `swift test`, swift-format/lint) on macOS arm64 runners for every PR.
- AC: the app launches to the menu bar; public CI is green on PRs; the release strings check passes; LICENSE/CONTRIBUTING are present.

**P1 Layout model**
- Tasks: §4 types and operations, Codable, normalize.
- Tests: property-style tests (random op sequences keep invariants); insert at every DropTarget; remove→siblings absorb; seam resize touches only the neighbours; desktop area kept on screen-edge docks; resize clamping; tab/untab; floatAll; deep nesting (depth 20); round-trip encode; snapshot of solved frames.
- AC: ≥ 95% line coverage on LayoutModel.

**P2 Engine**
- Tasks: solver, gaps, min sizes, camera (stepIn/stepOut/frameAlone/showAll/frameRect), collapse thresholds, navigation history and saved views, animation curves and interpolation.
- Tests: golden frame tables for 1–8 windows on several display sizes; rounding has no gaps or overlaps (within the gap tolerance); camera zoom maps the focused node to the screen; stepIn/stepOut round-trip; collapse thresholds; history back/forward; interruption retargets smoothly (monotone tests).
- AC: solving 200 windows takes < 2 ms on M1 (benchmark test).

**P3 Platform: read**
- Tasks: permissions check, display enumeration and UUIDs, window discovery (CGWindowList + AX), observers, FakePlatform for tests.
- Tests: unit tests for filtering logic using recorded fixtures (JSON dumps of CGWindowList/AX attributes).
- Manual QA: lists windows of Safari, Finder, Terminal, Xcode, VS Code (Electron), Slack, a Java app; ignores sheets, popovers, Spotlight, menu extras.

**P4 Platform: write + coordinator (MVP tiling)**
- Tasks: AX frame setting with per-app queues/timeouts, AppCore applying solved frames, auto-insert new windows, removal on close/minimize, exclusion list, "float all" escape hatch, safe quit restore.
- Manual QA checklist:
  - New window tiles; closing reflows.
  - Minimize/restore returns to its slot.
  - App hide/unhide works.
  - Windows with min size (System Settings, Calculator) float or clamp correctly.
  - Hung app (SIGSTOP a test app) doesn't block others.
  - Multi-monitor plug/unplug re-keys layouts.
  - Quit leaves all windows on-screen.
  - Electron and Java windows move.
- AC: 30-min dogfood session without a stuck window.

- **Full-screen handling (added to P4):**
  - Observe `kAXFullScreenAttribute` ("AXFullScreen") plus window moved/resized events, and re-check on activeSpaceDidChange.
  - On enter: mark the window `.fullscreen`, keep its tree slot, and let siblings reflow temporarily. On exit: resume into the same slot and re-solve.
  - A full-screen Space is never a workspace. Hotkeys that move or tile do nothing there (show a beep or HUD), it shows no drop targets, and the overview skips it.
  - When the P6 native backend is active, detect full-screen Spaces directly from the Space type in the managed-display-spaces query and use that rather than the AX heuristic.
  - If an app quits while full-screen, remove the window and normalize. On display unplug while full-screen, macOS moves the Space, so re-key and resume on exit to whichever display it lands on.
  - Tests: `suspend/resume` restore the identical tree (unit); the solver ignores suspended windows.
  - Extra manual QA:
    - Safari video full screen (the element, not the window) and exit.
    - Green-button full screen and exit.
    - Keynote presenting (presenter display + audience display) leaves the layout untouched and restores it after.
    - Unplug a display while a window is full-screen on it.
    - Quit the app while full-screen (layout closes the gap).
    - Hotkeys inside a full-screen Space do nothing.

**P5 Input + config loader**
- Tasks:
  - Config package: TOML load, unknown-key errors, key-path messages, file watch and reload, keep the last good config, first-run default file, JSON Schema. Covers top-level keys, `[gaps]` and `[mode.*]` in this phase.
  - Command-string parser.
  - **P5a spike (required checkpoint, before the input work merges):** on clean macOS 14, 15, 26 and 27 VMs, with a **fresh user account** and only Accessibility granted:
    - create the active tap (mouse + gesture + flagsChanged + keyDown/keyUp);
    - confirm creation succeeds and events can be swallowed;
    - confirm **no Input Monitoring prompt** appears and Lattice is not listed under Privacy & Security → Input Monitoring.
    `CGPreflightListenEventAccess` is irrelevant here (it covers listen access); don't use it as the signal. Record results in `docs/input-matrix.md`. A failing version gets the per-OS safety net (§6), and the matrix needs Adrian's sign-off.
  - Active tap module: callback budget, timeout re-enable, per-OS safety net, capability state in the menu.
  - `[mode.<name>]` bindings matched in the tap, with `[modifiers]` left/right sides, swallowing only bound keys, conflict detection and `mode <name>` switching. Carbon hotkey fallback.
  - Modifier-drag over app windows (swallowed) → move/dock/`frame-rect`. Title-bar drag-to-dock with drop overlays (hold over a centre target → tab). Seam resize via our own overlay handles.
  - Pinch: with `pinch-modifier` over any window (swallowed); without it, over bare desktop and the overview.
- Tests:
  - config parsing (defaults, unknown key, bad type, key paths, last-good fallback, unsupported Dinky layout keys, `[modifiers]` values);
  - command parser (Dinky grammar, extensions, errors);
  - key-name parsing;
  - pure tap classifier: event + flags (incl. left/right device bits) + config → pass/swallow/command, including "unbound keys always pass";
  - drop-target hit-testing;
  - **a CI/unit check that the code never creates a listen-only tap whose mask includes keyboard events** (a wrapper is the only tap constructor, and it asserts this);
  - safety-net feature-disable logic.
- Manual QA:
  - the P5a matrix;
  - unbound keys and clicks always reach apps;
  - right Option still types special characters with `alt = 'left'`;
  - modifier-drag over Safari/Finder/Electron windows never delivers a click to the app;
  - modifier-pinch over Safari zooms Lattice, not the page;
  - typing latency is unaffected (callback timing log is under 1 ms at p99);
  - tap recovers after a forced timeout (busy-loop test build).

**P6 Numbered workspaces on native Spaces (core, always on; SIP stays on)**
Approach is clean-room, informed by Dinky's README/RESEARCH and the yabai/mimi precedent it cites.
- **P6a Spike gate (required checkpoint before the rest of P6 merges):** run on SIP-on macOS 14 (latest patch), 15, 26 and 27:
  - create, adopt, bind, move and remove Spaces;
  - move windows (batch, same-app, with sheets);
  - rapidly switch 1↔5;
  - Cmd-Tab and Dock clicks;
  - Mission Control stays coherent;
  - Dock restart (`killall Dock` in a test VM);
  - display unplug and replug.
  Record the OS build for every result in `docs/spaces-matrix.md`. If an OS version fails (Dock incoherence or a lost window), the capability probe must route that version to `.currentSpaceOnly`, and the result needs Adrian's sign-off before release.
- **Config:** `workspaces` (default **1**), `[workspace-to-display]`, `[workspace.<n>] tiling` (§7a).
- **Default behaviour:** Lattice **adopts** the main display's current Space as workspace 1 (bind it, don't create anything). It creates Spaces only when `workspaces` > the number of adoptable Spaces on a target display.
- **Binding:** `[Int: SpaceID]` plus `ownedSpaces`, both persisted in Application Support. Only ordinary user Spaces are bindable; full-screen Spaces never are.
- **Reconcile planner** (pure, in LayoutModel): `step(displays: [DisplaySnapshot(uuid, nameForPatterns, spaces, current)], binding, owned, occupied, plan) -> (binding', owned', action: .create(displayUUID) | .move(from, to) | .remove(SpaceID) | nil)`.
  - Place workspaces display by display, in number order. Each goes on the first free Space after the previous workspace's Space, adopting existing unbound Spaces before creating new ones. Windows move only into empty Spaces.
  - **Remove only Spaces in `ownedSpaces` that are empty and unbound.** Never remove a Space Lattice didn't create, the current Space, or a display's last Space. This deliberately diverges from Dinky, which removes any empty unbound Space.
  - Lowering `workspaces` unbinds the extra numbers; their owned Spaces are removed only once empty.
  - Apply one action, re-snapshot, and loop until nil, capped at around 50 iterations. On a failed move, roll back the binding and retry at the next trigger. It must be idempotent.
  - Triggers: launch, config reload, and debounced (~1 s) display or Space changes. Skip while a switch is in flight. If a bound Space is briefly unlisted during display transitions, wait up to about 2 s.
- **SkyLight shim (`PlatformMac/Private/Spaces`):**
  - Queries: `SLSMainConnectionID`, `SLSCopyManagedDisplaySpaces` (also gives Space type, so full-screen Spaces are detected directly) and window→Space membership.
  - Operations: `SLSBridgedSpaceCreateOperation`, `SLSBridgedSpaceDestroyOperation` and `SLSBridgedMoveWindowsToManagedSpaceOperation`, submitted via SkyLight's internal sync/async bridged-operation dispatchers.
  - Resolve all of them at runtime. Each call returns success or failure; re-query after every action.
- **Switching:**
  - Post synthetic Dock-swipe gesture events (began/ended, very high velocity, one per step with a short delay for non-adjacent targets).
  - macOS 27+ needs the extra raw IOHID payload the Dock now reads, and its sign convention differs; keep version-gated builders with golden-byte tests.
  - The Dock swipes the display under the cursor, so **warp the cursor** to the target display and restore it after (accepted UX, as in Dinky).
  - Coalesce rapid requests to the latest target and fire the `workspace-changing`/`workspace-changed` hooks.
  - `follow-app-activation`: Cmd-Tab or a Dock click on a window in another workspace switches the fast way.
- **Window homes:** snapshot window→workspace about once a second, only while the display set has been stable. After a display unplug and replug, return displaced windows once the reconcile completes.
- **Commands:** `workspace <n|prev|next>`, `workspace-back-and-forth`, `move-window-to-workspace <n|prev|next> [--follow]`, `move-window-to-display <next|prev> [--follow]`. Rules can use `move-window-to-workspace`.
- **Safety net (not a user switch):** the capability probe runs at launch and after OS updates. If any required symbol or class is missing, or the OS version failed the spike matrix, Lattice runs `.currentSpaceOnly`:
  - it manages the current Space's windows;
  - workspace commands give a HUD saying "Workspaces unavailable on this macOS build";
  - the menu shows a persistent notice with a "Details" link;
  - it logs the OS build and the missing pieces.
  It never crashes, and never half-applies a plan.
- **On quit or disable:** keep owned Spaces (removing Spaces on quit would shuffle the user's windows). Leave windows where they are, on-screen. The menu has "Remove Lattice-created Spaces" (moves their windows to workspace 1's Space first), which is the uninstall path.
- Tests: planner unit tests:
  - default (count 1 adopts the current Space, creates nothing);
  - count 3 on one display with 1 or 5 existing Spaces;
  - user-created empty Spaces are never removed;
  - owned empty Spaces are removed after lowering the count;
  - display added/removed with pattern fallback to main;
  - occupied Spaces never get windows mixed;
  - idempotence and the iteration cap.
  Also: probe → backend selection with a fake symbol table, swipe payload encoders, switch coalescing, binding/owned persistence.
- Manual QA: the spike matrix list, plus "fresh install leaves Mission Control showing the same Spaces as before" and "Remove Lattice-created Spaces restores the original count".
- AC: passes the spike gate on every OS version marked supported, and the safety-net path is verified by forcing the probe to fail.

**P7 Animation + zoom camera + overview + previews**
- Tasks: display-link animator with the shared layout motion; proxy snapshots during big moves; camera zoom in/out/all/window, frame-rect and history wired to the platform (parking off-view windows); collapsed tiles; the overview; `overview-previews` (auto power-source detection, live vs snapshots, icon fallback); recording-indicator disclosure in onboarding.
- Tests: power-source classification with fixture `IOPS` dictionaries (desktop, laptop, laptop on mains, UPS attached to a desktop counts as no internal battery); preview-mode selection matrix.
- Manual QA: 60 fps on 10 windows (Instruments); Mac mini/Studio gets live previews and a MacBook gets snapshots; CPU/energy in Activity Monitor during a 1-min overview on a laptop is within budget; denying Screen Recording still gives a usable overview; nothing is written to disk (fs_usage spot-check); quitting while zoomed leaves every window on-screen.

**P8 Persistence, rules, scripting, tabs**
- Tasks:
  - Per-display layout save/restore with relaunch window re-matching.
  - Saved views 1–9 persisted per display.
  - Settings UI (config viewer, Open config, append-rule helper).
  - The rest of the §7a config: `[workspace.<n>]`, `[display.<pattern>]`, `[animations]`, `[drag]`, `[hooks]`; `exec-and-forget` from hooks and bindings only.
  - **Focus-follows-mouse** (`[focus-follows-mouse]` incl. `exclude-apps`), and **borders** (`[borders]`, off by default; click-through overlay windows tracking frames, `accent` colour, Increase Contrast).
  - URL scheme and `lattice` CLI (via a Unix socket in the app's container/`$TMPDIR` per user, not a fixed /tmp path): commands, `list-*`, `doctor`.
  - Tab groups with a tab strip overlay.
  - **Per-app rules:** `[[rules]]` exactly per §7a. Every new window goes through `RuleEngine.classify` before insertion; post-placement commands then run on it. Implement the extensions `ignore`, `dock`, `min-size` and `tab-with`, and the remaining tree commands.
  - Opt-in macOS tiling-pref override with backup/restore (§7).
- Tests:
  - RuleEngine table tests: file order, all matches run, last `layout floating|tiling` wins, `app-id` exact vs `app-name`/`title` case-insensitive regex, `kind` mapping from subrole, dialogs/sheets/panels/non-resizable always float, the full-screen-button heuristic and the `layout tiling` override, invalid regex/missing `run` rejected at load.
  - Parsing of Dinky's own example config sections (golden fixtures we write ourselves from the documented format).
  - Extension commands.
  - Focus-follows-mouse state machine (delay, button-down/menu suppression, post-Cmd-Tab/Space-change suppression, exclude-apps) with fake events; border colour parsing (`#rrggbb`, `#rrggbbaa`, `accent`, invalid → error) and frame tracking math.
  - Also: persistence migrations; URL parsing (fuzz invalid input; `exec-and-forget` rejected); prefs backup/restore unit tests against a fake defaults domain.
- Manual QA:
  - borders follow windows during animation and drag, never intercept clicks, hide in full screen, and look correct in light/dark/Increase Contrast/Reduce Transparency;
  - focus-follows-mouse respects the delay and doesn't fight Cmd-Tab;
  - reboot restores layout; kill -9 then relaunch offers prefs restore; "Restore macOS settings & quit" leaves `defaults read com.apple.WindowManager` identical to the pre-install snapshot.

**P9 Onboarding + distribution + updates**
- Tasks: native-look pass (materials, accent, SF Symbols, light/dark, Reduce Motion/Transparency, Increase Contrast audit of every panel); onboarding flow (§7, Accessibility + optional Screen Recording only); Sparkle integration; a GitHub Actions release workflow on tag: build arm64 → sign (Developer ID) → hardened runtime → notarize + staple → DMG → upload to **GitHub Releases** → generate and EdDSA-sign the appcast → publish it (Pages or release asset). Release strings check gate; CHANGELOG.
- AC: a clean macOS 14 and current-macOS VM can install from the GitHub Release (Gatekeeper passes), onboard without any Input Monitoring prompt (on versions that passed P5a), and update from N-1 → N via Sparkle.

**P10 (optional) Experimental flags**
- Tasks: AX window-id shortcut (`_AXUIElementGetWindow`) and raw multitouch. Each is behind a flag, off by default, symbol-checked at runtime, with automatic disable plus a log on failure. (Spaces are core in P6, not here.)
- AC: with these experimental flags off, the app passes all P4–P8 QA. Native Spaces (P6) stay on, since they are not a flag.

## 9. Risks
- AX quirks/latency per app (Electron, Java, Office) → per-app queues, retries, an exclusion list, a quirks table.
- Native macOS tiling/Stage Manager fighting the layout → detect it and offer the opt-in override with guaranteed restore.
- Moving windows via AX during animation looks janky → proxies, coalescing, short durations.
- Screen Recording indicator unsettles users → keep previews optional and clearly explained.
- **Active tap and Input Monitoring (UNVERIFIED):** the plan assumes an active tap from an AX-trusted process needs no Input Monitoring. If Apple tightens this (on any version, including a point release), the P5a matrix catches it, and the per-OS safety net disables only modifier-drag, pinch-over-apps and left/right modifiers. Re-run the matrix on every new OS release.
- **Tap timeouts:** a slow callback makes macOS disable the tap (`kCGEventTapDisabledByTimeout`). That causes lost bindings, and a swallowing tap that is slow stalls system-wide input. Mitigate with the ~1 ms callback budget (classify only, async work), immediate re-enable, a counter and a warning, and p99 timing in debug builds.
- **Swallowing bugs:** a wrong classification could eat clicks or keys system-wide. Keep the classifier pure and unit-tested, only swallow when the configured modifier or binding matches exactly, and provide an always-available menu "Disable input features" plus `enable off`.
- Power-source heuristic: a laptop on mains is treated as a laptop (a guess), and a desktop with a UPS reports no internal battery (correct). Users can override with `overview-previews`.
- Recreating TrellisWM behaviour risks drifting into copying → CONTRIBUTING clean-room rule, own names/strings/numbers, and PR review checks it.
- macOS updates break private shims → runtime capability probe, a safety net to `.currentSpaceOnly` with a visible notice, and the spike matrix re-run for each new major OS and x.y point release before declaring support.
- **Spaces backend fragility:** bridged SkyLight operations, internal symbol names and the Dock-swipe payload changed in macOS 26.4 and 27 and can change in any point release. Since Spaces are core, a breakage hits every user: watch beta seeds, re-run the P6a matrix, and ship probe updates quickly. The safety net must keep the app usable meanwhile.
- **Dock coherence:** WindowServer can accept an operation while Dock/Mission Control state diverges (ghost Spaces, wrong current Space, a desktop label mismatch). Re-query after every action, detect divergence, stop reconciling, and advise a Dock restart or logout. Never create or destroy in a loop.
- Cursor warp on cross-display switches is accepted. macOS drops mouse input for about 0.25 s after a warp → restore the cursor position and coalesce switches.
- Reconcile mistakes could delete user Spaces → only owned Spaces are ever removed (planner invariant, unit-tested), and never in a loop.
- Config format coupling to Dinky: if Dinky changes its schema we could drift → pin the documented format version in `docs/config.md`, and treat compatibility as best-effort beyond the listed sections.
- Full-screen detection gaps (video element full screen, presentation apps) → AX plus Space-type checks, and the QA list in P4.

## 10. Open decisions
Resolved:
- Name **Lattice** (`lattice://`, `com.designbyadrian.lattice`); **arm64 only**; **tile by default**.
- **Input**: an active tap (mouse, gesture, flagsChanged and keys as needed), never a listen-only keyboard tap. The goal is no Input Monitoring prompt (UNVERIFIED, P5a spike). Modifier-drag, pinch over apps and `[modifiers]` are restored.
- **Open source**: MIT, no licensing.
- **Look**: native macOS (system materials, accent colour, SF Symbols, AppKit controls, light/dark, Reduce Motion/Transparency, Increase Contrast).
- **Focus-follows-mouse**: supported, Dinky `[focus-follows-mouse]` format, off by default (as in Dinky), plus the `exclude-apps` extension.
- **Borders**: supported, Dinky `[borders]` key names, **off by default** (Dinky: on), plus the `'accent'` colour extension.
- **Previews**: auto by power source, with the `overview-previews` override.
- **Layouts**: TrellisWM-observed tree behaviour, no Dinky layouts.

None open. Pending only on spike results: the P5a input matrix and the P6a Spaces matrix (each needs Adrian's sign-off).
