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

function Get-WingetMutex {
    # A single named mutex serializes ALL winget access across the unelevated checker/
    # widget and the elevated applier. A default-security Global\ mutex throws when opened
    # from a different integrity level, so we create it with an Everyone-FullControl ACL
    # (fable review). OpenExisting first so we never clobber an existing owner's object.
    $name = 'Global\OverlineWingetLock'
    try { return [System.Threading.Mutex]::OpenExisting($name) } catch { }
    try {
        Add-Type -AssemblyName System.Threading.AccessControl -ErrorAction Stop
        $everyone = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::WorldSid, $null)
        $rule = New-Object System.Security.AccessControl.MutexAccessRule($everyone, [System.Security.AccessControl.MutexRights]::FullControl, [System.Security.AccessControl.AccessControlType]::Allow)
        $sec = New-Object System.Security.AccessControl.MutexSecurity
        $sec.AddAccessRule($rule)
        $createdNew = $false
        return [System.Threading.MutexAcl]::Create($false, $name, [ref]$createdNew, $sec)
    } catch {
        $createdNew = $false
        return [System.Threading.Mutex]::new($false, $name, [ref]$createdNew)
    }
}

function Invoke-WithWingetLock {
    # Runs $Block while holding the winget mutex. Returns the block's result, or $null if
    # the lock could not be acquired within $TimeoutMs (caller keeps last-good cache).
    # Returns { Acquired = $bool; Value = <block result> }. The explicit wrapper is required:
    # a block returning an empty array would otherwise unroll to $null and be indistinguishable
    # from "lock not acquired".
    param([scriptblock]$Block, [int]$TimeoutMs = 0)
    $mutex = Get-WingetMutex
    $acquired = $false
    try {
        try { $acquired = $mutex.WaitOne($TimeoutMs) }
        catch [System.Threading.AbandonedMutexException] { $acquired = $true }
        if (-not $acquired) { return [pscustomobject]@{ Acquired = $false; Value = $null } }
        return [pscustomobject]@{ Acquired = $true; Value = (& $Block) }
    } finally {
        if ($acquired) { try { $mutex.ReleaseMutex() } catch { } }
        $mutex.Dispose()
    }
}

function Write-StatusAtomic {
    # Serialize $Object to JSON and move it into place atomically (temp + rename) so a
    # reader never sees a half-written file.
    param($Object, [string]$Path)
    $tmp = "$Path.tmp"
    ($Object | ConvertTo-Json -Depth 12) | Set-Content -LiteralPath $tmp -Encoding utf8
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return (Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop) } catch { return $null }
}

function Read-IgnoreStore {
    param([string]$Path)
    $j = Read-JsonFile $Path
    if (-not $j) { return [pscustomobject]@{ skipVersion = @(); ignorePackage = @() } }
    if ($null -eq $j.skipVersion) { $j | Add-Member -NotePropertyName skipVersion -NotePropertyValue @() -Force }
    if ($null -eq $j.ignorePackage) { $j | Add-Member -NotePropertyName ignorePackage -NotePropertyValue @() -Force }
    return $j
}

function Read-LastApply { param([string]$Path) $j = Read-JsonFile $Path; if (-not $j) { return [pscustomobject]@{} } return $j }

function Read-InteractiveOverrides { param([string]$Path) $j = Read-JsonFile $Path; if (-not $j) { return [pscustomobject]@{} } return $j }

function Merge-IgnoreStaleInteractive {
    # Drops ignored/skipped items, flags post-apply false-positives, and populates
    # `interactive` from the overrides map (spec 10, 13; fable fix #2).
    param($Items, $Ignore, $LastApply, $Overrides)
    $result = @()

    $ignorePkg = @{}
    if ($Ignore.ignorePackage) { foreach ($e in $Ignore.ignorePackage) { $ignorePkg["$($e.channel)|$($e.id)"] = $true } }
    $skipVer = @{}
    if ($Ignore.skipVersion) { foreach ($e in $Ignore.skipVersion) { $skipVer["$($e.channel)|$($e.id)|$($e.version)"] = $true } }

    foreach ($it in $Items) {
        if ($ignorePkg.ContainsKey("$($it.channel)|$($it.id)")) { continue }
        if ($skipVer.ContainsKey("$($it.channel)|$($it.id)|$($it.available)")) { continue }

        if ($Overrides -and $it.id) {
            $ovProp = $Overrides.PSObject.Properties[$it.id]
            if ($ovProp -and $ovProp.Value) { $it.interactive = [string]$ovProp.Value }
        }

        if ($LastApply -and $it.id) {
            $laProp = $LastApply.PSObject.Properties[$it.id]
            if ($laProp -and $laProp.Value) {
                $la = $laProp.Value
                if (([int]$la.exitCode -eq 0) -and ($la.appliedVersion -eq $it.available)) { $it.suspectStale = $true }
            }
        }

        $result += $it
    }
    return $result
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

# ---------------------------------------------------------------------------------------
# Apply: upgrades + desktop-icon sweep + last-apply outcome store
# ---------------------------------------------------------------------------------------

function Get-UserDesktopPaths { , @([Environment]::GetFolderPath('Desktop')) }
function Get-PublicDesktopPath { Join-Path $env:PUBLIC 'Desktop' }

function Get-DesktopShortcutSnapshot {
    # Hashtable of every .lnk present on the given desktop paths (the "before" set).
    param([string[]]$Paths)
    $set = @{}
    foreach ($p in $Paths) {
        if (Test-Path $p) {
            Get-ChildItem $p -Filter '*.lnk' -File -ErrorAction SilentlyContinue | ForEach-Object { $set[$_.FullName] = $true }
        }
    }
    return $set
}

function Complete-DesktopSweep {
    # Delete any .lnk that appeared since the snapshot (an installer's new desktop icon).
    param($Snapshot, [string[]]$Paths)
    $removed = @()
    foreach ($p in $Paths) {
        if (-not (Test-Path $p)) { continue }
        Get-ChildItem $p -Filter '*.lnk' -File -ErrorAction SilentlyContinue | ForEach-Object {
            if (-not $Snapshot.ContainsKey($_.FullName)) {
                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
                $removed += $_.FullName
            }
        }
    }
    return $removed
}

function Write-LastApply {
    # Record an apply outcome so check.ps1 can compute suspectStale (spec 10). Atomic.
    param([string]$Path, [string]$Id, [string]$Version, [int]$ExitCode)
    $obj = Read-LastApply $Path
    if (-not $obj) { $obj = [pscustomobject]@{} }
    $entry = [pscustomobject]@{ appliedVersion = $Version; at = (Get-Date -Format o); exitCode = $ExitCode }
    $obj | Add-Member -NotePropertyName $Id -NotePropertyValue $entry -Force
    $tmp = "$Path.tmp"
    ($obj | ConvertTo-Json -Depth 12) | Set-Content -LiteralPath $tmp -Encoding utf8
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Invoke-ScoopApply {
    param([string]$Id)
    scoop update $Id *>&1 | Out-Null
    return $LASTEXITCODE
}

function Invoke-WingetApply {
    param([string]$Id, [switch]$Interactive)
    $a = @('upgrade', '--id', $Id, '--exact', '--accept-package-agreements', '--accept-source-agreements')
    if ($Interactive) { $a += '--interactive' } else { $a += @('--silent', '--disable-interactivity') }
    winget @a *>&1 | Out-Null
    return $LASTEXITCODE
}

function Invoke-WUApply {
    # Download + install one Windows Update by UpdateID via WUA COM. Requires elevation.
    # Returns 0 on success (ResultCode 2 = orcSucceeded), non-zero otherwise.
    param([string]$UpdateId)
    $session = New-Object -ComObject Microsoft.Update.Session
    $searcher = $session.CreateUpdateSearcher()
    $result = $searcher.Search("IsInstalled=0 and IsHidden=0")
    $coll = New-Object -ComObject Microsoft.Update.UpdateColl
    foreach ($u in $result.Updates) {
        if ([string]$u.Identity.UpdateID -eq $UpdateId) {
            try { if (-not $u.EulaAccepted) { $u.AcceptEula() } } catch { }
            [void]$coll.Add($u)
        }
    }
    if ($coll.Count -eq 0) { return 1 }
    $downloader = $session.CreateUpdateDownloader(); $downloader.Updates = $coll
    [void]$downloader.Download()
    $installer = $session.CreateUpdateInstaller(); $installer.Updates = $coll
    $ir = $installer.Install()
    if ([int]$ir.ResultCode -eq 2) { return 0 } else { return [int]$ir.ResultCode }
}

function Get-RunLogState {
    # Interpret an elevated run-log: 'complete' if it ends with a DONE record, else 'crashed'
    # (the process died mid-run without writing its sentinel). Mirrors the .rc/DONE pattern.
    param([string[]]$Lines)
    $done = $Lines | Where-Object { $_ -match '^DONE\s' } | Select-Object -Last 1
    if ($done) { return 'complete' }
    return 'crashed'
}

Export-ModuleMember -Function *
