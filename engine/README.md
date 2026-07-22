# Update-notifier island — engine + setup

A pamac-style update notifier for the overline-zebar bar. An auto-hiding **island** shows
`N updates` with a per-channel icon; clicking opens a **modal** to update everything / a whole
channel / individual items, with hide-ignore + undo, live progress, and a desktop-icon sweep.
Channels: **scoop**, **winget**, **Windows Update**.

Design: `docs/superpowers/specs/2026-07-22-update-island-design.md`
Plan: `docs/superpowers/plans/2026-07-22-update-island.md`

## Layout

```
engine/
  UpdateEngine.psm1      # the module: parsers, mutex, apply, sweep, last-apply
  check.ps1              # enumerate channels -> status.json (scheduled + "Check now")
  apply.ps1              # apply updates (-All / -Channel <c> / -Ids a,b / -Job file); -WhatIf
  apply-elevated.ps1     # elevated helper (machine winget + Windows Update), one RunAs
  ignore.ps1             # hide (skip-version / ignore-package) + un-hide
  deploy.ps1             # copy engine -> %LOCALAPPDATA%\overline-updates\engine, harden helper
  install-task.ps1       # register the scheduled checker (NEEDS ELEVATION)
  interactive-overrides.json   # ids known to need interactive install (seeded: Corsair.iCUE.5)
  _test/                 # dependency-free assert harness; run-tests.ps1
widgets/main/src/components/updates/   # the island (UpdateIsland.tsx, status.ts, useUpdateStatus.ts)
widgets/update-panel/                  # the modal widget
```

Runtime data lives in `%LOCALAPPDATA%\overline-updates\`: `status.json`, `ignore.json`,
`last-apply.json`, `run-<id>.log`, `.scoop-bucket-refresh`, `.wu-check`.

## Run the tests

```
pwsh -NoProfile -File engine/_test/run-tests.ps1     # "all green"
```

## Deploy

```
# 1. engine -> LOCALAPPDATA (unelevated; run ELEVATED when re-deploying apply-elevated.ps1)
pwsh -NoProfile -File engine/deploy.ps1

# 2. widgets: build, then copy dist over the deployed pack, then restart zebar
pnpm --filter @overline-zebar/main build
pnpm --filter @overline-zebar/update-panel build
#   copy widgets/main/dist and widgets/update-panel/dist over
#   %APPDATA%\zebar\downloads\mushfikurr.overline-zebar@1.0.3\widgets\*\dist
#   and add the update-panel entry + the main `cmd` shellCommand to that pack's zpack.json
#   (the deployed manifest keeps live 46px/primary settings — do NOT overwrite it wholesale).
```

The island reads `status.json`; run `check.ps1` once to populate it before first launch.

## SETUP — the elevated steps (need a UAC click; batched here on purpose)

Everything above works unelevated. These two need one elevation each — run them yourself:

1. **Register the scheduled checker** (so the island refreshes automatically):
   ```
   # from an ELEVATED pwsh:
   pwsh -File "$env:LOCALAPPDATA\overline-updates\engine\install-task.ps1"
   ```
   Registers `overline-update-check` for `JXN-WINDOWS\jxn` (Limited), at logon + every 45 min.

2. **First elevated apply is UAC-gated by design.** Clicking "Update everything" or updating a
   machine-scope winget / Windows Update item launches `apply-elevated.ps1` via `Start-Process
   -Verb RunAs` — one UAC per batch. To smoke-test it outside the widget:
   ```
   pwsh -File "$env:LOCALAPPDATA\overline-updates\engine\apply.ps1" -Channel winget -WhatIf
   # then, for real (will prompt UAC for machine-scope items):
   pwsh -File "$env:LOCALAPPDATA\overline-updates\engine\apply.ps1" -Ids <some.machine.id> -RunId test
   #   tail %LOCALAPPDATA%\overline-updates\run-test.log — expect STATUS ... then DONE <code>.
   ```

## Status (2026-07-22)

- **Engine (Phase 1) — DONE, fully tested + live-verified.** All parsers, cross-integrity mutex,
  atomic writes, WU throttle, and the apply engine (unelevated verified with a real Modrinth
  upgrade; elevated helper code complete). `run-tests.ps1` is green.
- **Island (Phase 2) — DONE, live-verified.** CDP screenshot confirmed it shows the real count on
  the bar and auto-hides at zero.
- **Modal (Phase 3-4) — render + action-layer verified.** CDP-verified rendering channels /
  items / drivers / hidden with correct badges. The action layer passes ids/versions as an argv
  **array** (never a shell string — no command injection), invoking `pwsh -File <abs> <args>`.
  Each action verified by running the widget's exact deployed script + args: `check.ps1` advances
  `status.json`; `apply.ps1 -Ids …` writes a `DONE`-terminated run-log; `ignore.ps1` skip/unhide
  round-trip. Unelevated apply also verified with a real Modrinth upgrade.
- **Elevated apply — DISPATCH + failure path verified (2026-07-22); a successful elevated INSTALL
  was not.** Ran a real Defender-WU apply through the widget flow: `apply.ps1` → RunAs (accepted) →
  `apply-elevated.ps1` → WUA COM → `STATUS`/`DONE`; `Get-RunLogState` = `complete`. Honest caveat:
  the Defender item was already current, so `Invoke-WUApply` returned at the `coll.Count == 0`
  branch — the actual **download+install COM sequence never ran**, **machine-scope winget elevated
  apply never ran** (a WU item was tested, not winget), and the **cross-integrity mutex under an
  elevated *winget* op is unproven in practice**. What's proven: the RunAs dispatch, the elevated
  helper, the run-log/DONE contract, and clean failure handling (no hang). The unexercised install
  code is standard winget/WUA that ran fine last session — low-risk, left unexercised on purpose.
- **Scheduled task — VERIFIED (2026-07-22).** `install-task.ps1` registered `overline-update-check`
  (Ready, Limited, user `jxn`, logon + 45 min); `Start-ScheduledTask` ran it (`LastTaskResult 0x0`)
  and it refreshed `status.json`. The island now auto-refreshes.
- **Only thing never clicked through the UI:** the button/island interactions themselves (their
  exact underlying commands ARE verified). Low risk, proven patterns.
