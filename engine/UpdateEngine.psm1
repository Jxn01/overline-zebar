# UpdateEngine.psm1 — the "engine" behind the overline-zebar update-notifier island.
#
# One module, two callers: check.ps1 (scheduled, writes status.json) and apply.ps1
# (user-initiated upgrades, elevating machine-scope winget + Windows Update through
# apply-elevated.ps1). See docs/superpowers/specs/2026-07-22-update-island-design.md.
#
# An Item is a PSCustomObject with fields:
#   channel, id, name, current, available, scope, interactive, driver, driverClass,
#   rebootHint, suspectStale
#
# Functions are added task-by-task per the implementation plan.

function New-UpdateItem {
    param(
        [string]$channel, [string]$id, [string]$name,
        [string]$current, [string]$available,
        [string]$scope = 'machine',
        [string]$interactive = 'unknown',
        [bool]$driver = $false,
        [string]$driverClass = $null,
        [bool]$rebootHint = $false,
        [bool]$suspectStale = $false
    )
    [pscustomobject]@{
        channel = $channel; id = $id; name = $name
        current = $current; available = $available
        scope = $scope; interactive = $interactive
        driver = $driver; driverClass = $driverClass
        rebootHint = $rebootHint; suspectStale = $suspectStale
    }
}

Export-ModuleMember -Function *
