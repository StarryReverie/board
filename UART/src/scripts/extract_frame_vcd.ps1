# extract_frame_vcd.ps1 - build a one-frame VCD + bit-level ASCII timing from the
# pin-transition log written by UART/src/test/tb_wave_868.v (times in ns).
# ASCII-only on purpose: Windows PowerShell 5.1 reads BOM-less files as ANSI.
# in : build/wave868/wave_868_events.txt   (xsim scratch, produced by run_wave868.ps1)
# out: UART/doc/wave/uart_frame_868.vcd  (one 8N1 frame, open with Vivado/xsim)
#      UART/doc/wave/uart_frame_868.txt  (bit-level ASCII timing, paste into report)
param(
    [string]$Src = '',
    [string]$OutDir = ''
)
$ErrorActionPreference = 'Stop'
$scriptsDir = Split-Path -Parent $MyInvocation.MyCommand.Path   # UART/src/scripts
$srcDir     = Split-Path -Parent $scriptsDir                    # UART/src
$root       = Split-Path -Parent (Split-Path -Parent $srcDir)   # repo root
if (-not $Src)    { $Src    = Join-Path $root 'build\wave868\wave_868_events.txt' }
if (-not $OutDir) { $OutDir = Join-Path $root 'UART\doc\wave' }
if (-not (Test-Path $Src)) { throw "no event log: $Src" }
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

$bitNs = 8680L
$tx = New-Object System.Collections.Generic.List[object]
$rx = New-Object System.Collections.Generic.List[object]
foreach ($ln in [IO.File]::ReadAllLines($Src)) {
    if ($ln.Length -eq 0 -or $ln[0] -eq '#') { continue }
    $p = $ln -split '\s+'
    if ($p.Count -lt 3) { continue }
    $rec = [pscustomobject]@{ t = [long]$p[0]; v = [int]$p[2] }
    if ($p[1] -eq 'tx') { [void]$tx.Add($rec) } elseif ($p[1] -eq 'rx') { [void]$rx.Add($rec) }
}
Write-Host ("events: tx={0} rx={1}" -f $tx.Count, $rx.Count)

# ---- pick the first real frame: a falling edge preceded by an idle-high period,
#      whose stop bit (10 bits later) is high ----
$frameStart = -1L
for ($k = 0; $k -lt $tx.Count; $k++) {
    if ($tx[$k].v -ne 0) { continue }
    if ($k -gt 0 -and ($tx[$k].t - $tx[$k - 1].t) -lt $bitNs) { continue }   # 不是空闲后的首个起始位
    $stopT = [long]($tx[$k].t + $bitNs * 9 + [long]($bitNs / 2))
    $v = 1
    foreach ($e in $tx) { if ($e.t -gt $stopT) { break }; $v = $e.v }
    if ($v -eq 1) { $frameStart = $tx[$k].t; break }
}
if ($frameStart -lt 0) { throw 'no valid 10-bit TX frame found in event log' }
$frameEnd = [long]($frameStart + $bitNs * 10)

# ---- decode the frame by sampling bit centres ----
$samples = @()
for ($i = 0; $i -lt 10; $i++) {
    $tc = [long]($frameStart + $bitNs * $i + [long]($bitNs / 2))
    $v = 1
    foreach ($e in $tx) { if ($e.t -gt $tc) { break }; $v = $e.v }
    $samples += $v
}
$dataBits = @($samples[1..8])
for ($i = 0; $i -lt 8; $i++) { if ($dataBits[$i] -eq 1) { $frameByte += [int][math]::Pow(2, $i) } }
Write-Host ("frame: start={0} data=0x{1:X2} stop={2}  ({3}..{4} ns, {5} ns = {6} bits)" -f `
    $samples[0], $frameByte, $samples[9], $frameStart, $frameEnd, ($frameEnd - $frameStart), (($frameEnd - $frameStart) / $bitNs))

# ---- window: 0.5 bit before start .. 1.5 bit after stop ----
$t0 = [long]([math]::Max(0, $frameStart - [long]($bitNs / 2)))
$t1 = [long]($frameEnd + [long]($bitNs * 3 / 2))

# ---- write VCD (timescale 1ns, ids: ! = uart_tx_pin, " = uart_rx_pin) ----
$outVcd = Join-Path $OutDir 'uart_frame_868.vcd'
$sw = New-Object IO.StreamWriter($outVcd, $false, (New-Object Text.UTF8Encoding($false)))
$sw.NewLine = "`n"
$sw.WriteLine('$date');       $sw.WriteLine('   build/tb_wave_868.v + build/extract_frame_vcd.ps1'); $sw.WriteLine('$end')
$sw.WriteLine('$version');    $sw.WriteLine('   xsim 2019.2 (pin transitions recorded by the testbench)'); $sw.WriteLine('$end')
$sw.WriteLine('$timescale');  $sw.WriteLine('   1ns'); $sw.WriteLine('$end')
$sw.WriteLine('$scope module uart_frame_868 $end')
$sw.WriteLine('$var wire 1 ! uart_tx_pin $end')
$sw.WriteLine('$var wire 1 " uart_rx_pin $end')
$sw.WriteLine('$upscope $end')
$sw.WriteLine('$enddefinitions $end')

# initial values at window start = last value before t0 (TX idle high, RX idle high)
$initTx = 1; $initRx = 1
foreach ($e in $tx) { if ($e.t -ge $t0) { break }; $initTx = $e.v }
foreach ($e in $rx) { if ($e.t -ge $t0) { break }; $initRx = $e.v }
$sw.WriteLine('#0')
$sw.WriteLine(('{0}!' -f $initTx))
$sw.WriteLine(('{0}"' -f $initRx))

$all = New-Object System.Collections.Generic.List[object]
foreach ($e in $tx) { if ($e.t -ge $t0 -and $e.t -le $t1) { [void]$all.Add([pscustomobject]@{ t = $e.t; line = ('{0}!' -f $e.v) }) } }
foreach ($e in $rx) { if ($e.t -ge $t0 -and $e.t -le $t1) { [void]$all.Add([pscustomobject]@{ t = $e.t; line = ('{0}"' -f $e.v) }) } }
$lastT = -1L
foreach ($e in ($all | Sort-Object t)) {
    if ($e.t -ne $lastT) { $sw.WriteLine('#' + ($e.t - $t0)); $lastT = $e.t }
    $sw.WriteLine($e.line)
}
$sw.Close()

# ---- ASCII timing ----
$outTxt = Join-Path $OutDir 'uart_frame_868.txt'
$tw = New-Object IO.StreamWriter($outTxt, $false, (New-Object Text.UTF8Encoding($false)))
$tw.NewLine = "`n"
$tw.WriteLine('uart_ip_top 8N1 frame timing (xsim, CLKS_PER_BIT=868, 100 MHz)')
$tw.WriteLine('=================================================================')
$tw.WriteLine(('bit width      : 868 clk = {0:N0} ns = {1:N3} us' -f $bitNs, ($bitNs / 1000)))
$tw.WriteLine(('frame (10 bit) : {0:N0} ns = {1:N3} us' -f ($bitNs * 10), (($bitNs * 10) / 1000)))
$tw.WriteLine(('baud error     : {0:N4} %  ((100e6/868 - 115200)/115200)' -f (((100000000.0 / 868) - 115200.0) / 115200.0 * 100.0)))
$tw.WriteLine('')
$tw.WriteLine(('TX start-bit falling edge at t = {0} ns' -f $frameStart))
$tw.WriteLine(('sampled frame  : start={0}  data(LSB first)={1} = 0x{2:X2}  stop={3}' -f $samples[0], ($dataBits -join ''), $frameByte, $samples[9]))
$tw.WriteLine('')
$tw.WriteLine('bit index :  0    1    2    3    4    5    6    7    8    9')
$tw.WriteLine('meaning   : str  d0   d1   d2   d3   d4   d5   d6   d7   stp')
$tw.WriteLine(('level     :  {0}' -f (($samples | ForEach-Object { ' ' + $_ + '  ' }) -join '')))
$tw.WriteLine('')
$tw.WriteLine('bit-period strip (each cell = 8.68 us):')
$strip = ($samples | ForEach-Object { if ($_ -eq 1) { '____' } else { '----' } }) -join ''
$tw.WriteLine('TX pin   idle' + $strip)
$tw.WriteLine('              str ' + (($dataBits | ForEach-Object { if ($_ -eq 1) { ' 1  ' } else { ' 0  ' } }) -join '') + ' stp')
$tw.WriteLine('')
$tw.WriteLine('TX pin transitions inside the frame (ns, relative to start edge):')
$prevT = $frameStart
foreach ($e in $tx) {
    if ($e.t -lt $frameStart -or $e.t -gt $frameEnd) { continue }
    $tw.WriteLine(('  +{0,7} ns  -> {1}   (bit {2}, {3:N1} bit periods)' -f ($e.t - $frameStart), $e.v, [math]::Floor(($e.t - $frameStart) / $bitNs), (($e.t - $frameStart) / $bitNs)))
}
$tw.Close()

Write-Host ("VCD  -> {0}  ({1:N0} bytes)" -f $outVcd, (Get-Item $outVcd).Length)
Write-Host ("TXT  -> {0}" -f $outTxt)
