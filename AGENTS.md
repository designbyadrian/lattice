# Agent / contributor workflow

## Branching

- Branch from `main` per phase or feature: `p0-skeleton`, `p1-layout-model`, etc.
- Open a PR to `main`. Do **not** merge without explicit human approval of that merge.
- Prefer non-breaking changes; bump `CFBundleShortVersionString` when shipping user-visible releases.

## Build

Requirements: Apple silicon, macOS 14+, Xcode 15+ (CI uses the runner’s Xcode).

```bash
swift build
swift test
```

### App target

The menu-bar app lives in `App/`. Generate or open the Xcode project:

```bash
# Option A: XcodeGen (if installed)
brew install xcodegen   # once
xcodegen generate
open Lattice.xcodeproj

# Option B: open Package.swift in Xcode and add/run the App sources via the
# checked-in Lattice.xcodeproj (preferred for day-to-day).
open Lattice.xcodeproj
```

Build & run the **Lattice** scheme (LSUIElement menu-bar app, bundle id `com.designbyadrian.lattice`).

### Release strings check

```bash
./scripts/check-release-strings.sh path/to/Lattice.app/Contents/MacOS/Lattice
```

## Cloud / coding agents

Repo implementation work should land on a feature branch with a PR. Parent chat tracks phase AC and spike sign-offs (P5a input matrix, P6a Spaces matrix).

## Import rules

- `LayoutModel`, `LayoutEngine`, `Config`: Foundation (+ TOML decoder) only.
- `AppCore` depends on `Platform` protocols, never on `PlatformMac` directly.
