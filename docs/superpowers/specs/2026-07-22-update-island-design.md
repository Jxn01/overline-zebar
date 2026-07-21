# Update-Notifier Island — Design Spec

- **Date:** 2026-07-22
- **Status:** Approved design, pending spec review
- **Target:** overline-zebar fork (Zebar 3.1.1), branch `build-zebar-3.1.1`
- **Related memory:** `zebar-update-island-idea`, `zebar-overline-build`, `winget-full-upgrade-gotchas`

## 1. Goal

A Manjaro/pamac-style update notifier for the overline-zebar bar. An **island** that appears only
when updates exist, shows a total count plus an icon for each channel that has updates, and opens a
**modal** for acting on them — update everything, update a whole channel, or update individual items,
with hide/ignore + undo. Channels: **scoop**, **winget**, **Windows Update**. Sits between the
hardware-status island and the media island.

## 2. Non-goals (YAGNI)

- No changelog/release-notes fetching in v1.
- No auto-apply / unattended updating — every apply is user-initiated.
- No channels beyond scoop/winget/Windows Update (extensible, but not built now).
- No toast/OS notifications — the island's presence is the signal.

## 3. Architecture — one engine, two callers

The fragile work (parsing tool output, elevation, the desktop-icon sweep, mutex) lives in **PowerShell**,
not the widget. The React widget is a thin face that reads JSON and fires named actions.

```
Scheduled Task (per-user)                  Widget (React, Zebar 3.1.1)
      │ runs on cadence                         │ reads (cheap)          │ fires actions
      ▼                                         ▼                        ▼
  UpdateEngine.psm1  ──writes──►  status.json / ignore.json  ◄──reads──  island + update-panel
      │  check()                    (%LOCALAPPDATA%\overline-updates\)        │
      │  apply()  ◄──────────────────────────────────────────────────────────┘
      ▼
  scoop / winget / Windows Update (WUA COM)
```

Two engine entry points share `UpdateEngine.psm1`:
- **`check`** — enumerates all three channels, writes `status.json`. Run by the scheduled task and by the modal's "Check now".
- **`apply`** — performs upgrades for a given scope (all / one channel / one item). Splits into an unelevated path and an elevated helper (see §11, §12).

## 4. Components (purpose · interface · dependencies)

- **`UpdateEngine.psm1`** — shared module. Functions: `Get-ScoopUpdates`, `Get-WingetUpdates`,
  `Get-WindowsUpdates`, `Invoke-ScoopApply`, `Invoke-WingetApply`, `Invoke-WUApply`,
  `Read-IgnoreStore`, `Read-LastApply`, `Write-StatusAtomic`. Depends on: scoop, winget,
  `Microsoft.WinGet.Client` (preferred for structured winget data), WUA COM. No widget dependency.
- **`check.ps1`** — thin wrapper: acquires the winget mutex (skip-if-held), calls the `Get-*Updates`
  functions, merges with `ignore.json` and `last-apply.json`, writes `status.json` atomically.
  Idempotent, standalone-runnable.
- **`apply.ps1`** — takes `{channel?, id?, all?}`; runs the unelevated updates inline and, if any elevated
  work is needed, launches the **elevated applier** once. Writes per-item progress to a run log and the
  outcome to `last-apply.json`.
- **`apply-elevated.ps1`** — the elevated helper (launched via `Start-Process -Verb RunAs`). Does the
  machine-scope winget + Windows Update installs, the Public-desktop icon sweep, and streams progress +
  a completion record to a run-log file. Fixed script, data-only job file, no caller-supplied code (§12).
- **`status.json` / `ignore.json` / `last-apply.json`** — cache, user hide/ignore choices, apply-outcome
  history (schemas in §5).
- **Scheduled Task `overline-update-check`** — per-user, runs `check.ps1` on cadence (§6).
- **`UpdateIsland` (widget component in `widgets/main`)** — reads `status.json`, renders the pill,
  auto-hides at zero, opens the modal. Clone of the `Media` auto-hide pattern; wraps `Chip`.
- **`update-panel` (new popup widget)** — the modal. Clone of the `forecast` widget pattern
  (registered in `zpack.json`, opened via `zebar.startWidget`, closes on `tauri://blur`/Escape).

## 5. Data model

`status.json` (written atomically by `check`):

```jsonc
{
  "generatedAt": "2026-07-22T00:00:00+02:00",
  "wingetLocked": false,                     // reported from the real mutex, not the source of truth
  "channels": {
    "scoop":  { "checkedAt": "...", "stale": false, "error": null, "items": [ /* Item */ ] },
    "winget": { "checkedAt": "...", "stale": false, "error": null, "items": [ ... ] },
    "windowsUpdate": { "checkedAt": "...", "stale": false, "error": null, "items": [ ... ] }
  }
}
```

`Item`:

```jsonc
{
  "channel": "winget",
  "id": "Modrinth.ModrinthApp",
  "name": "Modrinth App",
  "current": "0.15.11",
  "available": "0.15.14",
  "scope": "user",            // user | machine   (drives elevation)
  "interactive": "no",        // no | yes | unknown  (from overrides + heuristic)
  "driver": false,            // WU driver vs software
  "driverClass": null,        // "display" | "input" | "audio" | "other"  (display => caveat badge)
  "rebootHint": false,        // known to need a restart to finalize
  "suspectStale": false       // post-apply mismatch flag (see §10)
}
```

`ignore.json` (user-owned, edited via the modal):

```jsonc
{
  "skipVersion": [ { "channel": "winget", "id": "Foo.Bar", "version": "1.2.3" } ],
  "ignorePackage": [ { "channel": "scoop", "id": "someapp" } ]
}
```

For **winget**, `ignorePackage` is also written through as a real `winget pin add --blocking` so it's
enforced at the source. skip-version and all scoop/WU hides live only in `ignore.json`.

`last-apply.json` (written by `apply`, read by `check`) — records each apply outcome so `suspectStale`
can be computed across process runs and across the checker-vs-modal boundary:

```jsonc
{ "Corsair.iCUE.5": { "appliedVersion": "5.48.58", "at": "2026-07-21T23:27:00+02:00", "exitCode": 0 } }
```

**Hide semantics:** the default hide action on a row is **skip-this-version** (writes `skipVersion`; the
item reappears when a newer version lands — the common case). A secondary action is **ignore-package**
(writes `ignorePackage`, persistent). Both are reversible from the modal's Hidden section.

**Locations:** engine scripts + `interactive-overrides.json` deploy to
`%LOCALAPPDATA%\overline-updates\engine\` (fixed, ACL-restricted so the elevated helper can't be swapped
out); `status.json`, `ignore.json`, `last-apply.json`, and per-run logs live in
`%LOCALAPPDATA%\overline-updates\`.

## 6. The three channels

| Channel | Check | Apply | Elevation | Cadence |
|---|---|---|---|---|
| **scoop** | `scoop status` (after periodic `scoop update` bucket refresh) | `scoop update <id>` / `scoop update *` | none (per-user) | ~45 min |
| **winget** | `Get-WinGetPackage \| ? IsUpdateAvailable` (structured; falls back to `winget upgrade` table) | `winget upgrade --id … --silent` | user-scope none; **machine-scope needs admin** | ~45 min |
| **Windows Update** | WUA COM `Microsoft.Update.Session` search `IsInstalled=0 and IsHidden=0`, split `Type='Software'` vs `Type='Driver'` | WUA COM downloader + installer (built-in, no module dependency) | **admin** | ~4 h |

Checks need no elevation on any channel. Staggered, plus one run at logon. The winget check takes the
same source lock as an install — see §11.

**(D) winget count authority:** `Get-WinGetPackage`'s `IsUpdateAvailable` is known to disagree with
`winget upgrade`'s list (winget-cli #5540 / #5968). `Get-WinGetPackage` is authoritative for the count
and item list; the `winget upgrade` table is the fallback only when the module is unavailable. Resolve
the exact reconciliation in the plan.

## 7. The island

- **Auto-hides at zero actionable** (returns `null`, copying the `Media` island).
- Shows **"N updates"** + one icon per channel that has actionable items.
- **Count includes drivers** (per decision 2026-07-22). Count **excludes**: hidden items,
  pinned/ignored packages, and `suspectStale` false-positives.
- A small secondary dot when any item has `rebootHint` and a prior apply is pending a restart.
- Placement: `widgets/main/src/App.tsx`, left group, between the `Stats` `</Chip>` and `<Media/>`.

## 8. The modal (`update-panel`)

- **Header:** `Update everything` + `Check now`. "Update everything" runs unelevated items inline and
  bundles **all** elevated items into a **single** UAC; by default it **excludes drivers** (§15).
  **(E)** If a check/apply already holds the winget mutex, `Check now` **waits briefly and shows
  "update in progress"** rather than silently no-op'ing the click.
- **Per channel group:** icon · name · count · `Update all in <channel>`; expandable.
- **Per item row (expanded):** `name  current → available`, badges: **silent/interactive**, **driver**,
  **reboot**; a per-item `Update`; a hide control.
- **Windows Update drivers:** a separate, collapsed sub-group with its own `Update all drivers`;
  **never** part of "Update everything" by default. Rows with `driverClass == "display"` additionally
  carry a **"may replace your vendor driver"** caveat badge; other driver classes (input/audio/other)
  do not — the regression risk is category-specific (see §15).
- **Hidden section** (collapsed, bottom): every hidden/ignored item with `un-hide`.
- **Live per-row status:** `available → updating → done / failed(reason)`. Failures render their reason
  in the row (e.g. "files locked by …", "installer prohibits elevation").

## 9. Progress reporting (forks by elevation)

- **Unelevated updates** (scoop, user-scope winget): the widget launches them via `shellSpawn` and
  streams `onStdout`/`onExit` straight into the row.
- **Elevated updates** (machine-scope winget, Windows Update): `RunAs` cannot pipe stdout back to the
  unelevated widget (proven repeatedly this session). Instead, `apply-elevated.ps1` writes structured
  progress lines to a per-run log file (`%LOCALAPPDATA%\overline-updates\run-<id>.log`); the widget
  **tails that file** and updates rows from it.
- **Completion sentinel (required):** the elevated applier writes a **terminal per-item status**
  (`done` / `failed`+reason) and a final **overall done record carrying the batch exit code**. The widget
  treats *"log stopped without a done record"* as **crashed**, not hung — the `.rc`/DONE-marker pattern
  used throughout this session. Both progress paths converge on the same row-status model.

## 10. False-positive handling (post-apply mismatch)

Computed by `check` from `last-apply.json` — **not** a passive "available for N checks" rule (that would
bury updates you are merely deferring). Trigger: for an item whose last recorded apply **succeeded**
(`exitCode 0`) at version V, if the next check still reports `available == V` (i.e. `current` never moved
to V), set `suspectStale=true`, drop it from the island count, and show it in the modal with a "likely
already current" note. Clears automatically once `current` advances. (The iCUE ARP-DisplayVersion-lag case.)

## 11. Concurrency & correctness

- **winget mutex:** a real named `System.Threading.Mutex` (`Global\OverlineWingetLock`) serializes ALL
  winget access — the scheduled checker, the modal's "Check now", and every apply. If held, the checker
  **skips and keeps the last-good cache** with `stale=true`. `status.json.wingetLocked` only *reports*
  this; it is never the lock itself.
- **Atomic status writes:** `check` writes to `status.json.tmp` then renames over `status.json`, so the
  island never reads a half-written file mid-refresh. Same temp-then-rename for `last-apply.json`.
- **scoop** likewise serialized against concurrent scoop runs.

## 12. Elevation model

- **Unelevated inline:** scoop and user-scope winget (running these elevated is wrong — e.g. user-scope
  winget refuses under admin, MSYS2-class errors).
- **Elevated helper:** machine-scope winget + Windows Update go through `apply-elevated.ps1`, launched
  once via `Start-Process -Verb RunAs` (one UAC per user-initiated batch). The helper is a **fixed,
  ACL-protected script taking a data-only job file** (list of ids), never caller-supplied code, and runs
  as the interactive user with highest privileges (not SYSTEM — winget's app alias won't resolve there).

## 13. Silent vs interactive

- A maintained `interactive-overrides.json` (seeded from this session: `Corsair.iCUE.5` = interactive,
  etc.) plus an installer-type heuristic.
- Unknown → **try silent; on failure surface an "interactive" button** for that row, and auto-promote the
  id into the overrides list so it's labelled correctly next time.
- The row badge shows best-known state.

## 14. Desktop-icon sweep

Snapshot the `.lnk` files present before an apply batch, run the batch, then delete any `.lnk` that
newly appeared. Installer-agnostic; no per-package config.
- **(F)** The **user Desktop** sweep runs in the unelevated applier. The **Public Desktop** sweep needs
  elevation, so it runs **only** in the elevated applier — an unelevated scoop-only batch cannot clean a
  Public-desktop shortcut (rare in practice; noted so it isn't a silent gap).

## 15. Open question for spec review — RESOLVED

**Should "Update everything" include Windows Update drivers?** **Default: no.** Reviewed with the advisor
(fable, 2026-07-22): the risk is **real but calibrated** — WU drivers are WHQL-signed, won't brick, and
every regression is reversible (Device Manager → Roll Back Driver, or reinstall the vendor package), but
they lag vendor drivers and can overwrite a newer vendor driver with an older one. The risk is
**apply-time only** (checking is free/safe) and **concentrated in display-class drivers** (this machine's
list is the AMD iGPU, not the RTX 5090; input/audio/SoftwareComponent shims are low-stakes). Decision:
count them, own group, own button, **out of one-click by default**, with a caveat badge on display-class
rows only (§8). A single flag flips the one-click default if desired.

## 16. Testing

The engine is the fragile part and is tested standalone, without Zebar:
- **Engine functions** run against **mocked tool output** (captured `winget`/`scoop`/WUA fixtures) so
  parsing, ignore-merge, and `suspectStale` logic are unit-testable offline.
- **`apply` supports `-WhatIf`** — a dry run that logs exactly what it *would* upgrade, what it would
  elevate, and which `.lnk`s it would sweep, without touching the system. Makes the elevation and
  desktop-sweep paths safe to iterate.
- Widget layer is verified against hand-written `status.json` fixtures covering the empty, stale,
  all-drivers, mixed-scope, and `suspectStale` states.

## 17. Build order

1. **Engine + cache:** `UpdateEngine.psm1` + `check.ps1` writing `status.json`; scheduled task; mocked-
   output tests. Testable with zero Zebar involvement.
2. **Island (read-only):** `UpdateIsland` reads the cache, shows count + icons, auto-hides.
3. **Modal (read-only):** `update-panel` popup listing channels/items, hidden section.
4. **Apply:** scoop inline first (unelevated, safe to iterate) → elevated helper for winget/WU → the
   two progress paths (§9) → desktop sweep → hide/ignore + false-positive flagging.

Each step is independently shippable; the risky elevation/apply work comes last.
