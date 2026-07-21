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

function ConvertFrom-WingetTable {
    # Parses the FIRST table of `winget upgrade` output into Item[].
    # winget uses fixed-width columns aligned to the header; we derive each column's
    # start offset from the header line and slice every data row by those offsets.
    # Stops at the footer ("N upgrades available") so the "require explicit targeting"
    # tail table is not included.
    param([string[]]$Lines)
    $items = @()
    if (-not $Lines) { return ,$items }

    $hi = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $l = $Lines[$i]
        if ($l -match '^Name\s' -and $l -match '\bId\b' -and $l -match '\bAvailable\b') { $hi = $i; break }
    }
    if ($hi -lt 0) { return ,$items }

    $header = $Lines[$hi]
    $cols = 'Name', 'Id', 'Version', 'Available', 'Source'
    $starts = @()
    $pos = 0
    foreach ($c in $cols) {
        $idx = $header.IndexOf($c, $pos)
        if ($idx -lt 0) { return ,$items }
        $starts += $idx
        $pos = $idx + $c.Length
    }

    for ($i = $hi + 1; $i -lt $Lines.Count; $i++) {
        $row = $Lines[$i]
        if ([string]::IsNullOrWhiteSpace($row)) { break }
        if ($row -match 'upgrades? available' -or $row -match 'require explicit targeting' -or $row -match 'package\(s\)') { break }
        if ($row -match '^\s*-{3,}\s*$') { continue }

        $vals = @()
        for ($c = 0; $c -lt $starts.Count; $c++) {
            $s = $starts[$c]
            if ($s -ge $row.Length) { $vals += ''; continue }
            $e = if ($c -lt $starts.Count - 1) { [Math]::Min($starts[$c + 1], $row.Length) } else { $row.Length }
            $vals += $row.Substring($s, $e - $s).Trim()
        }
        if ([string]::IsNullOrWhiteSpace($vals[1])) { continue }
        $items += New-UpdateItem -channel 'winget' -id $vals[1] -name $vals[0] -current $vals[2] -available $vals[3] -scope 'machine'
    }
    return $items
}

function Get-WingetUpdates {
    # Prefers the structured Microsoft.WinGet.Client module (authoritative per spec 6-D);
    # falls back to parsing the CLI table when the module is unavailable.
    param([switch]$ForceTable)
    if (-not $ForceTable -and (Get-Module -ListAvailable -Name Microsoft.WinGet.Client)) {
        try {
            Import-Module Microsoft.WinGet.Client -ErrorAction Stop
            $pkgs = Get-WinGetPackage -ErrorAction Stop | Where-Object { $_.IsUpdateAvailable }
            return @($pkgs | ForEach-Object {
                    $avail = @($_.AvailableVersions)[0]
                    New-UpdateItem -channel 'winget' -id $_.Id -name $_.Name -current $_.InstalledVersion -available $avail -scope 'machine'
                })
        } catch { }
    }
    $out = winget upgrade --include-unknown 2>$null
    return (ConvertFrom-WingetTable $out)
}

Export-ModuleMember -Function *
