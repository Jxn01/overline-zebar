# Update-notifier island — engine + setup

A pamac-style update notifier for the overline-zebar bar. An auto-hiding **island** shows
`N updates` with a per-channel icon; clicking opens a **modal** to update everything / a whole
channel / individual items, with hide-ignore + undo, live progress, and a desktop-icon sweep.
Channels: **scoop**, **winget**, **Windows Update**.

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

## Known limitations

- **Every winget item defaults to `scope='machine'`** (the checker doesn't yet distinguish
  user-scope installs). Consequence: *every* winget "Update" routes through the elevated helper and
  pops a UAC — including genuinely **user-scope** apps (VS Code User, Cursor, Modrinth…). For most
  that's just an unnecessary prompt, but it's a **real failure mode**, not cosmetic: user-scope
  packages can misbehave under elevation (cf. the MSYS2 "cannot be operated on with administrator
  privileges" case in this machine's memory). Refining scope detection (e.g. from
  `Get-WinGetPackage`'s source/scope, or an ARP user-vs-machine lookup) is the highest-value future
  improvement. Decide it deliberately; don't treat it as a nicety.
- **Concurrent cross-integrity mutex contention is unproven** (see the elevated-apply note below):
  the ACL and mechanism are sound; a real unelevated-holds-while-elevated-opens race was not staged.

## SETUP — the elevated steps (need a UAC click; batched here on purpose)

Everything above works unelevated. These two need one elevation each — run them yourself:

1. **Register the scheduled checker** (so the island refreshes automatically):
   ```
   # from an ELEVATED pwsh:
   pwsh -File "$env:LOCALAPPDATA\overline-updates\engine\install-task.ps1"
   ```
   Registers `overline-update-check` for the current user (Limited), at logon + every 45 min.

2. **First elevated apply is UAC-gated by design.** Clicking "Update everything" or updating a
   machine-scope winget / Windows Update item launches `apply-elevated.ps1` via `Start-Process
   -Verb RunAs` — one UAC per batch. To smoke-test it outside the widget:
   ```
   pwsh -File "$env:LOCALAPPDATA\overline-updates\engine\apply.ps1" -Channel winget -WhatIf
   # then, for real (will prompt UAC for machine-scope items):
   pwsh -File "$env:LOCALAPPDATA\overline-updates\engine\apply.ps1" -Ids <some.machine.id> -RunId test
   #   tail %LOCALAPPDATA%\overline-updates\run-test.log — expect STATUS ... then DONE <code>.
   ```

## Status

In daily use. The engine's parsers, locking, atomic writes and apply paths are covered by `run-tests.ps1`;
the widget's actions run exactly the deployed scripts with arguments passed as an array (never a shell string).
