# Lattice

A native, open-source macOS tiling window manager (menu bar app).

**Build and usage docs are coming after the v1 implementation phases.** Until then:

```bash
swift build
swift test
```

See [AGENTS.md](AGENTS.md) for opening the app target. See [PLAN.md](PLAN.md) for the product plan.

Config format compatible with Dinky by Mikkel Malmberg (MIT) — see [NOTICE](NOTICE).

Config lives at `~/.config/lattice/lattice.toml`. Layouts are stored under
`~/Library/Application Support/com.designbyadrian.lattice/layouts/`.

Optional **Override macOS tiling** (menu) backs up `com.apple.WindowManager` keys to
`system-prefs-backup.json` and restores them on quit, crash recovery, or
**Restore macOS settings & quit**.
