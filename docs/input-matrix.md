# Input Monitoring spike matrix (P5a)

**Status:** all rows `PENDING_VM` — needs Adrian’s human sign-off before treating any macOS version as verified.

**Goal:** confirm that one **active** event tap (`kCGEventTapOptionDefault`, `cgSessionEventTap`) from an Accessibility-trusted process can create, receive, and swallow events **without** an Input Monitoring prompt, and without Lattice appearing under **System Settings → Privacy & Security → Input Monitoring**.

This claim is **UNVERIFIED** until this matrix is filled in. Code must still ship the per-OS safety net (§6 / P5): if a version fails, disable only modifier-drag swallowing, pinch-over-apps, and left/right modifier distinction; fall back to Carbon hotkeys and an `NSEvent` mouse-moved monitor for focus-follows-mouse.

Do **not** use `CGPreflightListenEventAccess` as the pass/fail signal (that API is about listen-only access).

## Matrix

| macOS | OS build | tap create OK? | swallow OK? | Input Monitoring prompt? | listed under Input Monitoring? | result | sign-off |
|-------|----------|----------------|-------------|--------------------------|--------------------------------|--------|----------|
| 14 | _pending_ | PENDING_VM | PENDING_VM | PENDING_VM | PENDING_VM | PENDING_VM | — |
| 15 | _pending_ | PENDING_VM | PENDING_VM | PENDING_VM | PENDING_VM | PENDING_VM | — |
| 26 | _pending_ | PENDING_VM | PENDING_VM | PENDING_VM | PENDING_VM | PENDING_VM | — |
| 27 | _pending_ | PENDING_VM | PENDING_VM | PENDING_VM | PENDING_VM | PENDING_VM | — |

**Column notes**

- **OS build:** full product version string from the VM (e.g. `sw_vers` / About This Mac).
- **tap create OK?:** active tap with mouse + gesture + `flagsChanged` + `keyDown`/`keyUp` in the mask creates successfully.
- **swallow OK?:** bound / classified events can be swallowed (callback returns `nil`); unbound keys and clicks still reach apps.
- **Input Monitoring prompt?:** whether macOS showed the Input Monitoring permission dialog during the test.
- **listed under Input Monitoring?:** whether Lattice appears in that Privacy list after the test.
- **result:** `PASS` / `FAIL` / `PENDING_VM`. On `FAIL`, that OS uses the safety net.
- **sign-off:** Adrian initials + date when the row is accepted.

## Test procedure (Adrian)

Run on **clean VMs** for macOS **14, 15, 26, and 27**:

1. Create a **fresh user account** on the VM (not a reused profile).
2. Install / run Lattice (or the P5a tap probe build). Grant **Accessibility only** — do not grant Input Monitoring if prompted (a prompt itself is a fail signal for that OS).
3. Confirm the process is Accessibility-trusted, then create **one active** session event tap whose mask includes mouse down/up/dragged/moved, scroll, gesture/magnify, `flagsChanged`, and `keyDown`/`keyUp`.
4. Verify events arrive and that the classifier can **swallow** a test binding (e.g. a harmless bound chord) while unbound typing and clicks still reach another app (TextEdit / Safari).
5. Check that **no Input Monitoring prompt** appeared and that Lattice is **not** listed under Privacy & Security → Input Monitoring.
6. Record the OS build and fill the row. On failure, mark `FAIL` and note that the safety net applies for that version.
7. Sign off the row (initials + date) when satisfied.

## Commit note

Matrix is pending human sign-off. Implementation must include the safety net regardless of VM results.
