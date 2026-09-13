<#
=============================================================================
  run_wave.ps1 — 实验一关键波形采样运行器（plan.md 四项仿真）
    * 编译 RTL + test/wave/wave_pipe.v（独立于 run_tb.ps1 的 21 项回归）
    * 运行后产出 out/wave/ 下：
        wave_cover.csv/.vcd    wave_hazard.csv/.vcd    wave_priority.csv/.vcd
        wave_marks.csv         wave_pipe.log
    * 随后调用 scripts/wave_png.ps1 渲染四项波形 PNG
    * 用法: powershell -File pipeline/src/scripts/run_wave.ps1 [-NoRender]
    * 环境: 默认 C:\Xilinx\Vivado\2019.2；$env:XVIVADO_ROOT 覆盖
=============================================================================
#>
param([switch]$NoRender)

$ErrorActionPreference = 'Stop'
$root    = Split-Path -Parent $PSScriptRoot              # src/
$vivado  = if ($env:XVIVADO_ROOT) { $env:XVIVADO_ROOT } else { 'C:\Xilinx\Vivado\2019.2' }
$settings = Join-Path $vivado 'settings64.bat'
if (-not (Test-Path $settings)) { Write-Error "找不到 $settings"; exit 1 }

$rtlFiles = @(Get-ChildItem -Path (Join-Path $root 'rtl') -Filter '*.v' -File | Select-Object -ExpandProperty FullName)
$tbWave   = Join-Path $root 'test\wave\wave_pipe.v'
if (-not (Test-Path $tbWave)) { Write-Error "找不到 $tbWave"; exit 1 }

$testDir = Join-Path $root 'test'
$outDir  = Join-Path $PSScriptRoot 'out\wave'
if (Test-Path $outDir) { Remove-Item $outDir -Recurse -Force }
New-Item -ItemType Directory -Path $outDir | Out-Null

# 镜像拷入仿真 cwd（$readmemh 相对 cwd）
foreach ($h in 'instr_cover_rom.hex','hazard_cover_rom.hex','fwd_priority_rom.hex') {
    Copy-Item -Path (Join-Path $testDir $h) -Destination $outDir -Force
}

$bat = Join-Path $outDir 'run.bat'
$all = @($rtlFiles) + @($tbWave)
$a = ($all | ForEach-Object { "`"$_`"" }) -join ' '
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('@echo off')
[void]$sb.AppendLine("call `"$settings`" >nul 2>&1")
[void]$sb.AppendLine("cd /d `"$outDir`"")
[void]$sb.AppendLine("call xvlog -i `"$root`" $a")
[void]$sb.AppendLine('if errorlevel 1 ( echo [COMPILE_FAIL] & exit /b 2 )')
[void]$sb.AppendLine('call xelab wave_pipe -s wave_pipe')
[void]$sb.AppendLine('if errorlevel 1 ( echo [XELAB_FAIL] & exit /b 3 )')
[void]$sb.AppendLine("call xsim wave_pipe -runall -log `"wave_pipe.log`"")
[void]$sb.AppendLine('if errorlevel 1 ( echo [XSIM_FAIL] & exit /b 4 )')
[void]$sb.AppendLine('exit /b 0')
Set-Content -Path $bat -Value $sb.ToString() -Encoding ASCII

Write-Host '[运行] wave_pipe（cover / hazard / priority 三段）'
& cmd.exe /c "`"$bat`" > `"$(Join-Path $outDir 'run_all.log')`" 2>&1"
if ($LASTEXITCODE -ne 0) { Write-Host ("  [异常] 退出码 {0}，见 out\wave\run_all.log" -f $LASTEXITCODE); exit 1 }

$log = Join-Path $outDir 'wave_pipe.log'
$pass = Select-String -Path $log -Pattern '=== ALL PASS ===' -Quiet
$marks = (Select-String -Path $log -Pattern 'WAVE_MARKS:').Line
Write-Host "  $marks"
if ($pass -and $marks -and $marks -notmatch '=-1(?:\s|$)') {
    Write-Host '  wave_pipe: === ALL PASS ==='
} else {
    Write-Host '  wave_pipe: FAIL（波形标记缺失或未全 PASS，见 out\wave\wave_pipe.log）'
    exit 1
}

if (-not $NoRender) {
    $png = Join-Path $PSScriptRoot 'wave_png.ps1'
    if (Test-Path $png) {
        Write-Host ''
        & powershell -NoProfile -File $png
    } else {
        Write-Host '[提示] 未找到 wave_png.ps1，跳过 PNG 渲染'
    }
}
Write-Host ''
Write-Host ("产物: $outDir")
