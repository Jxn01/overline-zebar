Import-Module "$PSScriptRoot/../UpdateEngine.psm1" -Force

$items = @(
    New-UpdateItem -channel 'winget' -id 'A.Keep'        -name 'Keep'  -current '1.0'  -available '2.0'
    New-UpdateItem -channel 'winget' -id 'B.Ignored'     -name 'Ign'   -current '1.0'  -available '2.0'
    New-UpdateItem -channel 'scoop'  -id 'c-skip'         -name 'skip'  -current '1.0'  -available '2.0'
    New-UpdateItem -channel 'scoop'  -id 'f-newer'        -name 'newer' -current '1.0'  -available '3.0'
    New-UpdateItem -channel 'winget' -id 'D.Stale'        -name 'Stale' -current '5.38' -available '5.48'
    New-UpdateItem -channel 'winget' -id 'E.Interactive'  -name 'Inter' -current '1.0'  -available '2.0'
)

$ignore = [pscustomobject]@{
    ignorePackage = @([pscustomobject]@{ channel = 'winget'; id = 'B.Ignored' })
    skipVersion   = @(
        [pscustomobject]@{ channel = 'scoop'; id = 'c-skip';  version = '2.0' }   # matches available -> drop
        [pscustomobject]@{ channel = 'scoop'; id = 'f-newer'; version = '2.0' }   # old version -> keep
    )
}
$lastApply = [pscustomobject]@{ 'D.Stale' = [pscustomobject]@{ appliedVersion = '5.48'; at = 'x'; exitCode = 0 } }
$overrides = [pscustomobject]@{ 'E.Interactive' = 'yes' }

$merged = @(Merge-IgnoreStaleInteractive $items $ignore $lastApply $overrides)

Assert-True ($null -eq ($merged | Where-Object id -eq 'B.Ignored')) 'merge: ignorePackage removed'
Assert-True ($null -eq ($merged | Where-Object id -eq 'c-skip'))    'merge: skipVersion matching available removed'
Assert-True ($null -ne ($merged | Where-Object id -eq 'f-newer'))   'merge: skipVersion for older version kept'
Assert-True ($null -ne ($merged | Where-Object id -eq 'A.Keep'))    'merge: unignored kept'
Assert-Equal (($merged | Where-Object id -eq 'D.Stale').suspectStale) $true  'merge: post-apply mismatch -> suspectStale'
Assert-Equal (($merged | Where-Object id -eq 'A.Keep').suspectStale) $false 'merge: no last-apply -> not stale'
Assert-Equal (($merged | Where-Object id -eq 'E.Interactive').interactive) 'yes' 'merge: overrides set interactive'
