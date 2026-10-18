# Lattice configuration reference

**Format:** Dinky-compatible TOML (best-effort) + Lattice extensions.  
**Path:** `~/.config/lattice/lattice.toml`  
**Schema:** [`Packages/Config/Sources/Resources/lattice.schema.json`](../Packages/Config/Sources/Resources/lattice.schema.json)  
**Defaults:** `DefaultConfigText` / first-run file.  
**Layout numbers:** [ADDENDUM-3.md](../ADDENDUM-3.md) §9; goldens in [`refimpl/`](../refimpl/).

## Validation

- Optional keys; omitted → default. Kebab-case. Unknown keys → error with key path.
- Broken file → keep last good config.
- `default-layout`, `[scrolling]`, `[accordion]` → not supported.
- `overview-previews` removed (ADDENDUM-2 D6).

## Top-level

| Key | Default | Notes |
|---|---|---|
| `start-at-login` | `true` | |
| `workspaces` | `1` | |
| `default-tiling` | **`false`** | Float-first (ADDENDUM-2 D1) |
| `follow-app-activation` | `true` | |
| `float-windows-without-fullscreen` | `true` | |
| `menu-bar-controls` | `['back','forward','views','desktop','everything']` | Lattice |

## Common tables

- `[gaps]` — `inner`/`outer` default **10**
- `[animations]` — `duration-ms` default **450**
- `[modifiers]` — sides + `frame-modifier = 'cmd-shift'`, `pinch-modifier = 'alt'` (no `drag-modifier`)
- `[mouse]` — `double-click-desktop` / `double-click-title` (command or `'none'`)
- `[layout]`, `[zoom]`, `[tabs]`, `[desktop-area]`, `[window-sizing]` — see ADDENDUM-3 §9
- `[borders]`, `[focus-follows-mouse]`, `[hooks]`, `[workspace.<n>]`, `[workspace-to-display]`, `[display.<pattern>]`, `[experimental]`
- `[[rules]]` — Dinky semantics; `run` required

## Commands (Lattice names)

| Prefer | Not used |
|---|---|
| `recall-view` / `store-view` | `view` / `save-view` |
| `unmanage-all` | `float-all` |
| `zoom all` | `overview` |
| `desktop-area` | vendor toggle-desktop forms |
| `dock-all`, `pan`, `split-new`, `split-direction`, `frame-rect` | — |

URL: `lattice://run?cmd=…` uses these names only.

## Default bindings

See [README.md](../README.md#default-key-bindings-b11).
