# Contributing to Lattice

## Clean-room rules

- Do **not** copy code, assets, icons, names, UI strings, settings keys, or URL commands from TrellisWM.
- Layout behaviour is recreated from observed behaviour and public docs only. Use Lattice's own names, numbers, and wording.
- Dinky is a **config format** reference only. Do not paste Dinky source, docs prose, or default-config comments. Matching the TOML schema/interface is fine; credit Dinky (MIT) in NOTICE/README/About.
- Prefer Apple public APIs and documented reverse-engineering notes. Private-API shims must load via `dlsym` / runtime checks and live under `PlatformMac/Private` or `Experimental`.

## Tests

- New behaviour needs tests. Pure model/engine/config changes should pass `swift test` without a GUI.
- Keep LayoutModel / LayoutEngine / Config free of AppKit.

## Code style

- Swift 6 with strict concurrency.
- AppKit for the app and Settings UI (not SwiftUI for Settings in v1).
- Prefer small, focused packages as in `PLAN.md` §3.

## Pull requests

- One phase or coherent change per PR when possible.
- Never merge without explicit human approval of that specific merge.
- Describe what was verified (`swift test`, manual QA checklist items).
