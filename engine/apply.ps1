# apply.ps1 — apply updates from a job file. Runs the unelevated pass (scoop + user-scope
# winget) inline; machine-scope winget and Windows Update are bundled to apply-elevated.ps1
# (Task 12). Emits STATUS lines to a run-log the widget tails, and records outcomes to
# last-apply.json. -WhatIf reports the plan without touching the system.
param(
    [string]$Job,                 # explicit job file (tests)
    [string]$Ids,                 # comma-separated ids (widget: per-item)
    [string]$Channel,             # a channel key (widget: update all in channel)
    [switch]$All,                 # update everything
    [switch]$IncludeDrivers,      # include WU drivers in All/Channel sweeps
    [string]$Root = (Join-Path $env:LOCALAPPDATA 'overline-updates'),
    [string]$RunLog,
    [string]$RunId,               # widget passes a plain id; the log path is resolved here
    [switch]$WhatIf
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'UpdateEngine.psm1') -Force

if (-not (Test-Path $Root)) { New-Item -ItemType Directory -Path $Root -Force | Out-Null }
$lastApplyPath = Join-Path $Root 'last-apply.json'
if (-not $RunLog) {
    if ($RunId) { $RunLog = Join-Path $Root "run-$RunId.log" }
    else { $RunLog = Join-Path $Root ("run-" + [guid]::NewGuid().ToString('N') + '.log') }
}
function Log($m) { Add-Content -LiteralPath $RunLog -Value $m }

# Build the item list. NB: do NOT reuse $job — the param is [string]$Job and PS variable
# names are case-insensitive, so assigning the parsed object to $job would coerce it to string.
if ($Job) {
    $jobData = Get-Content -LiteralPath $Job -Raw | ConvertFrom-Json
    $items = @($jobData.items)
    $includeDrivers = [bool]$jobData.includeDrivers
} else {
    $status = Read-JsonFile (Join-Path $Root 'status.json')
    $pool = @()
    if ($status) { foreach ($ch in 'scoop', 'winget', 'windowsUpdate') { $pool += @($status.channels.$ch.items) } }
    $pool = @($pool | Where-Object { $_ -and -not $_.suspectStale })
    $includeDrivers = [bool]$IncludeDrivers
    if ($Ids) {
        $idList = $Ids -split ','
        $items = @($pool | Where-Object { $idList -contains $_.id })   # explicit ids apply as asked
    } elseif ($Channel) {
        $items = @($pool | Where-Object { $_.channel -eq $Channel })
        if (-not $includeDrivers) { $items = @($items | Where-Object { -not $_.driver }) }
    } elseif ($All) {
        $items = $pool
        if (-not $includeDrivers) { $items = @($items | Where-Object { -not $_.driver }) }
    } else {
        $items = @()
    }
}
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

# Bundle everything that needs elevation (machine-scope winget + Windows Update) into ONE
# RunAs launch of apply-elevated.ps1, which appends to the SAME run-log and writes the DONE
# sentinel. Drivers are excluded unless the job opted in.
$elevated = @($items | Where-Object { $_.channel -eq 'windowsUpdate' -or ($_.channel -eq 'winget' -and $_.scope -eq 'machine') })
if (-not $includeDrivers) {
    $elevated = @($elevated | Where-Object { -not ($_.channel -eq 'windowsUpdate' -and $_.driver) })
}

if ($elevated.Count) {
    $elevJob = Join-Path $Root ('elevjob-' + [guid]::NewGuid().ToString('N') + '.json')
    @{ items = $elevated; includeDrivers = [bool]$includeDrivers } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $elevJob
    $elevScript = Join-Path $PSScriptRoot 'apply-elevated.ps1'
    Log "ELEVATE launching $($elevated.Count) item(s) (one UAC)"
    Start-Process pwsh -Verb RunAs -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $elevScript, '-Job', $elevJob, '-Root', $Root, '-RunLog', $RunLog
    # apply-elevated.ps1 writes the DONE sentinel once it finishes.
} else {
    Log 'DONE 0'
}
Write-Host "run-log: $RunLog"
