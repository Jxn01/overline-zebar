# Guard: every widget shell privilege is anchored and admits exactly what the widget sends.
# Zebar 3.1.1 joins argv with spaces and uses an UNANCHORED Regex::is_match (shell_state.rs), so a
# pattern like ".*overline-updates.*" admitted ANY cmd command containing that word.

$repoZpack = Join-Path $PSScriptRoot '..\..\zpack.json'
$installedZpack = "$env:APPDATA\zebar\downloads\mushfikurr.overline-zebar@1.0.3\zpack.json"
$spec = Import-PowerShellDataFile (Join-Path $PSScriptRoot '..\zpack-privileges.psd1')

# Zebar's check, reproduced: any privilege for the program whose regex matches the joined argv.
function Test-Allowed($privs, $program, [string[]]$argv) {
    $joined = $argv -join ' '
    foreach ($p in @($privs | Where-Object { $_.program -eq $program })) {
        if ($p.argsRegex -and [regex]::IsMatch($joined, $p.argsRegex)) { return $true }
    }
    return $false
}

$zpacks = @(@{ name = 'repo'; path = $repoZpack })
if (Test-Path $installedZpack) { $zpacks += @{ name = 'installed'; path = $installedZpack } }

foreach ($z in $zpacks) {
    $widgets = (Get-Content -LiteralPath $z.path -Raw | ConvertFrom-Json).widgets
    foreach ($w in $widgets) {
        $cmds = @($w.privileges.shellCommands)
        foreach ($c in $cmds) {
            Assert-True ($c.argsRegex -match '^\^.*\$$') "$($z.name) zpack: $($w.name)/$($c.program) argsRegex is ^...`$ anchored"
        }
        $want = $spec[$w.name]
        if ($want) {
            Assert-Equal (@($cmds | ForEach-Object { "$($_.program) $($_.argsRegex)" })) `
                (@($want | ForEach-Object { "$($_.program) $($_.argsRegex)" })) "$($z.name) zpack: $($w.name) privileges = zpack-privileges.psd1"
        } else {
            Assert-Equal $cmds.Count 0 "$($z.name) zpack: $($w.name) has no shell privileges (not in zpack-privileges.psd1)"
        }
    }
}

$root = 'C:\Users\someone\AppData\Local\overline-updates'
function C($w, $p, [string[]]$argv) { [pscustomobject]@{ w = $w; p = $p; argv = $argv } }
$allowed = @(
    # [widget, program, argv] -- the real calls in widgets/*/src
    (C 'main' 'shutdown' @('/a')), (C 'main' 'shutdown' @('/s'))
    (C 'main' 'explorer' @('ms-settings:network-status'))
    (C 'main' 'cmd' @('/c', 'type', '%LOCALAPPDATA%\overline-updates\status.json'))
    (C 'update-panel' 'cmd' @('/c', 'echo %LOCALAPPDATA%'))
    (C 'update-panel' 'cmd' @('/c', 'type', "$root\status.json"))
    (C 'update-panel' 'cmd' @('/c', 'type', "$root\ignore.json"))
    (C 'update-panel' 'cmd' @('/c', 'type', "$root\run-k3j9x0ab.log"))
    (C 'update-panel' 'pwsh' @('-NoProfile', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-File', "$root\engine\check.ps1"))
    (C 'update-panel' 'pwsh' @('-NoProfile', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-File', "$root\engine\apply.ps1", '-Ids', 'Microsoft.VisualStudioCode', '-RunId', 'k3j9x0ab'))
    (C 'update-panel' 'pwsh' @('-NoProfile', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-File', "$root\engine\ignore.ps1", '-Action', 'skip', '-Channel', 'winget', '-Id', 'Foo.Bar', '-Version', '1.2.3'))
    (C 'power' 'shutdown' @('/r', '/t', '0')), (C 'power' 'shutdown' @('/s', '/t', '0'))
    (C 'power' 'rundll32' @('user32.dll,LockWorkStation'))
    (C 'power' 'pwsh' @('-NoProfile', '-NonInteractive', '-Command', "Add-Type -AssemblyName System.Windows.Forms; [void][System.Windows.Forms.Application]::SetSuspendState('Suspend', `$false, `$false)"))
)
$denied = @(
    (C 'main' 'cmd' @('/c', 'calc & rem overline-updates'))
    (C 'main' 'cmd' @('/c', 'type', '%LOCALAPPDATA%\overline-updates\status.json', '&', 'calc'))
    (C 'main' 'explorer' @('C:\Windows\System32\calc.exe'))
    (C 'main' 'shutdown' @('/s', '/m', '\\otherhost'))
    (C 'update-panel' 'cmd' @('/c', 'calc & echo overline-updates'))
    (C 'update-panel' 'cmd' @('/c', 'type', "$root\status.json & calc"))
    (C 'update-panel' 'cmd' @('/c', 'type', 'C:\Users\..\AppData\Local\overline-updates\status.json'))
    (C 'update-panel' 'pwsh' @('-NoProfile', '-Command', 'calc; # overline-updates'))
    (C 'update-panel' 'pwsh' @('-NoProfile', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-File', 'C:\evil\overline-updates\engine\apply.ps1'))
    (C 'power' 'rundll32' @('powrprof.dll,SetSuspendState', '0,1,0'))
    (C 'power' 'rundll32' @('user32.dll,LockWorkStation', 'x', 'shell32.dll,ShellExec_RunDLL', 'calc'))
    (C 'power' 'pwsh' @('-Command', "calc; SetSuspendState('Suspend'"))
    (C 'power' 'pwsh' @('-NoProfile', '-NonInteractive', '-Command', "Add-Type -AssemblyName System.Windows.Forms; [void][System.Windows.Forms.Application]::SetSuspendState('Suspend', `$false, `$false); calc"))
)

foreach ($a in $allowed) {
    Assert-True (Test-Allowed $spec[$a.w] $a.p $a.argv) "allowed: $($a.w) $($a.p) $($a.argv -join ' ')"
}
foreach ($d in $denied) {
    Assert-True (-not (Test-Allowed $spec[$d.w] $d.p $d.argv)) "denied: $($d.w) $($d.p) $($d.argv -join ' ')"
}

# Positive control: the OLD unanchored patterns admit the injections above, so the denied cases bite.
$old = @(@{ program = 'cmd'; argsRegex = '.*overline-updates.*' })
Assert-True (Test-Allowed $old 'cmd' @('/c', 'calc & rem overline-updates')) 'control: an unanchored pattern admits an injection'
