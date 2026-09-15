# run_soc_tb.ps1 — SoC/UART 侧 TB 运行器（仓库自带；run_tb.ps1 只收 pipeline/src/test）
#   用途：xvlog/xelab/xsim 依次跑 soc/test 与 UART/src/test 的 TB —— 改 soc/ 或 UART/ 侧
#         RTL 后用它验证（这些 TB 不在 23 项 pipeline 回归里）。
#   用法：powershell -File soc/scripts/run_soc_tb.ps1          # 默认 3 项：tb_reset_sync/tb_soc_console/tb_soc_full
#         powershell -File soc/scripts/run_soc_tb.ps1 -All     # soc/test + UART/src/test 全部 tb_*.v
#   产物：<repo>/build/soc_sim_out/<tb>/（xvlog/xelab/xsim 日志）——build/ 不入库
param([switch]$All)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
$viv  = if ($env:XVIVADO_ROOT) { $env:XVIVADO_ROOT } else { 'C:\Xilinx\Vivado\2019.2' }

$rtl = @()
foreach ($d in @("$root\soc\rtl", "$root\UART\src\rtl", "$root\pipeline\src\rtl")) {
    $rtl += @(Get-ChildItem $d -Filter '*.v' -File | ForEach-Object { $_.FullName })
}

$tbDirs = @("$root\soc\test", "$root\UART\src\test")
if ($All) {
    $tbs = @()
    foreach ($d in $tbDirs) { $tbs += @(Get-ChildItem $d -Filter 'tb_*.v' -File | ForEach-Object { $_.BaseName }) }
    $tbs = $tbs | Sort-Object -Unique
} else {
    $tbs = @('tb_reset_sync', 'tb_soc_console', 'tb_soc_full')
}

$outRoot = "$root\build\soc_sim_out"
if (Test-Path $outRoot) { Remove-Item $outRoot -Recurse -Force }
New-Item -ItemType Directory -Path $outRoot -Force | Out-Null

$pass = 0
foreach ($tb in $tbs) {
    $tbFile = $null
    foreach ($d in $tbDirs) { $p = Join-Path $d ($tb + '.v'); if (Test-Path $p) { $tbFile = $p } }
    if (-not $tbFile) { Write-Host ("  {0,-20} SKIP (not found)" -f $tb); continue }

    $wDir = Join-Path $outRoot $tb
    New-Item -ItemType Directory -Path $wDir -Force | Out-Null
    # 仿真用 hex（$readmemh 按文件名读取）：从两个 TB 目录收集，再以目标目录实际数量核验
    foreach ($d in $tbDirs) {
        foreach ($h in @(Get-ChildItem $d -Filter '*.hex' -File -ErrorAction SilentlyContinue)) {
            Copy-Item -LiteralPath $h.FullName -Destination $wDir -Force
        }
    }
    $hexCnt = @(Get-ChildItem $wDir -Filter '*.hex' -File -ErrorAction SilentlyContinue).Count
    Write-Host ('    [dbg] {0}: hex in workdir = {1}' -f $tb, $hexCnt)

    $srcList = (@($rtl | ForEach-Object { '"' + $_ + '"' }) + ('"' + $tbFile + '"')) -join ' '
    $batLines = @(
        '@echo off',
        ('call "' + $viv + '\settings64.bat" >nul 2>&1'),
        ('set TEMP=' + $root + '\build\tmp'),
        ('set TMP=' + $root + '\build\tmp'),
        ('cd /d "' + $wDir + '"'),
        ('call xvlog -i "' + $root + '\pipeline\src" -i "' + $root + '\soc" -i "' + $root + '\UART\src" ' + $srcList),
        'if errorlevel 1 ( echo [XVLOG_FAIL] & exit /b 2 )',
        ('call xelab ' + $tb + ' -s ' + $tb),
        'if errorlevel 1 ( echo [XELAB_FAIL] & exit /b 3 )',
        ('call xsim ' + $tb + ' -runall -log sim.log'),
        'if errorlevel 1 ( echo [XSIM_FAIL] & exit /b 4 )',
        'exit /b 0'
    )
    $bat = Join-Path $wDir 'run.bat'
    Set-Content -Path $bat -Value $batLines -Encoding ASCII

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'cmd.exe'; $psi.Arguments = '/c "' + $bat + '"'
    $psi.WorkingDirectory = $wDir; $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    # 并发排空 stdout/stderr：只读一路会在另一路写满时死锁（xvlog/xelab/xsim 的 stderr 都可能很长）
    $proc = [System.Diagnostics.Process]::Start($psi)
    $soTask = $proc.StandardOutput.ReadToEndAsync()
    $seTask = $proc.StandardError.ReadToEndAsync()
    $proc.WaitForExit()
    $stdout = $soTask.GetAwaiter().GetResult()
    $stderr = $seTask.GetAwaiter().GetResult()

    $log = Join-Path $wDir 'sim.log'
    $txt = if (Test-Path $log) { Get-Content $log -Raw } else { '' }
    $allpass = $txt -match 'ALL PASS'
    $fails   = ([regex]::Matches($txt, 'FAIL:')).Count
    # 判据 = 日志 ALL PASS + 无 FAIL 行 + batch 退出码 0（xvlog/xelab/xsim 失败返回 2/3/4；
    # 若只在 ALL PASS 之后才失败，以前会被误记成 PASS）
    $passed  = $allpass -and ($fails -eq 0) -and ($proc.ExitCode -eq 0)
    if ($passed) { $pass++ }
    $rcTag = if ($proc.ExitCode -ne 0) { "  (退出码=$($proc.ExitCode))" } else { '' }
    Write-Host ("  {0,-20} {1}{2}{3}" -f $tb, $(if ($passed) { 'PASS' } else { 'FAIL' }), $(if ($fails) { "  (FAIL 行数=$fails)" } else { '' }), $rcTag)
    if (-not $passed) {
        # 编译/精化失败时 sim.log 可能不存在：把 batch 的失败标记与 stderr 也报出来
        foreach ($ln in (($stdout + "`n" + $stderr) -split "`r?`n")) {
            if ($ln -match '\[XVLOG_FAIL\]|\[XELAB_FAIL\]|\[XSIM_FAIL\]|ERROR:') { Write-Host ('      ' + $ln.Trim()) }
        }
    }
    if (-not $passed -and $txt) {
        ($txt -split "`n" | Select-String -Pattern 'FAIL:|ERROR|error' | Select-Object -First 8) | ForEach-Object { '      ' + $_.Line.Trim() }
    }
}
Write-Host ''
Write-Host ("== soc-tb summary ==  PASS {0}/{1}   logs: {2}" -f $pass, $tbs.Count, $outRoot)
if ($pass -ne $tbs.Count) { exit 1 }
exit 0
