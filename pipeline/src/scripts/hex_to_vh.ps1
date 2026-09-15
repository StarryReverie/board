<#
=============================================================================
 hex_to_vh.ps1 — 把程序 .hex 转成 imem 综合固化用的 imem_init.vh（实验一上板）
   文档：pipeline/doc/board_runbook.md §3
   为什么要两步：`.hex` 供仿真（TB 用 $readmemh 装载），`.vh` 供综合
     （imem.v 内 `ifdef IMEM_INIT_VH` 的 initial 逐字节字面量装载 = 上电自跑）。
     两者必须同源一致，本脚本负责转换 + 校验。
   用法：
     powershell -File pipeline/src/scripts/hex_to_vh.ps1 `
         -Hex pipeline/src/test/exp1_board_demo_rom.hex `
         -PadBytes 512
   默认输出：与 .hex 同目录的 <名字>_init.vh
     （例：pipeline/src/test/exp1_board_demo_rom.hex → exp1_board_demo_init.vh）
     与实验二既有约定一致（soc/test/console_init.vh）；该 .vh 是上板归档证据之一。
     注意：**不要**把产物放到 scripts/out/ 下——run_tb.ps1 / run_perf.ps1 每次都会
     清空重建 out/，放那里会在下一次跑回归时被删掉（随后综合报
     "cannot open include file imem_init.vh"）。工程侧由 create_exp1_board_proj.tcl
     把本产物复制为 imem_init.vh 放进工程自己的构建目录。
   校验：
     ① .hex 字节能被 4 整除（指令对齐）；
     ② 固件长度 ≤ -PadBytes，否则报错退出（防越界/截断）；
     ③ 生成后回读 .vh，逐字节与 .hex 比对（保证转换无损）。
=============================================================================
#>
param(
    [Parameter(Mandatory=$true)][string]$Hex,
    [int]$PadBytes = 512,          # 补零字节数（须 ≥ 固件长度且 4 字节对齐）
    [string]$Out = ''              # 默认: 与 .hex 同目录的 <名字>_init.vh
)

$ErrorActionPreference = 'Stop'

$hexPath = (Resolve-Path -LiteralPath $Hex).Path
if (-not $Out) {
    $hexDir  = Split-Path -Parent $hexPath
    $hexBase = [IO.Path]::GetFileNameWithoutExtension($hexPath)     # 例 exp1_board_demo_rom
    $stem    = $hexBase -replace '_rom$', ''                        # 例 exp1_board_demo
    $Out     = Join-Path $hexDir ($stem + '_init.vh')
}
$Out = [IO.Path]::GetFullPath($Out)
$outDir = Split-Path -Parent $Out
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

# ---- 解析 verilog hex（`@ADDR` 基址 + 每行若干十六进制字节）----
$bytes = New-Object System.Collections.Generic.List[byte]
$base  = 0
foreach ($line in Get-Content -LiteralPath $hexPath) {
    $t = $line.Trim()
    if ($t -eq '') { continue }
    if ($t.StartsWith('@')) {
        $base = [Convert]::ToInt32($t.Substring(1), 16)
        # 非 0 基址（多段镜像）不做支持：实验一固化为"从 0 开始的单段镜像"
        if ($base -ne 0) { Write-Error "不支持的基址 @$($t.Substring(1))（仅支持单段、基址 0）"; exit 1 }
        continue
    }
    if ($t.StartsWith('#')) { continue }
    foreach ($tok in ($t -split '\s+')) {
        if ($tok -eq '') { continue }
        $bytes.Add([Convert]::ToByte($tok, 16))
    }
}

# ---- 校验①：字对齐 ----
if ($bytes.Count -eq 0) { Write-Error "空的镜像：$hexPath"; exit 1 }
if (($bytes.Count % 4) -ne 0) { Write-Error "镜像字节数 $($bytes.Count) 不是 4 的倍数（指令未对齐）"; exit 1 }
$instrCnt = $bytes.Count / 4

# ---- 校验②：容量 ----
if (($PadBytes % 4) -ne 0) { Write-Error "-PadBytes 必须 4 字节对齐（当前 $PadBytes）"; exit 1 }
if ($bytes.Count -gt $PadBytes) {
    Write-Error "固件 $($bytes.Count) B 超过 -PadBytes=$PadBytes（下板 IMEM_BYTES），请缩小程序或增大容量口径"
    exit 1
}

# ---- 生成 imem_init.vh ----
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('// 本文件由 pipeline/src/scripts/hex_to_vh.ps1 生成，请勿手工编辑')
[void]$sb.AppendLine(('// 源镜像: {0}' -f (Split-Path -Leaf $hexPath)))
[void]$sb.AppendLine(('// 指令数: {0}  固件: {1} B  补零到: {2} B' -f $instrCnt, $bytes.Count, $PadBytes))
for ($i = 0; $i -lt $PadBytes; $i++) {
    $v = if ($i -lt $bytes.Count) { $bytes[$i] } else { 0 }
    [void]$sb.AppendLine(("mem[{0}] = 8'h{1:X2};" -f $i, $v))
}
[IO.File]::WriteAllText($Out, $sb.ToString(), (New-Object Text.UTF8Encoding($false)))

# ---- 校验③：回读 .vh 与 .hex 逐字节比对 ----
$mem = @{}
foreach ($line in Get-Content -LiteralPath $Out) {
    if ($line -match "^mem\[(\d+)\] = 8'h([0-9A-Fa-f]{2});") {
        $mem[[int]$Matches[1]] = [Convert]::ToByte($Matches[2], 16)
    }
}
if ($mem.Count -ne $PadBytes) { Write-Error "回读条目数 $($mem.Count) != $PadBytes"; exit 1 }
for ($i = 0; $i -lt $bytes.Count; $i++) {
    if ($mem[$i] -ne $bytes[$i]) {
        Write-Error ("回读不一致 @{0}: vh={1:X2} hex={2:X2}" -f $i, $mem[$i], $bytes[$i]); exit 1
    }
}
for ($i = $bytes.Count; $i -lt $PadBytes; $i++) {
    if ($mem[$i] -ne 0) { Write-Error ("补零区非零 @{0}" -f $i); exit 1 }
}

Write-Host ("[OK] hex_to_vh: {0} -> {1}" -f (Split-Path -Leaf $hexPath), $Out)
Write-Host ("     指令 {0} 条 / 固件 {1} B / 补零到 {2} B；回读逐字节一致" -f $instrCnt, $bytes.Count, $PadBytes)
Write-Host 'hex_to_vh done'
