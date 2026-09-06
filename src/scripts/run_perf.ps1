<#
=============================================================================
 run_perf.ps1 — T33 性能批量测量运行器（doc/perf_analysis.md §5.3）
   五档程序逐档编译运行 tb_perf.v（xvlog -d PERF_*），解析
   PERF_SUMMARY 行 → 汇总 src/scripts/out/perf_summary.csv
   指标口径见 doc/perf_analysis.md §3（C==IC+(F-1)+L+2T 恒等式由 TB 断言）
   用法：
     powershell -File src/scripts/run_perf.ps1       # 跑全部 5 档
     powershell -File src/scripts/run_perf.ps1 -Case sort,hazard
   环境：默认 C:\Xilinx\Vivado\2019.2；可用 $env:XVIVADO_ROOT 覆盖
=============================================================================
#>
param(
    [string]$Case = ''     # 过滤：逗号分隔程序名子串（test0/test1/sort/cover/hazard）
)

$ErrorActionPreference = 'Stop'
$root    = Split-Path -Parent $PSScriptRoot              # src/
$vivado  = if ($env:XVIVADO_ROOT) { $env:XVIVADO_ROOT } else { 'C:\Xilinx\Vivado\2019.2' }
$settings = Join-Path $vivado 'settings64.bat'
if (-not (Test-Path $settings)) { Write-Error "找不到 $settings"; exit 1 }

# ---- 五档程序表：名称 / 镜像 / 编译开关 / 说明 ----
$progs = @(
    @{ name = 'test0';  hex = 'test0_rom.hex';        def = '' },
    @{ name = 'test1';  hex = 'test1_rom.hex';        def = 'PERF_TEST1' },
    @{ name = 'sort';   hex = 'test_sort_rom.hex';    def = 'PERF_SORT' },
    @{ name = 'cover';  hex = 'instr_cover_rom.hex';  def = 'PERF_COVER' },
    @{ name = 'hazard'; hex = 'hazard_cover_rom.hex'; def = 'PERF_HAZARD' }
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
    $line = Select-String -Path $log -Pattern 'PERF_SUMMARY: name=(\S+) ic=(\S+) f=(\d+) c=(\d+) l=(\d+) t=(\d+) ident=(\d+) ok=(\d+)'
    if (-not $line) { Write-Host '  [异常] 未找到 PERF_SUMMARY 行'; exit 1 }
    $m = $line.Matches[0]
    $r = @{ name = $m.Groups[1].Value; ic = $m.Groups[2].Value; f = [int]$m.Groups[3].Value
            c  = [int]$m.Groups[4].Value; l = [int]$m.Groups[5].Value; t = [int]$m.Groups[6].Value
            ident = [int]$m.Groups[7].Value; ok = [int]$m.Groups[8].Value }
    $r.allpass = [bool](Select-String -Path $log -Pattern '=== ALL PASS ===' -Quiet)
    $rows += $r
    Write-Host ("  ic={0}  c={1}  f={2}  l={3}  t={4}  ident={5}  allpass={6}" -f
                $r.ic, $r.c, $r.f, $r.l, $r.t, $r.ident, $r.allpass)
}

# ---- 汇总 CSV + 指标表 ----
$lines = @('prog,ic,f,c,l,t,cpi,ipc,cpi_steady,ident,allpass')
Write-Host "`n== PERF 汇总 =="
$allOk = $true
foreach ($r in $rows) {
    $cpi  = if ($r.ic -match '^\d+$' -and $r.ic -ne 0) { [math]::Round($r.c / $r.ic, 3) } else { '' }
    $ipc  = if ($cpi -ne '') { [math]::Round($r.ic / $r.c, 3) } else { '' }
    $cs   = if ($cpi -ne '') { [math]::Round(($r.c - ($r.f - 1)) / $r.ic, 3) } else { '' }
    $lines += ('{0},{1},{2},{3},{4},{5},{6},{7},{8},{9},{10}' -f
               $r.name, $r.ic, $r.f, $r.c, $r.l, $r.t, $cpi, $ipc, $cs, $r.ident, $r.allpass)
    Write-Host ("  {0,-8} ic={1,-5} c={2,-5} CPI={3,-7} IPC={4,-7} CPI_s={5,-7} ident={6} allpass={7}" -f
                $r.name, $r.ic, $r.c, $cpi, $ipc, $cs, $r.ident, $r.allpass)
    if ($r.ident -ne 1 -or -not $r.allpass) { $allOk = $false }
}
Set-Content -Path $summary -Value $lines -Encoding ASCII
Write-Host ''
Write-Host ("汇总: $summary")
if ($allOk) { Write-Host '== PERF ALL PASS =='; exit 0 }
Write-Host '== PERF FAIL =='; exit 1
