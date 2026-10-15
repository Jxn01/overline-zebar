# Guard: the scheduled checker is registered for the CURRENT user's real account name.
# "$env:USERDOMAIN\$env:USERNAME" reads WORKGROUP\<user> in an SSH (network) logon on a workgroup PC, and
# Register-ScheduledTask then fails with "No mapping between account names and security IDs was done"
# (found 2026-10-15 deploying the engine to the laptop over SSH). WindowsIdentity gives MACHINE\user everywhere.

$installTask = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\install-task.ps1') -Raw
$code = ($installTask -split "`n" | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
Assert-True ($code -notmatch 'USERDOMAIN') 'install-task.ps1 does not build the principal from %USERDOMAIN%'
Assert-True ($code -match '\[Security\.Principal\.WindowsIdentity\]::GetCurrent\(\)\.Name') 'install-task.ps1 takes the principal from WindowsIdentity'
# positive control: the old line is what the first check rejects
Assert-True ('-UserId "$($env:USERDOMAIN)\$($env:USERNAME)"' -match 'USERDOMAIN') 'positive control: the old principal line is caught'
