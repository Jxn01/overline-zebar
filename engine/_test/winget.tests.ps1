Import-Module "$PSScriptRoot/../UpdateEngine.psm1" -Force
$lines = Get-Content "$PSScriptRoot/fixtures/winget-table.txt"
$items = @(ConvertFrom-WingetTable $lines)

Assert-Equal $items.Count 3 'winget: parses exactly the 3 main-table rows (stops at footer)'

$m = $items | Where-Object id -eq 'Modrinth.ModrinthApp'
Assert-Equal $m.name 'Modrinth App' 'winget: parses name containing a space'
Assert-Equal $m.current '0.15.11' 'winget: parses current version'
Assert-Equal $m.available '0.15.14' 'winget: parses available version'
Assert-Equal $m.channel 'winget' 'winget: sets channel'

$maria = $items | Where-Object id -eq 'MariaDB.Server'
Assert-Equal $maria.name 'MariaDB 12.2 (x64)' 'winget: parses name with parentheses'

$msys = $items | Where-Object id -eq 'MSYS2.MSYS2'
Assert-True ($null -eq $msys) 'winget: excludes the explicit-targeting tail'
