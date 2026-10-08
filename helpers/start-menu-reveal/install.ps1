# Autostart start-menu-reveal at logon (a Startup-folder shortcut, like the other AHK helpers here)
# and (re)start it now. Re-running is safe. -Uninstall removes the shortcut and stops the helper.
param([switch]$Uninstall)
$ErrorActionPreference = 'Stop'

$script = Join-Path $PSScriptRoot 'start-menu-reveal.ahk'
$ahk = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe"
$lnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'start-menu-reveal.lnk'

# Stop a running copy (matched by its script path on the command line, never by a pattern of our own).
Get-CimInstance Win32_Process -Filter "Name='AutoHotkey64.exe'" |
    Where-Object { $_.CommandLine -like "*$script*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId }

if ($Uninstall) {
    Remove-Item $lnk -ErrorAction SilentlyContinue
    'start-menu-reveal: removed'
    return
}

if (-not (Test-Path $ahk)) { throw "AutoHotkey v2 not found at $ahk (winget install AutoHotkey.AutoHotkey)" }

$shell = New-Object -ComObject WScript.Shell
$s = $shell.CreateShortcut($lnk)
$s.TargetPath = $ahk
$s.Arguments = "`"$script`""
$s.WorkingDirectory = $PSScriptRoot
$s.Save()

Start-Process $ahk -ArgumentList "`"$script`""
"start-menu-reveal: autostart at $lnk, running"
