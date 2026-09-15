<#
=============================================================================
 run_tb.ps1 - experiment-1 module test parallel runner (Vivado 2019.2 xsim)
   * auto-discover: RTL in pipeline/src/rtl/*.v and TB in pipeline/src/test/tb_*.v
   * why parallel: each TB needs a cold xelab+xsim process launch (~5-7 s) but
     the simulation content itself is microseconds (IDE feels fast only because
     its simulator engine is resident). Running 21 TBs serially = ~2-4 min.
     This runner splits the TBs across -Jobs isolated workers that compile +
     elaborate + simulate concurrently, so wall time ~= N_cases/Jobs * per-case.
   * each worker has its own scratch dir under out/ (own xvlog.pb/xsim.dir),
     so no shared-library races; a whole-worker watchdog (per-case budget x
     cases + slack) kills a hung worker and continues with the rest.
   * TB output contract: per assertion $display("PASS: ...") / ("FAIL: ..."),
     ending with $display("=== ALL PASS ===") or $display("=== FAIL ===")
   * usage:
       powershell -File pipeline/src/scripts/run_tb.ps1 -List
       powershell -File pipeline/src/scripts/run_tb.ps1
       powershell -File pipeline/src/scripts/run_tb.ps1 -Case alu
       powershell -File pipeline/src/scripts/run_tb.ps1 -Jobs 8     # cap to 8 workers
       powershell -File pipeline/src/scripts/run_tb.ps1 -Jobs 1     # serial (old behavior)
   * default -Jobs 0 = auto: min(#TB, logical processors) -> full-machine parallelism
   * env: default C:\Xilinx\Vivado\2019.2 ; override with $env:XVIVADO_ROOT
=============================================================================
#>
param(
    [string]$Case = '',          # filter keyword (substring of tb name, comma separated)
    [switch]$List,               # only list test benches
    [ValidateRange(1, [int]::MaxValue)]
    [int]$TimeoutSec = 30,       # per-case budget used for the worker watchdog
    [int]$Jobs = 0               # parallel workers; 0 = auto (min(#tb, logical processors))
)

$ErrorActionPreference = 'Stop'
$root    = Split-Path -Parent $PSScriptRoot          # repo root (src)

# ---- 本机环境修补：进程环境里存在"大小写重复"的变量名（如 NO_PROXY / no_proxy）----
#   Windows 环境块本身大小写不敏感，但 PowerShell 5.1 的 Start-Process 用区分大小写的
#   字典复制环境，会抛 "Item has already been added. Key in dictionary: 'NO_PROXY' ..."，
#   导致本脚本在本机无法启动 worker；Env: 提供程序读到同名项时同样会抛该异常（实测）。
#   这里把每组同名项**归一为唯一一项**。归一规则（确定性，不依赖枚举顺序）：
#     ① 取值以"大小写不敏感查找"的结果为准（= OS 实际会用的那个值），保证语义不变；
#     ② 规范名：优先全大写变体，否则按名称序数升序取第一个；
#     ③ 各变体自身取值互相冲突时打印警告并说明采用了哪一个，不静默丢弃。
#   归一后同名项只剩一项，$env:XVIVADO_ROOT 这类大小写不敏感查找的结果唯一且确定。
$envDict   = [Environment]::GetEnvironmentVariables('Process')
$envGroups = @{}
foreach ($k in @($envDict.Keys)) {
    $lk = $k.ToLowerInvariant()
    if (-not $envGroups.ContainsKey($lk)) { $envGroups[$lk] = @() }
    $envGroups[$lk] += ,([pscustomobject]@{ Name = $k; Value = [string]$envDict[$k] })
}
foreach ($lk in @($envGroups.Keys)) {
    $grp = @($envGroups[$lk])
    if ($grp.Count -lt 2) { continue }

    $eff    = [string][Environment]::GetEnvironmentVariable($lk, 'Process')      # ①
    $uppers = @($grp | Where-Object { $_.Name -ceq $_.Name.ToUpperInvariant() }) # ②
    $canon  = $null
    if ($uppers.Count -gt 0) { $canon = @($uppers | Sort-Object -Property Name -CaseSensitive)[0].Name }
    else                     { $canon = @($grp    | Sort-Object -Property Name -CaseSensitive)[0].Name }

    $ownValues = @($grp | Select-Object -ExpandProperty Value -Unique)
    if ($ownValues.Count -gt 1) {                                                # ③
        $namesTxt = ($grp | Select-Object -ExpandProperty Name) -join '/'
        $pairsTxt = ($grp | ForEach-Object { '{0}="{1}"' -f $_.Name, $_.Value }) -join ', '
        Write-Warning ('环境变量大小写重复且取值不一致：' + $namesTxt + ' → 归一为 ' +
                       $canon + '="' + $eff + '"（原 ' + $pairsTxt + '）')
    }

    # Env: 提供程序按大小写不敏感解析（实测：删 no_proxy 会删掉 NO_PROXY），
    # 故先按组内数量逐个删除，再把有效取值写回规范名 → 组内最终恰好剩一项。
    for ($i = 0; $i -lt $grp.Count; $i++) {
        Remove-Item -LiteralPath ('Env:' + $lk) -ErrorAction SilentlyContinue
    }
    Set-Item -LiteralPath ('Env:' + $canon) -Value $eff -ErrorAction SilentlyContinue
    $envNow = [string][Environment]::GetEnvironmentVariable($lk, 'Process')
    if ($envNow -ne $eff) {
        Write-Warning ('环境变量归一失败：' + $canon + ' 期望 "' + $eff + '"（实际 "' + $envNow + '"）')
    }
}

$vivado  = if ($env:XVIVADO_ROOT) { $env:XVIVADO_ROOT } else { 'C:\Xilinx\Vivado\2019.2' }
$settings = Join-Path $vivado 'settings64.bat'
if (-not (Test-Path $settings)) { Write-Error "cannot find $settings (set `$env:XVIVADO_ROOT)"; exit 1 }

# ---- collect sources & TBs -------------------------------------------------
$rtlFiles = @(Get-ChildItem -Path (Join-Path $root 'rtl') -Filter '*.v' -File | Select-Object -ExpandProperty FullName)
$tbFiles  = @(Get-ChildItem -Path (Join-Path $root 'test') -Filter 'tb_*.v' -File | Select-Object -ExpandProperty FullName)

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
if ($rtlFiles.Count -eq 0) { Write-Host '[hint] no RTL (*.v) in rtl/' }
if ($tbFiles.Count  -eq 0) { Write-Host '[hint] no tb_*.v in test/' }

if ($Jobs -le 0) {
    $cores = [Math]::Max(1, [int]$env:NUMBER_OF_PROCESSORS)
    $Jobs = [Math]::Min($tbNames.Count, $cores)
}
if ($Jobs -gt $tbNames.Count) { $Jobs = $tbNames.Count }

# ---- output dir (rebuilt every run) -----------------------------------------
$outDir = Join-Path $PSScriptRoot 'out'
if (Test-Path $outDir) { Remove-Item $outDir -Recurse -Force }
New-Item -ItemType Directory -Path $outDir | Out-Null

# program regression TBs read *.hex by name via $readmemh (sim cwd = worker dir)
$hexFiles = @(Get-ChildItem -Path (Join-Path $root 'test') -Filter '*.hex' -File |
    Select-Object -ExpandProperty FullName)
foreach ($h in $hexFiles) { Copy-Item $h -Destination $outDir -Force }

# ---- helpers ----------------------------------------------------------------
function Build-WorkerBat {
    param([int]$WorkerId, [string[]]$Subset)
    $wDir = Join-Path $outDir ("w$WorkerId")
    $allQuoted = (($rtlFiles + $tbFiles) | ForEach-Object { '"' + $_ + '"' }) -join ' '
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('@echo off')
    [void]$sb.AppendLine("call `"$settings`" >nul 2>&1")
    [void]$sb.AppendLine("cd /d `"$wDir`"")
    [void]$sb.AppendLine('if exist xvlog.pb del /q xvlog.pb')
    [void]$sb.AppendLine('if exist xsim.dir  rmdir /s /q xsim.dir')
    [void]$sb.AppendLine("call xvlog -i `"$root`" $allQuoted 2>&1")
    [void]$sb.AppendLine('if errorlevel 1 ( echo [WORKER_COMPILE_FAIL] & exit /b 2 )')
    $i = 0
    foreach ($tb in $Subset) {
        [void]$sb.AppendLine("call xelab $tb -s $tb 2>&1")
        [void]$sb.AppendLine("if errorlevel 1 ( echo [XELAB_FAIL] $tb & goto :next_$i )")
        [void]$sb.AppendLine("call xsim $tb -runall -log `"$tb.log`" 2>&1")
        [void]$sb.AppendLine("if errorlevel 1 ( echo [XSIM_FAIL] $tb )")
        [void]$sb.AppendLine(":next_$i")
        $i++
    }
    [void]$sb.AppendLine('echo [WORKER_DONE]')
    [void]$sb.AppendLine('exit /b 0')
    return $sb.ToString()
}

# ---- launch workers ----------------------------------------------------------
$sw = [System.Diagnostics.Stopwatch]::StartNew()
Write-Host ("compile+elaborate+simulate {0} test(s) across {1} worker(s) (watchdog {2}s/case)" -f $tbNames.Count, $Jobs, $TimeoutSec)

# round-robin assignment: tb -> worker id
$tbWorker = @{}
for ($i = 0; $i -lt $tbNames.Count; $i++) { $tbWorker[$tbNames[$i]] = $i % $Jobs }

$procs = @()   # @{ id; p; allowedMs; tbList }
for ($w = 0; $w -lt $Jobs; $w++) {
    $wDir = Join-Path $outDir ("w$w")
    New-Item -ItemType Directory -Path $wDir | Out-Null
    foreach ($h in $hexFiles) { Copy-Item $h -Destination $wDir -Force }

    $subset = @($tbNames | Where-Object { $tbWorker[$_] -eq $w })
    $batPath = Join-Path $outDir ("run_w$w.bat")
    Set-Content -Path $batPath -Value (Build-WorkerBat $w $subset) -Encoding ASCII

    $p = Start-Process -FilePath 'cmd.exe' `
            -ArgumentList @('/c', ('"' + $batPath + '"')) `
            -WorkingDirectory $outDir `
            -RedirectStandardOutput (Join-Path $wDir 'worker.out') `
            -RedirectStandardError  (Join-Path $wDir 'worker.err') `
            -PassThru -WindowStyle Hidden
    # each worker gets an absolute deadline: per-case budget x cases + slack;
    # slack scales with $Jobs because every worker recompiles all sources
    # (the compile phase slows down as concurrency grows).
    $slackSec = 90 * [Math]::Max(1, [int][Math]::Ceiling($Jobs / 8))
    $allowedMs = $subset.Count * $TimeoutSec * 1000 + $slackSec * 1000
    $deadline = (Get-Date).AddMilliseconds($allowedMs)
    $procs += @{ id = $w; p = $p; allowedMs = $allowedMs; deadline = $deadline; tbList = $subset }
}

# wait with per-worker watchdog; kill hung worker tree
foreach ($wp in $procs) {
    $leftMs = [int][Math]::Max(0, ($wp.deadline - (Get-Date)).TotalMilliseconds)
    $done = $wp.p.WaitForExit($leftMs)
    if (-not $done) {
        try { & taskkill.exe /PID $wp.p.Id /T /F 2>&1 | Out-Null } catch {}
        Write-Host ("  worker w{0} TIMEOUT(>{1:N0}s) killed" -f $wp.id, ($wp.allowedMs / 1000))
    }
}

# ---- aggregate results ---------------------------------------------------------
$passCnt = 0
$timeoutCnt = 0
$results = @()
foreach ($tb in $tbNames) {
    $w = $tbWorker[$tb]
    $log = Join-Path (Join-Path $outDir ("w$w")) "$tb.log"
    if (-not (Test-Path $log)) {
        Write-Host ("  {0,-20} FAIL no-log (worker w{1})" -f $tb, $w)
        $results += "$tb FAIL(no-log)"
        $timeoutCnt++
        continue
    }
    $lines = Get-Content $log
    $ok  = ($lines -match 'ALL PASS').Count -gt 0
    $bad = ($lines -match 'FAIL').Count -gt 0
    if ($ok -and -not $bad) {
        $passCnt++
        Write-Host ("  {0,-20} PASS" -f $tb)
        $results += "$tb PASS"
    } else {
        Write-Host ("  {0,-20} FAIL  <- see out\w{1}\{2}.log" -f $tb, $w, $tb)
        $results += "$tb FAIL"
    }
}

Write-Host ''
Write-Host '== summary =='
$results | ForEach-Object { Write-Host ("  {0}" -f $_) }
Write-Host ''
Write-Host ("PASS {0}/{1}  (missing/timeout {2})  elapsed {3:N0} s  workers: {4}  logs: {5}" -f $passCnt, $tbNames.Count, $timeoutCnt, $sw.Elapsed.TotalSeconds, $Jobs, $outDir)
if ($passCnt -ne $tbNames.Count) { exit 1 }
exit 0
