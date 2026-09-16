# run_exp2_wave.ps1 — 实验二波形 TB 运行器（第 3/4 项聚焦重绘的数据源）
#   用途：编译 soc/rtl + UART/src/rtl + pipeline/src/rtl 与两个波形 TB，跑 xsim，
#         产出逐拍/逐跳变 CSV（渲染 ppt/assets/exp2-*.png 用）。
#         这些 TB 放在 test/wave/ 子目录，run_soc_tb.ps1 只收 test 根目录的
#         tb_*.v，故不改变 8/8 回归口径。
#   用法：powershell -File UART/src/scripts/run_exp2_wave.ps1          # 两项都跑
#         powershell -File UART/src/scripts/run_exp2_wave.ps1 -Item 3  # 只第 3 项
#   产物：build/exp2_wave/<tb>/{*.log,*.csv}（不入库）
#         ppt/wave/exp2/{ip_duplex,wave_soc}.csv（渲染器输入，入库）
param([string]$Item = 'all')

$ErrorActionPreference = 'Stop'
$scriptsDir = Split-Path -Parent $MyInvocation.MyCommand.Path   # UART/src/scripts
$uartSrc    = Split-Path -Parent $scriptsDir                    # UART/src
$root       = Split-Path -Parent (Split-Path -Parent $uartSrc)  # repo root
$viv        = if ($env:XVIVADO_ROOT) { $env:XVIVADO_ROOT } else { 'C:\Xilinx\Vivado\2019.2' }

$rtl = @()
foreach ($d in @("$root\soc\rtl", "$root\UART\src\rtl", "$root\pipeline\src\rtl")) {
    $rtl += @(Get-ChildItem $d -Filter '*.v' -File | ForEach-Object { $_.FullName })
}

$tbs = @()
if ($Item -eq 'all' -or $Item -eq '3') {
    $tbs += @{ name = 'tb_ip_duplex'; file = "$root\UART\src\test\wave\tb_ip_duplex.v"; csv = 'ip_duplex.csv' }
}
if ($Item -eq 'all' -or $Item -eq '4') {
    $tbs += @{ name = 'tb_wave_soc'; file = "$root\soc\test\wave\tb_wave_soc.v"; csv = 'wave_soc.csv' }
}
if ($tbs.Count -eq 0) { Write-Error "未知 -Item '$Item'（用 all / 3 / 4）"; exit 1 }

$outRoot = "$root\build\exp2_wave"
if (Test-Path $outRoot) { Remove-Item $outRoot -Recurse -Force }
New-Item -ItemType Directory -Path $outRoot -Force | Out-Null
$csvDir = "$root\ppt\wave\exp2"
New-Item -ItemType Directory -Path $csvDir -Force | Out-Null

$pass = 0
foreach ($tb in $tbs) {
    $wDir = Join-Path $outRoot $tb.name
    New-Item -ItemType Directory -Path $wDir -Force | Out-Null

    $srcList = (@($rtl | ForEach-Object { '"' + $_ + '"' }) + ('"' + $tb.file + '"')) -join ' '
    $batLines = @(
        '@echo off',
        ('call "' + $viv + '\settings64.bat" >nul 2>&1'),
        ('cd /d "' + $wDir + '"'),
        ('call xvlog -i "' + $root + '\pipeline\src" -i "' + $root + '\soc" -i "' + $root + '\UART\src" ' + $srcList),
        'if errorlevel 1 ( echo [XVLOG_FAIL] & exit /b 2 )',
        ('call xelab ' + $tb.name + ' -s ' + $tb.name),
        'if errorlevel 1 ( echo [XELAB_FAIL] & exit /b 3 )',
        ('call xsim ' + $tb.name + ' -runall -log ' + $tb.name + '.log'),
        'if errorlevel 1 ( echo [XSIM_FAIL] & exit /b 4 )',
        'exit /b 0'
    )
    $bat = Join-Path $wDir 'run.bat'
    Set-Content -Path $bat -Value $batLines -Encoding ASCII

    & cmd.exe /c "`"$bat`" > `"$(Join-Path $wDir 'run_all.log')`" 2>&1"
    $rc  = $LASTEXITCODE
    $log = Join-Path $wDir ($tb.name + '.log')
    $txt = if (Test-Path $log) { Get-Content $log -Raw } else { '' }
    $ok  = ($txt -match 'ALL PASS') -and ($rc -eq 0)
    if ($ok) { $pass++ }
    Write-Host ("  {0,-16} {1}" -f $tb.name, $(if ($ok) { 'PASS' } else { 'FAIL' }))
    if (-not $ok) {
        foreach ($ln in (($txt -split "`r?`n") | Select-String -Pattern 'FAIL:|ERROR|error' | Select-Object -First 8)) {
            Write-Host ('      ' + $ln.Line.Trim())
        }
    }

    $csv = Join-Path $wDir $tb.csv
    if (Test-Path $csv) {
        Copy-Item -LiteralPath $csv -Destination (Join-Path $csvDir $tb.csv) -Force
        Write-Host ('      csv -> ' + (Join-Path $csvDir $tb.csv))
    } else {
        Write-Host ('      [WARN] csv missing: ' + $csv)
    }
}

Write-Host ''
Write-Host ("== exp2-wave summary ==  PASS {0}/{1}   logs: {2}" -f $pass, $tbs.Count, $outRoot)
if ($pass -ne $tbs.Count) { exit 1 }
exit 0
