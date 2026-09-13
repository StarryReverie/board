<#
=============================================================================
  report_png.ps1 — 生成 §7 报告素材（回归汇总 + 性能表）
    * 回归汇总：读 out/w*/tb_*.log 统计实际断言数 → PNG + MD
    * 性能表  ：读 out/perf_summary.csv → PNG + MD
    * 输出：pipeline/doc/sim_shots/{reg_summary,perf_table}_<日期>.png/.md
    * 用法：powershell -File pipeline/src/scripts/report_png.ps1
=============================================================================
#>
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$scripts  = $PSScriptRoot
$src      = Split-Path -Parent $scripts
$pipeline = Split-Path -Parent $src
$outRoot  = Join-Path $scripts 'out'
$outDir   = Join-Path $pipeline 'doc\sim_shots\auto'
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$date  = Get-Date -Format 'yyyyMMdd'
$stamp = Get-Date -Format 'yyyy-MM-dd HH:mm'

# ---------------------------------------------------------------- 表绘制
function New-Table {
    param([string]$Title, [string]$Sub, [string[]]$Cols, [int[]]$Widths,
          $Rows, [string]$Foot)
    $rowH = 26; $pad = 14; $hdrH = 74
    $tw = [int](($Widths | Measure-Object -Sum).Sum)
    $w = [int]($tw + 2 * $pad)
    $h = [int]($hdrH + $rowH * $Rows.Count + 46)
    $bmp = New-Object System.Drawing.Bitmap($w, $h)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
    $g.Clear([System.Drawing.Color]::White)

    $fT = New-Object System.Drawing.Font('Microsoft YaHei',14,[System.Drawing.FontStyle]::Bold)
    $fS = New-Object System.Drawing.Font('Microsoft YaHei',9)
    $fH = New-Object System.Drawing.Font('Microsoft YaHei',10,[System.Drawing.FontStyle]::Bold)
    $fC = New-Object System.Drawing.Font('Consolas',9.5)
    $fB = New-Object System.Drawing.Font('Microsoft YaHei',9.5)
    $brL = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(25,25,25))
    $brW = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $brN = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(90,90,90))
    $penG = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(200,200,200),1)
    $brHdr = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(226,234,248))
    $brSec = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(244,244,244))
    $brPass= New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(20,130,20))
    $sfC = New-Object System.Drawing.StringFormat
    $sfC.Alignment = [System.Drawing.StringAlignment]::Center
    $sfC.LineAlignment = [System.Drawing.StringAlignment]::Center
    $sfL = New-Object System.Drawing.StringFormat
    $sfL.Alignment = [System.Drawing.StringAlignment]::Near
    $sfL.LineAlignment = [System.Drawing.StringAlignment]::Center

    $g.DrawString($Title, $fT, $brL, [float]$pad, [float]6)
    $g.DrawString($Sub,   $fS, $brN, [float]$pad, [float]36)

    $y = $hdrH
    # header
    $x = $pad
    for ($c = 0; $c -lt $Cols.Count; $c++) {
        $rect = New-Object System.Drawing.RectangleF([float]$x,[float]$y,[float]$Widths[$c],[float]$rowH)
        $g.FillRectangle($brHdr, $rect)
        $g.DrawRectangle($penG, $x, $y, $Widths[$c], $rowH)
        $g.DrawString($Cols[$c], $fH, $brL, $rect, $sfC)
        $x += $Widths[$c]
    }
    $y += $rowH
    foreach ($r in $Rows) {
        if ($r.ContainsKey('sec')) {
            $rect = New-Object System.Drawing.RectangleF([float]$pad,[float]$y,[float]$tw,[float]$rowH)
            $g.FillRectangle($brSec, $rect)
            $g.DrawRectangle($penG, $pad, $y, $tw, $rowH)
            $g.DrawString($r.sec, $fH, $brL, [float]($pad+8), [float]($y+$rowH/2-9), $sfL)
        } else {
            $x = $pad
            $vals = $r.v
            for ($c = 0; $c -lt $Cols.Count; $c++) {
                $rect = New-Object System.Drawing.RectangleF([float]$x,[float]$y,[float]$Widths[$c],[float]$rowH)
                $g.DrawRectangle($penG, $x, $y, $Widths[$c], $rowH)
                $font = if ($c -eq 1) { $fC } else { $fB }
                $brush = if ($vals[$c] -eq 'PASS' -or $vals[$c] -eq 'ALL PASS') { $brPass } else { $brL }
                $al = if ($c -eq 1) { $sfL } else { $sfC }
                $g.DrawString([string]$vals[$c], $font, $brush, $rect, $al)
                $x += $Widths[$c]
            }
        }
        $y += $rowH
    }
    $g.DrawString($Foot, $fS, $brN, [float]$pad, [float]($y + 8))
    $g.Dispose()
    return $bmp
}

function Save-Both($bmp, [string]$name, [string[]]$md) {
    $png = Join-Path $outDir ("$name`_$date.png")
    $bmp.Save($png, [System.Drawing.Imaging.ImageFormat]::Png)
    Set-Content -LiteralPath (Join-Path $outDir ("$name`_$date.md")) -Value $md -Encoding UTF8
    Write-Host "  -> $png"
}

# ================= 回归汇总 =================
$groups = @(
    @{ title='模块单测（14）'; names=@('tb_pc_reg','tb_imem','tb_if_id','tb_decode','tb_regfile','tb_id_ex','tb_alu','tb_execute','tb_ex_mem','tb_dmem','tb_mem_wb','tb_wb','tb_hazard_unit','tb_pipeline_top') },
    @{ title='程序级（6）';   names=@('tb_prog_test0','tb_prog_test1','tb_prog_sort','tb_prog_cover','tb_prog_hazard','tb_prog_demo') },
    @{ title='性能（1）';     names=@('tb_perf') }
)
$logMap = @{}
foreach ($l in Get-ChildItem (Join-Path $outRoot 'w*\tb_*.log')) {
    $lines = Get-Content -LiteralPath $l.FullName
    $cnt = @($lines | Where-Object { $_ -match '^PASS:' }).Count
    $ok  = (@($lines | Where-Object { $_ -match 'ALL PASS' }).Count -gt 0) -and
           (@($lines | Where-Object { $_ -match 'FAIL' }).Count -eq 0)
    $logMap[$l.BaseName] = @{ count = $cnt; ok = $ok }
}
$rows = New-Object System.Collections.ArrayList
$idx = 0; $sum = 0; $regOk = $true
$md = @('# §7 回归测试汇总（21/21）','',
        '命令：`powershell -File pipeline/src/scripts/run_tb.ps1`　日期：' + $date + '　（每例 PASS/FAIL 见 `out/w*/tb_*.log`）','',
        '| 层级 | # | 用例 | 断言数 | 结果 |','|---|---|---|---|---|')
foreach ($grp in $groups) {
    [void]$rows.Add(@{ sec = $grp.title })
    $md += ('| **{0}** | | | | |' -f $grp.title)
    foreach ($nm in $grp.names) {
        $idx++
        $e = $logMap[$nm]
        $a = if ($e) { $e.count } else { 0 }
        $ok = if ($e) { $e.ok } else { $false }
        if (-not $ok) { $regOk = $false }
        $res = if (-not $e) { 'MISSING' } elseif ($ok) { 'PASS' } else { 'FAIL' }
        if ($nm -eq 'tb_perf') { $aTxt = "$a（单档）/ 74（5 档）" } else { $aTxt = "$a" }
        $sum += $a
        [void]$rows.Add(@{ v = @("$idx", $nm, "$aTxt", $res) })
        $md += ('| {0} | {1} | {2} | {3} | {4} |' -f $grp.title, $idx, $nm, $aTxt, $res)
    }
}
$perfCnt = if ($logMap['tb_perf']) { $logMap['tb_perf'].count } else { 0 }
$foot = "本次 21 项运行断言数 $sum（其中 tb_perf 单档 $perfCnt；性能 5 档合计 74，按 5 档计则 $($sum - $perfCnt + 74)）　$stamp"
$md += '', ('**本次 21 项运行断言数 {0}**（其中 `tb_perf` 单档 {1}；性能 5 档合计 74，按 5 档计则 {2}）' -f $sum, $perfCnt, ($sum - $perfCnt + 74))
$cols = @('#','用例','断言数','结果'); $wid = @(46,220,170,90)
if ($regOk) {
    $bmp = New-Table -Title '§7 回归测试汇总（21/21 PASS）' -Sub ("命令: powershell -File pipeline/src/scripts/run_tb.ps1　｜　$stamp") `
        -Cols $cols -Widths $wid -Rows $rows -Foot $foot
    Save-Both $bmp 'reg_summary' $md
} else {
    Write-Host '[FAIL] 回归日志缺失或未全 PASS，未生成汇总表'
}

# ================= 性能表 =================
$perf = Import-Csv (Join-Path $outRoot 'perf_summary.csv')
$static = @{ test0=10; test1=21; sort=36; cover=36; hazard=17 }
$rows2 = New-Object System.Collections.ArrayList
$md2 = @('# §7 性能测试（5 档 + 恒等式 C == IC + (F−1) + L + 2T）','',
         '命令：`powershell -File pipeline/src/scripts/run_perf.ps1`　日期：' + $date + '　时钟：100 MHz 名义（Tclk=10 ns）','',
         '| 程序 | 静态字数 | IC | C(拍) | L | T | CPI | IPC | CPU time(ns) | MIPS | 恒等式 |','|---|---|---|---|---|---|---|---|---|---|---|')
$expected = @('test0','test1','sort','cover','hazard')
$allOk = $true
foreach ($e in $expected) {
    if (-not ($perf | Where-Object { $_.prog -eq $e })) { $allOk = $false; Write-Host "[FAIL] 性能表缺少档: $e" }
}
foreach ($p in $perf) {
    $cpu = [int]$p.c * 10
    $mips = [math]::Round([double]$p.ipc * 100, 1)
    $ident = if ($p.ident -eq '1') { 'PASS' } else { 'FAIL' }
    if ($p.ident -ne '1' -or $p.allpass -ne 'True') { $allOk = $false }
    [void]$rows2.Add(@{ v = @($p.prog, $static[$p.prog], $p.ic, $p.c, $p.l, $p.t, $p.cpi, $p.ipc, $cpu, $mips, $ident) })
    $md2 += ('| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} | {9} | {10} |' -f
             $p.prog, $static[$p.prog], $p.ic, $p.c, $p.l, $p.t, $p.cpi, $p.ipc, $cpu, $mips, $ident)
}
$foot2 = "恒等式 5/5 PASS　｜　正确性门禁（同源 tb_prog_* 终值断言）全绿　｜　$stamp"
$md2 += '', '恒等式 **5/5 PASS**；每档内嵌正确性断言全绿（防“为快而错”）。'
$cols2 = @('程序','静态字数','IC','C(拍)','L','T','CPI','IPC','CPU time(ns)','MIPS','恒等式')
$wid2  = @(80,90,60,66,46,46,66,66,120,66,90)
if ($allOk) {
    $bmp2 = New-Table -Title '§7 性能测试（5 档 + 恒等式）' -Sub ("命令: powershell -File pipeline/src/scripts/run_perf.ps1　｜　100 MHz 名义　｜　$stamp") `
        -Cols $cols2 -Widths $wid2 -Rows $rows2 -Foot $foot2
    Save-Both $bmp2 'perf_table' $md2
} else {
    Write-Host '[FAIL] 性能数据缺失或未全 PASS，未生成汇总表'
}

Write-Host ''
Write-Host ("报告素材输出目录: $outDir")
if (-not $allOk) { exit 1 }
