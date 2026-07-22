# apply.ps1 — apply updates from a job file. Runs the unelevated pass (scoop + user-scope
# winget) inline; machine-scope winget and Windows Update are bundled to apply-elevated.ps1
# (Task 12). Emits STATUS lines to a run-log the widget tails, and records outcomes to
# last-apply.json. -WhatIf reports the plan without touching the system.
param(
    [Parameter(Mandatory)][string]$Job,
    [string]$Root = (Join-Path $env:LOCALAPPDATA 'overline-updates'),
    [string]$RunLog,
    [switch]$WhatIf
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'UpdateEngine.psm1') -Force

if (-not (Test-Path $Root)) { New-Item -ItemType Directory -Path $Root -Force | Out-Null }
$lastApplyPath = Join-Path $Root 'last-apply.json'
if (-not $RunLog) { $RunLog = Join-Path $Root ("run-" + [guid]::NewGuid().ToString('N') + '.log') }
function Log($m) { Add-Content -LiteralPath $RunLog -Value $m }

# NB: do NOT reuse $job — the param is [string]$Job and PS variable names are case-insensitive,
# so assigning the parsed object to $job would coerce it back to a string.
$jobData = Get-Content -LiteralPath $Job -Raw | ConvertFrom-Json
$items = @($jobData.items)
$userDesktops = Get-UserDesktopPaths

if ($WhatIf) {
    foreach ($it in $items) { Log "WOULDUPDATE $($it.channel) $($it.id) scope=$($it.scope)" }
    Log 'WHATIF done (0 items applied)'
    Write-Host "run-log: $RunLog"
    return
}

$snap = Get-DesktopShortcutSnapshot $userDesktops
foreach ($it in $items) {
    if ($it.channel -eq 'windowsUpdate') { continue }                         # elevated only (Task 12)
    if ($it.channel -eq 'winget' -and $it.scope -eq 'machine') { continue }   # elevated only (Task 12)

    Log "STATUS $($it.id) updating"
    $code = -1
    try {
        if ($it.channel -eq 'scoop') {
            $code = Invoke-ScoopApply $it.id
        } elseif ($it.channel -eq 'winget') {
            $lr = Invoke-WithWingetLock { Invoke-WingetApply -Id $it.id -Interactive:($it.interactive -eq 'yes') } 300000
            $code = if ($lr.Acquired) { [int]$lr.Value } else { -2 }   # -2 = winget busy
        }
    } catch { $code = -1 }

    $ver = if ($it.available) { [string]$it.available } else { '' }
    Write-LastApply $lastApplyPath $it.id $ver ([int]$code)
    if ($code -eq 0) { Log "STATUS $($it.id) done" } else { Log "STATUS $($it.id) failed exit=$code" }
}

$removed = @(Complete-DesktopSweep $snap $userDesktops)
if ($removed.Count) { Log "SWEPT $($removed.Count) desktop shortcut(s)" }
Log 'DONE 0'
Write-Host "run-log: $RunLog"
