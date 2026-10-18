# Lattice

Lattice is a native, open-source **macOS tiling window manager**. It runs as a menu-bar app (no Dock icon), arranges real windows in a nestable layout tree (splits, tabs, floating), and can back numbered workspaces with native macOS Spaces. Keyboard, drag, and URL/CLI control are supported.

**License:** MIT  
**Config format** compatible with [Dinky](https://github.com/mikker/Dinky) by Mikkel Malmberg (MIT). Lattice ships its own parser, defaults, and docs — see [NOTICE](NOTICE).

---

## Requirements

| | |
|---|---|
| Mac | **Apple silicon** (arm64 only) |
| OS | **macOS 14** or later |
| Tools to build | **Xcode** (15+; CI uses the runner’s Xcode) and the bundled Swift toolchain |
| Permissions | **Accessibility** (required). **Screen Recording** (optional, overview previews). Lattice aims to avoid **Input Monitoring** — see [docs/input-matrix.md](docs/input-matrix.md). |

---

## Clone and build

```bash
git clone https://github.com/designbyadrian/lattice.git
cd lattice

# Libraries + unit tests (no GUI required)
swift build
swift test

# Menu-bar app (needs XcodeGen once, or use the checked-in project)
brew install xcodegen   # if needed
xcodegen generate
open Lattice.xcodeproj
```

In Xcode, select the **Lattice** scheme, destination **My Mac**, then Run. The app appears in the menu bar (rectangle-split SF Symbol). Use **Quit Lattice** from that menu.

Bundle id: `com.designbyadrian.lattice`  
URL scheme: `lattice://`

More agent/contributor notes: [AGENTS.md](AGENTS.md).

---

## First launch

1. Complete onboarding (Accessibility → optional Screen Recording → short tutorial).
2. Lattice writes a default config if none exists (see below).
3. New manageable windows tile into the layout tree; floating exceptions follow config and rules.

If Accessibility is later revoked, the menu bar item shows a warning.

---

## Configuration

### File location

```text
~/.config/lattice/lattice.toml
```

- Created automatically on first run with **commented defaults**.
- Reloaded when you save the file (file watch). Invalid configs are **rejected**: the last good config stays active and the error (with key path, e.g. `rules[0].app-id`) appears in the menu.
- Every key is optional; missing keys keep defaults. Keys are **kebab-case**. **Unknown keys are errors.**
- Editors: the file starts with a `#:schema …` line pointing at the bundled JSON Schema for completion ([`lattice.schema.json`](Packages/Config/Sources/Resources/lattice.schema.json)).

**Open from the app:** menu → Settings → **Open config**, or edit the file directly.

Full schema reference: [docs/config.md](docs/config.md).

### Important defaults

| Key | Default | Meaning |
|---|---|---|
| `start-at-login` | `true` | Launch at login |
| `workspaces` | `1` | Number of workspaces (native Spaces) |
| `default-tiling` | `true` | Tile new managed windows |
| `follow-app-activation` | `true` | Follow Cmd-Tab / Dock activation across workspaces |
| `float-windows-without-fullscreen` | `true` | Float windows that cannot go full-screen (unless a rule forces tiling) |
| `overview-previews` | `'auto'` | Live previews on desktops, snapshots on laptops; `'off'` / deny Screen Recording → icons |
| `[borders] enabled` | `false` | Optional window borders |
| `[focus-follows-mouse] enabled` | `false` | Focus under pointer after a delay |
| `[modifiers] *` | `'both'` | Which physical side counts as alt/ctrl/cmd/shift in bindings |
| `drag-modifier` | `'alt'` | Hold to drag-dock / frame-rect over apps |
| `pinch-modifier` | `'ctrl-alt'` | Hold to pinch-zoom the Lattice camera over apps |
| `[experimental]` | both `false` | Optional private-API shortcuts (see below) |

Dinky’s `default-layout` and tables `[scrolling]` / `[accordion]` are **not supported** (clear errors). Lattice uses a single tree layout.

### Rules (example)

```toml
[[rules]]
app-id = 'com.apple.Music'
run = ['layout floating', 'move-window-to-workspace 2']
```

Matching is Dinky-style: all matching rules run in file order; last `layout floating` / `layout tiling` wins. See [docs/config.md](docs/config.md).

---

## Default key bindings

Bindings live under `[mode.main]` (US-layout key names). Change them in `lattice.toml`. Unbound keys always pass through to apps.

| Binding | Command |
|---|---|
| `alt-h` / `j` / `k` / `l` | `focus left` / `down` / `up` / `right` |
| `alt-shift-h` / `j` / `k` / `l` | `move left` / `down` / `up` / `right` |
| `alt-enter` | `split horizontal` |
| `alt-v` | `split vertical` |
| `alt-f` | `zoom window` |
| `alt-shift-f` | `zoom all` |
| `alt-o` | `overview` |
| `alt-tab` / `alt-shift-tab` | `tab next` / `tab prev` |
| `alt-1` … `alt-9` | `workspace N` |
| `alt-shift-1` … `alt-shift-9` | `move-window-to-workspace N --follow` |
| `alt-shift-q` | `float-all` |
| `alt-r` | `retile` |
| `alt-shift-space` | toggle `layout floating` / `layout tiling` |
| `ctrl-alt-h` / `j` / `k` / `l` | `dock left` / `down` / `up` / `right` |

**Modifiers:** under `[modifiers]`, set `alt = 'left'` (etc.) so the other Option key can still type special characters. That needs the active event tap; under the [input safety net](docs/input-matrix.md) it is ignored.

**Mouse:** hold `drag-modifier` (default Alt) over a window to move/dock without delivering the click to the app. Hold `pinch-modifier` to zoom Lattice’s camera. Title-bar drags without the modifier show drop overlays on mouse-up.

---

## Workspaces and Spaces

Lattice can bind numbered workspaces to native Spaces (SIP stays on). Capability is probed at launch; if the OS build fails the spike matrix or symbols are missing, Lattice runs in **current Space only** and the menu explains why.

- Spike results / sign-off: [docs/spaces-matrix.md](docs/spaces-matrix.md)
- Uninstall helpers in the menu: **Remove Lattice-created Spaces**, **Restore macOS settings & quit** (only if you opted into the tiling-pref override)

---

## Scripting

**URL** (same command grammar as bindings; `exec-and-forget` is rejected):

```text
lattice://run?cmd=workspace%202
lattice://workspace/2
```

**CLI** (while the app is running; talks over a per-user Unix socket, not a fixed `/tmp` path):

```bash
swift run lattice-cli doctor
# or the installed `lattice` helper once distributed
```

`lattice doctor` validates the config file.

---

## Experimental flags

Off by default. On failure they auto-disable and log; core tiling does not depend on them.

```toml
[experimental]
ax-window-id = false   # optional _AXUIElementGetWindow shortcut
multitouch = false     # raw multitouch path
```

---

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) (clean-room rules: no TrellisWM material; Dinky is config-format only). Product plan: [PLAN.md](PLAN.md). Security: [SECURITY.md](SECURITY.md).

```bash
swift test
./scripts/check-release-strings.sh path/to/Lattice.app/Contents/MacOS/Lattice
```
