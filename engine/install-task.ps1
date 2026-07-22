# install-task.ps1 — register the per-user update-checker scheduled task.
# Runs the DEPLOYED check.ps1 (run deploy.ps1 first). Limited run level (checks need no admin).
param(
    [string]$Root = (Join-Path $env:LOCALAPPDATA 'overline-updates'),
    [string]$TaskName = 'overline-update-check'
)
$ErrorActionPreference = 'Stop'
$checkPath = Join-Path $Root 'engine\check.ps1'
if (-not (Test-Path $checkPath)) { throw "check.ps1 not deployed at $checkPath - run deploy.ps1 first" }
$pwsh = (Get-Command pwsh).Source

$action = New-ScheduledTaskAction -Execute $pwsh -Argument "-NoProfile -WindowStyle Hidden -File `"$checkPath`""
$tLogon = New-ScheduledTaskTrigger -AtLogOn
$tRepeat = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 45)
$principal = New-ScheduledTaskPrincipal -UserId "$($env:USERDOMAIN)\$($env:USERNAME)" -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger @($tLogon, $tRepeat) -Principal $principal -Settings $settings -Force | Out-Null
Write-Host "registered '$TaskName' (at logon + every 45 min) -> $checkPath"
