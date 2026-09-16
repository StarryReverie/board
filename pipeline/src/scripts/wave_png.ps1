<#
=============================================================================
  wave_png.ps1 — 由 wave_pipe 采样 CSV 渲染四项波形 PNG（System.Drawing）
    * 输入 : scripts/out/wave/wave_{cover,hazard,priority}.csv + wave_marks.csv
    * 输出 : pipeline/doc/sim_shots/exp1/auto/{1..4}_*_<日期>.png（+ 同名 .log）
    * 说明 : xsim 2019.2 $dumpvars 只写初值，故波形由 TB 逐拍采样、离线绘制。
    * 用法 : powershell -File pipeline/src/scripts/wave_png.ps1
=============================================================================
#>
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$scripts  = $PSScriptRoot
$src      = Split-Path -Parent $scripts                      # pipeline/src
$pipeline = Split-Path -Parent $src                          # pipeline
$waveDir  = Join-Path $scripts 'out\wave'
$outDir   = Join-Path $pipeline 'doc\sim_shots\exp1\auto'
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$date    = Get-Date -Format 'yyyyMMdd'
$stamp   = Get-Date -Format 'yyyy-MM-dd HH:mm'

# ---------------------------------------------------------------- 位运算辅助
function Shr([long]$v,[int]$n){ [long]([math]::Floor([double]($v % 4294967296) / [math]::Pow(2,$n))) }
function Shl([long]$v,[int]$n){ [long](($v * [math]::Pow(2,$n)) % 4294967296) }
function Sx([long]$v,[int]$bits){ if ($v -ge [long][math]::Pow(2,$bits-1)) { $v - [long][math]::Pow(2,$bits) } else { $v } }

# ---------------------------------------------------------------- 指令反汇编
function Decode-Inst {
    param([long]$w)
    if ($w -eq 0) { return 'bubble' }
    $w = $w % 4294967296
    if ($w -eq 0x13) { return 'nop' }
    $op  = $w -band 0x7F
    $rd  = (Shr $w 7)  -band 0x1F
    $f3  = (Shr $w 12) -band 0x7
    $rs1 = (Shr $w 15) -band 0x1F
    $rs2 = (Shr $w 20) -band 0x1F
    $f7  = (Shr $w 25) -band 0x7F
    $sh  = (Shr $w 20) -band 0x1F
    switch ($op) {
        0x13 {
            $imm = Sx ((Shr $w 20) -band 0xFFF) 12
            switch ($f3) {
                0 { return ('addi x{0},x{1},{2}' -f $rd,$rs1,$imm) }
                2 { return ('slti x{0},x{1},{2}' -f $rd,$rs1,$imm) }
                3 { return ('sltiu x{0},x{1},{2}' -f $rd,$rs1,$imm) }
                4 { return ('xori x{0},x{1},{2}' -f $rd,$rs1,$imm) }
                6 { return ('ori x{0},x{1},{2}' -f $rd,$rs1,$imm) }
                7 { return ('andi x{0},x{1},{2}' -f $rd,$rs1,$imm) }
                1 { return ('slli x{0},x{1},{2}' -f $rd,$rs1,$sh) }
                5 { if ($f7 -eq 0x20) { return ('srai x{0},x{1},{2}' -f $rd,$rs1,$sh) }
                    return ('srli x{0},x{1},{2}' -f $rd,$rs1,$sh) }
                default { return ('op-imm x{0}' -f $rd) }
            }
        }
        0x33 {
            switch ($f3) {
                0 { if ($f7 -eq 0x20) { return ('sub x{0},x{1},x{2}' -f $rd,$rs1,$rs2) } return ('add x{0},x{1},x{2}' -f $rd,$rs1,$rs2) }
                1 { return ('sll x{0},x{1},x{2}' -f $rd,$rs1,$rs2) }
                2 { return ('slt x{0},x{1},x{2}' -f $rd,$rs1,$rs2) }
                3 { return ('sltu x{0},x{1},x{2}' -f $rd,$rs1,$rs2) }
                4 { return ('xor x{0},x{1},x{2}' -f $rd,$rs1,$rs2) }
                5 { if ($f7 -eq 0x20) { return ('sra x{0},x{1},x{2}' -f $rd,$rs1,$rs2) } return ('srl x{0},x{1},x{2}' -f $rd,$rs1,$rs2) }
                6 { return ('or x{0},x{1},x{2}' -f $rd,$rs1,$rs2) }
                7 { return ('and x{0},x{1},x{2}' -f $rd,$rs1,$rs2) }
            }
        }
        0x03 { $imm = Sx ((Shr $w 20) -band 0xFFF) 12; return ('lw x{0},{1}(x{2})' -f $rd,$imm,$rs1) }
        0x23 {
            $imm = Sx ((((Shr $w 25) -band 0x7F) * 32 + ((Shr $w 7) -band 0x1F)) % 4096) 12
            return ('sw x{0},{1}(x{2})' -f $rs2,$imm,$rs1)
        }
        0x63 {
            $b = (Shl ((Shr $w 31) -band 1) 12) -bor (Shl ((Shr $w 7) -band 1) 11) -bor
                 (Shl ((Shr $w 25) -band 0x3F) 5) -bor (Shl ((Shr $w 8) -band 0xF) 1)
            $b = Sx $b 13
            $mn = if ($f3 -eq 0) { 'beq' } else { 'bne' }
            return ('{0} x{1},x{2},{3}' -f $mn,$rs1,$rs2,$b)
        }
        0x6F {
            $j = (Shl ((Shr $w 31) -band 1) 20) -bor (Shl ((Shr $w 21) -band 0x3FF) 1) -bor
                 (Shl ((Shr $w 20) -band 1) 11) -bor (Shl ((Shr $w 12) -band 0xFF) 12)
            $j = Sx $j 21
            return ('jal x{0},{1}' -f $rd,$j)
        }
        0x67 { $imm = Sx ((Shr $w 20) -band 0xFFF) 12; return ('jalr x{0},{1}(x{2})' -f $rd,$imm,$rs1) }
        0x37 { return ('lui x{0},0x{1:X}' -f $rd,((Shr $w 12) -band 0xFFFFF)) }
    }
    return ('0x{0:X8}' -f $w)
}

# ---------------------------------------------------------------- CSV / marks
function Import-WaveCsv([string]$path) {
    $lines = Get-Content -LiteralPath $path
    $hdr = $lines[0] -split ','
    $rows = New-Object System.Collections.ArrayList
    for ($i = 1; $i -lt $lines.Count; $i++) {
        $f = $lines[$i] -split ','
        if ($f.Count -ne $hdr.Count) { continue }
        $h = @{}
        for ($c = 0; $c -lt $hdr.Count; $c++) { $h[$hdr[$c]] = $f[$c] }
        [void]$rows.Add($h)
    }
    return ,$rows
}

$marks = @{}
foreach ($l in (Get-Content -LiteralPath (Join-Path $waveDir 'wave_marks.csv') | Select-Object -Skip 1)) {
    $p = $l -split ','
    if ($p.Count -ge 3) { $marks[$p[0]] = [int]$p[2] }
}

# ---------------------------------------------------------------- 绘图
$cBg      = [System.Drawing.Color]::White
$cGrid    = [System.Drawing.Color]::FromArgb(226,226,226)
$cLabel   = [System.Drawing.Color]::FromArgb(30,30,30)
$cBitHi   = [System.Drawing.Color]::FromArgb(206,238,206)
$cBitLine = [System.Drawing.Color]::FromArgb(40,130,40)
$cBusFill = [System.Drawing.Color]::FromArgb(220,232,250)
$cBusLine = [System.Drawing.Color]::FromArgb(70,100,180)
$cHi      = [System.Drawing.Color]::FromArgb(255,246,196)
$cCursor  = [System.Drawing.Color]::FromArgb(220,30,30)
$cNote    = [System.Drawing.Color]::FromArgb(90,90,90)

$fTitle  = New-Object System.Drawing.Font('Microsoft YaHei',14,[System.Drawing.FontStyle]::Bold)
$fSub    = New-Object System.Drawing.Font('Microsoft YaHei',9)
$fSig    = New-Object System.Drawing.Font('Microsoft YaHei',10)
$fVal    = New-Object System.Drawing.Font('Consolas',9)
$fAxis   = New-Object System.Drawing.Font('Consolas',8)
$fNote   = New-Object System.Drawing.Font('Microsoft YaHei',9)
$sfC     = New-Object System.Drawing.StringFormat
$sfC.Alignment = [System.Drawing.StringAlignment]::Center
$sfC.LineAlignment = [System.Drawing.StringAlignment]::Center
$sfL     = New-Object System.Drawing.StringFormat
$sfL.Alignment = [System.Drawing.StringAlignment]::Near
$sfL.LineAlignment = [System.Drawing.StringAlignment]::Center

function Get-Cell($row, [string]$col) { if ($row.ContainsKey($col)) { return $row[$col] } return '0' }

function Format-Cell([string]$fmt, [string]$raw) {
    if ($raw -eq 'x' -or $raw -eq 'X') { return 'x' }
    if ($raw -eq 'z' -or $raw -eq 'Z') { return 'z' }
    $n = [long]$raw
    switch ($fmt) {
        'inst' { return (Decode-Inst $n) }
        'pc'   { return ('0x{0:X}' -f $n) }
        'hex'  { return ('0x{0:X8}' -f $n) }
        'dec'  { return ('{0}' -f $n) }
        'fwd'  { if ($n -eq 1) { return '01 EX/MEM' } elseif ($n -eq 2) { return '10 MEM/WB' } else { return '00 reg' } }
        default { return ('{0}' -f $n) }
    }
}

function New-Panel {
    param($Data, [int]$Start, [int]$End, [string]$Title, [string]$Sub, $Rows,
          [int]$Cursor, [string]$CursorLabel, $HiCycles, [string[]]$Notes)
    $nCyc  = $End - $Start + 1
    $gutter = 250; $cycleW = 118; $rowH = 42; $hdr = 88; $pad = 10
    $noteH = 6 + 20 * ($Notes.Count)
    $w = $gutter + $nCyc * $cycleW + 2 * $pad
    $h = $hdr + $Rows.Count * $rowH + $noteH + 12
    $bmp = New-Object System.Drawing.Bitmap($w, $h)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
    $g.Clear($cBg)

    $g.DrawString($Title, $fTitle, (New-Object System.Drawing.SolidBrush($cLabel)), [float]$pad, [float]6)
    $g.DrawString($Sub,   $fSub,   (New-Object System.Drawing.SolidBrush($cNote)),  [float]$pad, [float]34)
    $g.DrawString("时间标尺: 1 格 = 1 时钟周期 = 10 ns", $fSub, (New-Object System.Drawing.SolidBrush($cNote)), [float]($w - 250), [float]34)

    $x0 = $gutter
    $y0 = $hdr
    # 周期高亮列
    foreach ($hc in $HiCycles) {
        if ($hc -ge $Start -and $hc -le $End) {
            $xx = $x0 + ($hc - $Start) * $cycleW
            $g.FillRectangle((New-Object System.Drawing.SolidBrush($cHi)), $xx, $y0, $cycleW, ($Rows.Count * $rowH))
        }
    }
    # 网格 + 周期号
    for ($c = 0; $c -le $nCyc; $c++) {
        $xx = $x0 + $c * $cycleW
        $g.DrawLine((New-Object System.Drawing.Pen($cGrid,1)), $xx, $y0, $xx, ($y0 + $Rows.Count * $rowH))
        if ($c -lt $nCyc) {
            $cyc = $Start + $c
            $g.DrawString("$cyc", $fAxis, (New-Object System.Drawing.SolidBrush($cNote)), [float]$xx, [float]($y0 - 16))
        }
    }
    # 行
    for ($r = 0; $r -lt $Rows.Count; $r++) {
        $spec = $Rows[$r]
        $ry = $y0 + $r * $rowH
        $g.DrawLine((New-Object System.Drawing.Pen($cGrid,1)), $x0, ($ry + $rowH), ($x0 + $nCyc * $cycleW), ($ry + $rowH))
        $g.DrawString($spec.name, $fSig, (New-Object System.Drawing.SolidBrush($cLabel)), [float]$pad, [float]($ry + $rowH / 2 - 9), $sfL)

        if ($spec.type -eq 'clk') {
            $yHi = $ry + $rowH * 0.30; $yLo = $ry + $rowH * 0.74
            for ($c = 0; $c -lt $nCyc; $c++) {
                $xa = $x0 + $c * $cycleW; $xb = $xa + $cycleW
                $g.DrawLine((New-Object System.Drawing.Pen($cBitLine,1.5)), $xa, $yHi, ($xa + $cycleW/2), $yHi)
                $g.DrawLine((New-Object System.Drawing.Pen($cBitLine,1.5)), ($xa + $cycleW/2), $yHi, ($xa + $cycleW/2), $yLo)
                $g.DrawLine((New-Object System.Drawing.Pen($cBitLine,1.5)), ($xa + $cycleW/2), $yLo, $xb, $yLo)
                $g.DrawLine((New-Object System.Drawing.Pen($cBitLine,1.5)), $xb, $yLo, $xb, $yHi)
            }
            continue
        }
        if ($spec.type -eq 'bit') {
            $yHi = $ry + $rowH * 0.30; $yLo = $ry + $rowH * 0.74
            $prev = $null
            for ($c = 0; $c -lt $nCyc; $c++) {
                $cyc = $Start + $c
                $row = $Data[$cyc - 1]
                $v = 0; $raw = Get-Cell $row $spec.col
                if ($raw -match '^\d+$') { if ([long]$raw -ne 0) { $v = 1 } }
                $xa = $x0 + $c * $cycleW; $xb = $xa + $cycleW
                $yy = if ($v -eq 1) { $yHi } else { $yLo }
                if ($v -eq 1) { $g.FillRectangle((New-Object System.Drawing.SolidBrush($cBitHi)), $xa, $yHi, $cycleW, ($yLo - $yHi)) }
                if ($null -ne $prev -and $prev -ne $v) {
                    $g.DrawLine((New-Object System.Drawing.Pen($cBitLine,1.6)), $xa, $yHi, $xa, $yLo)
                }
                $g.DrawLine((New-Object System.Drawing.Pen($cBitLine,1.6)), $xa, $yy, $xb, $yy)
                $prev = $v
            }
            continue
        }
        # bus
        $yt = $ry + $rowH * 0.16; $yb = $ry + $rowH * 0.84
        for ($c = 0; $c -lt $nCyc; $c++) {
            $cyc = $Start + $c
            $row = $Data[$cyc - 1]
            $txt = Format-Cell $spec.fmt (Get-Cell $row $spec.col)
            $xa = $x0 + $c * $cycleW + 1; $xb = $xa + $cycleW - 2
            $rect = New-Object System.Drawing.RectangleF([float]$xa, [float]$yt, [float]($xb - $xa), [float]($yb - $yt))
            $g.FillRectangle((New-Object System.Drawing.SolidBrush($cBusFill)), $rect)
            $g.DrawRectangle((New-Object System.Drawing.Pen($cBusLine,1)), $xa, $yt, ($xb - $xa), ($yb - $yt))
            $br = New-Object System.Drawing.SolidBrush($cLabel)
            $g.DrawString($txt, $fVal, $br, $rect, $sfC)
        }
    }
    # 游标
    if ($Cursor -ge $Start -and $Cursor -le $End) {
        $xx = $x0 + ($Cursor - $Start) * $cycleW + $cycleW / 2
        $pen = New-Object System.Drawing.Pen($cCursor,2)
        $pen.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash
        $g.DrawLine($pen, $xx, ($y0 - 20), $xx, ($y0 + $Rows.Count * $rowH + 4))
        if ($CursorLabel) {
            $g.DrawString($CursorLabel, $fAxis, (New-Object System.Drawing.SolidBrush($cCursor)), [float]($xx - 60), [float]($y0 - 34))
        }
    }
    # 注释
    $ny = $y0 + $Rows.Count * $rowH + 8
    foreach ($nt in $Notes) {
        $g.DrawString($nt, $fNote, (New-Object System.Drawing.SolidBrush($cNote)), [float]$pad, [float]$ny)
        $ny += 20
    }
    $g.Dispose()
    return $bmp
}

function Merge-Vertical($bmps, [int]$gap) {
    $w = [int](($bmps | ForEach-Object { $_.Width } | Measure-Object -Maximum).Maximum)
    $h = [int](($bmps | ForEach-Object { $_.Height } | Measure-Object -Sum).Sum) + $gap * ($bmps.Count - 1)
    $out = New-Object System.Drawing.Bitmap($w, $h)
    $g = [System.Drawing.Graphics]::FromImage($out)
    $g.Clear([System.Drawing.Color]::White)
    $y = 0
    foreach ($b in $bmps) { $g.DrawImage($b, 0, $y); $y += $b.Height + $gap }
    $g.Dispose()
    return $out
}

function Save-Item([System.Drawing.Bitmap]$bmp, [string]$name, [string[]]$logLines) {
    $png = Join-Path $outDir ("$name`_$date.png")
    $bmp.Save($png, [System.Drawing.Imaging.ImageFormat]::Png)
    $log = Join-Path $outDir ("$name`_$date.log")
    Set-Content -LiteralPath $log -Value $logLines -Encoding UTF8
    Write-Host "  -> $png"
}

$cmdLine = 'powershell -File pipeline/src/scripts/run_wave.ps1'
$tbLog = Get-Content -LiteralPath (Join-Path $waveDir 'wave_pipe.log')

# ================= 项 1：五级流水线运行总览 =================
$cov = Import-WaveCsv (Join-Path $waveDir 'wave_cover.csv')
$s1 = $marks['1']; $e1 = $s1 + 9
$rows1 = @(
    @{name='clk  100MHz'; type='clk'},
    @{name='pc';                col='pc';         type='bus'; fmt='pc'},
    @{name='IF  inst';          col='if_inst';    type='bus'; fmt='inst'},
    @{name='ID  inst';          col='id_inst';    type='bus'; fmt='inst'},
    @{name='EX  inst';          col='ex_inst';    type='bus'; fmt='inst'},
    @{name='MEM inst';          col='mem_inst';   type='bus'; fmt='inst'},
    @{name='WB  inst';          col='wb_inst';    type='bus'; fmt='inst'}
)
$notes1 = @(
    "程序 instr_cover（26 条冻结指令全覆盖）｜时钟 100 MHz 名义（Tclk=10 ns）｜游标 = 五级同时有效拍",
    "该拍 5 个不同指令分别处于 IF/ID/EX/MEM/WB：取指与访存走独立 imem/dmem（哈佛），无结构冲突",
    "段间寄存器（IF/ID、ID/EX、EX/MEM、MEM/WB）在每拍沿锁存，五级并行推进"
)
$b1 = New-Panel -Data $cov -Start $s1 -End $e1 -Title '项1 · 五级流水线运行总览（连续 10 拍）' `
    -Sub "instr_cover ｜ 游标拍 c=$s1 ｜ $stamp" -Rows $rows1 -Cursor $s1 -CursorLabel "5 stages" `
    -HiCycles @($s1) -Notes $notes1
Save-Item $b1 "1_pipe_overview" ($tbLog + @('', "复现: $cmdLine", "采样: wave_cover.csv / wave_cover.vcd"))

# ================= 项 2：数据前递与前递优先级 =================
$haz = Import-WaveCsv (Join-Path $waveDir 'wave_hazard.csv')
$s2 = $marks['2'] - 1; $e2 = $marks['2'] + 2
$rows2 = @(
    @{name='fwd_a_sel';         col='fwd_a';      type='bus'; fmt='fwd'},
    @{name='fwd_b_sel';         col='fwd_b';      type='bus'; fmt='fwd'},
    @{name='idex_rs1_data';     col='idex_rs1';   type='bus'; fmt='hex'},
    @{name='exmem_alu_result';  col='exmem_alu';  type='bus'; fmt='hex'},
    @{name='wb_data';           col='wb_data';    type='bus'; fmt='hex'},
    @{name='alu_a (rs1_fwd)';   col='alu_a';      type='bus'; fmt='hex'},
    @{name='alu_b (rs2_fwd)';   col='alu_b';      type='bus'; fmt='hex'},
    @{name='alu_out';           col='alu_out';    type='bus'; fmt='hex'}
)
$notes2a = @(
    "hazard_cover 场景1：addi x1,x0,1 → addi x2,x1,1 → add x3,x2,x1（背靠背 RAW）",
    "游标拍：add x3 在 EX；x2 生产者(EX/MEM)与 x1 生产者(MEM/WB)同时可前递，两条通路并存",
    "alu_a=2（EX/MEM→x2）、alu_b=1（MEM/WB→x1）→ alu_out=3，验证前递通路有效"
)
$p2a = New-Panel -Data $haz -Start $s2 -End $e2 -Title '项2a · 数据前递（两条前递通路并存）' `
    -Sub "hazard_cover 场景1 ｜ 游标拍 c=$($marks['2']) ｜ $stamp" -Rows $rows2 -Cursor $marks['2'] -CursorLabel "EX/MEM + MEM/WB" `
    -HiCycles @($marks['2']) -Notes $notes2a

$pri = Import-WaveCsv (Join-Path $waveDir 'wave_priority.csv')
$s2b = $marks['2b'] - 1; $e2b = $marks['2b'] + 2
$rows2b = @(
    @{name='fwd_a_sel';         col='fwd_a';      type='bus'; fmt='fwd'},
    @{name='exmem_alu_result';  col='exmem_alu';  type='bus'; fmt='hex'},
    @{name='wb_data (MEM/WB)';  col='wb_data';    type='bus'; fmt='hex'},
    @{name='alu_a (rs1_fwd)';   col='alu_a';      type='bus'; fmt='hex'},
    @{name='alu_out';           col='alu_out';    type='bus'; fmt='hex'}
)
$notes2b = @(
    "fwd_priority 场景：addi x11,x0,1 → addi x11,x0,2 → add x12,x11,x0（同址连写，双命中）",
    "游标拍：I2 在 EX/MEM（x11=2）、I1 在 MEM/WB（x11=1）同时命中 rs1；fwd_a_sel=01 取 EX/MEM",
    "alu_a=2（取较新值 2，而非 MEM/WB 的 1）→ x12=2，验证 EX/MEM 优先于 MEM/WB"
)
$p2b = New-Panel -Data $pri -Start $s2b -End $e2b -Title '项2b · 前递优先级（EX/MEM 优先于 MEM/WB）' `
    -Sub "fwd_priority ｜ 游标拍 c=$($marks['2b']) ｜ $stamp" -Rows $rows2b -Cursor $marks['2b'] -CursorLabel "dual-hit -> 01" `
    -HiCycles @($marks['2b']) -Notes $notes2b

$b2 = Merge-Vertical @($p2a, $p2b) 12
Save-Item $b2 "2_fwd_priority" ($tbLog + @('', "复现: $cmdLine", "采样: wave_hazard.csv（2a）/ wave_priority.csv（2b）"))

# ================= 项 3：load-use 冻结 1 拍 =================
$s3 = $marks['3'] - 2; $e3 = $marks['3'] + 3
$rows3 = @(
    @{name='stall';             col='stall';      type='bit'},
    @{name='pc';                col='pc';         type='bus'; fmt='pc'},
    @{name='id_inst (消费者)';  col='id_inst';    type='bus'; fmt='inst'},
    @{name='ex_inst';           col='ex_inst';    type='bus'; fmt='inst'},
    @{name='mem_inst';          col='mem_inst';   type='bus'; fmt='inst'},
    @{name='wb_inst';           col='wb_inst';    type='bus'; fmt='inst'}
)
$notes3 = @(
    "hazard_cover 场景2：lw x4,0(x0) → addi x5,x4,1（load-use RAW）",
    "stall 高电平仅 1 拍：该拍 pc 冻结（不推进）、id_inst 保持、EX 灌气泡；下一拍 pc 恢复推进",
    "数据在 MEM 后才可用；冻结 1 拍后 MEM/WB 前递供数 → x5=4（代价恰 1 拍）"
)
$b3 = New-Panel -Data $haz -Start $s3 -End $e3 -Title '项3 · load-use 冻结 1 拍' `
    -Sub "hazard_cover 场景2 ｜ 游标拍 c=$($marks['3']) ｜ $stamp" -Rows $rows3 -Cursor $marks['3'] -CursorLabel "stall=1 (1 cycle)" `
    -HiCycles @($marks['3']) -Notes $notes3
Save-Item $b3 "3_loaduse_stall" ($tbLog + @('', "复现: $cmdLine", "采样: wave_hazard.csv"))

# ================= 项 4：分支预测不跳 + 冲刷 2 拍 =================
$s4 = $marks['4'] - 1; $e4 = $marks['4'] + 3
$rows4 = @(
    @{name='br_taken';          col='br_taken';   type='bit'},
    @{name='br_target';         col='br_target';  type='bus'; fmt='pc'},
    @{name='pc';                col='pc';         type='bus'; fmt='pc'},
    @{name='if_inst (IF)';      col='if_inst';    type='bus'; fmt='inst'},
    @{name='id_inst (ID)';      col='id_inst';    type='bus'; fmt='inst'},
    @{name='ex_inst (EX)';      col='ex_inst';    type='bus'; fmt='inst'}
)
$notes4 = @(
    "hazard_cover 场景4：beq x6,x4,ok_path（3==3 taken）→ 默认预测不跳，taken 时冲刷错误路径 2 条",
    "游标拍 br_taken=1（分支在 EX）；下一拍 IF/ID 置 NOP(0x00000013)、ID/EX 清气泡、pc 跳至 br_target=0x34",
    "被冲刷错误路径指令 addi x9,x0,99 / 下一取指未提交 → 末态 x9=7；重定向共损失 2 拍"
)
$b4 = New-Panel -Data $haz -Start $s4 -End $e4 -Title '项4 · 分支预测不跳 + 冲刷 2 拍' `
    -Sub "hazard_cover 场景4 ｜ 游标拍 c=$($marks['4']) ｜ $stamp" -Rows $rows4 -Cursor $marks['4'] -CursorLabel "br_taken=1" `
    -HiCycles @($marks['4'], ($marks['4'] + 1)) -Notes $notes4
Save-Item $b4 "4_branch_flush" ($tbLog + @('', "复现: $cmdLine", "采样: wave_hazard.csv"))

Write-Host ''
Write-Host ("波形 PNG 输出目录: $outDir")
