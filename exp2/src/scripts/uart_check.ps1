<#
=============================================================================
 uart_check.ps1 — 下板终端自动化验收取证（U32）
   用法：
     powershell -File uart_check.ps1                  # COM 自动探测或默认 COM8
     powershell -File uart_check.ps1 -Port COM3
     powershell -File uart_check.ps1 -Port COM3 -Baud 115200 -TimeoutSec 20
   动作（115200-8-N-1）：
     1) 复位提示后自动收 banner（期望 23 字节 "EES-338 RV32I UART OK\r\n"）
     2) 发送 AB（间隔 100ms，模拟逐字回显）并核对回显字节
     3) 证据日志写入 scripts/out/uart_check_*.log；控制台 PASS/FAIL 汇总
   注：CPU 上电即自发 banner（无需按键）；如需验证"按键复位重跑"，
       请手动按 P15 后再跑一次本脚本，两次均 PASS 即复位重跑一致。
=============================================================================
#>
param(
    [string]$Port = '',
    [int]$Baud = 115200,
    [int]$TimeoutSec = 20
)

$ErrorActionPreference = 'Stop'
$outDir = Join-Path $PSScriptRoot 'out'
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$logPath = Join-Path $outDir ("uart_check_" + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.log')
$log = New-Object System.Collections.Generic.List[string]
function Log([string]$m) { Write-Host $m; $log.Add($m) }

# ---- 端口：默认 COM8；无参且 COM8 不存在时自动挑选 CP210x ----
if (-not $Port) {
    $Port = 'COM8'
    $ports = [System.IO.Ports.SerialPort]::GetPortNames()
    if ($ports -notcontains $Port) { $Port = ($ports | Select-Object -First 1) }
    if (-not $Port) { Log 'ERROR: 未找到 COM 口'; exit 1 }
}

Log ("[端口] {0} @ {1}-8-N-1，超时 {2}s" -f $Port, $Baud, $TimeoutSec)
$sp = New-Object System.IO.Ports.SerialPort($Port, $Baud, [System.IO.Ports.Parity]::None, 8, [System.IO.Ports.StopBits]::One)
$sp.ReadTimeout = 1000
$sp.Open()
Start-Sleep -Milliseconds 300

# ---- 期望 banner（23 字节，与 console.S/手册核验一致）----
$expBanner = [byte[]](0x45,0x45,0x53,0x2D,0x33,0x33,0x38,0x20,0x52,0x56,0x33,0x32,
                     0x49,0x20,0x55,0x41,0x52,0x54,0x20,0x4F,0x4B,0x0D,0x0A)
$rx = New-Object System.Collections.Generic.List[byte]
$sw = [Diagnostics.Stopwatch]::StartNew()

# ---- 1) 收 banner：匹配前 23 字节或超时 ----
function Try-Match($buf, [byte[]]$pat) {
    if ($buf.Count -lt $pat.Length) { return $false }
    for ($i = 0; $i -lt $pat.Length; $i++) { if ($buf[$i] -ne $pat[$i]) { return $false } }
    return $true
}
$bannerOk = $false
while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec -and -not $bannerOk) {
    try { $b = $sp.ReadByte() } catch { Start-Sleep -Milliseconds 50; continue }
    $rx.Add([byte]$b)
    if ($rx.Count -gt 256) { $rx.RemoveAt(0) }   # 只留窗口
    $bannerOk = Try-Match $rx $expBanner
}
if ($bannerOk) {
    $txt = [Text.Encoding]::ASCII.GetString($rx.ToArray(), 0, $expBanner.Length)
    Log ("PASS: banner 23B = '" + $txt.Replace("`r",'\r').Replace("`n",'\n') + "'")
} else {
    Log ('FAIL: 超时未收到完整 banner；已收 ' + $rx.Count + 'B: ' +
         (($rx.ToArray() | ForEach-Object { $_.ToString('X2') }) -join ' '))
}

# ---- 2) 回显：发 A、B（间隔 100ms）并核对 ----
$sp.DiscardInBuffer()
$echoOk = $true
foreach ($ch in [byte[]](0x41, 0x42)) {
    $sp.Write([byte[]]$ch, 0, 1)
    $got = -1
    $t2 = [Diagnostics.Stopwatch]::StartNew()
    while ($t2.Elapsed.TotalSeconds -lt 5 -and $got -lt 0) {
        try { $got = $sp.ReadByte() } catch { Start-Sleep -Milliseconds 30 }
    }
    if ($got -ne $ch) { $echoOk = $false; Log ('FAIL: 回显期望 0x{0:X2}，实际 0x{1:X2}' -f $ch, $got) }
    Start-Sleep -Milliseconds 100
}
if ($echoOk) { Log 'PASS: 回显 AB 往返正确' }

$sp.Close()
Log ''
if ($bannerOk -and $echoOk) { Log '== UART CHECK ALL PASS ==' }
else { Log '== UART CHECK FAIL ==' }
Set-Content -Path $logPath -Value ($log -join "`r`n") -Encoding UTF8
Log ('证据日志: ' + $logPath)
if ($bannerOk -and $echoOk) { exit 0 } else { exit 1 }
