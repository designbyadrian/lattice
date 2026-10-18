# Lattice

Lattice is a native, open-source **macOS tiling window manager**. It runs from the menu bar, keeps a nestable arrangement per display (splits, tabs, a desktop region for floating windows), and zooms a camera over that arrangement. Numbered workspaces can use native macOS Spaces.

**License:** MIT  
**Config format** compatible with [Dinky](https://github.com/mikker/Dinky) by Mikkel Malmberg (MIT). See [NOTICE](NOTICE).

Personal / local builds only — no App Store or Sparkle updates (ADDENDUM-2 D10).

---

## Requirements

| | |
|---|---|
| Mac | Apple silicon (arm64) |
| OS | macOS 14+ |
| Build | Xcode + git; optional [XcodeGen](https://github.com/yonaskolb/XcodeGen) |
| Permissions | **Accessibility** (required). **Screen Recording** optional (still pictures while windows move). Lattice aims to avoid **Input Monitoring** — see [docs/input-matrix.md](docs/input-matrix.md). |

---

## Clone and build

```bash
git clone https://github.com/designbyadrian/lattice.git
cd lattice
git checkout implement-p0-p10   # until merged to main

swift build
swift test
python3 refimpl/test_refimpl.py   # layout goldens (ADDENDUM-3)

# App
brew install xcodegen             # once, if needed
xcodegen generate
open Lattice.xcodeproj            # scheme Lattice → Run
```

Or a Release build with a **stable** signing identity (keeps Accessibility grants across rebuilds):

```bash
export LATTICE_CODE_SIGN_IDENTITY="Apple Development"   # or your Keychain cert name
./scripts/build-local.sh
```

If grants stick after changing identity:  
`tccutil reset Accessibility com.designbyadrian.lattice`

**Second Mac:** same clone/pull + Xcode Run. Config does not sync — copy `~/.config/lattice/lattice.toml` if you want matching bindings. Checklist: [docs/personal-dogfood.md](docs/personal-dogfood.md).

---

## How it behaves (important)

- **Nothing moves at launch.** New windows **float** in the desktop region until you dock them (drag to an edge, green button, `dock-all`, or a `layout tiling` rule).
- **Zoom** changes the camera over the real arrangement (`zoom all` = show everything). There is no separate overview panel.
- **Menu bar:** Back, Forward, saved-view numbers, Desktop, Everything, plus the Lattice menu.
- Layout geometry matches the Python reference in [`refimpl/`](refimpl/) (ADDENDUM-3); Swift tests must match `refimpl/goldens.json`.

---

## Configuration

**Path:** `~/.config/lattice/lattice.toml` (created on first run).

- Kebab-case keys; unknown keys are errors; a broken save keeps the last good config.
- `#:schema` line points at the bundled JSON Schema for editors.
- Open from Settings → Open config, or edit the file. Settings writes preserve comments when possible.

Full reference: [docs/config.md](docs/config.md).

### Defaults (excerpt)

| Key | Default |
|---|---|
| `default-tiling` | `false` |
| `workspaces` | `1` |
| `[gaps] inner` / `outer` | `10` |
| `[animations] duration-ms` | `450` |
| `frame-modifier` | `'cmd-shift'` |
| `pinch-modifier` | `'alt'` |
| `menu-bar-controls` | `back`, `forward`, `views`, `desktop`, `everything` |

### Rules example

```toml
[[rules]]
app-id = 'com.apple.Music'
run = ['layout floating', 'move-window-to-workspace 2']
```

---

## Default key bindings (B11)

US-layout names in `[mode.main]`. Change them in Settings → Shortcuts or in the TOML.

| Keys | Command |
|---|---|
| `ctrl-alt-space` | `zoom all` |
| `ctrl-alt-up` / `down` | `zoom out` / `zoom in` |
| `ctrl-alt-left` / `right` | `pan left` / `pan right` |
| `ctrl-alt-shift-up` / `down` | `pan up` / `pan down` |
| `ctrl-alt-left-bracket` / `right-bracket` | `history back` / `forward` |
| `ctrl-alt-enter` | `zoom window --toggle` |
| `ctrl-alt-d` | `desktop-area toggle` |
| `ctrl-alt-n` | `split-new com.apple.finder` |
| `ctrl-alt-shift-1`…`9` | `store-view N` |
| `ctrl-alt-1`…`9` | `recall-view N` |
| `ctrl-alt-cmd-1`…`9` | `workspace N` |
| `ctrl-alt-cmd-shift-1`…`9` | `move-window-to-workspace N` |

**Mouse / trackpad**

| Action | Behaviour |
|---|---|
| Title-bar drag | Dock / undock / tab (hold centre ~400 ms) |
| `⌘⇧`-drag | Zoom camera to a rectangle |
| `⌥`-pinch (or pinch on bare desktop / zoomed-out view) | Continuous camera zoom, then settle |
| Double-click wallpaper | `zoom desktop --toggle` |
| Double-click tiled title bar | `zoom window --toggle` |
| Green button (managed windows) | Dock ↔ float (Option-click keeps macOS zoom) |

---

## Workspaces and Spaces

Numbered workspaces remain a core feature (unlike some site docs). Spike matrices: [docs/input-matrix.md](docs/input-matrix.md), [docs/spaces-matrix.md](docs/spaces-matrix.md). Uninstall helpers: Remove Lattice-created Spaces; Restore macOS settings & quit.

---

## Scripting

```text
lattice://run?cmd=zoom%20all
lattice://workspace/2
```

CLI talks to the running app over a per-user Unix socket (`swift run lattice-cli doctor`).

Command names are Lattice’s own (`recall-view`, `store-view`, `unmanage-all`, `dock-all`, `desktop-area`, `pan`, …).

---

## Contributing

[CONTRIBUTING.md](CONTRIBUTING.md) · [PLAN.md](PLAN.md) · [ADDENDUM.md](ADDENDUM.md) · [ADDENDUM-2.md](ADDENDUM-2.md) · [ADDENDUM-3.md](ADDENDUM-3.md) · [SECURITY.md](SECURITY.md)
