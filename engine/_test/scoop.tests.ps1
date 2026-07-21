Import-Module "$PSScriptRoot/../UpdateEngine.psm1" -Force
$lines = Get-Content "$PSScriptRoot/fixtures/scoop-status.txt"
$items = @(ConvertFrom-ScoopStatus $lines)

Assert-Equal $items.Count 3 'scoop: parses 3 outdated apps (skips WARN + separator)'

$fzf = $items | Where-Object id -eq 'fzf'
Assert-Equal $fzf.current '0.70.0' 'scoop: current version'
Assert-Equal $fzf.available '0.74.1' 'scoop: available version'
Assert-Equal $fzf.name 'fzf' 'scoop: name = id'
Assert-Equal $fzf.channel 'scoop' 'scoop: channel'
Assert-Equal $fzf.scope 'user' 'scoop: scope is user'
