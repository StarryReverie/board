#=============================================================================
# run_mut.ps1 — 指令级变异测试（上板自检链的灵敏度证据）
#   用途：把上板验收程序里与"正确运行签名"相关的指令逐条改坏（NOP / 交换操作数），
#         重跑程序并读 dmem[0] 签名；判据：**每个变异都必须使签名 ≠ 0x0F**。
#         这是报告里"签名 0x0F ⇒ 覆盖项全对"的灵敏度依据（见 board_runbook §5.1）。
#   用法：powershell -File pipeline/src/scripts/run_mut.ps1
#   产物：<repo>/build/mut_out/tb_mut.log（逐条 DETECTED/MISSED）——build/ 不入库
#   说明：不在回归集合内；TB 源码见 pipeline/src/test/mut/tb_mut.v
#=============================================================================
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$viv  = if ($env:XVIVADO_ROOT) { $env:XVIVADO_ROOT } else { 'C:\Xilinx\Vivado\2019.2' }
$wDir = Join-Path $root 'build\mut_out'
if (Test-Path $wDir) { Remove-Item $wDir -Recurse -Force }
New-Item -ItemType Directory -Path $wDir -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $root 'build\tmp') -Force | Out-Null

Copy-Item (Join-Path $root 'pipeline\src\test\exp1_board_demo_rom.hex') $wDir -Force
$rtl = @(Get-ChildItem (Join-Path $root 'pipeline\src\rtl') -Filter '*.v' -File | ForEach-Object { $_.FullName })
$tb  = Join-Path $root 'pipeline\src\test\mut\tb_mut.v'
$srcList = ((@($rtl | ForEach-Object { '"' + $_ + '"' }) + ('"' + $tb + '"')) -join ' ')
$bat = @(
    '@echo off',
    ('call "' + $viv + '\settings64.bat" >nul 2>&1'),
    ('set TEMP=' + $root + '\build\tmp'),
    ('set TMP=' + $root + '\build\tmp'),
    ('cd /d "' + $wDir + '"'),
    ('call xvlog -i "' + $root + '\pipeline\src" ' + $srcList),
    'if errorlevel 1 ( echo [XVLOG_FAIL] & exit /b 2 )',
    'call xelab tb_mut -s tb_mut',
    'if errorlevel 1 ( echo [XELAB_FAIL] & exit /b 3 )',
    'call xsim tb_mut -runall',
    'if errorlevel 1 ( echo [XSIM_FAIL] & exit /b 4 )',
    'exit /b 0'
)
$batFile = Join-Path $wDir 'run.bat'
Set-Content -Path $batFile -Value $bat -Encoding ASCII

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = 'cmd.exe'; $psi.Arguments = '/c "' + $batFile + '"'
$psi.WorkingDirectory = $wDir; $psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
# 并发排空 stdout/stderr：只读一路会在子进程写满另一路管道时死锁（Vivado 的 stderr 量不小）
$proc = [System.Diagnostics.Process]::Start($psi)
$soTask = $proc.StandardOutput.ReadToEndAsync()
$seTask = $proc.StandardError.ReadToEndAsync()
$proc.WaitForExit()
$out = $soTask.GetAwaiter().GetResult()
$err = $seTask.GetAwaiter().GetResult()
($out + "`r`n[stderr]`r`n" + $err) | Set-Content -Path (Join-Path $wDir 'tb_mut.log') -Encoding ASCII
foreach ($ln in ($out -split "`r?`n")) {
    if ($ln -match 'BASE|DETECTED|MISSED|mutation') { Write-Host ('  ' + $ln.Trim()) }
}
if ($proc.ExitCode -ne 0) {
    Write-Host ("[FAIL] 仿真未正常跑完（退出码 {0}；xvlog/xelab/xsim 失败），见 tb_mut.log" -f $proc.ExitCode)
    exit 1
}
if ($out -match 'MUTATION ALL PASS') { exit 0 } else { Write-Host '[FAIL] 见 tb_mut.log'; exit 1 }
