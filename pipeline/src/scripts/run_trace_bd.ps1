#=============================================================================
# run_trace_bd.ps1 — 逐拍 trace 上板验收程序（演示数字 / 报告证据来源）
#   用途：跑 test/trace/tb_boarddemo_trace.v，逐拍记录"程序真实触发过哪些机制"，
#         并汇总成报告/视频口播可直接引用的数字：
#           动态指令数、EX/MEM 与 MEM/WB 前递命中拍数、同拍两路并用、load-use 停顿、
#           taken 分支、访存次数、各 LED 的首次触发拍号
#   用法：powershell -File pipeline/src/scripts/run_trace_bd.ps1
#         （可选 -HaltPc 0x1e8 覆盖停机地址；默认按固件 .hex 长度自动推算）
#   产物：<repo>/build/exp1_trace/trace_bd.txt（逐拍 TRC 行 + 汇总）——build/ 不入库
#   说明：本脚本不在回归集合内（run_tb.ps1 只收 test 根目录 tb_*.v），按需手动运行。
#=============================================================================
param([string]$HaltPc = '')

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))   # pipeline/src/scripts -> repo
$viv  = if ($env:XVIVADO_ROOT) { $env:XVIVADO_ROOT } else { 'C:\Xilinx\Vivado\2019.2' }
$wDir = Join-Path $root 'build\exp1_trace'
if (Test-Path $wDir) { Remove-Item $wDir -Recurse -Force }
New-Item -ItemType Directory -Path $wDir -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $root 'build\tmp') -Force | Out-Null

# ---- 停机地址：默认 = 固件最后一条指令（本程序把 halt 放在末尾，见 exp1_board_demo.asm）----
$hexFile = Join-Path $root 'pipeline\src\test\exp1_board_demo_rom.hex'
if (-not $HaltPc) {
    $bytes = 0
    foreach ($l in (Get-Content $hexFile)) {
        if ($l -match '^@') { continue }
        $bytes += @($l -split '\s+' | Where-Object { $_ -match '^[0-9A-Fa-f]{2}$' }).Count
    }
    $HaltPc = '0x{0:x}' -f (($bytes / 4 - 1) * 4)
}
Write-Host ("[info] 固件 {0} 字节，停机地址取 {1}" -f (Get-Item $hexFile).Length, $HaltPc)

# ---- 编译 + 运行 ----
Copy-Item $hexFile $wDir -Force
$rtl = @(Get-ChildItem (Join-Path $root 'pipeline\src\rtl') -Filter '*.v' -File | ForEach-Object { $_.FullName })
$tb  = Join-Path $root 'pipeline\src\test\trace\tb_boarddemo_trace.v'
$srcList = ((@($rtl | ForEach-Object { '"' + $_ + '"' }) + ('"' + $tb + '"')) -join ' ')
$bat = @(
    '@echo off',
    ('call "' + $viv + '\settings64.bat" >nul 2>&1'),
    ('set TEMP=' + $root + '\build\tmp'),
    ('set TMP=' + $root + '\build\tmp'),
    ('cd /d "' + $wDir + '"'),
    ('call xvlog -i "' + $root + '\pipeline\src" ' + $srcList),
    'if errorlevel 1 ( echo [XVLOG_FAIL] & exit /b 2 )',
    'call xelab tb_boarddemo_trace -s tb_boarddemo_trace',
    'if errorlevel 1 ( echo [XELAB_FAIL] & exit /b 3 )',
    'call xsim tb_boarddemo_trace -runall',
    'if errorlevel 1 ( echo [XSIM_FAIL] & exit /b 4 )',
    'exit /b 0'
)
$batFile = Join-Path $wDir 'run_trace.bat'
Set-Content -Path $batFile -Value $bat -Encoding ASCII

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = 'cmd.exe'; $psi.Arguments = '/c "' + $batFile + '"'
$psi.WorkingDirectory = $wDir; $psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
# 并发排空 stdout/stderr（只读一路会在另一路写满时死锁）
$proc = [System.Diagnostics.Process]::Start($psi)
$soTask = $proc.StandardOutput.ReadToEndAsync()
$seTask = $proc.StandardError.ReadToEndAsync()
$proc.WaitForExit()
$out = $soTask.GetAwaiter().GetResult()
$err = $seTask.GetAwaiter().GetResult()
($out + "`r`n[stderr]`r`n" + $err) | Set-Content -Path (Join-Path $wDir 'trace_bd.txt') -Encoding ASCII

# ---- 汇总 ----
$rows = @()
foreach ($l in ($out -split "`r?`n")) {
    if ($l -match '^TRC: e=(\d+) pc=(\w+) fa=(\d) fb=(\d) stall=(\d) br=(\d) mw=(\d) mr=(\d) rw=(\d)') {
        $rows += [pscustomobject]@{
            e = [int]$Matches[1]; pc = $Matches[2]
            fa = [int]$Matches[3]; fb = [int]$Matches[4]; stall = [int]$Matches[5]
            br = [int]$Matches[6]; mw = [int]$Matches[7]; mr = [int]$Matches[8]; rw = [int]$Matches[9]
        }
    }
}
if ($rows.Count -eq 0) { Write-Host ("[ERR] 没有 TRC 行（仿真退出码 {0}），请查看 trace_bd.txt" -f $proc.ExitCode); exit 1 }

# 停机拍：trace 打印的是 %02h（小写、零填充），这里按数值比较，
# 免得 -HaltPc 0xA 这类输入比不过 0a；比不到就直接报错，不能退化成"整段都算程序本体"。
$haltVal   = [Convert]::ToInt64(($HaltPc -replace '^0x', ''), 16)
$firstHalt = ($rows | Where-Object { [Convert]::ToInt64($_.pc, 16) -eq $haltVal } | Select-Object -First 1).e
if ($null -eq $firstHalt) {
    Write-Host ("[ERR] trace 里没有 pc={0} 的拍，无法界定程序本体窗口，请检查 -HaltPc（固件停机地址）" -f $HaltPc)
    exit 1
}
$body = $rows | Where-Object { $_.e -le $firstHalt }

# 机制计数（依据见 board_runbook §5.1/§6.2）：
#   程序本体窗口内 taken 分支数 = 程序自身 taken（不含停机自环那一次）；
#   每次 taken 分支注入 **1 个可见伪 NOP 槽** + 另有 1 个纯气泡（控制字被清零故不出现），
#   即每支 taken 消耗 2 拍 → 冲刷拍数 = taken × 2。
#   动态指令 = EX 槽位 − 伪 NOP 槽；循环重复条数 = 动态 − 静态。
$slots     = $body.Count
$pcCount   = ($body | Group-Object pc).Count
$stallCyc  = @($body | Where-Object { $_.stall -eq 1 }).Count
$brTotal   = @($body | Where-Object { $_.br -eq 1 }).Count
$takenProg = $brTotal - 1                       # 去掉停机自环那一次
$dynInstr  = $slots - $takenProg                # 扣掉冲刷伪 NOP 槽
$flushCyc  = $takenProg * 2
$identSum  = $dynInstr + $stallCyc + $flushCyc

Write-Host ''
Write-Host '== 逐拍 trace 汇总（程序本体窗口）=='
Write-Host ("  停机指令({0}) 首次进 EX 的拍号 : {1}" -f $HaltPc, $firstHalt)
Write-Host ("  静态指令（不同 PC 数）         : {0}" -f $pcCount)
Write-Host ("  动态指令                       : {0}（EX 槽位 {1} − 冲刷伪 NOP {2}；其中循环多执行 {3} 条）" -f $dynInstr, $slots, $takenProg, ($dynInstr - $pcCount))
Write-Host ("  拍数恒等式                     : 动态 {0} + 停顿 {1} + 冲刷 {2}×2 = {3}  ⇒ 停机拍号 {4}" -f $dynInstr, $stallCyc, $takenProg, $identSum, $firstHalt)
Write-Host ("  EX/MEM 前递命中拍              : {0}" -f @($body | Where-Object { $_.fa -eq 1 -or $_.fb -eq 1 }).Count)
Write-Host ("  MEM/WB 前递命中拍              : {0}" -f @($body | Where-Object { $_.fa -eq 2 -or $_.fb -eq 2 }).Count)
Write-Host ("  同拍两路并用                   : {0}" -f @($body | Where-Object { $_.fa -gt 0 -and $_.fb -gt 0 }).Count)
Write-Host ("  load-use 停顿                  : {0}" -f $stallCyc)
Write-Host ("  taken 分支（含停机自环）       : {0}" -f $brTotal)
Write-Host ("  访存 store / load              : {0} / {1}" -f @($body | Where-Object { $_.mw -eq 1 }).Count, @($body | Where-Object { $_.mr -eq 1 }).Count)
$firstStore = ($body | Where-Object { $_.mw -eq 1 } | Select-Object -First 1).e
$firstStall = ($body | Where-Object { $_.stall -eq 1 } | Select-Object -First 1).e
$firstBr    = ($body | Where-Object { $_.br -eq 1 } | Select-Object -First 1).e
Write-Host ("  LED 首次触发拍（store/stall/br）: {0} / {1} / {2}" -f $firstStore, $firstStall, $firstBr)
Write-Host ''
Write-Host ("  日志: {0}" -f (Join-Path $wDir 'trace_bd.txt'))
