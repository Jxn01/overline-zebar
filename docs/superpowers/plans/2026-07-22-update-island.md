# Update-Notifier Island — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a pamac-style update-notifier island for overline-zebar: a PowerShell "engine" that checks scoop/winget/Windows Update and writes a JSON cache, a scheduled task that runs it, an auto-hiding island that shows the count, and a modal to apply updates (all / per-channel / per-item) with hide/ignore, live progress, and a desktop-icon sweep.

**Architecture:** Thin React widget over a PowerShell engine. One `UpdateEngine.psm1` serves both a scheduled `check.ps1` (writes `status.json`) and an `apply.ps1` (upgrades, elevating machine-scope winget + Windows Update through a fixed `apply-elevated.ps1`). The widget reads JSON and fires actions via Zebar's `shellExec`/`shellSpawn`.

**Tech Stack:** PowerShell 7.6, `Microsoft.WinGet.Client` module (winget data), WUA COM (Windows Update), Zebar 3.1.1 (`shellExec`/`shellSpawn`, zpack `shellCommands`), React 18 + TypeScript + Tailwind + `@overline-zebar/ui`, pnpm 9, Vite. Deploy via the `zebar-overline-build` recipe.

## Global Constraints

- **Zebar pinned to 3.1.1** — build commit `e8e2ded` (branch `build-zebar-3.1.1`), pnpm catalog `zebar:` = `'3.1.1'`. Never bump to 3.3.x. (from `zebar-overline-build` memory)
- **The Windows account name can differ from the profile folder name.** Always use the *account* name (`$env:USERNAME`) for scheduled tasks and ACLs — passing a profile-folder name that is not a real account fails with "No mapping between account names and security IDs was done".
- **Engine root:** `%LOCALAPPDATA%\overline-updates\`. Scripts under `engine\`, data files at the root.
- **Repo engine source:** `engine/` at the repo root; deployed by copy to the LOCALAPPDATA engine dir.
- **All winget access serialized** behind a named mutex `Global\OverlineWingetLock`.
- **status.json / last-apply.json written atomically** (temp + rename).
- **Elevated helper** = fixed script + data-only job file, run as interactive user with highest privileges (NOT SYSTEM). One UAC per user-initiated batch.
- **PowerShell only for engine** (this machine is PS-first). Test harness dependency-free (custom `Assert`), no Pester requirement.

---

## Phase 1 — Engine + cache

### Task 1: Test harness + repo scaffolding

**Files:**
- Create: `engine/_test/Assert.ps1`
- Create: `engine/_test/run-tests.ps1`
- Create: `engine/UpdateEngine.psm1` (empty stub with `Export-ModuleMember`)

**Interfaces:**
- Produces: `Assert-Equal $actual $expected $name`, `Assert-True $cond $name`, `Assert-Throws {…} $name`; `run-tests.ps1` dot-sources every `*.tests.ps1` under `engine/_test/` and exits non-zero on any failure.

- [ ] **Step 1: Write the assert harness**

`engine/_test/Assert.ps1`:
```powershell
$script:Failures = 0
function Assert-Equal($actual, $expected, $name) {
    $a = ($actual | ConvertTo-Json -Compress -Depth 10); $e = ($expected | ConvertTo-Json -Compress -Depth 10)
    if ($a -ne $e) { $script:Failures++; Write-Host "FAIL: $name`n  expected: $e`n  actual:   $a" -ForegroundColor Red }
    else { Write-Host "ok: $name" -ForegroundColor Green }
}
function Assert-True($cond, $name) {
    if (-not $cond) { $script:Failures++; Write-Host "FAIL: $name (expected true)" -ForegroundColor Red }
    else { Write-Host "ok: $name" -ForegroundColor Green }
}
function Assert-Throws([scriptblock]$block, $name) {
    try { & $block; $script:Failures++; Write-Host "FAIL: $name (no throw)" -ForegroundColor Red }
    catch { Write-Host "ok: $name" -ForegroundColor Green }
}
```

- [ ] **Step 2: Write the runner**

`engine/_test/run-tests.ps1`:
```powershell
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/Assert.ps1"
Get-ChildItem "$PSScriptRoot" -Filter '*.tests.ps1' | ForEach-Object { Write-Host "`n== $($_.Name) ==" -ForegroundColor Cyan; . $_.FullName }
if ($script:Failures -gt 0) { Write-Host "`n$script:Failures failure(s)" -ForegroundColor Red; exit 1 } else { Write-Host "`nall green" -ForegroundColor Green; exit 0 }
```

- [ ] **Step 3: Stub module** — `engine/UpdateEngine.psm1` with a header comment and `Export-ModuleMember -Function *`.

- [ ] **Step 4: Run** `pwsh -NoProfile -File engine/_test/run-tests.ps1` → Expected: "all green" (no tests yet).

- [ ] **Step 5: Commit** `git add engine && git commit -m "chore(update-island): engine test harness + module stub"`

### Task 2: winget output parsing (structured + table fallback)

**Files:**
- Modify: `engine/UpdateEngine.psm1`
- Test: `engine/_test/winget.tests.ps1`
- Fixture: `engine/_test/fixtures/winget-table.txt` (paste a real `winget upgrade --include-unknown` capture)

**Interfaces:**
- Produces: `ConvertFrom-WingetTable([string[]]$lines) -> Item[]` and `Get-WingetUpdates([switch]$UseModule) -> Item[]`. `Item` = PSCustomObject `{channel,id,name,current,available,scope,interactive,driver,driverClass,rebootHint,suspectStale}`.

- [ ] **Step 1: Failing test** — `winget.tests.ps1`: load fixture lines, call `ConvertFrom-WingetTable`, assert it returns the expected ids/versions and skips the header/separator + the "N upgrades available" footer and the "require explicit targeting" tail.
```powershell
Import-Module "$PSScriptRoot/../UpdateEngine.psm1" -Force
$lines = Get-Content "$PSScriptRoot/fixtures/winget-table.txt"
$items = ConvertFrom-WingetTable $lines
Assert-True ($items.Count -ge 1) 'winget: parses at least one row'
$m = $items | Where-Object id -eq 'Modrinth.ModrinthApp'
Assert-Equal $m.available '0.15.14' 'winget: parses available version'
Assert-Equal $m.channel 'winget' 'winget: sets channel'
```

- [ ] **Step 2: Run → FAIL** (`ConvertFrom-WingetTable` not defined).

- [ ] **Step 3: Implement** `ConvertFrom-WingetTable` — locate the header row (`Name … Id … Version … Available … Source`), compute column start offsets from the header, slice each subsequent row by offsets until the blank line / footer sentinel (`upgrades available` / `require explicit targeting`). Emit an `Item` per data row (`scope='machine'` default, refined later; `driver=$false`). `Get-WingetUpdates`: if `Microsoft.WinGet.Client` present, use `Get-WinGetPackage | ? IsUpdateAvailable` and map (authoritative per spec §6-D); else run `winget upgrade --include-unknown` and pipe through `ConvertFrom-WingetTable`.

- [ ] **Step 4: Run → PASS.**

- [ ] **Step 5: Commit** `feat(update-island): winget update parsing`.

### Task 3: scoop parsing

**Files:** Modify `engine/UpdateEngine.psm1`; Test `engine/_test/scoop.tests.ps1`; Fixture `engine/_test/fixtures/scoop-status.txt`.

**Interfaces:** Produces `ConvertFrom-ScoopStatus([string[]]$lines) -> Item[]`, `Get-ScoopUpdates() -> Item[]`.

- [ ] **Step 1: Failing test** — assert the fixture (a `scoop status` table with `Name / Installed Version / Latest Version`) parses to items with `channel='scoop'`, `scope='user'`, correct `current`/`available`.
- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3: Implement** — parse the table (header-offset method like winget), skip the WARN/"Everything is ok!" lines. `Get-ScoopUpdates` runs `scoop status` (assume buckets refreshed by the scheduled task) and parses.
- [ ] **Step 4: Run → PASS.**
- [ ] **Step 5: Commit** `feat(update-island): scoop update parsing`.

### Task 4: Windows Update (WUA COM) + driver classification

**Files:** Modify `engine/UpdateEngine.psm1`; Test `engine/_test/wu.tests.ps1`.

**Interfaces:** Produces `Get-DriverClass([string]$title) -> string` (`display|input|audio|other`) and `Get-WindowsUpdates() -> Item[]` (`channel='windowsUpdate'`, `scope='machine'`, `driver` bool, `driverClass` set for drivers, `rebootHint=$true`).

- [ ] **Step 1: Failing test** — `Get-DriverClass` is pure and unit-testable: assert `'AMD ... Display Driver ...' -> 'display'`, `'Razer ... Mouse ...' -> 'input'`, `'... AudioProcessingObject ...' -> 'audio'`, `'... SoftwareComponent ...' -> 'other'`.
- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3: Implement** `Get-DriverClass` (regex on title: `display|graphics|video` → display; `mouse|keyboard|hid|input` → input; `audio|realtek.*audio|apo` → audio; else other). `Get-WindowsUpdates`: `New-Object -ComObject Microsoft.Update.Session`, `CreateUpdateSearcher()`, search `"IsInstalled=0 and IsHidden=0"`; map each update, `driver = ($_.Type -eq 2 -or categories match 'Drivers')`, `driverClass = Get-DriverClass $_.Title`. Wrap in try/catch → return `@()` + surface error to caller.
- [ ] **Step 4: Run → PASS.**
- [ ] **Step 5: Commit** `feat(update-island): windows update + driver classification`.

### Task 5: ignore/last-apply merge + suspectStale

**Files:** Modify `engine/UpdateEngine.psm1`; Test `engine/_test/merge.tests.ps1`.

**Interfaces:** Produces `Read-IgnoreStore($path)`, `Read-LastApply($path)`, `Read-InteractiveOverrides($path)`, `Merge-IgnoreStaleInteractive([Item[]]$items, $ignore, $lastApply, $overrides) -> Item[]` (drops `ignorePackage` + matching `skipVersion`; sets `suspectStale=$true` when `lastApply[id].exitCode -eq 0 -and lastApply[id].appliedVersion -eq item.available`; sets `item.interactive = $overrides[id] ? 'yes' : (installer-type heuristic)` — **fable fix #2: `interactive` is populated HERE at check time, else every badge reads "unknown"**).

- [ ] **Step 1: Failing test** — build items + a fake ignore store + a fake last-apply + a fake overrides map; assert an ignored package is removed, a skip-version match is removed, an item whose applied version still equals `available` gets `suspectStale=$true`, an item with no last-apply stays `suspectStale=$false`, and an id present in overrides gets `interactive='yes'`.
- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3: Implement** the four functions (JSON read with `-Raw | ConvertFrom-Json`, null-safe defaults; overrides is `{ "Corsair.iCUE.5": "yes" }`).
- [ ] **Step 4: Run → PASS.**
- [ ] **Step 5: Commit** `feat(update-island): ignore + false-positive merge`.

### Task 6: mutex + atomic write + `check.ps1`

**Files:** Create `engine/check.ps1`; Modify `engine/UpdateEngine.psm1` (add `Write-StatusAtomic`, `Invoke-WithWingetLock`); Test `engine/_test/io.tests.ps1`.

**Interfaces:** Produces `Write-StatusAtomic($obj, $path)` (write `$path.tmp`, `Move-Item -Force`), `Get-WingetMutex() -> Mutex` and `Invoke-WithWingetLock([scriptblock]$b, [int]$timeoutMs) -> result|$null`. `check.ps1` orchestrates: acquire lock (skip winget if busy, keep last-good with `stale=true`), gather all channels, merge, `Write-StatusAtomic`.

**CRITICAL (fable review) — cross-integrity mutex:** the lock is shared between the *unelevated* checker/widget and the *elevated* applier. A default-security `Global\` mutex throws `UnauthorizedAccessException` (or hands back a non-shared object) when opened from a different integrity level. `Get-WingetMutex` MUST use the try-`OpenExisting`-else-create pattern with an explicit `System.Security.AccessControl.MutexSecurity` granting `Everyone` (`new SecurityIdentifier(WorldSid)`) `MutexRights::FullControl`, via the `Mutex(initiallyOwned:$false, name, [ref]createdNew, mutexSecurity)` constructor. Same-integrity tests pass regardless, so this is verified live in Task 12, but built here.

- [ ] **Step 1: Failing test** — `Write-StatusAtomic` writes valid JSON and leaves no `.tmp`; `Invoke-WithWingetLock` returns the block's value when free and `$null` when the mutex is already held (acquire it in the test first).
- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3: Implement** both; write `check.ps1` (dot-imports the module, resolves the LOCALAPPDATA root, calls Get-* for each channel guarded by per-channel try/catch → `error` field, winget wrapped in `Invoke-WithWingetLock`, merges ignore + last-apply, writes status atomically).
- [ ] **Step 4: Run → PASS**, then run `check.ps1` for real → inspect `status.json` has all three channels.
- [ ] **Step 5: Commit** `feat(update-island): check.ps1 + atomic writes + winget mutex`.

### Task 7: scheduled task installer

**Files:** Create `engine/install-task.ps1`, `engine/deploy.ps1`.

**Interfaces:** `deploy.ps1` copies `engine/*` → `%LOCALAPPDATA%\overline-updates\engine\` (ACL: remove inherited write for non-admins on `apply-elevated.ps1`). `install-task.ps1` registers `overline-update-check` (per-user, trigger: logon + every 45 min; action: `pwsh -NoProfile -WindowStyle Hidden -File …\engine\check.ps1`; `scoop update` bucket-refresh folded into check on a 6-run counter).

- [ ] **Step 1:** Write `deploy.ps1` (copy + `icacls` hardening of `apply-elevated.ps1`).
- [ ] **Step 2:** Write `install-task.ps1` using `Register-ScheduledTask` (principal `$env:USERDOMAIN\$env:USERNAME`, `RunLevel Limited`).
- [ ] **Step 3:** Run both; `Get-ScheduledTask overline-update-check` shows Ready; `Start-ScheduledTask` then confirm `status.json` refreshes.
- [ ] **Step 4: Commit** `feat(update-island): deploy + scheduled checker`.

---

## Phase 2 — Island (read-only)

### Task 8: status hook + UpdateIsland component

**Files:**
- Create: `widgets/main/src/components/updates/useUpdateStatus.ts`
- Create: `widgets/main/src/components/updates/UpdateIsland.tsx`
- Create: `widgets/main/src/components/updates/status.ts` (types + `actionableCount`)
- Modify: `widgets/main/src/App.tsx` (insert `<UpdateIsland/>` between `Stats </Chip>` and `<Media/>`)
- Modify: `zpack.json` (`main.privileges.shellCommands`: allow `pwsh`/`type` reading the engine dir)

**Interfaces:**
- Consumes: engine `status.json`.
- Produces: `type UpdateStatus`, `type UpdateItem`; `actionableCount(status): {total, perChannel}` excluding hidden/`suspectStale`; `useUpdateStatus()` polling hook.

- [ ] **Step 1:** Define `status.ts` types mirroring spec §5 + `actionableCount` (drivers **included** in total; excludes `suspectStale`). Add a tiny fixture-based sanity check in `widgets/main/src/components/updates/status.test.ts` (vitest if present; else a `// @check` note run manually) — count of a fixture with 1 suspectStale + 2 real = 2.
- [ ] **Step 2:** `useUpdateStatus()` — reads the JSON via `zebar.shellExec('cmd', ['/c','type','%LOCALAPPDATA%\\overline-updates\\status.json'])` (**fable fix #3: `cmd /c type` on the hot path — no ~0.5s pwsh cold-start every poll; pwsh is reserved for infrequent apply actions**), parses, re-polls every 60 s and on window focus. Reading a local file via shellExec sidesteps the SW cache — see `zebar-overline-build`. Missing file → treat as zero updates.
- [ ] **Step 3:** `UpdateIsland.tsx` — `const {status} = useUpdateStatus(); const {total, perChannel} = actionableCount(status); if (!total) return null;` render `<Chip as="button" onClick={openUpdatePanel}>` with a sync/refresh lucide icon, the number, and a small per-channel icon row (scoop/winget/windows). Copy the `Media` null-return auto-hide idiom.
- [ ] **Step 4:** Wire into `App.tsx` (add `openUpdatePanel` via the existing `openPanel` helper, `'update-panel','360px','520px'`). Add the `main` shellCommands entry.
- [ ] **Step 5:** `pnpm build`, deploy dist per recipe, restart zebar; with a hand-written `status.json` (2 real + 1 suspectStale + 1 driver) confirm the island shows **3** and hides when the file has zero actionable. Capture twice (per verification lesson).
- [ ] **Step 6: Commit** `feat(update-island): auto-hiding island reading status.json`.

---

## Phase 3 — Modal (read-only)

### Task 9: update-panel widget scaffold + registration

**Files:**
- Create: `widgets/update-panel/` (scaffold from `widgets/forecast`: `index.html`, `src/main.tsx`, `src/App.tsx`, `vite.config.ts`, `package.json`, `tsconfig.json`)
- Modify: `zpack.json` (register `update-panel`: `htmlPath`, `transparent:true`, `focused:true`, preset `top_center` offY 54, 360×520; `privileges.shellCommands` = `pwsh` against the engine dir)

**Interfaces:** Consumes `status.json`. Produces the popup that closes on `tauri://blur`/Escape (copy forecast's `useEffect`).

- [ ] **Step 1:** Copy forecast widget dir → `update-panel`, rename package, strip forecast-specific code, keep the close-on-blur/Escape effect and the `bg-background-deeper/95 backdrop-blur-xl rounded-2xl` shell.
- [ ] **Step 2:** Register in `zpack.json`; add to the pnpm workspace build.
- [ ] **Step 3:** `pnpm build`; open via the island click; confirm an empty panel appears under the bar and closes on blur/Escape.
- [ ] **Step 4: Commit** `feat(update-island): update-panel popup scaffold`.

### Task 10: channel groups + item rows + hidden section (read-only)

**Files:** Create `widgets/update-panel/src/components/{ChannelGroup,ItemRow,HiddenSection}.tsx`; Modify `widgets/update-panel/src/App.tsx`.

**Interfaces:** Consumes `UpdateStatus` (shared type copied into the panel or imported from `@overline-zebar/ui` if promoted). Produces the rendered tree; badges from `item.interactive`, `item.driver`, `item.driverClass==='display'` (caveat), `item.rebootHint`.

- [ ] **Step 1:** `ItemRow` — `name  current → available` + badges (silent/interactive, driver, display-caveat, reboot) + placeholder `Update` and hide buttons (no-ops this task).
- [ ] **Step 2:** `ChannelGroup` — header (icon, name, count, `Update all` placeholder), expand/collapse, maps rows; WU drivers render as a nested collapsed sub-group.
- [ ] **Step 3:** `HiddenSection` — lists `ignore.json` entries (read via shellExec) with `un-hide` placeholder.
- [ ] **Step 4:** `App.tsx` — header (`Update everything` + `Check now` placeholders), maps channel groups, mounts hidden section. Style to the OLED theme.
- [ ] **Step 5:** `pnpm build`, deploy; against the fixture `status.json` confirm all three channels, badges, driver sub-group, and a hidden entry render correctly. Screenshot.
- [ ] **Step 6: Commit** `feat(update-island): modal channel/item/hidden rendering`.

---

## Phase 4 — Apply

### Task 11: `apply.ps1` (unelevated scoop/user-winget) + last-apply

**Files:** Create `engine/apply.ps1`; Modify `engine/UpdateEngine.psm1` (`Invoke-ScoopApply`, `Invoke-WingetApply`, `Write-LastApply`, `Write-DesktopSweepSnapshot`/`Complete-DesktopSweep` for the user desktop); Test `engine/_test/apply.tests.ps1`.

**Interfaces:** `apply.ps1 -Job <path>` where the job = `{items:[{channel,id,scope,interactive}], includeDrivers:bool}`. Produces per-item run-log lines `STATUS <id> updating|done|failed <reason>` + writes `last-apply.json`. Supports `-WhatIf`.

- [ ] **Step 1: Failing test** — `-WhatIf` on a job of 2 scoop items writes a plan log listing both as "would update", touches nothing, writes no `last-apply.json`. Desktop-sweep snapshot/complete: create a temp "desktop", snapshot, add a `.lnk`, complete → the new `.lnk` is removed, pre-existing ones remain.
- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3: Implement** `apply.ps1`: read job; snapshot user-desktop `.lnk`; for each unelevated item run scoop/user-winget with the run-log `STATUS` protocol and capture exit code → `Write-LastApply`; complete the desktop sweep. Elevated items are deferred to Task 12 (this task handles only `scope=user`/scoop).
- [ ] **Step 4: Run → PASS**; then a real dry-run `apply.ps1 -Job … -WhatIf` against the live `status.json`.
- [ ] **Step 5: Commit** `feat(update-island): unelevated apply + desktop sweep + last-apply`.

### Task 12: `apply-elevated.ps1` + one-UAC bundling + completion sentinel

**Files:** Create `engine/apply-elevated.ps1`; Modify `engine/apply.ps1` (bundle elevated items, launch once via RunAs), `engine/UpdateEngine.psm1` (`Invoke-WingetApply -Machine`, `Invoke-WUApply`, Public-desktop sweep); Test `engine/_test/elevated.tests.ps1`.

**Interfaces:** `apply.ps1` writes an elevated job file and launches `Start-Process pwsh -Verb RunAs -ArgumentList '-File apply-elevated.ps1 -Job <file>'`. `apply-elevated.ps1` runs machine-winget + WU (drivers only if `includeDrivers`), writes `STATUS` lines, then a terminal `DONE <exitcode>` sentinel; also does the Public-desktop sweep.

- [ ] **Step 1: Failing test** — parse a sample elevated run-log: a log ending with `DONE 0` → `complete`; a log with `STATUS x updating` and no `DONE` → `crashed`. (Pure log-interpretation function `Get-RunLogState([string[]]$lines)` in the module, unit-tested.)
- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3: Implement** `Get-RunLogState`, `apply-elevated.ps1` (guarded per item, WU via COM downloader+installer, sentinel write in a `finally`), and the RunAs bundling in `apply.ps1` (all elevated ids → one job → one UAC). Serialize under the winget mutex.
- [ ] **Step 4: Run → PASS**; real test: elevate-update one safe machine-scope package end-to-end, confirm the sentinel + `last-apply.json`.
- [ ] **Step 5: Commit** `feat(update-island): elevated applier, one-UAC bundle, completion sentinel`.

### Task 13: wire the modal to apply (progress forks) + hide/ignore + check-now

**Files:** Modify `widgets/update-panel/src/App.tsx`, `ItemRow.tsx`, `ChannelGroup.tsx`, `HiddenSection.tsx`; Create `widgets/update-panel/src/useApply.ts`.

**Interfaces:** `useApply()` — for unelevated items streams via `zebar.shellSpawn('pwsh', ['-File','…apply.ps1','-Job',jobPath])` `onStdout` parsing `STATUS` lines; for elevated batches launches `apply.ps1` (which RunAs-launches the helper) and **tails** `run-<id>.log` via a `shellExec` poll, applying `Get-RunLogState` semantics (crashed vs done). Hide → writes `ignore.json` (+ `winget pin` for winget ignore-package) via `apply.ps1 -Hide`. `Check now` → `check.ps1`, guarded: if mutex busy, show "update in progress".

- [ ] **Step 1:** `useApply` with the two progress paths + a `rowStatus` map feeding `ItemRow`.
- [ ] **Step 2:** Wire `Update` (row), `Update all in channel`, `Update everything` (unelevated inline + one elevated bundle; **excludes drivers** unless the driver group's own button), the driver group's `Update all drivers`, hide/ignore + un-hide, and `Check now`.
- [ ] **Step 3:** Add every engine command to the `update-panel` `shellCommands` allowlist.
- [ ] **Step 4:** `pnpm build`, deploy; end-to-end: update a real scoop app from the modal (watch live streamed rows), update a real machine-scope winget item (watch tailed rows + one UAC), hide/un-hide an item, `Check now`. Screenshot each.
- [ ] **Step 5: Commit** `feat(update-island): modal apply, progress forks, hide/ignore, check-now`.

### Task 14: end-to-end verification + docs

**Files:** Modify `docs/superpowers/specs/2026-07-22-update-island-design.md` (status → Implemented); add `engine/README.md`.

- [ ] **Step 1:** Full pass against live state: island count matches modal; `Update everything` bundles one UAC and skips drivers; a display driver shows the caveat badge; a false-positive (simulate: seed `last-apply.json` with an id whose `available` is unchanged) drops from the count; reboot dot appears for a `rebootHint` item.
- [ ] **Step 2:** Write `engine/README.md` (commands, file locations, how to run tests, how to deploy).
- [ ] **Step 3:** Flip spec status; final `git commit` + note remaining follow-ups if any.

---

## Self-Review notes

- **Spec coverage:** §3-4 → Tasks 1-7; §5 data model → Tasks 2-6,11-12; §6 channels → 2/3/4; §7 island → 8; §8 modal → 9/10/13; §9 progress forks → 12/13; §10 suspectStale → 5,14; §11 mutex/atomic → 6; §12 elevation → 12; §13 silent/interactive → 2,13 (badge) + overrides file seeded in 12; §14 desktop sweep → 11 (user) / 12 (public); §15 drivers → 8 (count) / 10,13 (group+exclude) ; §16 testing → harness in 1, per-task tests; §17 build order → phase order.
- **Interactive-overrides.json** seeded in Task 12 (deploy) — referenced by Task 13 badges.
- **Type consistency:** `Item`/`UpdateItem` fields identical across engine (PS) and widget (TS): `channel,id,name,current,available,scope,interactive,driver,driverClass,rebootHint,suspectStale`.
