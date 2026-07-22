Import-Module "$PSScriptRoot/../UpdateEngine.psm1" -Force

$d = Join-Path ([System.IO.Path]::GetTempPath()) ("ovl-desk-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $d | Out-Null

# --- desktop sweep: new .lnk removed, pre-existing kept ---
Set-Content -LiteralPath (Join-Path $d 'existing.lnk') -Value 'x'
$snap = Get-DesktopShortcutSnapshot @($d)
Set-Content -LiteralPath (Join-Path $d 'NEW-installer.lnk') -Value 'y'
$removed = @(Complete-DesktopSweep $snap @($d))
Assert-True (Test-Path (Join-Path $d 'existing.lnk')) 'sweep: pre-existing .lnk kept'
Assert-True (-not (Test-Path (Join-Path $d 'NEW-installer.lnk'))) 'sweep: newly-created .lnk removed'
Assert-Equal $removed.Count 1 'sweep: removed exactly the new one'

# --- last-apply round-trips ---
$la = Join-Path $d 'last-apply.json'
Write-LastApply $la 'Foo.Bar' '2.0' 0
$read = Read-LastApply $la
Assert-Equal $read.'Foo.Bar'.appliedVersion '2.0' 'last-apply: version stored'
Assert-Equal $read.'Foo.Bar'.exitCode 0 'last-apply: exit code stored'

# --- run-log completion sentinel ---
Assert-Equal (Get-RunLogState @('STATUS x updating', 'STATUS x done', 'DONE 0')) 'complete' 'runlog: DONE record -> complete'
Assert-Equal (Get-RunLogState @('STATUS x updating')) 'crashed' 'runlog: no DONE record -> crashed'

# --- apply.ps1 -WhatIf touches nothing and writes no last-apply (fresh Root) ---
$d2 = Join-Path ([System.IO.Path]::GetTempPath()) ("ovl-wi-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $d2 | Out-Null
$job = Join-Path $d2 'job.json'
@{ items = @(@{ channel = 'scoop'; id = 'fzf'; scope = 'user'; interactive = 'no' }); includeDrivers = $false } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $job
$runlog = Join-Path $d2 'run.log'
& "$PSScriptRoot/../apply.ps1" -Job $job -Root $d2 -RunLog $runlog -WhatIf | Out-Null
$rl = Get-Content $runlog
Assert-True (($rl | Where-Object { $_ -match 'WOULDUPDATE .*fzf' }).Count -eq 1) 'whatif: reports the item as would-update'
Assert-True (-not (Test-Path (Join-Path $d2 'last-apply.json'))) 'whatif: writes no last-apply'

Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $d2 -Recurse -Force -ErrorAction SilentlyContinue
