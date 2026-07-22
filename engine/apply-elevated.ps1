# apply-elevated.ps1 — the elevated helper. Launched by apply.ps1 via Start-Process -Verb RunAs
# with a DATA-ONLY job file (never caller-supplied code). Applies machine-scope winget +
# Windows Update, does the Public-desktop sweep, appends STATUS lines to the shared run-log,
# and ALWAYS writes a DONE sentinel (in finally) so the widget can tell done from crashed.
param(
    [Parameter(Mandatory)][string]$Job,
    [string]$Root = (Join-Path $env:LOCALAPPDATA 'overline-updates'),
    [Parameter(Mandatory)][string]$RunLog
)
$ErrorActionPreference = 'Continue'
Import-Module (Join-Path $PSScriptRoot 'UpdateEngine.psm1') -Force
$lastApplyPath = Join-Path $Root 'last-apply.json'
function Log($m) { Add-Content -LiteralPath $RunLog -Value $m }

$overallExit = 0
try {
    $jobData = Get-Content -LiteralPath $Job -Raw | ConvertFrom-Json
    $items = @($jobData.items)
    $includeDrivers = [bool]$jobData.includeDrivers

    $publicDesktop = @(Get-PublicDesktopPath)
    $snap = Get-DesktopShortcutSnapshot $publicDesktop

    foreach ($it in $items) {
        if ($it.channel -eq 'windowsUpdate' -and $it.driver -and -not $includeDrivers) { continue }
        Log "STATUS $($it.id) updating"
        $code = -1
        try {
            if ($it.channel -eq 'winget') {
                $lr = Invoke-WithWingetLock { Invoke-WingetApply -Id $it.id -Interactive:($it.interactive -eq 'yes') } 600000
                $code = if ($lr.Acquired) { [int]$lr.Value } else { -2 }
            } elseif ($it.channel -eq 'windowsUpdate') {
                $code = Invoke-WUApply -UpdateId $it.id
            }
        } catch { $code = -1; Log "  error: $($_.Exception.Message)" }
        $ver = if ($it.available) { [string]$it.available } else { '' }
        Write-LastApply $lastApplyPath $it.id $ver ([int]$code)
        if ($code -eq 0) { Log "STATUS $($it.id) done" } else { Log "STATUS $($it.id) failed exit=$code"; $overallExit = 1 }
    }

    $removed = @(Complete-DesktopSweep $snap $publicDesktop)
    if ($removed.Count) { Log "SWEPT $($removed.Count) public desktop shortcut(s)" }
} catch {
    Log "FATAL $($_.Exception.Message)"
    $overallExit = 1
} finally {
    Log "DONE $overallExit"
}
