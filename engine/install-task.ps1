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

# Launch through `conhost --headless`, NOT `pwsh -WindowStyle Hidden`.
#
# -WindowStyle Hidden DOES NOT WORK on this machine. SW_HIDE is a request to the
# launched process, but the default terminal is {00000000-...} ("Let Windows decide"),
# which on Win11 delegates the console to Windows Terminal -- and WT creates the window
# itself and ignores SW_HIDE. The result was a console flashing on screen every 45
# minutes, stealing focus out of fullscreen games.
#
# Measured 2026-09-08 by registering each form and enumerating new top-level windows:
#   pwsh -WindowStyle Hidden ....... 1 new window (WindowsTerminal 1199x616) + OpenConsole
#   conhost --headless pwsh ........ 0 new windows, payload + git/scoop/winget children OK
#
# conhost --headless allocates a real-but-windowless console, so console grandchildren
# (git under `scoop update`, winget) inherit it instead of allocating their own window.
# Fallback if a future Windows build drops --headless: a GUI-subsystem launcher that
# spawns with CREATE_NO_WINDOW (0x08000000), e.g. pythonw.exe -c "subprocess.run(...)",
# which was measured equally clean. Do NOT "fix" this by changing DelegationConsole --
# that would change the user's default terminal everywhere.
#
# Same failure mode as matterlights' install-autostart.ps1; see that project's notes.
$conhost = "$env:SystemRoot\System32\conhost.exe"

$action = New-ScheduledTaskAction -Execute $conhost -Argument "--headless `"$pwsh`" -NoProfile -File `"$checkPath`""
$tLogon = New-ScheduledTaskTrigger -AtLogOn
$tRepeat = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 45)
$principal = New-ScheduledTaskPrincipal -UserId "$($env:USERDOMAIN)\$($env:USERNAME)" -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger @($tLogon, $tRepeat) -Principal $principal -Settings $settings -Force | Out-Null
Write-Host "registered '$TaskName' (at logon + every 45 min) -> $checkPath"
