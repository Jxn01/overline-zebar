# check.ps1 — enumerate scoop / winget / Windows Update and write status.json atomically.
# Run by the scheduled task and by the modal's "Check now". Safe to run standalone.
param(
    [string]$Root = (Join-Path $env:LOCALAPPDATA 'overline-updates'),
    [switch]$RefreshScoopBuckets
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'UpdateEngine.psm1') -Force

if (-not (Test-Path $Root)) { New-Item -ItemType Directory -Path $Root -Force | Out-Null }
$statusPath    = Join-Path $Root 'status.json'
$ignorePath    = Join-Path $Root 'ignore.json'
$lastApplyPath = Join-Path $Root 'last-apply.json'
$overridesPath = Join-Path $PSScriptRoot 'interactive-overrides.json'

$ignore    = Read-IgnoreStore $ignorePath
$lastApply = Read-LastApply $lastApplyPath
$overrides = Read-InteractiveOverrides $overridesPath
$prev      = Read-JsonFile $statusPath
$nowIso    = (Get-Date).ToString('o')

function New-ChannelResult($items, $err, $stale = $false) {
    # @($null) is a 1-element array holding $null (an empty result binds positionally to $null),
    # so filter nulls to avoid phantom empty items.
    $arr = @(@($items) | Where-Object { $null -ne $_ })
    [pscustomobject]@{ checkedAt = $nowIso; stale = $stale; error = $err; items = $arr }
}

# Refresh scoop buckets at most every ~3h (a git pull of every bucket is slow), or on demand.
$bucketMarker = Join-Path $Root '.scoop-bucket-refresh'
$bucketsStale = -not (Test-Path $bucketMarker) -or ((Get-Date) - (Get-Item $bucketMarker).LastWriteTime).TotalHours -ge 3
if ($RefreshScoopBuckets -or $bucketsStale) {
    try { scoop update *> $null; Set-Content -LiteralPath $bucketMarker -Value (Get-Date -Format o) } catch { }
}

# scoop
$scoop = try { New-ChannelResult (Get-ScoopUpdates) $null } catch { New-ChannelResult @() $_.Exception.Message }

# winget under the mutex — if busy, keep last-good and mark stale
$wingetLocked = $false
$lockResult = Invoke-WithWingetLock { Get-WingetUpdates } 0
if (-not $lockResult.Acquired) {
    $wingetLocked = $true
    if ($prev -and $prev.channels.winget) {
        $winget = $prev.channels.winget; $winget.stale = $true
    } else { $winget = New-ChannelResult @() $null $true }
} else {
    $winget = New-ChannelResult (@($lockResult.Value)) $null
}

# windows update: the WUA COM search is slow, so run it at most every ~4h (spec 6);
# between checks carry forward the last-good WU channel so the count doesn't blink to zero.
$wuMarker = Join-Path $Root '.wu-check'
$wuDue = -not (Test-Path $wuMarker) -or ((Get-Date) - (Get-Item $wuMarker).LastWriteTime).TotalHours -ge 4
if ($wuDue) {
    $wu = try { New-ChannelResult (Get-WindowsUpdates) $null } catch { New-ChannelResult @() $_.Exception.Message }
    if (-not $wu.error) { Set-Content -LiteralPath $wuMarker -Value (Get-Date -Format o) }
} elseif ($prev -and $prev.channels.windowsUpdate) {
    $wu = $prev.channels.windowsUpdate
} else {
    $wu = New-ChannelResult @() $null
}

# merge ignore/stale/interactive per channel (winget stale-from-cache items are already merged)
$scoop.items = @(Merge-IgnoreStaleInteractive $scoop.items $ignore $lastApply $overrides)
if (-not $wingetLocked) { $winget.items = @(Merge-IgnoreStaleInteractive $winget.items $ignore $lastApply $overrides) }
if ($wuDue) { $wu.items = @(Merge-IgnoreStaleInteractive $wu.items $ignore $lastApply $overrides) }

$status = [pscustomobject]@{
    generatedAt  = $nowIso
    wingetLocked = $wingetLocked
    channels     = [pscustomobject]@{ scoop = $scoop; winget = $winget; windowsUpdate = $wu }
}
Write-StatusAtomic $status $statusPath
Write-Host "status.json: scoop=$($scoop.items.Count) winget=$($winget.items.Count) wu=$($wu.items.Count) wingetLocked=$wingetLocked -> $statusPath"
