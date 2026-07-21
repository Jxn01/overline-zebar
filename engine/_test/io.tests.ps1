Import-Module "$PSScriptRoot/../UpdateEngine.psm1" -Force

# --- Write-StatusAtomic ---
$tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("ovl-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmpDir | Out-Null
$statusPath = Join-Path $tmpDir 'status.json'
Write-StatusAtomic ([pscustomobject]@{ hello = 'world'; n = 3 }) $statusPath
Assert-True (Test-Path $statusPath) 'atomic: status.json written'
Assert-True (-not (Test-Path "$statusPath.tmp")) 'atomic: no leftover .tmp'
$read = Get-Content $statusPath -Raw | ConvertFrom-Json
Assert-Equal $read.hello 'world' 'atomic: JSON round-trips'

# --- Invoke-WithWingetLock acquires when free ---
$free = Invoke-WithWingetLock { 42 } 1000
Assert-True $free.Acquired 'lock: acquired when free'
Assert-Equal $free.Value 42 'lock: returns block result when free'

# --- Invoke-WithWingetLock returns null when the mutex is held by another thread ---
$rs = [runspacefactory]::CreateRunspace(); $rs.Open()
$ps = [powershell]::Create(); $ps.Runspace = $rs
[void]$ps.AddScript({
        param($mod)
        Import-Module $mod -Force
        $m = Get-WingetMutex
        [void]$m.WaitOne(2000)
        Start-Sleep -Milliseconds 2000
        $m.ReleaseMutex(); $m.Dispose()
    }).AddArgument("$PSScriptRoot/../UpdateEngine.psm1")
$h = $ps.BeginInvoke()
Start-Sleep -Milliseconds 600      # let the other thread grab it
$held = Invoke-WithWingetLock { 99 } 300
Assert-True (-not $held.Acquired) 'lock: not acquired when held by another thread'
[void]$ps.EndInvoke($h); $ps.Dispose(); $rs.Close()

# --- lock is free again after the block ---
Assert-Equal (Invoke-WithWingetLock { 7 } 1000).Value 7 'lock: released after use'

Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
