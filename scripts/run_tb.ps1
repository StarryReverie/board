<#
=============================================================================
 run_tb.ps1 — 计组实验一单测批量运行器（本机 Vivado 2019.2 xsim）
   * 自动发现：根目录 RTL（*.v）与 test/tb_*.v（模块名=文件名去扩展名）
   * 流程：xvlog 编译全部源与 TB → 逐个 xelab+xsim → 汇总 PASS/FAIL
   * TB 输出约定：每项断言 $display("PASS: ...")/$display("FAIL: ...")，
     结尾 $display("=== ALL PASS ===") 或 $display("=== FAIL ===")
   * 用法：
       .\scripts\run_tb.ps1 -List              # 列出可跑的单测
       .\scripts\run_tb.ps1                     # 跑全部单测
       .\scripts\run_tb.ps1 -Case alu           # 只跑名字含 alu 的 TB
   * 环境：默认 C:\Xilinx\Vivado\2019.2；可用 $env:XVIVADO_ROOT 覆盖
=============================================================================
#>
param(
    [string]$Case = '',          # 过滤关键字（对 tb 名做子串匹配，可多个逗号分隔）
    [switch]$List                # 仅列出单测清单
)

$ErrorActionPreference = 'Stop'
$root    = Split-Path -Parent $PSScriptRoot          # 仓库根
$vivado  = if ($env:XVIVADO_ROOT) { $env:XVIVADO_ROOT } else { 'C:\Xilinx\Vivado\2019.2' }
$settings = Join-Path $vivado 'settings64.bat'
if (-not (Test-Path $settings)) { Write-Error "找不到 $settings（用 `$env:XVIVADO_ROOT 指定 Vivado 根目录）"; exit 1 }

# ---- 收集源文件与 TB -----------------------------------------------------
$rtlFiles = @(Get-ChildItem -Path $root -Filter '*.v' -File | Select-Object -ExpandProperty FullName)
$tbFiles  = @(Get-ChildItem -Path (Join-Path $root 'test') -Filter 'tb_*.v' -File | Select-Object -ExpandProperty FullName)

if ($rtlFiles.Count -eq 0) { Write-Host '[提示] 根目录暂无 RTL（*.v），先写模块再跑单测' }
if ($tbFiles.Count  -eq 0) { Write-Host '[提示] test/ 暂无 tb_*.v 单测' }

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
    Write-Host '== 可跑单测 =='
    $tbNames | ForEach-Object { Write-Host "  $_" }
    exit 0
}
if ($tbNames.Count -eq 0) { Write-Host '[提示] 没有匹配的单测，退出'; exit 0 }

# ---- 输出目录（本次运行清空重建） ------------------------------------------
$outDir = Join-Path $PSScriptRoot 'out'
if (Test-Path $outDir) { Remove-Item $outDir -Recurse -Force }
New-Item -ItemType Directory -Path $outDir | Out-Null

# ---- 生成批处理（单一 cmd 会话以保持 settings64 环境） ----------------------
$bat = Join-Path $outDir 'run.bat'
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('@echo off')
[void]$sb.AppendLine("call `"$settings`" >nul 2>&1")
[void]$sb.AppendLine("cd /d `"$outDir`"")
[void]$sb.AppendLine('if exist xvlog.pb del /q xvlog.pb')
[void]$sb.AppendLine('if exist xsim.dir  rmdir /s /q xsim.dir')
if (($rtlFiles.Count -gt 0) -or ($tbFiles.Count -gt 0)) {
    $all = @($rtlFiles) + @($tbFiles)
    $args = ($all | ForEach-Object { "`"$_`"" }) -join ' '
    [void]$sb.AppendLine("call xvlog -i `"$root`" $args")
    [void]$sb.AppendLine('if errorlevel 1 ( echo [COMPILE_FAIL] & exit /b 2 )')
}
foreach ($tb in $tbNames) {
    [void]$sb.AppendLine("call xelab $tb -s $tb")
    [void]$sb.AppendLine("if errorlevel 1 ( echo [XELAB_FAIL] $tb & exit /b 3 )")
    [void]$sb.AppendLine("call xsim $tb -runall -log `"$(Join-Path $outDir "$tb.log")`"")
    [void]$sb.AppendLine("if errorlevel 1 ( echo [XSIM_FAIL] $tb & exit /b 4 )")
}
[void]$sb.AppendLine('exit /b 0')
Set-Content -Path $bat -Value $sb.ToString() -Encoding ASCII

# ---- 执行 ----------------------------------------------------------------
$allLog = Join-Path $outDir 'run_all.log'
Write-Host "[运行] $($tbNames.Count) 个单测: $($tbNames -join ', ')"
& cmd.exe /c "`"$bat`" > `"$allLog`" 2>&1"
$runCode = $LASTEXITCODE
if ($runCode -ne 0) {
    Write-Host "`n[异常] 批处理退出码 $runCode，日志尾部："
    Get-Content $allLog -Tail 30
    exit $runCode
}

# ---- 汇总 ----------------------------------------------------------------
Write-Host "`n== 汇总 =="
$passCnt = 0
foreach ($tb in $tbNames) {
    $log = Join-Path $outDir "$tb.log"
    if (-not (Test-Path $log)) { Write-Host ("  {0,-18} NO-LOG" -f $tb); continue }
    $lines = Get-Content $log
    $ok = ($lines -match 'ALL PASS').Count -gt 0
    $bad = ($lines -match 'FAIL').Count -gt 0
    if ($ok -and -not $bad) { Write-Host ("  {0,-18} PASS" -f $tb); $passCnt++ }
    else                    { Write-Host ("  {0,-18} FAIL  <- 见 out\{1}.log" -f $tb, $tb) }
}
Write-Host ""
Write-Host "PASS $passCnt / $($tbNames.Count)（日志目录：$outDir）"
if ($passCnt -ne $tbNames.Count) { exit 1 }
exit 0
