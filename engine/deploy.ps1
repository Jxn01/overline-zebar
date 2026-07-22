# deploy.ps1 — copy the engine into %LOCALAPPDATA%\overline-updates\engine and (when present)
# harden the elevated helper so a non-admin process cannot swap it out.
# Run elevated only when re-deploying apply-elevated.ps1 (its ACL blocks unelevated overwrite).
param([string]$Root = (Join-Path $env:LOCALAPPDATA 'overline-updates'))
$ErrorActionPreference = 'Stop'

$engineDst = Join-Path $Root 'engine'
New-Item -ItemType Directory -Path $engineDst -Force | Out-Null

# copy engine files (module, scripts, overrides); skip the _test folder
Get-ChildItem $PSScriptRoot -File | Copy-Item -Destination $engineDst -Force

# harden the elevated helper if it exists: only Administrators/SYSTEM may write; user gets RX.
$elev = Join-Path $engineDst 'apply-elevated.ps1'
if (Test-Path $elev) {
    & icacls $elev /inheritance:r /grant:r 'Administrators:(F)' 'SYSTEM:(RX)' "$($env:USERNAME):(RX)" | Out-Null
    Write-Host "hardened $elev"
}
Write-Host "deployed engine -> $engineDst"
