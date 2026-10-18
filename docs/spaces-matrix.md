# Native Spaces spike matrix (P6a)

**Status:** all rows `PENDING_VM` — needs Adrian’s human sign-off before treating any macOS version as verified for `SpacesBackend.native`.

**Goal:** confirm that Lattice can create, adopt, bind, move, and remove ordinary user Spaces (and move windows between them) on SIP-on Apple silicon without Dock / Mission Control incoherence or lost windows. Spaces are **core** (not an experimental flag); if a version fails, the capability probe must route that OS to `.currentSpaceOnly`.

Clean-room: load SkyLight only via `dlsym` / `objc_getClass` with nil checks — never hard-link private symbols.

## Matrix

| macOS | OS build | create/adopt/bind/move/remove | move windows (batch/same-app/sheets) | rapid switch 1↔5 | Cmd-Tab + Dock clicks | Mission Control coherent | Dock restart | display unplug/replug | result | sign-off |
|-------|----------|-------------------------------|--------------------------------------|------------------|----------------------|--------------------------|--------------|----------------------|--------|----------|
| 14 | _pending_ | PENDING_VM | PENDING_VM | PENDING_VM | PENDING_VM | PENDING_VM | PENDING_VM | PENDING_VM | PENDING_VM | — |
| 15 | _pending_ | PENDING_VM | PENDING_VM | PENDING_VM | PENDING_VM | PENDING_VM | PENDING_VM | PENDING_VM | PENDING_VM | — |
| 26 | _pending_ | PENDING_VM | PENDING_VM | PENDING_VM | PENDING_VM | PENDING_VM | PENDING_VM | PENDING_VM | PENDING_VM | — |
| 27 | _pending_ | PENDING_VM | PENDING_VM | PENDING_VM | PENDING_VM | PENDING_VM | PENDING_VM | PENDING_VM | PENDING_VM | — |

**Column notes**

- **OS build:** full product version string from the VM (e.g. `sw_vers` / About This Mac).
- **create/adopt/bind/move/remove:** ordinary user Spaces only; full-screen Spaces must never be bindable. Owned-only removal (never delete Spaces Lattice did not create).
- **move windows:** batch move, same-app windows, and windows with sheets stay coherent.
- **rapid switch 1↔5:** synthetic Dock-swipe switching with cursor warp to the target display; no stuck or reversed desktops.
- **Cmd-Tab + Dock clicks:** follow-app-activation still lands on the right Space.
- **Mission Control coherent:** no ghost Spaces, wrong current Space, or desktop label mismatch after operations.
- **Dock restart:** after `killall Dock` in the test VM, re-query and confirm binding still matches reality (no create/destroy loop).
- **display unplug/replug:** displaced windows return after reconcile completes; pattern fallback to main works.
- **result:** `PASS` / `FAIL` / `PENDING_VM`. On `FAIL`, that OS uses `.currentSpaceOnly` until a probe update ships.
- **sign-off:** Adrian initials + date when the row is accepted.

## Test procedure (Adrian)

Run on **clean VMs** for macOS **14, 15, 26, and 27** (SIP on, Apple silicon):

1. Create a **fresh user account** on the VM (not a reused profile).
2. Install / run Lattice with Accessibility granted. Confirm the Spaces capability probe selects `.native` (or note `.currentSpaceOnly` if symbols are missing).
3. Set `workspaces` above the current Space count and confirm Lattice **adopts** the main display’s current Space as workspace 1, then **creates** only as needed. Lower the count and confirm only **owned**, empty, unbound Spaces are removed — user-created empty Spaces remain.
4. Exercise create / adopt / bind / move / remove; move windows in batch, same-app groups, and with sheets attached.
5. Rapidly switch workspaces **1↔5**; use Cmd-Tab and Dock clicks across Spaces; open Mission Control and check coherence.
6. Run `killall Dock`, wait for Dock to return, then re-check binding and Mission Control.
7. Unplug and replug an external display (or use a VM display change); confirm reconcile and window homes recover without lost windows.
8. Extra checks: fresh install leaves Mission Control showing the same Spaces as before; **Remove Lattice-created Spaces** restores the original count (windows moved to workspace 1’s Space first).
9. Record the OS build and fill the row. On failure (Dock incoherence or a lost window), mark `FAIL` so the probe routes that version to `.currentSpaceOnly`.
10. Sign off the row (initials + date) when satisfied.

## Commit note

Matrix is pending human sign-off. Implementation must include the `.currentSpaceOnly` safety net regardless of VM results.
