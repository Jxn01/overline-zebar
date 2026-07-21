# Runs every *.tests.ps1 in this folder against the update engine.
# Exit 0 = all green, 1 = one or more failures.
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/Assert.ps1"

Get-ChildItem "$PSScriptRoot" -Filter '*.tests.ps1' | Sort-Object Name | ForEach-Object {
    Write-Host "`n== $($_.Name) ==" -ForegroundColor Cyan
    . $_.FullName
}

if ($script:Failures -gt 0) {
    Write-Host "`n$script:Failures failure(s)" -ForegroundColor Red
    exit 1
} else {
    Write-Host "`nall green" -ForegroundColor Green
    exit 0
}
