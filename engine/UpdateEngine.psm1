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

function Get-DriverClass {
    # Classify a Windows Update driver by its title. Only 'display' drivers carry the
    # "may replace your vendor driver" caveat in the UI (spec 15). switch -Regex is
    # case-insensitive; first matching branch returns.
    param([string]$Title)
    switch -Regex ($Title) {
        'display|graphics|video|\bGPU\b|radeon|geforce|nvidia' { return 'display' }
        'mouse|keyboard|\bHID\b|touchpad|\binput\b|\bpen\b' { return 'input' }
        'audio|\bAPO\b|AudioProcessingObject|\bsound\b|realtek' { return 'audio' }
        default { return 'other' }
    }
}

function Get-WindowsUpdates {
    # WUA COM search for applicable, not-installed, not-hidden updates.
    # Software + drivers both returned; driver items get driverClass + rebootHint.
    # Throws on failure — check.ps1 records the per-channel error.
    $items = @()
    $session = New-Object -ComObject Microsoft.Update.Session
    $searcher = $session.CreateUpdateSearcher()
    $result = $searcher.Search("IsInstalled=0 and IsHidden=0")
    foreach ($u in $result.Updates) {
        $isDriver = $false
        try { if ([int]$u.Type -eq 2) { $isDriver = $true } } catch {}   # 2 = uoDriver
        if (-not $isDriver) {
            try { foreach ($cat in $u.Categories) { if ($cat.Name -match 'Driver') { $isDriver = $true; break } } } catch {}
        }
        $dc = if ($isDriver) { Get-DriverClass $u.Title } else { $null }
        $items += New-UpdateItem -channel 'windowsUpdate' -id ([string]$u.Identity.UpdateID) -name $u.Title `
            -current '' -available '' -scope 'machine' -driver $isDriver -driverClass $dc -rebootHint $true
    }
    return $items
}

function Get-ColumnSlice {
    # Slice a fixed-width row [start, end), clamped to the row length, trimmed.
    param([string]$Row, [int]$Start, [int]$End)
    if ($Start -ge $Row.Length) { return '' }
    $End = [Math]::Min($End, $Row.Length)
    if ($End -le $Start) { return '' }
    return $Row.Substring($Start, $End - $Start).Trim()
}

function ConvertFrom-ScoopStatus {
    # Parses `scoop status` (Name / Installed Version / Latest Version / …) into Item[].
    param([string[]]$Lines)
    $items = @()
    if (-not $Lines) { return $items }

    $hi = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $l = $Lines[$i]
        if ($l -match '^Name\s' -and $l -match 'Installed Version' -and $l -match 'Latest Version') { $hi = $i; break }
    }
    if ($hi -lt 0) { return $items }

    $header = $Lines[$hi]
    $cols = 'Name', 'Installed Version', 'Latest Version', 'Missing Dependencies', 'Info'
    $starts = @()
    $pos = 0
    foreach ($c in $cols) {
        $idx = $header.IndexOf($c, $pos)
        if ($idx -lt 0) { $starts += -1 } else { $starts += $idx; $pos = $idx + $c.Length }
    }
    if ($starts[0] -lt 0 -or $starts[1] -lt 0 -or $starts[2] -lt 0) { return $items }
    $latestEnd = if ($starts[3] -ge 0) { $starts[3] } else { [int]::MaxValue }

    for ($i = $hi + 1; $i -lt $Lines.Count; $i++) {
        $row = $Lines[$i]
        if ([string]::IsNullOrWhiteSpace($row)) { continue }
        if ($row -match '^\s*-{3,}') { continue }
        if ($row -match '^(WARN|Everything is ok|Updating|Scoop)') { continue }

        $name = Get-ColumnSlice $row $starts[0] $starts[1]
        $inst = Get-ColumnSlice $row $starts[1] $starts[2]
        $latest = Get-ColumnSlice $row $starts[2] $latestEnd
        if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($latest)) { continue }
        $items += New-UpdateItem -channel 'scoop' -id $name -name $name -current $inst -available $latest -scope 'user'
    }
    return $items
}

function Get-ScoopUpdates {
    # Assumes buckets were refreshed recently (the scheduled checker runs `scoop update`
    # periodically). Captures all streams so the WARN header is included and skipped.
    $out = (scoop status *>&1 | Out-String)
    return (ConvertFrom-ScoopStatus ($out -split "`r?`n"))
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
