<#
=============================================================================
 run_perf.ps1 — T33 性能批量测量运行器（pipeline/doc/perf_analysis.md v2.0 §5）
   八档程序逐档编译运行 tb_perf.v（xvlog -d PERF_*），解析
   PERF_SUMMARY 行 → 汇总 pipeline/src/scripts/out/perf_summary.csv
   档位：5 主档（test0/test1/sort/cover/hazard）+ 3 规模档（loop8/loop32/loop128）
   指标口径见 pipeline/doc/perf_analysis.md v2.0 §2（三窗口 + 恒等式；
   IC 包含末尾停机自旋，IC_useful=IC-1）
   用法：
     powershell -File pipeline/src/scripts/run_perf.ps1       # 跑全部 8 档
     powershell -File pipeline/src/scripts/run_perf.ps1 -Case sort,hazard
     powershell -File pipeline/src/scripts/run_perf.ps1 -Case loop   # 3 档规模档
   环境：默认 C:\Xilinx\Vivado\2019.2；可用 $env:XVIVADO_ROOT 覆盖
=============================================================================
#>
param(
    [string]$Case = ''     # 过滤：逗号分隔程序名子串（test0/test1/sort/cover/hazard/loop8/loop32/loop128）
)

$ErrorActionPreference = 'Stop'
$root    = Split-Path -Parent $PSScriptRoot              # src/
$vivado  = if ($env:XVIVADO_ROOT) { $env:XVIVADO_ROOT } else { 'C:\Xilinx\Vivado\2019.2' }
$settings = Join-Path $vivado 'settings64.bat'
if (-not (Test-Path $settings)) { Write-Error "找不到 $settings"; exit 1 }

# ---- 八档程序表：名称 / 镜像 / 编译开关 ----
$progs = @(
    @{ name = 'test0';   hex = 'test0_rom.hex';           def = '' },
    @{ name = 'test1';   hex = 'test1_rom.hex';           def = 'PERF_TEST1' },
    @{ name = 'sort';    hex = 'test_sort_rom.hex';       def = 'PERF_SORT' },
    @{ name = 'cover';   hex = 'instr_cover_rom.hex';     def = 'PERF_COVER' },
    @{ name = 'hazard';  hex = 'hazard_cover_rom.hex';    def = 'PERF_HAZARD' },
    @{ name = 'loop8';   hex = 'loop_heavy_8_rom.hex';    def = 'PERF_LOOP8' },
    @{ name = 'loop32';  hex = 'loop_heavy_32_rom.hex';   def = 'PERF_LOOP32' },
    @{ name = 'loop128'; hex = 'loop_heavy_128_rom.hex';  def = 'PERF_LOOP128' }
)
if ($Case) {
    $keys = $Case -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    $progs = @($progs | Where-Object {
        $hit = $false
        foreach ($k in $keys) { if ($_.name -like "*$k*") { $hit = $true; break } }
        $hit
    })
}
if ($progs.Count -eq 0) { Write-Host '[提示] 没有匹配的程序档，退出'; exit 0 }

# ---- 工具链文件 ----
$rtlFiles = @(Get-ChildItem -Path (Join-Path $root 'rtl') -Filter '*.v' -File | Select-Object -ExpandProperty FullName)
$tbPerf   = Join-Path $root (Join-Path 'test' 'tb_perf.v')
$testDir  = Join-Path $root 'test'
$outTop   = Join-Path $PSScriptRoot 'out'
New-Item -ItemType Directory -Path $outTop -Force | Out-Null
$summary  = Join-Path $outTop 'perf_summary.csv'

# ---- 逐档运行 ----
$rows = @()
foreach ($p in $progs) {
    $dir = Join-Path $outTop (Join-Path 'perf' $p.name)
    if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
    New-Item -ItemType Directory -Path $dir | Out-Null

    # 镜像拷入仿真 cwd（tb $readmemh 相对 cwd）
    Copy-Item -Path (Join-Path $testDir $p.hex) -Destination $dir -Force

    $bat = Join-Path $dir 'run.bat'
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('@echo off')
    [void]$sb.AppendLine("call `"$settings`" >nul 2>&1")
    [void]$sb.AppendLine("cd /d `"$dir`"")
    $all = @($rtlFiles) + @($tbPerf)
    $a = ($all | ForEach-Object { "`"$_`"" }) -join ' '
    if ($p.def) { $defOpt = "-d $($p.def)" } else { $defOpt = '' }
    [void]$sb.AppendLine("call xvlog $defOpt -i `"$root`" $a")
    [void]$sb.AppendLine('if errorlevel 1 ( echo [COMPILE_FAIL] & exit /b 2 )')
    [void]$sb.AppendLine('call xelab tb_perf -s tb_perf')
    [void]$sb.AppendLine('if errorlevel 1 ( echo [XELAB_FAIL] & exit /b 3 )')
    [void]$sb.AppendLine("call xsim tb_perf -runall -log `"$(Join-Path $dir 'tb.log')`"")
    [void]$sb.AppendLine('if errorlevel 1 ( echo [XSIM_FAIL] & exit /b 4 )')
    [void]$sb.AppendLine('exit /b 0')
    Set-Content -Path $bat -Value $sb.ToString() -Encoding ASCII

    Write-Host ("[运行] {0,-8} ({1})" -f $p.name, $p.hex)
    & cmd.exe /c "`"$bat`" > `"$(Join-Path $dir 'run_all.log')`" 2>&1"
    if ($LASTEXITCODE -ne 0) { Write-Host ("  [异常] 退出码 {0}" -f $LASTEXITCODE); exit 1 }

    $log = Join-Path $dir 'tb.log'
    $line = Select-String -Path $log -Pattern 'PERF_SUMMARY: name=(\S+) ic=(\d+) f=(\d+) h=(\d+) c_total=(\d+) c_steady=(\d+) c_fixed=(\d+) l=(\d+) t=(\d+) ident_a=(\d+) ident_b=(\d+) residual=(-?\d+) ok=(\d+)'
    if (-not $line) { Write-Host '  [异常] 未找到 PERF_SUMMARY 行'; exit 1 }
    $m = $line.Matches[0]
    $r = @{ name = $m.Groups[1].Value; ic = [int]$m.Groups[2].Value; f = [int]$m.Groups[3].Value
            h = [int]$m.Groups[4].Value; c = [int]$m.Groups[5].Value; cs = [int]$m.Groups[6].Value
            cf = [int]$m.Groups[7].Value; l = [int]$m.Groups[8].Value; t = [int]$m.Groups[9].Value
            ident_a = [int]$m.Groups[10].Value; ident_b = [int]$m.Groups[11].Value
            residual = [int]$m.Groups[12].Value; ok = [int]$m.Groups[13].Value }
    $r.allpass = [bool](Select-String -Path $log -Pattern '=== ALL PASS ===' -Quiet)
    $rows += $r
    Write-Host ("  ic={0}  c={1}  cs={2}  f={3}  l={4}  t={5}  A/B={6}/{7}  allpass={8}" -f
                $r.ic, $r.c, $r.cs, $r.f, $r.l, $r.t, $r.ident_a, $r.ident_b, $r.allpass)
}

# ---- 汇总 CSV + 指标表 ----
$lines = @('prog,IC,F,h,C_total,C_steady,C_fixed,L_loaduse,T_redirect,CPI_total,CPI_steady,IPC_steady,MIPS_100M,CPUtime_100M_ns,ident_a,ident_b,residual,correctness')
Write-Host "`n== PERF 汇总 =="
$allOk = $true
foreach ($r in $rows) {
    $useful = $r.ic - 1
    $cpi  = [math]::Round($r.c / $r.ic, 3)
    $cpiS = [math]::Round($r.cs / $useful, 3)
    $ipc  = [math]::Round($useful / $r.cs, 3)
    $mips = [math]::Round(100.0 * $useful / $r.c, 3)
    $time = $r.c * 10
    $lines += ('{0},{1},{2},{3},{4},{5},{6},{7},{8},{9},{10},{11},{12},{13},{14},{15},{16},{17}' -f
               $r.name, $r.ic, $r.f, $r.h, $r.c, $r.cs, $r.cf, $r.l, $r.t,
               $cpi, $cpiS, $ipc, $mips, $time, $r.ident_a, $r.ident_b, $r.residual, $r.ok)
    Write-Host ("  {0,-8} ic={1,-5} c={2,-5} CPI={3,-7} CPI_s={4,-7} IPC_s={5,-7} MIPS={6,-7} A/B={7}/{8} allpass={9}" -f
                $r.name, $r.ic, $r.c, $cpi, $cpiS, $ipc, $mips, $r.ident_a, $r.ident_b, $r.allpass)
    if ($r.ident_a -ne 1 -or $r.ident_b -ne 1 -or $r.residual -ne 0 -or $r.ok -ne 1 -or -not $r.allpass) { $allOk = $false }
}
Set-Content -Path $summary -Value $lines -Encoding ASCII
Write-Host ''
Write-Host ("汇总: $summary")
if ($allOk) { Write-Host '== PERF ALL PASS =='; exit 0 }
Write-Host '== PERF FAIL =='; exit 1
