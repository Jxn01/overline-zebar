# Writes the shell privileges from zpack-privileges.psd1 into a zpack.json -- the repo's, and the
# installed pack's (which holds local preset values, so only each widget's "shellCommands" array is
# replaced, as text; nothing else in the file changes). Widgets not listed in the .psd1 must have
# no shell privileges and are left alone. Restart Zebar afterwards: it reads privileges at start.
#
#   pwsh -File engine/set-zpack-privileges.ps1                      # repo zpack.json
#   pwsh -File engine/set-zpack-privileges.ps1 -Installed           # %APPDATA% installed pack too
param([switch]$Installed)
$ErrorActionPreference = 'Stop'

$privileges = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'zpack-privileges.psd1')
$targets = @(Join-Path $PSScriptRoot '..\zpack.json')
if ($Installed) { $targets += "$env:APPDATA\zebar\downloads\mushfikurr.overline-zebar@1.0.3\zpack.json" }

function Format-ShellCommands($entries, $indent) {
    $pad = ' ' * $indent
    $items = foreach ($e in $entries) {
        $prog = $e.program | ConvertTo-Json
        $rx = $e.argsRegex | ConvertTo-Json
        "$pad  {`n$pad    `"program`": $prog,`n$pad    `"argsRegex`": $rx`n$pad  }"
    }
    "`"shellCommands`": [`n" + ($items -join ",`n") + "`n$pad]"
}

foreach ($file in $targets) {
    $text = [IO.File]::ReadAllText($file)
    $nl = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $text = $text -replace "`r`n", "`n"
    foreach ($widget in $privileges.Keys) {
        $at = $text.IndexOf("`"name`": `"$widget`"")
        if ($at -lt 0) { Write-Host "$(Split-Path $file -Leaf): no widget '$widget' -- skipped"; continue }
        $start = $text.IndexOf('"shellCommands": [', $at)
        if ($start -lt 0) { throw "$file : widget '$widget' has no shellCommands" }
        # argsRegex values contain ']', so the array's own close is the first ']' that starts a line
        # (or the ']' of an empty "[]").
        if ($text.Substring($start).StartsWith('"shellCommands": []')) {
            $end = $start + '"shellCommands": ['.Length
        } else {
            $m = [regex]::Match($text.Substring($start), '\n[ \t]*\]')
            $end = $start + $m.Index + $m.Length - 1
        }
        $lineStart = $text.LastIndexOf("`n", $start) + 1
        $indent = $start - $lineStart
        $text = $text.Substring(0, $start) + (Format-ShellCommands $privileges[$widget] $indent) + $text.Substring($end + 1)
    }
    $null = $text | ConvertFrom-Json   # still valid JSON, or throw before writing
    [IO.File]::WriteAllText($file, ($text -replace "`n", $nl), [Text.UTF8Encoding]::new($false))
    Write-Host "updated $file"
}
