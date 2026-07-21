# Minimal dependency-free assertion harness for the update engine tests.
# Usage: dot-source Assert.ps1, then Assert-Equal / Assert-True / Assert-Throws.
# $script:Failures accumulates; run-tests.ps1 reads it to set the exit code.

$script:Failures = 0

function Assert-Equal($actual, $expected, $name) {
    $a = ($actual | ConvertTo-Json -Compress -Depth 12)
    $e = ($expected | ConvertTo-Json -Compress -Depth 12)
    if ($a -ne $e) {
        $script:Failures++
        Write-Host "FAIL: $name" -ForegroundColor Red
        Write-Host "  expected: $e" -ForegroundColor DarkGray
        Write-Host "  actual:   $a" -ForegroundColor DarkGray
    } else {
        Write-Host "ok: $name" -ForegroundColor Green
    }
}

function Assert-True($cond, $name) {
    if (-not $cond) {
        $script:Failures++
        Write-Host "FAIL: $name (expected true)" -ForegroundColor Red
    } else {
        Write-Host "ok: $name" -ForegroundColor Green
    }
}

function Assert-Throws([scriptblock]$block, $name) {
    try {
        & $block
        $script:Failures++
        Write-Host "FAIL: $name (expected an exception, none thrown)" -ForegroundColor Red
    } catch {
        Write-Host "ok: $name" -ForegroundColor Green
    }
}
