$ErrorActionPreference = 'Stop'
$vivado  = if ($env:XVIVADO_ROOT) { $env:XVIVADO_ROOT } else { 'C:\Xilinx\Vivado\2019.2' }
$scriptsDir = Split-Path -Parent $MyInvocation.MyCommand.Path   # UART/src/scripts
$srcDir     = Split-Path -Parent $scriptsDir                    # UART/src
$root       = Split-Path -Parent (Split-Path -Parent $srcDir)   # repo root
$rtl        = Join-Path $srcDir 'rtl'
$tb         = Join-Path $srcDir 'test\tb_wave_868.v'
$out        = Join-Path $root 'build\wave868'                   # build/ 不入库（.gitignore）
# 清空重建；xsim 退出后偶有句柄延迟，删不掉时退化为就地复用
if (Test-Path $out) {
    try { Remove-Item $out -Recurse -Force -ErrorAction Stop }
    catch { Start-Sleep -Milliseconds 500; Remove-Item $out -Recurse -Force -ErrorAction SilentlyContinue }
}
New-Item -ItemType Directory -Path $out -Force | Out-Null

$bat = Join-Path $out 'run.bat'
$lines = @(
    '@echo off'
    "call `"$vivado\settings64.bat`" >nul 2>&1"
    "cd /d `"$out`""
    "call xvlog `"$rtl\uart_tx.v`" `"$rtl\uart_rx.v`" `"$rtl\uart_ip_top.v`" `"$tb`""
    "if errorlevel 1 ( echo [XVLOG_FAIL] & exit /b 2 )"
    "call xelab tb_wave_868 -s tb_wave_868 --debug typical"
    "if errorlevel 1 ( echo [XELAB_FAIL] & exit /b 3 )"
    "call xsim tb_wave_868 -runall -log wave868.log"
    "if errorlevel 1 ( echo [XSIM_FAIL] & exit /b 4 )"
    'echo [WAVE_DONE]'
    'exit /b 0'
)
Set-Content -Path $bat -Value $lines -Encoding ASCII
& cmd.exe /c $bat
$runExit = $LASTEXITCODE
if ($runExit -ne 0) { exit $runExit }

$waveLog = Join-Path $out 'wave868.log'
if (-not (Test-Path $waveLog) -or -not (Select-String -Path $waveLog -Pattern 'ALL PASS' -Quiet)) {
    Write-Host '[WAVE_FAIL] wave868.log missing ALL PASS marker'
    exit 5
}
Write-Host '[WAVE_DONE] ALL PASS marker verified'
exit 0
