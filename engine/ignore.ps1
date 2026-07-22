# ignore.ps1 — manage ignore.json: skip a version, ignore a package, or un-hide.
# For winget, ignorePkg/unhide also writes/removes a real winget pin.
param(
    [Parameter(Mandatory)][ValidateSet('skip', 'ignorePkg', 'unhide')][string]$Action,
    [Parameter(Mandatory)][string]$Channel,
    [Parameter(Mandatory)][string]$Id,
    [string]$Version,
    [string]$Root = (Join-Path $env:LOCALAPPDATA 'overline-updates')
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'UpdateEngine.psm1') -Force

$path = Join-Path $Root 'ignore.json'
$store = Read-IgnoreStore $path
$skip = [System.Collections.Generic.List[object]]::new(); foreach ($e in @($store.skipVersion)) { if ($e) { $skip.Add($e) } }
$pkg = [System.Collections.Generic.List[object]]::new(); foreach ($e in @($store.ignorePackage)) { if ($e) { $pkg.Add($e) } }

switch ($Action) {
    'skip' {
        $skip.Add([pscustomobject]@{ channel = $Channel; id = $Id; version = $Version })
    }
    'ignorePkg' {
        $pkg.Add([pscustomobject]@{ channel = $Channel; id = $Id })
        if ($Channel -eq 'winget') { try { winget pin add --id $Id --exact --blocking --accept-source-agreements *> $null } catch { } }
    }
    'unhide' {
        $skip = [System.Collections.Generic.List[object]]@($skip | Where-Object { -not ($_.channel -eq $Channel -and $_.id -eq $Id) })
        $pkg = [System.Collections.Generic.List[object]]@($pkg | Where-Object { -not ($_.channel -eq $Channel -and $_.id -eq $Id) })
        if ($Channel -eq 'winget') { try { winget pin remove --id $Id --exact *> $null } catch { } }
    }
}

$out = [pscustomobject]@{ skipVersion = @($skip); ignorePackage = @($pkg) }
$tmp = "$path.tmp"
($out | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $tmp -Encoding utf8
Move-Item -LiteralPath $tmp -Destination $path -Force
Write-Host "ignore.json updated: $Action $Channel $Id"
