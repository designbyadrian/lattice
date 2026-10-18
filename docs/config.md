# Lattice configuration reference

**Format version:** Dinky-compatible TOML (best-effort). Lattice extensions are marked below.

**Path:** `~/.config/lattice/lattice.toml`  
**Schema:** [`Packages/Config/Sources/Resources/lattice.schema.json`](../Packages/Config/Sources/Resources/lattice.schema.json)  
**Defaults source:** first-run file from `DefaultConfigText` (also used when the file is missing).

## Validation

- All keys optional; omitted → default.
- Kebab-case keys.
- Unknown keys → load error with key path.
- Broken file → keep last good config; show error in menu.
- `default-layout` → error (“Lattice has a single tree layout”).
- `[scrolling]` / `[accordion]` → “not supported” (not unknown-key typos).

## Top-level

| Key | Type | Default | Notes |
|---|---|---|---|
| `start-at-login` | bool | `true` | |
| `workspaces` | int | `1` | Native Spaces across displays |
| `default-tiling` | bool | `true` | |
| `follow-app-activation` | bool | `true` | |
| `float-windows-without-fullscreen` | bool | `true` | AeroSpace-style heuristic |
| `overview-previews` | string | `'auto'` | **Lattice:** `auto` \| `live` \| `snapshots` \| `off` |

## Tables

### `[gaps]`

`inner`, `outer`: number or `{ left, right, top, bottom }`.

### `[workspace.<n>]`

`tiling` only. Numbers in `1…workspaces`.

### `[workspace-to-display]`

`<n> = 'main' | 'secondary' | '<display-name substring>'` or a list tried in order.

### `[display.<pattern>]`

Per-display gaps. Name patterns beat `main`/`secondary`; longer beats shorter.

### `[animations]`

`enabled`, `duration-ms`. Off under Reduce Motion.

### `[drag]`

`placeholders` — show drop overlays.

### `[modifiers]`

`alt`, `ctrl`, `cmd`, `shift`: `'both' | 'left' | 'right'` (default `'both'`).  
**Lattice:** `drag-modifier`, `pinch-modifier` (e.g. `'alt'`, `'ctrl-alt'`).

### `[hooks]`

`startup`, `workspace-changing`, `workspace-changed`, `focus-changed`, `mode-changed` — command strings or lists. May use `exec-and-forget` (not via URL).

### `[mode.<name>]`

Bindings: `alt-shift-h = 'command'` or a list (cycles). Start mode: `main`. US-layout key names.

### `[focus-follows-mouse]`

`enabled` (default `false`), `delay-ms` (default `100`), `accordion-edges` (accepted, unused).  
**Lattice:** `exclude-apps = ['bundle.id', …]`.

### `[borders]`

`enabled` (Lattice default `false`), `width`, `active-color`, `inactive-color`, `order` (`below`\|`above`), `exclude-apps`.  
Colours: `#rrggbb`, `#rrggbbaa`, or **Lattice** `'accent'`.

### `[experimental]` (Lattice)

`ax-window-id`, `multitouch` — booleans, default `false`.

## Rules `[[rules]]`

Fields: `app-id` (exact), `app-name` / `title` (case-insensitive regex), `kind` (`normal`\|`dialog`\|`sheet`\|`panel`), `run` (required).

All matching rules run in file order. Last `layout floating` / `layout tiling` wins for placement. Other commands run after place.

**Lattice `run` extensions:** `ignore`, `dock <dir>`, `min-size <w> <h>`, `tab-with <…>`, tree commands (`split`, `zoom`, …).

## Commands

Shared grammar: `verb arg… --flag` (bindings, rules, hooks, URL, CLI).

Kept from Dinky (subset): workspace navigation, focus/move/join/resize/balance, mode, reload-config, enable, list-*, exec-and-forget (not URL), layout floating|tiling only.

Lattice tree commands: `split`, `dock`, `tab-with` / `untab` / `tab`, `zoom`, `frame-rect`, `history`, `view` / `save-view`, `overview`, `float-all`, `ignore`, `min-size`.

See default bindings in the [README](../README.md#default-key-bindings).
