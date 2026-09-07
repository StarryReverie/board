<#
=============================================================================
 run_tb.ps1 - experiment-1 module test batch runner (local Vivado 2019.2 xsim)
   * auto-discover: RTL in src/rtl/*.v and TB in src/test/tb_*.v
     (module name = file basename)
   * flow: xvlog compile all sources -> per-TB xelab+xsim (watchdog timeout)
   * TB output contract: per assertion $display("PASS: ...") / ("FAIL: ..."),
     ending with $display("=== ALL PASS ===") or $display("=== FAIL ===")
   * each TB is run under a watchdog: if it does not finish within
     -TimeoutSec seconds it is killed and reported as TIMEOUT (FAIL), then
     the runner continues with the next TB (no infinite block). Wall time of
     every case is printed live so progress is visible.
   * usage:
       .\scripts\run_tb.ps1 -List
       .\scripts\run_tb.ps1
       .\scripts\run_tb.ps1 -Case alu
       .\scripts\run_tb.ps1 -TimeoutSec 60
   * env: default C:\Xilinx\Vivado\2019.2 ; override with $env:XVIVADO_ROOT
=============================================================================
#>
param(
    [string]$Case = '',          # filter keyword (substring of tb name, comma separated)
    [switch]$List,               # only list test benches
    [int]$TimeoutSec = 30,       # per-TB watchdog timeout (kill+continue when exceeded)
    [int]$CompileTimeoutSec = 600 # watchdog timeout for the xvlog compile step
)

$ErrorActionPreference = 'Stop'
$root    = Split-Path -Parent $PSScriptRoot          # repo root (src)
$vivado  = if ($env:XVIVADO_ROOT) { $env:XVIVADO_ROOT } else { 'C:\Xilinx\Vivado\2019.2' }
$settings = Join-Path $vivado 'settings64.bat'
if (-not (Test-Path $settings)) { Write-Error "cannot find $settings (set `$env:XVIVADO_ROOT)"; exit 1 }

# ---- collect sources & TBs -------------------------------------------------
$rtlFiles = @(Get-ChildItem -Path (Join-Path $root 'rtl') -Filter '*.v' -File | Select-Object -ExpandProperty FullName)
$tbFiles  = @(Get-ChildItem -Path (Join-Path $root 'test') -Filter 'tb_*.v' -File | Select-Object -ExpandProperty FullName)

if ($rtlFiles.Count -eq 0) { Write-Host '[hint] no RTL (*.v) in rtl/' }
if ($tbFiles.Count  -eq 0) { Write-Host '[hint] no tb_*.v in test/' }

$tbNames = @($tbFiles | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_) })
if ($Case) {
    $keys = $Case -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    $tbNames = @($tbNames | Where-Object {
        $n = $_
        $hit = $false
        foreach ($k in $keys) { if ($n -like "*$k*") { $hit = $true; break } }
        $hit
    })
}

if ($List) {
    Write-Host '== available tests =='
    $tbNames | ForEach-Object { Write-Host "  $_" }
    exit 0
}
if ($tbNames.Count -eq 0) { Write-Host '[hint] no matching test, exit'; exit 0 }

# ---- output dir (rebuilt every run) -----------------------------------------
$outDir = Join-Path $PSScriptRoot 'out'
if (Test-Path $outDir) { Remove-Item $outDir -Recurse -Force }
New-Item -ItemType Directory -Path $outDir | Out-Null

# program regression TBs read *.hex by name via $readmemh (sim cwd = outDir)
Get-ChildItem -Path (Join-Path $root 'test') -Filter '*.hex' -File |
    Copy-Item -Destination $outDir -Force

# ---- helpers ----------------------------------------------------------------
# Run a .bat under cmd.exe via a real .NET Process (async output drain) so a
# watchdog timeout can kill the whole tree; returns @{code; timedOut}.
function Run-CmdBat {
    param([string]$BatPath, [string]$StdOut, [int]$TimeoutSec)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'cmd.exe'
    $psi.Arguments = '/c "' + $BatPath + '"'
    $psi.UseShellExecute = $false
    $psi.WorkingDirectory = $outDir
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    $outSb = New-Object System.Text.StringBuilder
    $errSb = New-Object System.Text.StringBuilder
    $outEvent = Register-ObjectEvent -InputObject $proc -EventName OutputDataReceived -Action {
        if ($EventArgs.Data) { [void]$event.MessageData.Out.AppendLine($EventArgs.Data) }
    } -MessageData @{ Out = $outSb }
    $errEvent = Register-ObjectEvent -InputObject $proc -EventName ErrorDataReceived -Action {
        if ($EventArgs.Data) { [void]$event.MessageData.Out.AppendLine($EventArgs.Data) }
    } -MessageData @{ Out = $errSb }
    $proc.BeginOutputReadLine()
    $proc.BeginErrorReadLine()
    $done = $proc.WaitForExit($TimeoutSec * 1000)
    if ($done) {
        $proc.WaitForExit() | Out-Null
        $code = $proc.ExitCode
    } else {
        $code = -1
        try { & taskkill.exe /PID $proc.Id /T /F 2>&1 | Out-Null } catch {}
    }
    try { Unregister-Event -SourceIdentifier $outEvent.Id -ErrorAction SilentlyContinue } catch {}
    try { Unregister-Event -SourceIdentifier $errEvent.Id -ErrorAction SilentlyContinue } catch {}
    $proc.Dispose()
    [System.IO.File]::WriteAllText($StdOut, $outSb.ToString() + $errSb.ToString(), [System.Text.Encoding]::UTF8)
    return @{ code = $code; timedOut = -not $done }
}

function Build-Bat {
    param([string]$Body)
    $path = Join-Path $outDir ('step_' + [guid]::NewGuid().ToString('N') + '.bat')
    $head = "@echo off`r`ncall `"$settings`" >nul 2>&1`r`ncd /d `"$outDir`"`r`n"
    Set-Content -Path $path -Value ($head + $Body) -Encoding ASCII
    return $path
}

# ---- 1) compile all sources (single watchdog bound) --------------------------
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$allQuoted = (($rtlFiles + $tbFiles) | ForEach-Object { '"' + $_ + '"' }) -join ' '
$compileBody = "if exist xvlog.pb del /q xvlog.pb`r`n" +
               "if exist xsim.dir rmdir /s /q xsim.dir`r`n" +
               "call xvlog -i `"$root`" $allQuoted 2>&1`r`n" +
               "exit /b %errorlevel%"
Write-Host "[1/2] xvlog compile ($($rtlFiles.Count + $tbFiles.Count) files) ..." -NoNewline
$r = Run-CmdBat -BatPath (Build-Bat $compileBody) -StdOut (Join-Path $outDir 'compile.log') -TimeoutSec $CompileTimeoutSec
if ($r.timedOut) {
    Write-Host " TIMEOUT(>$CompileTimeoutSec s)"
    Write-Host 'compile step killed; tail of compile.log:'
    Get-Content (Join-Path $outDir 'compile.log') -Tail 20
    exit 2
}
if ($r.code -ne 0) {
    Write-Host " FAIL (exit $($r.code))"
    Get-Content (Join-Path $outDir 'compile.log') -Tail 20
    exit 2
}
Write-Host (' done ({0:N0} s)' -f $sw.Elapsed.TotalSeconds)

# ---- 2) per-TB xelab+xsim with watchdog --------------------------------------
$passCnt = 0
$timeoutCnt = 0
Write-Host "[2/2] run $($tbNames.Count) test(s) (watchdog ${TimeoutSec}s each)"
$results = @()
foreach ($tb in $tbNames) {
    $tsw = [System.Diagnostics.Stopwatch]::StartNew()
    Write-Host ("  {0,-20} " -f $tb) -NoNewline
    $logPath = Join-Path $outDir "$tb.log"
    $tbBody = "call xelab $tb -s $tb 2>&1`r`n" +
              "if errorlevel 1 exit /b 3`r`n" +
              "call xsim $tb -runall -log `"$logPath`" 2>&1`r`n" +
              "exit /b %errorlevel%"
    $r = Run-CmdBat -BatPath (Build-Bat $tbBody) -StdOut (Join-Path $outDir "run_$tb.out") -TimeoutSec $TimeoutSec
    $tsw.Stop()
    $sec = ('{0:N1}s' -f $tsw.Elapsed.TotalSeconds)
    if ($r.timedOut) {
        $timeoutCnt++
        Write-Host ("TIMEOUT(>{0}s)" -f $TimeoutSec)
        $results += "$tb TIMEOUT"
        continue
    }
    if (-not (Test-Path $logPath)) {
        Write-Host ("FAIL no-log ({0})" -f $sec)
        $results += "$tb NO-LOG"
        continue
    }
    $lines = Get-Content $logPath
    $ok  = ($lines -match 'ALL PASS').Count -gt 0
    $bad = ($lines -match 'FAIL').Count -gt 0
    if ($ok -and -not $bad) {
        $passCnt++
        Write-Host ("PASS ({0})" -f $sec)
        $results += "$tb PASS"
    } else {
        Write-Host ("FAIL ({0})  <- see out\{1}.log" -f $sec, $tb)
        $results += "$tb FAIL"
    }
}

# ---- summary ------------------------------------------------------------------
Write-Host ''
Write-Host '== summary =='
$results | ForEach-Object { Write-Host ("  {0}" -f $_) }
Write-Host ''
Write-Host ("PASS {0}/{1}  (timeout {2})  elapsed {3:N0} s  logs: {4}" -f $passCnt, $tbNames.Count, $timeoutCnt, $sw.Elapsed.TotalSeconds, $outDir)
if ($passCnt -ne $tbNames.Count) { exit 1 }
exit 0
