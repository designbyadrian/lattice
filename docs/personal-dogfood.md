# Personal dogfood checklist (Xcode install)

Local builds only — no notarization or Sparkle. Both Macs: Apple silicon, macOS 14+, git, Xcode.

---

## A. Install / update

```bash
git clone https://github.com/designbyadrian/lattice.git   # first time
cd lattice
git fetch && git checkout implement-p0-p10 && git pull

swift test
python3 refimpl/test_refimpl.py

command -v xcodegen >/dev/null && xcodegen generate
open Lattice.xcodeproj   # scheme Lattice → Run
```

Stable signing (optional): `./scripts/build-local.sh` with `LATTICE_CODE_SIGN_IDENTITY` set.

Config is per Mac: `~/.config/lattice/lattice.toml`. Copy from the first Mac if you want the same shortcuts.

---

## B. Permissions (each Mac)

1. Accessibility → enable Lattice.
2. Optional Screen Recording (“pictures while windows move”).
3. You should **not** need Input Monitoring. If prompted, note FAIL for personal P5a.

---

## C. Behaviour smoke (float-first)

- [ ] After launch, **no window moved** on its own.
- [ ] New Safari window appears **floating**; docked neighbours (if any) do not jump.
- [ ] Drag a window title bar to a screen edge → docks; desktop region remains.
- [ ] Menu **Dock all windows** tiles floats in one motion.
- [ ] `⌃⌥Space` → show everything (camera); windows shrink in place (or icon covers).
- [ ] `⌃⌥[` / `⌃⌥]` → history back/forward.
- [ ] Double-click wallpaper → frame desktop; again → back.
- [ ] Double-click a **tiled** title bar → frame window; floating title bar still uses macOS action.
- [ ] Green button on managed window toggles dock/float (without Option).
- [ ] `⌘⇧`-drag draws a rectangle and zooms to it.
- [ ] Menu-bar Back / Forward / Everything / Desktop controls work; Lattice menu has no Overview.

---

## D. Personal P5a (input) — ~10 min

1. Quit other WMs.
2. Unbound typing in TextEdit still works.
3. Bound chords (`⌃⌥…`) work.
4. Lattice not listed under Input Monitoring.

---

## E. Spaces (optional)

Only if `workspaces > 1`. Otherwise leave default `1`. Full matrix: [spaces-matrix.md](spaces-matrix.md).

---

## F. Quit / relaunch

- [ ] Quit leaves windows on-screen.
- [ ] Relaunch restores the arrangement (same display).

---

## G. Second Mac

- [ ] Same branch pull + Xcode Run  
- [ ] Accessibility  
- [ ] Optional: copy `lattice.toml`  
- [ ] Section C smoke  
